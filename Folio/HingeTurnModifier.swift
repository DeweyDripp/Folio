import SwiftUI

/// Experimental forward-only hinge interaction for iPhone Duo.
/// The latch prevents the several callbacks emitted during one fold from
/// turning more than one page or spread.
@available(iOS 27.1, *)
private struct HingeTurnModifier: ViewModifier {
    let isEnabled: Bool
    let turnForward: () -> Void
    @State private var hasReachedPartiallyOpen = false
    @State private var didTurnForGesture = false
    @State private var peakAngle: Double?
    @State private var previousAngle: Double?

    func body(content: Content) -> some View {
        content.onHingeChange { _, context in
            guard let hinge = context.hinge else {
                hasReachedPartiallyOpen = false
                didTurnForGesture = false
                peakAngle = nil
                previousAngle = nil
                return
            }

            let angle = hinge.angle.degrees
            let movement = previousAngle.map { angle - $0 }
            previousAngle = angle

            if hinge.status == .closed {
                hasReachedPartiallyOpen = false
                didTurnForGesture = false
                peakAngle = nil
                return
            }

            // During one opening animation the simulator can report tiny
            // reversals. Ignore all of them after the first turn, and only
            // re-arm once the next closing motion is clearly underway.
            if didTurnForGesture {
                peakAngle = max(peakAngle ?? angle, angle)
                if angle < (peakAngle ?? angle) - 5 {
                    didTurnForGesture = false
                    hasReachedPartiallyOpen = true
                    peakAngle = angle
                }
                return
            }

            switch hinge.status {
            case .partiallyOpen:
                hasReachedPartiallyOpen = true
            case .fullyOpen:
                // A slight close/open may never cross the simulator's
                // discrete status thresholds, so use the angle reversal too.
                break
            case .closed:
                // Closing without reopening cancels the pending turn.
                hasReachedPartiallyOpen = false
            default:
                break
            }

            if movement ?? 0 < -0.5 {
                hasReachedPartiallyOpen = true
            } else if hasReachedPartiallyOpen,
                      movement ?? 0 > 0.5,
                      isEnabled {
                hasReachedPartiallyOpen = false
                didTurnForGesture = true
                peakAngle = angle
                turnForward()
            }
        }
    }
}

extension View {
    /// Turns forward once when a supported Duo enters its partially-open pose.
    /// On other devices this is a no-op.
    func hingeTurnsPage(isEnabled: Bool, turnForward: @escaping () -> Void) -> some View {
        if #available(iOS 27.1, *) {
            return AnyView(modifier(HingeTurnModifier(isEnabled: isEnabled, turnForward: turnForward)))
        }

        return AnyView(self)
    }
}
