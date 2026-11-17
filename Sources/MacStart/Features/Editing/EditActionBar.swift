import MacStartCore
import SwiftUI

/// What edit mode does with the selected items.
enum EditAction {
    /// Groups the selected apps into a new folder.
    case newFolder
    /// Moves the selected items to the end of a page. One past the last page makes a new page.
    case moveToPage(Int)
    case hide
    case deselectAll
}

/// The bar above the page dots in edit mode: how many items are selected, and what to do with them.
struct EditActionBar: View {
    let selection: Set<Item.ID>
    let pageCount: Int
    let isHighContrast: Bool
    let perform: @MainActor (EditAction) -> Void

    var body: some View {
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
            barButton("Hide", systemImage: "eye.slash", help: appsOnlyHelp) {
                perform(.hide)
            }
            .disabled(appsOnlyHelp != nil)
            barButton(
                "Deselect All", systemImage: "xmark.circle", help: selection.isEmpty ? "Nothing is selected" : nil
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
            ForEach(0..<pageCount, id: \.self) { page in
                Button("Page \(page + 1)") {
                    perform(.moveToPage(page))
                }
            }
            Divider()
            Button("New Page") {
                perform(.moveToPage(pageCount))
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

    private var hasOnlyApps: Bool {
        selection.allSatisfy {
            if case .app = $0 {
                return true
            }
            return false
        }
    }

    /// Why New Folder is unavailable, or nil when it is available.
    private var newFolderHelp: String? {
        selection.count >= 2 && hasOnlyApps ? nil : "Select two or more apps, and no folders"
    }

    /// Why Hide is unavailable, or nil when it is available.
    private var appsOnlyHelp: String? {
        if selection.isEmpty {
            return "Select apps first"
        }
        return hasOnlyApps ? nil : "Works on apps only, not folders"
    }
}
