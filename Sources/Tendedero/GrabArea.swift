import AppKit
import SwiftUI

/// Bridges each photo to AppKit's drag and drop, so it can be dragged into
/// any app as a real file. Each destination means one thing:
///
/// - An app gets a copy, and the photo stays on the line.
/// - A folder or the Desktop keeps the file, and the photo leaves the line.
/// - The Trash discards it.
/// - Nowhere that accepts it: the photo flies back to the line.
///
/// Click picks a photo out, shift click takes the run between two of them,
/// command click adds or removes one. What is picked out is what a drag
/// carries and what every item in the right-click menu acts on, so three
/// photos picked out and one of them right-clicked means three of everything.
/// Double click opens, press and hold looks at the photo, a force click or the
/// middle button opens Markup, the corner cross discards just its own photo.
struct GrabArea: NSViewRepresentable {
    let item: Pegged
    let line: Line

    func makeNSView(context: Context) -> GrabView {
        let view = GrabView()
        configure(view)
        return view
    }

    func updateNSView(_ view: GrabView, context: Context) {
        configure(view)
    }

    private func configure(_ view: GrabView) {
        let id = item.id
        let line = line
        view.url = item.url
        view.dragImage = item.thumb
        view.onPress = { shift, command in
            line.press(id, extending: shift, toggling: command)
        }
        view.onSettle = { dragged in line.settle(id, dragged: dragged) }
        view.dragEntries = {
            line.dragPayload(including: id).map { ($0.url, $0.thumb) }
        }
        view.onDoubleClick = { line.open(id) }
        view.onDragStart = { line.draggingID = id }
        view.onDragEnd = {
            line.draggingID = nil
            // Moved into a folder: it is saved where you wanted it.
            line.prune()
        }
        view.onTrash = { line.trash(id) }
        view.onDiscard = { line.discard(id) }
        // Holding a photo looks at it, the way holding a key on a keyboard
        // does elsewhere; Markup moved to force click and the middle button,
        // which are both deliberate rather than merely slow.
        view.onLongPress = { line.quickLook(id) }
        view.onForceClick = { line.quickLook(id) }
        view.onMiddleClick = { line.markup(id) }
        view.onPressChange = { pressed in line.pressedID = pressed ? id : nil }
        view.menuProvider = { CardMenu.make(for: item, on: line) }
    }
}

/// The menu a card offers. Kept out of `GrabArea` so it can be built and
/// inspected without a window: what it offers depends on how many photos are
/// picked out, and that is the part worth checking.
@MainActor
enum CardMenu {
    static func make(for item: Pegged, on line: Line) -> NSMenu {
        let id = item.id
        // Everything below acts on what is picked out. Right-clicking one of
        // three chosen photos means all three; right-clicking a photo that is
        // not part of the group means just that photo. One pick counts as one,
        // so a plain click needs no special case.
        let group = line.targets(including: id)
        let count = group.count
        /// "Save to Desktop · 3 photos" while a group is picked out. The
        /// title is localized before it gets here, so the translation checker
        /// still sees every key.
        func counted(_ title: String) -> String {
            guard count > 1 else { return title }
            return title + " · " + String(format: L("%d photos"), count)
        }
        let menu = NSMenu()
        // Items say themselves whether they can be used.
        menu.autoenablesItems = false
        menu.addItem(ClosureMenuItem(counted(L("Copy"))) { line.copy(id) })
        menu.addItem(CopyAllImagesMenu.make(for: line))
        menu.addItem(ClosureMenuItem(counted(L("Open"))) { line.open(id) })
        // One photo each: Quick Look already pages through the whole line, and
        // Markup edits the one file it was given.
        menu.addItem(ClosureMenuItem(L("Quick Look")) { line.quickLook(id) })
        if !item.isRecording {
            menu.addItem(ClosureMenuItem(L("Markup")) { line.markup(id) })
        }
        menu.addItem(ClosureMenuItem(counted(L("Show in Finder"))) { line.reveal(id) })
        // Only offered when every file is still where the line says it is.
        let airdrop = ClosureMenuItem(counted(L("Send via AirDrop"))) { line.airdrop(id) }
        airdrop.isEnabled = !group.isEmpty
            && group.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) }
        menu.addItem(airdrop)
        let inInbox = group.contains { line.isInInbox($0.id) }
        if inInbox {
            menu.addItem(ClosureMenuItem(counted(L("Save to Desktop"))) { line.saveToDesktop(id) })
        }
        menu.addItem(.separator())
        if inInbox {
            menu.addItem(ClosureMenuItem(counted(L("Discard"))) { line.discardGroup(id) })
        } else {
            menu.addItem(ClosureMenuItem(counted(L("Take down"))) { line.discardGroup(id) })
            menu.addItem(ClosureMenuItem(counted(L("Move to Trash"))) { line.trashGroup(id) })
        }
        // One side at a time only means something for a single photo: with
        // three picked out, "everything to the left" is a question about which
        // of the three, so both are offered only when one is picked.
        // No count on these two: they are about one side of one photo.
        let left = ClosureMenuItem(L("Take down everything to the left")) { line.takeDown(id, toTheLeft: true) }
        left.isEnabled = count == 1 && !line.neighbours(of: id, toTheLeft: true).isEmpty
        menu.addItem(left)
        let right = ClosureMenuItem(L("Take down everything to the right")) { line.takeDown(id, toTheLeft: false) }
        right.isEnabled = count == 1 && !line.neighbours(of: id, toTheLeft: false).isEmpty
        menu.addItem(right)
        // The whole line, this photo included. Same way out as the corner
        // cross: a file from the line's own folder goes to the Trash, one from
        // anywhere else just leaves the line.
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(L("Take everything down")) { line.clear() })
        return menu
    }
}

final class GrabView: NSView, NSDraggingSource {
    static var isDragging = false
    /// A photo's menu is open. It reaches past the line, so the line waits.
    static var isShowingMenu = false

    var url: URL?
    var dragImage: NSImage?
    // Every callback runs on the main thread: AppKit calls these from within
    // event handling. Saying so explicitly lets the closures reach the line,
    // which lives on the main actor, and keeps older compilers happy.
    /// Shift and command, as they were when the button went down.
    var onPress: @MainActor (_ shift: Bool, _ command: Bool) -> Void = { _, _ in }
    /// The button came up. `dragged` says whether it turned into a drag.
    var onSettle: @MainActor (_ dragged: Bool) -> Void = { _ in }
    /// What this drag should carry: one photo, or everything picked out.
    var dragEntries: @MainActor () -> [(url: URL, image: NSImage?)] = { [] }
    var onDoubleClick: @MainActor () -> Void = {}
    var onDragStart: @MainActor () -> Void = {}
    var onDragEnd: @MainActor () -> Void = {}
    var onTrash: @MainActor () -> Void = {}
    var onDiscard: @MainActor () -> Void = {}
    var onLongPress: @MainActor () -> Void = {}
    var onForceClick: @MainActor () -> Void = {}
    var onMiddleClick: @MainActor () -> Void = {}
    var onPressChange: @MainActor (Bool) -> Void = { _ in }
    var menuProvider: @MainActor () -> NSMenu = { NSMenu() }

    private var downPoint: NSPoint?
    private var startedDrag = false
    private var holdTimer: Timer?
    private var didLongPress = false

    /// How long you hold before Markup opens. Long enough not to fire on a
    /// slow click, short enough to feel deliberate.
    private static let holdDuration: TimeInterval = 0.45

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The discard cross drawn in the top left corner of the card. It is
    /// handled here because this view sits on top of the SwiftUI card.
    static let crossHitSize: CGFloat = 26

    private func isInCross(_ event: NSEvent) -> Bool {
        let p = convert(event.locationInWindow, from: nil)
        let corner = NSRect(x: 0, y: isFlipped ? 0 : bounds.height - Self.crossHitSize,
                            width: Self.crossHitSize, height: Self.crossHitSize)
        return corner.contains(p)
    }

    override func mouseDown(with event: NSEvent) {
        if isInCross(event) {
            downPoint = nil
            onDiscard()
            return
        }
        if event.clickCount == 2 {
            downPoint = nil
            onDoubleClick()
            return
        }
        // Picking happens on the way down, as it does in the Finder: a drag
        // that follows must already know what it is carrying.
        onPress(event.modifierFlags.contains(.shift), event.modifierFlags.contains(.command))
        downPoint = event.locationInWindow
        startedDrag = false
        didLongPress = false
        onPressChange(true)
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: Self.holdDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.downPoint != nil, !self.startedDrag else { return }
                self.didLongPress = true
                self.onPressChange(false)
                self.onLongPress()
            }
        }
    }

    /// A force click on a trackpad opens Quick Look, as it does in Finder.
    /// It counts instead of the click and of a long press.
    override func pressureChange(with event: NSEvent) {
        guard event.stage == 2, downPoint != nil, !startedDrag, !didLongPress else { return }
        didLongPress = true
        endPress()
        onForceClick()
    }

    private func endPress() {
        holdTimer?.invalidate()
        holdTimer = nil
        onPressChange(false)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downPoint, !startedDrag else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 4, !didLongPress else { return }

        // Everything picked out travels together; a photo that is not part of
        // the selection travels alone.
        var payload = dragEntries()
        if payload.isEmpty, let url { payload = [(url, dragImage)] }
        guard !payload.isEmpty else { return }
        startedDrag = true
        endPress()

        var items: [NSDraggingItem] = []
        for (n, entry) in payload.enumerated() {
            let item = NSDraggingItem(pasteboardWriter: entry.url as NSURL)
            // The cards behind peek out a little, so the drag reads as a
            // stack rather than one photo.
            let step = CGFloat(min(n, 3))
            let frame = imageFrame()
                .insetBy(dx: step * 3, dy: step * 3)
                .offsetBy(dx: step * 7, dy: -step * 7)
            item.setDraggingFrame(frame, contents: n == 0 ? dragImage : entry.image)
            items.append(item)
        }
        let session = beginDraggingSession(with: items, event: event, source: self)
        // Released where nothing accepts it: it flies back to the line.
        session.animatesToStartingPositionsOnCancelOrFail = true
        GrabView.isDragging = true
        onDragStart()
    }

    override func mouseUp(with event: NSEvent) {
        // The pick already happened on the way down; letting go changes
        // nothing. Copying moved to the menu, so a click no longer touches the
        // clipboard.
        endPress()
        onSettle(startedDrag)
        downPoint = nil
        didLongPress = false
    }

    override func rightMouseDown(with event: NSEvent) {
        // The menu runs until it closes, and the line stays down meanwhile.
        GrabView.isShowingMenu = true
        NSMenu.popUpContextMenu(menuProvider(), with: event, for: self)
        GrabView.isShowingMenu = false
    }

    /// The middle button, for mice that have one. Markup is the one thing a
    /// mouse cannot reach any other way now that holding the button looks at
    /// the photo; a trackpad reaches it with a force click instead.
    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else {
            super.otherMouseDown(with: event)
            return
        }
        onMiddleClick()
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Apps pick copy. Finder picks move, so a folder or the Desktop keeps
        // the file. Delete is what lets the Dock's Trash accept it.
        context == .outsideApplication ? [.copy, .move, .delete] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        GrabView.isDragging = false
        startedDrag = false
        downPoint = nil
        log.notice("Drag ended with operation \(operation.rawValue, privacy: .public)")
        // Dropped on the Trash: macOS only tells us, we move the file.
        if operation.contains(.delete) {
            onDragEnd()
            onTrash()
            return
        }
        onDragEnd()
        // Finder finishes a move a moment later. Check again then, so a photo
        // saved into a folder leaves the line.
        if operation.contains(.move) {
            let done = onDragEnd
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { done() }
        }
    }

    /// The drag preview keeps the photo's aspect ratio inside the card.
    private func imageFrame() -> NSRect {
        guard let size = dragImage?.size, size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return NSRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, key: String = "", handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { MainActor.assumeIsolated { handler() } }
}
