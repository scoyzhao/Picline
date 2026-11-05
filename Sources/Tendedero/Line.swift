import AppKit
import AVFoundation
import Combine
import os

let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "local.captureline.preview", category: "line")

/// One screenshot hanging on the line.
struct Pegged: Identifiable, Equatable {
    let id = UUID()
    var url: URL
    var thumb: NSImage
    /// Every photo hangs a little crooked, like on a real line.
    let tilt = Double.random(in: -2.5...2.5)
    var falling = false
    /// Still flying in from where it was captured; the card waits hidden.
    var flying = false
    /// A screen recording rather than a screenshot.
    var isRecording: Bool { Tendedero.isRecording(url) }

    static func == (a: Pegged, b: Pegged) -> Bool {
        a.id == b.id && a.falling == b.falling && a.flying == b.flying && a.thumb === b.thumb
    }
}

/// The line itself: what hangs on it and what you can do with each item.
/// The files never move. The line is only a view onto them.
@MainActor
final class Line: ObservableObject {
    @Published private(set) var items: [Pegged] = []
    @Published private(set) var gust = 0
    @Published var copiedID: UUID?
    @Published var draggingID: UUID?
    @Published var pressedID: UUID?
    /// Which photos are picked out. One click picks one; shift click takes the
    /// run between the last one picked and this one; command click adds or
    /// removes a single photo.
    @Published private(set) var selection: Set<UUID> = []
    /// Where a shift click measures from: the last photo picked on its own.
    private var anchorID: UUID?
    /// A press inside a group, held back until the button comes up: dragging
    /// a picked-out photo has to carry the whole group, so the group can only
    /// close down into one after a press that did not turn into a drag.
    private var pendingCollapse: UUID?
    /// Whether the line has slid down into view.
    @Published var revealed = false

    /// Card frames in window coordinates, reported by the views. The panel
    /// uses them to only catch clicks over photos and let the rest through.
    var hitRects: [UUID: CGRect] = [:]

    var maxItems = 8 {
        didSet {
            if maxItems != oldValue, liveCount >= maxItems { onCapacityReached?(maxItems) }
        }
    }
    var onCapacityReached: ((Int) -> Void)?
    /// How many photos fit across the screen. With Keep on line set, the
    /// line can hold more, and the rest are reached by scrolling.
    var visibleCount = 8
    /// How far the line is scrolled towards older photos, in points; 0 shows
    /// the newest.
    @Published var scroll: CGFloat = 0

    /// Keep on line, from the menu bar: how many photos the line keeps, or
    /// nil for as many as fit across the screen.
    nonisolated static let keepChoices = [9, 25, 50, 100]
    nonisolated static var keepOnLine: Int? {
        get {
            let n = UserDefaults.standard.integer(forKey: "keepOnLine")
            return keepChoices.contains(n) ? n : nil
        }
        set { UserDefaults.standard.set(newValue ?? 0, forKey: "keepOnLine") }
    }


    var soundOn: Bool {
        get { !UserDefaults.standard.bool(forKey: "soundOff") }
        set { UserDefaults.standard.set(!newValue, forKey: "soundOff") }
    }

    var liveCount: Int { items.filter { !$0.falling }.count }
    var liveImageCount: Int { items.filter { !$0.falling && !$0.isRecording }.count }

    private let storeKey = "pegged"
    private let defaults: UserDefaults
    let imageOpener: ImageOpener

    init(defaults: UserDefaults = .standard, imageOpener: ImageOpener? = nil) {
        self.defaults = defaults
        self.imageOpener = imageOpener ?? ImageOpener(defaults: defaults)
        restore()
        scheduleGust()
    }

    // MARK: Choosing several

    /// The button went down on a photo. Shift takes the run from the anchor,
    /// command adds or removes one, a plain press picks this one out — unless
    /// it is already part of a group, which stays as it is for now.
    func press(_ id: UUID, extending: Bool, toggling: Bool) {
        if extending || toggling {
            pendingCollapse = nil
            select(id, extending: extending, toggling: toggling)
            return
        }
        if selection.contains(id), selection.count > 1 {
            pendingCollapse = id
            return
        }
        pendingCollapse = nil
        select(id)
    }

    /// The button came up without a drag: a press inside a group now closes
    /// down to that one photo, the way the Finder does it.
    func settle(_ id: UUID, dragged: Bool) {
        guard let pending = pendingCollapse else { return }
        pendingCollapse = nil
        if !dragged, pending == id { select(id) }
    }

    func select(_ id: UUID, extending: Bool = false, toggling: Bool = false) {
        let live = items.filter { !$0.falling }
        guard let index = live.firstIndex(where: { $0.id == id }) else { return }
        // Shift measures from the photo picked before, and takes everything
        // between the two, this one included.
        if extending, let anchor = anchorID,
           let from = live.firstIndex(where: { $0.id == anchor }) {
            let run = from <= index ? from...index : index...from
            selection = Set(live[run].map(\.id))
            return
        }
        if toggling {
            if selection.contains(id) {
                selection.remove(id)
            } else {
                selection.insert(id)
            }
            anchorID = id
            return
        }
        selection = [id]
        anchorID = id
    }

    func clearSelection() {
        pendingCollapse = nil
        guard !selection.isEmpty || anchorID != nil else { return }
        selection.removeAll()
        anchorID = nil
    }

    /// What an action acts on: the whole group when this photo is part of it,
    /// otherwise just this photo. One rule serves both halves of the menu,
    /// because a plain click leaves exactly one photo picked out — so "do it
    /// to these three" and "do it to this one" are the same sentence.
    func targets(including id: UUID) -> [Pegged] {
        let live = items.filter { !$0.falling }
        guard let hit = live.first(where: { $0.id == id }) else { return [] }
        let chosen = live.filter { selection.contains($0.id) }
        return chosen.count > 1 && chosen.contains(where: { $0.id == id }) ? chosen : [hit]
    }

    /// A drag carries the same thing the menu acts on.
    func dragPayload(including id: UUID) -> [Pegged] {
        targets(including: id)
    }

    private func forgetSelection(_ id: UUID) {
        if anchorID == id { anchorID = nil }
        selection.remove(id)
    }

    // MARK: Hanging and dropping

    @discardableResult
    func hang(_ url: URL, quietly: Bool = false, flying: Bool = false, thumbnail: NSImage? = nil) -> UUID? {
        guard !items.contains(where: { $0.url == url && !$0.falling }),
              let thumb = thumbnail ?? makeThumbnail(url) else { return nil }
        guard liveCount < maxItems else {
            onCapacityReached?(maxItems)
            return nil
        }
        var item = Pegged(url: url, thumb: thumb)
        item.flying = flying
        items.append(item)
        scroll = 0
        save()
        if !quietly { play("Tink", volume: 0.35) }
        if liveCount == maxItems { onCapacityReached?(maxItems) }
        return item.id
    }

    /// The capture has reached the line: the real card takes over.
    func land(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].flying = false
    }

    /// Called just before a photo starts falling, so the fall can be drawn
    /// over the whole screen.
    var onFall: ((Pegged) -> Void)?

    func drop(_ id: UUID, quietly: Bool = false) {
        guard let i = items.firstIndex(where: { $0.id == id }), !items[i].falling else { return }
        onFall?(items[i])
        items[i].falling = true
        hitRects[id] = nil
        save()
        if !quietly { play("Pop", volume: 0.25) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.items.removeAll { $0.id == id }
            self?.forgetSelection(id)
        }
    }

    /// "Take everything down": every photo goes the way of its corner cross.
    func clear() {
        clearSelection()
        takeDown(items.filter { !$0.falling })
    }

    /// The photos hung before (left) or after (right) this one.
    func neighbours(of id: UUID, toTheLeft: Bool) -> [Pegged] {
        let live = items.filter { !$0.falling }
        guard let i = live.firstIndex(where: { $0.id == id }) else { return [] }
        return toTheLeft ? Array(live[..<i]) : Array(live[(i + 1)...])
    }

    /// Takes down everything on one side of a photo. Each one goes the way
    /// of its own corner button: to the Trash from Tendedero's folder, and
    /// only off the line from anywhere else.
    func takeDown(_ id: UUID, toTheLeft: Bool) {
        takeDown(neighbours(of: id, toTheLeft: toTheLeft))
    }

    /// One after another, and only the first makes a sound.
    private func takeDown(_ live: [Pegged]) {
        for (n, item) in live.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06 * Double(n)) { [weak self] in
                self?.discard(item.id, quietly: n > 0)
            }
        }
    }

    /// Photos whose file was deleted or moved away fall off by themselves.
    func prune() {
        for item in items where !item.falling && !FileManager.default.fileExists(atPath: item.url.path) {
            drop(item.id, quietly: true)
        }
    }

    // MARK: Actions on one photo

    /// Every image on the line, including offscreen cards, in hanging order.
    /// Prepare the batch before clearing the clipboard so a missing file does
    /// not destroy what the user already copied.
    @discardableResult
    func copyAllImages(to pasteboard: NSPasteboard = .general) throws -> Int {
        let images = items.filter { !$0.falling && !$0.isRecording }
        guard !images.isEmpty else { return 0 }
        var singleImage: Data?
        for item in images {
            guard let png = pngData(item.url), NSBitmapImageRep(data: png) != nil else {
                throw ImageCopyError.unreadableImage
            }
            if images.count == 1 { singleImage = png }
        }
        pasteboard.clearContents()
        let written: Bool
        if let png = singleImage {
            let entry = NSPasteboardItem()
            entry.setData(png, forType: .png)
            entry.setString(images[0].url.absoluteString, forType: .fileURL)
            written = pasteboard.writeObjects([entry])
        } else {
            // Native URL writers preserve the entire file list across apps
            // and after this process exits. Raster data would select only one.
            written = pasteboard.writeObjects(images.map { $0.url as NSURL })
        }
        guard written, pasteboard.setString("1", forType: ClipboardWatcher.ownType) else {
            throw ImageCopyError.clipboardUnavailable
        }
        // Fulfil every URL representation now, rather than leaving later
        // items dependent on a live pasteboard writer in this process.
        let copiedFiles = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        guard copiedFiles == images.map(\.url) else { throw ImageCopyError.clipboardUnavailable }
        if let last = images.last { markCopied(last.id) }
        return images.count
    }

    /// Copies every photo the menu was asked about, one pasteboard item each:
    /// Finder and chat windows both take a list of files, and the picture data
    /// rides along so pasting into an editor still gives a picture.
    func copy(_ id: UUID) {
        let group = targets(including: id)
        guard !group.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(group.map { item in
            let entry = NSPasteboardItem()
            // A recording is copied as the file, which apps paste as the video.
            if !item.isRecording, let png = pngData(item.url) { entry.setData(png, forType: .png) }
            entry.setString(item.url.absoluteString, forType: .fileURL)
            entry.setString("1", forType: ClipboardWatcher.ownType)
            return entry
        })

        markCopied(id)
    }

    private func markCopied(_ id: UUID) {
        copiedID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.copiedID == id { self?.copiedID = nil }
        }
    }

    func open(_ id: UUID) {
        for item in targets(including: id) { imageOpener.open(item.url) }
    }

    /// Moves the file to the Trash and takes the photo off the line. When a
    /// drag ends on the Dock's Trash, macOS only reports it: deleting the file
    /// is the source app's job, as Finder does.
    @discardableResult
    func trash(_ id: UUID, quietly: Bool = false) -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return false }
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            log.notice("Trashed \(item.url.lastPathComponent, privacy: .public)")
            if soundOn && !quietly { Line.trashSound?.play() }
            drop(id, quietly: true)
            return true
        } catch {
            log.error("Could not trash \(item.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            if !quietly { NSSound.beep() }
            return false
        }
    }

    private static let trashSound = NSSound(
        contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/drag to trash.aif",
        byReference: true)

    /// Whether the file lives in Tendedero's own folder. Those are discarded
    /// to the Trash, or the folder would fill up with forgotten screenshots.
    /// Files anywhere else, like the Desktop, stay where they are.
    func isInInbox(_ id: UUID) -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return false }
        return item.url.standardizedFileURL.path.hasPrefix(Inbox.folder.standardizedFileURL.path + "/")
    }

    /// The corner cross and "Take down" both end up here. The cross is always
    /// one photo; the menu widens this to the group through `discardGroup`.
    func discard(_ id: UUID, quietly: Bool = false) {
        if isInInbox(id) { trash(id, quietly: quietly) } else { drop(id, quietly: quietly) }
    }

    /// The menu's "Discard" and "Take down": one after another, and only the
    /// first makes a sound.
    func discardGroup(_ id: UUID) {
        for (n, item) in targets(including: id).enumerated() {
            discard(item.id, quietly: n > 0)
        }
    }

    /// The menu's "Move to Trash", for the whole group.
    func trashGroup(_ id: UUID) {
        for (n, item) in targets(including: id).enumerated() {
            trash(item.id, quietly: n > 0)
        }
    }

    /// Moves along a line that holds more than fit, from a scroll gesture.
    func scroll(by delta: CGFloat) {
        let most = CGFloat(max(0, items.count - visibleCount)) * Layout.spacing
        let next = min(most, max(0, scroll + delta))
        if next != scroll { scroll = next }
    }

    /// Inbox mode: keep the picked photos by moving them to the Desktop.
    ///
    /// A photo from the line's own folder is moved, since that folder exists
    /// only to be emptied. One that came from somewhere else is copied: the
    /// menu offers this for the line's own screenshots, and a stray foreign
    /// photo in a mixed group must not be taken out of the folder you put it
    /// in.
    func saveToDesktop(_ id: UUID, into folder: URL? = nil) {
        let group = targets(including: id)
        guard !group.isEmpty else { return }
        let desktop = folder ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
        var trouble = false
        for item in group {
            let target = uniqueURL(in: desktop, for: item.url.lastPathComponent)
            do {
                if isInInbox(item.id) {
                    try FileManager.default.moveItem(at: item.url, to: target)
                } else {
                    try FileManager.default.copyItem(at: item.url, to: target)
                }
                drop(item.id, quietly: true)
            } catch {
                log.error("Could not save to Desktop: \(error.localizedDescription, privacy: .public)")
                trouble = true
            }
        }
        if trouble { NSSound.beep() }
    }

    private func uniqueURL(in folder: URL, for name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    /// Long press: open the photo in the system Markup editor. Markup does
    /// not edit video, so a recording opens in the trimming editor instead.
    func markup(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        if item.isRecording {
            Trim.shared.edit(item.url, size: item.thumb.size)
        } else {
            Markup.shared.edit(item.url)
        }
    }

    /// After editing, the photo on the line shows the new version.
    func reloadThumbnail(for url: URL, thumbnail: NSImage? = nil) {
        guard let i = items.firstIndex(where: { $0.url == url && !$0.falling }),
              let thumb = thumbnail ?? makeThumbnail(url) else { return }
        items[i].thumb = thumb
    }

    /// Recover the same card through another matching file. Preserve its ID,
    /// position and tilt; deleting a duplicate never deletes either source.
    func replaceFile(at oldURL: URL, with url: URL, thumbnail: NSImage) {
        guard let index = items.firstIndex(where: { $0.url == oldURL && !$0.falling }) else { return }
        items[index].url = url
        items[index].thumb = thumbnail
        save()
    }

    func removeDuplicateOrMissingFile(_ url: URL) {
        guard let item = items.first(where: { $0.url == url && !$0.falling }) else { return }
        drop(item.id, quietly: true)
    }

    /// Quick Look on this photo, with the rest of the line a key press away.
    func quickLook(_ id: UUID) {
        let live = items.filter { !$0.falling }
        guard let index = live.firstIndex(where: { $0.id == id }) else { return }
        QuickLook.shared.show(live.map(\.url), at: index)
    }

    /// After a change of size, every photo is redrawn sharp at the new one.
    func reloadThumbnails() {
        for i in items.indices where !items[i].falling {
            if let thumb = makeThumbnail(items[i].url) { items[i].thumb = thumb }
        }
    }

    func reveal(_ id: UUID) {
        let urls = targets(including: id).map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Hands the photos to AirDrop: the system window lists the devices near
    /// you, and the one you pick gets the files. The photos stay on the line.
    ///
    /// The window belongs to the sharing service, so it is opened after the
    /// menu has closed: nothing of ours can pop a window while a menu still
    /// runs its own event loop.
    func airdrop(_ id: UUID) {
        let urls = targets(including: id).map(\.url)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls) else {
            NSSound.beep()
            return
        }
        DispatchQueue.main.async {
            // The line is a floating strip that never takes focus; the
            // AirDrop window is a normal one, so the app has to come forward
            // for it to be in front of what you were doing.
            NSApp.activate(ignoringOtherApps: true)
            service.perform(withItems: urls)
        }
    }

    // MARK: Breeze

    /// Every so often a little wind moves the line. It is the detail that
    /// makes it feel like an object and not a widget.
    private func scheduleGust() {
        DispatchQueue.main.asyncAfter(deadline: .now() + .random(in: 7...16)) { [weak self] in
            guard let self else { return }
            if !self.items.isEmpty && self.draggingID == nil { self.gust += 1 }
            self.scheduleGust()
        }
    }

    // MARK: Persistence

    private func save() {
        let paths = items.filter { !$0.falling }.map(\.url.path)
        defaults.set(paths, forKey: storeKey)
    }

    /// Everything comes back as it was. This runs before the line knows its
    /// screen, so the capacity is still the default one: hanging through
    /// `hang` would let photos fall off a wide screen's line at every launch.
    private func restore() {
        let paths = defaults.stringArray(forKey: storeKey) ?? []
        for path in paths where FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            guard !items.contains(where: { $0.url == url }), let thumb = makeThumbnail(url) else { continue }
            items.append(Pegged(url: url, thumb: thumb))
        }
    }

    // MARK: Helpers

    private func play(_ name: String, volume: Float) {
        guard soundOn, let sound = NSSound(named: name)?.copy() as? NSSound else { return }
        sound.volume = volume
        sound.play()
    }

    private func pngData(_ url: URL) -> Data? {
        if url.pathExtension.lowercased() == "png" { return try? Data(contentsOf: url) }
        guard let tiff = NSImage(contentsOf: url)?.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// Screen recordings, as macOS saves them.
func isRecording(_ url: URL) -> Bool {
    ["mov", "mp4"].contains(url.pathExtension.lowercased())
}

/// The default size covers a card at twice its size in points, as on a
/// Retina screen, and no more: every photo on the line keeps one in memory.
func makeThumbnail(_ url: URL, maxPixels: Int = Int(320 * Layout.size.scale)) -> NSImage? {
    if isRecording(url) { return firstFrame(url, maxPixels: maxPixels) }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixels,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}

/// A recording shows its first frame.
private func firstFrame(_ url: URL, maxPixels: Int) -> NSImage? {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: maxPixels, height: maxPixels)
    guard let cg = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}
