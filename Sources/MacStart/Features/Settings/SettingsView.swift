import MacStartCore
import SwiftUI

/// The settings window's content: the shortcut and launch at login, the grid size, the hidden apps, and backups.
struct SettingsView: View {
    let model: SettingsModel
    let icons: IconProvider

    var body: some View {
        let preferences = model.store.preferences
        Form {
            Section("General") {
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
                    isOn: Binding(get: { preferences.launchAtLogin }, set: { model.setLaunchAtLogin($0) })
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
            Section("Grid") {
                Stepper(
                    value: Binding(get: { preferences.gridColumns }, set: { model.setGridColumns($0) }),
                    in: Preferences.allowedGridColumns
                ) {
                    LabeledContent("Columns", value: "\(preferences.gridColumns)")
                }
                Stepper(
                    value: Binding(get: { preferences.gridRows }, set: { model.setGridRows($0) }),
                    in: Preferences.allowedGridRows
                ) {
                    LabeledContent("Rows", value: "\(preferences.gridRows)")
                }
            }
            Section("Hidden Apps") {
                let hiddenApps = model.hiddenApps
                if hiddenApps.isEmpty {
                    Text("No hidden apps. To hide one, right-click it in MacStart and choose Hide.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(hiddenApps) { hidden in
                        HiddenAppRow(hidden: hidden, icons: icons) {
                            model.unhide(hidden.id)
                        }
                    }
                }
            }
            Section("Backup") {
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
        .frame(width: 480)
        .frame(minHeight: 520)
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

/// One hidden app with its Unhide button.
struct HiddenAppRow: View {
    let hidden: SettingsModel.HiddenApp
    let icons: IconProvider
    let unhide: () -> Void

    var body: some View {
        HStack {
            Group {
                if let app = hidden.app {
                    Image(nsImage: icons.icon(for: app, side: 24))
                        .resizable()
                        .interpolation(.high)
                } else {
                    Image(systemName: "questionmark.app.dashed")
                        .resizable()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(hidden.name)
                if hidden.app == nil {
                    Text("Not installed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Unhide", action: unhide)
                .accessibilityLabel("Unhide \(hidden.name)")
        }
    }
}
