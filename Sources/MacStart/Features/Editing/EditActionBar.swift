import MacStartCore
import SwiftUI

/// What edit mode does with the selected items.
enum EditAction {
    /// Groups the selected apps into a new folder.
    case newFolder
    /// Moves the selected items to the end of a page. One past the last page makes a new page.
    case moveToPage(Int)
    case hide
    /// Moves the selected apps of the open folder out, right after the folder.
    case removeFromFolder
    case deselectAll
}

/// What the selected items allow, for the action bar and for the menu of a selected tile.
struct EditSelectionSummary: Equatable {
    let count: Int
    let hasOnlyApps: Bool
    /// How many selected apps the open folder holds, or nil when no folder is open.
    let countInOpenFolder: Int?

    init(_ selection: Set<Item.ID>, openFolder: Folder? = nil) {
        count = selection.count
        hasOnlyApps = selection.allSatisfy {
            if case .app = $0 {
                return true
            }
            return false
        }
        countInOpenFolder = openFolder.map { folder in folder.apps.count { selection.contains(.app($0)) } }
    }

    /// Why Remove from Folder is unavailable, or nil when it is available.
    var removeFromFolderHelp: String? {
        (countInOpenFolder ?? 0) > 0 ? nil : "Select apps in this folder first"
    }

    /// Why New Folder is unavailable, or nil when it is available.
    var newFolderHelp: String? {
        count >= 2 && hasOnlyApps ? nil : "Select two or more apps, and no folders"
    }

    /// Why Hide is unavailable, or nil when it is available.
    var hideHelp: String? {
        if count == 0 {
            return "Select apps first"
        }
        return hasOnlyApps ? nil : "Works on apps only, not folders"
    }
}

/// The items of a Move to Page menu: every page, then a new one at the end. A page without room for the items is
/// unavailable, because a move never pushes items to the next page.
struct PageMenuItems: View {
    let pageCount: Int
    /// True when the items fit on the page.
    let canMove: @MainActor (Int) -> Bool
    /// Takes the page to move to. One past the last page makes a new page.
    let move: @MainActor (Int) -> Void

    var body: some View {
        ForEach(0..<pageCount, id: \.self) { page in
            let hasRoom = canMove(page)
            Button(hasRoom ? "Page \(page + 1)" : "Page \(page + 1) (No Room)") {
                move(page)
            }
            .disabled(!hasRoom)
        }
        Divider()
        Button("New Page") {
            move(pageCount)
        }
    }
}

/// The menu of a tile selected in edit mode. Its actions apply to the whole selection, as in Finder.
struct SelectionMenuItems: View {
    let summary: EditSelectionSummary
    let pageCount: Int
    /// True when an action fits without pushing items to the next page.
    let canPerform: @MainActor (EditAction) -> Bool
    let perform: @MainActor (EditAction) -> Void

    var body: some View {
        Button("New Folder with Selection") {
            perform(.newFolder)
        }
        .disabled(summary.newFolderHelp != nil || !canPerform(.newFolder))
        Menu("Move Selection to Page") {
            PageMenuItems(pageCount: pageCount, canMove: { canPerform(.moveToPage($0)) }) {
                perform(.moveToPage($0))
            }
        }
        if summary.countInOpenFolder != nil {
            Button("Remove Selection from Folder") {
                perform(.removeFromFolder)
            }
            .disabled(summary.removeFromFolderHelp != nil || !canPerform(.removeFromFolder))
        }
        Button("Hide Selection") {
            perform(.hide)
        }
        .disabled(summary.hideHelp != nil)
        Divider()
        Button("Deselect All") {
            perform(.deselectAll)
        }
    }
}

/// The bar above the page dots in edit mode: how many items are selected, and what to do with them.
struct EditActionBar: View {
    let selection: Set<Item.ID>
    /// The open folder, whose apps can be taken out with Remove from Folder.
    let openFolder: Folder?
    let pageCount: Int
    let isHighContrast: Bool
    /// True when an action fits without pushing items to the next page.
    let canPerform: @MainActor (EditAction) -> Bool
    let perform: @MainActor (EditAction) -> Void

    var body: some View {
        let summary = EditSelectionSummary(selection, openFolder: openFolder)
        let newFolderHelp =
            summary.newFolderHelp ?? (canPerform(.newFolder) ? nil : "No room on this page for a new folder")
        HStack(spacing: 2) {
            Text(selection.isEmpty ? "Click items to select them" : "\(selection.count) selected")
                .foregroundStyle(.white.opacity(isHighContrast ? 0.95 : 0.75))
                .monospacedDigit()
                .padding(.horizontal, 12)
            Divider()
                .frame(height: 18)
            barButton("New Folder", systemImage: "folder.badge.plus", help: newFolderHelp) {
                perform(.newFolder)
            }
            .disabled(newFolderHelp != nil)
            moveMenu
            if openFolder != nil {
                let removeHelp =
                    summary.removeFromFolderHelp
                    ?? (canPerform(.removeFromFolder) ? nil : "No room on this page for these apps")
                barButton("Remove from Folder", systemImage: "folder.badge.minus", help: removeHelp) {
                    perform(.removeFromFolder)
                }
                .disabled(removeHelp != nil)
            }
            barButton("Hide", systemImage: "eye.slash", help: summary.hideHelp) {
                perform(.hide)
            }
            .disabled(summary.hideHelp != nil)
            barButton(
                "Deselect All",
                systemImage: "xmark.circle",
                help: selection.isEmpty ? "Nothing is selected" : nil
            ) {
                perform(.deselectAll)
            }
            .disabled(selection.isEmpty)
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 6)
        .frame(height: GridMetrics.toolbarHeight)
        .background(Capsule().fill(.white.opacity(isHighContrast ? 0.25 : 0.14)))
        .overlay(Capsule().strokeBorder(.white.opacity(isHighContrast ? 0.85 : 0.25), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Edit actions")
    }

    private var moveMenu: some View {
        Menu {
            PageMenuItems(pageCount: pageCount, canMove: { canPerform(.moveToPage($0)) }) {
                perform(.moveToPage($0))
            }
        } label: {
            Label("Move to Page", systemImage: "arrow.right.square")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .padding(.horizontal, 10)
        .disabled(selection.isEmpty)
        .opacity(selection.isEmpty ? 0.4 : 1)
        .help(selection.isEmpty ? "Select items first" : "Move the selected items to the end of a page")
    }

    private func barButton(
        _ title: String,
        systemImage: String,
        help: String?,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: GridMetrics.toolbarHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .opacity(help == nil ? 1 : 0.4)
        .help(help ?? title)
    }
}
