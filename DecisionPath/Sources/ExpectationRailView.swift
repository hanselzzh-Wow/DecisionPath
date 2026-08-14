import UIKit

/// 按住路标往上推时，从路标头顶长出来的一条刻度。
///
/// 「留一个预期」原本是选择之后的独立一步。独立一步意味着一次额外的决定
/// （要不要留），而这一步的全部价值在于它便宜 —— 一旦要专门想一下，它就不便宜了。
/// 做成手势之后它和选择是同一个动作：按住、往上推多少、松手。
///
/// 它不接管触摸。手指在哪、推到几分，全由 `RootViewController` 算好了塞进来 ——
/// 手势的起点在路标上，判定必须跟着那一次触摸走，不能在这里重新识别一遍。
final class ExpectationRailView: UIView {

    /// 刻度总共几档、每档多高。上推的距离换算成分数就靠这两个数，
    /// `RootViewController` 也要用，所以放在这里，只有一份。
    static let steps = 10
    static let stepHeight: CGFloat = 22
    /// 推到这个距离之前不算数 —— 手指按下去总会带一点位移，
    /// 不留这段空白的话，轻轻一碰就变成「我预期 1 分」。
    static let deadZone: CGFloat = 28

    var scale: MetricScale = .satisfaction {
        didSet { applyScale() }
    }

    /// nil = 还没推到刻度上。此时松手就是「不留预期」，走原来的路。
    var value: Int? {
        didSet {
            guard value != oldValue else { return }
            applyValue()
        }
    }

    private let highLabel = UILabel()
    private let lowLabel = UILabel()
    private let readoutLabel = UILabel()
    private var ticks: [UIView] = []
    private var numbers: [UILabel] = []

    init() {
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: 出现与消失

    /// 贴着路标的正上方长出来。用 frame 不用约束：它只活在一次触摸里，
    /// 而且要跟着被按住的那个路标走，约束反而更绕。
    func present(above control: UIView, in container: UIView) {
        value = nil
        applyScale()    // 复用同一个实例，别留着上一条记录的词
        let size = intrinsicContentSize
        var centerX = control.center.x
        // 左右两个路标都靠边，刻度直接居中会被切掉一半。
        centerX = min(max(centerX, size.width / 2 + 12), container.bounds.width - size.width / 2 - 12)
        frame = CGRect(x: centerX - size.width / 2,
                       y: control.frame.minY - size.height - 14,
                       width: size.width, height: size.height)
        // 插在路标底下：手指所在的那块永远压在最上面。
        // 不能 addSubview 之后再排序 —— 重新挂一次会打断正在进行的那次触摸。
        container.insertSubview(self, belowSubview: control)

        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: 10)
        UIView.animate(withDuration: 0.18) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    func dismiss() {
        UIView.animate(withDuration: 0.16) {
            self.alpha = 0
            self.transform = CGAffineTransform(translationX: 0, y: 8)
        } completion: { _ in
            self.removeFromSuperview()
            self.transform = .identity
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 132, height: Self.stepHeight * CGFloat(Self.steps) + 62)
    }

    // MARK: 构造

    private func build() {
        isUserInteractionEnabled = false
        backgroundColor = .clear

        for label in [highLabel, lowLabel] {
            label.font = UIFont(name: "Songti SC", size: 12) ?? .systemFont(ofSize: 12)
            label.textColor = Palette.fadedInk.withAlphaComponent(0.85)
            label.textAlignment = .center
            addSubview(label)
        }

        readoutLabel.font = UIFont(name: "Songti SC", size: 15) ?? .systemFont(ofSize: 15, weight: .medium)
        readoutLabel.textColor = Palette.accent
        readoutLabel.textAlignment = .center
        addSubview(readoutLabel)

        for index in 1...Self.steps {
            let tick = UIView()
            tick.backgroundColor = Palette.fadedInk.withAlphaComponent(0.28)
            tick.layer.cornerRadius = 1
            addSubview(tick)
            ticks.append(tick)

            let number = UILabel()
            number.text = "\(index)"
            number.font = UIFont(name: "Songti SC", size: 11) ?? .systemFont(ofSize: 11)
            number.textColor = Palette.fadedInk.withAlphaComponent(0.5)
            number.textAlignment = .left
            addSubview(number)
            numbers.append(number)
        }

        applyScale()
        applyValue()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        highLabel.frame = CGRect(x: 0, y: 0, width: width, height: 18)
        lowLabel.frame = CGRect(x: 0, y: bounds.height - 40, width: width, height: 18)
        readoutLabel.frame = CGRect(x: 0, y: bounds.height - 20, width: width, height: 20)

        // 1 在下、10 在上 —— 手往上推，分数往上走，方向和身体一致。
        for (index, tick) in ticks.enumerated() {
            let y = highLabel.frame.maxY + 6 + Self.stepHeight * CGFloat(Self.steps - 1 - index)
            tick.frame = CGRect(x: width / 2 - 22, y: y, width: tickWidth(for: index + 1), height: 2)
            numbers[index].frame = CGRect(x: width / 2 + 26, y: y - 7, width: 20, height: 16)
        }
    }

    /// 整十的那几档长一点。全等长的话推到第几档只能靠数，数不过来。
    private func tickWidth(for step: Int) -> CGFloat {
        step == value ? 62 : (step % 5 == 0 ? 40 : 28)
    }

    // MARK: 状态

    private func applyScale() {
        highLabel.text = scale.high
        lowLabel.text = scale.low
        applyValue()
    }

    private func applyValue() {
        for (index, tick) in ticks.enumerated() {
            let step = index + 1
            let selected = step == value
            let reached = value.map { step <= $0 } ?? false
            tick.backgroundColor = selected
                ? Palette.accent
                : Palette.fadedInk.withAlphaComponent(reached ? 0.5 : 0.28)
            numbers[index].textColor = selected
                ? Palette.accent
                : Palette.fadedInk.withAlphaComponent(0.5)
        }
        readoutLabel.text = value.map { "\($0) · \(scale.word(for: $0))" } ?? "往上推，留个预期"
        readoutLabel.textColor = value == nil ? Palette.fadedInk.withAlphaComponent(0.8) : Palette.accent
        setNeedsLayout()
    }
}

extension MetricScale {
    /// 数据里存 1–10，给用户看的永远是这三个词。
    func word(for value: Int) -> String {
        switch value {
        case ...3: return low
        case 8...: return high
        default: return mid
        }
    }
}
