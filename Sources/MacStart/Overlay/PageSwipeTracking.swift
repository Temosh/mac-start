import AppKit

/// The values of a scroll event that paging needs, copied out of the event so they can cross into main-actor code.
struct ScrollInput: Sendable {
    /// True for trackpads and the Magic Mouse, false for wheel mice.
    let isPrecise: Bool
    let deltaX: CGFloat
    let deltaY: CGFloat
    let phase: NSEvent.Phase
    let momentumPhase: NSEvent.Phase
    /// Seconds since system startup.
    let time: TimeInterval

    init(_ event: NSEvent) {
        isPrecise = event.hasPreciseScrollingDeltas
        deltaX = event.scrollingDeltaX
        deltaY = event.scrollingDeltaY
        phase = event.phase
        momentumPhase = event.momentumPhase
        time = event.timestamp
    }
}

/// A two-finger swipe in progress: how far it moved the pages, and how fast it was moving.
struct PageSwipeTracking {
    /// The horizontal distance moved, in points. Negative values move the pages left, toward the next page.
    private(set) var offset: CGFloat = 0
    /// Nil until the first movement shows the swipe's direction. Vertical swipes do not turn pages.
    private(set) var isHorizontal: Bool?
    /// The last moves, kept for the speed at the end.
    private var recentMoves: [(time: TimeInterval, deltaX: CGFloat)] = []

    /// How far back the speed at the end looks, in seconds.
    private static let speedWindow: TimeInterval = 0.1

    mutating func add(deltaX: CGFloat, deltaY: CGFloat, time: TimeInterval) {
        if isHorizontal == nil, deltaX != 0 || deltaY != 0 {
            isHorizontal = abs(deltaX) >= abs(deltaY)
        }
        guard isHorizontal == true else {
            return
        }
        offset += deltaX
        recentMoves.append((time, deltaX))
        recentMoves.removeAll { time - $0.time > Self.speedWindow }
    }

    /// The speed over the last tenth of a second before `time`, in points per second. Fingers that rested
    /// before lifting give zero, so a slow release never counts as a flick.
    func velocity(at time: TimeInterval) -> CGFloat {
        let moves = recentMoves.filter { time - $0.time <= Self.speedWindow }
        guard let first = moves.first, let last = moves.last, last.time > first.time else {
            return 0
        }
        let distance = moves.dropFirst().reduce(0) { $0 + $1.deltaX }
        return distance / CGFloat(last.time - first.time)
    }
}
