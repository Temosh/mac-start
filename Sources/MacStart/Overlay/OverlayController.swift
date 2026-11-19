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
    private lazy var drags = DragCoordinator(store: store, state: state) { [weak self] page, changes in
        self?.showPage(page, alongWith: changes)
    }
    /// Bumped on every show and hide, so a hide that finishes late cannot close a panel shown again meanwhile.
    private var visibilityGeneration = 0
    private var scrollMonitor: Any?
    private var keyMonitor: Any?
    private var lastWheelPageTurn = Date.distantPast
    /// The two-finger swipe in progress.
    private var swipe: PageSwipeTracking?
    /// The last app other than MacStart that was active. It gets the focus back when the overlay closes while
    /// MacStart is active, for example after a click on the Dock icon.
    private var previousApp: NSRunningApplication?
    private let logger = LogArea.overlay.logger

    /// Opens the settings window, which closes the overlay.
    private let openSettings: @MainActor () -> Void

    init(
        store: LayoutStore,
        icons: IconProvider,
        launcher: AppLauncher,
        openSettings: @escaping @MainActor () -> Void
    ) {
        self.store = store
        self.icons = icons
        self.launcher = launcher
        self.openSettings = openSettings
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
        prewarmIcons()
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

    /// Draws the grid's icons in the background, so showing the overlay does not draw them: every placed app at
    /// the grid's icon size, and the first nine apps of each folder at the folder icon's small size.
    func prewarmIcons() {
        guard let screen = NSScreen.screens.first else {
            return
        }
        let metrics = GridMetrics(
            overlaySize: screen.frame.size,
            columns: store.preferences.gridColumns,
            rows: store.preferences.gridRows
        )
        let miniSide = FolderIcon.miniSide(forSide: metrics.iconSize)
        var requests: [(app: InstalledApp, side: CGFloat)] = []
        for item in store.layout.pages.flatMap(\.items) {
            switch item {
            case .app(let id):
                if let app = store.app(for: id) {
                    requests.append((app, metrics.iconSize))
                }
            case .folder(let folder):
                for id in folder.apps.prefix(9) {
                    if let app = store.app(for: id) {
                        requests.append((app, miniSide))
                    }
                }
            }
        }
        Task {
            await icons.prewarm(requests)
        }
    }

    /// The spring that settles the pages.
    private static let pageSpring = Spring(response: 0.32, dampingRatio: 0.88)

    /// Moves to a page, clamped to the existing pages, with a spring from wherever a swipe left the pages.
    /// `velocity` is how fast the pages were moving, in points per second, so the spring carries a flick on
    /// instead of starting from rest. `changes` run in the same transaction as the page turn; see
    /// `turnPage(initialVelocity:after:)`.
    func showPage(_ index: Int, velocity: CGFloat = 0, alongWith changes: () -> Void = {}) {
        // During a drag, the changes can add the new page after the last one, so one more page is allowed here;
        // the turn clamps again once the changes are made.
        let lastPage = max(store.layout.pages.count - 1, 0) + (state.drag == nil ? 0 : 1)
        let page = min(max(index, 0), lastPage)
        let start = -CGFloat(state.currentPage) * panel.frame.width + state.pageOffset
        let distance = -CGFloat(page) * panel.frame.width - start
        // The spring takes its starting speed relative to the distance it covers.
        let relativeVelocity = abs(distance) >= 1 ? min(max(velocity / distance, -20), 20) : 0
        turnPage(initialVelocity: relativeVelocity) {
            changes()
            return page
        }
    }

    /// Makes `change`, which returns the page to show once it is made, and turns to that page in the same
    /// transaction. A change made apart from the turn, just before it, could make SwiftUI draw the pager with the
    /// old page and then miss the new one, so the pages stayed put.
    private func turnPage(initialVelocity: CGFloat = 0, after change: () -> Int?) {
        let animation: Animation? =
            Self.reduceMotion ? nil : .interpolatingSpring(Self.pageSpring, initialVelocity: initialVelocity)
        withAnimation(animation) {
            guard let page = change() else {
                return
            }
            // Clamped after the change, which can add or remove pages, or the new page a drag waits on.
            state.currentPage = min(max(page, 0), lastShownPage)
            state.pageOffset = 0
        }
    }

    private func turnPage(by offset: Int) {
        showPage(state.currentPage + offset)
    }

    /// The last page the pager shows: the layout's last page, or the new page a drag waits on after it.
    private var lastShownPage: Int {
        max(store.layout.pages.count - 1, 0) + (state.drag?.isOnNewPage == true ? 1 : 0)
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
                // The overlay does not make MacStart the active app, so the menu bar never sees Command-Comma.
                let isSettingsShortcut = modifiers == .command && event.charactersIgnoringModifiers == ","
                let isSelectAllShortcut = modifiers == .command && event.charactersIgnoringModifiers == "a"
                // Local monitors run on the main thread.
                let isHandled = MainActor.assumeIsolated {
                    guard let self, self.panel.isKeyWindow else {
                        return false
                    }
                    if isSettingsShortcut {
                        self.openSettings()
                        return true
                    }
                    // In edit mode, Command-A selects items. Otherwise it selects the search text.
                    if isSelectAllShortcut, self.state.isEditing, !self.state.isEditingFolderName,
                        self.state.drag == nil
                    {
                        self.selectAllShown()
                        return true
                    }
                    return self.handleKey(keyCode: keyCode, hasModifiers: !modifiers.isEmpty)
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
        if state.drag != nil || drags.isSelectingRectangle {
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
            handleEscape()
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

    /// Escape clears the search first, then leaves edit mode, and closes the overlay when nothing else is left.
    private func handleEscape() {
        if !state.query.isEmpty {
            state.query = ""
        } else if state.isEditing {
            state.endEditing()
        } else {
            hide()
        }
    }

    /// A click on empty space closes the overlay. In edit mode it does nothing, so a stray click keeps the
    /// selection; Deselect All clears it.
    private func dismiss() {
        guard !state.isEditing else {
            return
        }
        hide()
    }

    /// Moves the keyboard selection through the search results, or through the pages of the grid.
    private func moveSelection(_ direction: GridDirection) {
        let itemCounts =
            state.isSearching
            ? [store.searchResults(matching: state.query).count] : store.layout.pages.map(\.items.count)
        let page = state.isSearching ? 0 : state.currentPage
        let navigation = GridNavigation(columns: store.preferences.gridColumns, itemCounts: itemCounts)
        guard let next = navigation.position(after: direction, from: state.selection, onPage: page) else {
            return
        }
        guard !state.isSearching, next.page != page else {
            state.selection = next
            return
        }
        showPage(next.page) { state.selection = next }
    }

    /// Return opens the selected item, or selects it in edit mode. While searching, it opens the best result when
    /// nothing is selected.
    private func activateSelection() {
        if state.isSearching {
            let results = store.searchResults(matching: state.query)
            let slot = state.selection?.slot ?? 0
            if results.indices.contains(slot) {
                open(.app(results[slot].id))
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
        open(items[selection.slot])
    }

    /// A click on a tile. In edit mode, or with Command, it selects the tile, and Shift selects the range from the
    /// last clicked tile. Otherwise it launches the app or opens the folder.
    private func click(_ item: Item) {
        guard !drags.suppressesClick else {
            return
        }
        let modifiers = NSEvent.modifierFlags
        if state.isEditing, case .folder(let folder) = item, !modifiers.contains(.shift) {
            // In edit mode a click opens a folder, as outside it. The folder's badge selects it.
            openFolder(folder.id)
            return
        }
        if state.isEditing || modifiers.contains(.command) {
            if !state.isEditing {
                beginEditing()
            }
            if modifiers.contains(.shift) {
                extendEditSelection(to: item.id)
            } else {
                toggleEditSelection(item.id)
            }
            return
        }
        open(item)
    }

    /// A click on a tile's badge in edit mode: selects or deselects the tile, and Shift selects the range from the
    /// last clicked tile.
    private func select(_ item: Item) {
        guard state.isEditing else {
            return
        }
        if NSEvent.modifierFlags.contains(.shift) {
            extendEditSelection(to: item.id)
        } else {
            toggleEditSelection(item.id)
        }
    }

    /// Launches an app or opens a folder. In edit mode it selects the item instead.
    private func open(_ item: Item) {
        if state.isEditing {
            toggleEditSelection(item.id)
            return
        }
        switch item {
        case .app(let id):
            if let app = store.app(for: id) {
                launch(app)
            }
        case .folder(let folder):
            openFolder(folder.id)
        }
    }

    // MARK: - Edit mode

    private func toggleEditing() {
        if state.isEditing {
            state.endEditing()
        } else {
            beginEditing()
        }
    }

    /// Enters edit mode. An open folder stays open, and its apps can be selected.
    private func beginEditing() {
        state.isEditing = true
    }

    private func toggleEditSelection(_ id: Item.ID) {
        if state.editSelection.remove(id) == nil {
            state.editSelection.insert(id)
        }
        state.editSelectionAnchor = id
    }

    /// Selects every item from the last clicked one to `id`, in the order the overlay shows them.
    private func extendEditSelection(to id: Item.ID) {
        let order = shownItemIDs
        guard
            let anchor = state.editSelectionAnchor,
            let start = order.firstIndex(of: anchor),
            let end = order.firstIndex(of: id)
        else {
            toggleEditSelection(id)
            return
        }
        state.editSelection.formUnion(order[min(start, end)...max(start, end)])
    }

    private func clearEditSelection() {
        state.editSelection = []
        state.editSelectionAnchor = nil
    }

    /// The items edit mode can select, in the order the overlay shows them: the search results, or every page.
    private var shownItemIDs: [Item.ID] {
        if let folder = openFolder {
            return folder.apps.map { .app($0) }
        }
        if state.isSearching {
            return store.searchResults(matching: state.query).map { .app($0.id) }
        }
        return store.layout.pages.flatMap(\.items).map(\.id)
    }

    /// Selects every app of the open folder, every search result, or every item on the current page.
    private func selectAllShown() {
        if openFolder != nil || state.isSearching {
            state.editSelection.formUnion(shownItemIDs)
        } else if store.layout.pages.indices.contains(state.currentPage) {
            state.editSelection.formUnion(store.layout.pages[state.currentPage].items.map(\.id))
        }
    }

    private var openFolder: Folder? {
        state.openFolderID.flatMap { store.folder(withID: $0) }
    }

    /// Closes the open folder when an edit left it with fewer than two apps, so it no longer exists.
    private func closeFolderIfGone() {
        if state.openFolderID != nil, openFolder == nil {
            closeFolder()
        }
    }

    /// Moves items to the end of a page and turns to where they landed, in one transaction. An open folder closes,
    /// because the pages behind it are about to move.
    private func moveItems(_ ids: Set<Item.ID>, toPage page: Int, alongWith changes: () -> Void = {}) {
        turnPage {
            // A page without room for the items takes none of them, and nothing else changes either.
            guard store.moveItems(ids, toPage: page) else {
                return nil
            }
            if state.openFolderID != nil {
                closeFolder()
            }
            changes()
            // Emptied pages are gone now, so the page of the first moved item tells where they went.
            return store.layout.pages.firstIndex { candidate in
                candidate.items.contains { ids.contains($0.id) }
            }
        }
    }

    /// Applies an edit action to the selected items, then clears the selection and shows where they went.
    private func performEdit(_ action: EditAction) {
        let selection = state.editSelection
        let apps = selectedApps
        switch action {
        case .newFolder:
            turnPage {
                guard let folderID = store.makeFolder(of: apps) else {
                    return nil
                }
                clearEditSelection()
                return store.layout.position(ofFolder: folderID)?.page
            }
        case .moveToPage(let page):
            moveItems(selection, toPage: page, alongWith: clearEditSelection)
        case .hide:
            store.hide(apps)
            clearEditSelection()
            closeFolderIfGone()
        case .removeFromFolder:
            guard let folderID = state.openFolderID, store.removeApps(apps, fromFolder: folderID) else {
                return
            }
            clearEditSelection()
            closeFolderIfGone()
        case .deselectAll:
            clearEditSelection()
        }
    }

    /// The apps in the edit selection.
    private var selectedApps: Set<AppID> {
        Set(
            state.editSelection.compactMap { id -> AppID? in
                if case .app(let appID) = id {
                    return appID
                }
                return nil
            }
        )
    }

    /// True when an edit action fits, since no edit pushes items to the next page.
    private func canPerformEdit(_ action: EditAction) -> Bool {
        let capacity = store.preferences.pageCapacity
        switch action {
        case .newFolder:
            return store.layout.canMakeFolder(of: selectedApps, pageCapacity: capacity)
        case .moveToPage(let page):
            return store.layout.canMoveItems(state.editSelection, toPage: page, pageCapacity: capacity)
        case .removeFromFolder:
            guard let folderID = state.openFolderID else {
                return false
            }
            return store.layout.canRemoveApps(selectedApps, fromFolder: folderID, pageCapacity: capacity)
        case .hide, .deselectAll:
            return true
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
            openFolderSelection()
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

    /// Return in a folder launches the selected app, or selects it in edit mode.
    private func openFolderSelection() {
        guard
            let folder = openFolder,
            let index = state.folderSelection,
            folder.apps.indices.contains(index)
        else {
            return
        }
        open(.app(folder.apps[index]))
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

    /// Turns pages with two-finger swipes and mouse wheels while the grid shows.
    private func installScrollMonitor() {
        guard scrollMonitor == nil else {
            return
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let input = ScrollInput(event)
            // Local monitors run on the main thread.
            let isHandled = MainActor.assumeIsolated { self?.handleScroll(input) ?? false }
            return isHandled ? nil : event
        }
    }

    /// A swipe moves the pages with the fingers and, when the fingers lift, settles on a page: a short flick is
    /// enough to turn it. A mouse wheel turns one page per notch.
    private func handleScroll(_ input: ScrollInput) -> Bool {
        guard state.drag == nil, state.openFolderID == nil, !state.isSearching else {
            return false
        }
        // Mouse wheels, and devices that scroll smoothly without gesture phases, turn pages notch by notch.
        guard input.isPrecise, !(input.phase.isEmpty && input.momentumPhase.isEmpty) else {
            let delta = abs(input.deltaY) >= abs(input.deltaX) ? input.deltaY : input.deltaX
            if delta != 0 {
                turnPageForWheel(delta: delta)
            }
            return true
        }
        // The swipe decided its page when the fingers lifted; momentum would only drag the pages further.
        guard input.momentumPhase.isEmpty else {
            return true
        }
        if input.phase.contains(.began) {
            swipe = PageSwipeTracking()
        }
        if input.phase.contains(.changed), var tracking = swipe {
            tracking.add(deltaX: input.deltaX, deltaY: input.deltaY, time: input.time)
            swipe = tracking
            if tracking.isHorizontal == true {
                state.pageOffset = rubberBanded(tracking.offset)
            }
        }
        if input.phase.contains(.ended) || input.phase.contains(.cancelled), let tracking = swipe {
            swipe = nil
            finishSwipe(tracking, endedAt: input.time, isCancelled: input.phase.contains(.cancelled))
        }
        return true
    }

    /// Past the first or the last page, the pages follow the fingers only a third of the way.
    private func rubberBanded(_ offset: CGFloat) -> CGFloat {
        let isPastFirst = state.currentPage == 0 && offset > 0
        let isPastLast = state.currentPage >= store.layout.pages.count - 1 && offset < 0
        return isPastFirst || isPastLast ? offset / 3 : offset
    }

    private func finishSwipe(_ tracking: PageSwipeTracking, endedAt time: TimeInterval, isCancelled: Bool) {
        guard tracking.isHorizontal == true else {
            return
        }
        let velocity = tracking.velocity(at: time)
        let page =
            isCancelled
            ? state.currentPage
            : PageSwipe.targetPage(
                from: state.currentPage,
                pageCount: store.layout.pages.count,
                offset: Double(tracking.offset),
                velocity: Double(velocity),
                pageWidth: Double(panel.frame.width)
            )
        showPage(page, velocity: isCancelled ? 0 : velocity)
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
            click: { [weak self] item in self?.click(item) },
            dismiss: { [weak self] in self?.dismiss() },
            showPage: { [weak self] page in self?.showPage(page) },
            moveItems: { [weak self] ids, page in self?.moveItems(ids, toPage: page) },
            canMoveItems: { [weak self] ids, page in
                guard let self else {
                    return false
                }
                return store.layout.canMoveItems(ids, toPage: page, pageCapacity: store.preferences.pageCapacity)
            },
            closeFolder: { [weak self] in self?.closeFolder() },
            renameFolder: { [weak self] id, name in self?.store.renameFolder(id, to: name) },
            removeFromFolder: { [weak self] id, index in
                self?.store.removeApp(fromFolder: id, at: index)
                self?.closeFolderIfGone()
            },
            canRemoveFromFolder: { [weak self] id, index in
                guard let self, let folder = store.folder(withID: id), folder.apps.indices.contains(index) else {
                    return false
                }
                return store.layout.canRemoveApps(
                    [folder.apps[index]],
                    fromFolder: id,
                    pageCapacity: store.preferences.pageCapacity
                )
            },
            showInFinder: { [weak self] app in self?.showInFinder(app) },
            hide: { [weak self] app in self?.store.hide(app.id) },
            openSettings: openSettings,
            toggleEditing: { [weak self] in self?.toggleEditing() },
            select: { [weak self] item in self?.select(item) },
            performEdit: { [weak self] action in self?.performEdit(action) },
            canPerformEdit: { [weak self] action in self?.canPerformEdit(action) ?? false },
            dragChanged: { [weak self] update in self?.drags.update(update) },
            dragEnded: { [weak self] in self?.drags.end() }
        )
        panel.setContent(OverlayView(store: store, state: state, icons: icons, actions: actions))
        return panel
    }
}
