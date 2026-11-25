/// The user's settings. Stored in `UserDefaults` and included in every export.
public struct Preferences: Hashable, Sendable {
    /// The grid sizes Settings offers, grouped by rows. Each row count gets the three column counts that keep tiles
    /// close to square on the screen sizes MacStart runs on; other grids look too sparse or too crowded.
    public static let allowedGridSizes: [GridSize] = [
        GridSize(columns: 5, rows: 4), GridSize(columns: 6, rows: 4), GridSize(columns: 7, rows: 4),
        GridSize(columns: 6, rows: 5), GridSize(columns: 7, rows: 5), GridSize(columns: 8, rows: 5),
        GridSize(columns: 7, rows: 6), GridSize(columns: 8, rows: 6), GridSize(columns: 9, rows: 6),
    ]

    /// The global shortcut that toggles the overlay.
    public var hotKey: HotKey
    /// Columns by rows per page, kept to one of `allowedGridSizes`. Set as one value, so a change of both columns
    /// and rows is never checked against a half-changed size.
    public var gridSize: GridSize {
        didSet { gridSize = gridSize.nearestAllowed }
    }
    public var launchAtLogin: Bool

    /// A grid size that is not allowed becomes the nearest allowed one.
    public init(hotKey: HotKey, gridColumns: Int, gridRows: Int, launchAtLogin: Bool) {
        self.hotKey = hotKey
        self.gridSize = GridSize(columns: gridColumns, rows: gridRows).nearestAllowed
        self.launchAtLogin = launchAtLogin
    }

    /// Option-S, a 7 x 5 grid, and launch at login on.
    public static let `default` = Preferences(hotKey: .default, gridColumns: 7, gridRows: 5, launchAtLogin: true)

    public var gridColumns: Int {
        gridSize.columns
    }

    public var gridRows: Int {
        gridSize.rows
    }

    /// How many items fit on one page.
    public var pageCapacity: Int {
        gridSize.capacity
    }
}

/// Columns by rows of a page.
public struct GridSize: Hashable, Sendable {
    public let columns: Int
    public let rows: Int

    public init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }

    public var capacity: Int {
        columns * rows
    }

    /// Columns by rows, as in "7 × 5".
    public var text: String {
        "\(columns) × \(rows)"
    }

    /// This size when it is allowed. Otherwise the rows move to the nearest allowed row count, then the columns to
    /// the nearest column count allowed with those rows.
    var nearestAllowed: GridSize {
        // The unwraps are safe: `allowedGridSizes` is a non-empty constant, and every allowed row count has columns.
        let allowed = Preferences.allowedGridSizes
        let rows = rows.clamped(to: allowed.map(\.rows).min()!...allowed.map(\.rows).max()!)
        let columnsForRows = allowed.filter { $0.rows == rows }.map(\.columns)
        let columns = columns.clamped(to: columnsForRows.min()!...columnsForRows.max()!)
        return GridSize(columns: columns, rows: rows)
    }
}

extension Preferences: Codable {
    private enum CodingKeys: String, CodingKey {
        case hotKey
        case gridColumns
        case gridRows
        case launchAtLogin
    }

    /// A grid size that is not allowed, as in a backup from a version that allowed more, becomes the nearest
    /// allowed size instead of failing the whole file.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            hotKey: try container.decode(HotKey.self, forKey: .hotKey),
            gridColumns: try container.decode(Int.self, forKey: .gridColumns),
            gridRows: try container.decode(Int.self, forKey: .gridRows),
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
