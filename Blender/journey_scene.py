"""DecisionPath 整场景 3D 灰模。

这份脚本和 `greybox.py` 的职责不同：

- `greybox.py` 把单栋建筑渲成 SpriteKit 可用的 PNG。
- 本脚本验证整条街、固定相机、真实遮挡、统一光照和无缝前进循环。

默认只生成 `.blend` 和三张检查帧，速度快：

    /Applications/Blender.app/Contents/MacOS/Blender \
      --background --python Blender/journey_scene.py

确认构图后再渲染 12 秒 H.264 灰模：

    JOURNEY_RENDER_ANIMATION=1 /Applications/Blender.app/Contents/MacOS/Blender \
      --background --python Blender/journey_scene.py
"""

import math
import os
import sys
import bpy
from mathutils import Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import buildings  # noqa: E402


OUT_DIR = os.path.join(SCRIPT_DIR, "out", "journey-greybox")
BLEND_PATH = os.path.join(OUT_DIR, "journey-city.blend")
VIDEO_PATH = os.path.join(OUT_DIR, "journey-loop.mp4")

FPS = 24
LOOP_SECONDS = 12
FRAME_START = 1
FRAME_END = FPS * LOOP_SECONDS
LOOP_LENGTH = 48.0

ROAD_WIDTH = 7.2
SIDEWALK_WIDTH = 1.25
ROAD_SPEED = LOOP_LENGTH / LOOP_SECONDS

CAMERA_TILT = 34.0
CAMERA_YAW = 32.0
CAMERA_ORTHO_SCALE = 35.0
RENDER_WIDTH = 576
RENDER_HEIGHT = 1024
RENDER_SCALE = int(os.environ.get("JOURNEY_RENDER_SCALE", "100"))


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        if collection.users == 0:
            bpy.data.collections.remove(collection)


def srgb(hex_code):
    value = int(hex_code.lstrip("#"), 16)
    return (
        ((value >> 16) & 255) / 255.0,
        ((value >> 8) & 255) / 255.0,
        (value & 255) / 255.0,
        1.0,
    )


MATERIAL_COLORS = {
    "ground": srgb("E9E0CE"),
    "road": srgb("77736B"),
    "sidewalk": srgb("C8BEAA"),
    "lane": srgb("D8B46C"),
    "ink": srgb("2B2824"),
    "accent": srgb("B85C38"),
    "tree": srgb("78806D"),
    "trunk": srgb("746456"),
    "paper": srgb("F2EAD9"),
    "building-a": srgb("B6B0A4"),
    "building-b": srgb("99968F"),
    "building-c": srgb("C4B9A4"),
    "building-d": srgb("85847F"),
}


def material(name, color, roughness=0.82):
    existing = bpy.data.materials.get(name)
    if existing:
        return existing
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def assign_material(obj, mat):
    if hasattr(obj.data, "materials"):
        obj.data.materials.clear()
        obj.data.materials.append(mat)


def box(name, size, location, mat, parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    assign_material(obj, mat)
    obj.parent = parent
    return obj


def cylinder(name, radius, depth, location, mat, vertices=16, parent=None):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=depth, location=location
    )
    obj = bpy.context.object
    obj.name = name
    assign_material(obj, mat)
    obj.parent = parent
    return obj


def sphere(name, radius, location, mat, parent=None):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=radius, location=location)
    obj = bpy.context.object
    obj.name = name
    assign_material(obj, mat)
    obj.parent = parent
    return obj


def empty(name, location=(0, 0, 0), parent=None):
    obj = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    obj.parent = parent
    return obj


def action_fcurves(obj):
    """兼容 Blender 5 的 layered Action 与旧版 Action。"""
    animation = obj.animation_data
    action = animation.action if animation else None
    if action is None:
        return []
    if hasattr(action, "fcurves"):
        return list(action.fcurves)
    curves = []
    for layer in action.layers:
        for strip in layer.strips:
            for channelbag in getattr(strip, "channelbags", []):
                curves.extend(channelbag.fcurves)
    return curves


def configure_scene(scene):
    # Blender 5.2 把 Eevee 枚举名重新收敛为 BLENDER_EEVEE。
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = RENDER_WIDTH
    scene.render.resolution_y = RENDER_HEIGHT
    scene.render.resolution_percentage = max(25, min(100, RENDER_SCALE))
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.fps = FPS
    scene.frame_start = FRAME_START
    scene.frame_end = FRAME_END

    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = MATERIAL_COLORS["paper"]
    background.inputs["Strength"].default_value = 0.75

    scene.render.image_settings.color_mode = "RGB"
    scene.render.ffmpeg.format = "MPEG4"
    scene.render.ffmpeg.codec = "H264"
    scene.render.ffmpeg.constant_rate_factor = "MEDIUM"
    scene.render.ffmpeg.ffmpeg_preset = "GOOD"
    scene.render.filepath = VIDEO_PATH


def look_at(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def add_camera(scene):
    target = Vector((0.5, 0.0, 3.1))
    horizontal = 32.0
    yaw = math.radians(CAMERA_YAW)
    tilt = math.radians(CAMERA_TILT)
    camera_position = target + Vector((
        -math.cos(yaw) * math.cos(tilt) * horizontal,
        -math.sin(yaw) * math.cos(tilt) * horizontal,
        math.sin(tilt) * horizontal,
    ))

    data = bpy.data.cameras.new("JourneyCamera")
    data.type = "ORTHO"
    data.ortho_scale = CAMERA_ORTHO_SCALE
    data.lens = 50
    camera = bpy.data.objects.new("JourneyCamera", data)
    scene.collection.objects.link(camera)
    camera.location = camera_position
    look_at(camera, target)
    scene.camera = camera
    return camera


def add_lighting():
    bpy.ops.object.light_add(type="AREA", location=(-8.0, -12.0, 24.0))
    key = bpy.context.object
    key.name = "SoftKey"
    key.data.energy = 1250
    key.data.shape = "DISK"
    key.data.size = 12.0
    key.data.color = (1.0, 0.82, 0.64)
    look_at(key, (2.0, 0.0, 0.0))

    bpy.ops.object.light_add(type="SUN", location=(0, 0, 18))
    sun = bpy.context.object
    sun.name = "LongShadowSun"
    sun.data.energy = 1.4
    sun.data.angle = math.radians(7.0)
    sun.rotation_euler = (
        math.radians(31.0),
        math.radians(-22.0),
        math.radians(-38.0),
    )


def build_tree(name, location, scale, parent, mats):
    trunk_h = 1.5 * scale
    cylinder(
        f"{name}-trunk", 0.16 * scale, trunk_h,
        (location[0], location[1], trunk_h / 2), mats["trunk"],
        vertices=10, parent=parent,
    )
    crown = sphere(
        f"{name}-crown", 1.05 * scale,
        (location[0], location[1], trunk_h + 0.75 * scale), mats["tree"],
        parent=parent,
    )
    crown.scale.z = 1.15


CITY_BY_ID = {asset_id: params for asset_id, _kind, params in buildings.CITY_SPECS}
SUBURB_BY_ID = {asset_id: params for asset_id, _kind, params in buildings.SUBURB_SPECS}

# 每个路段两栋：近侧保持低矮，远侧逐渐形成城市纵深。
# 这里直接复用原版本的参数化楼房，不再另造抽象占位盒。
STREET_BUILDINGS = [
    (("city", "city-01"), ("city", "city-04")),
    (("city", "city-02"), ("city", "city-06")),
    (("suburb", "sub-03"), ("city", "city-09")),
    (("city", "city-11"), ("city", "city-10")),
]


def architecture_material(obj):
    """把旧 Workbench 资产的 object.color 转成 Eevee 材质。"""
    rgba = tuple(obj.color)
    key = "Architecture-" + "-".join(f"{channel:.3f}" for channel in rgba[:3])
    return material(key, rgba, roughness=0.88)


def build_architecture(name, asset, center_x, center_y, side, parent):
    pack, asset_id = asset
    if pack == "city":
        params = dict(CITY_BY_ID[asset_id])
        parts, height = buildings.make_city_building(
            name, seed=sum(ord(char) for char in name), **params
        )
    else:
        params = dict(SUBURB_BY_ID[asset_id])
        parts, height = buildings.make_suburb_building(
            name, seed=sum(ord(char) for char in name), **params
        )

    holder = empty(f"{name}-Architecture", (center_x, center_y, 0), parent)
    # 资产的主立面默认朝 -Y；近侧楼旋转后朝向道路。
    if side < 0:
        holder.rotation_euler.z = math.pi

    for part in parts:
        assign_material(part, architecture_material(part))
        part.parent = holder
    return holder, height, params["width"], params["depth"]


def populate_module(parent, module_index, mats):
    center_x = module_index * 12.0

    box(
        f"Road-{module_index}", (12.0, ROAD_WIDTH, 0.08),
        (center_x, 0, 0.04), mats["road"], parent,
    )
    sidewalk_y = ROAD_WIDTH / 2 + SIDEWALK_WIDTH / 2
    for side in (-1, 1):
        box(
            f"Sidewalk-{module_index}-{side}",
            (12.0, SIDEWALK_WIDTH, 0.12),
            (center_x, side * sidewalk_y, 0.06), mats["sidewalk"], parent,
        )

    dash_x = center_x - 5.0
    dash_number = 0
    while dash_x < center_x + 6.0:
        box(
            f"Dash-{module_index}-{dash_number}", (1.35, 0.13, 0.025),
            (dash_x, 0, 0.11), mats["lane"], parent,
        )
        dash_x += 3.0
        dash_number += 1

    for side_index, side in enumerate((-1, 1)):
        asset = STREET_BUILDINGS[module_index][side_index]
        name = f"{parent.name}-J{module_index}-{side_index}-{asset[1]}"
        x_offset = center_x + (-2.0 if side_index == 0 else 2.1)
        params = CITY_BY_ID[asset[1]] if asset[0] == "city" else SUBURB_BY_ID[asset[1]]
        depth = params["depth"]
        # 相机位于 -Y 一侧。近侧楼更矮、退得更远，人物和路不能被建筑立面吞掉。
        near_clearance = 3.8 if side < 0 else 0.8
        y_offset = side * (ROAD_WIDTH / 2 + SIDEWALK_WIDTH + depth / 2 + near_clearance)
        build_architecture(name, asset, x_offset, y_offset, side, parent)

    tree_side = -1 if module_index % 2 == 0 else 1
    build_tree(
        f"Tree-{module_index}",
        (center_x + 4.8, tree_side * (ROAD_WIDTH / 2 + 1.0), 0),
        0.82 + module_index * 0.07,
        parent,
        mats,
    )


def build_loop_world(mats):
    root = empty("MovingWorld")
    # 前后各复制一整圈。移动 48m 后，+48m 的副本正好接替当前圈。
    for tile in (-1, 0, 1):
        tile_root = empty(f"LoopTile-{tile}", (tile * LOOP_LENGTH, 0, 0), root)
        for module_index in range(4):
            populate_module(tile_root, module_index, mats)

    root.location.x = 0
    root.keyframe_insert(data_path="location", frame=FRAME_START)
    root.location.x = -LOOP_LENGTH
    root.keyframe_insert(data_path="location", frame=FRAME_END + 1)
    for curve in action_fcurves(root):
        for point in curve.keyframe_points:
            point.interpolation = "LINEAR"
    return root


def add_traveler(mats):
    traveler_x = -2.8
    root = empty("Traveler", (traveler_x, 0.0, 0.0))

    body = cylinder("TravelerBody", 0.22, 0.72, (0, 0, 1.05), mats["accent"], 16)
    head = sphere("TravelerHead", 0.23, (0, 0, 1.62), mats["ink"])
    body.parent = root
    head.parent = root

    for name, y, phase in (("Near", -0.12, 0), ("Far", 0.12, 6)):
        leg_pivot = empty(f"Leg{name}Pivot", (0, y, 0.78), root)
        leg = cylinder(f"Leg{name}", 0.075, 0.72, (0, 0, -0.36), mats["ink"], 12)
        leg.parent = leg_pivot
        leg.location = (0, 0, -0.36)

        arm_pivot = empty(f"Arm{name}Pivot", (0, y, 1.32), root)
        arm = cylinder(f"Arm{name}", 0.06, 0.58, (0, 0, -0.29), mats["ink"], 12)
        arm.parent = arm_pivot
        arm.location = (0, 0, -0.29)

        for frame, angle in ((1 + phase, -22), (7 + phase, 22), (13 + phase, -22)):
            leg_pivot.rotation_euler.y = math.radians(angle)
            leg_pivot.keyframe_insert(data_path="rotation_euler", frame=frame, index=1)
            arm_pivot.rotation_euler.y = math.radians(-angle * 0.72)
            arm_pivot.keyframe_insert(data_path="rotation_euler", frame=frame, index=1)
        for obj in (leg_pivot, arm_pivot):
            for curve in action_fcurves(obj):
                for point in curve.keyframe_points:
                    point.interpolation = "BEZIER"
                curve.modifiers.new(type="CYCLES")

    return root


def add_static_ground(mats):
    box("Ground", (180.0, 120.0, 0.05), (0, 0, -0.055), mats["ground"])


def build_scene():
    os.makedirs(OUT_DIR, exist_ok=True)
    clear_scene()
    scene = bpy.context.scene
    configure_scene(scene)

    mats = {key: material(key.title(), color) for key, color in MATERIAL_COLORS.items()}
    add_static_ground(mats)
    add_camera(scene)
    add_lighting()
    build_loop_world(mats)
    add_traveler(mats)

    scene.frame_set(FRAME_START)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    return scene


def render_checks(scene):
    scene.render.image_settings.file_format = "PNG"
    for frame in (1, FRAME_END // 3, FRAME_END * 2 // 3):
        scene.frame_set(frame)
        scene.render.filepath = os.path.join(OUT_DIR, f"check-{frame:03d}.png")
        bpy.ops.render.render(write_still=True)


def render_animation(scene):
    # Blender 5 将图片/视频拆成 media_type；切到 VIDEO 后 FFMPEG 才进入枚举。
    scene.render.image_settings.media_type = "VIDEO"
    scene.render.image_settings.file_format = "FFMPEG"
    scene.render.filepath = VIDEO_PATH
    bpy.ops.render.render(animation=True)


def main():
    scene = build_scene()
    if os.environ.get("JOURNEY_SKIP_CHECKS") != "1":
        render_checks(scene)
    if os.environ.get("JOURNEY_RENDER_ANIMATION") == "1":
        render_animation(scene)
    print(f"[journey] blend: {BLEND_PATH}")
    print(f"[journey] loop: {LOOP_SECONDS}s, {FPS}fps, {ROAD_SPEED:.2f}m/s")


if __name__ == "__main__":
    main()
