"""
Optimize an exported .glb file to authentic PS2 texture specs:
- General surfaces (walls, floors, tiles, snow): max 128px, subtle 16-bit color posterize.
- Ads, text signs, pine murals (ad_, text_, skybox_): max 256px so they stay legible.
- Normal maps (_normal, ssbump): max 128px, NO color posterize or desaturation.
Preserves all mesh geometry, UVs, and glTF 2.0 binary structure.
"""
import io
import json
import os
import struct
import sys
from PIL import Image, ImageEnhance, ImageOps


def optimize_glb(glb_path: str) -> None:
    orig_size = os.path.getsize(glb_path)
    with open(glb_path, "rb") as f:
        data = f.read()

    magic, version, length = struct.unpack_from("<4sII", data, 0)
    assert magic == b"glTF" and version == 2, "Not a valid glTF 2.0 binary"

    # Chunk 0: JSON
    json_len, json_type = struct.unpack_from("<I4s", data, 12)
    assert json_type == b"JSON"
    gltf = json.loads(data[20 : 20 + json_len].decode("utf-8"))

    # Chunk 1: BIN
    bin_offset = 20 + json_len
    bin_len, bin_type = struct.unpack_from("<I4s", data, bin_offset)
    assert bin_type == b"BIN\x00"
    bin_data = data[bin_offset + 8 : bin_offset + 8 + bin_len]

    images = gltf.get("images", [])
    buffer_views = gltf.get("bufferViews", [])

    # Map bufferView index -> image index
    bv_to_img = {}
    for idx, img_def in enumerate(images):
        if "bufferView" in img_def:
            bv_to_img[img_def["bufferView"]] = idx

    new_bin = bytearray()
    resized_count = 0

    for bv_idx, bv in enumerate(buffer_views):
        start = bv.get("byteOffset", 0)
        blen = bv["byteLength"]
        raw = bin_data[start : start + blen]

        if bv_idx in bv_to_img:
            img_idx = bv_to_img[bv_idx]
            img_def = images[img_idx]
            name = (img_def.get("name") or "").lower()
            is_normal = ("normal" in name) or ("ssbump" in name) or ("bump" in name)
            is_sign = any(k in name for k in ("ad_", "text_", "skybox", "sign", "poster", "logo"))
            max_dim = 256 if is_sign else 128

            try:
                im = Image.open(io.BytesIO(raw))
                has_alpha = im.mode in ("RGBA", "LA") or (im.mode == "P" and "transparency" in im.info)
                w, h = im.size
                if max(w, h) > max_dim:
                    scale = max_dim / float(max(w, h))
                    nw = max(4, int(round(w * scale)))
                    nh = max(4, int(round(h * scale)))
                    im = im.resize((nw, nh), Image.Resampling.BILINEAR)
                    resized_count += 1

                if not is_normal:
                    if has_alpha:
                        rgba = im.convert("RGBA")
                        rgb, alpha = rgba.convert("RGB"), rgba.getchannel("A")
                        rgb = ImageEnhance.Color(rgb).enhance(0.92)
                        rgb = ImageOps.posterize(rgb, 5)  # 32 levels per channel (PS2 15/16-bit feel)
                        im = Image.merge("RGBA", (*rgb.split(), alpha))
                    else:
                        rgb = im.convert("RGB")
                        rgb = ImageEnhance.Color(rgb).enhance(0.92)
                        rgb = ImageOps.posterize(rgb, 5)
                        im = rgb

                out_buf = io.BytesIO()
                im.save(out_buf, format="PNG", optimize=True)
                img_def["mimeType"] = "image/png"
                raw = out_buf.getvalue()
            except Exception as e:
                print(f"  [warn] skipped image {name}: {e}")

        # Align each bufferView to 4 bytes
        while len(new_bin) % 4 != 0:
            new_bin.append(0)
        bv["byteOffset"] = len(new_bin)
        bv["byteLength"] = len(raw)
        new_bin.extend(raw)

    while len(new_bin) % 4 != 0:
        new_bin.append(0)

    gltf["buffers"][0]["byteLength"] = len(new_bin)
    new_json = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(new_json) % 4 != 0:
        new_json += b" "

    total_len = 12 + 8 + len(new_json) + 8 + len(new_bin)
    out = bytearray()
    out.extend(struct.pack("<4sII", b"glTF", 2, total_len))
    out.extend(struct.pack("<I4s", len(new_json), b"JSON"))
    out.extend(new_json)
    out.extend(struct.pack("<I4s", len(new_bin), b"BIN\x00"))
    out.extend(new_bin)

    tmp_path = glb_path + ".tmp"
    with open(tmp_path, "wb") as f:
        f.write(out)
    os.replace(tmp_path, glb_path)

    new_size = os.path.getsize(glb_path)
    print(
        f"Optimized {glb_path}: {orig_size / (1024*1024):.2f} MB -> {new_size / (1024*1024):.2f} MB "
        f"({resized_count}/{len(images)} images downscaled to PS2 128/256px)"
    )


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else r"c:\Users\dark\Documents\貝克潤ps-2\assets\models\everpine_mall_ps2.glb"
    optimize_glb(target)
