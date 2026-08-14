import SpriteKit
import UIKit

/// 折线世界。
///
/// 和上一版（`JourneyScene`）的根本区别：那一版的路是**一条固定的斜线**，
/// 世界沿着它滚；这一版的路是一条**可以改形状的折线**，
/// 相机跟着人走。因为岔路必须在用户开口的那一刻长出来 ——
/// 它是一个交互状态，不是地图上的一个地点。
///
/// 预渲的循环视频做不到这件事：一段胶片只能朝一个方向滚，路的形状是烘死的。
/// 这也是这一版把世界画回程序里的原因。
final class PathWorldScene: SKScene {

    // MARK: 尺度
    //
    // 这些数都以**米**为单位，只有一处例外：人物按 pt 给。
    // 人是被放大的那个谎（见 `WorldProjection.pointsPerMeter` 的注释）。

    private enum M {
        static let roadWidth: CGFloat = 6.2
        static let shoulder: CGFloat = 1.6        // 路肩，楼要退到它外面
        static let propGap: ClosedRange<CGFloat> = 6...13
        static let propSetback: ClosedRange<CGFloat> = 2.5...9
        /// 人物钉在屏幕的哪儿（0–1）。往左下放一点，身后才留得下走过的路。
        static let anchor = CGPoint(x: 0.40, y: 0.34)
        static let walkMetersPerSecond: CGFloat = 2.4
        static let crossMetersPerSecond: CGFloat = 5.4
    }

    private enum Z {
        static let ground: CGFloat = 0
        static let ghostRoad: CGFloat = 10
        static let road: CGFloat = 20
        static let lane: CGFloat = 30
        static let prop: CGFloat = 100      // 再按世界位置细分
        static let pending: CGFloat = 900
        static let traveler: CGFloat = 1000
        static let signpost: CGFloat = 1100
    }

    // MARK: 状态

    private var network = RoadNetwork()
    private var distance: CGFloat = 0          // 人物走了多少米
    /// 米/秒。`SKNode` 自己有个 `speed`（动作倍率），所以这里叫 pace。
    private var pace: CGFloat = M.walkMetersPerSecond
    private var lastUpdate: TimeInterval = 0

    private let worldNode = SKNode()
    private var roadNode: SKShapeNode?
    private var laneNode: SKShapeNode?
    private var ghostNodes: [SKShapeNode] = []
    private var signposts: [Heading: SKNode] = [:]
    private var traveler: FigureNode?
    private var travelerRoot = SKNode()
    private var pendingLamps: [SKNode] = []
    private var pendingCount = 0

    /// 已经生成到多少米，以及生成出来的东西（世界坐标 → 节点）。
    private var propsSpawnedTo: CGFloat = 0
    private var props: [(node: SKNode, world: CGPoint)] = []

    /// 选择完成之后通知外面（`RoadSceneView` 用它换场景包等）。
    var onCrossed: (() -> Void)?

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = Palette.canvasTop
        scaleMode = .resizeFill
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMove(to view: SKView) {
        addChild(worldNode)
        addChild(travelerRoot)
        rebuild()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard view != nil, oldSize != size else { return }
        rebuild()
    }

    // MARK: 外面看得见的五个动作（语义和 RoadSceneView 的公开方法一一对应）

    func presentFork() {
        guard network.forkDistance == nil else { return }
        network.openFork(travelerDistance: distance)
        redrawRoads()
        addSignposts()
    }

    func crossFork(left: Bool) {
        guard network.forkDistance != nil else { return }
        let heading: Heading = left ? .left : .right
        // 选中的那块牌子亮一下，另一块留在原地暗下去 ——
        // 它不会被删掉，等会儿会从人物身后退出画面。
        signposts[heading]?.run(.sequence([.scale(to: 1.16, duration: 0.14),
                                           .scale(to: 1, duration: 0.2)]))
        if let board = signposts[heading]?.childNode(withName: "board") as? SKShapeNode {
            board.fillColor = Palette.accent
        }
        signposts[heading == .left ? .right : .left]?.run(.fadeAlpha(to: 0.45, duration: 0.4))

        network.take(heading)
        redrawRoads()
        pace = M.crossMetersPerSecond
        run(.sequence([.wait(forDuration: 1.6), .run { [weak self] in
            self?.pace = M.walkMetersPerSecond
            self?.clearSignposts()
            self?.onCrossed?()
        }]))
    }

    func resetFork() {
        clearSignposts()
        pace = M.walkMetersPerSecond
    }

    func setPendingCount(_ count: Int) {
        guard count != pendingCount else { return }
        pendingCount = count
        rebuildPendingLamps()
    }

    func playTravelerMotion(_ clip: MotionClip) { traveler?.play(clip) }

    // MARK: 每帧

    override func update(_ currentTime: TimeInterval) {
        guard lastUpdate > 0 else { lastUpdate = currentTime; return }
        let delta = min(CGFloat(currentTime - lastUpdate), 1 / 20)
        lastUpdate = currentTime

        // 走到岔口就停下。停的是**世界**，不是只有人 ——
        // 相机跟着人走，人不动，世界自然也不动。
        if let fork = network.forkDistance {
            let remaining = fork - distance
            pace = remaining < 0.2 ? 0 : min(pace, max(0, remaining * 1.1))
        }

        distance += pace * delta
        network.extendIfNeeded(travelerDistance: distance)
        spawnPropsAhead()
        recycleProps()
        layoutWorld()

        let phase = distance * WorldProjection.pointsPerMeter / max(Tuning.strideLength, 1) * .pi * 2
        traveler?.apply(phase: phase,
                        intensity: UIAccessibility.isReduceMotionEnabled
                            ? Tuning.reduceMotionSwingScale : 1)
    }

    /// 相机：把人物钉在屏幕上的固定点，世界整体反向平移。
    /// 路一拐弯，世界的滚动方向就跟着变 —— 这一句就是「能拐 90 度」的全部实现。
    private func layoutWorld() {
        let here = network.main.position(at: distance)
        let anchor = CGPoint(x: size.width * M.anchor.x, y: size.height * M.anchor.y)
        let offset = WorldProjection.screen(here.point)
        worldNode.position = CGPoint(x: anchor.x - offset.x, y: anchor.y - offset.y)
        travelerRoot.position = anchor
        traveler?.xScale = here.heading.facesLeftOnScreen ? -1 : 1
    }

    // MARK: 搭建

    private func rebuild() {
        guard size.width > 0, size.height > 0 else { return }
        worldNode.removeAllChildren()
        travelerRoot.removeAllChildren()
        props.removeAll()
        ghostNodes.removeAll()
        signposts.removeAll()
        pendingLamps.removeAll()
        propsSpawnedTo = 0
        roadNode = nil
        laneNode = nil

        redrawRoads()
        spawnPropsAhead()

        let figure = FigureNode(figure: .walker, height: Tuning.travelerHeight, clip: .walking)
        figure.zPosition = Z.traveler
        travelerRoot.addChild(contactShadow(width: Tuning.travelerHeight * 0.34))
        travelerRoot.addChild(figure)
        traveler = figure
        rebuildPendingLamps()
        layoutWorld()
    }

    // MARK: 路

    private func redrawRoads() {
        roadNode?.removeFromParent()
        laneNode?.removeFromParent()
        ghostNodes.forEach { $0.removeFromParent() }
        ghostNodes.removeAll()

        // 走过的和要走的都是同一条 `main`，所以「身后的路」是免费的：
        // 它就在那儿，只是退到人物后面去了。
        let road = SKShapeNode(path: network.main.screenPath())
        style(road, width: M.roadWidth, color: Palette.road, z: Z.road)
        worldNode.addChild(road)
        roadNode = road

        let lane = SKShapeNode(path: dashed(network.main.screenPath()))
        style(lane, width: 0.18, color: tint(0.86), z: Z.lane)
        worldNode.addChild(lane)
        laneNode = lane

        // 还没选的两条 + 已经错过的那些，用同一种更淡的墨色。
        // 「未选择」不是灰掉的按钮，是一条真的路，只是没人走。
        for branch in network.pendingBranches.values {
            let node = SKShapeNode(path: branch.screenPath())
            style(node, width: M.roadWidth, color: blend(Palette.road, toward: Palette.canvasTop, 0.42), z: Z.ghostRoad)
            worldNode.addChild(node)
            ghostNodes.append(node)
        }
        for ghost in network.ghosts {
            let node = SKShapeNode(path: ghost.screenPath())
            style(node, width: M.roadWidth, color: blend(Palette.road, toward: Palette.canvasTop, 0.62), z: Z.ghostRoad)
            worldNode.addChild(node)
            ghostNodes.append(node)
        }
    }

    private func style(_ node: SKShapeNode, width meters: CGFloat, color: UIColor, z: CGFloat) {
        node.lineWidth = meters * WorldProjection.pointsPerMeter
        node.strokeColor = color
        node.fillColor = .clear
        // 圆角接头：90 度的拐角在正投影里是个尖角，圆一下才像铺出来的路。
        node.lineJoin = .round
        node.lineCap = .round
        node.zPosition = z
        node.isAntialiased = true
    }

    private func dashed(_ path: CGPath) -> CGPath {
        let dash = 1.6 * WorldProjection.pointsPerMeter
        return path.copy(dashingWithPhase: 0, lengths: [dash, dash * 1.4])
    }

    // MARK: 路标
    //
    // 两块牌子立在岔口上，各自站在自己那条岔路的入口。
    // 它们是世界里的东西，不是浮在世界前面的 UI —— 会跟着一起退，会被楼挡住。

    private func addSignposts() {
        clearSignposts()
        guard network.forkDistance != nil else { return }
        for (heading, branch) in network.pendingBranches {
            let post = makeSignpost()
            // 立在岔路口往里一点点的地方，这样两块牌子分得开。
            let spot = branch.position(at: RoadNetwork.branchLength * 0.42)
            post.position = WorldProjection.screen(spot.point)
            post.zPosition = Z.signpost
            post.alpha = 0
            post.setScale(0.7)
            worldNode.addChild(post)
            post.run(.group([.fadeIn(withDuration: 0.35), .scale(to: 1, duration: 0.45)]))
            signposts[heading] = post
        }
    }

    private func clearSignposts() {
        signposts.values.forEach { $0.removeFromParent() }
        signposts.removeAll()
    }

    private func makeSignpost() -> SKNode {
        let container = SKNode()
        let height = 2.6 * WorldProjection.pointsPerMeter
        container.addChild(contactShadow(width: height * 0.3))

        let post = SKShapeNode(rectOf: CGSize(width: height * 0.07, height: height))
        post.fillColor = tint(0.28)
        post.strokeColor = .clear
        post.position = CGPoint(x: 0, y: height / 2)
        container.addChild(post)

        let board = SKShapeNode(rectOf: CGSize(width: height * 0.86, height: height * 0.34),
                                cornerRadius: height * 0.04)
        board.name = "board"
        board.fillColor = tint(0.16)
        board.strokeColor = .clear
        board.position = CGPoint(x: 0, y: height * 0.92)
        container.addChild(board)
        return container
    }

    // MARK: 待回访的灯
    //
    // 摆在**人物身后走过的那段路**上。数量是真的：三个待回访就是三盏灯。

    private func rebuildPendingLamps() {
        pendingLamps.forEach { $0.removeFromParent() }
        pendingLamps.removeAll()
        guard pendingCount > 0 else { return }
        for index in 0..<pendingCount {
            let lamp = makeLamp()
            lamp.zPosition = Z.pending
            worldNode.addChild(lamp)
            pendingLamps.append(lamp)
        }
        positionPendingLamps()
    }

    private func positionPendingLamps() {
        for (index, lamp) in pendingLamps.enumerated() {
            let behind = max(0, distance - CGFloat(index + 1) * 5.5)
            let spot = network.main.position(at: behind)
            let side = perpendicular(of: spot.heading)
            let offset = CGPoint(x: spot.point.x + side.x * (M.roadWidth / 2 + 1.0),
                                 y: spot.point.y + side.y * (M.roadWidth / 2 + 1.0))
            lamp.position = WorldProjection.screen(offset)
        }
    }

    private func makeLamp() -> SKNode {
        let container = SKNode()
        let height = 2.2 * WorldProjection.pointsPerMeter
        let post = SKShapeNode(rectOf: CGSize(width: height * 0.06, height: height))
        post.fillColor = tint(0.3)
        post.strokeColor = .clear
        post.position = CGPoint(x: 0, y: height / 2)
        container.addChild(post)

        let glow = SKShapeNode(circleOfRadius: height * 0.13)
        glow.fillColor = Palette.accent
        glow.strokeColor = .clear
        glow.position = CGPoint(x: 0, y: height)
        container.addChild(glow)

        if !UIAccessibility.isReduceMotionEnabled {
            glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.55, duration: 1.9),
                                               .fadeAlpha(to: 1, duration: 1.9)])))
        }
        return container
    }

    // MARK: 沿路的景物

    private func spawnPropsAhead() {
        let horizon = distance + 70
        while propsSpawnedTo < horizon {
            propsSpawnedTo += CGFloat.random(in: M.propGap)
            guard propsSpawnedTo <= network.main.totalLength else { break }
            let spot = network.main.position(at: propsSpawnedTo)
            let side = perpendicular(of: spot.heading)

            // 远侧（画面上方）放楼，近侧只放树。
            //
            // 近侧的东西在人物**前面**掠过：一栋 20 米的楼摆在那儿，
            // 会连人带路一起盖住 —— 第一版就是这么糊掉的。
            place(building: true, at: spot.point, side: side, sign: -1)
            if Bool.random() { place(building: false, at: spot.point, side: side, sign: 1) }
        }
    }

    private func place(building: Bool, at point: CGPoint, side: CGPoint, sign: CGFloat) {
        guard let prop = makeProp(building: building) else { return }
        // 退线要算上它自己的占地宽度，否则墙角会压在路面上。
        let setback = M.roadWidth / 2 + M.shoulder + prop.halfWidth
            + CGFloat.random(in: building ? 0.5...4 : 0...1.5)
        let world = CGPoint(x: point.x + side.x * setback * sign,
                            y: point.y + side.y * setback * sign)
        prop.node.position = WorldProjection.screen(world)
        // 离路越远画得越靠后，近的压住远的。
        prop.node.zPosition = Z.prop + (sign > 0 ? setback : -setback)
        worldNode.addChild(prop.node)
        props.append((prop.node, world))
    }

    /// 退到人物身后足够远就删掉。留着不删，走十分钟之后场上会有几千个节点。
    private func recycleProps() {
        let here = network.main.position(at: distance).point
        props.removeAll { prop in
            let dx = prop.world.x - here.x, dy = prop.world.y - here.y
            guard dx * dx + dy * dy > 110 * 110 else { return false }
            prop.node.removeFromParent()
            return true
        }
    }

    /// 一个沿路景物，外加它的占地半宽（米）—— 摆放要靠它算退线。
    private func makeProp(building: Bool) -> (node: SKNode, halfWidth: CGFloat)? {
        let ids = building
            ? SceneArt.ids(pack: "oldtown", heightMeters: 3...18)
            : SceneArt.ids(pack: "common", heightMeters: 2...8)
        guard let name = ids.randomElement(), let entry = SceneArt.entry(name),
              UIImage(named: name) != nil else { return nil }
        let world = entry.worldSize
        guard world.height > 0 else { return nil }

        let scale = WorldProjection.pointsPerMeter
        let sprite = SKSpriteNode(texture: SKTexture(imageNamed: name))
        sprite.size = CGSize(width: world.width * scale, height: world.height * scale)
        sprite.anchorPoint = CGPoint(x: entry.anchor.first ?? 0.5,
                                     y: entry.anchor.count > 1 ? entry.anchor[1] : 0)
        sprite.color = Palette.paper
        sprite.colorBlendFactor = building ? 0.18 : 0.06

        let container = SKNode()
        container.addChild(contactShadow(width: sprite.size.width * (entry.shadowWidthFactor ?? 1)))
        container.addChild(sprite)
        // 图的宽度是**投影后**的宽度，除回去才是世界里的占地。
        // 除以 axisX 的长度（0.906）是因为占地宽主要沿着那条轴。
        return (container, world.width / 2 * 0.906)
    }

    // MARK: 小工具

    /// 某个朝向的「右手边」在世界里的方向。
    private func perpendicular(of heading: Heading) -> CGPoint {
        let v = heading.vector
        return CGPoint(x: v.y, y: -v.x)
    }

    private func contactShadow(width: CGFloat) -> SKNode {
        let node = SKShapeNode(ellipseOf: CGSize(width: width, height: width * 0.26))
        node.fillColor = Palette.ink.withAlphaComponent(0.16)
        node.strokeColor = .clear
        node.zPosition = -1
        return node
    }

    /// 两个颜色之间插值。`amount` = 往 `toward` 走多少。
    private func blend(_ color: UIColor, toward: UIColor, _ amount: CGFloat) -> UIColor {
        let a = color.cgColor.components ?? [0, 0, 0, 1]
        let b = toward.cgColor.components ?? [1, 1, 1, 1]
        return UIColor(red: a[0] + (b[0] - a[0]) * amount,
                       green: a[1] + (b[1] - a[1]) * amount,
                       blue: a[2] + (b[2] - a[2]) * amount, alpha: 1)
    }

    /// 0 = 全墨，1 = 纸白。和切图那版同一套规则。
    private func tint(_ amount: CGFloat) -> UIColor {
        let ink = Palette.ink.cgColor.components ?? [0, 0, 0, 1]
        let paper = Palette.canvasTop.cgColor.components ?? [1, 1, 1, 1]
        return UIColor(red: ink[0] + (paper[0] - ink[0]) * amount,
                       green: ink[1] + (paper[1] - ink[1]) * amount,
                       blue: ink[2] + (paper[2] - ink[2]) * amount,
                       alpha: 1)
    }
}
