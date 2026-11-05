import AppKit

@main
struct CheckCopyAll {
    @MainActor
    static func main() throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/copy-all-check", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if CommandLine.arguments.contains("--preview-limit") || CommandLine.arguments.contains("--preview-feedback") {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            let isDark = CommandLine.arguments.contains("--dark")
            NSApp.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
            let states = CommandLine.arguments.contains("--preview-feedback") ? ["capacity", "copy", "error"] : ["capacity"]
            var previous: NSWindow?
            for state in states {
                switch state {
                case "copy": LineFeedback.copiedImages(9)
                case "error": LineFeedback.copyFailed(ImageCopyError.unreadableImage.localizedDescription)
                default: LineFeedback.capacityReached(9)
                }
                precondition(previous?.isVisible != true, "New feedback must replace the previous panel.")
                guard let window = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible }),
                      let view = window.contentView,
                      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    fatalError("The feedback panel must be visible.")
                }
                precondition(window.styleMask.contains(.nonactivatingPanel) && window.ignoresMouseEvents)
                precondition(view.bounds.width == 320)
                precondition(view.subviews.compactMap { $0 as? NSImageView }.count == 1,
                             "Feedback uses one status icon, with no redundant trailing icon.")
                let labels = view.subviews.compactMap { $0 as? NSTextField }
                precondition(labels.count == (state == "copy" ? 1 : 2))
                for (index, label) in labels.enumerated() {
                    precondition(view.bounds.contains(label.frame), "Text must remain inside the rounded surface.")
                    for other in labels.dropFirst(index + 1) {
                        precondition(!label.frame.intersects(other.frame), "Heading, status, and detail must not overlap.")
                    }
                }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                precondition(bitmap.hasAlpha && (bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.1,
                             "Rounded corners must remain transparent instead of showing a square backing.")
                let name = CommandLine.arguments.contains("--preview-feedback")
                    ? "feedback-\(state)-\(isDark ? "dark" : "light").png" : "capacity-feedback.png"
                let preview = directory.appendingPathComponent(name)
                try bitmap.representation(using: .png, properties: [:])!.write(to: preview, options: .atomic)
                print("Saved feedback preview: \(preview.path)")
                previous = window
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 3.5))
            precondition(previous?.isVisible != true, "Feedback must dismiss automatically.")
            print("PASS: compact feedback geometry, replacement, nonactivation, and automatic dismissal.")
            return
        }
        if CommandLine.arguments.contains("--restore-clipboard") {
            let pasteboard = NSPasteboard.general
            let current = pasteboard.pasteboardItems ?? []
            guard current.contains(where: { $0.types.contains(ClipboardWatcher.ownType) }), current.allSatisfy({ item in
                item.string(forType: .fileURL).flatMap(URL.init(string:))?.path.hasPrefix(directory.path + "/") == true
            }) else {
                print("Clipboard has changed; keeping the user's current contents.")
                return
            }
            let snapshot = directory.appendingPathComponent("clipboard-before.plist")
            let data = try Data(contentsOf: snapshot)
            let contents = try PropertyListSerialization.propertyList(from: data, format: nil) as! [[String: Data]]
            let restored = contents.map { values -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: .init(type)) }
                return item
            }
            pasteboard.clearContents()
            if !restored.isEmpty { precondition(pasteboard.writeObjects(restored)) }
            try FileManager.default.removeItem(at: snapshot)
            print("Restored the clipboard saved before compatibility checks.")
            return
        }
        let urls = try fixtures(in: directory)
        let suite = "picline.copy-all-check.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let line = Line(defaults: defaults)
        line.maxItems = 100
        line.visibleCount = 1
        for url in urls { precondition(line.hang(url, quietly: true) != nil) }

        if CommandLine.arguments.contains("--copy-to-general") {
            let snapshot = directory.appendingPathComponent("clipboard-before.plist")
            if !FileManager.default.fileExists(atPath: snapshot.path) {
                let contents = (NSPasteboard.general.pasteboardItems ?? []).map { item in
                    Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                        item.data(forType: type).map { (type.rawValue, $0) }
                    })
                }
                let data = try PropertyListSerialization.data(fromPropertyList: contents, format: .binary, options: 0)
                try data.write(to: snapshot, options: .atomic)
            }
            let count = try line.copyAllImages()
            print("Copied \(count) generated test images to the general clipboard.")
            return
        }

        let pasteboard = NSPasteboard(name: .init("picline.copy-all-check.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let originalIDs = line.items.map(\.id)
        line.select(originalIDs[1])
        let copied = try line.copyAllImages(to: pasteboard)
        precondition(copied == 3, "The entire line must be copied regardless of selection and scroll.")
        let entries = pasteboard.pasteboardItems ?? []
        precondition(entries.count == 3)
        precondition(entries.compactMap { $0.string(forType: .fileURL) } == urls.map(\.absoluteString))
        precondition((pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) == urls)
        precondition((pasteboard.propertyList(forType: .init("NSFilenamesPboardType")) as? [String]) == urls.map(\.path))
        precondition(entries.allSatisfy { !$0.types.contains(.png) }, "Multi-image paste must not look like a single raster image.")
        precondition(urls.allSatisfy { url in
            guard let data = try? Data(contentsOf: url), let bitmap = NSBitmapImageRep(data: data) else { return false }
            return bitmap.pixelsWide == 320 && bitmap.pixelsHigh == 200
        })
        print("PASS: all images, line order, offscreen cards, mixed PNG/JPEG, original pixel dimensions, modern and legacy file lists.")
        precondition(ClipboardWatcher.inputs(from: entries).isEmpty)
        precondition(line.items.map(\.id) == originalIDs && line.liveCount == 3)
        precondition(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        precondition(CopyAllImagesMenu.make(for: line).isEnabled)
        print("PASS: copying keeps original cards/files and is ignored by clipboard intake.")

        let emptySuite = "picline.copy-all-check.empty.\(UUID())"
        let emptyDefaults = UserDefaults(suiteName: emptySuite)!
        defer { emptyDefaults.removePersistentDomain(forName: emptySuite) }
        let empty = Line(defaults: emptyDefaults)
        pasteboard.clearContents()
        pasteboard.setString("existing clipboard", forType: .string)
        let emptyCount = try empty.copyAllImages(to: pasteboard)
        precondition(emptyCount == 0)
        precondition(pasteboard.string(forType: .string) == "existing clipboard")
        precondition(!CopyAllImagesMenu.make(for: empty).isEnabled)
        print("PASS: an empty line disables the menu and preserves the clipboard.")

        precondition(empty.hang(urls[1], quietly: true) != nil)
        let singleCount = try empty.copyAllImages(to: pasteboard)
        precondition(singleCount == 1)
        precondition(pasteboard.pasteboardItems?.first?.data(forType: .png) != nil)
        empty.clear()
        pasteboard.clearContents()
        pasteboard.setString("existing clipboard", forType: .string)
        print("PASS: single-image copying still supplies raster data.")

        let missing = directory.appendingPathComponent("missing.png")
        try Data(contentsOf: urls[0]).write(to: missing, options: .atomic)
        precondition(empty.hang(missing, quietly: true) != nil)
        try FileManager.default.removeItem(at: missing)
        do {
            _ = try empty.copyAllImages(to: pasteboard)
            fatalError("A missing image must fail explicitly.")
        } catch ImageCopyError.unreadableImage {
            precondition(pasteboard.string(forType: .string) == "existing clipboard")
        }
        print("PASS: unreadable images report failure without clearing the clipboard.")

        let recording = directory.appendingPathComponent("recording.mov")
        try Data().write(to: recording, options: .atomic)
        precondition(line.hang(recording, quietly: true, thumbnail: NSImage(size: NSSize(width: 16, height: 16))) != nil)
        precondition(line.liveImageCount == 3)
        let imageCount = try line.copyAllImages(to: pasteboard)
        precondition(imageCount == 3)
        line.drop(originalIDs[0], quietly: true)
        let remainingCount = try line.copyAllImages(to: pasteboard)
        precondition(remainingCount == 2)
        print("PASS: recordings and cards being removed are excluded.")
        try checkCapacity(in: directory, image: urls[0])
        print("All copy-all checks passed. The user's clipboard was not used.")
    }

    @MainActor
    static func checkCapacity(in directory: URL, image: URL) throws {
        let suite = "picline.capacity-check.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let line = Line(defaults: defaults)
        line.maxItems = 9
        // A wide display must not raise a selected nine-photo limit.
        line.visibleCount = 12
        var warnings: [Int] = []
        line.onCapacityReached = { warnings.append($0) }
        let data = try Data(contentsOf: image)
        let urls = try (1...12).map { number -> URL in
            let url = directory.appendingPathComponent("capacity-\(number).png")
            try data.write(to: url, options: .atomic)
            return url
        }
        for url in urls.prefix(8) { precondition(line.hang(url, quietly: true) != nil) }
        precondition(warnings.isEmpty)
        precondition(line.hang(urls[8], quietly: true) != nil)
        precondition(warnings == [9] && line.liveCount == 9)
        let pasteboard = NSPasteboard(name: .init("picline.nine-photo-check.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let batchCount = try line.copyAllImages(to: pasteboard)
        precondition(batchCount == 9 && pasteboard.pasteboardItems?.count == 9)
        precondition((pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) == Array(urls.prefix(9)))
        let originalIDs = line.items.map(\.id)
        let paths = defaults.stringArray(forKey: "pegged")
        for _ in 0..<2 { precondition(line.hang(urls[9], quietly: true) == nil) }
        precondition(warnings == [9, 9, 9])
        precondition(line.items.map(\.id) == originalIDs && !line.items.contains(where: \.falling))
        precondition(defaults.stringArray(forKey: "pegged") == paths)
        precondition(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        precondition(line.hang(urls[0], quietly: true) == nil && warnings.count == 3)
        print("PASS: the ninth photo hangs and warns; repeated tenth-photo attempts warn without replacing, dropping, or deleting anything.")

        line.drop(originalIDs[8], quietly: true)
        precondition(line.hang(urls[9], quietly: true) != nil && line.liveCount == 9)
        precondition(warnings == [9, 9, 9, 9])
        let beforeLowering = line.items.filter { !$0.falling }.map(\.id)
        line.maxItems = 4
        precondition(warnings.last == 4 && line.liveCount == 9)
        precondition(line.items.filter { !$0.falling }.map(\.id) == beforeLowering)
        precondition(line.hang(urls[10], quietly: true) == nil)
        let restored = Line(defaults: defaults)
        restored.maxItems = 9
        precondition(restored.items.map(\.url) == line.items.filter { !$0.falling }.map(\.url))
        precondition(restored.liveCount == 9)
        precondition(Line.keepChoices == [9, 25, 50, 100])
        print("PASS: taking one down frees capacity; lowering the limit and restarting preserve existing photos; nine is an available menu choice.")
    }

    static func fixtures(in directory: URL) throws -> [URL] {
        try (1...3).map { number in
            let jpeg = number == 2
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 200,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            var pixel = [number == 1 ? 220 : 40, number == 2 ? 190 : 70, number == 3 ? 220 : 80, 255]
            for y in 0..<200 { for x in 0..<320 { bitmap.setPixel(&pixel, atX: x, y: y) } }
            let url = directory.appendingPathComponent("picline-test-\(number).\(jpeg ? "jpg" : "png")")
            let data = bitmap.representation(using: jpeg ? .jpeg : .png, properties: [:])!
            try data.write(to: url, options: .atomic)
            return url
        }
    }
}
