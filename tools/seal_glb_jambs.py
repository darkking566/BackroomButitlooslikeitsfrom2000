"""
Directly append an `AutoSealedDoorJambs` mesh into a glTF 2.0 (.glb) file to seal
hollow Source-engine wall-thickness / door-jamb gaps without altering any existing
nodes, interactive doors, materials, or textures.
"""
import json
import os
import struct
import sys
from collections import defaultdict
import numpy as np


COMP_MAP = {
    5120: np.int8,
    5121: np.uint8,
    5122: np.int16,
    5123: np.uint16,
    5125: np.uint32,
    5126: np.float32,
}
TYPE_CNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def node_local_matrix(node: dict) -> np.ndarray:
    if "matrix" in node:
        return np.array(node["matrix"], dtype=np.float64).reshape((4, 4)).T
    M = np.eye(4, dtype=np.float64)
    if "scale" in node:
        s = node["scale"]
        M = M @ np.diag([s[0], s[1], s[2], 1.0])
    if "rotation" in node:
        x, y, z, w = node["rotation"]
        R = np.array([
            [1 - 2*(y*y + z*z), 2*(x*y - z*w),     2*(x*z + y*w),     0.0],
            [2*(x*y + z*w),     1 - 2*(x*x + z*z), 2*(y*z - x*w),     0.0],
            [2*(x*z - y*w),     2*(y*z + x*w),     1 - 2*(x*x + y*y), 0.0],
            [0.0,               0.0,               0.0,               1.0],
        ], dtype=np.float64)
        M = R @ M
    if "translation" in node:
        t = node["translation"]
        T = np.eye(4, dtype=np.float64)
        T[:3, 3] = t
        M = T @ M
    return M


def seal_glb(glb_path: str, interactives_json: str = "") -> None:
    skip_names = set()
    if interactives_json and os.path.exists(interactives_json):
        try:
            ia = json.load(open(interactives_json, "r", encoding="utf-8"))
            if isinstance(ia, list):
                for e in ia:
                    if isinstance(e, dict) and "n" in e:
                        skip_names.add(str(e["n"]))
        except Exception as e:
            print(f"  [warn] could not read {interactives_json}: {e}")

    data = open(glb_path, "rb").read()
    magic, version, _ = struct.unpack_from("<4sII", data, 0)
    assert magic == b"glTF" and version == 2

    json_len, json_type = struct.unpack_from("<I4s", data, 12)
    assert json_type == b"JSON"
    gltf = json.loads(data[20 : 20 + json_len].decode("utf-8"))

    bin_off = 20 + json_len
    bin_len, bin_type = struct.unpack_from("<I4s", data, bin_off)
    assert bin_type == b"BIN\x00"
    bin_data = bytearray(data[bin_off + 8 : bin_off + 8 + bin_len])

    # Avoid double-sealing if already present
    for n in gltf.get("nodes", []):
        if n.get("name") == "AutoSealedDoorJambs":
            print(f"  {glb_path}: AutoSealedDoorJambs already present, skipping.")
            return

    def get_acc(idx: int) -> np.ndarray:
        acc = gltf["accessors"][idx]
        bv = gltf["bufferViews"][acc["bufferView"]]
        off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
        dt = COMP_MAP[acc["componentType"]]
        cnt = TYPE_CNT[acc["type"]]
        arr = np.frombuffer(bin_data, dtype=dt, count=acc["count"] * cnt, offset=off)
        return arr.reshape((acc["count"], cnt)) if cnt > 1 else arr

    # Compute world matrices for all nodes
    nodes = gltf.get("nodes", [])
    world_mats = [np.eye(4, dtype=np.float64) for _ in nodes]
    parent_of = {}
    for pi, pn in enumerate(nodes):
        for ci in pn.get("children", []):
            parent_of[ci] = pi

    def compute_world(ni: int, visited=None):
        if visited is None:
            visited = set()
        if ni in visited:
            return np.eye(4, dtype=np.float64)
        visited.add(ni)
        local = node_local_matrix(nodes[ni])
        if ni in parent_of:
            return compute_world(parent_of[ni], visited) @ local
        return local

    for ni in range(len(nodes)):
        world_mats[ni] = compute_world(ni)

    # Scan each static mesh node for hollow wall-thickness open edge pairs
    quad_verts = []
    quad_norms = []
    quad_indices = []
    sealed_count = 0

    for ni, node in enumerate(nodes):
        if "mesh" not in node:
            continue
        nname = node.get("name", "")
        if nname in skip_names or nname.lower().startswith("infodecal"):
            continue
        M = world_mats[ni]
        R3 = M[:3, :3]
        mesh = gltf["meshes"][node["mesh"]]

        edge_faces = defaultdict(list)
        for prim in mesh.get("primitives", []):
            if "POSITION" not in prim.get("attributes", {}):
                continue
            # Skip sky/tool materials so we don't bridge skybox edges
            mat_idx = prim.get("material")
            if mat_idx is not None and mat_idx < len(gltf.get("materials", [])):
                mname = gltf["materials"][mat_idx].get("name", "").upper()
                if "SKY" in mname or "TOOLS" in mname:
                    continue

            pos_local = get_acc(prim["attributes"]["POSITION"]).astype(np.float64)
            pos = (pos_local @ R3.T) + M[:3, 3]
            if "indices" in prim:
                idx = get_acc(prim["indices"]).astype(np.int64).reshape(-1, 3)
            else:
                idx = np.arange(len(pos)).reshape(-1, 3)

            qpos = [tuple(np.round(p, 3)) for p in pos]
            for tri in idx:
                p0, p1, p2 = pos[tri[0]], pos[tri[1]], pos[tri[2]]
                n = np.cross(p1 - p0, p2 - p0)
                nl = np.linalg.norm(n)
                if nl < 1e-8:
                    continue
                n /= nl
                q0, q1, q2 = qpos[tri[0]], qpos[tri[1]], qpos[tri[2]]
                for a, c in ((q0, q1), (q1, q2), (q2, q0)):
                    ek = (a, c) if a < c else (c, a)
                    edge_faces[ek].append(n)

        open_e = [(ek, fl[0]) for ek, fl in edge_faces.items() if len(fl) == 1]
        if not open_e:
            continue

        by_ax = {0: [], 1: [], 2: []}
        for (a, c), n in open_e:
            va, vc = np.array(a), np.array(c)
            dv = vc - va
            L = np.linalg.norm(dv)
            if L < 0.04:
                continue
            dn = dv / L
            for ax in range(3):
                if abs(dn[ax]) > 0.995:
                    if va[ax] > vc[ax]:
                        va, vc = vc, va
                    other = [0, 1, 2]
                    other.remove(ax)
                    by_ax[ax].append((va, vc, va[ax], vc[ax], va[other[0]], va[other[1]], n))
                    break

        for ax, items in by_ax.items():
            buckets = defaultdict(list)
            for it in items:
                buckets[(round(it[2], 2), round(it[3], 2))].append(it)
            for grp in buckets.values():
                used = set()
                for i in range(len(grp)):
                    if i in used:
                        continue
                    v0a, v1a, _, _, a1, b1, n1 = grp[i]
                    best_j = -1
                    best_dist = 0.90
                    for j in range(i + 1, len(grp)):
                        if j in used:
                            continue
                        v0b, v1b, _, _, a2, b2, n2 = grp[j]
                        da, db = abs(a1 - a2), abs(b1 - b2)
                        if not ((da < 0.025 and 0.03 <= db <= 0.88) or (db < 0.025 and 0.03 <= da <= 0.88)):
                            continue
                        if np.dot(n1, n2) > -0.85:
                            continue
                        sep = v0b - v0a
                        sl = np.linalg.norm(sep)
                        if sl < 0.03:
                            continue
                        sd = sep / sl
                        if abs(np.dot(n1, sd)) > 0.85 and abs(np.dot(n2, sd)) > 0.85:
                            if sl < best_dist:
                                best_dist = sl
                                best_j = j
                    if best_j != -1:
                        used.add(i)
                        used.add(best_j)
                        v0b, v1b = grp[best_j][0], grp[best_j][1]
                        qn = np.cross(v1a - v0a, v0b - v0a)
                        qnl = np.linalg.norm(qn)
                        if qnl < 1e-8:
                            continue
                        qn = (qn / qnl).astype(np.float32)
                        base = len(quad_verts)
                        quad_verts.extend([
                            v0a.astype(np.float32),
                            v1a.astype(np.float32),
                            v1b.astype(np.float32),
                            v0b.astype(np.float32),
                        ])
                        quad_norms.extend([qn, qn, qn, qn])
                        quad_indices.extend([base, base + 1, base + 2, base, base + 2, base + 3])
                        sealed_count += 1

    if sealed_count == 0:
        print(f"  {glb_path}: 0 gaps found.")
        return

    pos_arr = np.array(quad_verts, dtype=np.float32)
    nrm_arr = np.array(quad_norms, dtype=np.float32)
    idx_arr = np.array(quad_indices, dtype=np.uint32)

    def append_bv(raw_bytes: bytes, target: int) -> int:
        while len(bin_data) % 4 != 0:
            bin_data.append(0)
        off = len(bin_data)
        bin_data.extend(raw_bytes)
        bv_idx = len(gltf["bufferViews"])
        gltf["bufferViews"].append({
            "buffer": 0,
            "byteOffset": off,
            "byteLength": len(raw_bytes),
            "target": target,
        })
        return bv_idx

    bv_pos = append_bv(pos_arr.tobytes(), 34962)
    bv_nrm = append_bv(nrm_arr.tobytes(), 34962)
    bv_idx = append_bv(idx_arr.tobytes(), 34963)

    acc_pos = len(gltf["accessors"])
    gltf["accessors"].append({
        "bufferView": bv_pos,
        "componentType": 5126,
        "count": len(pos_arr),
        "type": "VEC3",
        "min": pos_arr.min(axis=0).tolist(),
        "max": pos_arr.max(axis=0).tolist(),
    })
    acc_nrm = len(gltf["accessors"])
    gltf["accessors"].append({
        "bufferView": bv_nrm,
        "componentType": 5126,
        "count": len(nrm_arr),
        "type": "VEC3",
    })
    acc_idx = len(gltf["accessors"])
    gltf["accessors"].append({
        "bufferView": bv_idx,
        "componentType": 5125,
        "count": len(idx_arr),
        "type": "SCALAR",
    })

    # Add matte dark-gray double-sided material
    mat_idx = len(gltf.setdefault("materials", []))
    gltf["materials"].append({
        "name": "AutoJambTrim",
        "doubleSided": True,
        "pbrMetallicRoughness": {
            "baseColorFactor": [0.22, 0.22, 0.20, 1.0],
            "metallicFactor": 0.0,
            "roughnessFactor": 0.92,
        },
    })

    mesh_idx = len(gltf.setdefault("meshes", []))
    gltf["meshes"].append({
        "name": "AutoSealedDoorJambs_MESH",
        "primitives": [{
            "attributes": {"POSITION": acc_pos, "NORMAL": acc_nrm},
            "indices": acc_idx,
            "material": mat_idx,
        }],
    })

    node_idx = len(gltf.setdefault("nodes", []))
    gltf["nodes"].append({
        "name": "AutoSealedDoorJambs",
        "mesh": mesh_idx,
    })

    scene_idx = gltf.get("scene", 0)
    gltf["scenes"][scene_idx].setdefault("nodes", []).append(node_idx)

    while len(bin_data) % 4 != 0:
        bin_data.append(0)
    gltf["buffers"][0]["byteLength"] = len(bin_data)

    new_json = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(new_json) % 4 != 0:
        new_json += b" "

    total_len = 12 + 8 + len(new_json) + 8 + len(bin_data)
    out = bytearray()
    out.extend(struct.pack("<4sII", b"glTF", 2, total_len))
    out.extend(struct.pack("<I4s", len(new_json), b"JSON"))
    out.extend(new_json)
    out.extend(struct.pack("<I4s", len(bin_data), b"BIN\x00"))
    out.extend(bin_data)

    tmp = glb_path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(out)
    os.replace(tmp, glb_path)
    print(f"Sealed {glb_path}: added AutoSealedDoorJambs with {sealed_count} jamb quads ({len(pos_arr)} verts).")


if __name__ == "__main__":
    seal_glb(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "")
