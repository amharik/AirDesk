import SwiftUI

struct LocalCursorOverlay: View {
    @ObservedObject var presentation: LocalCursorPresentation

    var body: some View {
        TimelineView(.animation) { timeline in
            if let frame = presentation.frame(
                at: timeline.date.timeIntervalSinceReferenceDate
            ) {
                GeometryReader { proxy in
                    let size = frame.shape.nominalSize
                    let originX = frame.point.x * proxy.size.width - frame.hotspot.x * size
                    let originY = frame.point.y * proxy.size.height - frame.hotspot.y * size
                    Image(systemName: frame.shape.systemImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                        .foregroundStyle(Color.white)
                        .shadow(color: Color.black.opacity(0.65), radius: 2, x: 0, y: 1)
                        .position(x: originX + size / 2, y: originY + size / 2)
                }
            } else {
                Color.clear
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
