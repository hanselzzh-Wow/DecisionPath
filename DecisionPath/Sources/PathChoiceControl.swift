import UIKit

final class PathChoiceControl: UIControl {
    private let titleLabel = UILabel()
    private let diamondView = UIView()

    var accentColor: UIColor = Palette.accent {
        didSet {
            diamondView.backgroundColor = accentColor
            diamondView.layer.shadowColor = accentColor.cgColor
        }
    }

    var title: String {
        get { titleLabel.text ?? "" }
        set {
            titleLabel.text = newValue
            accessibilityLabel = newValue
        }
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.2) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.965, y: 0.965).translatedBy(x: 0, y: 3)
                    : .identity
                self.layer.shadowOpacity = self.isHighlighted ? 0.12 : 0.22
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        isAccessibilityElement = true
        accessibilityTraits = .button

        backgroundColor = Palette.cloud.withAlphaComponent(0.91)
        layer.cornerRadius = 3
        layer.borderWidth = 0.7
        layer.borderColor = Palette.cloud.withAlphaComponent(0.8).cgColor
        layer.shadowColor = Palette.ink.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowOffset = CGSize(width: 5, height: 7)
        layer.shadowRadius = 0

        titleLabel.font = UIFont(name: "Songti SC", size: 16) ?? .systemFont(ofSize: 16, weight: .medium)
        titleLabel.textColor = Palette.ink
        titleLabel.numberOfLines = 2
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true

        diamondView.backgroundColor = accentColor
        diamondView.transform = CGAffineTransform(rotationAngle: .pi / 4)
        diamondView.layer.cornerRadius = 2
        diamondView.layer.shadowColor = accentColor.cgColor
        diamondView.layer.shadowOpacity = 0.38
        diamondView.layer.shadowRadius = 6

        [titleLabel, diamondView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            diamondView.centerXAnchor.constraint(equalTo: centerXAnchor),
            diamondView.topAnchor.constraint(equalTo: topAnchor, constant: -5),
            diamondView.widthAnchor.constraint(equalToConstant: 12),
            diamondView.heightAnchor.constraint(equalToConstant: 12),

            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -13)
        ])
    }
}

enum Palette {
    static let canvasTop = UIColor(red: 0.965, green: 0.942, blue: 0.887, alpha: 1)
    static let canvasBottom = UIColor(red: 0.906, green: 0.859, blue: 0.775, alpha: 1)
    static let surface = UIColor(red: 0.992, green: 0.973, blue: 0.925, alpha: 1)
    static let road = UIColor(red: 0.405, green: 0.39, blue: 0.36, alpha: 1)
    static let sidewalk = UIColor(red: 0.90, green: 0.855, blue: 0.765, alpha: 1)
    static let ink = UIColor(red: 0.145, green: 0.137, blue: 0.122, alpha: 1)
    static let fadedInk = UIColor(red: 0.35, green: 0.33, blue: 0.29, alpha: 1)
    static let accent = UIColor(red: 0.66, green: 0.32, blue: 0.20, alpha: 1)
    static let buildingWall = UIColor(red: 0.88, green: 0.79, blue: 0.66, alpha: 1)
    static let roof = UIColor(red: 0.78, green: 0.65, blue: 0.53, alpha: 1)
    static let roofAccent = UIColor(red: 0.70, green: 0.42, blue: 0.31, alpha: 1)
    static let foliage = UIColor(red: 0.41, green: 0.45, blue: 0.35, alpha: 1)
    static let foliageLight = UIColor(red: 0.62, green: 0.62, blue: 0.47, alpha: 1)

    static let cloud = surface
    static let copper = accent
    static let paper = canvasBottom
    static let paperLight = surface
}
