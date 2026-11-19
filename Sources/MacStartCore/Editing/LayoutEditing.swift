import Foundation

/// Where an item sits in the layout: a top-level slot, or an app inside a folder.
public enum LayoutLocation: Hashable, Sendable {
    case slot(GridPosition)
    case inFolder(UUID, index: Int)
}

extension Folder {
    /// The name for a new folder: the category of the app dropped onto, else the category of the dropped app,
    /// else "Folder".
    public static func defaultName(target: InstalledApp?, dropped: InstalledApp?) -> String {
        target?.categoryName ?? dropped?.categoryName ?? "Folder"
    }

    /// The name for a new folder made from several apps: the category of the first app that has one, else
    /// "Folder".
    public static func defaultName(for apps: [InstalledApp]) -> String {
        apps.lazy.compactMap(\.categoryName).first ?? "Folder"
    }
}

/// Edits made by the user. Each edit leaves the layout normalized: folders with fewer than 2 apps dissolve and
/// empty pages go away. An edit never pushes an item to the next page: one that would overfill a page is refused
/// and changes nothing, so the user's arrangement of every page stays as it is. Positions are counted as the
/// overlay shows them during a drag, which is with the dragged item already taken out.
extension Layout {
    /// The slot of the folder with `id`.
    public func position(ofFolder id: UUID) -> GridPosition? {
        for (pageIndex, page) in pages.enumerated() {
            for (slot, item) in page.items.enumerated() {
                if case .folder(let folder) = item, folder.id == id {
                    return GridPosition(page: pageIndex, slot: slot)
                }
            }
        }
        return nil
    }

    /// The item at `location`. For an app inside a folder, that is the app.
    public func item(at location: LayoutLocation) -> Item? {
        switch location {
        case .slot(let position):
            guard pages.indices.contains(position.page), pages[position.page].items.indices.contains(position.slot)
            else {
                return nil
            }
            return pages[position.page].items[position.slot]
        case .inFolder(let folderID, let index):
            guard
                let position = position(ofFolder: folderID),
                case .folder(let folder) = pages[position.page].items[position.slot],
                folder.apps.indices.contains(index)
            else {
                return nil
            }
            return .app(folder.apps[index])
        }
    }

    /// Moves the item at `source` to `destination`. The item lands in the destination slot, and the items from
    /// there on move one slot later. A destination page one past the last page adds a page. An app moved out of
    /// a folder leaves the folder. Returns false, and changes nothing, when the destination page has no room.
    @discardableResult
    public mutating func moveItem(from source: LayoutLocation, to destination: GridPosition, pageCapacity: Int) -> Bool
    {
        var edited = self
        guard let item = edited.extractItem(at: source) else {
            return false
        }
        let page = min(max(destination.page, 0), edited.pages.count)
        if page == edited.pages.count {
            edited.pages.append(Page())
        }
        let slot = min(max(destination.slot, 0), edited.pages[page].items.count)
        edited.pages[page].items.insert(item, at: slot)
        return apply(edited.pages, pageCapacity: pageCapacity)
    }

    /// Drops the app at `source` onto the item at `target`. Onto an app, the two make a new folder in the
    /// target's slot, named by `newFolderName` from the target app and the dropped app. Onto a folder, the app
    /// joins it at the end. Returns the folder's identifier, or nil when nothing changed because the source is a
    /// folder or a position is invalid.
    @discardableResult
    public mutating func dropApp(
        from source: LayoutLocation,
        onto target: GridPosition,
        newFolderName: (_ target: AppID, _ dropped: AppID) -> String,
        pageCapacity: Int
    ) -> UUID? {
        guard case .app(let droppedID)? = item(at: source) else {
            return nil
        }
        var edited = self
        _ = edited.extractItem(at: source)
        guard
            edited.pages.indices.contains(target.page),
            edited.pages[target.page].items.indices.contains(target.slot)
        else {
            return nil
        }
        let folder: Folder
        switch edited.pages[target.page].items[target.slot] {
        case .app(let targetID):
            folder = Folder(name: newFolderName(targetID, droppedID), apps: [targetID, droppedID])
        case .folder(var existing):
            existing.apps.append(droppedID)
            folder = existing
        }
        edited.pages[target.page].items[target.slot] = .folder(folder)
        guard edited.apply(edited.pages, pageCapacity: pageCapacity) else {
            return nil
        }
        self = edited
        return folder.id
    }

    /// Moves an app out of its folder into the slot right after the folder. Returns false, and changes nothing,
    /// when the folder's page has no room.
    @discardableResult
    public mutating func removeApp(fromFolder id: UUID, at index: Int, pageCapacity: Int) -> Bool {
        guard let position = position(ofFolder: id) else {
            return false
        }
        return moveItem(
            from: .inFolder(id, index: index),
            to: GridPosition(page: position.page, slot: position.slot + 1),
            pageCapacity: pageCapacity
        )
    }

    /// Moves the given apps out of a folder into the slots right after it, in the folder's order. Apps that are
    /// not in the folder stay where they are. A folder left with one app dissolves into it. Returns false, and
    /// changes nothing, when the folder's page has no room for them.
    @discardableResult
    public mutating func removeApps(_ apps: Set<AppID>, fromFolder id: UUID, pageCapacity: Int) -> Bool {
        guard
            let position = position(ofFolder: id),
            case .folder(var folder) = pages[position.page].items[position.slot]
        else {
            return false
        }
        let removed = folder.apps.filter(apps.contains)
        guard !removed.isEmpty else {
            return false
        }
        var edited = pages
        folder.apps.removeAll(where: apps.contains)
        edited[position.page].items[position.slot] = .folder(folder)
        edited[position.page].items.insert(contentsOf: removed.map(Item.app), at: position.slot + 1)
        return apply(edited, pageCapacity: pageCapacity)
    }

    /// True when the apps can leave the folder without overfilling its page.
    public func canRemoveApps(_ apps: Set<AppID>, fromFolder id: UUID, pageCapacity: Int) -> Bool {
        var trial = self
        return trial.removeApps(apps, fromFolder: id, pageCapacity: pageCapacity)
    }

    /// Reorders an app inside its folder. `destination` counts without the moved app.
    public mutating func moveApp(inFolder id: UUID, from index: Int, to destination: Int) {
        guard
            let position = position(ofFolder: id),
            case .folder(var folder) = pages[position.page].items[position.slot],
            folder.apps.indices.contains(index)
        else {
            return
        }
        let app = folder.apps.remove(at: index)
        folder.apps.insert(app, at: min(max(destination, 0), folder.apps.count))
        pages[position.page].items[position.slot] = .folder(folder)
    }

    /// Moves the items with the given identifiers to the end of `page`, in reading order: page by page and slot by
    /// slot, with the apps of a folder in the folder's order. An app inside a folder leaves the folder. A page one
    /// past the last page adds as many pages at the end as the items fill. Returns false, and changes nothing,
    /// when nothing moves or the page has no room for all of them.
    @discardableResult
    public mutating func moveItems(_ ids: Set<Item.ID>, toPage page: Int, pageCapacity: Int) -> Bool {
        var pages = self.pages
        var moved: [Item] = []
        for pageIndex in pages.indices {
            var kept: [Item] = []
            for item in pages[pageIndex].items {
                if ids.contains(item.id) {
                    moved.append(item)
                    continue
                }
                if case .folder(var folder) = item {
                    moved += folder.apps.filter { ids.contains(.app($0)) }.map(Item.app)
                    folder.apps.removeAll { ids.contains(.app($0)) }
                    kept.append(.folder(folder))
                } else {
                    kept.append(item)
                }
            }
            pages[pageIndex].items = kept
        }
        guard !moved.isEmpty else {
            return false
        }
        // Emptied pages stay until normalizing, so `page` still counts the pages as they were.
        let target = min(max(page, 0), pages.count)
        if target == pages.count {
            let size = max(pageCapacity, 1)
            for start in stride(from: 0, to: moved.count, by: size) {
                pages.append(Page(items: Array(moved[start..<min(start + size, moved.count)])))
            }
        } else {
            pages[target].items += moved
        }
        return apply(pages, pageCapacity: pageCapacity)
    }

    /// True when the items can move to `page` without overfilling it.
    public func canMoveItems(_ ids: Set<Item.ID>, toPage page: Int, pageCapacity: Int) -> Bool {
        var trial = self
        return trial.moveItems(ids, toPage: page, pageCapacity: pageCapacity)
    }

    /// The folders in reading order.
    public var foldersInReadingOrder: [Folder] {
        pages.flatMap(\.items).compactMap { item in
            if case .folder(let folder) = item {
                return folder
            }
            return nil
        }
    }

    /// Moves the given apps to the end of the folder with `id`, in reading order. Apps leave their slots or their
    /// folders; apps already in the folder stay where they are in it. A folder left with one app dissolves into
    /// it. Returns false, and changes nothing, when the folder is missing or none of the apps moves.
    @discardableResult
    public mutating func moveApps(_ apps: Set<AppID>, toFolder id: UUID, pageCapacity: Int) -> Bool {
        guard
            let position = position(ofFolder: id),
            case .folder(let target) = pages[position.page].items[position.slot]
        else {
            return false
        }
        let moving = apps.subtracting(target.apps)
        let ordered = pages.flatMap(\.items).flatMap(\.appIDs).filter(moving.contains)
        guard !ordered.isEmpty else {
            return false
        }
        var pages = self.pages
        for pageIndex in pages.indices {
            pages[pageIndex].items = pages[pageIndex].items.compactMap { item in
                switch item {
                case .app(let appID):
                    return moving.contains(appID) ? nil : item
                case .folder(var folder) where folder.id == id:
                    folder.apps += ordered
                    return .folder(folder)
                case .folder(var folder):
                    folder.apps.removeAll(where: moving.contains)
                    return .folder(folder)
                }
            }
        }
        return apply(pages, pageCapacity: pageCapacity)
    }

    /// True when at least one of the apps can move into the folder.
    public func canMoveApps(_ apps: Set<AppID>, toFolder id: UUID, pageCapacity: Int) -> Bool {
        var trial = self
        return trial.moveApps(apps, toFolder: id, pageCapacity: pageCapacity)
    }

    /// Makes a folder of the given apps, in reading order, where the first of them is: in that app's slot, or right
    /// after the folder that holds it. `name` names the folder from its apps. Returns the folder's identifier, or
    /// nil, changing nothing, when fewer than 2 of the apps are placed or the page has no room for the folder.
    @discardableResult
    public mutating func makeFolder(
        of apps: Set<AppID>,
        named name: (_ apps: [AppID]) -> String,
        pageCapacity: Int
    ) -> UUID? {
        let ordered = pages.flatMap(\.items).flatMap(\.appIDs).filter(apps.contains)
        guard ordered.count >= 2 else {
            return nil
        }
        let folder = Folder(name: name(ordered), apps: ordered)
        var pages = self.pages
        var isPlaced = false
        for pageIndex in pages.indices {
            var kept: [Item] = []
            for item in pages[pageIndex].items {
                switch item {
                case .app(let id) where apps.contains(id):
                    if !isPlaced {
                        kept.append(.folder(folder))
                        isPlaced = true
                    }
                case .folder(var existing):
                    let holdsFirstApp = !isPlaced && existing.apps.contains(where: apps.contains)
                    existing.apps.removeAll(where: apps.contains)
                    kept.append(.folder(existing))
                    if holdsFirstApp {
                        kept.append(.folder(folder))
                        isPlaced = true
                    }
                case .app:
                    kept.append(item)
                }
            }
            pages[pageIndex].items = kept
        }
        return apply(pages, pageCapacity: pageCapacity) ? folder.id : nil
    }

    /// True when the apps can make a folder without overfilling a page.
    public func canMakeFolder(of apps: Set<AppID>, pageCapacity: Int) -> Bool {
        var trial = self
        return trial.makeFolder(of: apps, named: { _ in "" }, pageCapacity: pageCapacity) != nil
    }

    /// Where page `page` of `previous` is in this layout, after an edit that took the items in `taken`. Pages carry
    /// no identity, and an edit drops the pages it empties, so the page is found by an item it kept: an app that
    /// was not taken, or a folder that lost none of its apps. A page that kept no item is placed right after the
    /// nearest earlier page that did. The result is a valid page index.
    public func index(ofPage page: Int, in previous: Layout, taking taken: Set<Item.ID>) -> Int {
        let lastPage = max(pages.count - 1, 0)
        guard previous.pages.indices.contains(page) else {
            return min(max(page, 0), lastPage)
        }
        for candidate in stride(from: page, through: 0, by: -1) {
            guard
                let kept = previous.pages[candidate].items.first(where: { !Self.isTouched($0, by: taken) }),
                let index = pages.firstIndex(where: { $0.items.contains { $0.id == kept.id } })
            else {
                continue
            }
            return min(index + (candidate == page ? 0 : 1), lastPage)
        }
        return min(page, lastPage)
    }

    /// True when an edit that takes `taken` moves the item or changes what it holds.
    private static func isTouched(_ item: Item, by taken: Set<Item.ID>) -> Bool {
        taken.contains(item.id) || item.appIDs.contains { taken.contains(.app($0)) }
    }

    /// Hides an app. Reconcile then takes it out of its slot or folder, because hidden wins over placement.
    public mutating func hide(_ id: AppID) {
        hidden.insert(id)
    }

    /// Unhides an app. Reconcile then appends it to the last page, like a newly installed app.
    public mutating func unhide(_ id: AppID) {
        hidden.remove(id)
    }

    /// Renames a folder. Surrounding whitespace is dropped, and an empty name keeps the old one.
    public mutating func renameFolder(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmed.isEmpty,
            let position = position(ofFolder: id),
            case .folder(var folder) = pages[position.page].items[position.slot]
        else {
            return
        }
        folder.name = trimmed
        pages[position.page].items[position.slot] = .folder(folder)
    }

    /// Takes `edited` as the new pages once they are normalized, unless a page would hold more items than fit.
    /// Returns false, and changes nothing, in that case.
    private mutating func apply(_ edited: [Page], pageCapacity: Int) -> Bool {
        // No cascade: a capacity no page reaches keeps every item on its page, so overfilled pages show.
        let normalized = Self.normalized(edited, pageCapacity: .max)
        guard normalized.allSatisfy({ $0.items.count <= pageCapacity }) else {
            return false
        }
        pages = normalized
        return true
    }

    /// Takes the item at `source` out without normalizing, so every other position stays valid. A folder that
    /// loses an app keeps its slot, even with a single app left.
    private mutating func extractItem(at source: LayoutLocation) -> Item? {
        switch source {
        case .slot(let position):
            guard pages.indices.contains(position.page), pages[position.page].items.indices.contains(position.slot)
            else {
                return nil
            }
            return pages[position.page].items.remove(at: position.slot)
        case .inFolder(let folderID, let index):
            guard
                let position = position(ofFolder: folderID),
                case .folder(var folder) = pages[position.page].items[position.slot],
                folder.apps.indices.contains(index)
            else {
                return nil
            }
            let app = folder.apps.remove(at: index)
            pages[position.page].items[position.slot] = .folder(folder)
            return .app(app)
        }
    }
}
