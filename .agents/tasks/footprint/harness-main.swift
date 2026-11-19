// Scratch harness: hosts the real OverlayView in a window far off every display, in a process with the .prohibited
// activation policy, to measure memory and build time. It never takes focus, never activates, and registers no
// hotkey or login item. Layout comes from a copy of layout.json; preferences come from argv.
import AppKit
import MacStartCore
import SwiftUI

setvbuf(stdout, nil, _IONBF, 0)

final class MemoryStorage: KeyValueStorage {
    var values: [String: Any] = [:]
    func string(forKey key: String) -> String? { values[key] as? String }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}

func cpuSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
        + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
}

func vmmapSummary() -> String {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/vmmap")
    process.arguments = ["--summary", "\(getpid())"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try? process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

func measure(_ label: String) {
    let lines = vmmapSummary().split(separator: "\n")
    func squeeze(_ line: Substring, _ count: Int) -> String {
        line.split(separator: " ", omittingEmptySubsequences: true).prefix(count).joined(separator: " ")
    }
    var parts: [String] = []
    if let line = lines.first(where: { $0.hasPrefix("Physical footprint:") }) {
        parts.append("footprint \(line.split(separator: " ").last ?? "?")")
    }
    for name in ["CoreAnimation", "CG Raster Data", "IOSurface"] {
        if let line = lines.first(where: { $0.hasPrefix(name + " ") }) {
            let fields = line.dropFirst(name.count).split(separator: " ", omittingEmptySubsequences: true)
            // VIRTUAL RESIDENT DIRTY SWAPPED ...
            if fields.count >= 4 { parts.append("\(name) dirty \(fields[2])") }
        }
    }
    // The last TOTAL line belongs to the MALLOC ZONE table: ... COUNT BYTES-ALLOCATED FRAG %FRAG REGIONS
    if let line = lines.last(where: { $0.hasPrefix("TOTAL") }) {
        let fields = line.split(separator: " ", omittingEmptySubsequences: true)
        if fields.count >= 9 {
            parts.append("malloc dirty \(fields[3]) + swapped \(fields[4]), live \(fields[6]), free-but-dirty \(fields[7])")
        }
    }
    print(String(format: "%-58@ %@", label as NSString, parts.joined(separator: " | ") as NSString))
    _ = squeeze
}

struct LayerStats {
    var layers = 0
    var byClass: [String: Int] = [:]
    var contents: [String: Int] = [:]
    var filters: [String: Int] = [:]
    var compositingFilters = 0
    var rasterized = 0
    var masks = 0
    var shadows = 0
}

func inspect(_ layer: CALayer, into stats: inout LayerStats) {
    stats.layers += 1
    stats.byClass[String(describing: type(of: layer)), default: 0] += 1
    if let contents = layer.contents {
        let kind = CFGetTypeID(contents as CFTypeRef) == CGImage.typeID ? "CGImage" : String(describing: type(of: contents))
        stats.contents[kind, default: 0] += 1
    }
    for filter in layer.filters ?? [] {
        stats.filters[String(describing: (filter as AnyObject).value(forKey: "name") ?? filter), default: 0] += 1
    }
    if layer.compositingFilter != nil { stats.compositingFilters += 1 }
    if layer.shouldRasterize { stats.rasterized += 1 }
    if layer.mask != nil { stats.masks += 1 }
    if layer.shadowOpacity > 0 { stats.shadows += 1 }
    for sublayer in layer.sublayers ?? [] { inspect(sublayer, into: &stats) }
}

@MainActor
enum Harness {
    static var window: NSWindow!

    static let noActions = OverlayActions(
        click: { _ in }, dismiss: {}, showPage: { _ in }, moveItems: { _, _ in }, canMoveItems: { _, _ in true },
        moveAppsToFolder: { _, _ in }, canMoveAppsToFolder: { _, _ in true }, closeFolder: {}, renameFolder: { _, _ in },
        removeFromFolder: { _, _ in }, canRemoveFromFolder: { _, _ in true }, showInFinder: { _ in }, hide: { _ in },
        openSettings: {}, toggleEditing: {}, select: { _ in }, performEdit: { _ in }, canPerformEdit: { _ in true },
        dragChanged: { _ in }, dragEnded: {}
    )

    static func requests(_ store: LayoutStore) -> [(app: InstalledApp, side: CGFloat)] {
        let screen = NSScreen.screens.first!
        let metrics = GridMetrics(
            overlaySize: screen.frame.size, columns: store.preferences.gridColumns, rows: store.preferences.gridRows)
        let miniSide = FolderIcon.miniSide(forSide: metrics.iconSize)
        var result: [(app: InstalledApp, side: CGFloat)] = []
        for item in store.layout.pages.flatMap(\.items) {
            switch item {
            case .app(let id):
                if let app = store.app(for: id) { result.append((app, metrics.iconSize)) }
            case .folder(let folder):
                for id in folder.apps.prefix(9) {
                    if let app = store.app(for: id) { result.append((app, miniSide)) }
                }
            }
        }
        return result
    }

    /// Builds the overlay content in the window and forces the first layout, display, and commit.
    static func build(_ store: LayoutStore, _ state: OverlayState, _ icons: IconProvider) -> String {
        let cpu = cpuSeconds()
        let wall = Date.now
        let blur = NSVisualEffectView()
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        window.contentView = blur
        let hosting = NSHostingView(rootView: OverlayView(store: store, state: state, icons: icons, actions: noActions))
        hosting.sizingOptions = []
        hosting.frame = blur.bounds
        hosting.autoresizingMask = [.width, .height]
        blur.addSubview(hosting)
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CATransaction.flush()
        return String(format: "%.0f ms wall, %.0f ms CPU", Date.now.timeIntervalSince(wall) * 1000, (cpuSeconds() - cpu) * 1000)
    }

    /// Shows the kept content again, as the app does today: order in, present, first frame.
    static func reshow(_ state: OverlayState) -> String {
        let cpu = cpuSeconds()
        let wall = Date.now
        window.orderFrontRegardless()
        state.isPresented = true
        state.searchFocusRequest += 1
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CATransaction.flush()
        return String(format: "%.0f ms wall, %.0f ms CPU", Date.now.timeIntervalSince(wall) * 1000, (cpuSeconds() - cpu) * 1000)
    }

    static func hide(_ state: OverlayState) {
        state.isPresented = false
        window.orderOut(nil)
        state.reset()
    }

    static func settle() async {
        try? await Task.sleep(for: .seconds(1.2))
    }

    static func timed(_ body: () async -> Void) async -> String {
        let cpu = cpuSeconds()
        let wall = Date.now
        await body()
        return String(format: "%.0f ms wall, %.0f ms CPU", Date.now.timeIntervalSince(wall) * 1000, (cpuSeconds() - cpu) * 1000)
    }

    static func zones() {
        let lines = vmmapSummary().split(separator: "\n")
        guard let header = lines.firstIndex(where: { $0.hasPrefix("MALLOC ZONE") }) else { return }
        for line in lines[(header + 2)...] where !line.hasPrefix("=") && !line.hasPrefix("TOTAL") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            if fields.count >= 9, fields[6] != "0K" || fields[7] != "0K" {
                print("    zone \(fields[0].prefix(34)): dirty \(fields[3]) + swapped \(fields[4]), live \(fields[6]), free-but-dirty \(fields[7])")
            }
        }
    }

    static func run() async {
        let arguments = CommandLine.arguments
        let directory = URL(filePath: arguments[1])
        let storage = MemoryStorage()
        storage.values["preferences"] = arguments[2]
        let preferencesStore = PreferencesStore(storage: storage)
        let store = LayoutStore(
            scanner: CatalogScanner(roots: CatalogScanner.standardRoots()),
            fileStore: LayoutFileStore(fileURL: directory.appending(path: "layout.json")),
            preferencesStore: preferencesStore,
            preferences: preferencesStore.load() ?? .default
        )
        let environment = ProcessInfo.processInfo.environment
        print("icons: \(environment["HARNESS_IOSURFACE"] == "1" ? "IOSurface" : "CGContext (as shipped)"), autorelease pools: \(environment["HARNESS_POOL"] == "1")")
        measure("start")
        print("load (read layout, scan catalog): \(await timed { await store.load() }), \(store.catalog.count) apps")
        let icons = IconProvider()
        let wanted = requests(store)
        print("prewarm \(wanted.count) icons: \(await timed { await icons.prewarm(wanted) })")
        measure("loaded, icons prewarmed")
        zones()
        if environment["HARNESS_MODE"] == "watch" {
            await watchCheck()
            exit(0)
        }
        if environment["HARNESS_MODE"] == "rescan" {
            var timings: [String] = []
            for _ in 0..<5 { timings.append(await timed { await store.refreshCatalog() }) }
            print("rescan: \(timings.joined(separator: "; "))")
            measure("after 5 rescans")
            exit(0)
        }
        if environment["HARNESS_MODE"] == "controller" {
            await controllerCycles(store, icons)
            exit(0)
        }
        if environment["HARNESS_MODE"] == "heapdiff" {
            await heapDiff(store, icons)
            exit(0)
        }
        var rescans: [String] = []
        for _ in 0..<3 { rescans.append(await timed { await store.refreshCatalog() }) }
        print("rescan, nothing shown: \(rescans.joined(separator: "; "))")
        measure("after 3 rescans, nothing shown")

        let frame = NSScreen.screens.first!.frame
        window = NSWindow(
            contentRect: NSRect(x: -40000, y: -40000, width: frame.width, height: frame.height),
            styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .darkAqua)
        let state = OverlayState()
        state.isPresented = true
        print("first build + first frame: \(build(store, state, icons))")
        await settle()
        if let image = window.contentView?.layer.flatMap(firstImage) {
            print("icon CGImage: \(image.width)x\(image.height), bytesPerRow \(image.bytesPerRow), colorSpace \(image.colorSpace.map { String(describing: $0.name ?? "unnamed" as CFString) } ?? "none")")
        }
        measure("shown")
        hide(state)
        await settle()
        measure("hidden, tree kept (as shipped)")
        rescans = []
        for _ in 0..<3 {
            rescans.append(await timed {
                await store.refreshCatalog()
                await settle()
            })
        }
        print("rescan + settle, hidden tree kept: \(rescans.joined(separator: "; "))  (settle is 1200 ms of wall)")
        for batch in 1...5 {
            for _ in 0..<20 {
                _ = reshow(state)
                await Task.yield()
                hide(state)
                await Task.yield()
            }
            await settle()
            measure("show/hide cycles: \(batch * 20)")
        }
        zones()
        exit(0)
    }

    static func heapSnapshot(_ name: String) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/heap")
        process.arguments = ["-s", "\(getpid())"]
        FileManager.default.createFile(atPath: name, contents: nil)
        process.standardOutput = FileHandle(forWritingAtPath: name)
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    static func heapDiff(_ store: LayoutStore, _ icons: IconProvider) async {
        let frame = NSScreen.screens.first!.frame
        window = NSWindow(
            contentRect: NSRect(x: -40000, y: -40000, width: frame.width, height: frame.height),
            styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.appearance = NSAppearance(named: .darkAqua)
        let state = OverlayState()
        state.isPresented = true
        _ = build(store, state, icons)
        await settle()
        let variant = ProcessInfo.processInfo.environment["HARNESS_CYCLE"] ?? "full"
        func cycle() async {
            switch variant {
            case "window":  // order in and out only
                window.orderFrontRegardless()
                window.displayIfNeeded()
                CATransaction.flush()
                await Task.yield()
                window.orderOut(nil)
            case "state":  // state changes only, window stays out
                state.isPresented = true
                state.searchFocusRequest += 1
                window.contentView?.layoutSubtreeIfNeeded()
                CATransaction.flush()
                await Task.yield()
                state.isPresented = false
                state.reset()
            case "focus":  // only the search focus request, window in front
                state.searchFocusRequest += 1
                window.contentView?.layoutSubtreeIfNeeded()
                CATransaction.flush()
                await Task.yield()
            default:
                _ = reshow(state)
                await Task.yield()
                hide(state)
            }
            await Task.yield()
        }
        if variant == "focus" {
            window.orderFrontRegardless()
        } else {
            hide(state)
        }
        for _ in 0..<30 { await cycle() }
        await settle()
        measure("[\(variant)] after 30 warm-up cycles")
        heapSnapshot("heap-\(variant)-a.txt")
        for _ in 0..<300 { await cycle() }
        await settle()
        measure("[\(variant)] after 300 more cycles")
        heapSnapshot("heap-\(variant)-b.txt")
    }

    static func run(_ tool: String, _ arguments: [String], to path: String) {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        FileManager.default.createFile(atPath: path, contents: nil)
        process.standardOutput = FileHandle(forWritingAtPath: path)
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    static func nonObjectAddresses(_ path: String) -> Set<String> {
        run("/usr/bin/heap", ["-addresses=non-object", "\(getpid())"], to: path)
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        var result = Set<String>()
        for line in text.split(separator: "\n") {
            // Lines look like: "non-object  0x10123abc0: 48 bytes" or similar; keep "address:size".
            if let range = line.range(of: #"0x[0-9a-f]+"#, options: .regularExpression) {
                let size = line.split(separator: " ").last(where: { Int($0) != nil }) ?? ""
                result.insert("\(line[range]) \(size)")
            }
        }
        return result
    }

    /// The real OverlayController, shown and hidden with its own fade timing, panel off every display.
    static func controllerCycles(_ store: LayoutStore, _ icons: IconProvider) async {
        let controller = OverlayController(store: store, icons: icons, launcher: AppLauncher()) {}
        let cycles = Int(ProcessInfo.processInfo.environment["HARNESS_CYCLES"] ?? "300") ?? 300
        func cycle() async {
            controller.show()
            try? await Task.sleep(for: .seconds(0.3))
            controller.hide()
            try? await Task.sleep(for: .seconds(0.35))
        }
        if ProcessInfo.processInfo.environment["HARNESS_ZOOMCHECK"] == "1" {
            await zoomCheck(controller)
            return
        }
        if ProcessInfo.processInfo.environment["HARNESS_FOLDERS"] == "1" {
            guard
                let folderID = store.layout.pages.flatMap(\.items).lazy.compactMap({ item -> UUID? in
                    if case .folder(let folder) = item { return folder.id }
                    return nil
                }).first
            else {
                print("no folder in the layout")
                return
            }
            if let position = store.layout.position(ofFolder: folderID) {
                controller.showPage(position.page)
            }
            controller.show()
            await settle()
            func folderCycle() async {
                controller.state.openFolder(folderID)
                try? await Task.sleep(for: .seconds(0.35))
                controller.state.closeFolder()
                try? await Task.sleep(for: .seconds(0.35))
            }
            for _ in 0..<20 { await folderCycle() }
            await settle()
            measure("[folders] after 20 warm-up open/close")
            var batchCPU = cpuSeconds()
            for index in 1...cycles {
                await folderCycle()
                if index % 50 == 0 {
                    measure("[folders] after \(index) more")
                    print(String(format: "    CPU per open+close: %.1f ms", (cpuSeconds() - batchCPU) * 1000 / 50))
                    batchCPU = cpuSeconds()
                }
            }
            return
        }
        for _ in 0..<30 { await cycle() }
        await settle()
        measure("[controller] after 30 warm-up show/hide")
        let isDetailed = ProcessInfo.processInfo.environment["MallocStackLogging"] != nil
        if isDetailed { heapSnapshot("heap-controller-a.txt") }
        let before = isDetailed ? nonObjectAddresses("addresses-a.txt") : []
        var batchCPU = cpuSeconds()
        for index in 1...cycles {
            await cycle()
            if index % 50 == 0 {
                measure("[controller] after \(index) more")
                print(String(format: "    CPU per show+hide: %.1f ms", (cpuSeconds() - batchCPU) * 1000 / 50))
                batchCPU = cpuSeconds()
            }
        }
        await settle()
        guard isDetailed else { return }
        heapSnapshot("heap-controller-b.txt")
        let after = nonObjectAddresses("addresses-b.txt")
        let added = after.subtracting(before)
        print("non-object blocks: \(before.count) -> \(after.count), new and still live: \(added.count)")
        // Allocation stacks for a sample of the new blocks, when MallocStackLogging is on.
        for (index, entry) in added.sorted().enumerated() where index % max(added.count / 12, 1) == 0 {
            let address = String(entry.split(separator: " ")[0])
            run("/usr/bin/malloc_history", ["\(getpid())", address], to: "stack-\(index).txt")
        }
    }

    /// Checks the Core Animation zoom: about the content's center, zoomed out while hidden, identity once shown, and
    /// still identity after SwiftUI updates the content.
    static func zoomCheck(_ controller: OverlayController) async {
        guard let panel = NSApp.windows.compactMap({ $0 as? OverlayPanel }).first,
            let view = panel.hostingView, let layer = view.layer
        else {
            controller.show()
            await settle()
            if NSApp.windows.contains(where: { $0 is OverlayPanel }) { await zoomCheck(controller) }
            return
        }
        func describe(_ t: CATransform3D) -> String {
            String(format: "scale %.3f x %.3f, offset %.2f, %.2f", t.m11, t.m22, t.m41, t.m42)
        }
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        func mapped(_ point: CGPoint, _ t: CATransform3D) -> CGPoint {
            // Row vectors, about the anchor point (the view's origin in AppKit).
            CGPoint(x: point.x * t.m11 + point.y * t.m21 + t.m41, y: point.x * t.m12 + point.y * t.m22 + t.m42)
        }
        print("anchorPoint \(layer.anchorPoint), view bounds \(view.bounds), layer bounds \(layer.bounds)")
        print("shown: \(describe(layer.sublayerTransform)), zoom animation running: \(layer.animation(forKey: "zoom") != nil)")
        controller.hide()
        try? await Task.sleep(for: .seconds(0.1))
        if let presentation = layer.presentation() {
            print("mid-hide presentation: \(describe(presentation.sublayerTransform))")
        }
        await settle()
        let hidden = layer.sublayerTransform
        print("hidden: \(describe(hidden)), center maps to \(mapped(center, hidden)) (center \(center)), corner (0,0) maps to \(mapped(.zero, hidden))")
        controller.show()
        await settle()
        controller.state.query = "a"
        await settle()
        controller.state.query = ""
        await settle()
        print("shown again after SwiftUI updates: \(describe(layer.sublayerTransform)), animations \(layer.animationKeys() ?? [])")
    }

    /// Checks the FSEvents wiring on a temporary root: a write inside a bundle's Resources reports nothing, a new
    /// app reports a change.
    static func watchCheck() async {
        let root = FileManager.default.temporaryDirectory.appending(path: "macstart-watch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appending(path: "Old.app/Contents/Resources")
        try? FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        // FSEvents can still deliver changes made just before a stream starts, so the setup settles first.
        try? await Task.sleep(for: .seconds(1.5))
        var changes = 0
        let watcher = CatalogWatcher(roots: [root], latency: 0.2) { changes += 1 }
        try? await Task.sleep(for: .seconds(1))
        FileManager.default.createFile(atPath: resources.appending(path: "x").path, contents: Data([1]))
        try? await Task.sleep(for: .seconds(1.5))
        print("after a write inside Old.app/Contents/Resources: \(changes) change reports (expected 0)")
        try? FileManager.default.createDirectory(
            at: root.appending(path: "New.app/Contents"), withIntermediateDirectories: true)
        try? await Task.sleep(for: .seconds(1.5))
        print("after New.app appeared: \(changes) change reports (expected 1)")
        withExtendedLifetime(watcher) {}
    }

    static func firstImage(in layer: CALayer) -> CGImage? {
        if let contents = layer.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID {
            return (contents as! CGImage)
        }
        for sublayer in layer.sublayers ?? [] {
            if let image = firstImage(in: sublayer) { return image }
        }
        return nil
    }
}

NSApplication.shared.setActivationPolicy(.prohibited)
Task { @MainActor in await Harness.run() }
NSApplication.shared.run()
