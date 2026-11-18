import bpy
import os
import math
import struct
import zlib
import numpy as np

OUT_TEX_DIR = r"c:\Users\dark\Documents\貝克潤ps-2\assets\textures\north_corridor_ps2"
OUT_GLB_PATH = r"c:\Users\dark\Documents\貝克潤ps-2\assets\models\north_corridor_ps2.glb"
os.makedirs(OUT_TEX_DIR, exist_ok=True)
os.makedirs(os.path.dirname(OUT_GLB_PATH), exist_ok=True)

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

scene = bpy.context.scene
col = scene.collection
rng = np.random.default_rng(108)


def fbm_2d(w, h, scales=(2, 4, 16, 32)):
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

# 1A. Concrete Floor (128x256) with rectangular expansion joints + damp foreground patch + light sheen lane
W_F, H_F = 128, 256
grain_f = fbm_2d(W_F, H_F, scales=(2, 4, 8, 16))
damp_n = fbm_2d(W_F, H_F, scales=(8, 16, 32))

u = np.linspace(0, 1, W_F)[None, :]
v = np.linspace(0, 1, H_F)[:, None]

# Joint grid (matched cleanly across the 20m x 14m floor slab)
seam_u = np.zeros_like(u)
for su in [0.22, 0.38, 0.54, 0.72]:
    seam_u = np.maximum(seam_u, (np.abs(u - su) < 0.009).astype(np.float32))
seam_v = np.zeros_like(v)
for sv in [0.16, 0.34, 0.52, 0.70, 0.88]:
    seam_v = np.maximum(seam_v, (np.abs(v - sv) < 0.006).astype(np.float32))
joint_mask = np.maximum(seam_u, seam_v)

# Damp spots & wet foreground splash near x ~ -0.3 (u ~ 0.48), y ~ 2.5..4.5 -> PNG bottom (v ~ 0.77 since UV v=0 at y=0)
wet_spot_fg = np.exp(-(((u - 0.48) / 0.085) ** 2 + ((v - 0.77) / 0.075) ** 2))
wet_spot_mid = np.exp(-(((u - 0.47) / 0.065) ** 2 + ((v - 0.42) / 0.16) ** 2))
puddle_mask = ((wet_spot_fg * (0.7 + 0.5 * damp_n)) > 0.46).astype(np.float32)
sheen_lane = np.clip(wet_spot_mid * 0.8 + 0.25 * damp_n, 0.0, 1.0)

dry_rgb = np.stack([
    108 + grain_f * 26 - joint_mask * 30,
    103 + grain_f * 24 - joint_mask * 29,
    94 + grain_f * 22 - joint_mask * 27,
], axis=-1)
wet_rgb = np.stack([
    56 + grain_f * 14,
    53 + grain_f * 13,
    48 + grain_f * 12,
], axis=-1)
floor_rgb = dry_rgb * (1.0 - puddle_mask[..., None]) + wet_rgb * puddle_mask[..., None]
floor_rgb = np.clip(np.round(floor_rgb / 5.0) * 5.0, 0, 255).astype(np.uint8)
floor_rgba = np.concatenate([floor_rgb, np.full((H_F, W_F, 1), 255, dtype=np.uint8)], axis=-1)
img_floor_col = save_rgba_png("ps2_nc_floor_col", floor_rgba, 'sRGB')

# Roughness: concrete sheen in lane (0.45), damp foreground puddle (0.12), dry concrete (0.86)
rough_val = 220.0 - sheen_lane * 95.0
rough_u8 = np.where(puddle_mask > 0.5, 28.0, rough_val).clip(18, 240).astype(np.uint8)
rough_rgba = np.stack([rough_u8, rough_u8, rough_u8, np.full_like(rough_u8, 255)], axis=-1)
img_floor_rough = save_rgba_png("ps2_nc_floor_rough", rough_rgba, 'Non-Color')

# 1B. Concrete Wall (128x128) - warm olive-grey raw plaster/concrete with bottom grime
S = 128
w_noise = fbm_2d(S, S, scales=(2, 8, 16, 32))
row_t = np.linspace(0, 1, S)[:, None]
bottom_grime = np.clip((row_t - 0.72) / 0.28, 0.0, 1.0)
top_soot = np.clip((0.18 - row_t) / 0.18, 0.0, 1.0)
val_w = 104 + w_noise * 40 - bottom_grime * 24 - top_soot * 18
wall_rgb = np.stack([val_w * 1.02, val_w * 0.99, val_w * 0.92], axis=-1)
wall_rgb = np.clip(np.round(wall_rgb / 5.0) * 5.0, 0, 255).astype(np.uint8)
wall_rgba = np.concatenate([wall_rgb, np.full((S, S, 1), 255, dtype=np.uint8)], axis=-1)
img_wall = save_rgba_png("ps2_nc_wall", wall_rgba, 'sRGB')

# 1C. Hero Seepage Pier Wall (128x128) - distinct vertical water seepage stain down near-left edge
col_t = np.linspace(0, 1, S)[None, :]
streak_n = fbm_2d(S, S, scales=(2, 16, 32))
# Stain starts top-leftish of pier (u ~ 0.28) and trickles down with irregular drips
drip_center = 0.27 + (streak_n - 0.5) * 0.09
drip_mask = np.exp(-((col_t - drip_center) / 0.065) ** 2) * np.clip((row_t - 0.05) / 0.25, 0.0, 1.0)
seep_strength = np.clip(drip_mask * (0.65 + 0.55 * streak_n), 0.0, 0.88)
pier_rgb = wall_rgb.astype(np.float32) * (1.0 - seep_strength[..., None] * 0.58)
pier_rgb = np.clip(np.round(pier_rgb / 5.0) * 5.0, 0, 255).astype(np.uint8)
pier_rgba = np.concatenate([pier_rgb, np.full((S, S, 1), 255, dtype=np.uint8)], axis=-1)
img_pier_seep = save_rgba_png("ps2_nc_pier_seep", pier_rgba, 'sRGB')

# 1D. Steel Utility Fire Door (128x128)
door_rgba = np.zeros((S, S, 4), dtype=np.uint8)
door_noise = fbm_2d(S, S, scales=(4, 16))
d_val = 148 + door_noise * 24
door_rgb = np.stack([d_val * 0.97, d_val * 0.99, d_val * 1.02], axis=-1)
# Dark frame border
door_rgb[:6, :, :] = 76
door_rgb[:, :7, :] = 76
door_rgb[:, -7:, :] = 76
# Door leaf inner shadow seam
door_rgb[6:10, 7:-7, :] = 92
door_rgb[10:, 7:10, :] = 104
door_rgb[10:, -10:-7, :] = 104
# Small white placard upper center & black lever handle on right
door_rgb[28:40, 52:76, :] = [190, 192, 186]
door_rgb[62:68, 96:112, :] = [32, 34, 36]
door_rgba[:, :, :3] = np.clip(np.round(door_rgb / 5.0) * 5.0, 0, 255).astype(np.uint8)
door_rgba[:, :, 3] = 255
img_door = save_rgba_png("ps2_nc_door", door_rgba, 'sRGB')

# 1E. Perforated Metal Cable Tray (128x128)
tray_val = np.full((S, S), 118.0, dtype=np.float32)
gx = (np.arange(S) % 8)
gy = (np.arange(S) % 8)
hole = ((gx[None, :] >= 2) & (gx[None, :] <= 5) & (gy[:, None] >= 2) & (gy[:, None] <= 5))
tray_val = np.where(hole, 42.0, tray_val + (fbm_2d(S, S, scales=(4, 16)) - 0.5) * 18.0)
tray_rgb = np.stack([tray_val, tray_val * 1.01, tray_val * 1.03], axis=-1)
tray_rgb = np.clip(np.round(tray_rgb / 5.0) * 5.0, 0, 255).astype(np.uint8)
tray_rgba = np.concatenate([tray_rgb, np.full((S, S, 1), 255, dtype=np.uint8)], axis=-1)
img_tray = save_rgba_png("ps2_nc_cable_tray", tray_rgba, 'sRGB')


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


def make_flat_mat(name, rgba, rough=0.85, metallic=0.0, emit=None, emit_strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metallic
    if emit is not None:
        bsdf.inputs["Emission Color"].default_value = emit
        bsdf.inputs["Emission Strength"].default_value = emit_strength
    return mat


mat_floor = make_tex_mat("Mat_PS2_NC_Floor", img_floor_col, img_floor_rough)
mat_wall = make_tex_mat("Mat_PS2_NC_Wall", img_wall, rough_val=0.90)
mat_pier_seep = make_tex_mat("Mat_PS2_NC_PierSeep", img_pier_seep, rough_val=0.86)
mat_door = make_tex_mat("Mat_PS2_NC_Door", img_door, rough_val=0.52, metallic=0.18)
mat_tray = make_tex_mat("Mat_PS2_NC_CableTray", img_tray, rough_val=0.48, metallic=0.35)
mat_beam = make_flat_mat("Mat_PS2_NC_Beam", (0.28, 0.27, 0.25, 1.0), rough=0.92)
mat_curb = make_flat_mat("Mat_PS2_NC_Curb", (0.38, 0.36, 0.33, 1.0), rough=0.88)
mat_pipe = make_flat_mat("Mat_PS2_NC_Pipe", (0.50, 0.51, 0.50, 1.0), rough=0.45, metallic=0.25)
mat_dark_metal = make_flat_mat("Mat_PS2_NC_DarkMetal", (0.10, 0.11, 0.12, 1.0), rough=0.72, metallic=0.20)
mat_jbox = make_flat_mat("Mat_PS2_NC_JBox", (0.64, 0.65, 0.63, 1.0), rough=0.55)
mat_light = make_flat_mat("Mat_PS2_NC_LightBar", (0.96, 0.99, 1.0, 1.0), rough=0.1, emit=(0.92, 0.97, 1.0, 1.0), emit_strength=6.5)


def add_box(name, center, size, mat, face_mats=None):
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
        (0, 1, 5, 4),  # 0: -Y (front facing Godot +Z)
        (2, 3, 7, 6),  # 1: +Y (back facing Godot -Z)
        (3, 0, 4, 7),  # 2: -X (left outer)
        (1, 2, 6, 5),  # 3: +X (right)
        (4, 5, 6, 7),  # 4: +Z (top)
        (3, 2, 1, 0),  # 5: -Z (bottom)
    ]
    mesh.from_pydata(verts, [], faces)
    uv_layer = mesh.uv_layers.new(name="UVMap")
    mesh.materials.append(mat)
    mat_map = {None: 0}
    if face_mats:
        for f_idx, f_mat in face_mats.items():
            if f_mat not in mat_map:
                mat_map[f_mat] = len(mesh.materials)
                mesh.materials.append(f_mat)
    for fi, poly in enumerate(mesh.polygons):
        uvs = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
        for li, uv in zip(poly.loop_indices, uvs):
            uv_layer.data[li].uv = uv
        if face_mats and fi in face_mats:
            poly.material_index = mat_map[face_mats[fi]]
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    col.objects.link(obj)
    return obj


def add_pipe(name, p0, p1, radius, mat, segs=6):
    mesh = bpy.data.meshes.new(name)
    v0 = np.array(p0, dtype=np.float64)
    v1 = np.array(p1, dtype=np.float64)
    axis = v1 - v0
    length = np.linalg.norm(axis)
    if length < 1e-5:
        return None
    dir_v = axis / length
    ref = np.array([0.0, 0.0, 1.0]) if abs(dir_v[2]) < 0.9 else np.array([1.0, 0.0, 0.0])
    t1 = np.cross(dir_v, ref)
    t1 /= np.linalg.norm(t1)
    t2 = np.cross(dir_v, t1)

    verts = []
    for base in (v0, v1):
        for k in range(segs):
            ang = 2.0 * math.pi * k / segs
            pt = base + radius * (math.cos(ang) * t1 + math.sin(ang) * t2)
            verts.append(tuple(pt))
    faces = []
    for k in range(segs):
        kn = (k + 1) % segs
        faces.append((k, kn, segs + kn, segs + k))
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(mat)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    col.objects.link(obj)
    return obj


# ---------------------------------------------------------
# 3. Build North Corridor Geometry (Origin = Godot (0, 0, -20))
#    Blender +X = Godot +X (right)
#    Blender +Y = Godot -Z (north / forward into corridor, y: 0..14)
#    Blender +Z = Godot +Y (up, z: 0..3.6)
# ---------------------------------------------------------

# 3A. Subdivided Main Floor (x: -10..10, y: 0..14)
fl_mesh = bpy.data.meshes.new("NorthCorridorFloor")
nx, ny = 8, 8
x_min, x_max = -10.0, 10.0
y_min, y_max = 0.0, 14.0
fl_verts = []
fl_faces = []
for iy in range(ny + 1):
    ty = iy / ny
    fy = y_min + ty * (y_max - y_min)
    for ix in range(nx + 1):
        tx = ix / nx
        fx = x_min + tx * (x_max - x_min)
        fl_verts.append((fx, fy, 0.002))
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
col.objects.link(bpy.data.objects.new("NorthCorridorFloor", fl_mesh))

# 3B. Ceiling Slab (x: -10..10, y: 0..14, z: 3.56)
ce_mesh = bpy.data.meshes.new("NorthCorridorCeiling")
ce_verts = [(x_min, y_min, 3.58), (x_max, y_min, 3.58), (x_max, y_max, 3.58), (x_min, y_max, 3.58)]
ce_mesh.from_pydata(ce_verts, [], [(3, 2, 1, 0)])
uv_ce = ce_mesh.uv_layers.new(name="UVMap")
for poly in ce_mesh.polygons:
    for li, uv in zip(poly.loop_indices, [(0, 0), (1, 0), (1, 1), (0, 1)]):
        uv_ce.data[li].uv = uv
ce_mesh.materials.append(mat_beam)
ce_mesh.update()
col.objects.link(bpy.data.objects.new("NorthCorridorCeiling", ce_mesh))

# 3C. Left Concrete Wall along x = -3.7 (segmented around The Paths doorway y: 6.1..8.3 -> Godot z: -28.3..-26.1)
add_box("LeftWall_South", (-3.85, 3.05, 1.80), (0.30, 6.10, 3.60), mat_wall)
add_box("LeftWall_North", (-3.85, 11.15, 1.80), (0.30, 5.70, 3.60), mat_wall)
add_box("LeftWall_Header", (-3.85, 7.20, 3.00), (0.30, 2.20, 1.20), mat_wall)

# Connector Alcove to The Paths (x: -10.0..-3.7, y: 5.7..8.3 -> Godot z: -28.3..-25.7)
add_box("PathsConn_WallS", (-6.85, 5.75, 1.45), (6.30, 0.24, 2.90), mat_wall)
add_box("PathsConn_WallN", (-6.85, 8.25, 1.45), (6.30, 0.24, 2.90), mat_wall)
add_box("PathsConn_Ceil", (-6.85, 7.00, 2.86), (6.30, 2.74, 0.16), mat_beam)

# Left Wall Concrete Curb (broken cleanly at the doorway)
add_box("LeftCurb_S", (-3.56, 3.05, 0.09), (0.28, 6.10, 0.18), mat_curb)
add_box("LeftCurb_N", (-3.56, 11.15, 0.09), (0.28, 5.70, 0.18), mat_curb)

# Left Wall Structural Pilaster near foreground + Door 1 (closed utility door)
add_box("LeftPilaster_FG", (-3.62, 1.55, 1.80), (0.22, 0.38, 3.60), mat_wall)
add_box("LeftDoor1_Closed", (-3.67, 3.20, 1.25), (0.08, 1.15, 2.15), mat_door)

# Wall-mounted Black AC / Equipment Box + 2 Diagonal Wall Brackets between the doors
add_box("LeftWallUnit_Box", (-3.44, 5.05, 2.56), (0.50, 1.10, 0.36), mat_dark_metal)
add_pipe("LeftUnit_Brk1", (-3.70, 4.62, 2.06), (-3.24, 4.62, 2.38), 0.028, mat_dark_metal, segs=4)
add_pipe("LeftUnit_Brk2", (-3.70, 5.48, 2.06), (-3.24, 5.48, 2.38), 0.028, mat_dark_metal, segs=4)

# Left Door 2 (Door to The Paths, ajar inward at y=6.1..8.3 so it preserves corridor silhouette & stays walkable)
# Door frame + ajar leaf swung into connector hallway
add_box("LeftDoor2_FrameS", (-3.76, 6.16, 1.22), (0.22, 0.12, 2.40), mat_door)
add_box("LeftDoor2_FrameN", (-3.76, 8.24, 1.22), (0.22, 0.12, 2.40), mat_door)
add_box("LeftDoor2_FrameTop", (-3.76, 7.20, 2.40), (0.22, 2.20, 0.12), mat_door)
door2_leaf = add_box("LeftDoor2_AjarLeaf", (-4.37, 6.43, 1.18), (0.07, 1.12, 2.32), mat_door)
door2_leaf.rotation_euler = (0.0, 0.0, math.radians(-68.0))

# Far Left Wall Pipe Bundle + Door 3 hint at y = 11.4
add_box("LeftDoor3_Far", (-3.67, 11.60, 1.22), (0.08, 1.05, 2.10), mat_door)

# 3D. Right Side Hero Concrete Pier with Seepage Stain (x: 1.65..3.05, y: 3.2..6.6)
# Visible face -Y (y=3.2) & -X (x=1.65) get the seepage stain texture!
add_box(
    "RightPier_Hero",
    (2.35, 4.90, 1.80),
    (1.40, 3.40, 3.60),
    mat_wall,
    face_mats={0: mat_pier_seep, 2: mat_pier_seep},
)
# Pier curb wrapping its front (-Y) and inner corridor face (-X)
add_box("RightPier_CurbF", (2.35, 3.08, 0.09), (1.76, 0.24, 0.18), mat_curb)
add_box("RightPier_CurbL", (1.53, 4.90, 0.09), (0.24, 3.40, 0.18), mat_curb)

# Recessed Right Wall behind the Pier (x: 4.15, y: 6.2..14.0 -> leaves dark niche & open right bay access!)
add_box("RightWall_Back", (4.30, 10.10, 1.80), (0.30, 7.80, 3.60), mat_wall)
add_box("RightCurb_Back", (3.98, 10.10, 0.09), (0.34, 7.80, 0.18), mat_curb)
# Step pillar on right back wall + black bucket tucked behind foreground pier
add_box("RightPillar_Back", (3.85, 8.80, 1.80), (0.45, 0.55, 3.60), mat_wall)
add_pipe("CornerBucket", (3.35, 6.75, 0.0), (3.35, 6.75, 0.42), 0.20, mat_dark_metal, segs=8)

# Outer Perimeter Walls enclosing the East Bay (x: +9.8) and North Partition (y = 13.85)
# North wall at y=13.85 leaves x: -3.0..+1.0 OPEN into Pump Control Room (matches existing -3..1 doorway!)
add_box("EastOuterWall", (9.85, 7.00, 1.80), (0.30, 14.00, 3.60), mat_wall)
add_box("NorthWall_West", (-6.50, 13.85, 1.80), (7.00, 0.30, 3.60), mat_wall)
add_box("NorthWall_East", (5.50, 13.85, 1.80), (9.00, 0.30, 3.60), mat_wall)
add_box("NorthWall_Header", (-1.00, 13.85, 3.20), (4.00, 0.30, 0.80), mat_wall)

# 3E. Ceiling Cross-Beams + Junction Box + Perforated Cable Trays + Overhead Pipes + Fluorescent Row
# Low heavy foreground concrete beam across the top of the frame
add_box("Beam_Foreground", (0.0, 2.25, 3.12), (20.0, 0.72, 0.92), mat_beam)
add_box("Beam_Mid", (0.0, 7.60, 3.24), (20.0, 0.50, 0.68), mat_beam)
add_box("Beam_North", (0.0, 12.80, 3.24), (20.0, 0.50, 0.68), mat_beam)

# Small white junction box & drop conduit hanging on the left side of the foreground beam
add_box("FG_JunctionBox", (-2.15, 1.83, 2.86), (0.24, 0.16, 0.24), mat_jbox)
add_pipe("FG_DropConduit", (-2.15, 1.83, 2.98), (-2.15, 1.83, 3.55), 0.025, mat_pipe, segs=6)
add_pipe("FG_ShortPipe", (-1.92, 1.84, 2.66), (-2.15, 1.84, 2.78), 0.020, mat_pipe, segs=6)

# Perforated Steel Cable Trays (parallel lengthwise strips under the slab)
add_box("CableTray_Center", (0.45, 7.90, 3.26), (0.78, 11.40, 0.06), mat_tray)
add_box("CableTray_Right", (2.05, 7.90, 3.26), (0.78, 11.40, 0.06), mat_tray)

# Longitudinal Overhead Galvanized Pipes (6-sided low-poly)
for px, pz, pr in [(-2.65, 3.10, 0.075), (-1.95, 3.14, 0.060), (-0.45, 3.12, 0.055), (3.15, 3.08, 0.085)]:
    add_pipe(f"LongPipe_{px:.1f}", (px, 0.2, pz), (px, 13.7, pz), pr, mat_pipe, segs=6)

# Transverse cross pipes under the ceiling slab
for py, pz, pr in [(3.9, 2.98, 0.045), (9.4, 2.98, 0.045)]:
    add_pipe(f"CrossPipe_{py:.1f}", (-3.6, py, pz), (3.8, py, pz), pr, mat_pipe, segs=6)

# Row of 6 Receding White Fluorescent Tube Lights down center-left + 1 Right Bay Light
for idx, ly in enumerate([2.95, 4.75, 6.55, 8.35, 10.15, 11.95]):
    add_box(f"FluoroHousing_{idx}", (-1.05, ly, 2.98), (1.42, 0.26, 0.05), mat_dark_metal)
    add_box(f"FluoroTube_{idx}", (-1.05, ly, 2.93), (1.36, 0.18, 0.05), mat_light)

# Right Bay Fluorescent Light peeking past the hero pier on the right edge of the frame
add_box("FluoroHousing_RightBay", (4.75, 3.85, 2.98), (1.42, 0.26, 0.05), mat_dark_metal)
add_box("FluoroTube_RightBay", (4.75, 3.85, 2.93), (1.36, 0.18, 0.05), mat_light)

# ---------------------------------------------------------
# 4. Export glTF (.glb) & Print Triangle Budget
# ---------------------------------------------------------
total_tris = 0
for obj in bpy.data.objects:
    if obj.type == 'MESH':
        for p in obj.data.polygons:
            total_tris += max(1, len(p.vertices) - 2)

bpy.ops.export_scene.gltf(
    filepath=OUT_GLB_PATH,
    export_format='GLB',
    export_yup=True,
    export_texcoords=True,
    export_normals=True,
    export_materials='EXPORT',
    export_image_format='AUTO',
)
print(f"[north_corridor_ps2_build] Exported {OUT_GLB_PATH} | Total triangles: {total_tris}")
