import AppKit
import Carbon.HIToolbox
import MacStartCore
import SwiftUI
import os

/// Shows and hides the overlay, and turns the user's actions in it into launches, page changes, and dismissals.
@MainActor
final class OverlayController: NSObject, NSWindowDelegate {
    /// The length of the show and hide animations, in seconds.
    static let animationDuration = 0.2
    /// The shortest time between two page turns from a mouse wheel, so one flick turns one page.
    private static let wheelPageTurnInterval = 0.3

    let state = OverlayState()
    private let store: LayoutStore
    private let icons: IconProvider
    private let launcher: AppLauncher
    private lazy var panel = makePanel()
    private lazy var drags = DragCoordinator(store: store, state: state) { [weak self] page in
        self?.showPage(page)
    }
    /// Bumped on every show and hide, so a hide that finishes late cannot close a panel shown again meanwhile.
    private var visibilityGeneration = 0
    private var scrollMonitor: Any?
    private var keyMonitor: Any?
    private var lastWheelPageTurn = Date.distantPast
    /// The last app other than MacStart that was active. It gets the focus back when the overlay closes while
    /// MacStart is active, for example after a click on the Dock icon.
    private var previousApp: NSRunningApplication?
    private let logger = LogArea.overlay.logger

    init(store: LayoutStore, icons: IconProvider, launcher: AppLauncher) {
        self.store = store
        self.icons = icons
        self.launcher = launcher
        super.init()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func toggle() {
        if state.isPresented {
            hide()
        } else {
            show()
        }
    }

    /// Shows the overlay on the main display, the one with the menu bar.
    func show() {
        guard let screen = NSScreen.screens.first else {
            logger.error("No display to show the overlay on")
            return
        }
        visibilityGeneration += 1
        panel.setFrame(screen.frame, display: false)
        state.clampPage(toPageCount: store.layout.pages.count)

        if !panel.isVisible {
            panel.contentView?.alphaValue = 0
        }
        panel.makeKeyAndOrderFront(nil)
        state.isPresented = true
        fadeContent(toVisible: true)
        installEventMonitors()
        state.searchFocusRequest += 1
        logger.debug(
            "Overlay shown, frame \(NSStringFromRect(self.panel.frame), privacy: .public), screen \(NSStringFromRect(screen.frame), privacy: .public)"
        )
    }

    /// Hides the overlay. With `restoringFocus`, the previous app gets the focus back if MacStart took it.
    func hide(restoringFocus: Bool = true) {
        guard state.isPresented else {
            return
        }
        state.isPresented = false
        drags.cancel()
        removeEventMonitors()
        visibilityGeneration += 1
        let generation = visibilityGeneration

        fadeContent(toVisible: false)
        guard !Self.reduceMotion else {
            finishHiding(generation: generation, restoringFocus: restoringFocus)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(Self.animationDuration))
            finishHiding(generation: generation, restoringFocus: restoringFocus)
        }
        logger.debug("Overlay hiding, restoring focus: \(restoringFocus)")
    }

    private func finishHiding(generation: Int, restoringFocus: Bool) {
        guard generation == visibilityGeneration else {
            return
        }
        panel.orderOut(nil)
        state.reset()
        logger.debug("Overlay ordered out")
        if restoringFocus, NSApp.isActive {
            previousApp?.activate()
        }
    }

    /// Fades the panel's content in or out. The final opacity is set first and the fade only animates the way
    /// there, so the overlay ends up right even when no animation runs, for example while the display sleeps.
    /// The window's own alpha is never animated: `NSWindow.animator()` can leave it stuck at the start value.
    private func fadeContent(toVisible isVisible: Bool) {
        guard let content = panel.contentView else {
            return
        }
        let target: CGFloat = isVisible ? 1 : 0
        let start = content.layer?.presentation()?.opacity ?? Float(content.alphaValue)
        content.alphaValue = target
        guard !Self.reduceMotion, let layer = content.layer else {
            return
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = start
        fade.toValue = Float(target)
        fade.duration = Self.animationDuration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "fade")
    }

    /// Scrolls to a page, clamped to the existing pages.
    func showPage(_ index: Int) {
        let pageCount = store.layout.pages.count
        guard pageCount > 0 else {
            return
        }
        let page = min(max(index, 0), pageCount - 1)
        withAnimation(Self.reduceMotion ? nil : .easeInOut(duration: 0.3)) {
            state.currentPage = page
        }
    }

    private func turnPage(by offset: Int) {
        showPage((state.currentPage ?? 0) + offset)
    }

    private func launch(_ app: InstalledApp) {
        guard !drags.suppressesClick else {
            return
        }
        hide(restoringFocus: false)
        Task {
            do {
                try await launcher.launch(app)
            } catch {
                presentLaunchFailure(of: app, error: error)
            }
        }
    }

    private func presentLaunchFailure(of app: InstalledApp, error: any Error) {
        logger.error("Cannot open \(app.id.path): \(String(describing: error))")
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Cannot open \(app.displayName)"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    // MARK: - Input

    /// Watches the keyboard and the mouse wheel while the overlay is open. Local monitors see key presses
    /// before the search field does, so the arrow keys, Return, and Escape act on the grid even while the field
    /// has the focus. Every other key goes on to the field.
    private func installEventMonitors() {
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let keyCode = Int(event.keyCode)
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    .subtracting([.function, .numericPad, .capsLock])
                // Local monitors run on the main thread.
                let isHandled = MainActor.assumeIsolated {
                    self?.handleKey(keyCode: keyCode, hasModifiers: !modifiers.isEmpty) ?? false
                }
                return isHandled ? nil : event
            }
        }
        installScrollMonitor()
    }

    private func removeEventMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        removeScrollMonitor()
    }

    /// Handles a key press that the search field must not get. Returns true when the key was used.
    private func handleKey(keyCode: Int, hasModifiers: Bool) -> Bool {
        // While an input method composes text, its keys belong to the input method.
        guard panel.isKeyWindow, !hasModifiers, !isComposingText else {
            return false
        }
        if state.drag != nil {
            guard keyCode == kVK_Escape else {
                return false
            }
            drags.cancel()
            return true
        }
        if state.openFolderID != nil {
            return handleFolderKey(keyCode: keyCode)
        }
        switch keyCode {
        case kVK_Escape:
            clearSearchOrHide()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            activateSelection()
        case kVK_LeftArrow:
            moveSelection(.left)
        case kVK_RightArrow:
            moveSelection(.right)
        case kVK_UpArrow:
            moveSelection(.up)
        case kVK_DownArrow:
            moveSelection(.down)
        default:
            return false
        }
        return true
    }

    private var isComposingText: Bool {
        (panel.firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }

    /// Escape clears the search first, and closes the overlay when there is nothing to clear.
    private func clearSearchOrHide() {
        if state.query.isEmpty {
            hide()
        } else {
            state.query = ""
        }
    }

    /// Moves the keyboard selection through the search results, or through the pages of the grid.
    private func moveSelection(_ direction: GridDirection) {
        let itemCounts =
            state.isSearching
            ? [store.searchResults(matching: state.query).count] : store.layout.pages.map(\.items.count)
        let page = state.isSearching ? 0 : (state.currentPage ?? 0)
        let navigation = GridNavigation(columns: store.preferences.gridColumns, itemCounts: itemCounts)
        guard let next = navigation.position(after: direction, from: state.selection, onPage: page) else {
            return
        }
        state.selection = next
        if !state.isSearching, next.page != page {
            showPage(next.page)
        }
    }

    /// Return launches the selected app. While searching, it launches the best result when nothing is selected.
    private func activateSelection() {
        if state.isSearching {
            let results = store.searchResults(matching: state.query)
            let slot = state.selection?.slot ?? 0
            if results.indices.contains(slot) {
                launch(results[slot])
            }
            return
        }
        guard
            let selection = state.selection,
            selection.page == state.currentPage,
            store.layout.pages.indices.contains(selection.page)
        else {
            return
        }
        let items = store.layout.pages[selection.page].items
        guard items.indices.contains(selection.slot) else {
            return
        }
        switch items[selection.slot] {
        case .app(let id):
            if let app = store.app(for: id) {
                launch(app)
            }
        case .folder(let folder):
            openFolder(folder.id)
        }
    }

    // MARK: - Folders

    /// Keys while a folder is open. Escape closes it. While its name is being edited, every other key goes to the
    /// name field; otherwise the arrow keys move the selection through the folder and Return launches the app.
    private func handleFolderKey(keyCode: Int) -> Bool {
        if keyCode == kVK_Escape {
            closeFolder()
            return true
        }
        guard !state.isEditingFolderName else {
            return false
        }
        switch keyCode {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            launchFolderSelection()
        case kVK_LeftArrow:
            moveFolderSelection(.left)
        case kVK_RightArrow:
            moveFolderSelection(.right)
        case kVK_UpArrow:
            moveFolderSelection(.up)
        case kVK_DownArrow:
            moveFolderSelection(.down)
        default:
            return false
        }
        return true
    }

    private func openFolder(_ id: UUID) {
        guard !drags.suppressesClick else {
            return
        }
        state.openFolder(id)
    }

    /// Closes the open folder and gives the keyboard back to the search field.
    private func closeFolder() {
        state.closeFolder()
        state.searchFocusRequest += 1
    }

    private func moveFolderSelection(_ direction: GridDirection) {
        guard let folderID = state.openFolderID, let folder = store.folder(withID: folderID) else {
            return
        }
        // The same column count as the folder panel.
        let columns = min(max(folder.apps.count, 1), store.preferences.gridColumns)
        let navigation = GridNavigation(columns: columns, itemCounts: [folder.apps.count])
        let current = state.folderSelection.map { GridPosition(page: 0, slot: $0) }
        if let next = navigation.position(after: direction, from: current, onPage: 0) {
            state.folderSelection = next.slot
        }
    }

    private func launchFolderSelection() {
        guard
            let folderID = state.openFolderID,
            let folder = store.folder(withID: folderID),
            let index = state.folderSelection,
            folder.apps.indices.contains(index),
            let app = store.app(for: folder.apps[index])
        else {
            return
        }
        launch(app)
    }

    /// Shows the app in Finder. Finder takes the focus, which closes the overlay.
    private func showInFinder(_ app: InstalledApp) {
        hide(restoringFocus: false)
        NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: app.id.path)])
    }

    /// Takes a key press that reached the panel itself, which happens when the search field lost the focus.
    /// Typed text goes to the search, and the field gets the focus back. Returns true when the key was used.
    private func handleUnfocusedKey(_ event: NSEvent) -> Bool {
        guard !event.modifierFlags.contains(.command) else {
            return false
        }
        if let characters = event.characters,
            characters.contains(where: { $0.isLetter || $0.isNumber || $0.isPunctuation || $0.isSymbol })
        {
            state.query += characters
            state.searchFocusRequest += 1
        }
        // Other plain keys are swallowed, so the panel does not beep.
        return true
    }

    /// Turns pages with a mouse wheel. Trackpads and the Magic Mouse scroll precisely, and the paged scroll view
    /// handles their swipes itself.
    private func installScrollMonitor() {
        guard scrollMonitor == nil else {
            return
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard !event.hasPreciseScrollingDeltas else {
                return event
            }
            let delta =
                abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? event.scrollingDeltaY : event.scrollingDeltaX
            guard delta != 0 else {
                return event
            }
            // Local monitors run on the main thread.
            MainActor.assumeIsolated { self?.turnPageForWheel(delta: delta) }
            return nil
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    private func turnPageForWheel(delta: CGFloat) {
        let now = Date.now
        guard now.timeIntervalSince(lastWheelPageTurn) >= Self.wheelPageTurnInterval else {
            return
        }
        lastWheelPageTurn = now
        turnPage(by: delta < 0 ? 1 : -1)
    }

    // MARK: - Window and system events

    func windowDidResignKey(_ notification: Notification) {
        // Another app or window took the focus.
        logger.debug("Overlay lost key focus")
        hide()
    }

    @objc private func activeSpaceDidChange() {
        logger.debug("Active Space changed")
        hide()
    }

    @objc private func applicationDidActivate(_ notification: Notification) {
        guard
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            return
        }
        previousApp = app
    }

    @objc private func screenParametersDidChange() {
        if state.isPresented, let screen = NSScreen.screens.first {
            panel.setFrame(screen.frame, display: true)
        }
    }

    // MARK: - Setup

    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel(contentRect: NSScreen.screens.first?.frame ?? .zero)
        panel.delegate = self
        panel.onKeyDown = { [weak self] event in
            self?.handleUnfocusedKey(event) ?? false
        }
        let actions = OverlayActions(
            launch: { [weak self] app in self?.launch(app) },
            dismiss: { [weak self] in self?.hide() },
            showPage: { [weak self] page in self?.showPage(page) },
            openFolder: { [weak self] id in self?.openFolder(id) },
            closeFolder: { [weak self] in self?.closeFolder() },
            renameFolder: { [weak self] id, name in self?.store.renameFolder(id, to: name) },
            removeFromFolder: { [weak self] id, index in self?.store.removeApp(fromFolder: id, at: index) },
            showInFinder: { [weak self] app in self?.showInFinder(app) },
            hide: { [weak self] app in self?.store.hide(app.id) },
            dragChanged: { [weak self] update in self?.drags.update(update) },
            dragEnded: { [weak self] in self?.drags.end() }
        )
        panel.setContent(OverlayView(store: store, state: state, icons: icons, actions: actions))
        return panel
    }
}
