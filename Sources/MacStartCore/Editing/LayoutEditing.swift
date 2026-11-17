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

/// Edits from dragging and the folder panel. Each edit leaves the layout normalized: folders with fewer than 2
/// apps dissolve, empty pages go away, and items that do not fit a page move onto the next one. Positions are
/// counted as the overlay shows them during a drag, which is with the dragged item already taken out.
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
    /// a folder leaves the folder.
    public mutating func moveItem(from source: LayoutLocation, to destination: GridPosition, pageCapacity: Int) {
        guard let item = extractItem(at: source) else {
            return
        }
        let page = min(max(destination.page, 0), pages.count)
        if page == pages.count {
            pages.append(Page())
        }
        let slot = min(max(destination.slot, 0), pages[page].items.count)
        pages[page].items.insert(item, at: slot)
        pages = Self.normalized(pages, pageCapacity: pageCapacity)
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
        edited.pages = Self.normalized(edited.pages, pageCapacity: pageCapacity)
        self = edited
        return folder.id
    }

    /// Moves an app out of its folder into the slot right after the folder.
    public mutating func removeApp(fromFolder id: UUID, at index: Int, pageCapacity: Int) {
        guard let position = position(ofFolder: id) else {
            return
        }
        moveItem(
            from: .inFolder(id, index: index),
            to: GridPosition(page: position.page, slot: position.slot + 1),
            pageCapacity: pageCapacity
        )
    }

    /// Moves the given apps out of a folder into the slots right after it, in the folder's order. Apps that are
    /// not in the folder stay where they are. A folder left with one app dissolves into it.
    public mutating func removeApps(_ apps: Set<AppID>, fromFolder id: UUID, pageCapacity: Int) {
        guard
            let position = position(ofFolder: id),
            case .folder(var folder) = pages[position.page].items[position.slot]
        else {
            return
        }
        let removed = folder.apps.filter(apps.contains)
        guard !removed.isEmpty else {
            return
        }
        folder.apps.removeAll(where: apps.contains)
        pages[position.page].items[position.slot] = .folder(folder)
        pages[position.page].items.insert(contentsOf: removed.map(Item.app), at: position.slot + 1)
        pages = Self.normalized(pages, pageCapacity: pageCapacity)
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
    /// past the last page adds a page, and items that do not fit move on to the next page.
    public mutating func moveItems(_ ids: Set<Item.ID>, toPage page: Int, pageCapacity: Int) {
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
            return
        }
        // Emptied pages stay until normalizing, so `page` still counts the pages as they were.
        let target = min(max(page, 0), pages.count)
        if target == pages.count {
            pages.append(Page())
        }
        pages[target].items += moved
        pages = Self.normalized(pages, pageCapacity: pageCapacity)
    }

    /// Makes a folder of the given apps, in reading order, where the first of them is: in that app's slot, or right
    /// after the folder that holds it. `name` names the folder from its apps. Returns the folder's identifier, or
    /// nil when fewer than 2 of the apps are placed.
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
        pages = Self.normalized(pages, pageCapacity: pageCapacity)
        return folder.id
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
