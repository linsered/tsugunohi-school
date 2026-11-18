"""
从 Noto Sans/Serif SC 可变字体生成子集字体，供 Web 导出内嵌。

原始字体位于 C:/Windows/Fonts/NotoSansSC-VF.ttf、NotoSerifSC-VF.ttf，
为 SIL Open Font License 1.1 授权，允许随项目再分发（见 fonts/OFL-NOTO.txt）。

做法：
1. 扫描项目内所有文本，收集实际用到的字符（含中文）。
2. 把可变字体实例化为 Regular(400) 静态字体。
3. 只保留用到的字形，输出为 assets/fonts/ui.ttf、serif.ttf。

依赖：pip install fonttools
运行：python tools/build_fonts.py
"""

import glob
import os
import sys

from fontTools import subset
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_DIR = os.path.join(ROOT, "assets", "fonts")
SRC_SANS = r"C:/Windows/Fonts/NotoSansSC-VF.ttf"
SRC_SERIF = r"C:/Windows/Fonts/NotoSerifSC-VF.ttf"


def collect_chars():
    chars = set(chr(i) for i in range(32, 127))  # ASCII 可打印
    chars.update("　—…‘’“”·→←↑↓〇×√■□●○▲▼、。，！？：；（）《》【】％＋－／")
    patterns = [
        "scripts/*.gd", "scenes/*.tscn", "project.godot",
        "README.md", "docs/*.md", "tools/*.py",
    ]
    for pat in patterns:
        for path in glob.glob(os.path.join(ROOT, pat)):
            with open(path, "r", encoding="utf-8", errors="ignore") as fh:
                chars.update(fh.read())
    # 保险：常见全角与游戏内可能出现的符号
    chars.update("０１２３４５６７８９")
    return "".join(sorted(chars))


def build(src, dst, text):
    if not os.path.exists(src):
        print("  [skip] 源字体不存在:", src)
        return False
    from fontTools.ttLib import TTFont
    font = TTFont(src)
    # 可变字体 -> 固定 Regular 字重，避免各平台对 VF 支持不一致
    try:
        font = instantiateVariableFont(font, {"wght": 400}, inplace=True)
    except Exception as exc:  # 非可变字体则直接用
        print("  [info] 实例化跳过:", exc)
    options = subset.Options()
    options.desubroutinize = True
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    options.notdef_outline = True
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(text=text)
    subsetter.subset(font)
    font.save(dst)
    font.close()
    return True


def main():
    os.makedirs(FONT_DIR, exist_ok=True)
    text = collect_chars()
    cjk = sum(1 for c in text if "\u4e00" <= c <= "\u9fff")
    print("收集字符: %d（其中 CJK %d）" % (len(text), cjk))
    ok1 = build(SRC_SANS, os.path.join(FONT_DIR, "ui.ttf"), text)
    ok2 = build(SRC_SERIF, os.path.join(FONT_DIR, "serif.ttf"), text)
    if not (ok1 and ok2):
        print("字体源缺失，终止。")
        return 1
    for name in ("ui.ttf", "serif.ttf"):
        p = os.path.join(FONT_DIR, name)
        print("生成 %s: %.1f KB" % (name, os.path.getsize(p) / 1024))
    return 0


if __name__ == "__main__":
    sys.exit(main())
