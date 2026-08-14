#!/usr/bin/env python3
"""把渲好的循环视频拷进 Xcode 工程。

    python3 Blender/import_world_video.py [variant ...]

不带参数就把 out/ 下所有已经渲出 `<variant>-loop.mp4` 的变体都拷过去。

目标目录 `DecisionPath/Resources/World` 在工程里是**文件夹引用**，
所以加一段新的世界不用改 pbxproj —— 和 SceneArt 走 data set 是同一个道理。

App 侧按 variant 名找文件（`Bundle.main.url(forResource:withExtension:subdirectory:)`），
所以这里落地的文件名就是 `<variant>.mp4`，不带 `-loop`。
"""

import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_ROOT = os.path.join(ROOT, "Blender/out")
TARGET = os.path.join(ROOT, "DecisionPath/Resources/World")


def main():
    os.makedirs(TARGET, exist_ok=True)
    wanted = sys.argv[1:]
    copied = []
    for variant in sorted(os.listdir(OUT_ROOT)):
        if wanted and variant not in wanted:
            continue
        source = os.path.join(OUT_ROOT, variant, f"{variant}-loop.mp4")
        if not os.path.exists(source):
            continue
        target = os.path.join(TARGET, f"{variant}.mp4")
        shutil.copy(source, target)
        copied.append((variant, os.path.getsize(target) / 1024 / 1024))

    if not copied:
        sys.exit("没有找到 <variant>-loop.mp4，先跑 WORLD_RENDER_ANIMATION=1 的渲染")
    for variant, size in copied:
        print(f"{variant}.mp4  {size:.1f} MB")
    print(f"共 {len(copied)} 段，目录 {TARGET}")


if __name__ == "__main__":
    main()
