import SwiftUI

/// Hosts text/PDF pages in the same interactive paper renderer as EPUBs.
struct PaperPageContainer<Content: View>: UIViewControllerRepresentable {
    @Binding var page: Int
    let pageCount: Int
    let step: Int
    let animated: Bool
    let paperColor: Color
    let content: (Int) -> Content

    func makeUIViewController(context: Context) -> Controller {
        Controller(page: page, content: content(page))
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.usesPageTurnAnimation = animated
        controller.paperColor = UIColor(paperColor)
        controller.prepareTurn = { [weak controller] left in
            guard let controller else { return nil }
            let original = controller.displayedPage
            let target = controller.requestedPage ?? (original + (left ? step : -step))
            controller.requestedPage = nil
            guard target >= 0, target < pageCount else { return nil }
            controller.displayedPage = target
            controller.host.rootView = content(target)
            page = target
            return {
                controller.displayedPage = original
                controller.host.rootView = content(original)
                page = original
            }
        }
        guard !controller.isTurning else { return }
        if page != controller.displayedPage {
            controller.requestedPage = page
            controller.turnByTap(left: page > controller.displayedPage)
        } else {
            controller.host.rootView = content(page)
        }
    }

    final class Controller: PaperTurnController {
        let host: UIHostingController<Content>
        var displayedPage: Int
        var requestedPage: Int?

        init(page: Int, content: Content) {
            displayedPage = page
            host = UIHostingController(rootView: content)
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidLoad() {
            super.viewDidLoad()
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
            host.didMove(toParent: self)
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            view.addGestureRecognizer(tap)
        }

        @objc private func tapped(_ gesture: UITapGestureRecognizer) {
            let x = gesture.location(in: view).x
            if x < view.bounds.width * 0.2 { turnByTap(left: false) }
            if x > view.bounds.width * 0.8 { turnByTap(left: true) }
        }
    }
}
