import AVFoundation
import UIKit

/// 世界那一层：Blender 渲出来的无缝循环，铺满整屏，在所有东西后面走。
///
/// 为什么是视频而不是拼切图：`Blender/journey_scene.py` 和 `world_variants*.py`
/// 建的本来就是**整个世界** —— 3 个 48 米的 tile 首尾相接，世界根节点在 288 帧里
/// 线性平移 48 米，所以第 289 帧和第 1 帧逐像素重合。那套东西给的密度、体积感和
/// 影子，切图拼不出来。
///
/// 能这么用的前提只有一条：**人物不在视频里**（渲染时 `WORLD_TRAVELER=0`）。
/// 人要能停在路口、要能走进选中的那条路、要能换动作 —— 这些是产品的动作，
/// 不是背景的动作，所以它们留在 `RoadSceneView` 那一层，画在这层上面。
final class WorldVideoView: UIView {

    /// 一趟旅程会经过的地方，按顺序。
    ///
    /// 每做完一个选择就往前走一段（`advance()`）。这就是「几个场景接成一条路」：
    /// 每段自己是 288 帧首尾重合的循环，所以**在哪儿切都行**，
    /// 接缝交给交叉淡入，读起来是走进了另一个地方，不是换了个世界。
    ///
    /// 前提是几段共用同一台相机（`Blender/world_variants.py` 的 `SHARED_CAMERA`）——
    /// 否则路的角度和宽度会在接缝上跳一下，那一下骗不过眼睛。
    /// `yellow-fork-forest` **不在这里**：那一段的路是音叉形的，会分成两条。
    /// 人物走的是中线，路一分叉，人就走在两条路中间的草地上了。
    /// 它是留给「做选择」那一下的片段，不是拿来平走的。
    static let journey = ["suburban-forest", "cbd-urban-blocks", "cbd-landmarks"]

    static func pickVariant() -> String { journey.first ?? "suburban-forest" }

    /// 视频里世界前进的速度（米/秒）—— `LOOP_LENGTH / LOOP_SECONDS = 48 / 12`。
    static let worldMetersPerSecond: CGFloat = 4

    private struct Channel {
        let player = AVQueuePlayer()
        let layer = AVPlayerLayer()
        /// 必须持有：它一被释放，循环就断在第一遍结束的地方。
        var looper: AVPlayerLooper?
        var variant: String?
    }

    private var front = Channel()
    private var back = Channel()
    private var desiredRate: Float = 1
    private var observations: [NSKeyValueObservation] = []

    var variant: String? { front.variant }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = Palette.paper
        for channel in [back, front] {          // front 后加 = 在上面
            channel.player.isMuted = true
            channel.player.preventsDisplaySleepDuringVideoPlayback = false
            channel.layer.player = channel.player
            // 视频按屏幕比例渲（720×1568 ≈ 402:874），但机型比例不完全一致。
            // resizeAspectFill：宁可切掉边上一点，也不能留黑边或者把路压变形 ——
            // 路的角度一变，站在上面的人物就对不上了。
            channel.layer.videoGravity = .resizeAspectFill
            layer.addSublayer(channel.layer)
            // 换到下一段（也就是循环绕回去）时 AVQueuePlayer 会把 rate 打回 1.0。
            // 不盯着这件事，人在路口停着、世界忽然自己走起来 —— 一圈一次。
            observations.append(channel.player.observe(\.currentItem) { [weak self] player, _ in
                guard let self, player.rate != self.desiredRate else { return }
                player.rate = self.desiredRate
            })
        }
        back.layer.opacity = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)   // 布局不该被当成一次动画
        front.layer.frame = bounds
        back.layer.frame = bounds
        CATransaction.commit()
    }

    // MARK: 播放

    /// 直接切到某一段（不淡入）。视频不在时返回 false —— 调用方据此退回程序世界。
    @discardableResult
    func play(variant name: String) -> Bool {
        guard front.variant != name else { return true }
        guard let item = Self.item(for: name) else { return false }
        front.looper = AVPlayerLooper(player: front.player, templateItem: item)
        front.variant = name
        front.layer.opacity = 1
        front.player.play()
        return true
    }

    /// 走到下一段。1.8 秒的交叉淡入 —— 慢到读得出「换了个地方」，
    /// 快到不至于让人盯着一片重影发呆。
    func advance(duration: CFTimeInterval = 1.8) {
        guard let current = front.variant,
              let index = Self.journey.firstIndex(of: current) else { return }
        let next = Self.journey[(index + 1) % Self.journey.count]
        guard next != current, let item = Self.item(for: next) else { return }

        back.looper = AVPlayerLooper(player: back.player, templateItem: item)
        back.variant = next
        back.player.rate = desiredRate
        back.layer.opacity = 0

        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1
        fadeIn.duration = duration
        fadeIn.fillMode = .forwards
        fadeIn.isRemovedOnCompletion = false
        back.layer.add(fadeIn, forKey: "fade")
        back.layer.opacity = 1

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in self?.swapChannels() }
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1
        fadeOut.toValue = 0
        fadeOut.duration = duration
        front.layer.add(fadeOut, forKey: "fade")
        front.layer.opacity = 0
        CATransaction.commit()
    }

    /// 淡完之后把旧的那一路彻底停掉：两路视频一直解码是白烧电。
    private func swapChannels() {
        let old = front
        front = back
        back = old
        back.player.pause()
        back.looper?.disableLooping()
        back.looper = nil
        back.variant = nil
        back.layer.opacity = 0
        // 上下顺序跟着换，否则下一次淡入会被压在下面。
        layer.insertSublayer(front.layer, above: back.layer)
    }

    // MARK: 速度

    /// 世界的速度跟着人物走。
    ///
    /// `rate` 是播放倍速：1.0 = 正常走，0 = 停在路口，2.4 = 穿过岔路那一下。
    /// 这也是「走到路口停下来」在视频这一层的实现 —— 世界和人物用同一个数，
    /// 所以不会出现人停了树还在飘。
    func setPace(_ pace: CGFloat, walkingPace: CGFloat) {
        guard front.variant != nil, walkingPace > 0 else { return }
        desiredRate = Float(max(0, pace / walkingPace))
        for channel in [front, back] where channel.variant != nil {
            guard abs(channel.player.rate - desiredRate) > 0.01 else { continue }
            channel.player.rate = desiredRate
        }
    }

    func pause() {
        front.player.pause()
        back.player.pause()
    }

    func resume() {
        guard front.variant != nil else { return }
        front.player.rate = desiredRate
        if back.variant != nil { back.player.rate = desiredRate }
    }

    // MARK: 找文件

    /// `World` 在工程里是**文件夹引用**，所以视频进包时带着目录 ——
    /// 加一段新的只要把文件丢进那个目录，不用改 pbxproj。
    private static func item(for name: String) -> AVPlayerItem? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp4",
                                        subdirectory: "World")
        else { return nil }
        return AVPlayerItem(url: url)
    }
}
