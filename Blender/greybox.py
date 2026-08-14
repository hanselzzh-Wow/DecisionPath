"""
第一轮 Blender 灰模：定相机，出资产。

用途只有一个 —— 把「斜俯视相机」这三个数字定死（俯角、偏航、每米像素）。
在这之前不要建任何精细模型：相机一改，所有资产作废。

跑法（不需要打开 Blender 界面）：

    blender --background --python Blender/greybox.py

输出到 Blender/out/<preset>/：
    scene.png          整体构图预览 —— 判断角度看这张，不要看单个盒子
    <asset>.png        单个资产，透明底
    SceneArt.json      每个资产的真实高度和接地点，给 SpriteKit 用

三个预设一次全渲，贴进 App 对比后选一个，然后把 PRESETS 删到只剩那一个。
"""

import json
import math
import os
import sys

import bpy
from mathutils import Vector

# 同目录 import：blender --python 不会把脚本目录加进 sys.path。
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import buildings  # noqa: E402

# ---------------------------------------------------------------- 相机预设
#
# tilt = 俯角（度）。0 = 纯侧视（看不到地面），90 = 纯俯视。
# yaw  = 偏航（度）。0 = 正对建筑正面，45 = 正对建筑的角。
#
# 北极星写了「不再采用静态等距建筑」，所以 45/45 那组（经典等距）
# 大概率不是答案 —— 但还是渲出来，因为要有个上界来对比。

ALL_PRESETS = [
    {"name": "a-shallow", "tilt": 22.0, "yaw": 20.0},
    {"name": "b-middle", "tilt": 32.0, "yaw": 30.0},
    {"name": "c-isometric", "tilt": 45.0, "yaw": 45.0},
]

# 迭代几何的时候只渲一个角度 —— 三个角度是 3 倍时间，而相机这轮不动。
# 要回头比角度：GREYBOX_PRESETS=all（或写 a-shallow,c-isometric）
_WANTED = os.environ.get("GREYBOX_PRESETS", "b-middle")
PRESETS = (ALL_PRESETS if _WANTED == "all"
           else [p for p in ALL_PRESETS if p["name"] in _WANTED.split(",")])

# ---------------------------------------------------------------- 尺度
#
# App 里 Tuning.travelerHeight = 70pt，人设定为 1.7m。
# 按 @3x 出图：70 / 1.7 * 3 ≈ 123.5 px/m。
# 这个数改了，所有资产的相对大小会跟着变，App 那边 pointsPerMeter 也要同步。

FIGURE_HEIGHT_M = 1.7
POINTS_PER_METER = 70.0 / FIGURE_HEIGHT_M
PIXELS_PER_METER = POINTS_PER_METER * 3.0

FRAME_MARGIN = 0.08          # 资产四周留白比例
CAMERA_DISTANCE = 200.0      # 正交相机推多远无所谓，只要在物体之外
# 屏幕最高 874pt，@3x = 2622px。渲得比这大纯属浪费 ——
# 第一版渲到 8192，资产目录 294MB。同时也避开 GPU 的纹理上限。
MAX_RENDER_PX = 2600

OUT_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")


# ---------------------------------------------------------------- 场景准备

def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.cameras, bpy.data.objects):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def configure_render(scene):
    """Workbench：灰模阶段不需要材质，也不该有材质。

    刻意关掉阴影和空腔 —— 接触影由 SpriteKit 画，烘进贴图之后就没法
    按层调浓淡了。物体描边开着，因为墨线是这套视觉的一部分。
    """
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"

    shading = scene.display.shading
    shading.light = "STUDIO"
    # OBJECT：每个物件用自己的 obj.color。表面不用贴图，靠色阶分构件。
    shading.color_type = "OBJECT"
    shading.show_shadows = False
    shading.show_cavity = False
    try:
        shading.show_object_outline = True
        shading.object_outline_color = (0.10, 0.09, 0.08)
    except AttributeError:
        pass
    try:
        scene.display.render_aa = "16"
    except (AttributeError, TypeError):
        pass


def make_camera(scene, tilt_deg, yaw_deg):
    camera_data = bpy.data.cameras.new("GreyboxCam")
    camera_data.type = "ORTHO"
    camera_data.clip_start = 0.1
    camera_data.clip_end = CAMERA_DISTANCE * 3
    camera = bpy.data.objects.new("GreyboxCam", camera_data)
    scene.collection.objects.link(camera)
    # tilt=0 → 相机水平看（侧视）；tilt=90 → 垂直向下看。
    camera.rotation_euler = (math.radians(90.0 - tilt_deg), 0.0, math.radians(yaw_deg))
    scene.camera = camera
    return camera


# ---------------------------------------------------------------- 灰模物件
#
# 全部以「底面中心在原点」建模。接地点的计算依赖这个约定。

def _new_box(name, size, location):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (size[0], size[1], size[2])
    return obj


def _new_cylinder(name, radius, depth, location, vertices=24):
    bpy.ops.mesh.primitive_cylinder_add(
        radius=radius, depth=depth, location=location, vertices=vertices
    )
    obj = bpy.context.object
    obj.name = name
    return obj


def _new_sphere(name, radius, location, segments=24):
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=radius, location=location, segments=segments, ring_count=segments // 2
    )
    obj = bpy.context.object
    obj.name = name
    return obj


def build_building(name, width, depth, height, gable=0.0):
    """一栋楼。gable > 0 时加一个人字屋顶（高度是 gable 米）。

    参数化就是这里 —— 要二十栋不重样的楼，不是建二十次模型，
    是把 width/depth/height/gable 换二十组数。
    """
    parts = [_new_box(f"{name}-body", (width, depth, height), (0, 0, height / 2))]
    if gable > 0:
        bpy.ops.mesh.primitive_cone_add(
            vertices=4,
            radius1=math.hypot(width, depth) / 2 * 1.02,
            depth=gable,
            location=(0, 0, height + gable / 2),
        )
        roof = bpy.context.object
        roof.name = f"{name}-roof"
        roof.rotation_euler = (0, 0, math.radians(45))
        parts.append(roof)
    return parts, height + gable


def _paint(objs, amount, hue=None):
    """amount：0 = 纸白，1 = 全墨。hue 给定时在该色相上压明度。"""
    for obj in objs:
        if hue is None:
            obj.color = buildings.tone(amount)
        else:
            obj.color = buildings._linear(buildings._mix(hue, buildings._INK, amount))
    return objs


FOLIAGE = (0.573, 0.631, 0.525)
PAVING = (0.796, 0.776, 0.733)


def build_tree(name, height, canopy_ratio=0.62):
    trunk_h = height * (1.0 - canopy_ratio)
    canopy_r = height * canopy_ratio / 2
    trunk = _new_cylinder(f"{name}-trunk", height * 0.045, trunk_h, (0, 0, trunk_h / 2))
    canopy = _new_sphere(f"{name}-canopy", canopy_r, (0, 0, trunk_h + canopy_r * 0.9))
    _paint([trunk], 0.42, hue=(0.573, 0.525, 0.475))
    _paint([canopy], 0.16, hue=FOLIAGE)
    return [trunk, canopy], height


def build_pole(name, height):
    post = _new_cylinder(f"{name}-post", 0.05, height, (0, 0, height / 2), vertices=12)
    head = _new_sphere(f"{name}-head", 0.16, (0, 0, height), segments=16)
    return _paint([post, head], 0.40, hue=PAVING), height + 0.16


def build_sign(name, height):
    post = _new_box(f"{name}-post", (0.10, 0.10, height), (0, 0, height / 2))
    board = _new_box(f"{name}-board", (0.90, 0.08, 0.50), (0, 0, height * 0.92))
    _paint([post], 0.40, hue=PAVING)
    _paint([board], 0.22)
    return [post, board], height * 0.92 + 0.25


def build_figure(name, height=FIGURE_HEIGHT_M):
    """胶囊小人。只用来判断尺度，不做姿态。

    总高必须精确等于 height —— 这个小人是整个世界的尺子，它不准，
    所有资产的相对大小就都不准。
    """
    head_r = height * 0.115
    body_h = height - head_r * 1.95
    body = _new_cylinder(f"{name}-body", height * 0.11, body_h, (0, 0, body_h / 2), vertices=16)
    head = _new_sphere(f"{name}-head", head_r, (0, 0, body_h + head_r * 0.95), segments=16)
    return _paint([body, head], 0.80), height


def build_fork_road(name, half_width=3.9, trunk=48.0, transition=36.0,
                    tine=44.0, separation=18.0, samples=20):
    """音叉形岔路：主路进来，两条岔路弯开之后**平行**往前走。

    和 Y 字型的区别是关键的 —— Y 字型两条路越走越远，最后各自消失在一个方向；
    音叉型分开之后并排前进，你选的那条和你没选的那条一直在彼此旁边。
    这才是「未选择的路」：它没有消失，它只是没被走。

    做成单个 mesh 而不是多个物体：Workbench 的描边按物体轮廓画，拆开会在
    接缝处画出多余的线。
    """
    verts, faces = [], []

    def quad(p0, p1, p2, p3):
        base = len(verts)
        verts.extend([p0, p1, p2, p3])
        faces.append((base, base + 1, base + 2, base + 3))

    def strip(points):
        for i in range(len(points) - 1):
            (x0, y0), (x1, y1) = points[i], points[i + 1]
            dx, dy = x1 - x0, y1 - y0
            length = math.hypot(dx, dy) or 1.0
            nx = -dy / length * half_width
            ny = dx / length * half_width
            quad((x0 + nx, y0 + ny, 0), (x1 + nx, y1 + ny, 0),
                 (x1 - nx, y1 - ny, 0), (x0 - nx, y0 - ny, 0))

    # 主干
    quad((-trunk, half_width, 0), (0.0, half_width, 0),
         (0.0, -half_width, 0), (-trunk, -half_width, 0))

    for side in (1, -1):
        points = []
        for i in range(samples + 1):
            t = i / samples
            # smoothstep：弯开的过程要柔，硬折角看着像画错了
            points.append((t * transition, side * separation * t * t * (3.0 - 2.0 * t)))
        points.append((transition + tine, side * separation))
        strip(points)

    obj = buildings.new_mesh(f"{name}-fork", verts, faces, (0, 0, 0.03))
    return _paint([obj], 0.04, hue=PAVING), 0.06


def build_road(name, width=6.0, length=60.0):
    return _paint([_new_box(f"{name}-slab", (length, width, 0.06), (0, 0, 0.03))], 0.04, hue=PAVING), 0.06


# ---------------------------------------------------------------- 取景与渲染

def _camera_basis(camera):
    rotation = camera.matrix_world.to_3x3()
    right = rotation @ Vector((1.0, 0.0, 0.0))
    up = rotation @ Vector((0.0, 1.0, 0.0))
    forward = rotation @ Vector((0.0, 0.0, -1.0))
    return right, up, forward


def frame_points(scene, camera, corners, margin=FRAME_MARGIN):
    """把相机对准这组世界坐标点，并按 PIXELS_PER_METER 定分辨率。

    相机方向不变 —— 只平移和改 ortho_scale。所以每个资产都来自同一台相机，
    这正是这条管线相对手画的全部价值。
    """
    right, up, forward = _camera_basis(camera)

    us = [corner.dot(right) for corner in corners]
    vs = [corner.dot(up) for corner in corners]
    ws = [corner.dot(forward) for corner in corners]

    width = (max(us) - min(us)) * (1.0 + 2.0 * margin)
    height = (max(vs) - min(vs)) * (1.0 + 2.0 * margin)
    width = max(width, 0.05)
    height = max(height, 0.05)

    center_u = (max(us) + min(us)) / 2.0
    center_v = (max(vs) + min(vs)) / 2.0

    camera.location = (
        right * center_u + up * center_v + forward * (min(ws) - CAMERA_DISTANCE)
    )
    # ortho_scale 对应分辨率较大的那一边，所以两者必须一起设，像素/米才恒定。
    camera.data.ortho_scale = max(width, height)

    # 超大资产降采样。降完之后这张图的像素/米就不是全局那个值了，所以要
    # 逐资产记进 manifest —— App 靠它把像素换算回真实尺寸，而不是假设全局一致。
    ppm = PIXELS_PER_METER
    longest = max(width, height) * ppm
    if longest > MAX_RENDER_PX:
        ppm *= MAX_RENDER_PX / longest

    scene.render.resolution_x = max(int(round(width * ppm)), 4)
    scene.render.resolution_y = max(int(round(height * ppm)), 4)
    scene.render.resolution_percentage = 100
    return width, height, ppm


def frame_objects(scene, camera, objects, margin=FRAME_MARGIN):
    # matrix_world 是惰性求值的：改完 location/scale 不 update，拿到的还是旧矩阵，
    # 框出来就是缩放前的单位盒。第一版就栽在这里。
    bpy.context.view_layer.update()
    corners = []
    for obj in objects:
        matrix = obj.matrix_world
        corners.extend(matrix @ Vector(corner) for corner in obj.bound_box)
    return frame_points(scene, camera, corners, margin=margin)


# 整体预览固定框住这块世界区域，三个预设才可比 —— 自动取景会让每个预设
# 框住不同大小的地方，那样对比的是取景，不是相机角度。
# 每个场景包一个取景框：CBD 的塔楼七十米高，用老城那个框会被裁掉一半。
PREVIEW_REGIONS = {
    "cbd": {"x": (-78.0, 78.0), "y": (-34.0, 34.0), "z": (0.0, 86.0)},
    "oldtown": {"x": (-52.0, 52.0), "y": (-24.0, 24.0), "z": (0.0, 30.0)},
    "suburb": {"x": (-42.0, 42.0), "y": (-22.0, 22.0), "z": (0.0, 18.0)},
}


def preview_corners(pack):
    region = PREVIEW_REGIONS[pack]
    xs, ys, zs = region["x"], region["y"], region["z"]
    return [
        Vector((x, y, z))
        for x in xs
        for y in ys
        for z in zs
    ]


def ground_anchor(scene, camera, width, height):
    """世界原点（= 资产的接地点）在图像里的归一化位置。

    SKSpriteNode.anchorPoint 用的是同一套坐标（左下 0,0），所以这个数
    直接填进去，物体就会稳稳站在它被放置的那个点上。
    """
    right, up, forward = _camera_basis(camera)
    offset = Vector((0.0, 0.0, 0.0)) - camera.location
    u = offset.dot(right)
    v = offset.dot(up)
    return (u / width + 0.5, v / height + 0.5)


def set_visible(all_objects, visible_objects):
    visible = set(obj.name for obj in visible_objects)
    for obj in all_objects:
        obj.hide_render = obj.name not in visible


def render_to(scene, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


# ---------------------------------------------------------------- 主流程

# 接触影相对贴图宽度的比例。树冠比树干宽得多，路灯杆更是细得离谱 ——
# 按图宽画影子会明显不对。影子由 SpriteKit 画，不烘进贴图。
SHADOW_FACTORS = {"tree": 0.5, "lamp": 0.12, "signpost": 0.3, "figure": 0.45}


def shadow_factor(asset_id):
    for prefix, value in SHADOW_FACTORS.items():
        if asset_id.startswith(prefix):
            return value
    return 1.0


def build_asset_library():
    """返回 [(资产 id, kind, 物件列表, 真实高度米)]。

    建筑来自 buildings.BUILDING_SPECS —— 加楼改那张表，不改这里。
    """
    library = []

    for asset_id, pack, kind, parts, height in buildings.build_all_buildings():
        library.append((asset_id, pack, kind, parts, height))

    for name, height in (("tree-a", 5.5), ("tree-b", 3.2), ("tree-c", 7.4)):
        parts, total = build_tree(name, height)
        library.append((name, "common", "tree", parts, total))

    parts, total = build_pole("lamp", 4.2)
    library.append(("lamp", "common", "prop", parts, total))

    parts, total = build_sign("signpost", 2.1)
    library.append(("signpost", "common", "prop", parts, total))

    parts, total = build_figure("figure")
    library.append(("figure", "common", "figure", parts, total))

    parts, total = build_fork_road("road-fork")
    library.append(("road-fork", "common", "road", parts, total))

    return library


def layout_preview(library, pack):
    """把一个场景包的建筑摆在岔路两侧。

    每个包单出一张 —— 它们是三个不同的地方，放一起比没有意义。
    """
    fork_parts, _ = build_fork_road("preview-road")
    picked = [item for item in library if item[1] == pack]

    placements = {}
    far, near = -40.0, -34.0
    for index, (asset_id, _pack, _kind, parts, height) in enumerate(picked):
        gap = 15.0 + height * 0.55
        if index % 2 == 0:
            placements[asset_id] = (far, 15.0)
            far += gap
        else:
            placements[asset_id] = (near, -16.0)
            near += gap

    for extra, spot in (("tree-a", (-10.0, -8.0)), ("tree-b", (14.0, -7.6)),
                        ("tree-c", (-26.0, -8.2)), ("lamp", (-4.0, 6.0)),
                        ("signpost", (12.0, 7.4)), ("figure", (-6.0, 0.0))):
        placements[extra] = spot

    moved = list(fork_parts)
    for asset_id, _pack, _kind, parts, _height in library:
        if asset_id not in placements:
            continue
        x, y = placements[asset_id]
        for part in parts:
            part.location = (part.location.x + x, part.location.y + y, part.location.z)
        moved.extend(parts)
    return moved, placements


def restore_layout(library, placements):
    for asset_id, _pack, _kind, parts, _height in library:
        if asset_id not in placements:
            continue
        x, y = placements[asset_id]
        for part in parts:
            part.location = (part.location.x - x, part.location.y - y, part.location.z)


def run_preset(preset):
    scene = bpy.context.scene
    clear_scene()
    configure_render(scene)
    camera = make_camera(scene, preset["tilt"], preset["yaw"])

    library = build_asset_library()
    all_objects = [part for _id, _pack, _kind, parts, _h in library for part in parts]

    out_dir = os.path.join(OUT_ROOT, preset["name"])

    # 每个场景包一张整体预览 —— 判断角度和密度看这些，不要看单栋楼。
    for pack in buildings.PACKS:
        preview_objects, placements = layout_preview(library, pack)
        all_objects = list({obj.name: obj for obj in all_objects + preview_objects}.values())
        set_visible(all_objects, preview_objects)
        bpy.context.view_layer.update()
        frame_points(scene, camera, preview_corners(pack), margin=0.02)
        render_to(scene, os.path.join(out_dir, f"scene-{pack}.png"))
        restore_layout(library, placements)

    # 再逐个出资产。
    manifest = []
    for asset_id, pack, kind, parts, world_height in library:
        set_visible(all_objects, parts)
        width, height, ppm = frame_objects(scene, camera, parts)
        anchor = ground_anchor(scene, camera, width, height)
        render_to(scene, os.path.join(out_dir, f"{asset_id}.png"))
        manifest.append(
            {
                "id": asset_id,
                "pack": pack,
                "kind": kind,
                "worldHeight": round(world_height, 4),
                # 这张图自己的像素/米。超大资产会被降采样，所以不能假设全局一致。
                "pixelsPerMeter": round(ppm, 4),
                "anchor": [round(anchor[0], 5), round(anchor[1], 5)],
                "pixelSize": [scene.render.resolution_x, scene.render.resolution_y],
                "shadowWidthFactor": shadow_factor(asset_id),
            }
        )

    payload = {
        "camera": {
            "tilt": preset["tilt"],
            "yaw": preset["yaw"],
            "projection": "orthographic",
            "pixelsPerMeter": round(PIXELS_PER_METER, 4),
            "pointsPerMeter": round(POINTS_PER_METER, 4),
            "figureHeightMeters": FIGURE_HEIGHT_M,
        },
        "assets": manifest,
    }
    with open(os.path.join(out_dir, "SceneArt.json"), "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)

    print(f"[greybox] {preset['name']}: {len(manifest)} assets -> {out_dir}")


def main():
    for preset in PRESETS:
        run_preset(preset)
    print(f"[greybox] done. compare the three scene.png under {OUT_ROOT}")


if __name__ == "__main__":
    main()
