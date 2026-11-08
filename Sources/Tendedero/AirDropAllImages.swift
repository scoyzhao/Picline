import AppKit

enum ImageAirDropError: LocalizedError {
    case unreadableImage
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unreadableImage: return L("An image is missing or unreadable. Nothing was sent.")
        case .unavailable: return L("AirDrop is unavailable. Check Wi-Fi and Bluetooth, then try again.")
        }
    }
}

@MainActor
enum AirDropImages {
    static func validate(_ urls: [URL]) throws {
        for url in urls {
            guard url.isFileURL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  FileManager.default.isReadableFile(atPath: url.path),
                  makeThumbnail(url, maxPixels: 1) != nil else {
                throw ImageAirDropError.unreadableImage
            }
        }
    }

    static func present(_ urls: [URL]) throws {
        guard let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls) else {
            throw ImageAirDropError.unavailable
        }
        // Let the context menu close before opening the system sharing window.
        DispatchQueue.main.async {
            do {
                // Files can disappear while the menu is closing. Never send a partial batch.
                try validate(urls)
                guard service.canPerform(withItems: urls) else { throw ImageAirDropError.unavailable }
                NSApp.activate(ignoringOtherApps: true)
                service.perform(withItems: urls)
            } catch {
                reportFailure(error)
            }
        }
    }

    static func reportFailure(_ error: Error) {
        log.error("AirDrop all images failed: \(error.localizedDescription, privacy: .public)")
        LineFeedback.airdropFailed(error.localizedDescription)
    }
}

@MainActor
enum AirDropAllImagesMenu {
    static func make(for line: Line,
                     present: @escaping @MainActor ([URL]) throws -> Void = AirDropImages.present,
                     onFailure: (@MainActor (Error) -> Void)? = nil) -> NSMenuItem {
        let title = L("Send all images via AirDrop") + " · " + String(format: L("%d photos"), line.liveImageCount)
        let item = ClosureMenuItem(title) {
            do {
                try line.airdropAllImages(present: present)
            } catch {
                if let onFailure { onFailure(error) }
                else { AirDropImages.reportFailure(error) }
            }
        }
        item.isEnabled = line.liveImageCount > 0
        return item
    }
}
