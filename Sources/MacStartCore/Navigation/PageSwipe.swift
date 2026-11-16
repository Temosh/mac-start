/// Decides where a finished two-finger swipe lands, like Launchpad: a short flick is enough to turn the page.
public enum PageSwipe {
    /// The share of the page width a slow swipe has to move to turn the page.
    public static let distanceRatio = 0.08
    /// The speed, in points per second, from which a swipe turns the page whatever its distance.
    public static let flickSpeed = 300.0

    /// The page a swipe lands on. `offset` is how far the content moved, and `velocity` how fast it moved at the
    /// end, both in points; negative values move the content left, toward the next page. A flick decides by its
    /// direction, even against the distance moved; a slow swipe decides by distance. A swipe moves one page at
    /// most and stays within the pages.
    public static func targetPage(
        from currentPage: Int,
        pageCount: Int,
        offset: Double,
        velocity: Double,
        pageWidth: Double
    ) -> Int {
        let step: Int
        if abs(velocity) >= flickSpeed {
            step = velocity < 0 ? 1 : -1
        } else if abs(offset) >= pageWidth * distanceRatio {
            step = offset < 0 ? 1 : -1
        } else {
            step = 0
        }
        return min(max(currentPage + step, 0), max(pageCount - 1, 0))
    }
}
