"""為 gm_brmovie_complete 地圖的每個材質生成原創 128px 貼圖（不使用、不包含任何第三方貼圖內容）。
輸入 palette_movie.json：{材質名: [r,g,b]}，平均色只當色調參考；圖樣全部程式生成。
用法：cd tools/map_textures && python gen_movie.py  -> assets/textures/movie_map/<材質名>.png
"""
import json
import os
import zlib

import numpy as np
from PIL import Image

import gen
from gen import N, fbm, rng_for, tint, speckle

OUT = os.path.join(gen.HERE, '..', '..', 'assets', 'textures', 'movie_map')
PAL = json.load(open(os.path.join(gen.HERE, 'palette_movie.json')))
RGB = tuple


def stripes(img, period, thick, axis, k):
    m = gen.line_mask(period, thick, axis)[:, :, None]
    return np.clip(img * (1 - m * (1 - k)), 0, 1)


def carpet(rng, base):
    s = fbm(rng, 4, lo=3) * 0.5 + 0.25 + speckle(rng, 0.35)
    return tint(base, s)


def wallpaper(rng, base, kind):
    s = fbm(rng, 3, lo=2) * 0.3 + 0.55 + speckle(rng, 0.04)
    img = tint(base, s)
    if kind == 'stripe':
        img = stripes(img, 16, 5, 1, 0.82)
    elif kind == 'lines':
        img = stripes(img, 8, 1, 1, 0.75)
    elif kind == 'dots':
        y, x = np.mgrid[0:N, 0:N]
        m = (((x % 16) - 8) ** 2 + ((y % 16) - 8) ** 2 < 5).astype(float)[:, :, None]
        img = np.clip(img * (1 - m * 0.22), 0, 1)
    else:  # 古典花紋：菱形格 + 小點
        y, x = np.mgrid[0:N, 0:N]
        d = (np.abs((x % 32) - 16) + np.abs((y % 32) - 16)) % 16
        m = (d < 2).astype(float)[:, :, None]
        img = np.clip(img * (1 - m * 0.2), 0, 1)
    return img


def asphalt(rng, base):
    s = fbm(rng, 5, lo=4) * 0.4 + 0.4 + speckle(rng, 0.45)
    return tint(base, s)


def corrugated(rng, base):
    s = fbm(rng, 4, lo=2) * 0.25 + 0.55
    img = tint(base, s)
    x = np.arange(N)
    ridge = (0.82 + 0.18 * np.sin(x / 4.0 * np.pi / 2))[None, :, None]
    return np.clip(img * ridge, 0, 1)


def blotch(rng, base, thresh=0.52, soft=0.1):
    """污漬/裂縫類貼花：RGBA，alpha 由雜訊閾值決定。"""
    n = fbm(rng, 5, lo=2)
    a = np.clip((n - thresh) / soft, 0, 1) * 0.75
    rgb = np.ones((N, N, 3)) * (np.array(base, float) / 255.0)[None, None, :] * 0.5
    return np.dstack([rgb, a])


def crack(rng, base):
    y, x = np.mgrid[0:N, 0:N]
    path = (N / 2 + 18 * np.sin(x / 11.0) + 9 * np.sin(x / 4.3 + 2)).astype(float)
    d = np.abs(y - path) - fbm(rng, 4, lo=3) * 3
    a = np.clip(1 - d / 1.6, 0, 1) * 0.9
    rgb = np.ones((N, N, 3)) * 0.05
    return np.dstack([rgb, a])


def glass(rng, base):
    rgb = np.ones((N, N, 3)) * (np.array(base, float) / 255.0 * 0.6 + 0.25)[None, None, :]
    a = np.full((N, N), 0.28) + fbm(rng, 3, lo=2) * 0.1
    return np.dstack([rgb, a])


def chainlink(rng, base):
    y, x = np.mgrid[0:N, 0:N]
    d = np.minimum(((x + y) % 16), ((x - y) % 16))
    a = (d < 2).astype(float)
    rgb = np.ones((N, N, 3)) * 0.5
    return np.dstack([rgb, a])


def leaves(rng, base):
    n = fbm(rng, 5, lo=4) + speckle(rng, 0.3)
    a = (n > 0.5).astype(float)
    g = tint(base, fbm(rng, 3, lo=3) * 0.8 + 0.1)
    return np.dstack([g, a])


def rug(rng, base):
    img = carpet(rng, base)
    border = np.zeros((N, N, 1))
    border[:8] = border[-8:] = 1
    border[:, :8] = border[:, -8:] = 1
    return np.clip(img * (1 - border * 0.45) + border * 0.12, 0, 1)


def poster(rng, base):
    """海報/標示：底色 + 色塊標題 + 幾行假文字（只有色條，沒有任何真實字樣）。"""
    img = tint(base, fbm(rng, 3, lo=2) * 0.2 + 0.6)
    img[:6] = img[-6:] = img[:, :6] = img[:, -6:] = 0.9
    hue = np.array([rng.random(), rng.random() * 0.6, rng.random()]) * 0.8 + 0.1
    img[14:40, 14:N - 14] = hue
    for i, yy in enumerate(range(52, N - 20, 10)):
        w = int(rng.integers(30, N - 28))
        img[yy:yy + 4, 14:14 + w] = 0.15
    return img


def build(n, avg):
    u = n.upper()
    r = rng_for(n)
    base = tuple(avg) if avg else (120, 120, 120)

    def has(*k):
        return any(x in u for x in k)

    if has('SKY', 'TOOLS', 'PI_WINDOW') or n == 'Material':
        return np.dstack([np.zeros((N, N, 3)), np.zeros((N, N))])
    if has('GLASS', 'DEV_WATER', 'POOLSROOMSWATER', 'POOLROOMSWATER'):
        return glass(r, base)
    if has('CRACK'):
        return crack(r, base)
    if has('STAIN', 'RUST_PATCH', 'LEAKING', 'DRAINAGE', 'BURN', 'OIL_', 'SPLATTER', 'DEBRIS', 'HOLES', 'DECAL_PAINT', 'UNBREAKABLE'):
        return blotch(r, base)
    if has('CHAINLINK', 'FENCE'):
        return chainlink(r, base)
    if has('IVY', 'LEAVES', 'TREES'):
        return leaves(r, base)
    if has('RUG'):
        return rug(r, base)
    if has('POSTER', 'PAPERS', 'PHOTOS', 'MURAL', 'SIGN', 'NOTICE', 'LOGO', 'EVERYTHINGMUSTGO', 'GUARANTEED', 'SPLENDOR',
           'STAYINCHARACTER', 'CLARK', 'PARSONS', 'FLANNEL', 'WARNING', 'RESTRICTED', 'HANDYPARKING', 'NOPARKING',
           'ARROW', 'XMARK', 'INTERCOM', 'SURVEILLANCE', 'NOSIGNAL', 'OFFDESKTOP', 'FIREALARM', 'EXTINGUSHER', 'DANGER',
           'TOILETS', 'RESTROOMS', 'SWITCH', 'POWEROUTLET', 'MTN_', 'SIO_', 'MORE', 'WIDESIGN', 'BACKROOMSIGN', 'CALENDAR'):
        return poster(r, base)
    if has('LIGHT_NEON', 'LIGHTS_ON', 'FLU', 'BLINDS_ILLUM', 'LIGHTS_OFF', '75OFF'):
        return gen.light_panel(r, cool=False) if 'OFF' not in u else gen.flat(r, base, 0.03)
    if has('ASPHALT', 'ROAD', 'PAVEMENT', 'PI_CURB'):
        return asphalt(r, base)
    if has('SIDEWALK', 'CONCRETE_FLOOR', 'CONCRETEFLOOR', 'CONCRETE_BTS', 'NUKFLOOR', 'TRAIN_CEMENT'):
        return gen.concrete(r, base, joints=64)
    if has('GRASS', 'DIRT', 'GROUND', 'ROCKS'):
        return gen.grass(r, (60, 100, 36)) if 'GRASS' in u else gen.rock(r, base)
    if has('CARPET', 'BRCARPET', 'OFFFLR', 'CSREV_OFFFLRC', 'MILFLR', 'MILRUG'):
        return carpet(r, base)
    if has('WALLPAPER'):
        k = 'stripe' if 'KANE' in u else 'lines' if 'LINES' in u else 'dots' if 'DOTS' in u else 'damask'
        return wallpaper(r, base, k)
    if has('BRICK'):
        return gen.bricks(r, base, bw=32, bh=16)
    if has('TILE', 'POOLTILE', 'INTERIORTILE'):
        return gen.tiles(r, base, 16, 0.6)
    if has('WOODFLOOR', 'WOOD', 'PWOOD', 'CABINET', 'SIDING', 'DOORTRIM', 'DOOR_2', 'WGH_FLOOR', 'XEN_VORT'):
        return gen.planks(r, base)
    if has('CORRUGATED', 'METALROOF', 'GARAGEDOOR', 'SHUTTERS', 'GASWORKS', 'FL_GASWORKS'):
        return corrugated(r, base)
    if has('GRATE', 'VENT'):
        return gen.grate(r, base)
    if has('DOOR'):
        return gen.door(r, base)
    if has('PIPE', 'RAIL', 'DUCT'):
        return gen.duct(r, base)
    if has('METAL', 'CRATE', 'HULL', 'NUKE', 'DEV_RAM', 'TNNL', 'TRAIN', 'BEAM'):
        return gen.metal_panels(r, base, size=64, rivets=True)
    if has('CLIFF', 'ROCK', 'MTN'):
        return gen.rock(r, base)
    if has('TARP'):
        return gen.tarpaper(r, base)
    if has('CEILING'):
        return gen.concrete(r, base, joints=32, stain=0.5)
    # 牆面灰泥 / 混凝土 / 其他
    return gen.concrete(r, base, joints=0, stain=0.4)


def main():
    os.makedirs(OUT, exist_ok=True)
    cnt = 0
    for n, avg in PAL.items():
        img = build(n, avg)
        if img.shape[2] == 3:
            img = np.dstack([img, np.ones((N, N))])
        if not any(k in n.upper() for k in ('LIGHT', 'FLU', '75OFF')):  # 配合遊戲的昏暗風格：降飽和、壓暗
            rgb = img[:, :, :3]
            g = rgb.mean(2, keepdims=True)
            img[:, :, :3] = (g + (rgb - g) * 0.6) * 0.78
        Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), 'RGBA').save(os.path.join(OUT, n + '.png'))
        cnt += 1
    print(cnt, 'textures ->', os.path.abspath(OUT))


if __name__ == '__main__':
    main()
