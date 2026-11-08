import AppKit

enum ImageCopyError: LocalizedError {
    case unreadableImage
    case clipboardUnavailable

    var errorDescription: String? {
        switch self {
        case .unreadableImage: return L("An image is missing or unreadable. Nothing was copied.")
        case .clipboardUnavailable: return L("Could not write to the clipboard. Please try again.")
        }
    }
}

@MainActor
enum CopyAllImagesMenu {
    static func make(for line: Line) -> NSMenuItem {
        let title = L("Copy all images") + " · " + String(format: L("%d photos"), line.liveImageCount)
        let item = ClosureMenuItem(title) {
            do {
                let count = try line.copyAllImages()
                if count > 0 { LineFeedback.copiedImages(count) }
            } catch {
                log.error("Copy all images failed: \(error.localizedDescription, privacy: .public)")
                LineFeedback.copyFailed(error.localizedDescription)
            }
        }
        item.isEnabled = line.liveImageCount > 0
        return item
    }
}

@MainActor
enum LineFeedback {
    private static var panel: NSPanel?
    private static var dismiss: DispatchWorkItem?

    static func copiedImages(_ count: Int) {
        show(title: String(format: L("Copied %d images"), count), symbol: "checkmark.circle",
             accent: color(44, 139, 110), detail: nil)
    }

    static func capacityReached(_ limit: Int) {
        show(title: String(format: L("The line is full (%d photos)."), limit), symbol: "exclamationmark.circle",
             accent: .systemOrange, detail: L("Take some photos down to make room."))
    }

    static func copyFailed(_ message: String) {
        show(title: L("Copy failed"), symbol: "exclamationmark.circle", accent: .systemRed, detail: message)
    }

    static func airdropFailed(_ message: String) {
        show(title: L("AirDrop failed"), symbol: "exclamationmark.circle", accent: .systemRed, detail: message)
    }

    private static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
    }

    private static func show(title: String, symbol: String, accent: NSColor, detail: String?) {
        dismiss?.cancel()
        panel?.orderOut(nil)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main else { return }
        let width: CGFloat = 320
        let textX: CGFloat = 54
        let textWidth = width - textX - 16
        let titleFont = NSFont.systemFont(ofSize: 14, weight: .medium)
        let detailFont = NSFont.systemFont(ofSize: 12)
        let titleHeight = max(20, ceil((title as NSString).boundingRect(
            with: NSSize(width: textWidth, height: 1000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: titleFont]).height) + 2)
        let detailHeight = detail.map { ceil(($0 as NSString).boundingRect(
            with: NSSize(width: textWidth, height: 1000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: detailFont]).height) + 4 } ?? 0
        let gap: CGFloat = detail == nil ? 0 : 4
        let textHeight = titleHeight + gap + detailHeight
        let size = NSSize(width: width, height: max(detail == nil ? 56 : 76, textHeight + 30))
        let textBottom = (size.height - textHeight) / 2
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let frame = NSRect(x: screen.visibleFrame.maxX - size.width - 20,
                           y: screen.visibleFrame.maxY - size.height - 18,
                           width: size.width, height: size.height)
        let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let root = NSView(frame: NSRect(origin: .zero, size: size))
        window.contentView = root
        let surface = NSBox(frame: root.bounds)
        surface.boxType = .custom
        surface.titlePosition = .noTitle
        surface.borderWidth = 0.5
        surface.borderColor = isDark ? color(255, 255, 255, alpha: 0.13) : color(30, 34, 39, alpha: 0.1)
        surface.fillColor = isDark ? color(34, 35, 38, alpha: 0.98) : color(253, 253, 253, alpha: 0.98)
        surface.cornerRadius = 12
        root.addSubview(surface)

        let secondary = isDark ? NSColor.secondaryLabelColor : color(105, 112, 120)
        let icon = NSImageView(frame: NSRect(x: 16, y: (size.height - 22) / 2, width: 22, height: 22))
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = accent
        root.addSubview(icon)

        let heading = NSTextField(wrappingLabelWithString: title)
        heading.font = titleFont
        heading.textColor = isDark ? .labelColor : color(32, 35, 40)
        heading.maximumNumberOfLines = 0
        heading.lineBreakMode = .byWordWrapping
        heading.frame = NSRect(x: textX, y: textBottom + detailHeight + gap, width: textWidth, height: titleHeight)
        root.addSubview(heading)

        if let detail {
            let text = NSTextField(wrappingLabelWithString: detail)
            text.font = detailFont
            text.textColor = secondary
            text.maximumNumberOfLines = 0
            text.lineBreakMode = .byWordWrapping
            text.frame = NSRect(x: textX, y: textBottom, width: textWidth, height: detailHeight)
            root.addSubview(text)
        }
        panel = window
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            window.animator().alphaValue = 1
        }
        let work = DispatchWorkItem { [weak window] in
            guard let window else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                window.animator().alphaValue = 0
            }, completionHandler: { [weak window] in window?.orderOut(nil) })
        }
        dismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
}
