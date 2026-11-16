import Foundation

/// A broken layout invariant. The numbers refer to the list in `docs/domain-model.md`.
public enum LayoutInvariantViolation: Hashable, Sendable {
    /// Invariant 1: the app is placed more than once.
    case duplicateApp(AppID)
    /// Invariant 2: the app is placed and hidden at the same time.
    case placedAndHidden(AppID)
    /// Invariant 3: the app is placed but not installed.
    case notInstalled(AppID)
    /// Invariant 4: the folder holds fewer than 2 apps.
    case undersizedFolder(UUID)
    /// Invariant 5: the layout has no page at all.
    case noPages
    /// Invariant 5: the page at this index is empty, and it is not a lone page of an empty layout.
    case emptyPage(index: Int)
    /// Invariant 6: the page at this index holds more items than the page capacity.
    case overfullPage(index: Int)
}

extension Layout {
    /// Every invariant this layout breaks. A reconciled layout breaks none.
    public func invariantViolations(catalog: Catalog, pageCapacity: Int) -> [LayoutInvariantViolation] {
        var violations: [LayoutInvariantViolation] = []

        var seen = Set<AppID>()
        var reported = Set<AppID>()
        for id in placedAppIDs {
            if !seen.insert(id).inserted, reported.insert(id).inserted {
                violations.append(.duplicateApp(id))
            }
            if hidden.contains(id) {
                violations.append(.placedAndHidden(id))
            }
            if !catalog.contains(id) {
                violations.append(.notInstalled(id))
            }
        }

        for page in pages {
            for case .folder(let folder) in page.items where folder.apps.count < 2 {
                violations.append(.undersizedFolder(folder.id))
            }
        }

        if pages.isEmpty {
            violations.append(.noPages)
        }
        let isLoneEmptyPageAllowed = pages.count == 1 && placedAppIDs.isEmpty
        for (index, page) in pages.enumerated() {
            if page.items.isEmpty, !isLoneEmptyPageAllowed {
                violations.append(.emptyPage(index: index))
            }
            if page.items.count > pageCapacity {
                violations.append(.overfullPage(index: index))
            }
        }
        return violations
    }
}
