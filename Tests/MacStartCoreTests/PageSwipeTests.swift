import MacStartCore
import Testing

@Suite("Page swipe")
struct PageSwipeTests {
    let width = 1800.0

    private func target(from page: Int = 1, offset: Double, velocity: Double) -> Int {
        PageSwipe.targetPage(from: page, pageCount: 3, offset: offset, velocity: velocity, pageWidth: width)
    }

    @Test func aShortFlickTurnsThePage() {
        #expect(target(offset: -40, velocity: -900) == 2)
        #expect(target(offset: 40, velocity: 900) == 0)
    }

    @Test func aSlowSwipeTurnsThePageOnlyAfterEnoughDistance() {
        #expect(target(offset: -100, velocity: -50) == 1)
        #expect(target(offset: -150, velocity: -50) == 2)
        #expect(target(offset: 150, velocity: 50) == 0)
    }

    @Test func aFlickBackCancelsTheSwipe() {
        #expect(target(offset: -400, velocity: 600) == 0)
    }

    @Test func theSwipeStaysWithinThePages() {
        #expect(target(from: 2, offset: -900, velocity: -2000) == 2)
        #expect(target(from: 0, offset: 900, velocity: 2000) == 0)
        #expect(PageSwipe.targetPage(from: 0, pageCount: 0, offset: -900, velocity: -2000, pageWidth: width) == 0)
    }
}
