import MacStartCore
import Testing

/// Reconciles many random layouts against random catalogs. Seeded, so every run checks the same cases and a
/// failure names the seed that reproduces it.
@Suite("Reconcile properties")
struct ReconcilePropertyTests {
    @Test func everyReconciledLayoutSatisfiesTheInvariants() {
        for seed in UInt64(0)..<500 {
            var random = SplitMix64(seed: seed)
            let scenario = Scenario.random(using: &random)

            let result = scenario.layout.reconciled(with: scenario.catalog, pageCapacity: scenario.pageCapacity)

            let violations = result.invariantViolations(catalog: scenario.catalog, pageCapacity: scenario.pageCapacity)
            #expect(violations.isEmpty, "seed \(seed): \(violations)")
            let accountedFor = Set(result.placedAppIDs).union(result.hidden)
            #expect(scenario.catalog.apps.allSatisfy { accountedFor.contains($0.id) }, "seed \(seed): an app is lost")
            #expect(
                result.reconciled(with: scenario.catalog, pageCapacity: scenario.pageCapacity) == result,
                "seed \(seed): a second reconcile changed the layout"
            )
        }
    }
}

/// A random stored layout, catalog, and page capacity.
///
/// The apps come from a small pool, so duplicates, moved apps, shared and missing bundle identifiers, and
/// placed-and-hidden conflicts all occur often.
private struct Scenario {
    let layout: Layout
    let catalog: Catalog
    let pageCapacity: Int

    /// Eight app names, each at two possible paths. Every fourth app has no bundle identifier, and every
    /// fourth other one shares `test.shared`.
    private static let pool: [AppID] = (0..<8).flatMap { index in
        let bundleIdentifier: String? =
            switch index % 4 {
            case 0: nil
            case 1: "test.shared"
            default: "test.app\(index)"
            }
        return ["/Applications", "/Applications/Moved"].map { folder in
            AppID(path: "\(folder)/App\(index).app", bundleIdentifier: bundleIdentifier)
        }
    }

    static func random(using random: inout SplitMix64) -> Scenario {
        var installed: [App] = []
        for id in pool where Bool.random(using: &random) {
            installed.append(app(id))
        }

        var pages: [Page] = []
        for _ in 0..<Int.random(in: 0...4, using: &random) {
            var items: [Item] = []
            for _ in 0..<Int.random(in: 0...8, using: &random) {
                items.append(randomItem(using: &random))
            }
            pages.append(Page(items: items))
        }

        var hidden = Set<AppID>()
        for _ in 0..<Int.random(in: 0...4, using: &random) {
            hidden.insert(randomPoolApp(using: &random))
        }

        return Scenario(
            layout: Layout(pages: pages, hidden: hidden),
            catalog: Catalog(installed),
            pageCapacity: Int.random(in: 1...6, using: &random)
        )
    }

    private static func randomItem(using random: inout SplitMix64) -> Item {
        guard Int.random(in: 0..<4, using: &random) == 0 else {
            return .app(randomPoolApp(using: &random))
        }
        var apps: [AppID] = []
        for _ in 0..<Int.random(in: 0...4, using: &random) {
            apps.append(randomPoolApp(using: &random))
        }
        return .folder(Folder(name: "Folder", apps: apps))
    }

    private static func randomPoolApp(using random: inout SplitMix64) -> AppID {
        pool[Int.random(in: 0..<pool.count, using: &random)]
    }
}
