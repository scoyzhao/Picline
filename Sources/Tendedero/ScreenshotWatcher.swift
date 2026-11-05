import Foundation
import CoreServices

/// Watches the folder macOS saves screenshots to and reports new ones.
/// Tendedero never takes screenshots itself: you keep your usual shortcut
/// (or CleanShot, or anything else) and the line just picks them up.
@MainActor
final class ScreenshotWatcher {
    let folder: URL
    /// On the Desktop we only accept real screenshots, tagged by macOS with an
    /// extended attribute. In a dedicated folder, any image counts.
    private let onlyTaggedScreenshots: Bool
    /// Screen recordings carry no tag, so they are only picked up in
    /// Tendedero's own folder, where nothing else is saved.
    private let acceptsRecordings: Bool
    private let recursive: Bool
    private var known: [URL: CaptureFileVersion]?
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?
    private var generation = UUID()
    private var listing = false
    private var missed = false
    private var stopped = true
    private let onNew: (URL) -> Void
    private let onChange: () -> Void

    static let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")

    /// Watches the folder macOS saves screenshots to, or a given folder.
    /// `anyImage` takes every new image even on the Desktop, for a folder
    /// the user chose to watch.
    init(folder: URL? = nil, anyImage: Bool = false, recursive: Bool = false, onNew: @escaping (URL) -> Void, onChange: @escaping () -> Void) {
        self.recursive = recursive
        self.onNew = onNew
        self.onChange = onChange
        self.folder = folder ?? Self.screenshotFolder()
        onlyTaggedScreenshots = !anyImage
            && self.folder.standardizedFileURL.path == Self.desktop.standardizedFileURL.path
        acceptsRecordings = self.folder.standardizedFileURL.path == Inbox.folder.standardizedFileURL.path
    }

    static func screenshotFolder() -> URL {
        let fm = FileManager.default
        // Read fresh through cfprefsd: inbox mode changes this value at runtime.
        CFPreferencesAppSynchronize("com.apple.screencapture" as CFString)
        // macOS 27 keeps it in "location-screenshot"; earlier versions in "location".
        let domain = "com.apple.screencapture" as CFString
        let raw = (CFPreferencesCopyAppValue("location-screenshot" as CFString, domain) as? String)
            ?? (CFPreferencesCopyAppValue("location" as CFString, domain) as? String)
        if let raw, !raw.isEmpty {
            let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue { return url }
        }
        return fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    /// Anything created after the app launched counts as new, even if it
    /// landed before the watcher was ready (macOS may be asking for Desktop
    /// access at that moment).
    private let launchDate = Date()

    /// Directory access can wait on a macOS consent prompt, so open it away
    /// from the main thread. A generation prevents a stopped scan or start
    /// from publishing into a later run of this watcher.
    func start() {
        guard stopped else { return }
        stopped = false
        let run = UUID()
        generation = run
        let path = folder.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fd = open(path, O_EVTONLY)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == run, !self.stopped else {
                    if fd >= 0 { close(fd) }
                    return
                }
                guard fd >= 0 else { return }
                close(fd)
                self.watch()
            }
        }
    }

    private func watch() {
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(nil, { _, info, _, _, _, _ in
            guard let info else { return }
            MainActor.assumeIsolated {
                Unmanaged<ScreenshotWatcher>.fromOpaque(info).takeUnretainedValue().scheduleScan()
            }
        }, &context, [folder.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.15, flags) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }
        self.stream = stream
        refresh()
    }

    func stop() {
        stopped = true
        generation = UUID()
        missed = false
        listing = false
        known = nil
        pending?.cancel()
        pending = nil
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    private func scheduleScan() {
        guard !stopped else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func refresh() {
        guard !stopped else { return }
        guard !listing else { missed = true; return }
        listing = true
        let run = generation
        let folder = folder
        let recursive = recursive
        let tagged = onlyTaggedScreenshots
        let recordings = acceptsRecordings
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snapshot = Self.listFolder(folder, recursive: recursive, tagged: tagged, recordings: recordings)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == run, !self.stopped else { return }
                self.listing = false
                if let snapshot {
                    let first = self.known == nil
                    let base = self.known ?? snapshot.filter { $0.value.created < self.launchDate }
                    for (url, version) in snapshot.sorted(by: { $0.value.created < $1.value.created })
                    where base[url] != version { self.onNew(url) }
                    self.known = snapshot
                    if !first { self.onChange() }
                }
                if self.missed { self.missed = false; self.refresh() }
            }
        }
    }

    nonisolated private static func listFolder(_ folder: URL, recursive: Bool, tagged: Bool, recordings: Bool) -> [URL: CaptureFileVersion]? {
        let fm = FileManager.default
        let urls: [URL]
        if recursive {
            var failed = false
            guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                 options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                 errorHandler: { _, _ in failed = true; return true }) else { return nil }
            urls = enumerator.allObjects.compactMap { $0 as? URL }
            // Keep the last good baseline on an access error, rather than
            // treating every file as new when access returns.
            if failed { return nil }
        } else {
            guard let children = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                             options: [.skipsHiddenFiles]) else { return nil }
            urls = children
        }
        var result: [URL: CaptureFileVersion] = [:]
        for url in urls {
            if isRecording(url) {
                guard recordings else { continue }
            } else {
                guard CaptureReceiver.imageExtensions.contains(url.pathExtension.lowercased()),
                      !tagged || isScreenCapture(url) else { continue }
            }
            if let version = CaptureFileVersion(at: url) { result[url] = version }
        }
        return result
    }

    nonisolated private static func isScreenCapture(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0
        }
    }
}
