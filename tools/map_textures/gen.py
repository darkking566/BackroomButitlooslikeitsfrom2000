"""為 Blender 地圖裡缺貼圖的材質生成原創 128px 無縫貼圖（不含任何第三方貼圖內容）。
平均色取自 palette.json（只是色調參考），圖樣全部由程式生成。
用法：cd tools/map_textures && python -I gen.py   -> assets/textures/map_fill/<材質名>.png
"""
import json
import os
import zlib

import numpy as np
from PIL import Image

N = 128
HERE = os.getcwd()  # 請在 tools/map_textures 目錄下執行（專案路徑含中文，__file__ 在部分 shell 會被轉壞）
OUT = os.path.join(HERE, '..', '..', 'assets', 'textures', 'map_fill')
PAL = json.load(open(os.path.join(HERE, 'palette.json')))


def rng_for(name):
    return np.random.default_rng(zlib.crc32(name.encode()))


def fbm(rng, octaves=5, persistence=0.55, lo=2):
    """無縫雜訊：頻域濾波的白噪聲，輸出約 0..1。"""
    out = np.zeros((N, N))
    amp = 1.0
    tot = 0.0
    fx = np.fft.fftfreq(N)[:, None] * N
    fy = np.fft.fftfreq(N)[None, :] * N
    r = np.sqrt(fx ** 2 + fy ** 2)
    for o in range(octaves):
        f = lo * (2 ** o)
        F = np.fft.fft2(rng.standard_normal((N, N))) * np.exp(-(r / f) ** 2)
        n = np.real(np.fft.ifft2(F))
        n = (n - n.mean()) / (n.std() + 1e-9)
        out += amp * n
        tot += amp
        amp *= persistence
    out /= tot
    return np.clip(out * 0.25 + 0.5, 0, 1)


def tint(base, shade):
    b = np.array(base, float)[None, None, :] / 255.0
    return np.clip(b * (0.6 + 0.8 * shade[:, :, None]), 0, 1)


def speckle(rng, amount):
    return (rng.random((N, N)) - 0.5) * amount


def line_mask(period, thick, axis):
    i = np.arange(N)
    m = ((i % period) < thick).astype(float)
    return m[:, None] * np.ones((1, N)) if axis == 0 else np.ones((N, 1)) * m[None, :]


def concrete(rng, base, joints=0, stain=0.5, stripe=False):
    s = fbm(rng, 5) * 0.6 + fbm(rng, 3, lo=1) * stain * 0.5 + 0.1 + speckle(rng, 0.18)
    img = tint(base, s)
    if joints:
        m = np.maximum(line_mask(joints, 1, 0), line_mask(joints, 1, 1))
        img *= (1 - 0.35 * m)[:, :, None]
    if stripe:
        img *= (1 - 0.3 * line_mask(16, 2, 0))[:, :, None]
    return np.clip(img, 0, 1)


def bricks(rng, base, bw=32, bh=16):
    img = np.zeros((N, N, 3))
    var = fbm(rng, 4)
    lum = float(np.mean(base)) / 255.0
    mortar = np.array([0.55, 0.53, 0.5]) * (lum * 1.4 + 0.25)
    for r in range(N // bh):
        off = (bw // 2) if r % 2 else 0
        for c in range(N // bw + 1):
            x0 = c * bw + off
            col = np.clip(np.array(base) / 255.0 * (0.78 + 0.45 * rng.random()), 0, 1)
            for y in range(r * bh, (r + 1) * bh):
                for x in range(x0, x0 + bw):
                    edge = (y - r * bh) < 2 or (x - x0) < 2
                    img[y, x % N] = mortar if edge else col
    img *= (0.8 + 0.4 * var)[:, :, None]
    img += speckle(rng, 0.08)[:, :, None]
    return np.clip(img, 0, 1)


def tiles(rng, base, size=32, grout=0.55):
    img = tint(base, fbm(rng, 3) * 0.3 + 0.5)
    for ty in range(N // size):
        for tx in range(N // size):
            img[ty * size:(ty + 1) * size, tx * size:(tx + 1) * size] *= 0.88 + 0.2 * rng.random()
    m = np.maximum(line_mask(size, 2, 0), line_mask(size, 2, 1))
    g = np.array(base, float) / 255.0 * grout
    img = img * (1 - m[:, :, None]) + g[None, None, :] * m[:, :, None]
    return np.clip(img + speckle(rng, 0.05)[:, :, None], 0, 1)


def metal_panels(rng, base, size=64, rivets=True, brushed=False, dark_seam=0.45):
    s = fbm(rng, 4) * 0.35 + 0.5 + speckle(rng, 0.06)
    if brushed:
        s = s * 0.6 + (rng.random((N, 1)) * np.ones((1, N))) * 0.25 + 0.1
    img = tint(base, s)
    m = np.maximum(line_mask(size, 2, 0), line_mask(size, 2, 1))
    img *= (1 - dark_seam * m)[:, :, None]
    if rivets:
        for y in range(8, N, size):
            for x in range(8, N, size):
                for dy, dx in ((0, 0), (0, size - 16), (size - 16, 0), (size - 16, size - 16)):
                    yy, xx = (y + dy) % N, (x + dx) % N
                    img[yy:yy + 3, xx:xx + 3] *= 1.35
    return np.clip(img, 0, 1)


def door(rng, base):
    img = metal_panels(rng, base, size=128, rivets=False)
    img[20:108, 20:108] *= 0.88
    img[20:22, 20:108] *= 1.3
    img[20:108, 20:22] *= 1.3
    img[106:108, 20:108] *= 0.6
    img[20:108, 106:108] *= 0.6
    img[60:68, 92:100] *= 1.6
    return np.clip(img, 0, 1)


def grate(rng, base):
    img = tint(base, fbm(rng, 3) * 0.3 + 0.55)
    for y in range(4, N, 16):
        for x in range(4, N, 16):
            img[y:y + 10, x:x + 10] = np.array(base) / 255.0 * 0.15
    return img


def duct(rng, base):
    img = tint(base, fbm(rng, 3) * 0.3 + 0.5 + speckle(rng, 0.05))
    img *= (1 - 0.3 * line_mask(32, 3, 0))[:, :, None]
    img *= (1 - 0.15 * line_mask(128, 2, 1))[:, :, None]
    return np.clip(img, 0, 1)


def planks(rng, base, w=16):
    img = np.zeros((N, N, 3))
    for i in range(N // w):
        tone = 0.82 + 0.3 * rng.random()
        grain = fbm(rng, 3, lo=1)
        block = np.array(base, float)[None, None, :] / 255.0 * tone * (0.75 + 0.5 * grain[:, :, None])
        img[i * w:(i + 1) * w] = block[i * w:(i + 1) * w]
    img[::w, :] *= 0.45
    img[1::w, :] *= 0.75
    img += speckle(rng, 0.05)[:, :, None]
    return np.clip(img, 0, 1)


def rock(rng, base):
    y = np.arange(N)[:, None]
    s = fbm(rng, 6, 0.6, lo=3) * 0.7 + 0.25 * np.sin(y * 2 * np.pi * 4 / N + fbm(rng, 2) * 6)
    s = np.clip(s + 0.2, 0, 1)
    return np.clip(tint(base, s) + speckle(rng, 0.08)[:, :, None], 0, 1)


def grass(rng, base):
    s = fbm(rng, 4, lo=4) * 0.5 + rng.random((N, N)) * 0.5
    img = tint(base, s)
    img[:, :, 1] *= 1.0 + 0.2 * fbm(rng, 2)
    return np.clip(img, 0, 1)


def tarpaper(rng, base):
    img = tint(base, fbm(rng, 4) * 0.4 + 0.45 + speckle(rng, 0.2))
    img *= (1 - 0.35 * line_mask(32, 2, 0))[:, :, None]
    return np.clip(img, 0, 1)


def light_panel(rng, cool=False):
    b = np.array([0.93, 0.96, 0.94]) if cool else np.array([0.97, 0.95, 0.85])
    img = np.ones((N, N, 3)) * b
    f = 10
    frame = np.array([0.42, 0.42, 0.4])
    img[:f] = frame
    img[-f:] = frame
    img[:, :f] = frame
    img[:, -f:] = frame
    img[f:-f, f:-f] *= (0.92 + 0.08 * fbm(rng, 2)[f:-f, f:-f])[:, :, None]
    return np.clip(img, 0, 1)


def flat(rng, base, noise=0.04):
    return np.clip(tint(base, np.full((N, N), 0.62) + (fbm(rng, 3) - 0.5) * noise * 6), 0, 1)


def button(rng, base):
    img = flat(rng, base, 0.05)
    img[44:84, 44:84] = np.array([0.55, 0.12, 0.1])
    img[44:46, 44:84] = 0.8
    return np.clip(img, 0, 1)


def build(n):
    r = rng_for(n)
    base = PAL.get(n, (120, 120, 120))
    if n.startswith('BRICKWALL'):
        lum = sum(base) / 3
        b = (min(255, lum * 1.15 + 25), lum * 0.78 + 8, lum * 0.66 + 5)
        return bricks(r, b, bw=(32, 16)[len(n) % 2], bh=(16, 8)[zlib.crc32(n.encode()) % 2])
    if n.startswith('CONCRETESTAIR'):
        return concrete(r, base, stripe=True)
    if n.startswith('CONCRETEFLOOR'):
        return concrete(r, base, joints=64)
    if n.startswith('CONCRETECEILING'):
        return concrete(r, base, joints=32, stain=0.8)
    if n.startswith('CONCRETEWALL'):
        return concrete(r, base, joints=64 if zlib.crc32(n.encode()) % 2 else 0)
    if n.startswith('PLASTERCEILING'):
        return concrete(r, base, stain=0.3)
    if n.startswith('CLIFFFACE'):
        return rock(r, base)
    if n.startswith('TARPAPER'):
        return tarpaper(r, base)
    if n.startswith('TILEFLOOR') or n.startswith('CITADEL_TILEFLOOR'):
        return tiles(r, base, 32 if 'TILEFLOOR003' in n else 16, 0.6)
    if n.startswith('WOODWALL'):
        return planks(r, base)
    if n.startswith('METALDOOR'):
        return door(r, base)
    if n.startswith('METALGRATE'):
        return grate(r, base)
    if n.startswith('METALDUCT'):
        return duct(r, base)
    if n.startswith('METALFREEZER'):
        return metal_panels(r, base, size=128, rivets=False, brushed=True, dark_seam=0.3)
    if n.startswith('METALHULL') or n.startswith('CITADEL_METALWALL'):
        return metal_panels(r, base, size=64, rivets=True, dark_seam=0.6)
    if n.startswith('METALPANEL'):
        return metal_panels(r, base, size=64, rivets=True)
    if n.startswith('FLUORESCENT'):
        return light_panel(r, cool='COOL' in n)
    if n.startswith('WHITE'):
        return flat(r, (235, 235, 235), 0.02)
    if n.startswith('DOORBUTTON'):
        return button(r, base)
    if n.startswith('BUILDING_'):
        return concrete(r, base, joints=64)
    return flat(r, base)


def main():
    os.makedirs(OUT, exist_ok=True)
    names = sorted(set(list(PAL.keys()) + ['FLATGRASS']))
    for n in names:
        img = grass(rng_for(n), (60, 100, 36)) if n == 'FLATGRASS' else build(n)
        Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, n + '.png'))
    print(len(names), 'textures ->', os.path.abspath(OUT))


if __name__ == '__main__':
    main()
