#!/usr/bin/env python3
"""把 Blender 渲出来的资产导入 Xcode 工程。

    python3 Blender/import_to_xcode.py [preset] [max_px]

做三件事：

1. 每张 PNG 生成一个 imageset（Assets.xcassets 是文件夹引用，放进去就会被编译）
2. SceneArt.json 做成 data set —— 走 NSDataAsset 读，这样加资产**不用改 pbxproj**
3. 超过 max_px 的图降采样，并同步改写 manifest 里的 pixelsPerMeter

第 3 步不能省：渲染上限拉到 8192 时资产目录是 294MB，而屏幕最高 874pt，
@3x 也只要 2622px。降完之后每张图的像素/米各不相同，所以必须逐条记进
manifest —— App 靠它把像素换算回真实尺寸，不能假设全局一致。

**max_px 要按「这张图在屏幕上多大」定，不是按「屏幕多大」定。**
2600 那个数假设的是一栋楼占满全屏。真实构图里不是这样：街边最高的楼约 420pt，
天际线上的地标约 330pt，@3x 也就 1300px 左右。差出来的不是磁盘，是内存 ——
SpriteKit 解码的是整张图，2368×2600 一张就是 24MB，满屏摆二三十张必被 jetsam。
所以默认给 1200：@3x 仍然够用，单张解码降到 5MB 以下。
"""

import json
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "DecisionPath/Resources/Assets.xcassets")
MAX_PX = 1200


def pixel_size(path):
    out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path],
                         capture_output=True, text=True).stdout
    width = int([l for l in out.splitlines() if "pixelWidth" in l][0].split(":")[1])
    height = int([l for l in out.splitlines() if "pixelHeight" in l][0].split(":")[1])
    return width, height


def main():
    preset = sys.argv[1] if len(sys.argv) > 1 else "b-middle"
    max_px = int(sys.argv[2]) if len(sys.argv) > 2 else MAX_PX
    source = os.path.join(ROOT, "Blender/out", preset)
    manifest_path = os.path.join(source, "SceneArt.json")
    if not os.path.exists(manifest_path):
        sys.exit(f"没找到 {manifest_path}，先跑 greybox.py")

    manifest = json.load(open(manifest_path))

    # 清掉上一批，避免删掉的资产还残留在工程里。
    for entry in os.listdir(CATALOG):
        if entry.endswith((".imageset", ".dataset")):
            shutil.rmtree(os.path.join(CATALOG, entry))

    shrunk = 0
    for asset in manifest["assets"]:
        asset_id = asset["id"]
        png = os.path.join(source, f"{asset_id}.png")
        if not os.path.exists(png):
            print("缺图:", asset_id)
            continue

        folder = os.path.join(CATALOG, f"{asset_id}.imageset")
        os.makedirs(folder, exist_ok=True)
        target = os.path.join(folder, f"{asset_id}.png")
        shutil.copy(png, target)

        width, height = asset["pixelSize"]
        if max(width, height) > max_px:
            ratio = max_px / max(width, height)
            subprocess.run(["sips", "-Z", str(max_px), target], capture_output=True)
            asset["pixelSize"] = list(pixel_size(target))
            asset["pixelsPerMeter"] = round(asset["pixelsPerMeter"] * ratio, 4)
            shrunk += 1

        # 单尺度 imageset：UIImage 的 scale 是 1，尺寸由 App 按真实米数换算，
        # 所以这里不需要 @2x/@3x 的区分。
        json.dump({"images": [{"filename": f"{asset_id}.png", "idiom": "universal"}],
                   "info": {"author": "xcode", "version": 1}},
                  open(os.path.join(folder, "Contents.json"), "w"), indent=2)

    dataset = os.path.join(CATALOG, "SceneArt.dataset")
    os.makedirs(dataset, exist_ok=True)
    json.dump(manifest, open(os.path.join(dataset, "SceneArt.json"), "w"),
              ensure_ascii=False, indent=2)
    json.dump({"data": [{"filename": "SceneArt.json", "idiom": "universal"}],
               "info": {"author": "xcode", "version": 1}},
              open(os.path.join(dataset, "Contents.json"), "w"), indent=2)

    total = sum(os.path.getsize(os.path.join(dp, f))
                for dp, _, fs in os.walk(CATALOG) for f in fs)
    print(f"导入 {len(manifest['assets'])} 个资产（降采样 {shrunk} 个），"
          f"资产目录 {total / 1024 / 1024:.1f} MB")


if __name__ == "__main__":
    main()
