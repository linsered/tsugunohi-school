#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
翌日·课后  asset pipeline
1) 把 Agnes 生成的洋红底精灵抠成透明 PNG，规范化到统一画布（脚底对齐）
2) 程序化生成墙面/地面噪声纹理、天空层
3) 用 numpy 合成全套环境音/音效（无版权依赖）
"""
import os, math, wave, struct
import numpy as np
from PIL import Image, ImageFilter

SRC = r"C:\Users\34015\.workbuddy\agnes-image-mcp\output"
ROOT = r"C:\Users\34015\WorkBuddy\2026-11-17-22-06-13\tsugunohi_school"
ART = os.path.join(ROOT, "assets", "art")
SFX = os.path.join(ROOT, "assets", "audio")
os.makedirs(ART, exist_ok=True)
os.makedirs(SFX, exist_ok=True)

RNG = np.random.default_rng(20261117)


# ---------------------------------------------------------------- chroma key
def key_magenta(im, lo=0.10, hi=0.34, despill=0.35):
    """以四角取样估计背景色，按色距离生成 alpha，并用 over 反混合去掉边缘染色。
    对非纯洋红底（偏品红/带明暗）也有效。"""
    a = np.asarray(im.convert("RGB")).astype(np.float32) / 255.0
    h, w, _ = a.shape
    pad = 8
    corners = np.concatenate([
        a[:pad, :pad].reshape(-1, 3), a[:pad, w - pad:].reshape(-1, 3),
        a[h - pad:, :pad].reshape(-1, 3), a[h - pad:, w - pad:].reshape(-1, 3),
    ])
    bg = np.median(corners, axis=0)
    d = np.linalg.norm(a - bg, axis=-1) / math.sqrt(3.0)
    alpha = np.clip((d - lo) / (hi - lo), 0.0, 1.0)

    # 反混合：observed = fg*a + bg*(1-a)  ->  fg = (observed - bg*(1-a)) / a
    aa = np.clip(alpha, 1e-3, 1.0)[..., None]
    fg = (a - bg * (1.0 - aa)) / aa
    fg = np.clip(fg, 0.0, 1.0)
    # 残余染色（洋红溢出）再往绿通道压一点
    over = np.clip(fg[..., 0] - fg[..., 1], 0, None) + np.clip(fg[..., 2] - fg[..., 1], 0, None)
    w_fix = np.clip(over, 0, 1) * despill
    fg = fg * (1.0 - w_fix[..., None] * np.array([0.6, 0.0, 0.6]))
    fg[..., 1] = np.clip(fg[..., 1] + w_fix * 0.25, 0, 1)

    out = np.concatenate([fg, alpha[..., None]], axis=-1)
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), "RGBA")


def bg_color(im, pad=8):
    a = np.asarray(im.convert("RGB")).astype(np.float32) / 255.0
    h, w, _ = a.shape
    c = np.concatenate([
        a[:pad, :pad].reshape(-1, 3), a[:pad, w - pad:].reshape(-1, 3),
        a[h - pad:, :pad].reshape(-1, 3), a[h - pad:, w - pad:].reshape(-1, 3),
    ])
    return np.median(c, axis=0)


def rgb_to_hsv_np(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    d = mx - mn + 1e-6
    h = np.zeros_like(mx)
    m = mx == r
    h[m] = (60 * ((g - b) / d) % 360)[m]
    m2 = (mx == g) & ~m
    h[m2] = (60 * (2 + (b - r) / d))[m2]
    m3 = (mx == b) & ~m & ~m2
    h[m3] = (60 * (4 + (r - g) / d))[m3]
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0.0)
    return h, s, mx


def kill_shadow(im, band=0.16, hue_tol=50.0, smin=0.12):
    """AI 偶尔会在脚下画一块与背景同色相的暗色投影，按“暗 + 背景色相 + 位于脚部”剔除。"""
    bgh, bgs, _ = rgb_to_hsv_np(bg_color(im)[None, None, :])
    bgh, bgs = float(bgh[0, 0]), float(bgs[0, 0])
    a = np.asarray(im).astype(np.float32) / 255.0
    al = a[..., 3]
    ys, xs = np.where(al > 0.08)
    if len(ys) == 0:
        return im
    y0, y1 = ys.min(), ys.max()
    H = y1 - y0 + 1
    h, s, v = rgb_to_hsv_np(a[..., :3])
    dh = np.abs(((h - bgh + 180.0) % 360.0) - 180.0)
    yy = np.arange(a.shape[0])[:, None]
    in_band = yy > (y0 + H * (1.0 - band))
    mask = in_band & (dh < hue_tol) & (s > smin * 0.6) & (al > 0.07)
    if mask.sum() == 0:
        return im
    # 轻微膨胀，把边缘也带走
    grown = mask.copy()
    grown[1:, :] |= mask[:-1, :]
    grown[:-1, :] |= mask[1:, :]
    grown[:, 1:] |= mask[:, :-1]
    grown[:, :-1] |= mask[:, 1:]
    al = np.where(grown, 0.0, al)
    a[..., 3] = al
    return Image.fromarray((a * 255).astype(np.uint8))


def keep_main_component(im, thresh=24):
    """只保留与顶部（头顶）连通的那一块，用来剔掉 AI 顺手画的地面投影。"""
    from collections import deque
    a = np.array(im)
    al = a[..., 3]
    mask = al > thresh
    h, w = mask.shape
    ys, xs = np.where(mask)
    if len(ys) == 0:
        return im
    top = ys.min()
    start = (int(top), int(xs[ys == top][0]))
    seen = np.zeros_like(mask, bool)
    comp = np.zeros_like(mask, bool)
    dq = deque([start])
    seen[start] = True
    while dq:
        y, x = dq.popleft()
        comp[y, x] = True
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                dq.append((ny, nx))
    a[..., 3] = np.where(comp, al, 0)
    return Image.fromarray(a)


def bbox_of(im):
    a = np.asarray(im)[..., 3]
    ys, xs = np.where(a > 24)
    if len(ys) == 0:
        return None
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def grade(im, sat=0.80, gain=0.96, contrast=1.05, tint=(0.96, 1.00, 1.06)):
    a = np.asarray(im).astype(np.float32) / 255.0
    rgb, al = a[..., :3], a[..., 3:4]
    lum = rgb @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    rgb = np.clip(lum[..., None] + (rgb - lum[..., None]) * sat, 0, 1)
    rgb = np.clip((rgb - 0.5) * contrast + 0.5, 0, 1)
    rgb = np.clip(rgb * gain * np.array(tint, dtype=np.float32), 0, 1)
    return Image.fromarray((np.clip(np.concatenate([rgb, al], -1), 0, 1) * 255).astype(np.uint8), "RGBA")


def normalize(im, target_h, canvas_w, canvas_h, pad_bottom=0, align="body"):
    """裁剪到 bbox，等比缩放到 target_h，脚底对齐画布底部。
    align="body" 时按上半身（头+躯干）alpha 重心水平对齐，避免步幅帧左右抖动。"""
    bb = bbox_of(im)
    if bb is None:
        raise RuntimeError("empty sprite")
    im = im.crop(bb)
    w, h = im.size
    s = target_h / h
    nw = max(1, int(round(w * s)))
    im = im.resize((nw, target_h), Image.LANCZOS)
    cx = nw / 2.0
    if align == "body":
        a = np.asarray(im)[..., 3].astype(np.float32)
        region = a[:max(1, int(target_h * 0.55))]
        col = region.sum(0)
        if col.sum() > 1e-3:
            cx = float((col * np.arange(len(col))).sum() / col.sum())
    canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    x = int(round(canvas_w / 2.0 - cx))
    y = canvas_h - target_h - pad_bottom
    canvas.alpha_composite(im, (x, y))
    return canvas, (x, y, nw, target_h)


def load(name):
    p = os.path.join(SRC, name + ".png")
    if not os.path.exists(p):
        raise FileNotFoundError(p)
    return Image.open(p).convert("RGBA")


# ---------------------------------------------------------------- 1. 角色
print("[1] characters")
CHAR_W, CHAR_H, CHAR_H_PX = 190, 168, 152
# 三帧取自同一张精灵表，保证服装/比例一致
sheet = load("sheet_abc")
SW = sheet.width // 3
for i, out in enumerate(["player_idle", "player_walk1", "player_walk2"]):
    frame = sheet.crop((i * SW, 0, (i + 1) * SW, sheet.height))
    im = key_magenta(frame)
    im = keep_main_component(im)
    im = grade(im, sat=0.82, gain=0.95, contrast=1.04, tint=(0.95, 1.0, 1.07))
    cv, rect = normalize(im, CHAR_H_PX, CHAR_W, CHAR_H)
    cv.save(os.path.join(ART, out + ".png"))
    print("   ", out, rect)

# 怨灵：保留半透明，抠图阈值更宽
gh = key_magenta(load("ghost"), lo=0.20, hi=0.55, despill=0.45)
gh = grade(gh, sat=0.55, gain=0.90, contrast=1.10, tint=(0.90, 1.0, 1.10))
cv, rect = normalize(gh, 300, 200, 316)
cv.save(os.path.join(ART, "ghost.png"))
print("    ghost", rect)

# 怨灵 远景点（小、更淡）
small = cv.resize((100, 158), Image.LANCZOS)
alpha = np.asarray(small).copy()
alpha[..., 3] = (alpha[..., 3].astype(np.float32) * 0.72).astype(np.uint8)
Image.fromarray(alpha).save(os.path.join(ART, "ghost_far.png"))

# ---------------------------------------------------------------- 2. 大图
print("[2] key art")
def crop169(im):
    w, h = im.size
    th = int(w * 9 / 16)
    if th <= h:
        top = (h - th) // 2
        return im.crop((0, top, w, top + th))
    tw = int(h * 16 / 9)
    left = (w - tw) // 2
    return im.crop((left, 0, left + tw, h))

t = crop169(load("title")).convert("RGB")
t.resize((1280, 720), Image.LANCZOS).save(os.path.join(ART, "title.png"))
for n, o in [("cg_bad", "cg_bad"), ("cg_good", "cg_good")]:
    crop169(load(n)).convert("RGB").resize((640, 360), Image.LANCZOS).save(os.path.join(ART, o + ".png"))

# 被划掉脸的集体照 -> 墙上告示
cp = load("classphoto")
cp = cp.crop((int(cp.width * .08), int(cp.height * .1), int(cp.width * .92), int(cp.height * .9)))
cp = grade(cp, sat=0.35, gain=0.62, contrast=1.05, tint=(1.0, 0.98, 0.92))
cp.convert("RGB").resize((104, 70), Image.LANCZOS).save(os.path.join(ART, "classphoto.png"))
print("    title / cg_bad / cg_good / classphoto")


# ---------------------------------------------------------------- 3. 纹理
print("[3] textures")

def value_noise(w, h, cells, rng):
    g = rng.random((cells + 1, cells + 1)).astype(np.float32)
    ys = np.linspace(0, cells, h, endpoint=False)
    xs = np.linspace(0, cells, w, endpoint=False)
    x0, y0 = xs.astype(int), ys.astype(int)
    fx, fy = (xs - x0)[None, :], (ys - y0)[:, None]
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    # 环绕采样保证无缝
    a = g[np.ix_(y0 % cells, x0 % cells)]
    b = g[np.ix_(y0 % cells, (x0 + 1) % cells)]
    c = g[np.ix_((y0 + 1) % cells, x0 % cells)]
    d = g[np.ix_((y0 + 1) % cells, (x0 + 1) % cells)]
    return (a * (1 - fx) * (1 - fy) + b * fx * (1 - fy) + c * (1 - fx) * fy + d * fx * fy)


def fbm(w, h, base=4, octaves=4, rng=RNG):
    out = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        out += value_noise(w, h, base * 2**o, rng) * amp
        tot += amp
        amp *= 0.5
    return out / tot


def tint_noise(n, c0, c1):
    n = n[..., None]
    c0 = np.array(c0, np.float32)
    c1 = np.array(c1, np.float32)
    return (c0 + (c1 - c0) * n).astype(np.uint8)

# 墙面灰泥 128x128 无缝
n = fbm(128, 128, base=2, octaves=5)
n = (n - n.min()) / (n.max() - n.min())
wall = tint_noise(n, (44, 52, 56), (72, 82, 87))
# 斑点污渍
for _ in range(26):
    cx, cy, r = RNG.integers(0, 128), RNG.integers(0, 128), RNG.integers(2, 9)
    yy, xx = np.mgrid[0:128, 0:128]
    d = ((xx - cx) ** 2 + (yy - cy) ** 2) / (r * r)
    m = np.clip(1 - d, 0, 1) ** 2 * 0.35
    wall = (wall * (1 - m[..., None]) + np.array([30, 35, 38], np.float32) * m[..., None]).astype(np.uint8)
Image.fromarray(wall).save(os.path.join(ART, "tex_wall.png"))

# 油毡地面 128x128
n = fbm(128, 128, base=3, octaves=4)
n = (n - n.min()) / (n.max() - n.min())
floor = tint_noise(n, (26, 30, 33), (48, 54, 58))
Image.fromarray(floor).save(os.path.join(ART, "tex_floor.png"))

# 天空（夜晚/黄昏）256x120，水平无缝
sky = np.zeros((120, 256, 3), np.float32)
top = np.array([12, 16, 22], np.float32)
bot = np.array([58, 62, 62], np.float32)
for y in range(120):
    t_ = (y / 119.0) ** 1.4
    sky[y, :, :] = top * (1 - t_) + bot * t_
cloud = fbm(256, 120, base=2, octaves=4)
cloud = (cloud - cloud.min()) / (cloud.max() - cloud.min())
sky = sky + (cloud[..., None] - 0.5) * 14
Image.fromarray(np.clip(sky, 0, 255).astype(np.uint8)).save(os.path.join(ART, "tex_sky.png"))
print("    tex_wall / tex_floor / tex_sky")


# ---------------------------------------------------------------- 4. 音频
print("[4] audio")
SR = 22050

def save_wav(name, data, sr=SR):
    data = np.asarray(data, np.float32)
    if data.ndim == 1:
        data = np.stack([data, data], -1)
    peak = np.max(np.abs(data)) or 1.0
    data = data / peak * 0.92
    pcm = (np.clip(data, -1, 1) * 32767).astype(np.int16)
    p = os.path.join(SFX, name + ".wav")
    with wave.open(p, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((pcm[:, 0] if pcm.ndim > 1 else pcm).tobytes())
    print("    ", name, round(len(pcm) / sr, 2), "s")


def t_axis(dur, sr=SR):
    return np.arange(int(dur * sr), dtype=np.float32) / sr


def env(n, a=0.01, d=0.1, s=0.7, r=0.2, sr=SR):
    a_n, d_n, r_n = int(a * sr), int(d * sr), int(r * sr)
    s_n = max(0, n - a_n - d_n - r_n)
    e = np.concatenate([
        np.linspace(0, 1, max(a_n, 1)),
        np.linspace(1, s, max(d_n, 1)),
        np.full(s_n, s),
        np.linspace(s, 0, max(r_n, 1)),
    ])
    return e[:n] if len(e) >= n else np.pad(e, (0, n - len(e)))


def lp_noise(n, cutoff, sr=SR, order=2):
    """简易一阶低通叠加，cutoff 为归一化系数 0..1"""
    x = RNG.normal(0, 1, n).astype(np.float32)
    for _ in range(order):
        y = np.empty_like(x)
        acc = 0.0
        a = cutoff
        for i in range(n):          # 逐样本（样本量小，可接受）
            acc += a * (x[i] - acc)
            y[i] = acc
        x = y
    return x


def fast_lp(x, cutoff, sr=SR):
    """FFT 二阶低通，cutoff 为归一化截止（0..1），全向量化。"""
    x = np.asarray(x, np.float32)
    n = len(x)
    fc = max(15.0, float(cutoff) * sr * 0.5)
    X = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1.0 / sr)
    H = 1.0 / (1.0 + (freqs / fc) ** 2)
    return np.fft.irfft(X * H, n).astype(np.float32)


def norm(x):
    m = np.max(np.abs(x)) or 1.0
    return x / m

# --- 环境底噪：三个层次，可无缝循环（整数周期）
def drone(dur, f0, layers, noise_amt=0.10, cutoff=0.02, sr=SR):
    n = int(dur * sr)
    t = np.arange(n, dtype=np.float32) / sr
    out = np.zeros(n, np.float32)
    for k, amp in enumerate(layers):
        f = f0 * (k + 1) * (1 + 0.0015 * k)
        ph = 2 * math.pi * f * t
        out += amp * np.sin(ph)
    # 让循环点相位对齐：频率取整到 dur 的整数周期
    nz = fast_lp(RNG.normal(0, 1, n).astype(np.float32), cutoff)
    out = out + nz * noise_amt
    # 缓慢呼吸
    lfo = 0.85 + 0.15 * np.sin(2 * math.pi * (3.0 / dur) * t)
    return out * lfo

save_wav("amb_day", drone(24, 55.0, [1.0, 0.28, 0.14, 0.07], 0.16, 0.035))
save_wav("amb_dusk", drone(24, 47.0, [1.0, 0.36, 0.22, 0.10], 0.22, 0.028))
save_wav("amb_night", drone(26, 38.0, [1.0, 0.20, 0.30, 0.12], 0.13, 0.012))
save_wav("amb_void", drone(24, 29.0, [1.0, 0.50, 0.33, 0.25], 0.30, 0.008))

# --- 脚步：短噪声 + 低频闷响
for i in range(4):
    n = int(0.22 * SR)
    t = t_axis(0.22)
    nz = fast_lp(RNG.normal(0, 1, n).astype(np.float32), 0.35)
    thud = np.sin(2 * math.pi * (70 - i * 6) * t) * np.exp(-t * 26)
    click = fast_lp(RNG.normal(0, 1, n).astype(np.float32), 0.75) * np.exp(-t * 70)
    sig = (nz * np.exp(-t * 18) * 0.55 + thud * 0.7 + click * 0.25) * env(n, 0.002, 0.05, 0.25, 0.15)
    save_wav(f"step{i+1}", sig * 0.55)

# --- 荧光灯嗡鸣
t = t_axis(3.0)
hum = 0.35 * np.sin(2 * math.pi * 100 * t) + 0.18 * np.sin(2 * math.pi * 200 * t + 1.1) + 0.07 * np.sin(2 * math.pi * 300 * t + 2.2)
hum *= 0.7 + 0.3 * np.sin(2 * math.pi * 0.7 * t)
save_wav("hum_light", hum * 0.25)

# --- 学校铃声（威斯敏斯特钟声片段，正弦叠加 + 衰减）
def bell_tone(f, dur, sr=SR, amp=1.0):
    n = int(dur * sr)
    t = np.arange(n, dtype=np.float32) / sr
    s = np.zeros(n, np.float32)
    for k, a in [(1, 1.0), (2.01, 0.45), (3.02, 0.22), (4.07, 0.10), (5.4, 0.05)]:
        s += a * np.sin(2 * math.pi * f * k * t) * np.exp(-t * (2.2 + k * 0.5))
    return s * amp

melody = [523.25, 392.00, 440.00, 349.23]  # C5 G4 A4 F4 —— 威斯敏斯特前四音
seq = np.zeros(int(6.0 * SR), np.float32)
step = int(0.85 * SR)
for i, f in enumerate(melody * 2):
    b = bell_tone(f, 2.6, amp=0.6)
    o = i * step
    seq[o:o + len(b)] += b[:max(0, min(len(b), len(seq) - o))]
save_wav("bell", seq)

# --- 音乐盒（小调，略带失谐，恐怖感）
def musicbox(dur=16.0, sr=SR):
    notes = [659.25, 587.33, 523.25, 587.33, 659.25, 783.99, 698.46, 587.33,
             523.25, 493.88, 523.25, 587.33, 493.88, 440.00, 392.00, 440.00]
    n = int(dur * sr)
    out = np.zeros(n, np.float32)
    slot = dur / len(notes)
    for i, f in enumerate(notes):
        dur_n = 2.4
        nn = int(dur_n * sr)
        t = np.arange(nn, dtype=np.float32) / sr
        det = 1.0 + RNG.normal(0, 0.0016)
        s = (np.sin(2 * math.pi * f * det * t) * 0.7 +
             np.sin(2 * math.pi * f * 3.01 * det * t) * 0.18 +
             np.sin(2 * math.pi * f * 5.4 * det * t) * 0.06)
        s *= np.exp(-t * 3.4)
        s *= np.clip(t * 400, 0, 1)  # 起音
        o = int(i * slot * sr)
        end = min(n, o + nn)
        out[o:end] += s[:end - o]
    # 磁带抖动
    wob = 1 + 0.004 * np.sin(2 * math.pi * 0.6 * np.arange(n) / sr)
    return out * wob

save_wav("musicbox", musicbox())

# --- 心跳
t = t_axis(1.15)
hb = np.zeros(len(t), np.float32)
for off, a in [(0.0, 1.0), (0.22, 0.62)]:
    tt = np.clip(t - off, 0, None)
    hb += a * np.sin(2 * math.pi * 48 * tt) * np.exp(-tt * 22) * (tt > 0)
save_wav("heartbeat", hb)

# --- 门吱呀
dur = 1.4
t = t_axis(dur)
f = 180 + 90 * np.sin(2 * math.pi * 0.7 * t) + 40 * np.sin(2 * math.pi * 3.1 * t)
ph = 2 * math.pi * np.cumsum(f) / SR
creak = np.sin(ph) * 0.5 + fast_lp(RNG.normal(0, 1, len(t)).astype(np.float32), 0.18) * 0.5
creak *= env(len(t), 0.08, 0.3, 0.5, 0.5)
save_wav("door", creak * 0.6)

# --- 跳跃惊吓 stinger
dur = 1.8
t = t_axis(dur)
boom = np.sin(2 * math.pi * np.cumsum(np.linspace(120, 35, len(t))) / SR) * np.exp(-t * 3.2)
nz = RNG.normal(0, 1, len(t)).astype(np.float32)
nz = fast_lp(nz, 0.6) * np.exp(-t * 5.0)
screech_f = np.linspace(2400, 900, len(t)) * (1 + 0.04 * np.sin(2 * math.pi * 11 * t))
screech = np.sin(2 * math.pi * np.cumsum(screech_f) / SR) * np.exp(-t * 6) * 0.35
hit = (boom * 1.0 + nz * 0.9 + screech) * env(len(t), 0.001, 0.02, 0.5, 0.9)
save_wav("stinger", hit)

# --- 耳语（滤波噪声 + 共振峰起伏）
dur = 2.6
t = t_axis(dur)
nz = RNG.normal(0, 1, len(t)).astype(np.float32)
nz = fast_lp(nz, 0.28) - fast_lp(nz, 0.06)
form = 0.4 + 0.6 * (0.5 + 0.5 * np.sin(2 * math.pi * 3.4 * t)) * (0.5 + 0.5 * np.sin(2 * math.pi * 1.7 * t + 1))
wh = nz * form * env(len(t), 0.3, 0.4, 0.6, 0.8)
save_wav("whisper", wh * 0.5)

# --- 水滴
t = t_axis(0.6)
drip = np.sin(2 * math.pi * np.cumsum(np.linspace(900, 1500, len(t))) / SR) * np.exp(-t * 30)
save_wav("drip", drip * 0.4)

# --- 窗框/椅子拖动（zai）
t = t_axis(1.1)
nz = fast_lp(RNG.normal(0, 1, len(t)).astype(np.float32), 0.12)
scrape = nz * (0.6 + 0.4 * np.sin(2 * math.pi * 17 * t)) * env(len(t), 0.05, 0.15, 0.6, 0.4)
save_wav("scrape", scrape * 0.5)

# --- 心跳加速版（循环）
print("[done]")
