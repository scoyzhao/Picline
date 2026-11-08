import AppKit

@main
struct CheckAirDropAll {
    @MainActor
    static func main() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("build/airdrop-all-check", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let urls = try fixtures(in: directory)
        let suite = "picline.airdrop-all-check.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let line = Line(defaults: defaults)
        line.maxItems = 100
        line.visibleCount = 1
        for url in urls { precondition(line.hang(url, quietly: true) != nil) }
        let originalIDs = line.items.map(\.id)
        let originalFiles = try urls.map { try Data(contentsOf: $0) }
        let savedPaths = defaults.stringArray(forKey: "pegged")
        line.select(originalIDs[0])

        if Bundle.main.bundleIdentifier == "local.picline.airdrop-check" {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 160),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Picline AirDrop Check"
            window.isReleasedWhenClosed = false
            for (index, item) in line.items.enumerated() {
                let view = NSImageView(frame: NSRect(x: 20 + index * 200, y: 24, width: 180, height: 112))
                view.image = item.thumb
                view.imageScaling = .scaleProportionallyUpOrDown
                view.setAccessibilityLabel(item.url.lastPathComponent)
                view.menu = CardMenu.make(for: item, on: line)
                window.contentView?.addSubview(view)
            }
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            let cleanup = Cleanup { defaults.removePersistentDomain(forName: suite) }
            NSApp.delegate = cleanup
            withExtendedLifetime((window, cleanup, line)) { NSApp.run() }
            return
        }

        var sent: [[URL]] = []
        let count = try line.airdropAllImages { sent.append($0) }
        precondition(count == 3 && sent == [urls])
        precondition(line.selection == [originalIDs[0]])
        precondition(line.items.map(\.id) == originalIDs)
        precondition(defaults.stringArray(forKey: "pegged") == savedPaths)
        let filesAfterPreparing = try urls.map { try Data(contentsOf: $0) }
        precondition(filesAfterPreparing == originalFiles)
        print("PASS: all three original files, hanging order, offscreen images, unchanged selection/cards/files/preferences.")

        let menu = NSMenu()
        menu.autoenablesItems = false
        let all = AirDropAllImagesMenu.make(for: line, present: { sent.append($0) })
        menu.addItem(all)
        precondition(all.isEnabled)
        precondition(all.title == L("Send all images via AirDrop") + " · " + String(format: L("%d photos"), 3))
        menu.performActionForItem(at: 0)
        precondition(sent == [urls, urls])
        line.select(originalIDs[1], toggling: true)
        let cardMenu = CardMenu.make(for: line.items[0], on: line)
        let existingIndex = cardMenu.items.firstIndex { $0.title.hasPrefix(L("Send via AirDrop")) }!
        let allIndex = cardMenu.items.firstIndex { $0.title.hasPrefix(L("Send all images via AirDrop")) }!
        precondition(allIndex == existingIndex + 1)
        precondition(cardMenu.items[existingIndex].title == L("Send via AirDrop") + " · " + String(format: L("%d photos"), 2))
        precondition(cardMenu.items[allIndex].title == all.title)
        precondition(line.targets(including: originalIDs[0]).map(\.url) == Array(urls.prefix(2)))
        print("PASS: separate counted right-click entry invokes the all-image action; existing selected-group AirDrop remains unchanged.")

        let emptySuite = "picline.airdrop-empty.\(UUID())"
        let emptyDefaults = UserDefaults(suiteName: emptySuite)!
        defer { emptyDefaults.removePersistentDomain(forName: emptySuite) }
        let empty = Line(defaults: emptyDefaults)
        precondition(!AirDropAllImagesMenu.make(for: empty).isEnabled)
        let emptyCount = try empty.airdropAllImages { _ in fatalError("Empty lines must not open AirDrop.") }
        precondition(emptyCount == 0)
        let movie = directory.appendingPathComponent("recording.mov")
        try Data().write(to: movie, options: .atomic)
        let placeholder = NSImage(size: NSSize(width: 16, height: 16))
        precondition(empty.hang(movie, quietly: true, thumbnail: placeholder) != nil)
        precondition(!AirDropAllImagesMenu.make(for: empty).isEnabled)
        print("PASS: empty and recording-only lines disable the all-images action.")
        precondition(empty.hang(urls[0], quietly: true) != nil)
        let singleCount = try empty.airdropAllImages { precondition($0 == [urls[0]]) }
        precondition(singleCount == 1)
        print("PASS: one image is handed off as its original file URL.")

        precondition(line.hang(movie, quietly: true, thumbnail: placeholder) != nil)
        line.drop(originalIDs[0], quietly: true)
        let filteredCount = try line.airdropAllImages { sent.append($0) }
        precondition(filteredCount == 2 && sent.last == Array(urls.suffix(2)))
        print("PASS: recordings and falling cards are excluded without changing the remaining order.")

        let missing = directory.appendingPathComponent("missing.png")
        try originalFiles[0].write(to: missing, options: .atomic)
        precondition(empty.hang(missing, quietly: true) != nil)
        var missingReported = false
        let beforeDeletion = AirDropAllImagesMenu.make(for: empty, present: { _ in
            fatalError("Missing images must not send a partial batch.")
        }, onFailure: { error in
            guard case ImageAirDropError.unreadableImage = error else { fatalError("Wrong missing-image error.") }
            missingReported = true
        })
        precondition(beforeDeletion.isEnabled)
        try FileManager.default.removeItem(at: missing)
        let missingMenu = NSMenu()
        missingMenu.autoenablesItems = false
        missingMenu.addItem(beforeDeletion)
        missingMenu.performActionForItem(at: 0)
        precondition(missingReported)
        do {
            try empty.airdropAllImages { _ in fatalError("Missing image was sent.") }
            fatalError("Missing images must produce an error.")
        } catch ImageAirDropError.unreadableImage {}
        print("PASS: a file removed after menu creation aborts the entire batch with an error.")

        try Data("not an image".utf8).write(to: missing, options: .atomic)
        do {
            try empty.airdropAllImages { _ in fatalError("Invalid image was sent.") }
            fatalError("Invalid images must produce an error.")
        } catch ImageAirDropError.unreadableImage {}
        try originalFiles[0].write(to: missing, options: .atomic)
        var reportedFailure = false
        let unavailableMenu = NSMenu()
        unavailableMenu.autoenablesItems = false
        unavailableMenu.addItem(AirDropAllImagesMenu.make(for: empty,
            present: { _ in throw ImageAirDropError.unavailable },
            onFailure: { error in
                guard case ImageAirDropError.unavailable = error else { fatalError("Wrong failure.") }
                reportedFailure = true
            }))
        unavailableMenu.performActionForItem(at: 0)
        precondition(reportedFailure)
        precondition(empty.liveImageCount == 2)
        print("PASS: unreadable images and an unavailable service report failure without removing cards.")

        let batchSuite = "picline.airdrop-nine.\(UUID())"
        let batchDefaults = UserDefaults(suiteName: batchSuite)!
        defer { batchDefaults.removePersistentDomain(forName: batchSuite) }
        let batch = Line(defaults: batchDefaults)
        batch.maxItems = 9
        var batchURLs: [URL] = []
        for number in 1...9 {
            let url = directory.appendingPathComponent("batch-\(number).png")
            try originalFiles[0].write(to: url, options: .atomic)
            batchURLs.append(url)
            precondition(batch.hang(url, quietly: true) != nil)
        }
        let nineCount = try batch.airdropAllImages { precondition($0 == batchURLs) }
        precondition(nineCount == 9 && batch.liveCount == 9)
        precondition(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        print("PASS: the nine-image batch is passed intact in hanging order.")

        if let service = NSSharingService(named: .sendViaAirDrop) {
            precondition(service.canPerform(withItems: urls), "The system must accept the whole mixed PNG/JPEG batch.")
            precondition(service.canPerform(withItems: batchURLs), "The system must accept nine image files together.")
            print("PASS: the native AirDrop service accepts the complete three-image and nine-image batches (no transfer performed).")
        } else {
            print("SKIP: the native AirDrop service is unavailable on this Mac.")
        }
        batch.maxItems = 25
        let tenth = directory.appendingPathComponent("batch-10.png")
        try originalFiles[0].write(to: tenth, options: .atomic)
        precondition(batch.hang(tenth, quietly: true) != nil)
        let tenCount = try batch.airdropAllImages { precondition($0 == batchURLs + [tenth]) }
        precondition(tenCount == 10)
        print("PASS: AirDrop-all is not truncated to nine when a larger line limit is selected.")
        print("All AirDrop-all checks passed. No user files, clipboard, or recipients were used.")
    }

    static func fixtures(in directory: URL) throws -> [URL] {
        try (1...3).map { number in
            let jpeg = number == 2
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 200,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            var pixel = [number == 1 ? 220 : 40, number == 2 ? 190 : 70, number == 3 ? 220 : 80, 255]
            for y in 0..<200 { for x in 0..<320 { bitmap.setPixel(&pixel, atX: x, y: y) } }
            let url = directory.appendingPathComponent("airdrop-test-\(number).\(jpeg ? "jpg" : "png")")
            try bitmap.representation(using: jpeg ? .jpeg : .png, properties: [:])!.write(to: url, options: .atomic)
            return url
        }
    }
}

@MainActor
private final class Cleanup: NSObject, NSApplicationDelegate {
    private let cleanup: () -> Void
    init(_ cleanup: @escaping () -> Void) { self.cleanup = cleanup }
    func applicationWillTerminate(_ notification: Notification) { cleanup() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
