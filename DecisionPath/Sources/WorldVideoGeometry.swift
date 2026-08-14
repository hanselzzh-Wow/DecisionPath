import UIKit

/// 视频那条路在屏幕上的几何。
///
/// 这些数不是调出来的，是**从渲染相机上量出来的**：拿 Blender 自己的
/// `world_to_camera_view` 投影一批已知的世界坐标（路中心、路肩、一个 1.7 米的人），
/// 再换算成屏幕比例。脚本在 `scratchpad/calib.py`，改相机就重跑一次。
///
/// 全部存成**屏幕高度的比例**，不是 pt —— 视频按 `resizeAspectFill` 铺满，
/// 换机型时按高度缩放，存绝对值换个屏幕就全错了。
///
/// > ⚠️ 相机一改，这里每个数都得重量。它们和 `Blender/world_variants.py`
/// > 的 `SHARED_CAMERA` 是同一件事的两面，对不上的时候人物就会走在路边的草地上。
enum WorldVideoGeometry {

    /// 当前这套：tilt 36° / yaw 32° / ortho 54 / 720×1568。
    static let cameraNote = "tilt 36 / yaw 32 / ortho 54"

    /// 路中心线在左右边缘的高度（0 = 屏幕底，1 = 顶）。
    static let roadEntryRatio: CGFloat = 0.2178
    static let roadExitRatio: CGFloat = 0.6497
    /// 屏幕上的路宽 / 屏幕高。
    static let roadWidthRatio: CGFloat = 0.0415
    /// 沿路走一世界米 = 屏幕高的多少。世界的速度、人物的步频从它来。
    static let alongRoadRatio: CGFloat = 0.013476
    /// **竖着**一世界米 = 屏幕高的多少。人物、路标的高度从它来。
    ///
    /// 和上面那个差 11% —— 因为相机是斜的：沿路的一米被压缩得比竖着的一米多。
    /// 混用一个数不会崩，但人会矮一成；分开写更省得以后有人来「修」它。
    static let uprightRatio: CGFloat = 0.01501
    /// 视频里世界前进的速度（米/秒）= LOOP_LENGTH / LOOP_SECONDS = 48 / 12。
    static let metersPerSecond: CGFloat = 4

    /// 把 `Tuning` 换算到视频世界的尺度。
    ///
    /// 换算方向是**世界说了算**：视频里 1 米就是那么多点，人物按真实身高画，
    /// 所以人会比现在小很多（70pt → 22pt）。切图那版把人放大了 3 倍才让
    /// 一条街装进竖屏；视频不需要那个谎，因为镜头本来就是照着这个构图渲的。
    static func applyToTuning(screenHeight: CGFloat) {
        guard screenHeight > 0 else { return }
        let upright = uprightRatio * screenHeight        // 竖着的一米
        let along = alongRoadRatio * screenHeight        // 沿路的一米

        Tuning.roadEntryHeightRatio = roadEntryRatio
        Tuning.roadExitHeightRatio = roadExitRatio
        Tuning.roadWidth = roadWidthRatio * screenHeight

        // 人物按真实身高画。这一行决定了整个世界的尺度感 ——
        // `Tuning.pointsPerMeter` 是从它推出来的，所以改它等于改全场。
        //
        // 70pt → 22pt。切图那版把人放大了三倍多，才让一条街装进竖屏；
        // 视频不需要那个谎，镜头本来就是照着这个构图渲的。
        Tuning.travelerHeight = Tuning.figureHeightMeters * upright

        // 步幅 0.75 米，沿路量。步频 = 世界速度 / 步幅 ——
        // 这两个数都必须用沿路的那把尺，否则脚在地上滑。
        Tuning.strideLength = 0.75 * along
        Tuning.paceWalking = metersPerSecond * along
        Tuning.paceDeciding = Tuning.paceWalking * 0.42
        Tuning.paceCrossing = Tuning.paceWalking * 2.4

        // 路标也在这个世界里，跟着一起缩。2.6 米是路牌的高度 ——
        // 人 1.7 米，路牌比人高一点点，这个关系一错，尺度感就全塌了。
        Tuning.gateHeight = 2.6 * upright
        Tuning.gateSideOffset = 3.0 * along
        Tuning.gateStandoff = 5.0 * along
    }
}
