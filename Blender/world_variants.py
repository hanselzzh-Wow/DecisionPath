"""生成 DecisionPath 的两套整场景变体。

1. CBD：宽路、幕墙高层、裙房和少量地标。
2. Forest：缓弯道路、高树干、连续树冠、林下灌木和稀疏郊区住宅。

两套场景都沿用 journey_scene.py 的正交沙盘相机、人物和 12 秒无缝前进循环。
"""

import math
import os
import random
import sys

import bpy
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import buildings  # noqa: E402
import journey_scene as journey  # noqa: E402


FPS = 24
FRAME_START = 1
FRAME_END = 288
LOOP_LENGTH = 48.0
OUT_ROOT = os.path.join(SCRIPT_DIR, "out")
RENDER_SCALE = int(os.environ.get("WORLD_RENDER_SCALE", "50"))

# ---------------------------------------------------------------- 接成一条路
#
# 每个变体原来各有一台相机（tilt 34/36/38，ortho 38/54/67/76）。单独看都对，
# 但它们**接不成一条路**：切一次变体，路的角度和宽度就跳一次，读起来是换了个世界，
# 不是走到了另一个地方。
#
# 所以现在有一台共用相机。代价是 CBD 的塔会被画框切掉顶 ——
# 那不是缺陷，那正是从街上抬头看塔楼的样子。真正的取舍在别处：
# ortho_scale 一旦定死，「一米在屏幕上多少像素」就定死了，
# 而这个数同时决定了 App 里人物的步速（见 Docs/Handoff 第 12 节）。
SHARED_CAMERA = dict(
    target=(4.0, 0.0, 4.5),
    ortho_scale=float(os.environ.get("WORLD_ORTHO_SCALE", "54.0")),
    distance=52.0,
    tilt=36.0,
    yaw=32.0,
)

# 人物由 App 画，不烘进视频 —— 它要能停、能走进岔路、能换动作。
# 需要一段「带人物的纯视频」做对照时把这个设成 1。
WITH_TRAVELER = os.environ.get("WORLD_TRAVELER", "0") == "1"


def mat(name, hex_code, roughness=0.86):
    return journey.material(name, journey.srgb(hex_code), roughness)


def configure_scene(scene, variant, ground_color):
    journey.configure_scene(scene)
    scene.render.resolution_percentage = max(25, min(100, RENDER_SCALE))
    # 出片尺寸按屏幕比例给（402:874 ≈ 0.46），两边都取 16 的倍数 —— H.264 要的。
    # 720×1568 是 iPhone 竖屏的一半多一点：视频会被拉满屏，但它是连续色块 + 柔和阴影，
    # 拉伸看不出来，而渲染时间和文件大小都省一半。
    scene.render.resolution_x = int(os.environ.get("WORLD_RENDER_WIDTH", "720"))
    scene.render.resolution_y = int(os.environ.get("WORLD_RENDER_HEIGHT", "1568"))
    scene.render.filepath = os.path.join(OUT_ROOT, variant, f"{variant}-loop.mp4")
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = journey.srgb(ground_color)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.68
    scene.frame_start = FRAME_START
    scene.frame_end = FRAME_END
    scene.render.fps = FPS


def add_camera(scene, *, target, ortho_scale, distance, tilt=34.0, yaw=32.0):
    target = Vector(target)
    yaw_r = math.radians(yaw)
    tilt_r = math.radians(tilt)
    position = target + Vector((
        -math.cos(yaw_r) * math.cos(tilt_r) * distance,
        -math.sin(yaw_r) * math.cos(tilt_r) * distance,
        math.sin(tilt_r) * distance,
    ))
    data = bpy.data.cameras.new("JourneyCamera")
    data.type = "ORTHO"
    data.ortho_scale = ortho_scale
    camera = bpy.data.objects.new("JourneyCamera", data)
    scene.collection.objects.link(camera)
    camera.location = position
    journey.look_at(camera, target)
    scene.camera = camera
    return camera


def animate_world(root):
    root.location.x = 0.0
    root.keyframe_insert(data_path="location", frame=FRAME_START)
    root.location.x = -LOOP_LENGTH
    root.keyframe_insert(data_path="location", frame=FRAME_END + 1)
    for curve in journey.action_fcurves(root):
        for point in curve.keyframe_points:
            point.interpolation = "LINEAR"


def architecture_material(obj):
    rgba = tuple(obj.color)
    key = "Architecture-" + "-".join(f"{channel:.3f}" for channel in rgba[:3])
    return journey.material(key, rgba, roughness=0.88)


def parent_architecture(parts, holder):
    for part in parts:
        journey.assign_material(part, architecture_material(part))
        part.parent = holder


def add_street_tree(name, location, scale, parent, mats):
    journey.cylinder(
        f"{name}-trunk", 0.16 * scale, 2.0 * scale,
        (location[0], location[1], 1.0 * scale), mats["trunk"], 10, parent,
    )
    crown = journey.sphere(
        f"{name}-crown", 1.05 * scale,
        (location[0], location[1], 2.65 * scale), mats["leaf"], parent,
    )
    crown.scale = (0.88, 0.88, 1.20)


def add_lamp(name, location, parent, mats):
    journey.cylinder(name, 0.07, 3.8, (location[0], location[1], 1.9), mats["lamp"], 10, parent)
    journey.sphere(f"{name}-globe", 0.20, (location[0], location[1], 3.88), mats["globe"], parent)


# --------------------------------------------------------------------- CBD

TOWER_BY_ID = {asset_id: params for asset_id, _kind, params in buildings.TOWER_SPECS}
LANDMARK_BY_ID = {
    asset_id: (builder, params)
    for asset_id, _kind, builder, params in buildings.LANDMARK_SPECS
}

# (类型, 资产, 缩放, 估算占地宽, 估算占地深)
CBD_LAYOUT = [
    (("tower", "twr-07", 0.56, 16.0, 13.0), ("tower", "twr-03", 0.58, 10.0, 10.0)),
    (("tower", "twr-08", 0.42, 26.0, 18.0), ("landmark", "lm-twist", 0.48, 15.0, 15.0)),
    (("tower", "twr-05", 0.52, 17.0, 15.0), ("tower", "twr-06", 0.55, 12.0, 12.0)),
    (("tower", "twr-01", 0.54, 16.0, 14.0), ("landmark", "lm-portal", 0.43, 30.0, 13.0)),
]


def build_cbd_asset(name, spec, location, side, parent):
    kind, asset_id, scale, _width, _depth = spec
    if kind == "tower":
        parts, _height = buildings.make_tower(
            name, seed=sum(ord(c) for c in name), **dict(TOWER_BY_ID[asset_id])
        )
    else:
        builder, params = LANDMARK_BY_ID[asset_id]
        parts, _height = builder(
            name, seed=sum(ord(c) for c in name), **dict(params)
        )
    holder = journey.empty(f"{name}-Architecture", location, parent)
    holder.scale = (scale, scale, scale)
    if side < 0:
        holder.rotation_euler.z = math.pi
    parent_architecture(parts, holder)
    return holder


def populate_cbd_tile(tile_root, mats):
    road_width = 10.4
    sidewalk_width = 2.0
    for module in range(4):
        x = module * 12.0
        journey.box(f"CBD-Road-{module}", (12.1, road_width, 0.08), (x, 0, 0.04), mats["road"], tile_root)
        sy = road_width / 2 + sidewalk_width / 2
        for side in (-1, 1):
            journey.box(
                f"CBD-Sidewalk-{module}-{side}", (12.1, sidewalk_width, 0.14),
                (x, side * sy, 0.07), mats["sidewalk"], tile_root,
            )
        # 四车道的节奏，但保留中线作为人物的视觉路径。
        for lane_y in (-2.35, 0.0, 2.35):
            dash_x = x - 5.0
            while dash_x < x + 6.0:
                journey.box(
                    f"CBD-Dash-{module}-{lane_y}-{dash_x}", (1.15, 0.08, 0.025),
                    (dash_x, lane_y, 0.10), mats["lane"], tile_root,
                )
                dash_x += 3.0

        for side_index, side in enumerate((-1, 1)):
            spec = CBD_LAYOUT[module][side_index]
            depth = spec[4] * spec[2]
            clearance = 3.0 if side < 0 else 1.4
            y = side * (road_width / 2 + sidewalk_width + depth / 2 + clearance)
            x_offset = x + (-2.2 if side < 0 else 2.0)
            name = f"{tile_root.name}-CBD-{module}-{side_index}-{spec[1]}"
            build_cbd_asset(name, spec, (x_offset, y, 0), side, tile_root)

        for side in (-1, 1):
            tree_y = side * (road_width / 2 + 1.0)
            add_street_tree(f"CBD-Tree-{module}-{side}", (x + 4.0, tree_y, 0), 0.72, tile_root, mats)
            if module % 2 == 0:
                add_lamp(f"CBD-Lamp-{module}-{side}", (x - 3.6, tree_y, 0), tile_root, mats)


def build_cbd_scene():
    variant = "cbd-landmarks"
    out_dir = os.path.join(OUT_ROOT, variant)
    os.makedirs(out_dir, exist_ok=True)
    journey.clear_scene()
    scene = bpy.context.scene
    configure_scene(scene, variant, "E8E1D5")

    mats = {
        "ground": mat("CBD-Ground", "D8D2C6"),
        "road": mat("CBD-Road", "676B6C"),
        "sidewalk": mat("CBD-Sidewalk", "C7C1B5"),
        "lane": mat("CBD-Lane", "D4C89F"),
        "trunk": mat("CBD-Trunk", "6B6258"),
        "leaf": mat("CBD-Leaf", "69796E"),
        "lamp": mat("CBD-Lamp", "3B3E3D"),
        "globe": mat("CBD-Globe", "E9D5A4", 0.42),
        "accent": mat("Accent", "B85C38"),
        "ink": mat("Ink", "2B2824"),
    }
    journey.box("CBD-Ground", (190, 130, 0.05), (0, 0, -0.055), mats["ground"])
    add_camera(scene, **SHARED_CAMERA)
    journey.add_lighting()

    root = journey.empty("MovingWorld")
    for tile in (-1, 0, 1):
        tile_root = journey.empty(f"CBD-LoopTile-{tile}", (tile * LOOP_LENGTH, 0, 0), root)
        populate_cbd_tile(tile_root, mats)
    animate_world(root)
    if WITH_TRAVELER:
        traveler = journey.add_traveler(mats)
        traveler.scale = (1.15, 1.15, 1.15)

    scene.frame_set(FRAME_START)
    blend_path = os.path.join(out_dir, f"{variant}.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    return scene, variant, blend_path


# ------------------------------------------------------------------ Forest

# 路的横向摆幅（米）。
#
# 0 = 直路。人物由 App 画在**固定的**屏幕位置上，路一摆，人就走到路肩上去了 ——
# 除非 App 也照着这条正弦走一遍。那件事做得到（视频进度 → x → y），
# 但得先把「视频 + 上层人物」这条链路跑通，所以先拉直。
# 想要弯路时把它调回 1.45，然后 App 那边照同一个公式补上横向偏移。
FOREST_CURVE = float(os.environ.get("WORLD_FOREST_CURVE", "0"))


def curve_y(x):
    return FOREST_CURVE * math.sin(math.tau * (x + 6.0) / LOOP_LENGTH)


def curve_angle(x):
    slope = FOREST_CURVE * math.tau / LOOP_LENGTH * math.cos(math.tau * (x + 6.0) / LOOP_LENGTH)
    return math.atan(slope)


def add_conifer(name, x, y, scale, parent, mats):
    trunk_h = 3.2 * scale
    journey.cylinder(f"{name}-trunk", 0.16 * scale, trunk_h, (x, y, trunk_h / 2), mats["trunk"], 10, parent)
    for index, (z, radius, depth) in enumerate(((3.0, 1.25, 2.8), (4.0, 1.02, 2.6), (5.0, 0.72, 2.2))):
        bpy.ops.mesh.primitive_cone_add(
            vertices=10, radius1=radius * scale, radius2=0.08 * scale,
            depth=depth * scale, location=(x, y, z * scale),
        )
        crown = bpy.context.object
        crown.name = f"{name}-crown-{index}"
        journey.assign_material(crown, mats["conifer"])
        crown.parent = parent


def add_deciduous(name, x, y, scale, parent, mats):
    trunk_h = 4.2 * scale
    journey.cylinder(f"{name}-trunk", 0.20 * scale, trunk_h, (x, y, trunk_h / 2), mats["trunk"], 10, parent)
    offsets = ((0.0, 0.0, 0.0, 1.25), (-0.55, 0.15, -0.15, 0.88), (0.48, -0.22, 0.10, 0.82))
    for index, (ox, oy, oz, radius) in enumerate(offsets):
        crown = journey.sphere(
            f"{name}-crown-{index}", radius * scale,
            (x + ox * scale, y + oy * scale, trunk_h + (1.0 + oz) * scale),
            mats["leaf_a"] if index == 0 else mats["leaf_b"], parent,
        )
        crown.scale.z = 1.15


SUBURB_BY_ID = {asset_id: params for asset_id, _kind, params in buildings.SUBURB_SPECS}


def add_forest_house(name, asset_id, x, y, side, parent):
    parts, _height = buildings.make_suburb_building(
        name, seed=sum(ord(c) for c in name), **dict(SUBURB_BY_ID[asset_id])
    )
    holder = journey.empty(f"{name}-Architecture", (x, y, 0), parent)
    holder.scale = (0.78, 0.78, 0.78)
    if side < 0:
        holder.rotation_euler.z = math.pi
    parent_architecture(parts, holder)


def populate_forest_tile(tile_root, mats):
    road_width = 5.6
    segment_length = 2.0
    for index in range(24):
        x = -5.0 + index * segment_length
        y = curve_y(x)
        angle = curve_angle(x)
        shoulder = journey.box(
            f"Forest-Shoulder-{index}", (segment_length * 1.10, road_width + 1.15, 0.06),
            (x, y, 0.025), mats["shoulder"], tile_root,
        )
        shoulder.rotation_euler.z = angle
        road = journey.box(
            f"Forest-Road-{index}", (segment_length * 1.12, road_width, 0.08),
            (x, y, 0.075), mats["road"], tile_root,
        )
        road.rotation_euler.z = angle
        if index % 3 == 0:
            dash = journey.box(
                f"Forest-Dash-{index}", (1.0, 0.10, 0.025),
                (x, y, 0.13), mats["lane"], tile_root,
            )
            dash.rotation_euler.z = angle

    rng = random.Random(731)
    for module in range(4):
        x0 = module * 12.0
        for side in (-1, 1):
            for tree_index in range(7):
                x = x0 - 5.2 + tree_index * 1.75 + rng.uniform(-0.55, 0.55)
                road_y = curve_y(x)
                distance = road_width / 2 + 1.6 + rng.uniform(0.0, 6.8)
                y = road_y + side * distance
                scale = rng.uniform(0.78, 1.28)
                name = f"{tile_root.name}-Tree-{module}-{side}-{tree_index}"
                if (tree_index + module + (1 if side > 0 else 0)) % 4 == 0:
                    add_conifer(name, x, y, scale, tile_root, mats)
                else:
                    add_deciduous(name, x, y, scale, tile_root, mats)

                if tree_index % 2 == 0:
                    shrub = journey.sphere(
                        f"{name}-shrub", rng.uniform(0.35, 0.62),
                        (x + rng.uniform(-0.8, 0.8), y + rng.uniform(-0.7, 0.7), 0.35),
                        mats["shrub"], tile_root,
                    )
                    shrub.scale.z = 0.72

        if module in (0, 2):
            house_side = 1 if module == 0 else -1
            hx = x0 + 2.5
            hy = curve_y(hx) + house_side * 11.8
            add_forest_house(
                f"{tile_root.name}-House-{module}",
                "sub-03" if module == 0 else "sub-01",
                hx, hy, house_side, tile_root,
            )


def animate_forest_traveler(traveler):
    traveler_x = traveler.location.x
    for index in range(17):
        t = index / 16.0
        frame = FRAME_START + round((FRAME_END + 1 - FRAME_START) * t)
        local_x = traveler_x + LOOP_LENGTH * t
        traveler.location.y = curve_y(local_x)
        traveler.rotation_euler.z = curve_angle(local_x)
        traveler.keyframe_insert(data_path="location", frame=frame, index=1)
        traveler.keyframe_insert(data_path="rotation_euler", frame=frame, index=2)
    for curve in journey.action_fcurves(traveler):
        for point in curve.keyframe_points:
            point.interpolation = "BEZIER"


def build_forest_scene():
    variant = "suburban-forest"
    out_dir = os.path.join(OUT_ROOT, variant)
    os.makedirs(out_dir, exist_ok=True)
    journey.clear_scene()
    scene = bpy.context.scene
    configure_scene(scene, variant, "E4E1D4")

    mats = {
        "ground": mat("Forest-Ground", "BFC4AA"),
        "road": mat("Forest-Road", "74756F"),
        "shoulder": mat("Forest-Shoulder", "AAA58F"),
        "lane": mat("Forest-Lane", "D0BE86"),
        "trunk": mat("Forest-Trunk", "675A4C"),
        "leaf_a": mat("Forest-Leaf-A", "657460"),
        "leaf_b": mat("Forest-Leaf-B", "7C876D"),
        "conifer": mat("Forest-Conifer", "536558"),
        "shrub": mat("Forest-Shrub", "879174"),
        "accent": mat("Accent", "B85C38"),
        "ink": mat("Ink", "2B2824"),
    }
    journey.box("Forest-Ground", (190, 130, 0.05), (0, 0, -0.055), mats["ground"])
    add_camera(scene, **SHARED_CAMERA)
    journey.add_lighting()

    root = journey.empty("MovingWorld")
    for tile in (-1, 0, 1):
        tile_root = journey.empty(f"Forest-LoopTile-{tile}", (tile * LOOP_LENGTH, 0, 0), root)
        populate_forest_tile(tile_root, mats)
    animate_world(root)
    if WITH_TRAVELER:
        animate_forest_traveler(journey.add_traveler(mats))

    scene.frame_set(FRAME_START)
    blend_path = os.path.join(out_dir, f"{variant}.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    return scene, variant, blend_path


def render_checks(scene, variant):
    out_dir = os.path.join(OUT_ROOT, variant)
    scene.render.image_settings.media_type = "IMAGE"
    scene.render.image_settings.file_format = "PNG"
    for frame in (1, 96, 192):
        scene.frame_set(frame)
        scene.render.filepath = os.path.join(out_dir, f"check-{frame:03d}.png")
        bpy.ops.render.render(write_still=True)


def render_animation(scene, variant):
    out_dir = os.path.join(OUT_ROOT, variant)
    scene.render.image_settings.media_type = "VIDEO"
    scene.render.image_settings.file_format = "FFMPEG"
    # 容器设置必须在切到 FFMPEG **之后**再设：切的时候会被恢复成默认值（MKV）。
    # 之前那版就是这么出来一个 .mkv 的 —— 文件名写着 .mp4，内容不是，
    # 而 AVFoundation 不认 MKV，在 App 里的表现是「视频加载不出来」，不报错。
    ffmpeg = scene.render.ffmpeg
    ffmpeg.format = "MPEG4"
    ffmpeg.codec = "H264"
    ffmpeg.constant_rate_factor = "HIGH"
    ffmpeg.ffmpeg_preset = "GOOD"
    # 循环要能从任意点无缝接上，关键帧密一点，seek 才不会糊一下。
    ffmpeg.gopsize = 12
    scene.render.use_file_extension = True
    scene.render.filepath = os.path.join(out_dir, f"{variant}-loop")
    bpy.ops.render.render(animation=True)

    # Blender 给视频文件名追加帧范围（`-loop0001-0288.mp4`）。改回干净的名字，
    # App 那边按 variant 名找文件。
    produced = os.path.join(out_dir, f"{variant}-loop{FRAME_START:04d}-{FRAME_END:04d}.mp4")
    final = os.path.join(out_dir, f"{variant}-loop.mp4")
    if os.path.exists(produced):
        os.replace(produced, final)
    return final


def main():
    only = os.environ.get("WORLD_ONLY")
    builders = {"cbd-landmarks": build_cbd_scene, "suburban-forest": build_forest_scene}
    chosen = [builders[only]] if only in builders else list(builders.values())
    for builder in chosen:
        scene, variant, blend_path = builder()
        if os.environ.get("WORLD_SKIP_CHECKS") != "1":
            render_checks(scene, variant)
        if os.environ.get("WORLD_RENDER_ANIMATION") == "1":
            render_animation(scene, variant)
        print(f"[world] {variant}: {blend_path}")


if __name__ == "__main__":
    main()
