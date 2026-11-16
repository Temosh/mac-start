extension Layout {
    /// Merges the catalog into this layout. The result satisfies every invariant in `docs/domain-model.md`.
    ///
    /// Steps, in order:
    /// 1. Collapse duplicates: keep each app's first occurrence in reading order. A placed app that is also
    ///    hidden stays hidden and leaves the grid.
    /// 2. Match stored apps to the catalog, placed and hidden alike: by exact path first, then rebind a
    ///    leftover whose bundle identifier matches exactly one still unmatched catalog app. Placed apps are
    ///    matched in reading order, then hidden apps in path order. Unmatched placed apps are removed.
    /// 3. Keep unmatched hidden apps, so a reinstalled app stays hidden.
    /// 4. Append catalog apps that are neither placed nor hidden to the last page, by display name.
    /// 5. Dissolve folders with fewer than 2 apps, remove empty pages, and move items that do not fit a page
    ///    onto the next one.
    ///
    /// Pure: the same layout, catalog, and capacity always give the same result.
    public func reconciled(with catalog: Catalog, pageCapacity: Int) -> Layout {
        precondition(pageCapacity > 0, "A page must hold at least one item.")
        let collapsed = collapsingDuplicates()
        let match = CatalogMatch(
            storedIDs: collapsed.placedAppIDs + collapsed.hidden.sorted { $0.path < $1.path }, catalog: catalog)

        var pages = collapsed.pages.map { page in
            Page(items: page.items.compactMap { match.resolvedItem($0) })
        }
        let hidden = Set(collapsed.hidden.map { match.resolved[$0] ?? $0 })

        let newApps = catalog.apps.filter { !match.matchedCatalogIDs.contains($0.id) }.sorted(
            by: InstalledApp.displayOrder)
        if pages.isEmpty {
            pages = [Page()]
        }
        pages[pages.count - 1].items += newApps.map { .app($0.id) }

        return Layout(pages: Self.normalized(pages, pageCapacity: pageCapacity), hidden: hidden)
    }

    /// Keeps the first occurrence of every app in reading order, and drops placed apps that are also hidden.
    private func collapsingDuplicates() -> Layout {
        var seen = Set<AppID>()
        func isFirstVisibleOccurrence(_ id: AppID) -> Bool {
            !hidden.contains(id) && seen.insert(id).inserted
        }

        var collapsedPages: [Page] = []
        for page in pages {
            var items: [Item] = []
            for item in page.items {
                switch item {
                case .app(let id):
                    if isFirstVisibleOccurrence(id) {
                        items.append(item)
                    }
                case .folder(var folder):
                    folder.apps = folder.apps.filter(isFirstVisibleOccurrence)
                    items.append(.folder(folder))
                }
            }
            collapsedPages.append(Page(items: items))
        }
        return Layout(pages: collapsedPages, hidden: hidden)
    }

    /// Dissolves folders with fewer than 2 apps, removes empty pages, and cascades overflow to later pages.
    private static func normalized(_ pages: [Page], pageCapacity: Int) -> [Page] {
        let nonEmptyPages =
            pages
            .map { Page(items: $0.items.compactMap(normalizedFolder)) }
            .filter { !$0.items.isEmpty }

        var result: [Page] = []
        var overflow: [Item] = []
        for page in nonEmptyPages {
            let items = overflow + page.items
            result.append(Page(items: Array(items.prefix(pageCapacity))))
            overflow = Array(items.dropFirst(pageCapacity))
        }
        while !overflow.isEmpty {
            result.append(Page(items: Array(overflow.prefix(pageCapacity))))
            overflow = Array(overflow.dropFirst(pageCapacity))
        }
        return result.isEmpty ? [Page()] : result
    }

    /// A folder with one app becomes that app in the same slot. A folder without apps disappears.
    private static func normalizedFolder(_ item: Item) -> Item? {
        guard case .folder(let folder) = item else {
            return item
        }
        switch folder.apps.count {
        case 0: return nil
        case 1: return .app(folder.apps[0])
        default: return item
        }
    }
}

/// The result of matching stored app IDs to the catalog.
private struct CatalogMatch {
    /// Each matched stored ID, mapped to the catalog's ID for the same app. The catalog's ID carries the
    /// current path and bundle identifier.
    private(set) var resolved: [AppID: AppID] = [:]
    /// Catalog apps that a stored ID matched.
    private(set) var matchedCatalogIDs: Set<AppID> = []

    /// `storedIDs` must be free of duplicates. Earlier IDs win when several could rebind to the same app.
    init(storedIDs: [AppID], catalog: Catalog) {
        for id in storedIDs {
            if let app = catalog[id] {
                resolved[id] = app.id
                matchedCatalogIDs.insert(app.id)
            }
        }

        var unmatchedByBundleIdentifier: [String: [AppID]] = [:]
        for app in catalog.apps where !matchedCatalogIDs.contains(app.id) {
            if let bundleIdentifier = app.id.bundleIdentifier {
                unmatchedByBundleIdentifier[bundleIdentifier, default: []].append(app.id)
            }
        }
        for id in storedIDs where resolved[id] == nil {
            guard
                let bundleIdentifier = id.bundleIdentifier,
                let candidates = unmatchedByBundleIdentifier[bundleIdentifier],
                candidates.count == 1
            else {
                continue
            }
            resolved[id] = candidates[0]
            matchedCatalogIDs.insert(candidates[0])
            unmatchedByBundleIdentifier[bundleIdentifier] = []
        }
    }

    /// The item with its apps resolved, or nil when nothing in it is installed. A folder keeps its matched apps.
    func resolvedItem(_ item: Item) -> Item? {
        switch item {
        case .app(let id):
            return resolved[id].map(Item.app)
        case .folder(var folder):
            folder.apps = folder.apps.compactMap { resolved[$0] }
            return .folder(folder)
        }
    }
}
