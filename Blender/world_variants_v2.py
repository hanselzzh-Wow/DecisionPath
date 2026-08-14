"""第二版环境：真实街区 CBD +《未选择的路》黄色岔路林。

CBD 不再把同类塔楼沿路排满，而是按街区、裙房、退界、广场和地标组织。
黄色树林使用音叉形道路：两条路分开后并排向前，未选择的路不会消失。
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
import world_variants as base  # noqa: E402


OUT_ROOT = os.path.join(SCRIPT_DIR, "out")
TREE_ASSET_DIR = os.path.join(
    SCRIPT_DIR, "vendor", "quaternius", "nature-megakit-standard", "glTF"
)
TREE_ASSET_FILES = tuple(
    [f"CommonTree_{index}.gltf" for index in range(1, 6)]
    + [f"TwistedTree_{index}.gltf" for index in range(1, 4)]
)
FRAME_START = 1
FRAME_END = 288
LOOP_LENGTH = 48.0
RENDER_SCALE = int(os.environ.get("WORLD_RENDER_SCALE", "50"))


def mat(name, color, roughness=0.86):
    return journey.material(name, journey.srgb(color), roughness)


def setup_scene(variant, background):
    out_dir = os.path.join(OUT_ROOT, variant)
    os.makedirs(out_dir, exist_ok=True)
    journey.clear_scene()
    scene = bpy.context.scene
    base.configure_scene(scene, variant, background)
    scene.render.resolution_percentage = max(25, min(100, RENDER_SCALE))
    return scene, out_dir


def add_vertical_fins(name, holder, width, depth, base_z, height, fin_mat, count=7):
    for face in (-1, 1):
        y = face * (depth / 2 + 0.07)
        for index in range(count):
            x = -width / 2 + (index + 0.5) * width / count
            journey.box(
                f"{name}-fin-y-{face}-{index}",
                (0.10, 0.14, height * 0.96), (x, y, base_z + height / 2), fin_mat, holder,
            )
    side_count = max(3, int(count * depth / max(width, 0.1)))
    for face in (-1, 1):
        x = face * (width / 2 + 0.07)
        for index in range(side_count):
            y = -depth / 2 + (index + 0.5) * depth / side_count
            journey.box(
                f"{name}-fin-x-{face}-{index}",
                (0.14, 0.10, height * 0.96), (x, y, base_z + height / 2), fin_mat, holder,
            )


def add_tower(
    name, location, size, parent, mats, *, style="vertical", podium=(4.0, 3.0),
    rotation=0.0, palette=None,
):
    tower_mats = dict(mats)
    if palette:
        tower_mats.update(palette)
    width, depth, height = size
    holder = journey.empty(f"{name}-Architecture", location, parent)
    holder.rotation_euler.z = rotation
    podium_h, podium_extra = podium
    journey.box(
        f"{name}-podium", (width + podium_extra, depth + podium_extra, podium_h),
        (0, 0, podium_h / 2), tower_mats["stone"], holder,
    )
    journey.box(
        f"{name}-podium-glass", (width + podium_extra - 0.6, depth + podium_extra + 0.10, podium_h * 0.52),
        (0, -0.02, podium_h * 0.38), tower_mats["dark_glass"], holder,
    )

    base_z = podium_h
    if style == "setback":
        lower_h = height * 0.62
        journey.box(f"{name}-shaft-a", (width, depth, lower_h), (0, 0, base_z + lower_h / 2), tower_mats["glass_a"], holder)
        add_vertical_fins(name + "-a", holder, width, depth, base_z, lower_h, tower_mats["fin"], 7)
        upper_w, upper_d = width * 0.72, depth * 0.74
        upper_h = height - lower_h
        journey.box(
            f"{name}-shaft-b", (upper_w, upper_d, upper_h),
            (width * 0.10, 0, base_z + lower_h + upper_h / 2), tower_mats["glass_b"], holder,
        )
        add_vertical_fins(
            name + "-b", holder, upper_w, upper_d, base_z + lower_h, upper_h, tower_mats["fin_light"], 5
        )
        crown_z = base_z + height
    elif style == "frame":
        journey.box(f"{name}-shaft", (width, depth, height), (0, 0, base_z + height / 2), tower_mats["glass_b"], holder)
        frame_t = 0.48
        for y in (-depth / 2 - 0.08, depth / 2 + 0.08):
            journey.box(f"{name}-frame-left-{y}", (frame_t, 0.16, height), (-width / 2, y, base_z + height / 2), tower_mats["stone"], holder)
            journey.box(f"{name}-frame-right-{y}", (frame_t, 0.16, height), (width / 2, y, base_z + height / 2), tower_mats["stone"], holder)
            journey.box(f"{name}-frame-top-{y}", (width, 0.16, frame_t), (0, y, base_z + height - frame_t / 2), tower_mats["stone"], holder)
        crown_z = base_z + height
    else:
        journey.box(f"{name}-shaft", (width, depth, height), (0, 0, base_z + height / 2), tower_mats["glass_a"], holder)
        add_vertical_fins(name, holder, width, depth, base_z, height, tower_mats["fin"], 8)
        crown_z = base_z + height

    journey.box(
        f"{name}-crown", (width * 0.46, depth * 0.42, 2.0),
        (width * 0.08, 0, crown_z + 1.0), tower_mats["mechanical"], holder,
    )
    return holder


def add_twist_landmark(name, location, parent, mats, scale=0.50):
    parts, _ = buildings.make_landmark_twist(
        name, width=15.0, depth=15.0, floors=24, twist_deg=78.0,
        seed=sum(ord(c) for c in name),
    )
    holder = journey.empty(f"{name}-Architecture", location, parent)
    holder.scale = (scale, scale, scale)
    for part in parts:
        # 让地标保留冷灰玻璃，不继承旧版横条楼的随机暖色。
        is_slab = "spandrel" in part.name or "spire" in part.name
        journey.assign_material(part, mats["fin_light"] if is_slab else mats["landmark_glass"])
        part.parent = holder
    return holder


def add_cbd_tree(name, location, parent, mats, scale=0.72):
    journey.cylinder(
        f"{name}-trunk", 0.13 * scale, 1.8 * scale,
        (location[0], location[1], 0.9 * scale), mats["tree_trunk"], 10, parent,
    )
    crown = journey.sphere(
        f"{name}-crown", 0.85 * scale,
        (location[0], location[1], 2.35 * scale), mats["tree"], parent,
    )
    crown.scale.z = 1.18


def add_crosswalk(name, x, road_width, parent, mats):
    for side in (-1, 1):
        for index in range(6):
            y = side * (0.65 + index * 0.72)
            journey.box(
                f"{name}-{side}-{index}", (0.42, 0.48, 0.025),
                (x, y, 0.12), mats["crosswalk"], parent,
            )


def populate_real_cbd_tile(tile_root, mats):
    road_width = 9.6
    sidewalk = 2.1
    for module in range(4):
        x = module * 12.0
        journey.box(f"CBD2-Road-{module}", (12.1, road_width, 0.08), (x, 0, 0.04), mats["road"], tile_root)
        for side in (-1, 1):
            journey.box(
                f"CBD2-Sidewalk-{module}-{side}", (12.1, sidewalk, 0.14),
                (x, side * (road_width / 2 + sidewalk / 2), 0.07), mats["sidewalk"], tile_root,
            )
        for lane_y in (-2.2, 0.0, 2.2):
            for dash in (-4.5, -1.5, 1.5, 4.5):
                journey.box(
                    f"CBD2-Dash-{module}-{lane_y}-{dash}", (1.1, 0.07, 0.025),
                    (x + dash, lane_y, 0.10), mats["lane"], tile_root,
                )

    # 真正的街区交叉口，避免所有建筑只沿一条展示轴排开。
    intersection_x = 13.0
    journey.box("CBD2-Cross-Road", (7.0, 48.0, 0.085), (intersection_x, 0, 0.045), mats["road"], tile_root)
    add_crosswalk("CBD2-Crosswalk", intersection_x - 4.0, road_width, tile_root, mats)
    add_crosswalk("CBD2-Crosswalk", intersection_x + 4.0, road_width, tile_root, mats)

    # 一侧留出城市广场和绿地，让地标拥有呼吸空间。
    journey.box("CBD2-Plaza", (13.0, 10.0, 0.10), (19.5, 11.2, 0.06), mats["plaza"], tile_root)
    journey.box("CBD2-Plaza-Green", (5.2, 4.6, 0.12), (18.0, 11.4, 0.12), mats["green"], tile_root)
    for index, point in enumerate(((15.5, 8.7), (20.5, 9.0), (16.2, 14.0), (21.3, 13.7))):
        add_cbd_tree(f"CBD2-Plaza-Tree-{index}", point, tile_root, mats, 0.82)

    # 三层纵深：近侧低、路边中层、远侧才出现高塔。
    warm = {"glass_a": mats["glass_warm"], "glass_b": mats["glass_warm_dark"],
            "dark_glass": mats["dark_warm"], "stone": mats["stone_warm"],
            "fin": mats["fin_warm"], "fin_light": mats["fin_warm_light"]}
    teal = {"glass_a": mats["glass_teal"], "glass_b": mats["glass_teal_dark"],
            "dark_glass": mats["dark_teal"], "stone": mats["stone_teal"],
            "fin": mats["fin_teal"], "fin_light": mats["fin_teal_light"]}
    silver = {"glass_a": mats["glass_silver"], "glass_b": mats["glass_silver_dark"],
              "dark_glass": mats["dark_silver"], "stone": mats["stone_silver"],
              "fin": mats["fin_silver"], "fin_light": mats["fin_silver_light"]}

    add_tower("CBD2-Near-A", (-1.5, -17.0, 0), (13.5, 10.5, 11.0), tile_root, mats,
              style="frame", podium=(3.8, 3.5), palette=warm)
    add_tower("CBD2-Far-A", (2.5, 17.8, 0), (11.0, 10.0, 38.0), tile_root, mats,
              style="setback", podium=(5.0, 4.5), rotation=math.radians(-4))
    add_tower("CBD2-Near-B", (28.5, -17.5, 0), (10.5, 9.5, 15.0), tile_root, mats,
              style="vertical", podium=(4.2, 4.0), rotation=math.radians(3), palette=teal)
    add_tower("CBD2-Mid-B", (41.0, -15.5, 0), (16.0, 11.5, 9.0), tile_root, mats,
              style="frame", podium=(3.8, 5.0), rotation=math.radians(-2), palette=warm)
    add_tower("CBD2-Far-B", (38.5, 19.5, 0), (12.0, 10.0, 42.0), tile_root, mats,
              style="setback", podium=(5.2, 4.5), palette=silver)
    add_twist_landmark("CBD2-Landmark", (21.0, 22.5, 0), tile_root, mats, 0.53)

    # 连续街道绿化，但保留路口视线。
    for module in (0, 2, 3):
        x = module * 12.0 + 4.0
        for side in (-1, 1):
            add_cbd_tree(
                f"CBD2-StreetTree-{module}-{side}",
                (x, side * (road_width / 2 + 1.05), 0), tile_root, mats, 0.66,
            )


def build_real_cbd():
    variant = "cbd-urban-blocks"
    scene, out_dir = setup_scene(variant, "E7E3DA")
    mats = {
        "ground": mat("CBD2-Ground", "D4D1C9"),
        "road": mat("CBD2-Road", "666B6D"),
        "sidewalk": mat("CBD2-Sidewalk", "C8C4BA"),
        "lane": mat("CBD2-Lane", "D4CCAE"),
        "crosswalk": mat("CBD2-Crosswalk", "DCD9CF"),
        "plaza": mat("CBD2-Plaza", "B9B3A8"),
        "green": mat("CBD2-Green", "849080"),
        "glass_a": mat("CBD2-Glass-A", "2D5870", 0.34),
        "glass_b": mat("CBD2-Glass-B", "476F7D", 0.36),
        "dark_glass": mat("CBD2-Dark-Glass", "203F4D", 0.30),
        "landmark_glass": mat("CBD2-Landmark-Glass", "25758A", 0.28),
        "stone": mat("CBD2-Stone", "A9A49A"),
        "fin": mat("CBD2-Fin", "D0C8B9"),
        "fin_light": mat("CBD2-Fin-Light", "B8CEC9"),
        "mechanical": mat("CBD2-Mechanical", "656965"),
        # 建筑各用一组低饱和材质；差异来自色温，不靠高饱和彩色玻璃。
        "glass_warm": mat("CBD2-Glass-Warm", "8A4F3F", 0.38),
        "glass_warm_dark": mat("CBD2-Glass-Warm-Dark", "663B35", 0.38),
        "dark_warm": mat("CBD2-Dark-Warm", "442C2B", 0.32),
        "stone_warm": mat("CBD2-Stone-Warm", "C39168"),
        "fin_warm": mat("CBD2-Fin-Warm", "D5A979"),
        "fin_warm_light": mat("CBD2-Fin-Warm-Light", "E4C49D"),
        "glass_teal": mat("CBD2-Glass-Teal", "26757A", 0.34),
        "glass_teal_dark": mat("CBD2-Glass-Teal-Dark", "1F5B62", 0.34),
        "dark_teal": mat("CBD2-Dark-Teal", "173F47", 0.30),
        "stone_teal": mat("CBD2-Stone-Teal", "74A19B"),
        "fin_teal": mat("CBD2-Fin-Teal", "90BBB1"),
        "fin_teal_light": mat("CBD2-Fin-Teal-Light", "B6D0C6"),
        "glass_silver": mat("CBD2-Glass-Silver", "686D8A", 0.36),
        "glass_silver_dark": mat("CBD2-Glass-Silver-Dark", "505673", 0.36),
        "dark_silver": mat("CBD2-Dark-Silver", "393D59", 0.32),
        "stone_silver": mat("CBD2-Stone-Silver", "AAA6B6"),
        "fin_silver": mat("CBD2-Fin-Silver", "C1BED1"),
        "fin_silver_light": mat("CBD2-Fin-Silver-Light", "D5D2E0"),
        "tree": mat("CBD2-Tree", "647467"),
        "tree_trunk": mat("CBD2-Tree-Trunk", "655C52"),
        "accent": mat("Accent", "B85C38"),
        "ink": mat("Ink", "2B2824"),
    }
    journey.box("CBD2-Ground", (190, 140, 0.05), (0, 0, -0.055), mats["ground"])
    base.add_camera(scene, **base.SHARED_CAMERA)
    journey.add_lighting()
    # CBD 需要清楚的材质色差；降低无方向环境光，避免所有立面被洗成灰白。
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.42
    bpy.data.objects["SoftKey"].data.energy = 980
    bpy.data.objects["LongShadowSun"].data.energy = 1.15
    root = journey.empty("MovingWorld")
    for tile in (-1, 0, 1):
        tile_root = journey.empty(f"CBD2-LoopTile-{tile}", (tile * LOOP_LENGTH, 0, 0), root)
        populate_real_cbd_tile(tile_root, mats)
    base.animate_world(root)
    if base.WITH_TRAVELER:
        traveler = journey.add_traveler(mats)
        traveler.scale = (1.12, 1.12, 1.12)
    scene.frame_set(FRAME_START)
    blend_path = os.path.join(out_dir, f"{variant}.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    return scene, variant, blend_path


# ----------------------------------------------------------- Yellow fork

def smoothstep(t):
    return t * t * (3.0 - 2.0 * t)


FORK_SEPARATION = 9.5
ROAD_HALF_WIDTH = 3.25


def strip_mesh(name, points, half_width, z, material, parent):
    verts, faces = [], []
    for index in range(len(points) - 1):
        x0, y0 = points[index]
        x1, y1 = points[index + 1]
        dx, dy = x1 - x0, y1 - y0
        length = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / length * half_width, dx / length * half_width
        base_index = len(verts)
        verts.extend(((x0 + nx, y0 + ny, z), (x1 + nx, y1 + ny, z),
                      (x1 - nx, y1 - ny, z), (x0 - nx, y0 - ny, z)))
        faces.append((base_index, base_index + 1, base_index + 2, base_index + 3))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    journey.assign_material(obj, material)
    obj.parent = parent
    return obj


def point_segment_distance(x, y, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    denom = dx * dx + dy * dy
    if denom == 0:
        return math.hypot(x - ax, y - ay)
    t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / denom))
    px, py = ax + t * dx, ay + t * dy
    return math.hypot(x - px, y - py)


def road_distance(x, y):
    """到正交音叉三段中心线的最近距离。"""
    segments = [
        (-42.0, 0.0, 0.0, 0.0),
        (0.0, -FORK_SEPARATION, 0.0, FORK_SEPARATION),
        (0.0, -FORK_SEPARATION, 56.0, -FORK_SEPARATION),
        (0.0, FORK_SEPARATION, 56.0, FORK_SEPARATION),
    ]
    return min(point_segment_distance(x, y, *segment) for segment in segments)


def cylinder_between(name, start, end, radius, material, parent, vertices=9):
    start_v, end_v = Vector(start), Vector(end)
    direction = end_v - start_v
    midpoint = (start_v + end_v) * 0.5
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=direction.length, location=midpoint
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    journey.assign_material(obj, material)
    obj.parent = parent
    return obj


def add_yellow_tree(name, x, y, scale, parent, mats, color_index):
    rng = random.Random(sum(ord(char) for char in name))
    trunk_h = rng.uniform(4.4, 5.5) * scale
    bpy.ops.mesh.primitive_cone_add(
        vertices=10, radius1=0.25 * scale, radius2=0.12 * scale,
        depth=trunk_h, location=(x, y, trunk_h / 2),
    )
    trunk = bpy.context.object
    trunk.name = f"{name}-trunk"
    journey.assign_material(trunk, mats["trunk"])
    trunk.parent = parent

    # 主干上长出三条可读的一级枝，不再把树冠直接插在一根杆上。
    branch_tips = []
    for index, angle in enumerate((0.35, 2.35, 4.45)):
        angle += rng.uniform(-0.35, 0.35)
        start_z = trunk_h * rng.uniform(0.56, 0.72)
        length = rng.uniform(1.25, 1.75) * scale
        tip = (
            x + math.cos(angle) * length,
            y + math.sin(angle) * length,
            start_z + rng.uniform(1.0, 1.55) * scale,
        )
        cylinder_between(
            f"{name}-branch-{index}", (x, y, start_z), tip,
            0.085 * scale, mats["branch"], parent, 8,
        )
        branch_tips.append(tip)

    branch_tips.append((x, y, trunk_h + 0.78 * scale))
    colors = (mats["yellow_a"], mats["yellow_b"], mats["yellow_c"], mats["orange"])
    for tip_index, tip in enumerate(branch_tips):
        radius = rng.uniform(1.12, 1.52) * scale
        location = (
            tip[0] + rng.uniform(-0.28, 0.28) * scale,
            tip[1] + rng.uniform(-0.28, 0.28) * scale,
            tip[2] + rng.uniform(0.05, 0.38) * scale,
        )
        crown = journey.sphere(
            f"{name}-crown-{tip_index}", radius, location,
            colors[(color_index + (1 if tip_index == 3 else 0)) % len(colors)], parent,
        )
        # 对每个低面数树冠做独立顶点扰动，轮廓不再是规则球体。
        for vertex in crown.data.vertices:
            co = vertex.co
            wave = math.sin(co.x * 3.1 + tip_index) * math.cos(co.y * 2.7 - tip_index)
            factor = rng.uniform(0.82, 1.17) * (1.0 + wave * 0.08)
            vertex.co *= factor
        crown.scale = (
            rng.uniform(1.00, 1.28), rng.uniform(0.90, 1.20), rng.uniform(0.82, 1.12)
        )
        crown.rotation_euler = (
            rng.uniform(-0.16, 0.16), rng.uniform(-0.16, 0.16), rng.uniform(0, math.tau)
        )


def add_blank_sign(name, x, y, rotation, parent, mats):
    holder = journey.empty(name, (x, y, 0), parent)
    holder.rotation_euler.z = rotation
    journey.cylinder(f"{name}-post", 0.07, 2.0, (0, 0, 1.0), mats["sign_post"], 10, holder)
    journey.box(f"{name}-board", (1.25, 0.10, 0.72), (0, 0, 1.85), mats["sign_board"], holder)


def load_tree_asset_prototypes():
    """导入 Quaternius CC0 树形；每个 glTF 只导入一次。"""
    prototypes = []
    for filename in TREE_ASSET_FILES:
        filepath = os.path.join(TREE_ASSET_DIR, filename)
        if not os.path.exists(filepath):
            raise FileNotFoundError(f"Missing tree asset: {filepath}")
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=filepath)
        imported = [obj for obj in bpy.data.objects if obj not in before and obj.type == "MESH"]
        if not imported:
            raise RuntimeError(f"Tree asset has no mesh: {filepath}")
        prototype = max(imported, key=lambda obj: obj.dimensions.z)
        prototype.name = f"TreePrototype-{os.path.splitext(filename)[0]}"
        prototypes.append(prototype)
        for extra in imported:
            if extra != prototype:
                bpy.data.objects.remove(extra, do_unlink=True)
    return prototypes


def add_asset_tree(name, prototype, location, scale, rotation, parent, mats, color_index):
    """链接复制树网格，并给每棵树独立指定树皮/秋叶材质。"""
    tree = prototype.copy()
    tree.data = prototype.data
    bpy.context.scene.collection.objects.link(tree)
    tree.name = name
    tree.location = location
    tree.rotation_euler.z = rotation
    tree.scale = (scale, scale, scale * 0.96)
    tree.parent = parent
    autumn = (mats["yellow_a"], mats["yellow_b"], mats["yellow_c"], mats["orange"])
    for slot in tree.material_slots:
        material_name = slot.material.name.lower() if slot.material else ""
        # 先读取共享网格上的原材质名称；切到 OBJECT 后槽位会暂时变空。
        slot.link = "OBJECT"
        if "lea" in material_name:
            slot.material = autumn[color_index % len(autumn)]
        elif "bark" in material_name:
            slot.material = mats["asset_bark"]
    return tree


def populate_yellow_fork(root, mats, tree_prototypes):
    # 正交音叉：主路到节点，向左右各转 90°，拉开后再转 90°并排前进。
    # 肩带比路面略宽，四个矩形在角部重叠，形成干净而明确的直角内角。
    for suffix, z, half_width, material in (
        ("Shoulder", 0.02, 4.1, mats["leaf_ground"]),
        ("Road", 0.06, ROAD_HALF_WIDTH, mats["road"]),
    ):
        journey.box(
            f"Fork-{suffix}-Trunk", (43.0, half_width * 2, 0.05),
            (-21.0, 0.0, z), material, root,
        )
        journey.box(
            f"Fork-{suffix}-Crossbar", (half_width * 2, FORK_SEPARATION * 2 + half_width * 2, 0.05),
            (0.0, 0.0, z), material, root,
        )
        for side in (-1, 1):
            journey.box(
                f"Fork-{suffix}-Tine-{side}", (57.0, half_width * 2, 0.05),
                (28.0, side * FORK_SEPARATION, z), material, root,
            )

    # 四段中心虚线完整保留，两个直角转向都清楚可读。
    for x in range(-38, 0, 5):
        journey.box(
            f"Fork-Dash-Trunk-{x}", (1.35, 0.10, 0.025),
            (x, 0.0, 0.10), mats["lane"], root,
        )
    for side in (-1, 1):
        for y_abs in (2.2, 5.2, 8.0):
            dash = journey.box(
                f"Fork-Dash-Turn-{side}-{y_abs}", (1.1, 0.10, 0.025),
                (0.0, side * y_abs, 0.10), mats["lane"], root,
            )
            dash.rotation_euler.z = math.pi / 2
        for x in range(4, 55, 5):
            journey.box(
                f"Fork-Dash-Tine-{side}-{x}", (1.35, 0.10, 0.025),
                (x, side * FORK_SEPARATION, 0.10), mats["lane"], root,
            )

    rng = random.Random(20261013)
    tree_index = 0
    for x in range(-40, 59, 4):
        for y_base in range(-24, 25, 4):
            if rng.random() < 0.18:
                continue
            xj = x + rng.uniform(-1.3, 1.3)
            yj = y_base + rng.uniform(-1.4, 1.4)
            if road_distance(xj, yj) < 5.0:
                continue
            scale = rng.uniform(0.58, 0.94)
            add_asset_tree(
                f"YellowTree-{tree_index}",
                tree_prototypes[tree_index % len(tree_prototypes)],
                (xj, yj, 0.0), scale, rng.uniform(0, math.tau), root, mats,
                rng.randrange(4),
            )
            tree_index += 1
            if tree_index % 3 == 0:
                leaf_patch = journey.sphere(
                    f"LeafPatch-{tree_index}", rng.uniform(0.45, 0.85),
                    (xj + rng.uniform(-1, 1), yj + rng.uniform(-1, 1), 0.12),
                    mats["leaf_patch"], root,
                )
                leaf_patch.scale = (1.4, 0.9, 0.16)

    # 两块空白路牌由 App 叠加选项文字。
    add_blank_sign("ChoiceSign-Left", 3.8, -5.4, math.radians(-8), root, mats)
    add_blank_sign("ChoiceSign-Right", 3.8, 5.4, math.radians(8), root, mats)


def animate_fork_world(root):
    root.location.x = 5.0
    root.keyframe_insert(data_path="location", frame=FRAME_START)
    root.location.x = -10.0
    root.keyframe_insert(data_path="location", frame=FRAME_END)
    for curve in journey.action_fcurves(root):
        for point in curve.keyframe_points:
            point.interpolation = "BEZIER"


def build_yellow_fork():
    variant = "yellow-fork-forest"
    scene, out_dir = setup_scene(variant, "F2DCA9")
    mats = {
        "ground": mat("YellowForest-Ground", "C8A95F"),
        "leaf_ground": mat("YellowForest-LeafGround", "D7B766"),
        "leaf_patch": mat("YellowForest-LeafPatch", "C58E3F"),
        "road": mat("YellowForest-Road", "777168"),
        "lane": mat("YellowForest-Lane", "E2C979"),
        "trunk": mat("YellowForest-Trunk", "6C4E35"),
        "branch": mat("YellowForest-Branch", "76543A"),
        "asset_bark": mat("YellowForest-Asset-Bark", "624631"),
        "yellow_a": mat("YellowForest-Yellow-A", "C28F2F"),
        "yellow_b": mat("YellowForest-Yellow-B", "D8AF49"),
        "yellow_c": mat("YellowForest-Yellow-C", "B77B29"),
        "orange": mat("YellowForest-Orange", "A96635"),
        "sign_post": mat("YellowForest-SignPost", "493D32"),
        "sign_board": mat("YellowForest-SignBoard", "E6D6B3"),
        "accent": mat("Accent", "B85C38"),
        "ink": mat("Ink", "2B2824"),
    }
    journey.box("YellowForest-Ground", (180, 110, 0.05), (4, 0, -0.055), mats["ground"])
    base.add_camera(scene, **base.SHARED_CAMERA)
    journey.add_lighting()
    root = journey.empty("MovingWorld")
    tree_prototypes = load_tree_asset_prototypes()
    populate_yellow_fork(root, mats, tree_prototypes)
    # 网格数据由所有实例共享；场景里不保留原点处的原型对象。
    for prototype in tree_prototypes:
        bpy.data.objects.remove(prototype, do_unlink=True)
    animate_fork_world(root)
    if base.WITH_TRAVELER:
        traveler = journey.add_traveler(mats)
        traveler.location.x = -12.5
        traveler.location.y = 0.0
    scene.frame_set(FRAME_START)
    blend_path = os.path.join(out_dir, f"{variant}.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    return scene, variant, blend_path


def render_checks(scene, variant):
    out_dir = os.path.join(OUT_ROOT, variant)
    scene.render.image_settings.media_type = "IMAGE"
    scene.render.image_settings.file_format = "PNG"
    for frame in (1, 144, 288):
        scene.frame_set(frame)
        scene.render.filepath = os.path.join(out_dir, f"check-{frame:03d}.png")
        bpy.ops.render.render(write_still=True)


def main():
    only = os.environ.get("WORLD_ONLY")
    builders = {"cbd-blocks": build_real_cbd, "yellow-fork": build_yellow_fork}
    chosen = [builders[only]] if only in builders else list(builders.values())
    for builder in chosen:
        scene, variant, blend_path = builder()
        if os.environ.get("WORLD_SKIP_CHECKS") != "1":
            render_checks(scene, variant)
        if os.environ.get("WORLD_RENDER_ANIMATION") == "1":
            base.render_animation(scene, variant)
        print(f"[world-v2] {variant}: {blend_path}")


if __name__ == "__main__":
    main()
