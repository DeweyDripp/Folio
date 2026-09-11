import UIKit

/// Shares the same gesture and curl lifecycle between the EPUB and SwiftUI readers.
class PaperTurnController: UIViewController, UIGestureRecognizerDelegate {
    typealias RestorePage = @MainActor () async -> Void
    var usesPageTurnAnimation = true
    var canTurnPage: () -> Bool = { true }
    /// Move instantly underneath the paper and return an undo action, or nil at a book boundary.
    var prepareTurn: (@MainActor (Bool) async -> RestorePage?)?
    var paperColor: UIColor = .systemBackground
    private(set) var isTurning = false
    private var curl: PaperCurlView?
    private var cover: UIImageView?
    private var turnsLeft = true
    private var dragProgress: CGFloat = 0
    private var requestedCompletion: Bool?
    private var ready = false
    private final var restorePage: RestorePage?
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(dragged))

    override func viewDidLoad() {
        super.viewDidLoad()
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let velocity = pan.velocity(in: view)
        return !isTurning && canTurnPage() && abs(velocity.x) > abs(velocity.y) * 1.3
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Readium's horizontal scroll recognizer must wait for our curl gesture.
        // Vertical drags fail the test above and remain available to the content.
        otherGestureRecognizer is UIPanGestureRecognizer
    }

    @objc private func dragged(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            beginTurn(left: gesture.velocity(in: view).x < 0)
        case .changed:
            let distance = gesture.translation(in: view).x * (turnsLeft ? -1 : 1)
            dragProgress = min(0.95, max(0, distance / max(1, view.bounds.width)))
            if ready { curl?.setProgress(dragProgress) }
        case .ended:
            let velocity = gesture.velocity(in: view).x * (turnsLeft ? -1 : 1)
            requestedCompletion = dragProgress > 0.25 || velocity > 450
            completeIfReady()
        case .cancelled, .failed:
            requestedCompletion = false
            completeIfReady()
        default:
            break
        }
    }

    func turnByTap(left: Bool) {
        guard !isTurning, canTurnPage() else { return }
        beginTurn(left: left)
        requestedCompletion = true
        completeIfReady()
    }

    private func beginTurn(left: Bool) {
        guard !isTurning, let prepareTurn else { return }
        isTurning = true
        turnsLeft = left
        ready = false
        dragProgress = 0
        requestedCompletion = nil

        // Capture before changing the live page. A stationary cover masks layout work.
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        let image = renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }
        let cover = UIImageView(image: image)
        cover.frame = view.bounds
        cover.isUserInteractionEnabled = false
        view.addSubview(cover)
        self.cover = cover

        if usesPageTurnAnimation && !UIAccessibility.isReduceMotionEnabled {
            let curl = PaperCurlView(image: image, turnsLeft: left, paperColor: paperColor)
            curl.frame = view.bounds
            view.addSubview(curl)
            self.curl = curl
        }

        Task { @MainActor in
            restorePage = await prepareTurn(left)
            // Give the web view its next render cycle before revealing it.
            try? await Task.sleep(for: .milliseconds(80))
            ready = true
            if restorePage == nil {
                cleanUp()
                return
            }
            if curl != nil { cover.removeFromSuperview() }
            curl?.setProgress(dragProgress)
            if view.window == nil { requestedCompletion = false }
            completeIfReady()
        }
    }

    private func completeIfReady() {
        guard isTurning, ready, let commit = requestedCompletion else { return }
        ready = false
        if let curl {
            curl.finish(at: commit ? 1 : 0) { [weak self] in
                Task { @MainActor in await self?.finish(commit: commit) }
            }
        } else {
            Task { @MainActor in await finish(commit: commit) }
        }
    }

    private func finish(commit: Bool) async {
        if !commit {
            await restorePage?()
            try? await Task.sleep(for: .milliseconds(80))
        }
        cleanUp()
    }

    private func cleanUp() {
        curl?.removeFromSuperview()
        cover?.removeFromSuperview()
        curl = nil
        cover = nil
        restorePage = nil
        requestedCompletion = nil
        isTurning = false
        ready = false
    }
}
