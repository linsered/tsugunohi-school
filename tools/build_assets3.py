#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""翌日·课后 —— 素材管线 v3（平行走廊版）"""
import os, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SRC = r"C:\Users\34015\.workbuddy\agnes-image-mcp\output"
ROOT = r"C:\Users\34015\WorkBuddy\2026-11-17-22-06-13\tsugunohi_school"
ART = os.path.join(ROOT, "assets", "art")
W, H = 1280, 720
CH = 660


def load(n):
    return Image.open(os.path.join(SRC, n + ".png")).convert("RGB")


def key_green(im, tol=50):
    a = np.asarray(im.convert("RGB")).astype(np.int16)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    bg = (g - np.maximum(r, b) > tol) & (g > 55)
    al = np.where(bg, 0, 255).astype(np.uint8)
    al = np.asarray(Image.fromarray(al).filter(ImageFilter.GaussianBlur(0.8)))
    al = np.clip((al.astype(np.float32) - 110) * 2.6, 0, 255).astype(np.uint8)
    src = np.asarray(im).astype(np.float32) / 255.0
    a_ = al.astype(np.float32)[..., None] / 255.0
    edge = (a_[..., 0] > 0.02) & (a_[..., 0] < 0.98)
    src[..., 1] = np.where(edge, np.minimum(src[..., 1], np.maximum(src[..., 0], src[..., 2])), src[..., 1])
    return Image.fromarray((np.clip(np.concatenate([src, a_], -1), 0, 1) * 255).astype(np.uint8), "RGBA")


def bbox(im):
    al = np.asarray(im)[..., 3]
    ys, xs = np.where(al > 30)
    if len(ys) == 0:
        return None
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


# ---------------- 走廊：一张平视侧立面，横向无缝平铺 ----------------
h = load("hall_flat").resize((W, int(H * 1.14)), Image.LANCZOS).crop((0, 0, W, H))
a = np.asarray(h).astype(np.float32) / 255.0
a *= 0.80
a[..., 0] *= 0.96
a[..., 2] *= 1.05
h = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
h.save(os.path.join(ART, "hall.png"))
h.transpose(Image.FLIP_LEFT_RIGHT).save(os.path.join(ART, "hall_f.png"))
print("[1] hall", h.size)

# ---------------- 可变物件：切成 5 个 ----------------
def key_flood(im, thresh=34):
    rgb = im.convert("RGB").copy()
    w, hh = rgb.size
    mk = (255, 0, 255)
    for xy in [(1, 1), (w - 2, 1), (1, hh - 2), (w - 2, hh - 2), (w // 2, 1), (w // 2, hh - 2)]:
        try:
            ImageDraw.floodfill(rgb, xy, mk, thresh=thresh)
        except Exception:
            pass
    a = np.asarray(rgb).astype(np.int16)
    bg = (a[..., 0] > 240) & (a[..., 1] < 30) & (a[..., 2] > 240)
    o = np.asarray(im.convert("RGB")).astype(np.int16)
    bg |= (o[..., 1] > o[..., 0] + 22) & (o[..., 1] > o[..., 2] + 22) & (o[..., 1] > 70)
    al = np.where(bg, 0, 255).astype(np.uint8)
    al = np.asarray(Image.fromarray(al).filter(ImageFilter.GaussianBlur(0.7)))
    al = np.clip((al.astype(np.float32) - 100) * 2.6, 0, 255).astype(np.uint8)
    src = np.asarray(im.convert("RGB")).astype(np.float32) / 255.0
    return Image.fromarray((np.clip(np.concatenate([src, al[..., None] / 255.0], -1), 0, 1) * 255).astype(np.uint8), "RGBA")


sheet = load("props_sheet")
sw = sheet.width // 5
names = ["prop_box", "prop_mop", "prop_chairs", "prop_ext", "prop_shoes"]
sizes = [132, 285, 250, 138, 52]
for i, n in enumerate(names):
    cell = sheet.crop((i * sw, 0, (i + 1) * sw, sheet.height))
    im = key_flood(cell)
    bb = bbox(im)
    if bb is None:
        continue
    im = im.crop(bb)
    th = sizes[i]
    sc = th / im.height
    im = im.resize((max(1, int(im.width * sc)), th), Image.LANCZOS)
    cv = Image.new("RGBA", (im.width + 12, th), (0, 0, 0, 0))
    cv.alpha_composite(im, (6, 0))
    cv.save(os.path.join(ART, n + ".png"))
    print("    ", n, cv.size)

# ---------------- 跳脸：同一张图取三种构图 ----------------
js = load("js_veil_a")


def cover(im, tw, th):
    s_ = max(tw / im.width, th / im.height)
    im = im.resize((max(1, int(im.width * s_)), max(1, int(im.height * s_))), Image.LANCZOS)
    x = max(0, (im.width - tw) // 2)
    y = max(0, (im.height - th) // 2)
    return im.crop((x, y, x + tw, y + th))


A = cover(js, W, H)
B = cover(js.crop((int(js.width * 0.16), int(js.height * 0.08),
                   int(js.width * 0.84), int(js.height * 0.52))), W, H)
C = cover(js.crop((int(js.width * 0.08), int(js.height * 0.10),
                   int(js.width * 0.92), int(js.height * 0.70))), W, H)

for im, n, tint in [(A, "js_a", (1.0, 1.0, 1.05)), (B, "js_b", (0.95, 1.0, 1.06)),
                    (C, "js_c", (1.18, 0.92, 0.92))]:
    arr = np.asarray(im).astype(np.float32) / 255.0
    arr = np.clip(arr ** 1.12, 0, 1) * np.array(tint, np.float32)
    arr = np.clip(arr * 0.92, 0, 1)
    Image.fromarray((arr * 255).astype(np.uint8)).save(os.path.join(ART, n + ".png"))
    print("    ", n)

# ---------------- 站立鬼：把洋红底彻底抠掉 ----------------
def key_magenta(im, lo=0.08, hi=0.30, despill=0.5):
    im = im.convert("RGB")
    a = np.asarray(im).astype(np.float32) / 255.0
    hh, ww, _ = a.shape
    pad = 8
    cs = np.concatenate([a[:pad, :pad].reshape(-1, 3), a[:pad, ww - pad:].reshape(-1, 3),
                         a[hh - pad:, :pad].reshape(-1, 3), a[hh - pad:, ww - pad:].reshape(-1, 3)])
    bg = np.median(cs, axis=0)
    dd = np.linalg.norm(a - bg, axis=-1) / math.sqrt(3.0)
    al = np.clip((dd - lo) / (hi - lo), 0, 1)
    aa = np.clip(al, 1e-3, 1.0)[..., None]
    fg = np.clip((a - bg * (1.0 - aa)) / aa, 0, 1)
    over = np.clip(fg[..., 0] - fg[..., 1], 0, None) + np.clip(fg[..., 2] - fg[..., 1], 0, None)
    fix = np.clip(over, 0, 1) * despill
    fg = fg * (1.0 - fix[..., None] * np.array([0.6, 0.0, 0.6]))
    fg[..., 1] = np.clip(fg[..., 1] + fix * 0.3, 0, 1)
    out = np.concatenate([fg, al[..., None]], -1)
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), "RGBA")


gv = key_magenta(load("ghost"))
bb = bbox(gv)
gv = gv.crop(bb)
sc = 600.0 / gv.height
gv = gv.resize((int(gv.width * sc), 600), Image.LANCZOS)
arr = np.asarray(gv).astype(np.float32) / 255.0
arr[..., :3] = np.clip(arr[..., :3] * np.array([0.86, 0.98, 1.12], np.float32), 0, 1)
cv = Image.new("RGBA", (gv.width + 16, 610), (0, 0, 0, 0))
cv.alpha_composite(Image.fromarray((arr * 255).astype(np.uint8), "RGBA"), (8, 0))
cv.save(os.path.join(ART, "f_ghost_veil.png"))
print("[2] f_ghost_veil rekeyed", cv.size)
print("[done]")
