import Foundation
import MacStartCore

/// Files in schema version 1. Never change them: they prove that version 1 files stay readable after the
/// format changes.
enum Fixtures {
    static let exportV1 = """
        {
          "exportedAt" : "2026-11-16T12:00:00Z",
          "layout" : {
            "hidden" : [
              { "bundleIdentifier" : "com.apple.Chess", "path" : "/System/Applications/Chess.app" }
            ],
            "pages" : [
              {
                "items" : [
                  { "app" : { "bundleIdentifier" : "com.apple.Safari", "path" : "/Applications/Safari.app" } },
                  {
                    "folder" : {
                      "apps" : [
                        { "bundleIdentifier" : "com.apple.Notes", "path" : "/System/Applications/Notes.app" },
                        { "path" : "/Applications/Unsigned Tool.app" }
                      ],
                      "id" : "5B0B7D6E-8F0A-4C1E-9C3B-2F1D4E5A6B7C",
                      "name" : "Work"
                    }
                  }
                ]
              }
            ]
          },
          "preferences" : {
            "gridColumns" : 8,
            "gridRows" : 6,
            "hotKey" : { "keyCode" : 49, "modifiers" : [ "control", "option" ] },
            "launchAtLogin" : false
          },
          "schemaVersion" : 1
        }
        """

    /// The content of `exportV1`.
    static let exportV1Content = Export(
        exportedAt: Date(timeIntervalSince1970: 1_794_830_400),
        layout: Layout(
            pages: [
                Page(items: [
                    .app(AppID(path: "/Applications/Safari.app", bundleIdentifier: "com.apple.Safari")),
                    .folder(
                        Folder(
                            id: UUID(uuidString: "5B0B7D6E-8F0A-4C1E-9C3B-2F1D4E5A6B7C")!,
                            name: "Work",
                            apps: [
                                AppID(path: "/System/Applications/Notes.app", bundleIdentifier: "com.apple.Notes"),
                                AppID(path: "/Applications/Unsigned Tool.app", bundleIdentifier: nil),
                            ]
                        )
                    ),
                ])
            ],
            hidden: [AppID(path: "/System/Applications/Chess.app", bundleIdentifier: "com.apple.Chess")]
        ),
        preferences: Preferences(
            hotKey: HotKey(keyCode: 49, modifiers: [.control, .option]),
            gridColumns: 8,
            gridRows: 6,
            launchAtLogin: false
        )
    )

    static let layoutV1 = """
        {
          "layout" : {
            "hidden" : [ ],
            "pages" : [
              { "items" : [ { "app" : { "bundleIdentifier" : "com.apple.Safari", "path" : "/Applications/Safari.app" } } ] }
            ]
          },
          "schemaVersion" : 1
        }
        """

    /// The content of `layoutV1`.
    static let layoutV1Content = Layout(pages: [
        Page(items: [.app(AppID(path: "/Applications/Safari.app", bundleIdentifier: "com.apple.Safari"))])
    ])
}
