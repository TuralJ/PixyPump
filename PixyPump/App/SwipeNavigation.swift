import SwiftUI

/// The bottom tabs, in order.
enum AppTab: Int, CaseIterable {
    case home, workout, progress, food
}

extension EnvironmentValues {
    /// Jump straight to a tab (used by the Home screen's buttons).
    @Entry var selectTab: (AppTab) -> Void = { _ in }
}

extension View {
    /// Detects a clear left/right swipe. Calls `onSwipe(+1)` for a swipe to the
    /// left (next) and `onSwipe(-1)` for a swipe to the right (previous).
    /// Vertical scrolling is unaffected, and swipes starting at the very left
    /// edge are ignored so the system "back" swipe keeps working.
    func horizontalSwipe(_ onSwipe: @escaping (Int) -> Void) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .global)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > 80,
                          abs(dx) > abs(dy) * 2,
                          value.startLocation.x > 30
                    else { return }
                    onSwipe(dx < 0 ? 1 : -1)
                }
        )
    }
}
