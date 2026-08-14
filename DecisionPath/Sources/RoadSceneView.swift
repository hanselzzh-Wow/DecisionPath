import SpriteKit
import UIKit

// MARK: - 场景调参
//
// 灰模阶段这里的数字先把节奏、速度、密度和比例调对，然后照着它渲资产。
// 现在资产回来了：街上的建筑、树、路灯、路牌、天际线全是 Blender 渲的贴图，
// 程序形状退到远山和最前景那两层 —— 那两层是纯剪影，画谁都一样。
//
// **贴图和形状共用同一套规则**（速度、墨色、接地影、水平翻转），
// 所以混着用不会散架。唯一的区别是尺寸：形状按 heightRange（人物身高的倍数）
// 给，贴图按 manifest 里的真实米数换算。

enum Tuning {

    // MARK: 路

    /// 路从左边缘进入的高度（0 = 屏幕底边，1 = 顶边）。
    static var roadEntryHeightRatio: CGFloat = 0.32
    /// 路从右边缘离开的高度。
    ///
    /// 倾角是由这两个数推出来的，不直接给 —— 这样"两端都落在左右侧边、不碰上下边"
    /// 是几何上的保证，换机型也不会破。直接给角度做不到这一点：同一个角度在
    /// 不同宽高比上会从不同的边出画。
    ///
    /// 这两个数不能随便给了：资产是用 tilt 32° / yaw 30° 的相机渲的，
    /// 那台相机下一条世界直线在屏幕上是 17°（= atan(tan(yaw)·sin(tilt))）。
    /// 路的倾角必须等于它，否则楼会歪着站在路边。
    static var roadExitHeightRatio: CGFloat = 0.46

    /// 路在进入点之前、离开点之后各延伸多少（pt）。景物要在画面外就位。
    static var roadBackExtension: CGFloat = 300
    static var roadForwardExtension: CGFloat = 300

    /// 路面宽度（pt，垂直于路的方向）。
    static var roadWidth: CGFloat = 74
    /// 车道标记的长/宽/间距。
    static var laneDashLength: CGFloat = 30
    static var laneDashWidth: CGFloat = 6
    static var laneDashGap: CGFloat = 74

    // MARK: 人物
    //
    // 人物的形象不在这里改 —— 见下面的 `Figure.walker`（骨架与外观）
    // 和 `MotionClip`（动作）。这里只有尺度和步态的整体强度。

    /// 人物总高（pt）。这个数决定整个世界的尺度感，先调它。
    static var travelerHeight: CGFloat = 70

    /// 人物的真实身高（米）。Blender 那边按同一个数建模，两边尺度才对得上。
    /// 改这个或 travelerHeight，等于整个世界换比例尺。
    static var figureHeightMeters: CGFloat = 1.7
    /// 一米等于多少 pt。渲出来的贴图按真实高度换算上屏尺寸，靠这个数。
    static var pointsPerMeter: CGFloat { travelerHeight / figureHeightMeters }

    /// 建筑相对真实尺度的压缩比。
    ///
    /// 这是一个**刻意的谎**，而且必须是谎：1 米 = 41pt，一栋 20 米的楼就是
    /// 824pt，而屏幕只有 874pt 高。按真实比例，一条真实的街会把整个屏幕吃掉 ——
    /// 没有天空、没有地平线、远景层全被挡住。
    ///
    /// 压缩的只是「建筑 : 人」这一个比值。建筑**互相之间**的比例仍然是建模时
    /// 定死的真实值，所以一座城看上去仍然自洽 —— 只是整体像个模型。
    /// 这和角色比门高的处理是同一类，不是错误，是竖屏的物理约束。
    ///
    /// 0.42 → 0.30：一排楼变成两排 + 一条天际线之后，原来的尺寸会把后面两层
    /// 整个盖住。现在 1 米 = 12.3pt，临街的 8–20 米老楼落在 100–250pt，
    /// 而路到地平线之间只有约 330pt —— 两排房子加一条天际线，正好排得下。
    static var buildingScale: CGFloat = 0.30
    /// 人物在**可见路段**上的位置（0 = 左边缘进入点，1 = 右边缘离开点）。
    /// 用可见路段而不是全长，这样换屏幕尺寸时人物的构图位置不会漂。
    /// 往右挪了一些：待回访的标记都在人物**身后**，站得太靠左的话
    /// 身后就全在屏幕外，那个"还亮着的路口"等于不存在。
    static var travelerProgress: CGFloat = 0.38
    /// 单步步幅（pt）。步频 = 世界速度 / 步幅，所以这个数决定脚滑不滑。
    static var strideLength: CGFloat = 30
    /// 走路时腿/手的摆动幅度（弧度），以及身体的上下起伏（身高倍数）。
    static var legSwing: CGFloat = 0.42
    static var armSwing: CGFloat = 0.26
    static var bobHeightRatio: CGFloat = 0.036

    // MARK: 速度

    static var paceWalking: CGFloat = 30
    static var paceDeciding: CGFloat = 13
    static var paceCrossing: CGFloat = 72

    // MARK: 形状与材质
    //
    // 这一组决定"看起来像不像出自同一只手"。它比任何单个形状的质量都重要 ——
    // 一堆各自漂亮但规则不一致的形状，永远拼不出一个世界。

    /// 圆角 = min(宽, 高) × 这个比例。全场共用一套，不要逐个形状拍脑袋。
    static var cornerRadiusRatio: CGFloat = 0.32
    /// 直边的弯曲幅度（相对于形状尺寸）。让线不那么 CAD —— 手画的线没有真正的直线。
    static var handWobble: CGFloat = 0.022
    /// 有机形状（树冠、灌木）的半径抖动。0 = 正圆。
    static var blobWobble: CGFloat = 0.055

    /// 接触影：把物体钉在地上。没有它，所有东西都像浮在纸上的贴纸。
    static var contactShadowOpacity: CGFloat = 0.5
    /// 影子的扁平度（高 = 宽 × 这个）。
    static var contactShadowFlatness: CGFloat = 0.2

    /// 纸纹强度（0 = 关）。把纯色块变成"印在纸上的东西"。
    static var paperGrainStrength: CGFloat = 0.75

    // MARK: 降低动态
    //
    // 不做全局慢放 —— 慢放仍然是持续运动，对前庭敏感的人没有帮助。
    // 做法是把各层速度向 1.0 收拢（视差趋同）并压缩步态幅度。

    /// 0 = 不收拢，1 = 完全收拢成单层。
    static var reduceMotionParallaxPull: CGFloat = 0.75
    static var reduceMotionSwingScale: CGFloat = 0.35

    // MARK: 决策路口

    /// 路标出现在可见路段的什么位置。要落在人物前方、且仍在画面内。
    static var gateProgress: CGFloat = 0.74
    static var gateSideOffset: CGFloat = 46
    static var gateHeight: CGFloat = 62
    /// 停在路口**前面**多远。停到 0 的话路标正好扣在人物身上，
    /// 而路标的 z 比人物低，会被人挡掉一半。
    static var gateStandoff: CGFloat = 84

    // MARK: 远景带（横向滚动，不沿路）
    //
    // 这两层是"深度"的主要来源。原型里缺的就是它们 —— 之前 8 个元素速度全挤在
    // 0.61–0.98，全是中景，所以怎么调都不像有纵深。

    static let bands: [BandSpec] = [
        // 三条带共用一条地平线（baseline 几乎相同）。分开会出现几条水平硬边，
        // 读起来像几张贴纸叠着，而不是一片远景。
        BandSpec(name: "远山",
                 speed: 0.10, z: 50, tint: 0.88,
                 baselineRatio: 0.782,
                 heightRange: 40...88, widthRange: 190...420,
                 gapRange: -110...30,
                 shape: .hill),
        // 天际线：地标终于有地方站了。
        //
        // 它们 100–123 米，按街上的尺度是 1400pt —— 三个屏幕高。所以这一层
        // 自己带一个 artScale：**远处的东西画小一点**，这是画背景的通行做法，
        // 也和这个世界已经认下的那个谎（buildingScale）是同一类。
        // 换来的是地平线不再是一条空线，而是一座远远的城。
        BandSpec(name: "天际线",
                 speed: 0.18, z: 70, tint: 0.66,
                 baselineRatio: 0.776,
                 heightRange: 0...0, widthRange: 0...0,
                 gapRange: -46...40,
                 shape: .roundedBox,
                 kinds: [.pack("cbd")],
                 // 0.13：地标 100–123 米落在 170–210pt，从地平线往上刚好到屏幕顶
                 // 那圈雾里。再大一点就捅出画面，再小一点就读不出是塔。
                 artScale: 0.13,
                 artHeightMeters: 20...130),
        // 用有机团块而不是圆角矩形：圆角矩形排成一条会读成 UI 横杠，不是树线。
        BandSpec(name: "远树丛",
                 speed: 0.30, z: 100, tint: 0.74,
                 baselineRatio: 0.773,
                 heightRange: 26...54, widthRange: 44...96,
                 gapRange: -50...8,
                 shape: .bush)
    ]

    // MARK: 沿路层
    //
    // side > 0 = 路的远侧（画面上方），side < 0 = 近侧（画面下方，在人物前面掠过）。
    //
    // heightRange 的单位是「人物身高的倍数」，不是 pt —— 人是这个世界的尺度单位，
    // 改 travelerHeight 时整个世界跟着等比缩放，比例关系不会散掉。

    /// 一条街只属于一个地方。高楼大厦和城中村不是同一条街上的不同楼 ——
    /// 所以场景包在 `rebuild()` 时挑一次，之后整条街（包括循环回来的那些）都用它。
    ///
    /// **cbd 不在里面，它只出现在天际线上。** 那些塔 22–81 米，站在路边就是
    /// 270–1000pt，一栋楼吃掉整个屏幕。竖屏里没有「站在写字楼脚下」这个镜头 ——
    /// 但「从老城的街上望过去，远处是一片塔」是有的，而且更像这个产品在说的事。
    static let streetPacks = ["oldtown", "oldtown", "oldtown", "suburb"]

    /// 一次挑几个资产来铺整条街。
    ///
    /// 不是全都用上：20 张贴图同时在内存里是几十兆，而且一条真实的街本来就
    /// 反复出现同样几栋楼。挑一小把、反复用，既省内存又更像一个地方。
    static let streetPaletteSize = 7

    static let roadLayers: [RoadLayerSpec] = [
        // 第二排：只要矮的（≤12 米），从临街那排的屋顶缝里露出来。
        //
        // 这里放高楼是错的，试过：正投影里没有近大远小，「远」只是往上挪 ——
        // 一栋 20 米的楼站在这儿，顶会顶到屏幕外，同时把天际线整个挡住。
        // 远处该是**更矮的东西**，露出的那点屋顶就是纵深。
        RoadLayerSpec(name: "远侧屋顶",
                      speed: 0.62, z: 280, tint: 0.52,
                      sideRange: 246...318, heightRange: 0.55...1.05,
                      gapRange: 64...142,
                      kinds: [.street, .street, .art("tree-c")],
                      artScale: 0.86,
                      artHeightMeters: 3...12),
        // 临街那一排。这是「城」的主体，也是唯一一层建筑按正常尺度出现的地方。
        RoadLayerSpec(name: "远侧临街",
                      speed: 0.72, z: 300, tint: 0.28,
                      sideRange: 132...212, heightRange: 0.55...1.05,
                      gapRange: 104...206,
                      kinds: [.street, .street, .street, .street, .art("tree-a")],
                      // 30 米的塔楼在这一排会独自占掉半个屏幕。它不是不能出现，
                      // 但得站在第二排之外 —— 现在先不让它进来。
                      artHeightMeters: 3...24),
        // 人行道：树、路灯、路牌。这一层的作用是把楼和路缝起来，
        // 没有它，楼看上去是浮在路后面的一排画片。
        RoadLayerSpec(name: "远侧路边",
                      speed: 0.88, z: 320, tint: 0.14,
                      sideRange: 54...104, heightRange: 0.35...0.75,
                      gapRange: 74...156,
                      // lamp 和 signpost 都不在里面。不是懒得放，是这个尺度下它们
                      // 读不出来：signpost（2.2 米）只剩一块横板，像一片浮在地上的
                      // 灰纸；lamp（4.4 米）细成一根针，而且它和「待回访」那盏灯
                      // 长得太像 —— 全世界只有待回访的灯该是一根杆顶着一个头。
                      // 要用得先重渲：杆加粗、灯头换个形。
                      kinds: [.art("tree-a"), .art("tree-b"), .shape(.rock)]),
        // 近侧：在人物前面掠过的东西。这里**不放建筑** ——
        // 一栋楼在这个距离上会盖掉人物、路和底部那两个路标。
        RoadLayerSpec(name: "近侧",
                      speed: 1.00, z: 600, tint: 0.04,
                      sideRange: -176 ... -86, heightRange: 0.5...1.0,
                      gapRange: 196...392,
                      kinds: [.art("tree-b"), .art("tree-a"), .art("tree-c"),
                              .shape(.rock), .shape(.bush)]),
        // 最前景：故意留给程序形状。它掠得最快、只读到一个剪影，
        // 用贴图是纯浪费 —— 而且这一层的手绘抖动正好补回一点纸感。
        RoadLayerSpec(name: "前景掠过",
                      speed: 1.32, z: 800, tint: 0.0,
                      sideRange: -300 ... -190, heightRange: 1.3...2.2,
                      gapRange: 520...1050,
                      kinds: [.shape(.bush), .shape(.tree)])
    ]
}

// MARK: - 层描述

struct BandSpec {
    let name: String
    let speed: CGFloat
    let z: CGFloat
    /// 0 = 全墨（近），1 = 纸白（远）。远近靠墨色浓淡，不靠新颜色。
    let tint: CGFloat
    /// 基线在屏幕高度的百分之多少处。
    let baselineRatio: CGFloat
    let heightRange: ClosedRange<CGFloat>
    let widthRange: ClosedRange<CGFloat>
    /// 允许为负 —— 负间距表示元素重叠成连绵的一片。
    let gapRange: ClosedRange<CGFloat>
    let shape: BlockShape
    /// 给了就走贴图，`shape` 只在贴图缺失时兜底。
    var kinds: [PropKind]?
    var artScale: CGFloat = 1
    var artHeightMeters: ClosedRange<CGFloat>?
}

struct RoadLayerSpec {
    let name: String
    let speed: CGFloat
    let z: CGFloat
    let tint: CGFloat
    let sideRange: ClosedRange<CGFloat>
    /// 单位是人物身高的倍数。只对程序形状生效 —— 贴图按 manifest 里的真实高度走。
    let heightRange: ClosedRange<CGFloat>
    let gapRange: ClosedRange<CGFloat>
    let kinds: [PropKind]
    /// 叠在 `buildingScale` 上的一层。**只有远景层该用它** ——
    /// 同一条街上两栋楼如果按不同的比例画，比例关系就散了。
    /// 现在只有第二排（0.82）和天际线（0.2）用。
    var artScale: CGFloat = 1
    /// 这一层只收真实高度落在这个区间的资产（米）。
    /// 第二排要高的（矮房子会被前排整个挡住），天际线要塔和地标。
    var artHeightMeters: ClosedRange<CGFloat>?
}

/// 一个景物槽位可以是程序画的形状，也可以是 Blender 渲出来的贴图。
/// 两者混用没有问题 —— 它们共用同一套规则（速度、墨色、接地影、翻转）。
enum PropKind {
    case shape(BlockShape)
    /// Asset Catalog 里的名字，尺寸和接地点从 SceneArt.json 读。
    case art(String)
    /// 从 manifest 里按场景包随机取一个。
    case pack(String)
    /// **这条街所在的那个地方**。具体是哪个包由 `rebuild()` 挑一次，
    /// 整条街共用 —— 写死成 `.pack("oldtown")` 的话，换地方就得改四处。
    case street
}

// MARK: - Blender 渲染资产清单
//
// Blender/greybox.py 渲图时会一并写出 SceneArt.json。把它和 PNG 一起丢进
// Xcode，景物就能从程序形状换成贴图，而摆放、视差、墨色浓淡的规则全不用改。

struct SceneArtEntry: Decodable {
    let id: String
    let pack: String
    let kind: String
    /// 图像的像素尺寸，以及这张图自己的像素/米。
    ///
    /// 真实尺寸由这两个数反推，而不是用 worldHeight —— 岔路那种扁平资产的
    /// 「高度」只有 0.06 米，按高度算会缩成 2pt。这个算法对所有资产都成立。
    let pixelSize: [CGFloat]
    let pixelsPerMeter: CGFloat
    /// 接地点在图里的归一化位置，和 SKSpriteNode.anchorPoint 同一套坐标。
    let anchor: [CGFloat]
    let shadowWidthFactor: CGFloat?

    var worldSize: CGSize {
        guard pixelSize.count > 1, pixelsPerMeter > 0 else { return .zero }
        return CGSize(width: pixelSize[0] / pixelsPerMeter,
                      height: pixelSize[1] / pixelsPerMeter)
    }
}

enum SceneArt {
    private struct Payload: Decodable { let assets: [SceneArtEntry] }

    private static let payload: Payload? = {
        // 走 Asset Catalog 的 data set，这样加资产不用改 pbxproj。
        guard let data = NSDataAsset(name: "SceneArt")?.data else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }()

    private static let entries: [String: SceneArtEntry] = {
        guard let assets = payload?.assets else { return [:] }
        return Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
    }()

    private static let byPack: [String: [String]] = {
        guard let assets = payload?.assets else { return [:] }
        return Dictionary(grouping: assets, by: { $0.pack }).mapValues { $0.map(\.id) }
    }()

    static func entry(_ id: String) -> SceneArtEntry? { entries[id] }
    static func ids(pack: String) -> [String] { byPack[pack] ?? [] }
    static var isLoaded: Bool { !entries.isEmpty }

    /// 按真实高度筛。层要的是「高的那批」还是「矮的那批」，
    /// 这件事只有 manifest 知道 —— 按 id 手写名单迟早和资产对不上。
    static func ids(pack: String, heightMeters: ClosedRange<CGFloat>?) -> [String] {
        let all = ids(pack: pack)
        guard let range = heightMeters else { return all }
        let hit = all.filter { entry($0).map { range.contains($0.worldSize.height) } ?? false }
        // 筛空了就不筛 —— 少一层筛选比空掉一整层强。
        return hit.isEmpty ? all : hit
    }
}

enum BlockShape {
    case box        // 房子
    case tree       // 圆冠树
    case pine       // 尖顶树
    case rock       // 石头
    case bush       // 灌木
    case pole       // 路灯/电线杆
    case hill       // 远山
    case roundedBox // 通用块

    /// 同一层里房子和灌木不能一样大。这个倍率叠在层的 heightRange 上。
    var sizeScale: CGFloat {
        switch self {
        case .box: return 1.55
        case .tree: return 1.0
        case .pine: return 1.15
        case .rock: return 0.62
        case .bush: return 0.5
        case .pole: return 1.3
        case .hill, .roundedBox: return 1.0
        }
    }

    /// 接触影相对形状宽度的比例。路灯的杆很细，影子不能按外框宽度画。
    /// 0 = 不画影子（远景带在地平线上，没有接地关系）。
    var shadowWidthFactor: CGFloat {
        switch self {
        case .box, .rock, .bush, .roundedBox: return 1.0
        case .tree: return 0.72
        case .pine: return 0.8
        case .pole: return 0.22
        case .hill: return 0
        }
    }
}

// MARK: - 人物：骨架 / 外观 / 动作
//
// 三层互不知道对方，所以「改人物形象」拆成三件互不牵连的小事：
//
//   改比例   → 改 Figure 里的 pivot 和 skin 尺寸
//   改外观   → 换 Skin 的 case（换成 .texture 就是接真资产，一根骨骼一行）
//   改动作   → 新增一个 MotionClip，零张新图
//
// 这个结构和 Spine / DragonBones 的导出结构是同构的。哪天手写数据不够用了，
// 换成它们的 runtime 不需要重新设计，骨骼名字对上即可。

enum BoneID: Hashable {
    case hip, torso, head, armFar, armNear, legFar, legNear
}

enum FigureInk {
    /// 0 = 全墨，1 = 纸白。
    case ink(CGFloat)
    /// 陶土强调色。
    case accent
}

enum Skin {
    /// 轴点在顶端，向下延伸。四肢用。
    case capsule(length: CGFloat, width: CGFloat, ink: FigureInk)
    /// 轴点在底边中点，向上延伸。躯干用。
    case panel(height: CGFloat, bottomWidth: CGFloat, topWidth: CGFloat, ink: FigureInk)
    /// 轴点在中心。头用。
    case blob(radius: CGFloat, ink: FigureInk)
    /// 真资产从这里进来。骨架和动作一个字都不用改。
    case texture(named: String, height: CGFloat, anchor: CGPoint)
    /// 纯变换骨骼，不画东西。
    case none
}

struct Bone {
    let id: BoneID
    /// nil = 挂在人物根节点上。父骨骼必须排在子骨骼前面。
    let parent: BoneID?
    /// 相对父骨骼轴点的位置，单位是人物身高的倍数。
    let pivot: CGPoint
    let skin: Skin
    /// 相对父骨骼的 zPosition。负值把远侧肢体压到躯干后面。
    let z: CGFloat
}

struct Figure {
    let bones: [Bone]
}

struct Track {
    /// 摆动幅度（弧度）。降低动态时只压缩它。
    var amplitude: CGFloat = 0
    var phaseShift: CGFloat = 0
    /// 静态姿势偏移（弧度）。举铁、躺下这类姿势主要靠它，且不受降低动态影响。
    var offset: CGFloat = 0
}

struct MotionClip {
    let name: String
    var tracks: [BoneID: Track] = [:]
    /// 身体上下起伏（身高倍数）。每一步一个起落。
    var bobAmplitude: CGFloat = 0
}

extension Figure {

    /// 灰模的行走者。所有数字都是身高的倍数 —— **改人物形象就是改这里。**
    static var walker: Figure {
        Figure(bones: [
            Bone(id: .hip, parent: nil, pivot: CGPoint(x: 0, y: 0.40),
                 skin: .none, z: 0),

            // 远侧肢体更淡、压在躯干后面 —— 最便宜的一点体积感。
            Bone(id: .legFar, parent: .hip, pivot: CGPoint(x: -0.03, y: 0),
                 skin: .capsule(length: 0.40, width: 0.105, ink: .ink(0.30)), z: -1),

            Bone(id: .torso, parent: .hip, pivot: .zero,
                 skin: .panel(height: 0.34, bottomWidth: 0.23, topWidth: 0.20, ink: .accent), z: 2),

            Bone(id: .armFar, parent: .torso, pivot: CGPoint(x: -0.05, y: 0.286),
                 skin: .capsule(length: 0.30, width: 0.075, ink: .ink(0.34)), z: -1),

            Bone(id: .head, parent: .torso, pivot: CGPoint(x: 0, y: 0.447),
                 skin: .blob(radius: 0.13, ink: .ink(0)), z: 1),

            Bone(id: .armNear, parent: .torso, pivot: CGPoint(x: 0.05, y: 0.286),
                 skin: .capsule(length: 0.30, width: 0.075, ink: .ink(0)), z: 2),

            Bone(id: .legNear, parent: .hip, pivot: CGPoint(x: 0.03, y: 0),
                 skin: .capsule(length: 0.40, width: 0.105, ink: .ink(0)), z: 3)
        ])
    }
}

extension MotionClip {

    static var walking: MotionClip {
        MotionClip(name: "走", tracks: [
            .legFar: Track(amplitude: Tuning.legSwing, phaseShift: 0),
            .legNear: Track(amplitude: Tuning.legSwing, phaseShift: .pi),
            .armFar: Track(amplitude: Tuning.armSwing, phaseShift: .pi),
            .armNear: Track(amplitude: Tuning.armSwing, phaseShift: 0)
        ], bobAmplitude: Tuning.bobHeightRatio)
    }

    /// 站着不动，只剩一点呼吸。犹豫的时候用。
    static var idle: MotionClip {
        MotionClip(name: "停", tracks: [
            .armFar: Track(amplitude: 0.03),
            .armNear: Track(amplitude: 0.03, phaseShift: .pi)
        ], bobAmplitude: Tuning.bobHeightRatio * 0.2)
    }

    // 下面两个是用来证明这套结构成立的：同一套骨架、同一套外观，
    // 只是另一组数字。以后的室内动作全部长这样，一张图都不用画。

    /// 举铁。
    static var lifting: MotionClip {
        MotionClip(name: "举铁", tracks: [
            .armFar: Track(amplitude: 0.34, phaseShift: 0, offset: -2.55),
            .armNear: Track(amplitude: 0.34, phaseShift: 0, offset: 2.55),
            .legFar: Track(offset: -0.12),
            .legNear: Track(offset: 0.12),
            .torso: Track(amplitude: 0.03)
        ], bobAmplitude: 0.008)
    }

    /// 躺下睡。根骨骼一个 offset 就把人放倒了。
    static var sleeping: MotionClip {
        MotionClip(name: "睡", tracks: [
            .hip: Track(offset: -.pi / 2),
            .legFar: Track(offset: 0.18),
            .legNear: Track(offset: -0.10),
            .armFar: Track(offset: 0.42),
            .armNear: Track(offset: -0.34),
            // 呼吸
            .torso: Track(amplitude: 0.018)
        ], bobAmplitude: 0)
    }
}

/// 一个按骨架搭出来的人物。外观由 `Skin` 决定，姿态由 `MotionClip` 决定，
/// 两者都可以随时换掉而不影响另一个。
final class FigureNode: SKNode {

    private let figureHeight: CGFloat
    private var boneNodes: [BoneID: SKNode] = [:]
    private let body = SKNode()
    private var clip: MotionClip

    init(figure: Figure, height: CGFloat, clip: MotionClip) {
        self.figureHeight = height
        self.clip = clip
        super.init()
        addChild(body)

        for bone in figure.bones {
            let node = SKNode()
            node.position = CGPoint(x: bone.pivot.x * height, y: bone.pivot.y * height)
            node.zPosition = bone.z
            if let skin = FigureNode.makeSkinNode(bone.skin, height: height) {
                node.addChild(skin)
            }
            let parent = bone.parent.flatMap { boneNodes[$0] } ?? body
            parent.addChild(node)
            boneNodes[bone.id] = node
        }
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 换一个动作。骨架和外观不动。
    func play(_ clip: MotionClip) { self.clip = clip }

    /// `intensity` 只压缩摆动幅度，不压缩静态姿势 ——
    /// 降低动态不该让一个躺着的人站起来。
    func apply(phase: CGFloat, intensity: CGFloat) {
        for (id, node) in boneNodes {
            let track = clip.tracks[id] ?? Track()
            node.zRotation = track.offset
                + track.amplitude * intensity * sin(phase + track.phaseShift)
        }
        body.position.y = abs(sin(phase)) * clip.bobAmplitude * figureHeight * intensity
    }

    private static func makeSkinNode(_ skin: Skin, height: CGFloat) -> SKNode? {
        switch skin {
        case .none:
            return nil

        case let .capsule(length, width, ink):
            let l = length * height
            let w = width * height
            let node = SKShapeNode(path: CGPath(roundedRect: CGRect(x: -w / 2, y: -l,
                                                                    width: w, height: l),
                                                cornerWidth: w / 2, cornerHeight: w / 2,
                                                transform: nil))
            node.fillColor = figureColor(ink)
            node.strokeColor = .clear
            return node

        case let .panel(panelHeight, bottomWidth, topWidth, ink):
            let h = panelHeight * height
            let bw = bottomWidth * height
            let tw = topWidth * height
            let node = SKShapeNode(path: handDrawnPolygon([
                CGPoint(x: -bw / 2, y: 0),
                CGPoint(x: bw / 2, y: 0),
                CGPoint(x: tw / 2, y: h),
                CGPoint(x: -tw / 2, y: h)
            ], wobble: height * Tuning.handWobble))
            node.fillColor = figureColor(ink)
            node.strokeColor = .clear
            return node

        case let .blob(radius, ink):
            let r = radius * height
            let node = SKShapeNode(path: blobPath(center: .zero, rx: r, ry: r,
                                                  lobes: 9, wobble: Tuning.blobWobble * 0.5))
            node.fillColor = figureColor(ink)
            node.strokeColor = .clear
            return node

        case let .texture(named, textureHeight, anchor):
            guard UIImage(named: named) != nil else { return nil }
            let texture = SKTexture(imageNamed: named)
            let source = texture.size()
            let scale = (textureHeight * height) / max(source.height, 1)
            let node = SKSpriteNode(texture: texture)
            node.size = CGSize(width: source.width * scale, height: source.height * scale)
            node.anchorPoint = anchor
            return node
        }
    }
}

// MARK: - 视图

/// 灰模阶段的道路世界：没有任何贴图，全部是纯色形状。
/// 调完 `Tuning` 之后，那些数字就是资产表。
final class RoadSceneView: UIView {
    private let spriteView = SKView()
    private var world: PathWorldScene?

    /// 场景还没搭起来时收到的那些调用。
    ///
    /// 闭环在 `viewDidLoad` 里就会 `resume()`，而这时候 `layoutSubviews` 还没跑过，
    /// 场景是 nil —— 「说到一半退出、回来接着选」那条路径上，岔路就这么被丢掉了：
    /// 文案在、按钮在，路上什么都没有。
    private var pendingReveal = false
    private var pendingCount = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        isUserInteractionEnabled = false
        backgroundColor = Palette.canvasTop

        spriteView.allowsTransparency = true
        spriteView.backgroundColor = .clear
        spriteView.isOpaque = false
        spriteView.ignoresSiblingOrder = true
        spriteView.preferredFramesPerSecond = 60
        addSubview(spriteView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        spriteView.frame = bounds
        if let world {
            world.size = bounds.size
        } else if bounds.width > 0, bounds.height > 0 {
            let scene = PathWorldScene(size: bounds.size)
            spriteView.presentScene(scene)
            world = scene
            scene.setPendingCount(pendingCount)
            if pendingReveal {
                pendingReveal = false
                scene.presentFork()
            }
        }
    }

    // MARK: 闭环碰世界的五个方法（语义不变）

    /// 前方分叉。**在用户开口的那一刻**，不是走到某个地点。
    func revealFork() {
        guard let world else { pendingReveal = true; return }
        world.presentFork()
    }

    func choose(left: Bool) { world?.crossFork(left: left) }

    func reset() {
        pendingReveal = false
        world?.resetFork()
    }

    /// 换人物动作。以后「走进健身房举铁」就是调这个，不需要新资产。
    func playTravelerMotion(_ clip: MotionClip) { world?.playTravelerMotion(clip) }

    /// 身后还亮着几个等待回访的路口。
    /// PRD 11.2：等待结果的选择不是一张卡片，是路上一个还亮着的标记。
    func setPendingCount(_ count: Int) {
        pendingCount = count
        world?.setPendingCount(count)
    }

    /// 视频世界（`WorldVideoView`）暂时不接在这里。
    ///
    /// 它渲得比程序世界好看得多，但**一段循环只能朝一个方向滚**，
    /// 而这一版的路要在用户开口时分叉、要拐 90 度。形状会变的东西，
    /// 交给能变形的那一层画。代码留着，见 Docs/Handoff 第 11 节。
    func pauseWorld() {}
    func resumeWorld() {}
}

// MARK: - 场景

private final class JourneyScene: SKScene {

    private enum JourneyState { case walking, deciding, crossing }

    private enum Z {
        static let backdrop: CGFloat = -10
        static let road: CGFloat = 200
        static let lane: CGFloat = 210
        static let gate: CGFloat = 450
        static let traveler: CGFloat = 500
        static let grain: CGFloat = 900
    }

    private struct BandItem {
        let node: SKNode
        let band: Int
        let width: CGFloat
    }

    private struct RoadProp {
        let node: SKNode
        let layer: Int
    }

    private let worldNode = SKNode()
    private let travelerNode = SKNode()
    private var backdrop: SKSpriteNode?
    private var paperGrain: SKSpriteNode?

    private var bandItems: [BandItem] = []
    private var bandTailX: [CGFloat] = []
    private var roadProps: [RoadProp] = []
    private var layerTailS: [CGFloat] = []
    private var laneMarkers: [SKShapeNode] = []

    private var roadStart = CGPoint.zero
    private var direction = CGVector(dx: 1, dy: 0)
    private var normal = CGVector(dx: 0, dy: 1)
    private var roadLength: CGFloat = 1
    /// 进入点到离开点的距离。人物和路标的位置按它算，不按全长算。
    private var visibleSpan: CGFloat = 1

    /// 这条街在哪儿，以及这一趟用哪几栋楼。都在 `rebuild()` 里定一次。
    /// 只在**程序世界**下用得上；视频世界里这些东西都在视频里。
    private var streetPack = "oldtown"
    private var streetPalette: [String] = []

    /// 世界那一层是视频，不用自己画。
    var usesVideoWorld = false
    /// 步速变了就告诉外面 —— 视频要跟着同一个数变倍速。
    var onPaceChange: ((CGFloat) -> Void)?

    private var journeyState: JourneyState = .walking
    /// 世界前进的速度。**只有这一个数** —— 视频的倍速、景物的位移、人物的步频
    /// 都从它派生，所以三者不可能各走各的。
    private var pace: CGFloat = Tuning.paceWalking {
        didSet {
            guard pace != oldValue else { return }
            onPaceChange?(pace)
        }
    }
    private var lastUpdateTime: TimeInterval = 0

    /// 累计行走距离。步态相位由它驱动，不由时间驱动 —— 这是脚不滑的原因。
    private var walkDistance: CGFloat = 0

    private var traveler: FigureNode?
    private var travelerMotion: MotionClip = .walking

    private let pendingNode = SKNode()
    private var pendingMarkers: [SKNode] = []
    private var pendingDistances: [CGFloat] = []
    private var pendingCount = 0

    private var decisionGate: SKNode?
    private weak var leftBoard: SKShapeNode?
    private weak var rightBoard: SKShapeNode?

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMove(to view: SKView) {
        addChild(worldNode)
        addChild(pendingNode)
        addChild(travelerNode)
        rebuild()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard view != nil, oldSize != size else { return }
        rebuild()
    }

    func restage() { rebuild() }

    func playTravelerMotion(_ clip: MotionClip) {
        travelerMotion = clip
        traveler?.play(clip)
    }

    func setPendingCount(_ count: Int) {
        guard count != pendingCount else { return }
        pendingCount = count
        rebuildPendingMarkers()
    }

    static var parallaxReport: String {
        let bands = Tuning.bands.map { "\($0.name) \(String(format: "%.2f", $0.speed))" }
        let roads = Tuning.roadLayers.map { "\($0.name) \(String(format: "%.2f", $0.speed))" }
        return (bands + roads + ["人物 1.00"]).joined(separator: " | ")
    }

    /// 把「可见路段上的比例」换算成沿路距离。
    private func distance(atVisibleProgress progress: CGFloat) -> CGFloat {
        Tuning.roadBackExtension + visibleSpan * progress
    }

    // MARK: 更新

    override func update(_ currentTime: TimeInterval) {
        guard lastUpdateTime > 0 else {
            lastUpdateTime = currentTime
            return
        }
        let delta = min(CGFloat(currentTime - lastUpdateTime), 1 / 20)
        lastUpdateTime = currentTime

        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        approachJunction()
        let travel = pace * delta

        if !usesVideoWorld {
            moveBands(travel: travel, reduceMotion: reduceMotion)
            moveLaneMarkers(travel: travel)
            moveRoadProps(travel: travel, reduceMotion: reduceMotion)
        }
        if let gate = decisionGate { move(gate, by: travel) }
        movePendingMarkers(travel: travel)
        updateTraveler(distance: travel, reduceMotion: reduceMotion)
    }

    /// 走到路口就停下。
    ///
    /// 「思考时慢慢走」原本是 13pt/s 匀速 —— 听起来对，实际是：用户读两行字的功夫，
    /// 路标就从他前面漂到身后、再漂出屏幕，只剩两个按钮悬在一片空地上。
    /// 想久一点是这个产品预期中的事，所以不能让「想久一点」把画面走坏。
    ///
    /// 停下来也更对：你是在**这个路口**停住的，不是边走边选。
    /// 步态不用另外处理 —— 相位由行走距离驱动，距离不涨，人就自然停在半步上。
    private func approachJunction() {
        guard journeyState == .deciding, let gate = decisionGate else { return }
        let remaining = projection(of: gate.position)
            - distance(atVisibleProgress: Tuning.travelerProgress)
            - Tuning.gateStandoff
        // 剩下的距离越短走得越慢，到路口正好是 0。0.34 是让减速看得出来、
        // 又不至于在半屏之外就开始爬。
        let eased = max(0, min(Tuning.paceDeciding, remaining * 0.34))
        // 指数收敛永远到不了 0：不掐掉的话世界会以 0.02 倍速一直爬，
        // 看起来像「停住了但又没完全停」，而视频那一层还得为这点速度一直解码。
        pace = eased < 1 ? 0 : eased
    }

    /// 降低动态时把各层速度向 1.0 收拢，而不是整体放慢。
    private func effectiveSpeed(_ speed: CGFloat, reduceMotion: Bool) -> CGFloat {
        guard reduceMotion else { return speed }
        return 1 + (speed - 1) * (1 - Tuning.reduceMotionParallaxPull)
    }

    // MARK: 决策路口

    func presentDecisionGate() {
        guard journeyState == .walking else { return }
        journeyState = .deciding
        pace = Tuning.paceDeciding

        let gate = makeDecisionGate()
        gate.position = point(along: distance(atVisibleProgress: Tuning.gateProgress), side: 0)
        gate.alpha = 0
        gate.setScale(0.72)
        gate.zPosition = Z.gate
        worldNode.addChild(gate)
        decisionGate = gate
        gate.run(.group([.fadeIn(withDuration: 0.45), .scale(to: 1, duration: 0.65)]))
    }

    func crossDecisionGate(left: Bool) {
        guard journeyState == .deciding else { return }
        journeyState = .crossing

        let selected = left ? leftBoard : rightBoard
        let other = left ? rightBoard : leftBoard
        selected?.fillColor = Palette.accent
        selected?.run(.sequence([.scale(to: 1.14, duration: 0.16), .scale(to: 1, duration: 0.22)]))
        other?.run(.fadeAlpha(to: 0.2, duration: 0.26))

        pace = Tuning.paceCrossing
        decisionGate?.run(.sequence([.wait(forDuration: 0.9), .fadeOut(withDuration: 0.45), .removeFromParent()]))
        run(.sequence([
            .wait(forDuration: 1.35),
            .run { [weak self] in
                self?.journeyState = .walking
                self?.pace = Tuning.paceWalking
                self?.decisionGate = nil
            }
        ]))
    }

    func resetDecisionGate() {
        decisionGate?.removeFromParent()
        decisionGate = nil
        leftBoard = nil
        rightBoard = nil
        journeyState = .walking
        pace = Tuning.paceWalking
    }

    // MARK: 搭建

    private func rebuild() {
        guard size.width > 0, size.height > 0 else { return }

        worldNode.removeAllChildren()
        travelerNode.removeAllChildren()
        bandItems.removeAll()
        bandTailX.removeAll()
        roadProps.removeAll()
        layerTailS.removeAll()
        laneMarkers.removeAll()
        decisionGate = nil
        traveler = nil
        walkDistance = 0
        chooseStreet()

        // 进入点和离开点都钉在左右侧边上，倾角由它们推出来。
        let entry = CGPoint(x: 0, y: size.height * Tuning.roadEntryHeightRatio)
        let exit = CGPoint(x: size.width, y: size.height * Tuning.roadExitHeightRatio)
        let dx = exit.x - entry.x
        let dy = exit.y - entry.y
        visibleSpan = max(hypot(dx, dy), 1)
        direction = CGVector(dx: dx / visibleSpan, dy: dy / visibleSpan)
        normal = CGVector(dx: -direction.dy, dy: direction.dx)

        // 往进入点之前退一段，让景物在画面外就位。
        roadStart = CGPoint(x: entry.x - direction.dx * Tuning.roadBackExtension,
                            y: entry.y - direction.dy * Tuning.roadBackExtension)
        roadLength = Tuning.roadBackExtension + visibleSpan + Tuning.roadForwardExtension

        // 视频世界里，底、路、远景带、沿路景物全部跳过 —— 那些视频里都有。
        // 留下来的四样是**必须跟着数据动**的：人物、路标、身后的灯、纸纹。
        // 注意几何还是要算（`point(along:side:)`）：人物和路标要站在视频那条路上，
        // 靠的就是同一套 entry/exit 比例。
        if !usesVideoWorld {
            addBackdrop()
            addRoad()
            addBands()
            addRoadProps()
        }
        addTraveler()
        rebuildPendingMarkers()
        addPaperGrain()
        resetDecisionGate()
    }

    /// 挑这条街在哪儿，以及这一趟反复出现的那几栋楼。
    ///
    /// 挑一小把而不是全用上，有两个原因，缺一个都不够：
    /// 内存（一张贴图解出来几兆，20 张同时在内存里就是几十兆），
    /// 以及**真实的街本来就是几栋楼反复出现**，全不一样反而假。
    private func chooseStreet() {
        streetPack = Tuning.streetPacks.randomElement() ?? "oldtown"
        streetPalette = Array(SceneArt.ids(pack: streetPack).shuffled()
                                .prefix(Tuning.streetPaletteSize))
    }

    /// 这一层能用的街景资产。先按层的高度区间筛，再和这一趟的选集取交集 ——
    /// 交空了就退回按高度筛的全集，宁可多一张贴图也不要空掉一层。
    private func streetIDs(heightMeters: ClosedRange<CGFloat>?) -> [String] {
        let allowed = SceneArt.ids(pack: streetPack, heightMeters: heightMeters)
        let inPalette = allowed.filter(streetPalette.contains)
        return inPalette.isEmpty ? allowed : inPalette
    }

    /// 场景自带一层不透明纸色底。纸纹用 multiply 混合，必须有东西可乘 ——
    /// 直接压在透明画布上会算不出颜色。
    private func addBackdrop() {
        backdrop?.removeFromParent()
        let node = SKSpriteNode(color: Palette.paper, size: size)
        node.position = CGPoint(x: size.width / 2, y: size.height / 2)
        node.zPosition = Z.backdrop
        addChild(node)
        backdrop = node
    }

    private func addPaperGrain() {
        paperGrain?.removeFromParent()
        // 视频世界里不铺纸纹。
        //
        // 它是 `.multiply` 的：在切图世界里下面永远是那张纸色底，乘出来就是纸感；
        // 但在视频上面，`.multiply` 会把整帧压暗到三分之一 —— 实测地面
        // 148 → 49。SpriteKit 的 multiply 不按 alpha 插值回目标色，
        // 调 `paperGrainStrength` 救不回来。要纸感得在视频那一层做。
        guard !usesVideoWorld, Tuning.paperGrainStrength > 0 else { return }
        let node = SKSpriteNode(texture: SKTexture(image: paperGrainImage(for: size)))
        node.size = size
        node.position = CGPoint(x: size.width / 2, y: size.height / 2)
        node.zPosition = Z.grain
        node.blendMode = .multiply
        node.alpha = Tuning.paperGrainStrength
        addChild(node)
        paperGrain = node
    }

    private func addRoad() {
        let half = Tuning.roadWidth / 2
        let path = CGMutablePath()
        path.move(to: point(along: -600, side: half))
        path.addLine(to: point(along: roadLength + 600, side: half))
        path.addLine(to: point(along: roadLength + 600, side: -half))
        path.addLine(to: point(along: -600, side: -half))
        path.closeSubpath()

        let road = SKShapeNode(path: path)
        road.fillColor = tinted(0.74)
        road.strokeColor = .clear
        road.zPosition = Z.road
        worldNode.addChild(road)

        // 车道标记：贴地的东西，跟着路的方向旋转。
        let dashRotation = atan2(direction.dy, direction.dx) - .pi / 2
        var s: CGFloat = -Tuning.laneDashGap
        while s < roadLength + Tuning.laneDashGap * 2 {
            let dash = SKShapeNode(rectOf: CGSize(width: Tuning.laneDashWidth,
                                                  height: Tuning.laneDashLength),
                                   cornerRadius: Tuning.laneDashWidth / 2)
            dash.fillColor = tinted(0.42)
            dash.strokeColor = .clear
            dash.position = point(along: s, side: 0)
            dash.zRotation = dashRotation
            dash.zPosition = Z.lane
            worldNode.addChild(dash)
            laneMarkers.append(dash)
            s += Tuning.laneDashGap
        }
    }

    private func addBands() {
        for (index, spec) in Tuning.bands.enumerated() {
            bandTailX.append(-160)
            let baseline = size.height * spec.baselineRatio
            var x: CGFloat = -160
            while x < size.width + 260 {
                let (node, width) = makeBandItem(for: spec)
                // 贴图的轴点是接地点（横向居中），形状也是横向居中，两者对齐方式一样。
                node.position = CGPoint(x: x + width / 2, y: baseline)
                // 天际线是重叠着排的，谁高谁在后 —— 和沿路层同一个道理（见 place），
                // 只是这里没有「离路多远」，用高度代替：一座城的远景就是高的在后面。
                node.zPosition = spec.z - node.calculateAccumulatedFrame().height / 1000
                worldNode.addChild(node)
                bandItems.append(BandItem(node: node, band: index, width: width))
                x += width + CGFloat.random(in: spec.gapRange)
                bandTailX[index] = x
            }
        }
    }

    /// 远景带里的一个元素。返回宽度是因为回收要用它算队尾。
    private func makeBandItem(for spec: BandSpec) -> (SKNode, CGFloat) {
        if let kinds = spec.kinds, let kind = kinds.randomElement() {
            let name: String?
            switch kind {
            case let .art(id): name = id
            case let .pack(pack):
                name = SceneArt.ids(pack: pack, heightMeters: spec.artHeightMeters).randomElement()
            case .street:
                name = streetIDs(heightMeters: spec.artHeightMeters).randomElement()
            case .shape: name = nil
            }
            // 天际线在地平线上，没有接地关系 —— 画影子会出现一排悬空的椭圆。
            if let name,
               let node = makeArtProp(named: name, tint: spec.tint,
                                      artScale: spec.artScale, groundShadow: false) {
                return (node, node.calculateAccumulatedFrame().width)
            }
        }
        let width = CGFloat.random(in: spec.widthRange)
        let height = CGFloat.random(in: spec.heightRange)
        return (makeBlock(shape: spec.shape, height: height, width: width, tint: spec.tint), width)
    }

    private func addRoadProps() {
        for (index, spec) in Tuning.roadLayers.enumerated() {
            layerTailS.append(-240)
            var s: CGFloat = -240
            while s < roadLength + 420 {
                let node = makeProp(for: spec)
                place(node, spec: spec, along: s, side: CGFloat.random(in: spec.sideRange))
                worldNode.addChild(node)
                roadProps.append(RoadProp(node: node, layer: index))
                s += CGFloat.random(in: spec.gapRange)
                layerTailS[index] = s
            }
        }
    }

    /// 摆一个沿路景物：位置按路的坐标算，**层内的前后由离路多远决定**。
    ///
    /// 一排楼是会互相遮的。同层同 z 时 SpriteKit 按加入顺序画，而回收会把节点
    /// 挪到队尾却不改加入顺序 —— 于是走着走着，远处的楼会压到近处的楼前面。
    /// 让 z 跟着 side 走就没有这个问题：谁离路远谁在后面，永远成立。
    /// 除数取 100 是量出来的：`sideRange` 最大 420，偏移最多 4.2，
    /// 而层与层之间的 z 差是 20，够不着邻层。
    private func place(_ node: SKNode, spec: RoadLayerSpec, along s: CGFloat, side: CGFloat) {
        node.position = point(along: s, side: side)
        node.zPosition = spec.z - side / 100
    }

    private func makeProp(for spec: RoadLayerSpec) -> SKNode {
        let name: String?
        switch spec.kinds.randomElement() ?? .shape(.box) {
        case let .art(id):
            name = id
        case let .pack(pack):
            name = SceneArt.ids(pack: pack, heightMeters: spec.artHeightMeters).randomElement()
        case .street:
            name = streetIDs(heightMeters: spec.artHeightMeters).randomElement()
        case let .shape(shape):
            return makeShapeProp(shape, spec: spec)
        }
        // 贴图缺了就干净降级回程序形状 —— 画面不空，也就可以一个资产一个资产地换。
        // 代价是这种失败很安静：楼变成灰块，不报错。
        guard let name,
              let node = makeArtProp(named: name, tint: spec.tint, artScale: spec.artScale)
        else { return makeShapeProp(.box, spec: spec) }
        return node
    }

    private func makeShapeProp(_ shape: BlockShape, spec: RoadLayerSpec) -> SKNode {
        let height = Tuning.travelerHeight * CGFloat.random(in: spec.heightRange) * shape.sizeScale
        let width = height * CGFloat.random(in: 0.5...0.95)

        let container = SKNode()
        if shape.shadowWidthFactor > 0 {
            container.addChild(makeContactShadow(width: width * shape.shadowWidthFactor))
        }
        container.addChild(makeBlock(shape: shape, height: height, width: width, tint: spec.tint))
        // 水平翻转 —— 一个形状立刻多出一种观感。资产真正画出来之后这条最省力。
        if Bool.random() { container.xScale = -1 }
        // 立着的东西永远不跟路旋转。只有贴地的（车道线、影子）才旋转。
        return container
    }

    /// Blender 渲出来的贴图。尺寸不由 heightRange 决定，而是由 manifest 里的
    /// 真实高度换算 —— 一栋 14 米的楼和一个 1.7 米的人的比例是建模时定的，
    /// 上屏之后不会再漂。
    private func makeArtProp(named name: String, tint: CGFloat,
                             artScale: CGFloat = 1, groundShadow: Bool = true) -> SKNode? {
        guard UIImage(named: name) != nil, let entry = SceneArt.entry(name) else { return nil }

        let world = entry.worldSize
        guard world.height > 0 else { return nil }
        let scale = Tuning.pointsPerMeter * Tuning.buildingScale * artScale
        let width = world.width * scale
        let height = world.height * scale

        let sprite = SKSpriteNode(texture: SKTexture(imageNamed: name))
        sprite.size = CGSize(width: width, height: height)
        // manifest 的 anchor 就是接地点，和 SKSpriteNode 同一套坐标系，直接填。
        sprite.anchorPoint = CGPoint(x: entry.anchor.first ?? 0.5,
                                     y: entry.anchor.count > 1 ? entry.anchor[1] : 0)
        // 远近仍然靠墨色浓淡 —— 贴图和程序形状走同一条规则，才会像一个世界。
        sprite.color = Palette.paper
        sprite.colorBlendFactor = tint

        let container = SKNode()
        container.addChild(makeContactShadow(width: width * (entry.shadowWidthFactor ?? 1)))
        container.addChild(sprite)
        if Bool.random() { container.xScale = -1 }
        return container
    }

    // MARK: 人物

    private func addTraveler() {
        let root = SKNode()
        root.position = point(along: distance(atVisibleProgress: Tuning.travelerProgress), side: 0)
        root.zPosition = Z.traveler
        // 注意：这里不设 zRotation。人是立着的。
        travelerNode.addChild(root)

        // 影子挂在 root 上而不是人物上 —— 人起伏时影子不该跟着跳。
        root.addChild(makeContactShadow(width: Tuning.travelerHeight * 0.34))

        let figure = FigureNode(figure: .walker,
                                height: Tuning.travelerHeight,
                                clip: travelerMotion)
        root.addChild(figure)
        traveler = figure
    }

    // MARK: 待回访标记

    /// 两盏待回访的灯之间隔多远，以及它们离路中心多远。
    /// 按**世界里的米**给，不按屏幕点 —— 视频世界的尺度和切图世界差三倍，
    /// 写死点数会让灯挤成一团、或者插到路当中。
    private static var pendingSpacing: CGFloat { 3.4 * Tuning.pointsPerMeter }
    private static var pendingSide: CGFloat { -1.5 * Tuning.pointsPerMeter }

    private func rebuildPendingMarkers() {
        pendingNode.removeAllChildren()
        pendingMarkers.removeAll()
        pendingDistances.removeAll()
        guard pendingCount > 0, visibleSpan > 1 else { return }

        let travelerDistance = distance(atVisibleProgress: Tuning.travelerProgress)
        for index in 0..<pendingCount {
            let marker = makePendingMarker()
            let s = travelerDistance - CGFloat(index + 1) * Self.pendingSpacing
            marker.position = point(along: s, side: Self.pendingSide)
            marker.zPosition = Z.traveler - 5
            pendingNode.addChild(marker)
            pendingMarkers.append(marker)
            pendingDistances.append(s)
        }
    }

    /// 一根细杆加一盏还亮着的灯。整个世界里只有它和用户的选择是暖的 ——
    /// 「还没有结果的事」应该是唯一会发光的东西。
    private func makePendingMarker() -> SKNode {
        let container = SKNode()
        let height = Tuning.travelerHeight * 0.62
        container.addChild(makeContactShadow(width: height * 0.28))

        let post = SKShapeNode(path: handDrawnPolygon([
            CGPoint(x: -height * 0.035, y: 0),
            CGPoint(x: height * 0.035, y: 0),
            CGPoint(x: height * 0.035, y: height),
            CGPoint(x: -height * 0.035, y: height)
        ], wobble: height * Tuning.handWobble))
        post.fillColor = tinted(0.24)
        post.strokeColor = .clear
        container.addChild(post)

        let lamp = SKShapeNode(circleOfRadius: height * 0.13)
        lamp.position = CGPoint(x: 0, y: height)
        lamp.fillColor = Palette.accent
        lamp.strokeColor = .clear
        container.addChild(lamp)

        let halo = SKShapeNode(circleOfRadius: height * 0.26)
        halo.position = lamp.position
        halo.fillColor = Palette.accent.withAlphaComponent(0.22)
        halo.strokeColor = .clear
        halo.zPosition = -1
        container.addChild(halo)

        if !UIAccessibility.isReduceMotionEnabled {
            // 极慢的呼吸。它在等，不是在提醒 —— PRD 14.3：不催促。
            halo.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.42, duration: 1.9),
                .fadeAlpha(to: 0.16, duration: 1.9)
            ])))
        }
        return container
    }

    private func movePendingMarkers(travel: CGFloat) {
        guard !pendingMarkers.isEmpty else { return }
        let trail = CGFloat(pendingMarkers.count) * Self.pendingSpacing
        let travelerDistance = distance(atVisibleProgress: Tuning.travelerProgress)
        for index in pendingMarkers.indices {
            pendingDistances[index] -= travel
            // 掉出队尾就绕回人物身后，所以「三个待回访」永远是三盏灯，
            // 数量是真的，不是装饰。
            if pendingDistances[index] < travelerDistance - trail {
                pendingDistances[index] += trail
            }
            pendingMarkers[index].position = point(along: pendingDistances[index], side: Self.pendingSide)
        }
    }

    private func updateTraveler(distance: CGFloat, reduceMotion: Bool) {
        walkDistance += distance

        // 相位由行走距离驱动。pace 从 13 跳到 72 时步频自动跟上，脚不会滑 ——
        // 因为脚的接触点和世界滚动用的是同一个距离量。
        let phase = walkDistance / max(Tuning.strideLength, 1) * .pi * 2
        traveler?.apply(phase: phase,
                        intensity: reduceMotion ? Tuning.reduceMotionSwingScale : 1)
    }

    // MARK: 运动与回收

    private func moveBands(travel: CGFloat, reduceMotion: Bool) {
        for item in bandItems {
            let spec = Tuning.bands[item.band]
            item.node.position.x -= travel * effectiveSpeed(spec.speed, reduceMotion: reduceMotion)
            if item.node.position.x + item.width / 2 < -80 {
                let x = bandTailX[item.band] + CGFloat.random(in: spec.gapRange)
                item.node.position.x = x + item.width / 2
                bandTailX[item.band] = x + item.width
            }
        }
    }

    private func moveLaneMarkers(travel: CGFloat) {
        for dash in laneMarkers {
            move(dash, by: travel)
            if projection(of: dash.position) < -Tuning.laneDashGap {
                dash.position = point(along: projection(of: dash.position) + roadLength
                                      + Tuning.laneDashGap * 2, side: 0)
            }
        }
    }

    private func moveRoadProps(travel: CGFloat, reduceMotion: Bool) {
        for prop in roadProps {
            let spec = Tuning.roadLayers[prop.layer]
            move(prop.node, by: travel * effectiveSpeed(spec.speed, reduceMotion: reduceMotion))
            guard projection(of: prop.node.position) < -420 else { continue }

            // 从这一层的队尾接着排，间距重新抖动 —— 所以循环周期不是固定的。
            layerTailS[prop.layer] += CGFloat.random(in: spec.gapRange)
            place(prop.node, spec: spec, along: layerTailS[prop.layer],
                  side: CGFloat.random(in: spec.sideRange))
            let s = CGFloat.random(in: 0.85...1.15)
            prop.node.xScale = Bool.random() ? s : -s
            prop.node.yScale = s
        }
    }

    // MARK: 形状
    //
    // 每个部件是独立的 SKShapeNode 子节点，不合并到同一条 path 里 —— SKShapeNode
    // 按 even-odd 填充，同一条 path 内重叠的子图形会被挖空（树干在树冠下变白）。
    // 拆成子节点之后这类 bug 结构上不可能再出现。

    private func makeBlock(shape: BlockShape, height: CGFloat, width: CGFloat?,
                           tint: CGFloat, floorDepth: CGFloat = 0) -> SKNode {
        let w = width ?? height * CGFloat.random(in: 0.5...0.95)
        let container = SKNode()
        let color = tinted(tint)
        let wob = Tuning.handWobble

        func piece(_ path: CGPath) -> SKShapeNode {
            let node = SKShapeNode(path: path)
            node.fillColor = color
            node.strokeColor = .clear
            return node
        }

        switch shape {
        case .box:
            let bodyH = height * 0.78
            let eave = w * 0.08
            container.addChild(piece(handDrawnPolygon([
                CGPoint(x: -w / 2, y: 0),
                CGPoint(x: w / 2, y: 0),
                CGPoint(x: w / 2, y: bodyH),
                CGPoint(x: w / 2 + eave, y: bodyH),
                CGPoint(x: 0, y: height),
                CGPoint(x: -w / 2 - eave, y: bodyH),
                CGPoint(x: -w / 2, y: bodyH)
            ], wobble: w * wob)))

        case .roundedBox:
            let r = min(w, height) * Tuning.cornerRadiusRatio
            container.addChild(piece(CGPath(roundedRect: CGRect(x: -w / 2, y: -floorDepth,
                                                                width: w, height: height + floorDepth),
                                            cornerWidth: r, cornerHeight: r, transform: nil)))

        case .bush:
            container.addChild(piece(blobPath(center: CGPoint(x: 0, y: height / 2),
                                              rx: w / 2, ry: height / 2,
                                              lobes: 9, wobble: Tuning.blobWobble)))

        case .tree:
            let trunkH = height * 0.38
            let trunkW = w * 0.16
            container.addChild(piece(handDrawnPolygon([
                CGPoint(x: -trunkW / 2, y: 0),
                CGPoint(x: trunkW / 2, y: 0),
                CGPoint(x: trunkW / 2, y: trunkH),
                CGPoint(x: -trunkW / 2, y: trunkH)
            ], wobble: trunkW * wob)))
            let canopyH = height - trunkH
            container.addChild(piece(blobPath(center: CGPoint(x: 0, y: trunkH + canopyH / 2),
                                              rx: w / 2, ry: canopyH / 2,
                                              lobes: 10, wobble: Tuning.blobWobble)))

        case .pine:
            let trunkH = height * 0.20
            let trunkW = w * 0.14
            container.addChild(piece(handDrawnPolygon([
                CGPoint(x: -trunkW / 2, y: 0),
                CGPoint(x: trunkW / 2, y: 0),
                CGPoint(x: trunkW / 2, y: trunkH),
                CGPoint(x: w / 2, y: trunkH),
                CGPoint(x: 0, y: height),
                CGPoint(x: -w / 2, y: trunkH),
                CGPoint(x: -trunkW / 2, y: trunkH)
            ], wobble: w * wob)))

        case .rock:
            container.addChild(piece(handDrawnPolygon([
                CGPoint(x: -w / 2, y: 0),
                CGPoint(x: -w * 0.32, y: height * 0.82),
                CGPoint(x: w * 0.18, y: height),
                CGPoint(x: w / 2, y: height * 0.34)
            ], wobble: w * wob * 1.6)))

        case .pole:
            let postW = max(w * 0.10, 2)
            let headSize = w * 0.30
            let postTop = height - headSize * 0.5
            container.addChild(piece(handDrawnPolygon([
                CGPoint(x: -postW / 2, y: 0),
                CGPoint(x: postW / 2, y: 0),
                CGPoint(x: postW / 2, y: postTop),
                CGPoint(x: -postW / 2, y: postTop)
            ], wobble: postW * wob)))
            container.addChild(piece(blobPath(center: CGPoint(x: 0, y: postTop),
                                              rx: headSize / 2, ry: headSize / 2,
                                              lobes: 8, wobble: Tuning.blobWobble * 0.5)))

        case .hill:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -w / 2, y: -floorDepth))
            path.addLine(to: CGPoint(x: -w / 2, y: 0))
            path.addQuadCurve(to: CGPoint(x: w / 2, y: 0),
                              control: CGPoint(x: 0, y: height * 2))
            path.addLine(to: CGPoint(x: w / 2, y: -floorDepth))
            path.closeSubpath()
            container.addChild(piece(path))
        }

        return container
    }

    /// 把物体钉在地上的那一小片影子。没有它，所有东西都像浮在纸上的贴纸。
    private func makeContactShadow(width: CGFloat) -> SKShapeNode {
        let w = max(width, 4)
        let h = w * Tuning.contactShadowFlatness
        let node = SKShapeNode(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        node.fillColor = tinted(0.78)
        node.strokeColor = .clear
        node.alpha = Tuning.contactShadowOpacity
        node.zPosition = -1
        return node
    }

    /// 程序生成的纸纹：细颗粒 + 少量纤维。不需要任何资产。
    private func paperGrainImage(for size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let area = size.width * size.height
            let speckCount = Int(area / 90)
            for _ in 0..<speckCount {
                let radius = CGFloat.random(in: 0.4...1.6)
                let grey = CGFloat.random(in: 0.58...0.92)
                UIColor(white: grey, alpha: CGFloat.random(in: 0.10...0.26)).setFill()
                context.cgContext.fillEllipse(in: CGRect(x: CGFloat.random(in: 0..<size.width),
                                                         y: CGFloat.random(in: 0..<size.height),
                                                         width: radius, height: radius))
            }

            // 纤维要比颗粒更淡：太清楚就不是纸纹，是脏点。
            let fibreCount = Int(area / 1500)
            for _ in 0..<fibreCount {
                let origin = CGPoint(x: CGFloat.random(in: 0..<size.width),
                                     y: CGFloat.random(in: 0..<size.height))
                let angle = CGFloat.random(in: 0..<(.pi * 2))
                let length = CGFloat.random(in: 4...14)
                context.cgContext.setStrokeColor(UIColor(white: 0.80, alpha: 0.06).cgColor)
                context.cgContext.setLineWidth(CGFloat.random(in: 0.3...0.6))
                context.cgContext.move(to: origin)
                context.cgContext.addLine(to: CGPoint(x: origin.x + cos(angle) * length,
                                                      y: origin.y + sin(angle) * length))
                context.cgContext.strokePath()
            }
        }
    }

    private func makeDecisionGate() -> SKNode {
        let gate = SKNode()
        let offset = Tuning.gateSideOffset

        let left = makeSignpost()
        left.node.position = CGPoint(x: normal.dx * offset, y: normal.dy * offset)
        // 不设 zRotation —— 路标是立着的。
        gate.addChild(left.node)
        leftBoard = left.board

        let right = makeSignpost()
        right.node.position = CGPoint(x: -normal.dx * offset, y: -normal.dy * offset)
        gate.addChild(right.node)
        rightBoard = right.board

        return gate
    }

    /// 牌面留空。文字之后用 SKLabelNode 叠上去 —— 牌子上的字永远不画进资产。
    private func makeSignpost() -> (node: SKNode, board: SKShapeNode) {
        let h = Tuning.gateHeight
        let container = SKNode()
        let wobble = h * Tuning.handWobble

        container.addChild(makeContactShadow(width: h * 0.30))

        let postW = h * 0.09
        let post = SKShapeNode(path: handDrawnPolygon([
            CGPoint(x: -postW / 2, y: 0),
            CGPoint(x: postW / 2, y: 0),
            CGPoint(x: postW / 2, y: h),
            CGPoint(x: -postW / 2, y: h)
        ], wobble: postW * Tuning.handWobble))
        post.fillColor = tinted(0.18)
        post.strokeColor = .clear
        container.addChild(post)

        let boardW = h * 0.72
        let boardH = h * 0.40
        let boardY = h * 0.88
        let board = SKShapeNode(path: handDrawnPolygon([
            CGPoint(x: -boardW / 2, y: boardY - boardH / 2),
            CGPoint(x: boardW / 2, y: boardY - boardH / 2),
            CGPoint(x: boardW / 2, y: boardY + boardH / 2),
            CGPoint(x: -boardW / 2, y: boardY + boardH / 2)
        ], wobble: wobble))
        board.fillColor = tinted(0.10)
        board.strokeColor = .clear
        container.addChild(board)

        return (container, board)
    }

    // MARK: 几何

    private func move(_ node: SKNode, by distance: CGFloat) {
        node.position.x -= direction.dx * distance
        node.position.y -= direction.dy * distance
    }

    private func point(along: CGFloat, side: CGFloat) -> CGPoint {
        CGPoint(x: roadStart.x + direction.dx * along + normal.dx * side,
                y: roadStart.y + direction.dy * along + normal.dy * side)
    }

    private func projection(of point: CGPoint) -> CGFloat {
        let dx = point.x - roadStart.x
        let dy = point.y - roadStart.y
        return dx * direction.dx + dy * direction.dy
    }
}

// MARK: - 画形状的共用工具
//
// 文件级函数：场景和人物都要用。

/// 0 = 全墨，1 = 纸白。远近靠这个混出来，不靠新增颜色。
private func tinted(_ amount: CGFloat) -> UIColor {
    Palette.ink.mixed(with: Palette.paper, amount: amount)
}

private func figureColor(_ ink: FigureInk) -> UIColor {
    switch ink {
    case let .ink(amount): return tinted(amount)
    case .accent: return Palette.accent
    }
}

/// 沿点序列画一条闭合路径，每条边略微外鼓或内凹。
/// 手画的线没有真正的直线 —— 这一点抖动就是"手的痕迹"。
private func handDrawnPolygon(_ points: [CGPoint], wobble: CGFloat) -> CGPath {
    let path = CGMutablePath()
    guard points.count > 2 else { return path }
    path.move(to: points[0])
    for index in points.indices {
        let a = points[index]
        let b = points[(index + 1) % points.count]
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = max(hypot(dx, dy), 0.001)
        let push = CGFloat.random(in: -wobble...wobble)
        let control = CGPoint(x: (a.x + b.x) / 2 - dy / length * push,
                              y: (a.y + b.y) / 2 + dx / length * push)
        path.addQuadCurve(to: b, control: control)
    }
    path.closeSubpath()
    return path
}

/// 半径带抖动的闭合平滑曲线。比正圆更像手画的树冠或灌木。
private func blobPath(center: CGPoint, rx: CGFloat, ry: CGFloat,
                      lobes: Int, wobble: CGFloat) -> CGPath {
    let count = max(lobes, 5)
    var points: [CGPoint] = []
    for index in 0..<count {
        let angle = CGFloat(index) / CGFloat(count) * .pi * 2
        let radius = 1 + CGFloat.random(in: -wobble...wobble)
        points.append(CGPoint(x: center.x + cos(angle) * rx * radius,
                              y: center.y + sin(angle) * ry * radius))
    }
    func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
    let path = CGMutablePath()
    path.move(to: midpoint(points[count - 1], points[0]))
    for index in 0..<count {
        let current = points[index]
        let next = points[(index + 1) % count]
        path.addQuadCurve(to: midpoint(current, next), control: current)
    }
    path.closeSubpath()
    return path
}

private extension UIColor {
    /// 0 = self，1 = other。
    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        let t = max(0, min(1, amount))
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t,
                       green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t,
                       alpha: a1 + (a2 - a1) * t)
    }
}
