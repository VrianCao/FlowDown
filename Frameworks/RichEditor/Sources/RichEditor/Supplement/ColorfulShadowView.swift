import ColorfulX
import UIKit

final class ColorfulShadowView: UIView {
    enum Mode: Equatable {
        case idle
        case appleIntelligence
    }

    struct Geometry: Equatable {
        var innerRect: CGRect
        var cornerRadius: CGFloat
        var blur: CGFloat
        var offset: CGSize

        static let zero = Geometry(
            innerRect: .zero,
            cornerRadius: 0,
            blur: 0,
            offset: .zero
        )
    }

    private let director: SpeckleAnimationRoundedRectangleDirector
    private let gradientView: AnimatedMulticolorGradientView
    private let maskLayer = CALayer()

    var shadowRadius: CGFloat = 1.0 {
        didSet {
            guard shadowRadius != oldValue else { return }
            needsMaskUpdate = true
            setNeedsLayout()
        }
    }

    private var geometry: Geometry = .zero {
        didSet {
            guard geometry != oldValue else { return }
            needsMaskUpdate = true
            setNeedsLayout()
        }
    }

    private var needsMaskUpdate = true
    private var lastBoundsSize: CGSize = .zero

    var mode: Mode = .idle {
        didSet { applyCurrentMode() }
    }

    private static let idlePalette: [ColorElement] = [
        UIColor(white: 0.0, alpha: 0.10),
    ]

    override init(frame: CGRect) {
        director = SpeckleAnimationRoundedRectangleDirector(
            inset: -0.2,
            cornerRadius: 1,
            direction: .clockwise,
            movementRate: 0.05,
            positionResponseRate: 1.5
        )
        gradientView = AnimatedMulticolorGradientView(animationDirector: director)
        super.init(frame: frame)

        isUserInteractionEnabled = false
        gradientView.isUserInteractionEnabled = false
        gradientView.backgroundColor = .clear
        gradientView.transitionSpeed = 32
        gradientView.noise = 0
        gradientView.bias /= 400_000
        addSubview(gradientView)
        maskLayer.contentsScale = layer.contentsScale
        gradientView.layer.mask = maskLayer

        // Add saturation filter using private API
        if let filterClass = NSClassFromString("CAFilter") as? NSObject.Type {
            let filter = filterClass.init()
            filter.setValue("colorSaturate", forKey: "name")
            filter.setValue(1.5, forKey: "inputAmount")
            gradientView.layer.setValue([filter], forKey: "filters")
        }

        applyCurrentMode()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        gradientView.frame = bounds

        if needsMaskUpdate || lastBoundsSize != bounds.size {
            regenerateMask()
            lastBoundsSize = bounds.size
        }
    }

    func updateGeometry(_ geometry: Geometry) {
        self.geometry = geometry
    }
}

private extension ColorfulShadowView {
    func regenerateMask() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard geometry.innerRect.width > 0, geometry.innerRect.height > 0 else { return }

        let scale: CGFloat
        #if targetEnvironment(macCatalyst)
            scale = window?.screen.scale ?? UIScreen.main.scale
        #else
            scale = window?.screen.scale ?? UIScreen.main.scale
        #endif

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        let path = UIBezierPath(roundedRect: geometry.innerRect, cornerRadius: geometry.cornerRadius)
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            let cgContext = context.cgContext

            cgContext.saveGState()
            cgContext.setShadow(offset: geometry.offset, blur: geometry.blur * shadowRadius, color: UIColor.white.cgColor)
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.addPath(path.cgPath)
            cgContext.fillPath()
            cgContext.restoreGState()

            cgContext.saveGState()
            cgContext.setBlendMode(.clear)
            cgContext.addPath(path.cgPath)
            cgContext.fillPath()
            cgContext.restoreGState()
        }

        maskLayer.contentsScale = scale
        maskLayer.frame = bounds
        maskLayer.contents = image.cgImage

        needsMaskUpdate = false
    }

    func applyCurrentMode() {
        switch mode {
        case .idle:
            shadowRadius = 1.0
            gradientView.setColors(Self.idlePalette, animated: true, repeats: true)
        case .appleIntelligence:
            shadowRadius = 2
            gradientView.setColors(ColorfulPreset.appleIntelligence, animated: true, repeats: true)
        }
    }
}
