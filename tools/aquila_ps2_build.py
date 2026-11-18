import bpy
import os
import math
import numpy as np
from mathutils import Vector

OUT_TEX_DIR = r"c:\Users\dark\Documents\貝克潤ps-2\assets\textures\aquila_ps2"
OUT_GLB_PATH = r"c:\Users\dark\Documents\貝克潤ps-2\assets\models\aquila_ps2_wing.glb"
os.makedirs(OUT_TEX_DIR, exist_ok=True)
os.makedirs(os.path.dirname(OUT_GLB_PATH), exist_ok=True)

# Clean all default objects cleanly in factory startup
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

scene = bpy.context.scene
col = scene.collection
rng = np.random.default_rng(42)


def fbm_2d(w, h, scales=(4, 8, 16, 32)):
    out = np.zeros((h, w), dtype=np.float32)
    amp = 0.5
    for s in scales:
        gh, gw = max(2, h // s), max(2, w // s)
        grid = rng.random((gh, gw)).astype(np.float32)
        ys = np.linspace(0, gh, h, endpoint=False)
        xs = np.linspace(0, gw, w, endpoint=False)
        y0 = np.floor(ys).astype(int) % gh
        y1 = (y0 + 1) % gh
        x0 = np.floor(xs).astype(int) % gw
        x1 = (x0 + 1) % gw
        fy = (ys - np.floor(ys))[:, None]
        fx = (xs - np.floor(xs))[None, :]
        c00 = grid[np.ix_(y0, x0)]
        c10 = grid[np.ix_(y0, x1)]
        c01 = grid[np.ix_(y1, x0)]
        c11 = grid[np.ix_(y1, x1)]
        interp = (c00 * (1 - fx) + c10 * fx) * (1 - fy) + (c01 * (1 - fx) + c11 * fx) * fy
        out += interp * amp
        amp *= 0.5
    out = (out - out.min()) / (out.max() - out.min() + 1e-6)
    return out


def save_rgba_png(name, rgba_u8, colorspace='sRGB'):
    import struct, zlib
    h, w, _ = rgba_u8.shape
    path = os.path.join(OUT_TEX_DIR, f"{name}.png")

    def png_chunk(chunk_type, data):
        chunk = chunk_type + data
        return struct.pack("!I", len(data)) + chunk + struct.pack("!I", zlib.crc32(chunk) & 0xFFFFFFFF)

    raw_rows = b"".join(b"\x00" + rgba_u8[y].tobytes() for y in range(h))
    ihdr = struct.pack("!IIBBBBB", w, h, 8, 6, 0, 0, 0)
    idat = zlib.compress(raw_rows, level=6)
    png_bytes = b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", ihdr) + png_chunk(b"IDAT", idat) + png_chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png_bytes)

    img = bpy.data.images.load(path, check_existing=False)
    img.name = name
    img.colorspace_settings.name = colorspace
    img.pack()
    return img


# ---------------------------------------------------------
# 1. Generate 128px PS2 Textures
# ---------------------------------------------------------
W_F, H_F = 128, 256
grain_f = fbm_2d(W_F, H_F, scales=(2, 4, 8, 16))
puddle_f = fbm_2d(W_F, H_F, scales=(16, 32, 64))

u = np.linspace(0, 1, W_F)[None, :]
v = np.linspace(0, 1, H_F)[:, None]

# Single pair of tire tracks curving gently along the aisle
track_center = 0.63 - 0.09 * v + 0.02 * np.sin(v * 3.0)
track1 = np.exp(-((u - (track_center - 0.085)) / 0.021) ** 2)
track2 = np.exp(-((u - (track_center + 0.085)) / 0.021) ** 2)
tire_mask = (np.clip((track1 + track2) * (0.75 + 0.35 * grain_f), 0.0, 1.0) > 0.42).astype(np.float32)

puddle_bias = (
    0.17 * np.exp(-(((u - 0.35) / 0.22) ** 2 + ((v - 0.20) / 0.16) ** 2)) +
    0.15 * np.exp(-(((u - 0.86) / 0.12) ** 2 + ((v - 0.35) / 0.20) ** 2)) +
    0.15 * np.exp(-(((u - 0.56) / 0.20) ** 2 + ((v - 0.72) / 0.18) ** 2))
)
puddle_mask = ((puddle_f + puddle_bias) > 0.63).astype(np.float32)
wet_mask = np.maximum(puddle_mask, tire_mask)

dry_rgb = np.stack([
    98 + grain_f * 36,
    97 + grain_f * 34,
    92 + grain_f * 32,
], axis=-1)
wet_rgb = np.stack([
    30 + grain_f * 10,
    33 + grain_f * 11,
    35 + grain_f * 12,
], axis=-1)
floor_rgb = dry_rgb * (1.0 - wet_mask[..., None]) + wet_rgb * wet_mask[..., None]
floor_rgb = np.clip(np.round(floor_rgb / 6.0) * 6.0, 0, 255).astype(np.uint8)
floor_rgba = np.concatenate([floor_rgb, np.full((H_F, W_F, 1), 255, dtype=np.uint8)], axis=-1)
img_floor_col = save_rgba_png("ps2_aquila_floor_col", floor_rgba, 'sRGB')

rough_u8 = np.where(wet_mask > 0.5, 18, 232).astype(np.uint8)
rough_rgba = np.stack([rough_u8, rough_u8, rough_u8, np.full_like(rough_u8, 255)], axis=-1)
img_floor_rough = save_rgba_png("ps2_aquila_floor_rough", rough_rgba, 'Non-Color')

# 1B. Dirty Concrete Pillar Texture (128x128) + Hero "F"
S_P = 128
p_noise = fbm_2d(S_P, S_P, scales=(2, 4, 16, 32))
row_t = np.linspace(0, 1, S_P)[:, None]
damp = np.clip((row_t - 0.55) / 0.45, 0.0, 1.0)
streak = fbm_2d(S_P, S_P, scales=(2, 32))
stain = np.clip(p_noise * 0.65 + streak * 0.35 - damp * 0.36, 0.14, 0.95)
base_p = 74 + stain * 115
pillar_rgb = np.stack([base_p, base_p * 0.99, base_p * 0.95], axis=-1)
pillar_rgb = np.clip(np.round(pillar_rgb / 5.0) * 5.0, 0, 255).astype(np.uint8)
pillar_rgba = np.concatenate([pillar_rgb, np.full((S_P, S_P, 1), 255, dtype=np.uint8)], axis=-1)
img_pillar = save_rgba_png("ps2_aquila_pillar", pillar_rgba, 'sRGB')

pillar_f_rgba = pillar_rgba.copy()
pillar_f_rgba[36:58, 35:39, :3] = [24, 24, 22]
pillar_f_rgba[36:40, 35:48, :3] = [24, 24, 22]
pillar_f_rgba[45:49, 35:45, :3] = [24, 24, 22]
img_pillar_f = save_rgba_png("ps2_aquila_pillar_f", pillar_f_rgba, 'sRGB')

# 1C. Corrugated Sheet Metal Texture (128x128)
W_C, H_C = 128, 128
cx = np.linspace(0, 1, W_C)[None, :]
cy = np.linspace(0, 1, H_C)[:, None]
rib_wave = 0.5 + 0.5 * np.sin(cx * 2.0 * math.pi * 16.0)
c_noise = fbm_2d(W_C, H_C, scales=(4, 16))
bottom_dirt = np.clip((cy - 0.72) / 0.28, 0.0, 1.0)
c_val = (118 + rib_wave * 42 + (c_noise - 0.5) * 28) * (1.0 - 0.42 * bottom_dirt)
corr_rgb = np.stack([c_val, c_val * 0.99, c_val * 0.94], axis=-1)
corr_rgb = np.clip(np.round(corr_rgb / 5.0) * 5.0, 0, 255).astype(np.uint8)
corr_rgba = np.concatenate([corr_rgb, np.full((H_C, W_C, 1), 255, dtype=np.uint8)], axis=-1)
img_corrugated = save_rgba_png("ps2_aquila_corrugated", corr_rgba, 'sRGB')


# ---------------------------------------------------------
# 2. Build Materials
# ---------------------------------------------------------
def make_tex_mat(name, col_img, rough_img=None, rough_val=0.88, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = col_img
    tex.interpolation = 'Closest'
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])

    if rough_img is not None:
        rtex = nt.nodes.new("ShaderNodeTexImage")
        rtex.image = rough_img
        rtex.interpolation = 'Closest'
        nt.links.new(rtex.outputs["Color"], bsdf.inputs["Roughness"])
    else:
        bsdf.inputs["Roughness"].default_value = rough_val
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


def make_flat_mat(name, rgba, rough=0.85, emit=None, emit_strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = rough
    if emit is not None:
        bsdf.inputs["Emission Color"].default_value = emit
        bsdf.inputs["Emission Strength"].default_value = emit_strength
    return mat


mat_floor = make_tex_mat("Mat_PS2_Floor", img_floor_col, img_floor_rough)
mat_pillar = make_tex_mat("Mat_PS2_Pillar", img_pillar, rough_val=0.90)
mat_pillar_f = make_tex_mat("Mat_PS2_PillarF", img_pillar_f, rough_val=0.90)
mat_corrugated = make_tex_mat("Mat_PS2_Corrugated", img_corrugated, rough_val=0.55, metallic=0.18)
mat_guard = make_flat_mat("Mat_PS2_YellowGuard", (0.58, 0.44, 0.08, 1.0), rough=0.65)
mat_pipe = make_flat_mat("Mat_PS2_Pipe", (0.62, 0.63, 0.60, 1.0), rough=0.45)
mat_valve = make_flat_mat("Mat_PS2_RedValve", (0.62, 0.07, 0.06, 1.0), rough=0.45)
mat_wire = make_flat_mat("Mat_PS2_Wire", (0.04, 0.04, 0.04, 1.0), rough=0.85)
mat_tube = make_flat_mat("Mat_PS2_LightBar", (0.95, 0.98, 1.0, 1.0), rough=0.1, emit=(0.92, 0.97, 1.0, 1.0), emit_strength=6.0)


def add_box(name, center, size, mat, front_mat=None):
    mesh = bpy.data.meshes.new(name)
    hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    cx, cy, cz = center
    verts = [
        (cx - hx, cy - hy, cz - hz),
        (cx + hx, cy - hy, cz - hz),
        (cx + hx, cy + hy, cz - hz),
        (cx - hx, cy + hy, cz - hz),
        (cx - hx, cy - hy, cz + hz),
        (cx + hx, cy - hy, cz + hz),
        (cx + hx, cy + hy, cz + hz),
        (cx - hx, cy + hy, cz + hz),
    ]
    faces = [
        (0, 1, 5, 4),
        (2, 3, 7, 6),
        (3, 0, 4, 7),
        (1, 2, 6, 5),
        (4, 5, 6, 7),
        (3, 2, 1, 0),
    ]
    mesh.from_pydata(verts, [], faces)
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for fi, poly in enumerate(mesh.polygons):
        uvs = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
        for li, uv in zip(poly.loop_indices, uvs):
            uv_layer.data[li].uv = uv
        poly.material_index = 1 if (front_mat and fi == 0) else 0
    mesh.materials.append(mat)
    if front_mat:
        mesh.materials.append(front_mat)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    col.objects.link(obj)
    return obj


# ---------------------------------------------------------
# 3. Build Aquila Wing Geometry (Blender +Y = Godot -Z forward!)
# ---------------------------------------------------------
fl_mesh = bpy.data.meshes.new("AquilaWetFloorOverlay")
nx, ny = 4, 8
x_min, x_max = -6.8, 4.3
y_min, y_max = -3.5, 17.5
fl_verts = []
fl_faces = []
for iy in range(ny + 1):
    ty = iy / ny
    fy = y_min + ty * (y_max - y_min)
    for ix in range(nx + 1):
        tx = ix / nx
        fx = x_min + tx * (x_max - x_min)
        fl_verts.append((fx, fy, 0.004))
for iy in range(ny):
    for ix in range(nx):
        i0 = iy * (nx + 1) + ix
        i1 = i0 + 1
        i2 = i0 + (nx + 1) + 1
        i3 = i0 + (nx + 1)
        fl_faces.append((i0, i1, i2, i3))
fl_mesh.from_pydata(fl_verts, [], fl_faces)
uv_fl = fl_mesh.uv_layers.new(name="UVMap")
for poly in fl_mesh.polygons:
    for li, vi in zip(poly.loop_indices, poly.vertices):
        vx, vy, _ = fl_verts[vi]
        uv_fl.data[li].uv = ((vx - x_min) / (x_max - x_min), (vy - y_min) / (y_max - y_min))
fl_mesh.materials.append(mat_floor)
fl_mesh.update()
col.objects.link(bpy.data.objects.new("AquilaWetFloorOverlay", fl_mesh))

ramp_mesh = bpy.data.meshes.new("AquilaLeftRamp")
xL, xR = -6.8, -4.4
y0, y1 = -1.5, 16.5
z0_top, z1_top = 0.08, 2.35
thick = 0.42
rv = [
    (xL, y0, z0_top - thick), (xR, y0, z0_top - thick), (xR, y1, z1_top - thick), (xL, y1, z1_top - thick),
    (xL, y0, z0_top),         (xR, y0, z0_top),         (xR, y1, z1_top),         (xL, y1, z1_top),
]
rf = [(4, 5, 6, 7), (1, 2, 6, 5), (3, 0, 4, 7), (0, 1, 5, 4), (2, 3, 7, 6), (3, 2, 1, 0)]
ramp_mesh.from_pydata(rv, [], rf)
uv_r = ramp_mesh.uv_layers.new(name="UVMap")
for poly in ramp_mesh.polygons:
    for li, uv in zip(poly.loop_indices, [(0, 0), (2, 0), (2, 1), (0, 1)]):
        uv_r.data[li].uv = uv
ramp_mesh.materials.append(mat_pillar)
ramp_mesh.update()
col.objects.link(bpy.data.objects.new("AquilaLeftRamp", ramp_mesh))

curb_mesh = bpy.data.meshes.new("AquilaRampCurb")
cv = [
    (xR - 0.18, y0, z0_top), (xR, y0, z0_top), (xR, y1, z1_top), (xR - 0.18, y1, z1_top),
    (xR - 0.18, y0, z0_top + 0.52), (xR, y0, z0_top + 0.52), (xR, y1, z1_top + 0.52), (xR - 0.18, y1, z1_top + 0.52),
]
curb_mesh.from_pydata(cv, [], rf)
uv_c = curb_mesh.uv_layers.new(name="UVMap")
for poly in curb_mesh.polygons:
    for li, uv in zip(poly.loop_indices, [(0, 0), (3, 0), (3, 0.5), (0, 0.5)]):
        uv_c.data[li].uv = uv
curb_mesh.materials.append(mat_pillar)
curb_mesh.update()
col.objects.link(bpy.data.objects.new("AquilaRampCurb", curb_mesh))
add_box("RampSupport_0", (-5.6, 12.0, 0.8), (0.85, 0.85, 1.6), mat_pillar)

for idx, py in enumerate([3.0, 9.5, 16.0]):
    is_hero = (idx == 0)
    add_box(f"AquilaPillar_{idx}", (-2.35, py, 1.65), (1.35, 1.35, 3.3), mat_pillar, mat_pillar_f if is_hero else None)
    add_box(f"AquilaDropCap_{idx}", (-2.35, py, 3.42), (3.1, 3.1, 0.28), mat_pillar)
    add_box(f"GuardA_{idx}", (-1.66, py - 0.66, 0.58), (0.08, 0.08, 1.16), mat_guard)
    add_box(f"GuardB_{idx}", (-1.66, py + 0.66, 0.58), (0.08, 0.08, 1.16), mat_guard)
    add_box(f"PillarBar_{idx}", (-1.64, py - 0.12, 2.05), (0.07, 0.16, 1.25), mat_tube)

wall_mesh = bpy.data.meshes.new("AquilaCorrugatedWall")
wv, wf = [], []
step = 0.35
n_seg = int((16.5 - (-1.5)) / step)
for i in range(n_seg + 1):
    wy = -1.5 + i * step
    wx = 4.22 - (0.07 if i % 2 == 1 else 0.0)
    wv.append((wx, wy, 0.0))
    wv.append((wx, wy, 2.75))
for i in range(n_seg):
    b = i * 2
    wf.append((b, b + 1, b + 3, b + 2))
wall_mesh.from_pydata(wv, [], wf)
uv_w = wall_mesh.uv_layers.new(name="UVMap")
for i, poly in enumerate(wall_mesh.polygons):
    u0 = (i * 0.25) % 1.0
    u1 = u0 + 0.25
    for li, uv in zip(poly.loop_indices, [(u0, 0.0), (u0, 1.0), (u1, 1.0), (u1, 0.0)]):
        uv_w.data[li].uv = uv
wall_mesh.materials.append(mat_corrugated)
wall_mesh.update()
col.objects.link(bpy.data.objects.new("AquilaCorrugatedWall", wall_mesh))

add_box("RightHeader", (4.26, 7.5, 3.18), (0.18, 18.0, 0.85), mat_pillar)
for idx, ly in enumerate([0.5, 7.5, 14.5]):
    add_box(f"RightBar_{idx}", (4.10, ly, 2.05), (0.08, 0.18, 1.22), mat_tube)

for w_idx in range(2):
    wmesh = bpy.data.meshes.new(f"HangingWire_{w_idx}")
    wverts, wfaces = [], []
    segs = 14
    for k in range(segs + 1):
        wy = -1.2 + k * (17.4 / segs)
        sag = abs(math.sin(k * 0.85 + w_idx * 1.3)) * 0.24
        wx = 4.08 - w_idx * 0.03
        wz = 2.72 - sag - w_idx * 0.05
        wverts.append((wx, wy, wz))
        wverts.append((wx, wy, wz - 0.035))
    for k in range(segs):
        b = k * 2
        wfaces.append((b, b + 1, b + 3, b + 2))
    wmesh.from_pydata(wverts, [], wfaces)
    wmesh.materials.append(mat_wire)
    wmesh.update()
    col.objects.link(bpy.data.objects.new(f"HangingWire_{w_idx}", wmesh))


def add_pipe(name, p1, p2, r=0.045):
    v1, v2 = Vector(p1), Vector(p2)
    diff = v2 - v1
    mid = (v1 + v2) * 0.5
    bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=r, depth=diff.length, location=mid)
    obj = bpy.context.active_object
    obj.name = name
    obj.rotation_euler = diff.to_track_quat('Z', 'Y').to_euler()
    obj.data.materials.append(mat_pipe)
    return obj


add_pipe("Pipe_Main_A", (-1.1, -2.0, 3.08), (-1.1, 17.0, 3.08), 0.05)
add_pipe("Pipe_Main_B", (1.6, -2.0, 3.08), (1.6, 17.0, 3.08), 0.045)
for idx, py in enumerate([0.0, 4.5, 9.0, 13.5, 16.5]):
    add_pipe(f"Pipe_Cross_{idx}", (-5.5, py, 2.98), (4.15, py, 2.98), 0.032)
    add_box(f"SprinklerValve_{idx}", (-1.1, py, 2.96), (0.11, 0.11, 0.10), mat_valve)
    add_box(f"SprinklerValveB_{idx}", (1.6, py, 2.96), (0.10, 0.10, 0.09), mat_valve)

total_tris = sum(len(o.data.polygons) * 2 for o in bpy.data.objects if o.type == 'MESH')
print(f"Total estimated polys/tris: ~{total_tris}")

bpy.ops.object.select_all(action='DESELECT')
for o in bpy.data.objects:
    if o.type == 'MESH':
        o.select_set(True)

bpy.ops.export_scene.gltf(
    filepath=OUT_GLB_PATH,
    export_format='GLB',
    use_selection=True,
    export_yup=True,
    export_apply=True,
)
print("Exported PS2 Aquila wing GLB:", OUT_GLB_PATH)
