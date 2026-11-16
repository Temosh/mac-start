import MacStartCore
import Testing

/// Three columns. Page 0 is a full 3 x 3 page, page 1 holds 5 items (rows of 3 and 2), page 2 is empty.
@Suite("Grid navigation")
struct GridNavigationTests {
    let navigation = GridNavigation(columns: 3, itemCounts: [9, 5, 0])

    private func move(_ direction: GridDirection, from page: Int, _ slot: Int) -> GridPosition? {
        navigation.position(after: direction, from: GridPosition(page: page, slot: slot), onPage: page)
    }

    @Test func theFirstPressSelectsTheFirstItemOfTheCurrentPage() {
        #expect(navigation.position(after: .down, from: nil, onPage: 1) == GridPosition(page: 1, slot: 0))
    }

    @Test func aSelectionOnAnotherPageStartsOverOnTheCurrentPage() {
        let elsewhere = GridPosition(page: 0, slot: 4)

        #expect(navigation.position(after: .right, from: elsewhere, onPage: 1) == GridPosition(page: 1, slot: 0))
    }

    @Test func anInvalidSelectionStartsOver() {
        let gone = GridPosition(page: 1, slot: 7)

        #expect(navigation.position(after: .left, from: gone, onPage: 1) == GridPosition(page: 1, slot: 0))
    }

    @Test func nothingIsSelectedOnAnEmptyPage() {
        #expect(navigation.position(after: .right, from: nil, onPage: 2) == nil)
    }

    @Test func movesWithinAPage() {
        #expect(move(.right, from: 0, 4) == GridPosition(page: 0, slot: 5))
        #expect(move(.left, from: 0, 4) == GridPosition(page: 0, slot: 3))
        #expect(move(.up, from: 0, 4) == GridPosition(page: 0, slot: 1))
        #expect(move(.down, from: 0, 4) == GridPosition(page: 0, slot: 7))
    }

    @Test func rightFromTheLastColumnGoesToTheSameRowOfTheNextPage() {
        #expect(move(.right, from: 0, 2) == GridPosition(page: 1, slot: 0))
        #expect(move(.right, from: 0, 5) == GridPosition(page: 1, slot: 3))
    }

    @Test func leftFromTheFirstColumnGoesToTheSameRowOfThePreviousPage() {
        #expect(move(.left, from: 1, 3) == GridPosition(page: 0, slot: 5))
    }

    @Test func movesIntoAShorterRowClampToItsLastItem() {
        #expect(move(.down, from: 1, 2) == GridPosition(page: 1, slot: 4))
        #expect(move(.right, from: 0, 8) == GridPosition(page: 1, slot: 4))
    }

    @Test func movesPastTheOuterEdgeKeepTheSelection() {
        #expect(move(.left, from: 0, 3) == GridPosition(page: 0, slot: 3))
        #expect(move(.up, from: 0, 1) == GridPosition(page: 0, slot: 1))
        #expect(move(.down, from: 0, 7) == GridPosition(page: 0, slot: 7))
        #expect(move(.right, from: 1, 4) == GridPosition(page: 1, slot: 4))
    }
}
