import UIKit

/// 场景化的 1–10 刻度。
///
/// 数据里存数字，给用户看的永远是三个词（虚脱／正常／满电）。
/// 不用 emoji 代替语言 —— PRD 14.4：emoji 只用于评分功能符号，不代替洞察的语言精度。
final class OutcomeScaleControl: UIControl {

    var scale: MetricScale = .satisfaction {
        didSet { applyScale() }
    }

    private(set) var value: Int? {
        didSet {
            guard value != oldValue else { return }
            applySelection()
            if value != nil { sendActions(for: .valueChanged) }
        }
    }

    private let lowLabel = UILabel()
    private let highLabel = UILabel()
    private let stack = UIStackView()
    private var stops: [UIButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func reset() {
        value = nil
    }

    private func build() {
        for label in [lowLabel, highLabel] {
            label.font = UIFont(name: "Songti SC", size: 13) ?? .systemFont(ofSize: 13)
            label.textColor = Palette.fadedInk
            label.adjustsFontForContentSizeCategory = true
            label.translatesAutoresizingMaskIntoConstraints = false
        }
        highLabel.textAlignment = .right

        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        for index in 1...10 {
            let stop = UIButton(type: .custom)
            stop.tag = index
            stop.setTitle("\(index)", for: .normal)
            stop.titleLabel?.font = UIFont(name: "Songti SC", size: 15) ?? .systemFont(ofSize: 15)
            stop.setTitleColor(Palette.fadedInk, for: .normal)
            stop.backgroundColor = Palette.surface.withAlphaComponent(0.85)
            stop.layer.cornerRadius = 8
            stop.layer.borderWidth = 1
            stop.layer.borderColor = Palette.fadedInk.withAlphaComponent(0.22).cgColor
            // 44pt 点击区是硬要求，见 PRD 15.7。
            stop.heightAnchor.constraint(equalToConstant: 44).isActive = true
            stop.addTarget(self, action: #selector(tapStop(_:)), for: .touchUpInside)
            stop.accessibilityLabel = "\(index) 分"
            stops.append(stop)
            stack.addArrangedSubview(stop)
        }

        addSubview(lowLabel)
        addSubview(highLabel)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),

            lowLabel.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 8),
            lowLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            lowLabel.bottomAnchor.constraint(equalTo: bottomAnchor),

            highLabel.topAnchor.constraint(equalTo: lowLabel.topAnchor),
            highLabel.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        applyScale()
        applySelection()
    }

    private func applyScale() {
        lowLabel.text = scale.low
        highLabel.text = scale.high
    }

    private func applySelection() {
        for stop in stops {
            let selected = stop.tag == value
            stop.backgroundColor = selected ? Palette.accent : Palette.surface.withAlphaComponent(0.85)
            stop.setTitleColor(selected ? Palette.surface : Palette.fadedInk, for: .normal)
            // 不把颜色作为唯一状态差异 —— 选中的同时也变粗、变大。
            stop.titleLabel?.font = selected
                ? (UIFont(name: "Songti SC", size: 17) ?? .systemFont(ofSize: 17, weight: .semibold))
                : (UIFont(name: "Songti SC", size: 15) ?? .systemFont(ofSize: 15))
            stop.layer.borderColor = (selected ? Palette.accent : Palette.fadedInk.withAlphaComponent(0.22)).cgColor
            stop.accessibilityTraits = selected ? [.button, .selected] : [.button]
        }
    }

    @objc private func tapStop(_ sender: UIButton) {
        value = sender.tag
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}
