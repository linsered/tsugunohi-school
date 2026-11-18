#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
翌日·课后 —— 素材管线（照片感版）
- 人物：白底洪水填充抠像 → 去边 → 统一高度 → 底部对齐
- 背景：照片裁 16:9 → 1280x720
- 跳脸：拍平到 1280x720，压暗
- 音频：numpy 合成（沿用）
"""
import os, math, wave
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SRC = r"C:\Users\34015\.workbuddy\agnes-image-mcp\output"
ROOT = r"C:\Users\34015\WorkBuddy\2026-11-17-22-06-13\tsugunohi_school"
ART = os.path.join(ROOT, "assets", "art")
SFX = os.path.join(ROOT, "assets", "audio")
os.makedirs(ART, exist_ok=True)
os.makedirs(SFX, exist_ok=True)

RNG = np.random.default_rng(20261118)
W, H = 1280, 720
CH_H = 640          # 人物在屏高度


def load(n):
    p = os.path.join(SRC, n + ".png")
    if not os.path.exists(p):
        raise FileNotFoundError(p)
    return Image.open(p).convert("RGB")


# ------------------------------------------------------------- 白底抠像
def key_white(im, thresh=26):
    """从四角洪水填充背景，再羽化边缘。比阈值抠图安全：不会吃掉衣服里的白。"""
    im = im.convert("RGB")
    w, h = im.size
    marker = (255, 0, 255)
    rgb = im.copy()
    for xy in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (w // 2, 0), (w // 2, h - 1)]:
        try:
            ImageDraw.floodfill(rgb, xy, marker, thresh=thresh)
        except Exception:
            pass
    a = np.asarray(rgb).astype(np.int16)
    isbg = (a[..., 0] > 240) & (a[..., 1] < 30) & (a[..., 2] > 240)
    alpha = np.where(isbg, 0, 255).astype(np.uint8)
    # 羽化：轻微模糊后拉回硬边
    af = Image.fromarray(alpha).filter(ImageFilter.GaussianBlur(1.2))
    alpha = np.asarray(af)
    alpha = np.clip((alpha.astype(np.float32) - 90) * 2.2, 0, 255).astype(np.uint8)

    # 蚀边 1px，去掉白底残留的白边
    from PIL import ImageFilter as _IF
    alpha = np.asarray(Image.fromarray(alpha).filter(_IF.MinFilter(3)))
    src = np.asarray(im).astype(np.float32) / 255.0
    al = alpha.astype(np.float32)[..., None] / 255.0
    # 去白边：把半透明像素往中性色收一点
    src = src * (0.55 + 0.45 * al) + (1.0 - al) * 0.0
    out = np.concatenate([np.clip(src, 0, 1), al], axis=-1)
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), "RGBA")


def key_green(im, tol=52):
    """绿幕底的图用绿键：G 明显高于 R/B 且亮度够。"""
    im = im.convert("RGB")
    a = np.asarray(im).astype(np.int16)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    isbg = (g - np.maximum(r, b) > tol) & (g > 60)
    alpha = np.where(isbg, 0, 255).astype(np.uint8)
    af = Image.fromarray(alpha).filter(ImageFilter.GaussianBlur(1.0))
    alpha = np.clip((np.asarray(af).astype(np.float32) - 100) * 2.4, 0, 255).astype(np.uint8)
    # 蚀边 1px，去掉白底残留的白边
    from PIL import ImageFilter as _IF
    alpha = np.asarray(Image.fromarray(alpha).filter(_IF.MinFilter(3)))
    src = np.asarray(im).astype(np.float32) / 255.0
    al = alpha.astype(np.float32)[..., None] / 255.0
    # 去绿溢：把边缘的绿往中性拉
    edge = (al[..., 0] > 0.02) & (al[..., 0] < 0.98)
    src[..., 1] = np.where(edge, np.minimum(src[..., 1], np.maximum(src[..., 0], src[..., 2])), src[..., 1])
    out = np.concatenate([np.clip(src, 0, 1), al], axis=-1)
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), "RGBA")


def bbox(im):
    a = np.asarray(im)[..., 3]
    ys, xs = np.where(a > 30)
    if len(ys) == 0:
        return None
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def grade(im, sat=0.86, gain=0.94, contrast=1.06, tint=(0.90, 0.98, 1.10)):
    a = np.asarray(im).astype(np.float32) / 255.0
    rgb, al = a[..., :3], a[..., 3:4]
    lum = rgb @ np.array([0.299, 0.587, 0.114], np.float32)
    rgb = np.clip(lum[..., None] + (rgb - lum[..., None]) * sat, 0, 1)
    rgb = np.clip((rgb - 0.5) * contrast + 0.5, 0, 1)
    rgb = np.clip(rgb * gain * np.array(tint, np.float32), 0, 1)
    return Image.fromarray((np.clip(np.concatenate([rgb, al], -1), 0, 1) * 255).astype(np.uint8), "RGBA")


def make_char(src_name, out_name, target_h=CH_H, align="center", extra_dark=0.0, green=False):
    im = key_green(load(src_name)) if green else key_white(load(src_name))
    bb = bbox(im)
    if bb is None:
        raise RuntimeError("empty " + src_name)
    im = im.crop(bb)
    w0, h0 = im.size
    s = target_h / h0
    nw = max(1, int(round(w0 * s)))
    im = im.resize((nw, target_h), Image.LANCZOS)
    im = grade(im, gain=0.94 - extra_dark)
    pad = 40
    cv = Image.new("RGBA", (nw + pad * 2, target_h + pad), (0, 0, 0, 0))
    cv.alpha_composite(im, (pad, 0))
    # 记录脚底基线（画布底边）
    cv.save(os.path.join(ART, out_name + ".png"))
    print("   ", out_name, cv.size)


# ------------------------------------------------------------- 背景
def crop169(im):
    w, h = im.size
    th = int(w * 9 / 16)
    if th <= h:
        top = (h - th) // 2
        return im.crop((0, top, w, top + th))
    tw = int(h * 16 / 9)
    left = (w - tw) // 2
    return im.crop((left, 0, left + tw, h))


def make_bg(src_name, out_name, flip=False, grade_boost=1.0):
    im = crop169(load(src_name)).resize((W, H), Image.LANCZOS)
    if flip:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    a = np.asarray(im).astype(np.float32) / 255.0
    a = np.clip(a * 0.82, 0, 1)                     # 整体压暗
    a[..., 2] *= 1.06                               # 偏冷
    a[..., 1] *= 1.01
    im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    im = im.filter(ImageFilter.GaussianBlur(0.6))
    im.save(os.path.join(ART, out_name + ".png"))
    print("   ", out_name, im.size)


def make_face(src_name, out_name, dark=0.86):
    im = crop169(load(src_name)).resize((W, H), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32) / 255.0 * dark
    a[..., 2] *= 1.08
    Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).save(os.path.join(ART, out_name + ".png"))
    print("   ", out_name)


print("[1] characters")
make_char("w_player", "c_player")
make_char("w_npc_girl", "c_npc_a")
make_char("w_ghost", "c_ghost_a")
make_char("st_player", "f_player")
make_char("st_ghost_tilt", "f_ghost_tilt")
make_char("g_ref_v3", "f_ghost_eye", green=True)
make_char("g_ref_v3b", "f_ghost_blood", green=True)
make_char("ghost", "f_ghost_veil", green=True)
make_char("w_player", "c_player_b", target_h=int(CH_H * 0.985))   # 动画第二帧（微缩放）

print("[2] backgrounds")
make_bg("cn_corridor", "bg_a")
make_bg("cor_window", "bg_b")
make_bg("cor_end3", "bg_c")
make_bg("cn_corridor", "bg_d", flip=True)

print("[3] jump scares")
make_face("j_face_blank", "j_blank", 0.80)
make_face("j_face_eye", "j_eye", 0.92)
make_face("ghost_face", "j_veil", 0.85)
print("[done art]")
