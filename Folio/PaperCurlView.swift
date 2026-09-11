import UIKit

/// A temporary image of the page, bent around a cylinder as the finger moves.
/// The live reader stays underneath, so text selection works normally after a turn.
final class PaperCurlView: UIView {
    private let image: UIImage
    private let turnsLeft: Bool
    private var strips: [CALayer] = []
    private var backs: [CALayer] = []
    private let stripCount = 96
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var startProgress: CGFloat = 0
    private var targetProgress: CGFloat = 0
    private var completion: (() -> Void)?
    private(set) var progress: CGFloat = 0

    init(image: UIImage, turnsLeft: Bool, paperColor: UIColor) {
        self.image = image
        self.turnsLeft = turnsLeft
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        accessibilityIdentifier = "reader.paperCurl"
        clipsToBounds = true

        for index in 0..<stripCount {
            let strip = CALayer()
            strip.contents = image.cgImage
            strip.contentsScale = image.scale
            strip.contentsRect = CGRect(x: CGFloat(index) / CGFloat(stripCount), y: 0,
                                        width: 1 / CGFloat(stripCount), height: 1)
            strip.isDoubleSided = false
            layer.addSublayer(strip)
            strips.append(strip)

            let back = CALayer()
            back.backgroundColor = paperColor.cgColor
            back.isDoubleSided = false
            layer.addSublayer(back)
            backs.append(back)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        setProgress(progress)
    }

    func setProgress(_ value: CGFloat) {
        progress = min(1, max(0, value))
        let width = bounds.width
        let stripWidth = width / CGFloat(stripCount)
        let radius = max(12, width * 0.12)
        let fold = width - progress * (width + .pi * radius)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in 0..<stripCount {
            let sourceX = (CGFloat(index) + 0.5) * stripWidth
            let x = turnsLeft ? sourceX : width - sourceX
            let distance = max(0, x - fold)
            let angle = min(.pi, distance / radius)
            let bentX = distance == 0 ? x : fold + radius * sin(angle)
                - max(0, distance - .pi * radius)
            let screenX = turnsLeft ? bentX : width - bentX
            let z = radius * (1 - cos(angle))
            let rotation = turnsLeft ? -angle : angle

            let strip = strips[index]
            strip.bounds = CGRect(x: 0, y: 0, width: stripWidth + 0.6, height: bounds.height)
            strip.position = CGPoint(x: screenX, y: bounds.midY)
            strip.zPosition = z
            strip.transform = CATransform3DMakeRotation(rotation, 0, 1, 0)

            let back = backs[index]
            back.bounds = strip.bounds
            back.position = strip.position
            back.zPosition = z + 0.01
            back.transform = CATransform3DMakeRotation(rotation + .pi, 0, 1, 0)
            // A soft tonal change makes the bent paper read as a curved surface.
            back.opacity = Float(0.84 + 0.16 * abs(cos(angle)))
        }
        CATransaction.commit()
    }

    func finish(at target: CGFloat, completion: @escaping () -> Void) {
        displayLink?.invalidate()
        self.completion = completion
        startProgress = progress
        targetProgress = target
        startTime = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    @objc private func tick() {
        let elapsed = min(1, (CACurrentMediaTime() - startTime) / 0.28)
        let eased = CGFloat(1 - pow(1 - elapsed, 3))
        setProgress(startProgress + (targetProgress - startProgress) * eased)
        if elapsed >= 1 {
            displayLink?.invalidate()
            displayLink = nil
            let done = completion
            completion = nil
            done?()
        }
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil {
            displayLink?.invalidate()
            displayLink = nil
        }
        super.willMove(toWindow: newWindow)
    }
}
