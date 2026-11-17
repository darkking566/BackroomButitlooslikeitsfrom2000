extends RefCounted
# 共用材質風格：讓純色 StandardMaterial3D 帶上和起點壁紙相同的「32 格/公尺」像素顆粒感，色調稍微壓暗降飽和，
# 這樣校舍翼、西翼等區域和起點（backrooms 壁紙/地毯 shader）看起來是同一個質感。

static var _tex: ImageTexture


static func grain() -> ImageTexture:
	if _tex == null:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
		for y in 32:
			for x in 32:
				var v := 0.93 + rng.randf() * 0.07
				if rng.randf() < 0.04:
					v = 0.82  # 零星的暗點，像受潮的污漬
				img.set_pixel(x, y, Color(v, v, v))
		_tex = ImageTexture.create_from_image(img)
	return _tex


static var _pix := {}


# 把高解析貼圖縮成 64 px 的像素風（最近鄰），並稍微壓暗、降飽和；同一張只處理一次
static func pixelate(tex: Texture2D, bright: float = 0.8, sat: float = 0.55) -> Texture2D:
	if tex == null:
		return null
	var id := tex.get_instance_id()
	if _pix.has(id):
		return _pix[id]
	var img := tex.get_image()
	if img == null:
		return tex
	if img.is_compressed():
		img.decompress()
	img.adjust_bcs(bright, 1.0, sat)
	img.resize(mini(img.get_width(), 64), mini(img.get_height(), 64), Image.INTERPOLATE_NEAREST)
	var avg := img.duplicate() as Image
	avg.resize(1, 1, Image.INTERPOLATE_BILINEAR)
	var lum := avg.get_pixel(0, 0).get_luminance()
	if lum > 0.55:
		img.adjust_bcs(0.55 / lum, 1.0, 1.0)  # 純白的牆壓到和其他牆同一個亮度，不然會在昏暗的場景裡爆白
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_pix[id] = t
	return t


static func apply(m: StandardMaterial3D) -> StandardMaterial3D:
	if m == null or m.emission_enabled or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return m  # 發光體與半透明（窗、玻璃）保持原樣
	m.albedo_texture = grain()
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE  # 世界座標每公尺 = 32 像素
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	var c := m.albedo_color
	m.albedo_color = Color.from_hsv(c.h, c.s * 0.65, c.v * 0.7)
	return m
