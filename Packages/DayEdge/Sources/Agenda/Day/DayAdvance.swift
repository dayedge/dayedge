import SwiftUI

/// Stepping to another day: the new day arrives from the side it lies on —
/// a few points and a fade, never a page slide. Each step restarts it, so
/// rapid stepping stays responsive. Reduce Motion: a short fade, no movement.
struct DayAdvance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let date: Date
    /// Hidden, the view follows Month's selected day: nothing to show.
    let isActive: Bool

    @State private var startOffset: CGFloat = 0
    @State private var step = 0

    private struct Frame {
        var x: CGFloat = 0
        var opacity: Double = 1
    }

    static let distance: CGFloat = 12

    /// Where the arriving day starts: right of its place for a later day,
    /// left for an earlier one.
    static func startOffset(from old: Date, to new: Date, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion, new != old else { return 0 }
        return new > old ? distance : -distance
    }

    func body(content: Content) -> some View {
        let duration = reduceMotion ? 0.1 : 0.17
        content
            .keyframeAnimator(initialValue: Frame(), trigger: step) { view, frame in
                view.offset(x: frame.x).opacity(frame.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.x) {
                    MoveKeyframe(startOffset)
                    LinearKeyframe(0, duration: duration, timingCurve: .easeOut)
                }
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(0)
                    LinearKeyframe(1, duration: duration, timingCurve: .easeOut)
                }
            }
            .onChange(of: date) { old, new in
                guard isActive else { return }
                startOffset = Self.startOffset(from: old, to: new, reduceMotion: reduceMotion)
                step += 1
            }
    }
}
