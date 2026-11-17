@tool
extends Level0Expanse
# Level 0「錄影帶」翼：參考 VHS 閾限空間照片做的一串彩色房間，每段換一種色調與天花高度，
# 霧色 / 環境光在相鄰區域間漸變。入口兩個：高柱長廳東牆 z[96..99]、熄燈區南牆 x[8..10]。
#   K 小船走廊    x[-44..-20] z[95..100]   黃天花 2.8、嵌燈、地毯上一艘小船
#   P 琥珀走廊    x[-20..2]   z[94..101]   護牆板、假門
#   Q 紫玻璃支廊  x[-14..-10] z[101..112]  玻璃磚牆
#   L 檯燈客廳    x[-22..-4]  z[112..126]  暖色壁紙、拱門、後室通往白色挑高廳
#   T 青色大廳    x[2..26]    z[94..113]   橘色亮面地板、藍色量體、櫃台、吊燈；北接熄燈區走廊
#   V 黃色前室    x[12..19]   z[113..118]  壁燈
#   W 白色挑高廳  x[-4..26]   z[118..146]  高 9、八葉吊扇、高窗、南側夾層 y 4、樓梯往下
#   B 藍色樓梯間  x[4..12]    z[146..163]  y -2 起爬到 4，沿回程走道回到夾層
# 生成節點不設 owner（AGENTS.md）。

var _m_yellow_ceil: StandardMaterial3D
var _m_white: StandardMaterial3D
var _m_cream: StandardMaterial3D
var _m_amber: StandardMaterial3D
var _m_glass: StandardMaterial3D
var _m_mullion: StandardMaterial3D
var _m_warm: StandardMaterial3D
var _m_rug: StandardMaterial3D
var _m_teal: StandardMaterial3D
var _m_blue: StandardMaterial3D
var _m_orange: StandardMaterial3D
var _m_gray: StandardMaterial3D
var _m_well: StandardMaterial3D
var _m_sky: StandardMaterial3D
var _m_lamp: StandardMaterial3D
var _fan: Node3D


func _init_materials() -> void:
	super._init_materials()
	_m_yellow_ceil = _mat(Color(0.86, 0.72, 0.32))
	_m_white = _mat(Color(0.86, 0.85, 0.80))
	_m_cream = _mat(Color(0.76, 0.70, 0.56), 0.95)
	_m_amber = _mat(Color(0.74, 0.50, 0.22))
	_m_glass = _mat(Color(0.55, 0.38, 0.85), 0.3, 0.55)
	_m_mullion = _mat(Color(0.30, 0.24, 0.38), 0.6)
	_m_warm = _mat(Color(0.62, 0.40, 0.24))
	_m_rug = _mat(Color(0.42, 0.22, 0.14), 0.95)
	_m_teal = _mat(Color(0.22, 0.55, 0.56))
	_m_blue = _mat(Color(0.16, 0.30, 0.62))
	_m_orange = _mat(Color(0.82, 0.42, 0.14), 0.25)
	_m_orange.metallic = 0.1
	_m_gray = _mat(Color(0.60, 0.60, 0.62), 0.9)
	_m_well = _mat(Color(0.32, 0.46, 0.78))
	_m_sky = _mat(Color(0.75, 0.88, 1.0), 0.5, 1.4)
	_m_lamp = _mat(Color(1.0, 0.95, 0.80), 0.5, 1.6)


func _mat(c: Color, rough: float = 0.85, emit: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return preload("res://scripts/pixel_style.gd").apply(m)


func _process(delta: float) -> void:
	if _fan and not Engine.is_editor_hint():
		_fan.rotate_y(delta * 1.3)
	super._process(delta)


func _zone_env(zone: String) -> Array:
	match zone:
		"vhs_corridor":
			return [Color(0.70, 0.62, 0.40), 0.035, Color(0.80, 0.74, 0.55), 0.5]
		"vhs_amber":
			return [Color(0.60, 0.42, 0.18), 0.04, Color(0.78, 0.56, 0.30), 0.45]
		"vhs_purple":
			return [Color(0.36, 0.22, 0.52), 0.045, Color(0.58, 0.42, 0.78), 0.42]
		"vhs_warm":
			return [Color(0.50, 0.32, 0.18), 0.04, Color(0.72, 0.50, 0.32), 0.4]
		"vhs_teal_hall": # 熄燈區 → 青色大廳之間的半過渡
			return [Color(0.36, 0.44, 0.34), 0.05, Color(0.58, 0.64, 0.52), 0.42]
		"vhs_teal":
			return [Color(0.25, 0.45, 0.48), 0.025, Color(0.55, 0.72, 0.75), 0.5]
		"vhs_vestibule":
			return [Color(0.72, 0.62, 0.36), 0.03, Color(0.82, 0.74, 0.52), 0.52]
		"vhs_loft":
			return [Color(0.78, 0.76, 0.68), 0.02, Color(0.85, 0.84, 0.78), 0.6]
		"vhs_blue":
			return [Color(0.30, 0.42, 0.70), 0.03, Color(0.50, 0.62, 0.90), 0.5]
	return super._zone_env(zone)


func _build() -> void:
	_make_roots("Tapes")
	_build_boat_corridor()
	_build_amber_hall()
	_build_lounge()
	_build_lobby()
	_build_loft()
	_build_stairwell()
	_build_tape_props()
	# 區域觸發：彼此略重疊，走過去時霧色從一區漸變到下一區
	_trigger("ZoneCorridor", Vector3(-32.0, 1.5, 97.5), Vector3(24.4, 3.0, 5.0), "vhs_corridor")
	_trigger("ZoneAmber", Vector3(-9.0, 1.5, 97.5), Vector3(22.4, 3.0, 7.0), "vhs_amber")
	_trigger("ZonePurple", Vector3(-12.0, 1.3, 106.5), Vector3(4.0, 2.6, 11.6), "vhs_purple")
	_trigger("ZoneLounge", Vector3(-13.0, 1.6, 119.0), Vector3(18.4, 3.2, 14.4), "vhs_warm")
	_trigger("ZoneTealHall", Vector3(9.0, 1.3, 87.4), Vector3(2.0, 2.6, 13.6), "vhs_teal_hall")
	_trigger("ZoneLobby", Vector3(14.0, 2.0, 103.5), Vector3(24.0, 4.0, 19.4), "vhs_teal")
	_trigger("ZoneVestibule", Vector3(15.5, 1.3, 115.5), Vector3(7.0, 2.6, 5.4), "vhs_vestibule")
	_trigger("ZoneLoft", Vector3(11.0, 3.5, 132.0), Vector3(30.4, 11.0, 28.4), "vhs_loft")
	_trigger("ZoneWell", Vector3(8.0, 2.75, 154.5), Vector3(8.0, 9.5, 17.4), "vhs_blue")


# --- 小工具 ---
func _glow(pos: Vector3, sz: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	_lights.add_child(mi)


func _omni(pos: Vector3, c: Color, energy: float, rng: float) -> void:
	var o := OmniLight3D.new()
	o.position = pos
	o.light_color = c
	o.light_energy = energy
	o.omni_range = rng
	o.shadow_enabled = false
	_lights.add_child(o)


# 嵌入天花的圓形筒燈
func _downlight(pos: Vector3, c: Color, energy: float, rng: float) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.18
	cm.bottom_radius = 0.18
	cm.height = 0.03
	cm.radial_segments = 10
	mi.mesh = cm
	mi.material_override = _m_lamp
	mi.position = pos
	_lights.add_child(mi)
	_omni(pos - Vector3(0, 0.3, 0), c, energy, rng)


# --- K: 小船走廊 ---
func _build_boat_corridor() -> void:
	_slab(-44.0, 95.0, -20.0, 100.0, 0.0, _m_cream)
	_slab(-44.0, 95.0, -20.0, 100.0, 3.0, _m_yellow_ceil)
	_wall(true, 95.0, -44.0, -20.0, 0.0, 2.8, _m_white)
	_wall(true, 100.0, -44.0, -20.0, 0.0, 2.8, _m_white)
	# 踢腳板
	_box(Vector3(-32.0, 0.06, 95.17), Vector3(24.0, 0.12, 0.04), _mat_wood, false)
	_box(Vector3(-32.0, 0.06, 99.83), Vector3(24.0, 0.12, 0.04), _mat_wood, false)
	for i in 7:
		_downlight(Vector3(-41.0 + i * 3.4, 2.78, 97.5), Color(1.0, 0.93, 0.70), 0.7, 5.0)
	# 手寫風格的牆上字（原創字句）
	var sign_l := Label3D.new()
	sign_l.text = "Almost Home"
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Segoe Script", "Brush Script MT", "Comic Sans MS"])
	f.font_italic = true
	sign_l.font = f
	sign_l.font_size = 96
	sign_l.pixel_size = 0.004
	sign_l.modulate = Color(0.32, 0.26, 0.20)
	sign_l.outline_size = 0
	sign_l.position = Vector3(-31.0, 1.9, 95.18)
	_lights.add_child(sign_l)
	_note("BoatNote", Vector3(-36.0, 1.4, 99.83), 180.0, "閱讀牆上的便條", "小船走廊便條",
		"【小船走廊】\n地毯是乾的。船底也是乾的。\n\n"
		+ "「船槳不見了，但船頭朝著東邊。我想它知道路。」")


# --- P: 琥珀走廊 + Q 紫玻璃支廊 ---
func _build_amber_hall() -> void:
	_slab(-20.0, 94.0, 2.0, 101.0, 0.0, MAT_CARPET)
	_slab(-20.0, 94.0, 2.0, 101.0, 3.2, MAT_CEILING)
	_wall(false, -20.0, 94.0, 101.0, 0.0, 3.0, _m_amber, [Vector4(95.0, 100.0, 0.0, 2.8)])
	_wall(true, 94.0, -20.0, 2.0, 0.0, 3.0, _m_amber)
	_wall(true, 101.0, -20.0, 2.0, 0.0, 3.0, _m_amber, [Vector4(-14.0, -10.0, 0.0, 2.6)])
	# 東牆 x=2 由青色大廳西牆提供
	# 護牆板 + 壓條
	for seg in [[-20.0, 2.0, 94.17], [-20.0, -14.0, 100.83], [-10.0, 2.0, 100.83]]:
		var a: float = seg[0]
		var b: float = seg[1]
		var z: float = seg[2]
		_box(Vector3((a + b) * 0.5, 0.5, z), Vector3(b - a, 1.0, 0.04), _mat_wood, false)
		_box(Vector3((a + b) * 0.5, 1.03, z), Vector3(b - a, 0.06, 0.08), _mat_rail, false)
	# 打不開的鑲板門
	_box(Vector3(-6.0, 1.1, 94.2), Vector3(1.1, 2.2, 0.08), _mat_wood, false)
	for px in [-6.25, -5.75]:
		for py in [0.6, 1.6]:
			_box(Vector3(px, py, 94.25), Vector3(0.36, 0.75, 0.03), _mat_thick, false)
	_box(Vector3(-5.6, 1.0, 94.27), Vector3(0.08, 0.08, 0.06), _mat_rail, false)
	for lx in [-16.0, -8.0, -1.0]:
		_glow(Vector3(lx, 1.9, 94.2), Vector3(0.3, 0.2, 0.1), _m_lamp)
		_omni(Vector3(lx, 1.9, 94.8), Color(1.0, 0.72, 0.38), 0.7, 5.5)
		_glow(Vector3(lx + 2.0, 1.9, 100.8), Vector3(0.3, 0.2, 0.1), _m_lamp)
		_omni(Vector3(lx + 2.0, 1.9, 100.2), Color(1.0, 0.72, 0.38), 0.6, 5.0)

	# Q 紫玻璃支廊
	_slab(-14.0, 101.0, -10.0, 112.0, 0.0, MAT_CARPET)
	_slab(-14.0, 101.0, -10.0, 112.0, 2.8, MAT_CEILING)
	_wall(false, -14.0, 101.15, 112.0, 0.0, 2.6, _m_glass)
	_wall(false, -10.0, 101.15, 112.0, 0.0, 2.6, _m_glass)
	# 玻璃磚格線（只做內側面）
	for side in [[-13.83, 1.0], [-10.17, -1.0]]:
		var x: float = side[0]
		var z := 101.4
		while z < 112.0:
			_box(Vector3(x, 1.3, z), Vector3(0.04, 2.6, 0.05), _m_mullion, false)
			z += 0.5
		for yy in [0.5, 1.0, 1.5, 2.0]:
			_box(Vector3(x, yy, 106.6), Vector3(0.04, 0.05, 10.9), _m_mullion, false)
	for lz in [104.0, 109.0]:
		_omni(Vector3(-12.0, 2.2, lz), Color(0.70, 0.45, 1.0), 0.8, 5.0)


# --- L: 檯燈客廳（前室 z[112..119]、拱門、後室 z[119..126]）---
func _build_lounge() -> void:
	_slab(-22.0, 112.0, -4.0, 126.0, 0.0, _m_rug)
	_slab(-22.0, 112.0, -4.0, 126.0, 3.4, MAT_CEILING)
	_wall(true, 112.0, -22.0, -4.0, 0.0, 3.2, _m_warm, [Vector4(-13.0, -11.0, 0.0, 2.4)])
	_wall(false, -22.0, 112.0, 126.0, 0.0, 3.2, _m_warm)
	_wall(true, 126.0, -22.0, -4.0, 0.0, 3.2, _m_warm)
	_wall(false, -4.0, 112.0, 118.0, 0.0, 3.2, _m_warm) # z[118..126] 由白色挑高廳西牆提供
	# 內牆 z=119，開口 x[-15..-11] 上緣用階梯狀填塊做出圓拱
	_wall(true, 119.0, -22.0, -4.0, 0.0, 3.2, _m_warm, [Vector4(-15.0, -11.0, 0.0, 3.0)])
	var c := 1.7
	while c < 3.0:
		var w := sqrt(maxf(0.0, 4.0 - (c - 1.0) * (c - 1.0)))
		var fill := 2.0 - w
		if fill > 0.02:
			_box(Vector3(-15.0 + fill * 0.5, c, 119.0), Vector3(fill, 0.2, 0.3), _m_warm, false)
			_box(Vector3(-11.0 - fill * 0.5, c, 119.0), Vector3(fill, 0.2, 0.3), _m_warm, false)
		c += 0.2
	# 牆腳線
	_box(Vector3(-13.0, 0.06, 112.17), Vector3(18.0, 0.12, 0.04), _mat_wood, false)
	_box(Vector3(-13.0, 0.06, 125.83), Vector3(18.0, 0.12, 0.04), _mat_wood, false)
	# 落地燈的暖光（燈本體是 prop），加上天花吸頂燈
	_omni(Vector3(-20.6, 1.55, 113.4), Color(1.0, 0.70, 0.40), 1.1, 6.0)
	_omni(Vector3(-6.0, 1.55, 124.6), Color(1.0, 0.70, 0.40), 0.9, 6.0)
	_downlight(Vector3(-13.0, 3.18, 115.5), Color(1.0, 0.80, 0.55), 0.5, 6.0)
	_downlight(Vector3(-13.0, 3.18, 122.5), Color(1.0, 0.80, 0.55), 0.45, 6.0)
	_note("LoungeNote", Vector3(-8.0, 1.4, 125.83), 180.0, "閱讀牆上的紙條", "客廳紙條",
		"【檯燈客廳】\n兩盞燈都插著電，但插頭的另一頭沒有插座。\n\n"
		+ "「椅子還是溫的。我沒有坐下來，你也別坐。」")


# --- T: 青色大廳 + 熄燈區走廊 + V 黃色前室 ---
func _build_lobby() -> void:
	# 熄燈區南牆 x[8..10] → 大廳北牆
	_slab(8.0, 80.8, 10.0, 94.0, 0.0, MAT_CARPET)
	_slab(8.0, 80.8, 10.0, 94.0, 2.8, MAT_CEILING)
	_wall(false, 8.0, 80.8, 94.0, 0.0, 2.6, MAT_WALLPAPER)
	_wall(false, 10.0, 80.8, 94.0, 0.0, 2.6, MAT_WALLPAPER)
	_light(Vector3(9.0, 2.58, 85.0), 0.5, 5.0)
	_omni(Vector3(9.0, 2.2, 92.0), Color(0.55, 0.85, 0.85), 0.5, 4.0) # 盡頭透出的青光

	var x1 := 2.0
	var x2 := 26.0
	var z1 := 94.0
	var z2 := 113.0
	_slab(x1, z1, x2, z2, 0.0, _m_orange)
	_slab(x1, z1, x2, z2, 4.2, _m_white)
	_wall(true, z1, x1, x2, 0.0, 4.0, _m_teal, [Vector4(8.0, 10.0, 0.0, 2.6)])
	_wall(false, x1, z1, z2, 0.0, 4.0, _m_teal, [Vector4(96.0, 99.0, 0.0, 2.8)])
	_wall(false, x2, z1, z2, 0.0, 4.0, _m_teal, [Vector4(97.0, 100.0, 0.0, 2.6)]) # → 校舍翼
	_wall(true, z2, x1, x2, 0.0, 4.0, _m_teal, [Vector4(14.0, 17.0, 0.0, 2.6)])
	# 色塊：牆下半段藍色
	_box(Vector3(14.0, 0.6, 94.17), Vector3(24.0, 1.2, 0.04), _m_blue, false)
	_box(Vector3(25.83, 0.6, 95.25), Vector3(0.04, 1.2, 2.5), _m_blue, false)
	_box(Vector3(25.83, 0.6, 106.75), Vector3(0.04, 1.2, 12.5), _m_blue, false)
	_box(Vector3(14.0, 0.01, 111.3), Vector3(24.0, 0.02, 0.6), _m_blue, false) # 地面藍色色帶
	# 可走進去的藍色量體
	_wall(true, 100.0, 12.0, 20.0, 0.0, 3.0, _m_blue, [Vector4(14.5, 17.5, 0.0, 2.5)])
	_wall(true, 108.0, 12.0, 20.0, 0.0, 3.0, _m_blue)
	_wall(false, 12.0, 100.0, 108.0, 0.0, 3.0, _m_blue)
	_wall(false, 20.0, 100.0, 108.0, 0.0, 3.0, _m_blue)
	_slab(11.85, 99.85, 20.15, 108.15, 3.15, _m_blue, 0.15)
	_omni(Vector3(16.0, 2.4, 105.0), Color(0.55, 0.65, 1.0), 0.5, 5.0)
	# 柱子
	for p in [Vector2(6.0, 100.0), Vector2(22.0, 100.0), Vector2(6.0, 107.0), Vector2(22.0, 107.0)]:
		_box(Vector3(p.x, 2.0, p.y), Vector3(0.8, 4.0, 0.8), _m_blue)
	# 櫃台
	_box(Vector3(6.5, 0.5, 109.6), Vector3(5.0, 1.0, 0.8), _m_teal)
	_box(Vector3(6.5, 1.03, 109.6), Vector3(5.2, 0.06, 1.0), _m_orange)
	# 長條吊燈
	for lz in [97.0, 111.0]:
		for lx in [6.0, 14.0, 22.0]:
			_glow(Vector3(lx, 3.2, lz), Vector3(2.4, 0.08, 0.16), _m_lamp)
			_box(Vector3(lx - 1.0, 3.6, lz), Vector3(0.02, 0.8, 0.02), _mat_rail, false)
			_box(Vector3(lx + 1.0, 3.6, lz), Vector3(0.02, 0.8, 0.02), _mat_rail, false)
			_omni(Vector3(lx, 2.9, lz), Color(0.95, 0.95, 0.88), 0.75, 7.5)

	# V 黃色前室
	_slab(12.0, 113.0, 19.0, 118.0, 0.0, _m_cream)
	_slab(12.0, 113.0, 19.0, 118.0, 2.8, _m_yellow_ceil)
	_wall(false, 12.0, 113.15, 117.85, 0.0, 2.6, _m_white)
	_wall(false, 19.0, 113.15, 117.85, 0.0, 2.6, _m_white)
	_glow(Vector3(12.2, 1.8, 115.5), Vector3(0.1, 0.3, 0.22), _m_lamp)
	_omni(Vector3(12.8, 1.8, 115.5), Color(1.0, 0.80, 0.50), 0.9, 5.0)


# --- W: 白色挑高廳 ---
func _build_loft() -> void:
	var x1 := -4.0
	var x2 := 26.0
	var z1 := 118.0
	var z2 := 146.0
	_slab_hole(x1, z1, x2, z2, 0.0, Rect2(4.0, 142.0, 4.0, 4.0), _m_orange)
	_slab(x1, z1, x2, z2, 9.2, _m_white)
	_wall(true, z1, x1, x2, 0.0, 9.0, _m_white, [Vector4(14.0, 17.0, 0.0, 2.6)])
	_wall(false, x1, z1, z2, 0.0, 9.0, _m_white, [Vector4(121.0, 124.0, 0.0, 2.8)])
	_wall(false, x2, z1, z2, 0.0, 9.0, _m_white, [Vector4(120.0, 136.0, 5.5, 8.0), Vector4(139.5, 142.5, 0.0, 2.6)])
	# 南牆：下樓梯口 x[4..8]、夾層接回程走道 x[8..12]
	_wall(true, z2, x1, x2, -2.0, 11.0, _m_white, [Vector4(4.0, 8.0, -2.0, 3.8), Vector4(8.0, 12.0, 4.0, 7.0)])
	# 高窗：藍框 + 發光淡藍玻璃
	_box(Vector3(26.1, 6.75, 128.0), Vector3(0.05, 2.5, 16.0), _m_sky)
	var wz := 120.0
	while wz <= 136.01:
		_box(Vector3(25.9, 6.75, wz), Vector3(0.12, 2.5, 0.12), _m_blue, false)
		wz += 2.0
	_box(Vector3(25.9, 6.75, 128.0), Vector3(0.12, 0.1, 16.0), _m_blue, false)
	_omni(Vector3(24.0, 6.5, 128.0), Color(0.75, 0.85, 1.0), 0.8, 10.0)

	# 夾層 z[138..146] y 4
	_slab(x1, 138.0, x2, z2, 4.0, _m_gray)
	_box(Vector3(11.0, 4.55, 138.1), Vector3(30.0, 1.1, 0.2), _m_gray) # 矮牆
	var mx := -3.0
	while mx <= 25.01:
		_box(Vector3(mx, 6.3, 138.1), Vector3(0.1, 2.4, 0.1), _mat_rail, false) # 室內窗框帶
		mx += 2.0
	_box(Vector3(11.0, 7.65, 138.1), Vector3(30.0, 0.3, 0.2), _m_gray, false)
	for cx in [0.0, 10.0, 16.0, 22.0]:
		_box(Vector3(cx, 1.9, 138.3), Vector3(0.3, 3.8, 0.3), _mat_rail) # 鋼柱

	# 往下的樓梯 z 142 → 146（到 y -2），兩側灰色斜矮牆
	_stairs(Vector3(6.0, -2.0, 146.0), Vector3(0, 0, -1), 4.0, 10, 0.2, 0.4, _m_gray, true)
	var ang := atan2(1.0, 2.0)
	for px in [3.85, 8.15]:
		_box(Vector3(px, -0.5, 144.0), Vector3(0.3, 3.0, 4.0), _m_gray)
		_box(Vector3(px, 0.42, 141.0), Vector3(0.3, 0.16, sqrt(5.0)), _m_gray, false, Vector3(-ang, 0, 0))

	# 八葉吊扇（只在遊戲中轉）
	_box(Vector3(11.0, 8.85, 128.0), Vector3(0.08, 0.7, 0.08), _mat_rail, false)
	_fan = Node3D.new()
	_fan.name = "CeilingFan"
	_fan.position = Vector3(11.0, 8.45, 128.0)
	_lights.add_child(_fan)
	var hub := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.35
	hm.bottom_radius = 0.35
	hm.height = 0.18
	hm.radial_segments = 10
	hub.mesh = hm
	hub.material_override = _m_gray
	_fan.add_child(hub)
	for i in 8:
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.6, 0.04, 0.38)
		blade.mesh = bm
		blade.material_override = _m_white
		var a := i * PI / 4.0
		blade.position = Vector3(cos(a) * 1.6, 0.0, sin(a) * 1.6)
		blade.rotation = Vector3(0.12, -a, 0.0)
		_fan.add_child(blade)

	# 方形吸頂燈
	for lx in [2.0, 11.0, 20.0]:
		for lz in [122.0, 132.0]:
			_glow(Vector3(lx, 8.98, lz), Vector3(1.2, 0.04, 1.2), _m_lamp)
			_omni(Vector3(lx, 8.4, lz), Color(1.0, 0.98, 0.92), 1.0, 11.0)
		_glow(Vector3(lx, 3.78, 142.0), Vector3(0.9, 0.04, 0.9), _m_lamp)
		_omni(Vector3(lx, 3.4, 142.0), Color(1.0, 0.98, 0.92), 0.6, 6.0)
		_glow(Vector3(lx, 8.98, 142.0), Vector3(1.2, 0.04, 1.2), _m_lamp)
		_omni(Vector3(lx, 8.2, 142.0), Color(1.0, 0.98, 0.92), 0.6, 7.0)


# --- B: 藍色樓梯間 ---
func _build_stairwell() -> void:
	var x1 := 4.0
	var x2 := 12.0
	_slab(x1, 146.0, x2, 163.0, -2.0, _m_well)
	_slab(x1, 146.0, x2, 163.0, 7.7, _m_well)
	_wall(false, x1, 146.15, 163.0, -2.0, 9.5, _m_well)
	_wall(false, x2, 146.15, 163.0, -2.0, 9.5, _m_well)
	_wall(true, 163.0, x1, x2, -2.0, 9.5, _m_well)
	# 主梯：z 148 → 160，y -2 → 4
	_stairs(Vector3(6.0, -2.0, 148.0), Vector3(0, 0, 1), 4.0, 30, 0.2, 0.4, _m_well, true)
	_slab(x1, 160.0, x2, 163.0, 4.0, _m_well) # 頂部平台
	_slab(8.0, 146.0, x2, 160.0, 4.0, _m_well) # 回程走道 → 夾層
	_rail(false, 8.1, 146.0, 160.0, 4.0)
	_rail(false, 4.3, 148.0, 160.0, -2.0, 6.0)
	_rail(false, 7.85, 148.0, 160.0, -2.0, 6.0)
	# 頂端的天窗
	_box(Vector3(8.0, 6.1, 162.83), Vector3(6.0, 2.2, 0.04), _m_sky, false)
	_box(Vector3(8.0, 6.1, 162.8), Vector3(0.1, 2.2, 0.08), _m_white, false)
	_box(Vector3(8.0, 6.1, 162.8), Vector3(6.0, 0.1, 0.08), _m_white, false)
	_omni(Vector3(8.0, 6.0, 161.5), Color(0.80, 0.90, 1.0), 1.4, 12.0)
	_omni(Vector3(8.0, 1.0, 149.0), Color(0.45, 0.60, 1.0), 0.8, 7.0)
	_omni(Vector3(10.0, 6.5, 152.0), Color(0.45, 0.60, 1.0), 0.6, 7.0)
	_note("WellNote", Vector3(11.0, 5.4, 162.83), 180.0, "閱讀窗下的紙條", "樓梯間紙條",
		"【藍色樓梯間】\n窗外不是天空，是一片很亮的藍色牆。\n\n"
		+ "「往上走、轉身、再往回走。你會回到剛剛那個大房間的上面。這是我唯一確定的事。」")


func _build_tape_props() -> void:
	_prop("boat", Vector3(-30.0, 0.0, 98.2), 90.0)
	_prop("trashcan", Vector3(-21.0, 0.0, 95.4))
	_prop("plant", Vector3(1.0, 0.0, 95.0))
	# 客廳
	_prop("floor_lamp", Vector3(-20.6, 0.0, 113.0))
	_prop("armchair", Vector3(-18.6, 0.0, 114.4), 35.0)
	_prop("floor_lamp", Vector3(-5.0, 0.0, 125.0))
	_prop("armchair", Vector3(-7.5, 0.0, 124.6), 180.0)
	_prop("armchair", Vector3(-19.5, 0.0, 123.0), 90.0)
	_prop("plant", Vector3(-21.0, 0.0, 125.0))
	# 大廳：面對櫃台的椅子、藍色量體裡一張椅子
	for cx in [4.8, 6.5, 8.2]:
		_prop("chair", Vector3(cx, 0.0, 111.4), 180.0)
	_prop("chair", Vector3(16.0, 0.0, 106.5), 0.0)
	_prop("trashcan", Vector3(25.4, 0.0, 94.6))
	_prop("plant", Vector3(25.0, 0.0, 112.0))
	# 挑高廳與夾層
	_prop("ladder", Vector3(25.75, 0.0, 144.5), 90.0)
	for cx in [-2.5, -1.8, -1.1]:
		_prop("chair", Vector3(cx, 0.0, 119.0), 0.0)
	_prop("cardboard_boxes", Vector3(24.5, 4.0, 145.0), 20.0)
	_prop("box_closed", Vector3(23.4, 4.0, 145.2), 45.0)
	_prop("plant", Vector3(-3.0, 4.0, 145.0))
	_prop("bucket", Vector3(11.0, -2.0, 147.0))
