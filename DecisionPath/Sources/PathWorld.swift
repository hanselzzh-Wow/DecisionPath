import SpriteKit
import UIKit

// MARK: - 世界的坐标系
//
// 路不再是一条固定的斜线，而是一条**折线**：能分叉、能拐 90 度。
// 所以需要一个真正的世界坐标系（米），以及它到屏幕的投影。
//
// 两条水平轴的投影方向不是拍脑袋定的，是从渲染资产那台相机
// （`Blender/greybox.py` 的 b-middle：tilt 32° / yaw 30°）算出来的。
// 楼是用那台相机渲的，它们的墙脚就是沿着这两条轴的 ——
// 轴对不上，楼就会歪着站在路边，而这件事一眼看得出来。

enum WorldProjection {

    /// 世界 +X 在屏幕上的方向（单位向量，屏幕 y 向上）。右转走这条。
    static let axisX = CGVector(dx: 0.8660, dy: -0.2650)
    /// 世界 +Y。**这是「前进」**。
    static let axisY = CGVector(dx: 0.5000, dy: 0.4589)

    /// 一世界米等于多少屏幕点。
    ///
    /// 12 是这么来的：真实的路宽 7 米，屏幕上要 84pt 左右才站得下人和路标。
    /// 人物仍然按 70pt 画（`Tuning.travelerHeight`），也就是说人被放大了三倍多 ——
    /// 这是竖屏下必须撒的那个谎，和 `buildingScale` 是同一件事，
    /// 只不过现在谎撒在人身上，不撒在楼身上。
    static var pointsPerMeter: CGFloat = 12

    static func screen(_ world: CGPoint) -> CGPoint {
        CGPoint(x: (world.x * axisX.dx + world.y * axisY.dx) * pointsPerMeter,
                y: (world.x * axisX.dy + world.y * axisY.dy) * pointsPerMeter)
    }
}

/// 路只能朝三个方向：前、右、左。
///
/// 不是偷懒 —— 是因为**只有这三个方向能回到原来的角度**。
/// 用户要的是「岔进去一小段，再反向拐 90 度，回到基础方向」，
/// 那么岔出去的那一下必须正好是 90 度，否则拐回来就对不齐。
enum Heading {
    case forward, right, left

    var vector: CGPoint {
        switch self {
        case .forward: return CGPoint(x: 0, y: 1)
        case .right: return CGPoint(x: 1, y: 0)
        case .left: return CGPoint(x: -1, y: 0)
        }
    }

    /// 岔进去一小段之后，反向拐 90 度 —— **两种岔路都回到 forward**。
    ///
    /// 这里错过一次，值得留着：`.left` 的反向一开始写成了 `.right`。
    /// 但 `.left`/`.right` 是**绝对方向**（−X / +X），不是「往左拐 / 往右拐」，
    /// 所以那样写出来的是原地掉头 180°，人物走出去七米又倒着走回来。
    /// 从 −X 顺时针转 90° 是 +Y，从 +X 逆时针转 90° 也是 +Y —— 就是 forward。
    var turningBack: Heading { .forward }

    /// 人物面朝的方向（屏幕 x 分量为负就翻过来）。
    var facesLeftOnScreen: Bool {
        let v = vector
        return (v.x * WorldProjection.axisX.dx + v.y * WorldProjection.axisY.dx) < 0
    }
}

/// 一条路：世界坐标里的一串顶点。
struct RoadPath {

    private(set) var vertices: [CGPoint]
    private(set) var headings: [Heading] = []
    private(set) var lengths: [CGFloat] = []

    init(start: CGPoint = .zero) { vertices = [start] }

    var end: CGPoint { vertices[vertices.count - 1] }
    var totalLength: CGFloat { lengths.reduce(0, +) }

    mutating func append(_ heading: Heading, meters: CGFloat) {
        let v = heading.vector
        vertices.append(CGPoint(x: end.x + v.x * meters, y: end.y + v.y * meters))
        headings.append(heading)
        lengths.append(meters)
    }

    /// 走到 `distance` 米的时候，人在哪儿、朝哪儿。
    func position(at distance: CGFloat) -> (point: CGPoint, heading: Heading) {
        var remaining = max(0, distance)
        for (index, length) in lengths.enumerated() {
            if remaining <= length || index == lengths.count - 1 {
                let from = vertices[index]
                let v = headings[index].vector
                return (CGPoint(x: from.x + v.x * remaining, y: from.y + v.y * remaining),
                        headings[index])
            }
            remaining -= length
        }
        return (end, headings.last ?? .forward)
    }

    /// 截到某个长度为止 —— 路口出现时，主路就在那儿断掉，变成一个 T。
    mutating func truncate(to distance: CGFloat) {
        var kept: [CGFloat] = []
        var remaining = distance
        for length in lengths {
            if remaining <= 0 { break }
            kept.append(min(length, remaining))
            remaining -= length
        }
        lengths = kept
        headings = Array(headings.prefix(kept.count))
        var points = [vertices[0]]
        for (index, length) in kept.enumerated() {
            let v = headings[index].vector
            let from = points[index]
            points.append(CGPoint(x: from.x + v.x * length, y: from.y + v.y * length))
        }
        vertices = points
    }

    /// 画出来用的屏幕折线。
    func screenPath() -> CGPath {
        let path = CGMutablePath()
        for (index, vertex) in vertices.enumerated() {
            let p = WorldProjection.screen(vertex)
            index == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        return path
    }
}

// MARK: - 路网
//
// 主路 + 若干条**没走的路**。没走的那些不会被删掉：它们留在世界里，
// 跟着一起往后退。这是这个 App 的名字本身 —— 未选择的路没有消失，
// 它只是没被走。

struct RoadNetwork {

    /// 岔口离人物多远的时候出现。太近来不及看，太远走过去太久。
    static let forkLead: CGFloat = 13
    /// 岔进去多长，然后拐回来。用户说的「走一小段」。
    static let branchLength: CGFloat = 7
    /// 拐回来之后的直路。够长，长到下一个路口之前不用再想它。
    static let runLength: CGFloat = 60

    private(set) var main = RoadPath()
    private(set) var ghosts: [RoadPath] = []
    /// 岔口在主路上的位置（米）。nil = 现在没有岔口。
    private(set) var forkDistance: CGFloat?
    private(set) var pendingBranches: [Heading: RoadPath] = [:]

    init() {
        main.append(.forward, meters: Self.runLength)
    }

    /// 前面出现一个岔口。主路在那儿断掉，左右各支出一条。
    mutating func openFork(travelerDistance: CGFloat) {
        guard forkDistance == nil else { return }
        let at = travelerDistance + Self.forkLead
        main.truncate(to: at)
        forkDistance = at

        for heading in [Heading.left, .right] {
            var branch = RoadPath(start: main.end)
            branch.append(heading, meters: Self.branchLength)
            branch.append(heading.turningBack, meters: Self.runLength)
            pendingBranches[heading] = branch
        }
    }

    /// 选了一条。它接到主路上，另一条留在世界里当「没走的那条」。
    mutating func take(_ heading: Heading) {
        guard forkDistance != nil else { return }
        main.append(heading, meters: Self.branchLength)
        main.append(heading.turningBack, meters: Self.runLength)
        if let other = pendingBranches[heading == .left ? .right : .left] {
            ghosts.append(other)
        }
        pendingBranches.removeAll()
        forkDistance = nil
    }

    /// 主路快走完了就再接一段，世界永远有前方。
    mutating func extendIfNeeded(travelerDistance: CGFloat) {
        guard forkDistance == nil,
              main.totalLength - travelerDistance < Self.runLength else { return }
        main.append(.forward, meters: Self.runLength)
    }
}
