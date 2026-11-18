import AppKit
import MacStartCore
import SwiftUI

/// The width every settings pane shares, so switching panes changes only the window's height.
private let paneWidth: CGFloat = 500

/// The shortcut and launch at login.
struct GeneralSettingsPane: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Shortcut") {
                    HotKeyRecorder(model: model)
                }
                if let message = model.hotKeyMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                Toggle(
                    "Open at login",
                    isOn: Binding(
                        get: { model.store.preferences.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )
                if let message = model.loginItemMessage {
                    HStack {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if model.loginItemNeedsApproval {
                            Button("Open Login Items") {
                                model.openLoginItemsSettings()
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: paneWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The grid size, which asks to confirm before it moves apps, and Reset Layout.
struct LayoutSettingsPane: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                Picker(
                    "Grid size",
                    selection: Binding(get: { model.gridSize }, set: { model.requestGridSize($0) })
                ) {
                    ForEach(Preferences.allowedGridRows, id: \.self) { rows in
                        if rows != Preferences.allowedGridRows.lowerBound {
                            Divider()
                        }
                        ForEach(Preferences.allowedGridColumns, id: \.self) { columns in
                            let size = GridSize(columns: columns, rows: rows)
                            Text(size.text).tag(size)
                        }
                    }
                }
                Text("Columns × rows. A new size asks to confirm first, because apps move to fill it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text(
                        "Puts every app back in name order, with no folders and no hidden apps, as on the first launch."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    Spacer()
                    // In a settings form the destructive role alone looks like any other button. The red, which
                    // also tints the bezel, sets it apart from the harmless buttons around it, as in the alert.
                    Button("Reset Layout…", role: .destructive) {
                        model.resetLayout()
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: paneWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The hidden apps, which can run to hundreds: a search field, a list where several can be selected, and one
/// Unhide button for the selection.
struct HiddenAppsSettingsPane: View {
    let model: SettingsModel
    let icons: IconProvider

    @State private var query = ""
    @State private var selection: Set<AppID> = []

    var body: some View {
        let hiddenApps = model.hiddenApps
        let shown = matches(in: hiddenApps)
        VStack(alignment: .leading, spacing: 10) {
            if hiddenApps.isEmpty {
                Text("No hidden apps. To hide one, right-click it in MacStart and choose Hide.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SystemSearchField(text: $query, placeholder: "Search \(hiddenApps.count) hidden apps")
                List(shown, selection: $selection) { hidden in
                    HiddenAppRow(hidden: hidden, icons: icons)
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                HStack {
                    Text(
                        selection.isEmpty
                            ? "Select apps to show them again. ⌘-click or ⇧-click selects several."
                            : "\(selection.count) of \(hiddenApps.count) selected"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("Unhide") {
                        model.unhide(selection)
                        selection = []
                    }
                    .disabled(selection.isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: paneWidth, height: 440)
        // Only apps the list shows stay selected, so Unhide never acts on apps the search hides.
        .onChange(of: query) {
            selection.formIntersection(matches(in: model.hiddenApps).map(\.id))
        }
    }

    private func matches(in hiddenApps: [SettingsModel.HiddenApp]) -> [SettingsModel.HiddenApp] {
        let words = query.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else {
            return hiddenApps
        }
        return hiddenApps.filter { $0.name.localizedStandardContains(words) }
    }
}

/// Export and import of the whole setup.
struct BackupSettingsPane: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                HStack {
                    Button("Export…") {
                        model.exportBackup()
                    }
                    Button("Import…") {
                        model.importBackup()
                    }
                }
                Text(
                    "A backup holds the pages, folders, hidden apps, and every setting. Import it on this Mac or a new one."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: paneWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Shows the shortcut. A click starts recording a new one.
struct HotKeyRecorder: View {
    let model: SettingsModel

    var body: some View {
        Button {
            if model.isRecordingHotKey {
                model.cancelRecordingHotKey()
            } else {
                model.startRecordingHotKey()
            }
        } label: {
            Text(model.isRecordingHotKey ? "Type a shortcut…" : model.hotKeyText)
                .frame(minWidth: 120)
        }
        .help("Click, then press the new shortcut. Escape cancels.")
        .accessibilityLabel(model.isRecordingHotKey ? "Recording shortcut" : "Shortcut \(model.hotKeyText)")
        .accessibilityHint("Click, then press the new shortcut")
    }
}

/// One hidden app in the list.
struct HiddenAppRow: View {
    let hidden: SettingsModel.HiddenApp
    let icons: IconProvider

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let app = hidden.app {
                    Image(nsImage: icons.icon(for: app, side: 20))
                        .resizable()
                        .interpolation(.high)
                } else {
                    Image(systemName: "questionmark.app.dashed")
                        .resizable()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
            Text(hidden.name)
            Spacer()
            if hidden.app == nil {
                Text("Not installed")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The system search field, bound to a string. A SwiftUI search field would go into the window's toolbar, which
/// holds the pane buttons.
struct SystemSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text {
            field.stringValue = text
        }
        field.placeholderString = placeholder
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSSearchField {
                text.wrappedValue = field.stringValue
            }
        }

        /// The clear button and Return send the action.
        @objc func searchChanged(_ field: NSSearchField) {
            text.wrappedValue = field.stringValue
        }
    }
}
