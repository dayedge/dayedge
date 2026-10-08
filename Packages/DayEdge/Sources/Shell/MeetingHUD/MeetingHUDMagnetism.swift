import CoreGraphics

/// Pure horizontal magnetic resistance for the Meeting HUD.
///
/// The curve deliberately has no abrupt capture boundary: outside the
/// influence radius the raw position is returned unchanged, then a smoothstep
/// curve progressively compresses the remaining distance to the display's
/// vertical center line. Window movement and screen selection stay in
/// `MeetingHUDWindowController`; keeping the math here makes its feel stable,
/// symmetric, and directly testable without constructing an `NSPanel`.
struct MeetingHUDMagnetism {
    var influenceRadius: CGFloat = 80
    var exactSnapRadius: CGFloat = 6
    var releaseSnapRadius: CGFloat = 36

    func adjustedCenterX(rawCenterX: CGFloat, targetCenterX: CGFloat) -> CGFloat {
        let distance = rawCenterX - targetCenterX
        let absoluteDistance = abs(distance)

        guard influenceRadius > 0, absoluteDistance < influenceRadius else {
            return rawCenterX
        }
        guard absoluteDistance > exactSnapRadius else {
            return targetCenterX
        }

        let proximity = 1 - absoluteDistance / influenceRadius
        let attraction = proximity * proximity * (3 - 2 * proximity)
        return targetCenterX + distance * (1 - attraction)
    }

    func shouldSettleOnCenter(rawCenterX: CGFloat, targetCenterX: CGFloat) -> Bool {
        abs(rawCenterX - targetCenterX) <= releaseSnapRadius
    }
}
