import SwiftUI

extension View {
    /// One line that never wraps or ellipsizes: text longer than the room
    /// runs on and fades out over its last `fade` points (a short title
    /// ends before the fade, so it's untouched). It never asks for more
    /// width than it's given: the full line is drawn as an overlay on a
    /// shrinkable one-line placeholder, so a long title can't widen its
    /// row or the panel.
    package func fadingOverflow(fade: CGFloat = 24) -> some View {
        lineLimit(1)
            .hidden()
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .clipped()
            .mask(
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: fade)
                }
            )
    }
}
