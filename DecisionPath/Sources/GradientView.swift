import UIKit

/// 一层垂直渐隐。用来把文字从世界里托起来，而不用加一块实心面板。
final class GradientView: UIView {

    override class var layerClass: AnyClass { CAGradientLayer.self }

    private var gradient: CAGradientLayer { layer as! CAGradientLayer }

    func configure(top: UIColor, bottom: UIColor) {
        gradient.colors = [top.cgColor, bottom.cgColor]
        gradient.locations = [0, 1]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
    }
}
