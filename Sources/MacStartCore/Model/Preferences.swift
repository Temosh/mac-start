/// The user's settings. Stored in `UserDefaults` and included in every export.
public struct Preferences: Hashable, Sendable {
    /// The column counts Settings offers and files may contain.
    public static let allowedGridColumns = 3...15
    /// The row counts Settings offers and files may contain.
    public static let allowedGridRows = 2...10

    /// The global shortcut that toggles the overlay.
    public var hotKey: HotKey
    /// Columns per page, kept within `allowedGridColumns`.
    public var gridColumns: Int {
        didSet { gridColumns = gridColumns.clamped(to: Self.allowedGridColumns) }
    }
    /// Rows per page, kept within `allowedGridRows`.
    public var gridRows: Int {
        didSet { gridRows = gridRows.clamped(to: Self.allowedGridRows) }
    }
    public var launchAtLogin: Bool

    /// Grid values outside the allowed ranges are clamped to the nearest allowed value.
    public init(hotKey: HotKey, gridColumns: Int, gridRows: Int, launchAtLogin: Bool) {
        self.hotKey = hotKey
        self.gridColumns = gridColumns.clamped(to: Self.allowedGridColumns)
        self.gridRows = gridRows.clamped(to: Self.allowedGridRows)
        self.launchAtLogin = launchAtLogin
    }

    /// Option-S, a 7 x 5 grid, and launch at login on.
    public static let `default` = Preferences(hotKey: .default, gridColumns: 7, gridRows: 5, launchAtLogin: true)

    /// How many items fit on one page.
    public var pageCapacity: Int {
        gridColumns * gridRows
    }
}

extension Preferences: Codable {
    private enum CodingKeys: String, CodingKey {
        case hotKey
        case gridColumns
        case gridRows
        case launchAtLogin
    }

    /// Rejects grid sizes outside the allowed ranges instead of clamping them, so a bad file is reported.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let columns = try container.decode(Int.self, forKey: .gridColumns)
        guard Self.allowedGridColumns.contains(columns) else {
            throw DecodingError.dataCorruptedError(
                forKey: .gridColumns,
                in: container,
                debugDescription: "Grid columns must be in \(Self.allowedGridColumns), got \(columns)."
            )
        }
        let rows = try container.decode(Int.self, forKey: .gridRows)
        guard Self.allowedGridRows.contains(rows) else {
            throw DecodingError.dataCorruptedError(
                forKey: .gridRows,
                in: container,
                debugDescription: "Grid rows must be in \(Self.allowedGridRows), got \(rows)."
            )
        }
        self.init(
            hotKey: try container.decode(HotKey.self, forKey: .hotKey),
            gridColumns: columns,
            gridRows: rows,
            launchAtLogin: try container.decode(Bool.self, forKey: .launchAtLogin)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hotKey, forKey: .hotKey)
        try container.encode(gridColumns, forKey: .gridColumns)
        try container.encode(gridRows, forKey: .gridRows)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
    }
}

/// A global keyboard shortcut: a virtual key code and its modifier keys.
public struct HotKey: Hashable, Sendable, Codable {
    /// The virtual key code, as in Carbon's `kVK_*` constants and `NSEvent.keyCode`.
    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Option-S. `0x01` is `kVK_ANSI_S`.
    public static let `default` = HotKey(keyCode: 0x01, modifiers: [.option])

    /// The virtual key codes of F1 to F20 (`kVK_F1` to `kVK_F20`).
    public static let functionKeyCodes: Set<UInt16> = [
        0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D,
        0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A,
    ]

    /// True when the shortcut can be global without taking a key away from typing: it uses Command, Option, or
    /// Control, or it is a function key. Shift alone is not enough.
    public var isUsableAsGlobalShortcut: Bool {
        !modifiers.isDisjoint(with: [.command, .option, .control]) || Self.functionKeyCodes.contains(keyCode)
    }

    /// The modifier keys of a shortcut.
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }
}

extension HotKey.Modifiers: Codable {
    /// File names of the modifiers, in the order macOS shows them in shortcuts.
    private static let names: [(modifier: HotKey.Modifiers, name: String)] = [
        (.control, "control"), (.option, "option"), (.shift, "shift"), (.command, "command"),
    ]

    // Encoded as names, for example `["option", "shift"]`, so files stay readable.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        var modifiers: HotKey.Modifiers = []
        for name in try container.decode([String].self) {
            guard let entry = Self.names.first(where: { $0.name == name }) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown modifier \"\(name)\".")
            }
            modifiers.insert(entry.modifier)
        }
        self = modifiers
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Self.names.filter { contains($0.modifier) }.map(\.name))
    }
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
