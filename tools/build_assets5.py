#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""翌日·课后 —— 素材管线 v5（绿幕严格键 + 新卡司）"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SRC = r"C:\Users\34015\.workbuddy\agnes-image-mcp\output"
ART = r"C:\Users\34015\WorkBuddy\2026-11-17-22-06-13\tsugunohi_school\assets\art"
CHAR_H = 460


def load(n):
    return Image.open(os.path.join(SRC, n + ".png")).convert("RGB")


def key_green(im, erode=3):
    """只键绿幕：G 明显高于 R/B 且与边界连通。白/蓝/红衣服一律不受影响。"""
    rgb = np.asarray(im).astype(np.float32) / 255.0
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    gd = g - np.maximum(r, b)
    near = gd > 0.10
    h, w = near.shape
    m = Image.fromarray(np.where(near, 255, 0).astype(np.uint8)).convert("RGB")
    for xy in [(1, 1), (w - 2, 1), (1, h - 2), (w - 2, h - 2),
               (w // 2, 1), (w // 2, h - 2), (1, h // 2), (w - 2, h // 2)]:
        if np.asarray(m)[xy[1], xy[0], 0] > 100:
            ImageDraw.floodfill(m, xy, (255, 0, 255), thresh=10)
    arr = np.asarray(m)
    bg = (arr[..., 0] > 200) & (arr[..., 1] < 60) & (arr[..., 2] > 200)
    al = np.where(bg, 0, 255).astype(np.uint8)
    # 软边：模糊后二值化，避免硬切留下亮环
    # 先削掉最外 2px（原图烘焙的高光正好在这圈），再软化边缘
    al = np.asarray(Image.fromarray(al).filter(ImageFilter.MinFilter(5)))
    al = np.asarray(Image.fromarray(al).filter(ImageFilter.GaussianBlur(0.9)))
    al = np.clip((al.astype(np.float32) - 60.0) * 2.0, 0, 255).astype(np.uint8)
    # 边缘压暗除光：把轮廓往里 4px 的爆亮白边一起压下去
    out = rgb.copy()
    a01 = al.astype(np.float32) / 255.0
    inner = np.asarray(Image.fromarray(al).filter(ImageFilter.MinFilter(9)))
    band = (al > 120) & (inner < 120)
    out[band] = out[band] * 0.52
    soft = (al > 0) & (al <= 120)
    out[soft] = out[soft] * 0.70
    edge = (a01 > 0.02) & (a01 < 0.98)
    out[..., 1] = np.where(edge, np.minimum(out[..., 1], np.maximum(out[..., 0], out[..., 2])), out[..., 1])
    return Image.fromarray((np.clip(np.concatenate([out, al[..., None] / 255.0], -1), 0, 1)
                            * 255).astype(np.uint8), "RGBA")


def bbox(im):
    al = np.asarray(im)[..., 3]
    ys, xs = np.where(al > 30)
    if len(ys) == 0:
        return None
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def fit(im, th, pad=8):
    bb = bbox(im)
    if bb is None:
        return None
    im = im.crop(bb)
    sc = th / im.height
    im = im.resize((max(1, int(im.width * sc)), th), Image.LANCZOS)
    cv = Image.new("RGBA", (im.width + pad * 2, th), (0, 0, 0, 0))
    cv.alpha_composite(im, (pad, 0))
    return cv


def tint(im, sat=0.88, gain=0.93, tc=(0.90, 0.98, 1.12)):
    a = np.asarray(im).astype(np.float32) / 255.0
    rgb, al = a[..., :3], a[..., 3:]
    lum = rgb @ np.array([0.299, 0.587, 0.114], np.float32)
    rgb = np.clip(lum[..., None] + (rgb - lum[..., None]) * sat, 0, 1)
    rgb = np.clip(rgb * gain * np.array(tc, np.float32), 0, 1)
    return Image.fromarray((np.clip(np.concatenate([rgb, al], -1), 0, 1) * 255).astype(np.uint8), "RGBA")


def emit(src, out, th=CHAR_H, sat=0.88, gain=0.93, tc=(0.90, 0.98, 1.12)):
    im = fit(tint(key_green(load(src)), sat=sat, gain=gain, tc=tc), th)
    if im:
        im.save(os.path.join(ART, out + ".png"))
        print("  ", out, im.size)
    else:
        print("  !!", out, "EMPTY")


# 主角单独使用（已产出且用户认可），此处不覆盖 p.png

print("[friend]")
emit("zhouyu", "friend")
emit("zhouyu_ghost", "friend_g", sat=0.74, gain=0.88, tc=(0.84, 0.96, 1.18))

print("[bullies]")
for i, s in enumerate(["bully_a", "bully_b", "bully_c"]):
    emit(s, "b%d" % (i + 1))

print("[crowd 9 pairs]")
npc = ["npc_02", "npc_03", "npc_04", "npc_05", "npc_06",
       "npc_07", "npc_08", "npc_09", "npc_10"]
gws = ["gw_02", "gw_03", "gw_04", "gw_05", "gw_06",
       "gw_07", "gw_08", "gw_09", "gw_10"]
for i, s in enumerate(npc):
    emit(s, "n%02d" % (i + 1))
for i, s in enumerate(gws):
    emit(s, "g%02d" % (i + 1), sat=0.72, gain=0.87, tc=(0.84, 0.96, 1.18))

print("[extreme ghosts]")
emit("gx_longneck", "x1", sat=0.70, gain=0.86, tc=(0.82, 0.95, 1.20))
emit("gx_head180", "x2", sat=0.70, gain=0.86, tc=(0.82, 0.95, 1.20))
emit("gx_bighead", "x3", sat=0.62, gain=0.84, tc=(0.86, 0.96, 1.12))
emit("gx_face90", "x4", sat=0.70, gain=0.86, tc=(0.82, 0.95, 1.20))
print("[done]")
