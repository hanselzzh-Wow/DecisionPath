"""参数化建筑生成器：中国当代城市 + 城郊两套词汇。

不是「建二十栋楼」，是「写一个生成器，喂二十组参数」。要改某一栋，改它那一行；
要多二十栋，多二十行。这是「不会画画」和「建筑肯定超过 15 个」的共同解法。

风格取舍：让人一眼认出「这是中国街道」的，不是屋顶形状，是几个具体构件 ——

    通长招牌带    临街商铺上方那条横贯整个立面的灯箱。最强的识别符号。
    封闭阳台      阳台被铝合金窗封起来，凸出立面一块。
    防盗窗        低层窗户外面那层格栅。
    凸出楼梯间    立面上一条竖向体块，窗比住户窗小、错半层。
    卷帘门        商铺关门时的横向瓦楞板。
    屋顶水箱间    平屋顶上那个小方盒子。

招牌一律留空白板 —— 字由 SKLabelNode 叠，永远不画进资产。

两条纪律：

1. **四个立面全建。** 别因为「当前角度看不到背面」就省掉 —— 一旦省了，相机就
   被锁死了，而相机是这个项目里最应该保持自由的东西。
2. **一切按米。** 人 1.7 米。所有比例关系在建模时定死，上屏之后不再靠眼睛调。
"""

import math
import random

import bpy


PANEL_T = 0.05          # 贴面板的厚度（窗、门这类）
BITE = 0.012            # 贴面板往墙里沉多少 —— 共面会 z-fighting，渲出来是摩尔纹
EAVE = 0.26             # 屋檐/女儿墙出挑


# ---------------------------------------------------------------- 基础网格

def new_box(name, size, location):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (size[0], size[1], size[2])
    return obj


def new_mesh(name, verts, faces, location=(0.0, 0.0, 0.0)):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    return obj


def panel(name, face, width, depth, along, z, size_along, size_z, thickness=PANEL_T):
    """把一块板贴在指定立面上。along 是沿该立面横向的偏移。

    做成独立物体是有意的：Workbench 的物体描边会给每个物体勾一圈边，
    所以窗户天然读成「画上去的线」，不需要布尔运算挖洞。
    """
    if face in ("-Y", "+Y"):
        sign = -1 if face == "-Y" else 1
        return new_box(name, (size_along, thickness, size_z),
                       (along, sign * (depth / 2 + thickness / 2 - BITE), z))
    sign = -1 if face == "-X" else 1
    return new_box(name, (thickness, size_along, size_z),
                   (sign * (width / 2 + thickness / 2 - BITE), along, z))


# ---------------------------------------------------------------- 色阶
#
# 表面不用贴图，只用纯色 —— 但不是一个灰色，是一条明度阶。
# 全部落在「纸白 → 墨」这一条色带上，不引入新色相。
#
# 陶土色刻意不用在建筑上（哪怕招牌很适合）：它是「当前选择」的语义色，
# 用在环境里会把那个意思稀释掉。整个世界只有用户的选择是暖的。

_PAPER = (0.949, 0.918, 0.851)
_INK = (0.141, 0.133, 0.122)


def _srgb_to_linear(c):
    # Blender 的 object color 是线性空间，直接塞 sRGB 值会偏亮。
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def tone(amount):
    """0 = 纸白，1 = 全墨。返回 Blender 用的线性 RGBA。"""
    mixed = tuple(a + (b - a) * amount for a, b in zip(_PAPER, _INK))
    return tuple(_srgb_to_linear(c) for c in mixed) + (1.0,)


# 整体偏亮：这是印在暖纸上的世界，墙面重了就发闷。
# 最暗的必须是窗洞 —— 全部对比度都押在它身上。
# 建筑主色板：低饱和、明度收窄。变化在色相，不在明暗 ——
# 这样整条街的构图仍然读成一块，而不是花的。
#
# 刻意绕开砖红/橙这一段：那是陶土强调色的地盘。一旦有楼是那个颜色，
# 「当前选择」就不特殊了。这条是硬约束，加新色的时候先看这里。

# 建筑主色板。
#
# 直接给最终色，不做归一化 —— 上一版把所有色相拉到同一明度，结果全成了
# 高明度中饱和的糖果色。真实城市恰恰相反：饱和度极低、明度跨度大。
# 水泥灰、灰白瓷砖、旧米黄、暗红砖，都是几乎接近中性、只带一点色相偏移的颜色。
#
# 唯一的加工是补偿 Workbench 的 studio 光（正面约 ×0.75，侧面约 ×0.45），
# 所以这里的值比你想在屏幕上看到的亮一档。别照着目标色直接填。

_SHADE_COMPENSATION = 1.24


def _hex(code):
    v = int(code, 16)
    rgb = ((v >> 16 & 255) / 255.0, (v >> 8 & 255) / 255.0, (v & 255) / 255.0)
    return tuple(min(c * _SHADE_COMPENSATION, 1.0) for c in rgb)


# 老城/城中村：旧涂料、瓷砖、砖。
BUILDING_HUES = tuple(_hex(c) for c in (
    "9B9791",   # 水泥灰
    "BEB9AE",   # 灰白瓷砖
    "BCAE92",   # 米黄涂料
    "A89873",   # 旧土黄
    "9C7A6B",   # 砖褐
    "8E6459",   # 暗红砖
    "879083",   # 灰绿
    "CDC5B5",   # 米白
    "6F6C68",   # 深灰
))

# 高层/幕墙：更冷、更统一，和老楼拉开一个色温。
TOWER_HUES = tuple(_hex(c) for c in (
    "8A959B",   # 灰蓝玻璃
    "97A2A3",   # 青灰
    "A6ABAA",   # 浅灰
    "7C8489",   # 深灰蓝
    "B4B4AF",   # 银灰
))


def _mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def _linear(rgb):
    return tuple(_srgb_to_linear(c) for c in rgb) + (1.0,)


def building_base(seed, palette=None):
    """一栋楼的主色。由 seed 决定，所以同一栋楼永远是同一个颜色。"""
    palette = palette or BUILDING_HUES
    return palette[seed % len(palette)]


# 构件之间走明度，不走色相：往墨里压或者往纸里提。
# 窗洞压得最狠 —— 全部对比度押在它身上，它不参与变色。
_SHIFT = {
    "wall": (_INK, 0.00),
    "roof": (_INK, 0.20),
    "detail": (_INK, 0.34),
    "shopfront": (_INK, 0.58),
    "window": (_INK, 0.74),
    # 幕墙玻璃不能按窗洞那么暗压：窗洞是墙上的几个小孔，幕墙是整片立面。
    # 压到 0.8 会让整栋楼变成黑块，一片 CBD 就是黑森林。
    "curtain": (_INK, 0.44),
    "spandrel": (_PAPER, 0.22),   # 层间实体带：比玻璃亮，横向节奏靠它
    "sign": (_PAPER, 0.74),
}

# 按物件名分色。命名本来就是成体系的，所以不用改任何构造函数的签名。
_TONE_RULES = (
    (("-spandrel",), "spandrel"),
    (("-curtain",), "curtain"),
    (("-sign",), "sign"),
    (("-win", "-glass", "-door", "-corewin"), "window"),
    (("-shutter", "-rib-", "-glassfront"), "shopfront"),
    (("-cage", "-bar-", "-rail", "-baluster"), "detail"),
    (("-roof", "-parapet", "-slab", "-gable", "-tank", "-canopy", "-step"), "roof"),
)


def paint_by_name(parts, base):
    for obj in parts:
        key = "wall"
        for needles, candidate in _TONE_RULES:
            if any(needle in obj.name for needle in needles):
                key = candidate
                break
        target, amount = _SHIFT[key]
        obj.color = _linear(_mix(base, target, amount))
    return parts


FACES = ("-Y", "+Y", "-X", "+X")


def face_span(face, width, depth):
    return width if face in ("-Y", "+Y") else depth


# ---------------------------------------------------------------- 中国城市构件

def sign_band(name, width, depth, z, height=0.92, wrap=True):
    """通长招牌带。留白，字后面用 SKLabelNode 叠。

    这是整套词汇里最强的一个 —— 一条横贯立面的灯箱，别的国家的街道没有。
    """
    parts = [panel(f"{name}-sign-Y", "-Y", width, depth, 0, z,
                   width * 0.995, height, thickness=0.22)]
    if wrap:
        # 拐角包过去一小段，才像真的灯箱而不是贴纸。
        parts.append(panel(f"{name}-sign-X", "+X", width, depth,
                           -depth / 2 + depth * 0.18, z,
                           depth * 0.34, height, thickness=0.22))
    return parts


def rolling_shutter(name, width, depth, z, opening_w, opening_h):
    """卷帘门：一块底板加几条横向瓦楞。"""
    parts = [panel(f"{name}-shutter", "-Y", width, depth, 0, z,
                   opening_w, opening_h, thickness=0.10)]
    ribs = max(int(opening_h / 0.36), 3)
    for i in range(ribs):
        rz = z - opening_h / 2 + (i + 0.5) * opening_h / ribs
        parts.append(panel(f"{name}-rib-{i}", "-Y", width, depth, 0, rz,
                           opening_w * 0.97, 0.07, thickness=0.16))
    return parts


def enclosed_balcony(name, width, depth, face, along, z, bay_w, height):
    """封闭阳台：凸出一块，正面再贴一层窗。"""
    out = 1.15
    parts = []
    if face in ("-Y", "+Y"):
        sign = -1 if face == "-Y" else 1
        cx, cy = along, sign * (depth / 2 + out / 2 - BITE)
        parts.append(new_box(f"{name}-box", (bay_w, out, height), (cx, cy, z)))
        parts.append(new_box(f"{name}-glass", (bay_w * 0.86, 0.06, height * 0.72),
                             (cx, cy + sign * (out / 2), z + height * 0.04)))
    else:
        sign = -1 if face == "-X" else 1
        cx, cy = sign * (width / 2 + out / 2 - BITE), along
        parts.append(new_box(f"{name}-box", (out, bay_w, height), (cx, cy, z)))
        parts.append(new_box(f"{name}-glass", (0.06, bay_w * 0.86, height * 0.72),
                             (cx + sign * (out / 2), cy, z + height * 0.04)))
    return parts


def window_cage(name, face, width, depth, along, z, win_w, win_h):
    """防盗窗：窗外那层格栅。只装低层 —— 这个细节本身就说明了楼层。"""
    parts = [panel(f"{name}-cage", face, width, depth, along, z,
                   win_w * 1.16, win_h * 1.12, thickness=0.22)]
    for i in (-1, 1):
        parts.append(panel(f"{name}-bar-v{i}", face, width, depth,
                           along + i * win_w * 0.28, z, 0.06, win_h * 1.06,
                           thickness=0.30))
    parts.append(panel(f"{name}-bar-h", face, width, depth, along, z,
                       win_w * 1.10, 0.06, thickness=0.30))
    return parts


def stair_core(name, width, depth, floors, floor_height, face="-Y", offset=0.0):
    """凸出的楼梯间：一条竖向体块，窗户错半层、比住户窗小。"""
    core_w = 2.5
    out = 0.75
    total = floors * floor_height
    parts = []
    sign = -1 if face == "-Y" else 1
    cy = sign * (depth / 2 + out / 2 - BITE)
    parts.append(new_box(f"{name}-core", (core_w, out, total), (offset, cy, total / 2)))
    for floor in range(floors):
        # 错半层，这是楼梯间最容易认出来的地方。
        z = (floor + 1.0) * floor_height - floor_height * 0.5 + floor_height * 0.42
        parts.append(new_box(f"{name}-corewin-{floor}",
                             (core_w * 0.42, 0.06, floor_height * 0.34),
                             (offset, cy + sign * (out / 2), z)))
    return parts


def roof_utilities(name, width, depth, base_z, rng):
    """屋顶水箱间和机房。平屋顶上那几个小方盒。"""
    parts = [new_box(f"{name}-tankroom", (width * 0.3, depth * 0.34, 2.4),
                     (width * 0.16, depth * 0.1, base_z + 1.2))]
    if rng.random() < 0.6:
        parts.append(new_box(f"{name}-tank", (1.5, 1.5, 1.1),
                             (-width * 0.22, -depth * 0.14, base_z + 0.55)))
    return parts


def parapet(name, width, depth, base_z, rail=0.34):
    parts = [new_box(f"{name}-slab", (width + EAVE, depth + EAVE, 0.10),
                     (0, 0, base_z + 0.05))]
    w = width / 2 + EAVE / 2
    d = depth / 2 + EAVE / 2
    for tag, size, loc in (
        ("n", (width + EAVE, 0.14, rail), (0, d, base_z + rail / 2)),
        ("s", (width + EAVE, 0.14, rail), (0, -d, base_z + rail / 2)),
        ("e", (0.14, depth + EAVE, rail), (w, 0, base_z + rail / 2)),
        ("w", (0.14, depth + EAVE, rail), (-w, 0, base_z + rail / 2)),
    ):
        parts.append(new_box(f"{name}-parapet-{tag}", size, loc))
    return parts, 0.10 + rail


def gable_roof(name, width, depth, base_z, height):
    w = width / 2 + EAVE
    d = depth / 2 + EAVE
    verts = [(-w, -d, 0), (w, -d, 0), (w, d, 0), (-w, d, 0),
             (-w, 0, height), (w, 0, height)]
    faces = [(0, 1, 5, 4), (2, 3, 4, 5), (0, 4, 3), (1, 2, 5), (0, 3, 2, 1)]
    return [new_mesh(f"{name}-gable", verts, faces, (0, 0, base_z))], height


def terrace_railing(name, width, depth, base_z, height=1.0):
    """自建房顶层露台的栏杆。城郊那套的标志之一。"""
    parts = []
    w = width / 2
    d = depth / 2
    for tag, size, loc in (
        ("n", (width, 0.09, height), (0, d, base_z + height / 2)),
        ("s", (width, 0.09, height), (0, -d, base_z + height / 2)),
        ("e", (0.09, depth, height), (w, 0, base_z + height / 2)),
        ("w", (0.09, depth, height), (-w, 0, base_z + height / 2)),
    ):
        parts.append(new_box(f"{name}-rail-{tag}", size, loc))
    for i in range(int(width / 0.8)):
        x = -w + (i + 0.5) * width / int(width / 0.8)
        parts.append(new_box(f"{name}-baluster-{i}", (0.07, 0.07, height),
                             (x, -d, base_z + height / 2)))
    return parts, height


# ---------------------------------------------------------------- 立面排窗

def facade_windows(name, face, width, depth, floors, floor_height, bays,
                   start_floor, rng, cage_floors=0, balcony_bays=(),
                   skip_along=None):
    span = face_span(face, width, depth)
    if span < 2.2 or bays < 1:
        return []

    win_w = min(span / bays * 0.54, 1.6)
    win_h = min(floor_height * 0.48, 1.7)
    parts = []
    for floor in range(start_floor, floors):
        base = floor * floor_height
        z = base + floor_height * 0.55
        for bay in range(bays):
            along = (bay + 0.5) / bays * span - span / 2
            if skip_along is not None and abs(along - skip_along[0]) < skip_along[1]:
                continue
            if face == "-Y" and bay in balcony_bays:
                parts.extend(enclosed_balcony(
                    f"{name}-bal-{floor}-{bay}", width, depth, face, along,
                    base + floor_height * 0.5, win_w * 1.5, floor_height * 0.78))
                continue
            parts.append(panel(f"{name}-win-{face}-{floor}-{bay}", face,
                               width, depth, along, z, win_w, win_h))
            if floor < cage_floors:
                parts.extend(window_cage(f"{name}-cg-{face}-{floor}-{bay}", face,
                                         width, depth, along, z, win_w, win_h))
    return parts


# ---------------------------------------------------------------- 城市建筑

def make_city_building(name, *, width, depth, floors, floor_height=3.1,
                       ground="shop", bays=3, balconies=True, cage_floors=2,
                       stairs=True, roof_kit=True, seed=0):
    """临街的多层楼。底层商铺 + 招牌带是默认形态。"""
    rng = random.Random(seed)
    body_h = floors * floor_height
    parts = [new_box(f"{name}-body", (width, depth, body_h), (0, 0, body_h / 2))]

    upper_start = 1 if ground != "plain" else 0
    balcony_bays = ()
    if balconies and floors >= 2 and bays >= 2:
        balcony_bays = tuple(sorted(rng.sample(range(bays), max(1, bays // 2))))

    core_offset = width * rng.choice((-0.32, 0.32))
    skip = (core_offset, 1.6) if stairs else None

    for face in FACES:
        parts.extend(facade_windows(
            name, face, width, depth, floors, floor_height, bays,
            upper_start, rng,
            cage_floors=min(cage_floors, floors) if face in ("-Y", "+Y") else 0,
            balcony_bays=balcony_bays if face == "-Y" else (),
            skip_along=skip if face == "-Y" else None,
        ))

    if stairs and floors >= 2:
        parts.extend(stair_core(name, width, depth, floors, floor_height,
                                offset=core_offset))

    if ground == "shop":
        opening_w = width * 0.8
        opening_h = floor_height * 0.66
        if rng.random() < 0.45:
            parts.extend(rolling_shutter(name, width, depth,
                                         floor_height * 0.42, opening_w, opening_h))
        else:
            parts.append(panel(f"{name}-glassfront", "-Y", width, depth, 0,
                               floor_height * 0.42, opening_w, opening_h,
                               thickness=0.09))
            parts.append(panel(f"{name}-shopdoor", "-Y", width, depth,
                               opening_w * 0.32, floor_height * 0.36,
                               0.95, floor_height * 0.58, thickness=0.14))
        parts.extend(sign_band(name, width, depth, floor_height * 0.93))
    elif ground == "door":
        parts.append(panel(f"{name}-door", "-Y", width, depth, core_offset,
                           floor_height * 0.42, 1.4, floor_height * 0.8,
                           thickness=0.10))
        parts.append(new_box(f"{name}-canopy", (2.4, 1.0, 0.16),
                             (core_offset, -(depth / 2 + 0.5), floor_height * 0.88)))

    roof_parts, roof_h = parapet(name, width, depth, body_h)
    parts.extend(roof_parts)
    if roof_kit:
        parts.extend(roof_utilities(name, width, depth, body_h + 0.10, rng))
        roof_h = max(roof_h, 2.5)

    return paint_by_name(parts, building_base(seed)), body_h + roof_h


# ---------------------------------------------------------------- 高层

def curtain_wall(name, width, depth, base_z, floors, floor_height):
    """玻璃幕墙：整层通长的横向玻璃带 + 层间实体带。

    高层不用「一扇一扇的窗」—— 那是老楼的读法。幕墙读起来是横向条带，
    这也是它和城中村最快拉开距离的一招。
    """
    parts = []
    for floor in range(floors):
        z = base_z + floor * floor_height
        for face in FACES:
            span = face_span(face, width, depth)
            parts.append(panel(f"{name}-curtain-{face}-{floor}", face, width, depth,
                               0, z + floor_height * 0.60,
                               span * 0.94, floor_height * 0.62, thickness=0.10))
            parts.append(panel(f"{name}-spandrel-{face}-{floor}", face, width, depth,
                               0, z + floor_height * 0.16,
                               span * 0.94, floor_height * 0.12, thickness=0.16))
    return parts


def make_tower(name, *, width, depth, floors, floor_height=3.5,
               podium_floors=0, podium_extra=3.0, setback_at=None,
               setback_shrink=0.72, seed=0):
    """高楼大厦：幕墙塔身 + 可选裙房 + 可选退台。

    和老楼的区别不是「更高」，是整套构件都不一样：没有阳台、没有防盗窗、
    没有外挂楼梯间；有的是幕墙、裙房、屋顶机房。
    """
    rng = random.Random(seed)
    parts = []
    base_z = 0.0

    if podium_floors > 0:
        pw = width + podium_extra
        pd = depth + podium_extra * 0.6
        ph = podium_floors * floor_height * 1.15
        parts.append(new_box(f"{name}-podium", (pw, pd, ph), (0, 0, ph / 2)))
        parts.extend(curtain_wall(f"{name}-pod", pw, pd, 0.0, podium_floors,
                                  floor_height * 1.15))
        parts.extend(parapet(f"{name}-podroof", pw, pd, ph, rail=0.28)[0])
        base_z = ph

    shaft_floors = floors if setback_at is None else setback_at
    shaft_h = shaft_floors * floor_height
    parts.append(new_box(f"{name}-body", (width, depth, shaft_h),
                         (0, 0, base_z + shaft_h / 2)))
    parts.extend(curtain_wall(name, width, depth, base_z, shaft_floors, floor_height))
    top_z = base_z + shaft_h

    if setback_at is not None and setback_at < floors:
        parts.extend(parapet(f"{name}-setback", width, depth, top_z, rail=0.30)[0])
        tw = width * setback_shrink
        td = depth * setback_shrink
        th = (floors - setback_at) * floor_height
        parts.append(new_box(f"{name}-cap", (tw, td, th), (0, 0, top_z + th / 2)))
        parts.extend(curtain_wall(f"{name}-top", tw, td, top_z,
                                  floors - setback_at, floor_height))
        width, depth, top_z = tw, td, top_z + th

    roof_parts, roof_h = parapet(name, width, depth, top_z, rail=0.42)
    parts.extend(roof_parts)
    parts.append(new_box(f"{name}-plantroom", (width * 0.34, depth * 0.36, 3.2),
                         (width * 0.1, 0, top_z + 1.6)))
    if rng.random() < 0.5:
        parts.append(new_box(f"{name}-mast", (0.28, 0.28, 4.5),
                             (-width * 0.24, depth * 0.12, top_z + 2.25)))
        roof_h = max(roof_h, 4.5)
    roof_h = max(roof_h, 3.2)

    return paint_by_name(parts, building_base(seed, TOWER_HUES)), top_z + roof_h


# ---------------------------------------------------------------- 地标
#
# 天际线的记忆点不在方盒子上，在异形上：收分、扭转、开洞、连桥、球体。
# 一片 CBD 只要有两三个这样的，整条街就不是「随便哪个城市」了。

def _glass_block(name, tag, size, location, rotation_z=0.0):
    obj = new_box(f"{name}-curtain-{tag}", size, location)
    if rotation_z:
        obj.rotation_euler = (0.0, 0.0, rotation_z)
    return obj


def make_landmark_taper(name, *, base_w, top_w, floors, floor_height=3.8,
                        segments=5, spire=0.0, seed=0):
    """收分塔：一节比一节窄。金茂那一路。"""
    parts = []
    per = max(floors // segments, 1)
    z = 0.0
    for seg in range(segments):
        t = seg / max(segments - 1, 1)
        w = base_w + (top_w - base_w) * t
        h = per * floor_height
        parts.append(new_box(f"{name}-body-{seg}", (w, w, h), (0, 0, z + h / 2)))
        parts.extend(curtain_wall(f"{name}-s{seg}", w, w, z, per, floor_height))
        # 每节交界挑出一圈檐，收分才读得出来
        parts.append(new_box(f"{name}-slab-{seg}", (w + 0.8, w + 0.8, 0.35),
                             (0, 0, z + h)))
        z += h
    if spire > 0:
        parts.append(new_box(f"{name}-spire", (0.7, 0.7, spire), (0, 0, z + spire / 2)))
        z += spire
    return paint_by_name(parts, building_base(seed, TOWER_HUES)), z


def make_landmark_twist(name, *, width, depth, floors, floor_height=3.6,
                        twist_deg=110.0, seed=0):
    """扭转塔：每层转一点。上海中心那一路。"""
    parts = []
    step = math.radians(twist_deg) / max(floors - 1, 1)
    for floor in range(floors):
        z = floor * floor_height
        angle = step * floor
        scale = 1.0 - 0.22 * (floor / max(floors - 1, 1))
        parts.append(_glass_block(name, f"f{floor}",
                                  (width * scale, depth * scale, floor_height * 0.80),
                                  (0, 0, z + floor_height * 0.5), angle))
        slab = new_box(f"{name}-spandrel-f{floor}",
                       (width * scale + 0.5, depth * scale + 0.5, floor_height * 0.16),
                       (0, 0, z + floor_height * 0.06))
        slab.rotation_euler = (0.0, 0.0, angle)
        parts.append(slab)
    top = floors * floor_height
    parts.append(new_box(f"{name}-spire", (0.5, 0.5, 6.0), (0, 0, top + 3.0)))
    return paint_by_name(parts, building_base(seed, TOWER_HUES)), top + 6.0


def make_landmark_portal(name, *, span, depth, height, leg_w, bridge_h, seed=0):
    """门形塔：两条腿加一段横梁，中间是空的。央视那一路。

    「中间有个洞」是最强的地标信号 —— 因为普通楼绝不会这样。
    """
    parts = []
    leg_h = height - bridge_h
    for side in (-1, 1):
        x = side * (span - leg_w) / 2
        parts.append(new_box(f"{name}-leg{side}", (leg_w, depth, leg_h), (x, 0, leg_h / 2)))
        parts.extend(curtain_wall(f"{name}-leg{side}", leg_w, depth, 0,
                                  int(leg_h / 3.6), 3.6))
    parts.append(new_box(f"{name}-bridge", (span, depth, bridge_h),
                         (0, 0, leg_h + bridge_h / 2)))
    parts.extend(curtain_wall(f"{name}-br", span, depth, leg_h,
                              max(int(bridge_h / 3.6), 1), 3.6))
    return paint_by_name(parts, building_base(seed, TOWER_HUES)), height


def make_landmark_twin(name, *, width, depth, floors, gap, bridge_floor,
                       floor_height=3.7, seed=0):
    """双塔连桥。"""
    parts = []
    height = floors * floor_height
    for side in (-1, 1):
        x = side * (width + gap) / 2
        parts.append(new_box(f"{name}-t{side}", (width, depth, height), (x, 0, height / 2)))
        obj_parts = curtain_wall(f"{name}-t{side}", width, depth, 0, floors, floor_height)
        for part in obj_parts:
            part.location = (part.location.x + x, part.location.y, part.location.z)
        parts.extend(obj_parts)
        cap = parapet(f"{name}-r{side}", width, depth, height)[0]
        for part in cap:
            part.location = (part.location.x + x, part.location.y, part.location.z)
        parts.extend(cap)
    bz = bridge_floor * floor_height
    parts.append(new_box(f"{name}-bridge", (gap + width, depth * 0.5, floor_height * 1.6),
                         (0, 0, bz)))
    parts.append(new_box(f"{name}-curtain-bridge", (gap, depth * 0.52, floor_height * 0.9),
                         (0, 0, bz)))
    return paint_by_name(parts, building_base(seed, TOWER_HUES)), height


def make_landmark_tv(name, *, shaft_h, sphere_r, antenna_h, seed=0):
    """电视塔：细杆 + 球 + 天线。剪影最独特的一个。"""
    parts = []
    bpy.ops.mesh.primitive_cylinder_add(radius=2.2, depth=shaft_h,
                                        location=(0, 0, shaft_h / 2), vertices=16)
    shaft = bpy.context.object
    shaft.name = f"{name}-shaft"
    parts.append(shaft)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=sphere_r, location=(0, 0, shaft_h * 0.72),
                                         segments=24, ring_count=12)
    pod = bpy.context.object
    pod.name = f"{name}-curtain-pod"
    parts.append(pod)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.45, depth=antenna_h,
                                        location=(0, 0, shaft_h + antenna_h / 2), vertices=8)
    mast = bpy.context.object
    mast.name = f"{name}-mast"
    parts.append(mast)

    parts.append(new_box(f"{name}-base", (13.0, 13.0, 5.0), (0, 0, 2.5)))
    return paint_by_name(parts, building_base(seed, TOWER_HUES)), shaft_h + antenna_h


def make_landmark_stepped(name, *, base_w, floors, steps=4, floor_height=3.7, seed=0):
    """层层退台的金字塔式高层。"""
    parts = []
    z = 0.0
    per = max(floors // steps, 1)
    for step in range(steps):
        w = base_w * (1.0 - 0.17 * step)
        h = per * floor_height
        parts.append(new_box(f"{name}-body-{step}", (w, w * 0.85, h), (0, 0, z + h / 2)))
        parts.extend(curtain_wall(f"{name}-s{step}", w, w * 0.85, z, per, floor_height))
        parts.extend(parapet(f"{name}-p{step}", w, w * 0.85, z + h, rail=0.3)[0])
        z += h
    return paint_by_name(parts, building_base(seed, TOWER_HUES)), z


LANDMARK_SPECS = [
    ("lm-taper", "收分塔", make_landmark_taper,
     dict(base_w=16.0, top_w=7.0, floors=30, segments=5, spire=9.0)),
    ("lm-twist", "扭转塔", make_landmark_twist,
     dict(width=15.0, depth=15.0, floors=26, twist_deg=115.0)),
    ("lm-portal", "门形塔", make_landmark_portal,
     dict(span=30.0, depth=13.0, height=62.0, leg_w=10.0, bridge_h=15.0)),
    ("lm-twin", "双塔连桥", make_landmark_twin,
     dict(width=11.0, depth=11.0, floors=24, gap=13.0, bridge_floor=17)),
    ("lm-tv", "电视塔", make_landmark_tv,
     dict(shaft_h=78.0, sphere_r=8.5, antenna_h=22.0)),
    ("lm-step", "退台塔", make_landmark_stepped,
     dict(base_w=20.0, floors=28, steps=4)),
]


# ---------------------------------------------------------------- 城郊建筑

def make_suburb_building(name, *, width, depth, floors, floor_height=3.3,
                         roof="terrace", bays=2, gate=False, seed=0):
    """自建房：面宽窄、层数不多、平顶带露台栏杆，或者简单坡顶。"""
    rng = random.Random(seed)
    body_h = floors * floor_height
    parts = [new_box(f"{name}-body", (width, depth, body_h), (0, 0, body_h / 2))]

    for face in FACES:
        parts.extend(facade_windows(name, face, width, depth, floors, floor_height,
                                    bays, 0, rng,
                                    cage_floors=1 if face == "-Y" else 0))

    parts.append(panel(f"{name}-door", "-Y", width, depth, 0,
                       floor_height * 0.42, 1.25, floor_height * 0.78,
                       thickness=0.10))
    parts.append(new_box(f"{name}-step", (2.0, 0.9, 0.18),
                         (0, -(depth / 2 + 0.45), 0.09)))

    if roof == "terrace":
        slab = [new_box(f"{name}-roofslab", (width + EAVE, depth + EAVE, 0.12),
                        (0, 0, body_h + 0.06))]
        rail_parts, rail_h = terrace_railing(name, width, depth, body_h + 0.12)
        parts.extend(slab + rail_parts)
        roof_h = 0.12 + rail_h
        if rng.random() < 0.5:
            parts.append(new_box(f"{name}-watertank", (1.2, 1.2, 1.0),
                                 (width * 0.24, depth * 0.2, body_h + 0.6)))
            roof_h = max(roof_h, 1.1)
    else:
        roof_parts, roof_h = gable_roof(name, width, depth, body_h, width * 0.3)
        parts.extend(roof_parts)

    if gate:
        wall_h = 1.9
        yard = depth * 0.9
        parts.append(new_box(f"{name}-yardwall", (width + 1.6, 0.18, wall_h),
                             (0, -(depth / 2 + yard), wall_h / 2)))
        parts.append(new_box(f"{name}-gate", (1.9, 0.10, wall_h * 0.92),
                             (0, -(depth / 2 + yard) - 0.08, wall_h * 0.46)))

    return paint_by_name(parts, building_base(seed)), body_h + roof_h


# ---------------------------------------------------------------- 清单
#
# 改这两张表就是改这座城 —— 加一行就是加一栋楼。
# kind 会写进 manifest，以后「走进健身房」按它挑建筑。
#
# 尺度提醒：1 米 ≈ 41pt，所以 6 层（约 19m）≈ 780pt，比屏幕还高。
# 高层只适合放远侧层当背景；临街那一层用 2–4 层。

CITY_SPECS = [
    ("city-01", "临街商铺·二层", dict(width=8.0, depth=7.0, floors=2, bays=3, ground="shop")),
    ("city-02", "临街商铺·三层", dict(width=6.5, depth=7.5, floors=3, bays=2, ground="shop")),
    ("city-03", "临街商铺·宽面", dict(width=12.0, depth=8.0, floors=2, bays=5, ground="shop")),
    ("city-04", "住宅·四层", dict(width=14.0, depth=9.0, floors=4, bays=5, ground="door")),
    ("city-05", "住宅·六层板楼", dict(width=17.0, depth=9.5, floors=6, bays=6, ground="door")),
    ("city-06", "住宅底商", dict(width=13.0, depth=9.0, floors=5, bays=5, ground="shop")),
    ("city-07", "城中村自建·窄面", dict(width=5.0, depth=8.0, floors=5, bays=2, ground="shop", balconies=False)),
    ("city-08", "城中村自建·窄面", dict(width=4.5, depth=7.5, floors=4, bays=2, ground="shop", balconies=False)),
    ("city-09", "办公楼", dict(width=11.0, depth=10.0, floors=4, bays=4, ground="door", balconies=False, cage_floors=0)),
    ("city-10", "塔楼", dict(width=9.0, depth=9.0, floors=9, bays=3, ground="door", balconies=True)),
    ("city-11", "平房店面", dict(width=7.5, depth=6.0, floors=1, bays=2, ground="shop", balconies=False, stairs=False, roof_kit=False)),
    ("city-12", "老式多层", dict(width=15.0, depth=8.5, floors=5, bays=6, ground="plain", cage_floors=3)),
    ("city-13", "临街商铺·窄", dict(width=5.5, depth=6.0, floors=2, bays=2, ground="shop")),
    ("city-14", "住宅·七层", dict(width=19.0, depth=10.0, floors=7, bays=7, ground="door")),
    ("city-15", "城中村·六层", dict(width=5.5, depth=9.0, floors=6, bays=2, ground="shop", balconies=False)),
    ("city-16", "菜场/仓储", dict(width=18.0, depth=12.0, floors=1, floor_height=5.0, bays=5, ground="shop", balconies=False, stairs=False)),
    ("city-17", "老小区·三层", dict(width=12.0, depth=8.0, floors=3, bays=4, ground="plain", cage_floors=2)),
    ("city-18", "底商三层", dict(width=10.0, depth=7.5, floors=3, bays=3, ground="shop")),
    ("city-19", "沿街四层", dict(width=9.0, depth=8.0, floors=4, bays=3, ground="shop")),
    ("city-20", "住宅·转角", dict(width=11.0, depth=11.0, floors=5, bays=4, ground="door")),
]

TOWER_SPECS = [
    ("twr-01", "写字楼·裙房", dict(width=13.0, depth=12.0, floors=12, podium_floors=2)),
    ("twr-02", "写字楼·退台", dict(width=11.0, depth=11.0, floors=16, setback_at=11)),
    ("twr-03", "玻璃塔楼", dict(width=10.0, depth=10.0, floors=20)),
    ("twr-04", "板式高层", dict(width=22.0, depth=11.0, floors=14)),
    ("twr-05", "高层·大裙房", dict(width=12.0, depth=12.0, floors=9, podium_floors=3, podium_extra=5.0)),
    ("twr-06", "双退台塔楼", dict(width=12.0, depth=12.0, floors=22, setback_at=15, setback_shrink=0.66)),
    ("twr-07", "低层办公", dict(width=16.0, depth=13.0, floors=6, podium_floors=1)),
    ("twr-08", "商场盒子", dict(width=26.0, depth=18.0, floors=4, floor_height=4.6)),
]

SUBURB_SPECS = [
    ("sub-01", "自建房·露台", dict(width=7.0, depth=8.0, floors=2, roof="terrace", bays=2, gate=True)),
    ("sub-02", "自建房·三层", dict(width=6.0, depth=8.5, floors=3, roof="terrace", bays=2)),
    ("sub-03", "自建房·坡顶", dict(width=7.5, depth=7.0, floors=2, roof="gable", bays=3)),
    ("sub-04", "平房", dict(width=8.0, depth=6.0, floors=1, roof="gable", bays=3)),
    ("sub-05", "平房·带院", dict(width=6.5, depth=6.0, floors=1, roof="terrace", bays=2, gate=True)),
    ("sub-06", "小仓库", dict(width=10.0, depth=7.0, floors=1, floor_height=4.4, roof="gable", bays=2)),
]


# 三个场景包。它们不是同一条街上的不同楼，是三个不同的地方 ——
# 走到哪儿，换哪一套。App 那边按 pack 挑资产。

PACKS = ("cbd", "oldtown", "suburb")


def build_all_buildings():
    """返回 [(id, pack, kind, 物件列表, 总高)]。"""
    out = []
    for index, (asset_id, kind, params) in enumerate(TOWER_SPECS):
        parts, height = make_tower(asset_id, seed=index * 11 + 5, **params)
        out.append((asset_id, "cbd", kind, parts, height))
    for index, (asset_id, kind, builder, params) in enumerate(LANDMARK_SPECS):
        parts, height = builder(asset_id, seed=index * 13 + 2, **params)
        out.append((asset_id, "cbd", kind, parts, height))
    for index, (asset_id, kind, params) in enumerate(CITY_SPECS):
        parts, height = make_city_building(asset_id, seed=index * 17 + 3, **params)
        out.append((asset_id, "oldtown", kind, parts, height))
    for index, (asset_id, kind, params) in enumerate(SUBURB_SPECS):
        parts, height = make_suburb_building(asset_id, seed=index * 23 + 7, **params)
        out.append((asset_id, "suburb", kind, parts, height))
    return out
