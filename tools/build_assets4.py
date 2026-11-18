#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""翌日·课后 —— 素材管线 v4（分层场景 + 十日卡司）"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SRC = r"C:\Users\34015\.workbuddy\agnes-image-mcp\output"
ART = r"C:\Users\34015\WorkBuddy\2026-11-17-22-06-13\tsugunohi_school\assets\art"
W, H = 1280, 720
CHAR_H = 460
DOOR_H = 420
WIN_H = 232


def load(n):
    return Image.open(os.path.join(SRC, n + ".png")).convert("RGB")


def key_flood(im, thresh=0.11, erode=3):
    """只把「与画面边缘连通的背景色区域」判为透明，内部一律保留 —— 不会吃掉衣服。"""
    rgb = np.asarray(im.convert("RGB")).astype(np.float32) / 255.0
    h, w, _ = rgb.shape
    pad = 8
    cs = np.concatenate([rgb[:pad, :pad].reshape(-1, 3), rgb[:pad, w - pad:].reshape(-1, 3),
                         rgb[h - pad:, :pad].reshape(-1, 3), rgb[h - pad:, w - pad:].reshape(-1, 3)])
    bg = np.median(cs, axis=0)
    dist = np.linalg.norm(rgb - bg, axis=-1)
    near = dist < thresh
    # 用洪水填充只保留与边界连通的 part
    mask = Image.fromarray(np.where(near, 255, 0).astype(np.uint8)).convert("RGB")
    for xy in [(1, 1), (w - 2, 1), (1, h - 2), (w - 2, h - 2),
               (w // 2, 1), (w // 2, h - 2), (1, h // 2), (w - 2, h // 2)]:
        try:
            ImageDraw.floodfill(mask, xy, (255, 0, 255), thresh=12)
        except Exception:
            pass
    m = np.asarray(mask)
    border = (m[..., 0] > 200) & (m[..., 1] < 60) & (m[..., 2] > 200)
    al = np.where(border, 0, 255).astype(np.uint8)
    al = np.asarray(Image.fromarray(al).filter(ImageFilter.GaussianBlur(0.8)))
    al = np.clip((al.astype(np.float32) - 110) * 2.8, 0, 255).astype(np.uint8)
    if erode > 1:
        al = np.asarray(Image.fromarray(al).filter(ImageFilter.MinFilter(erode)))
    src = rgb
    return Image.fromarray((np.clip(np.concatenate([src, al[..., None] / 255.0], -1), 0, 1)
                            * 255).astype(np.uint8), "RGBA")


def bbox(im):
    al = np.asarray(im)[..., 3]
    ys, xs = np.where(al > 30)
    if len(ys) == 0:
        return None
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def fit(im, th, pad_w=10):
    bb = bbox(im)
    if bb is None:
        return None
    im = im.crop(bb)
    sc = th / im.height
    im = im.resize((max(1, int(im.width * sc)), th), Image.LANCZOS)
    cv = Image.new("RGBA", (im.width + pad_w * 2, th), (0, 0, 0, 0))
    cv.alpha_composite(im, (pad_w, 0))
    return cv


def tint(im, sat=0.9, gain=0.92, gy=1.0, tintc=(0.90, 0.98, 1.12)):
    a = np.asarray(im).astype(np.float32) / 255.0
    rgb, al = a[..., :3], a[..., 3:]
    lum = rgb @ np.array([0.299, 0.587, 0.114], np.float32)
    rgb = np.clip(lum[..., None] + (rgb - lum[..., None]) * sat, 0, 1)
    rgb = np.clip(rgb * gain * gy * np.array(tintc, np.float32), 0, 1)
    return Image.fromarray((np.clip(np.concatenate([rgb, al], -1), 0, 1) * 255).astype(np.uint8), "RGBA")


# ---------------------------------------------------------- 背景墙
wall = load("lay_wall").resize((W, H), Image.LANCZOS)
a = np.asarray(wall).astype(np.float32) / 255.0 * 0.86
a[..., 2] *= 1.04
wall = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
wall.save(os.path.join(ART, "wall.png"))
wall.transpose(Image.FLIP_LEFT_RIGHT).save(os.path.join(ART, "wall_f.png"))
print("[wall] ok")

# ---------------------------------------------------------- 门窗构件
d = fit(tint(key_flood(load("lay_door")), gain=0.80), DOOR_H, 6)
d.save(os.path.join(ART, "door.png"))
print("[door]", d.size)

wn = fit(tint(key_flood(load("lay_window")), gain=0.86), WIN_H, 6)
wn.save(os.path.join(ART, "window.png"))
print("[window]", wn.size)

# ---------------------------------------------------------- 行人 10
npc_src = ["w_npc_girl", "npc_02", "npc_03", "npc_04", "npc_05",
           "npc_06", "npc_07", "npc_08", "npc_09", "npc_10"]
for i, s in enumerate(npc_src):
    im = fit(tint(key_flood(load(s))), CHAR_H, 8)
    if im:
        im.save(os.path.join(ART, "n%02d.png" % (i + 1)))
print("[npc] 10 ok")

# ---------------------------------------------------------- 行走鬼 10
gw_src = ["w_ghost", "gw_02", "gw_03", "gw_04", "gw_05",
          "gw_06", "gw_07", "gw_08", "gw_09", "gw_10"]
for i, s in enumerate(gw_src):
    im = fit(tint(key_flood(load(s)), sat=0.72, gain=0.88, tintc=(0.84, 0.96, 1.18)), CHAR_H, 8)
    if im:
        im.save(os.path.join(ART, "g%02d.png" % (i + 1)))
print("[ghost walk] 10 ok")

# ---------------------------------------------------------- 全屏跳脸 5
def cover(im, tw, th):
    s = max(tw / im.width, th / im.height)
    im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)
    x = max(0, (im.width - tw) // 2)
    y = max(0, (im.height - th) // 2)
    return im.crop((x, y, x + tw, y + th))


for i, s in enumerate(["js_veil_a", "js_02", "js_03", "js_04", "js_06"]):
    im = cover(load(s), W, H)
    arr = np.asarray(im).astype(np.float32) / 255.0
    arr = np.clip(arr ** 1.10, 0, 1) * 0.94
    arr[..., 2] *= 1.06
    Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8)).save(
        os.path.join(ART, "s%d.png" % (i + 1)))
print("[scare] 5 ok")

# ---------------------------------------------------------- 窗外鬼影 / 物件鬼
wg = fit(tint(key_flood(load("win_ghost")), sat=0.66, gain=0.86, tintc=(0.82, 0.96, 1.22)), 190, 6)
if wg:
    wg.save(os.path.join(ART, "wghost.png"))
    print("[win ghost]", wg.size)

for s, out in [("obj_ghost_box", "obox"), ("obj_ghost_chair", "ochair")]:
    im = fit(tint(key_flood(load(s)), sat=0.74, gain=0.86), 210, 8)
    if im:
        im.save(os.path.join(ART, out + ".png"))
        print("[obj ghost]", out, im.size)

print("[done]")
