@tool
extends "res://scripts/level0_tapes.gd"
# Level 0「校舍」翼：參考另一批 VHS 影像（學校走廊、黃色大廳與斜坡、圍圈的椅子、
# 有半牆的黃色走廊、室內建築立面、空蕩大房間）。在錄影帶翼東側，兩個入口、一個迴圈：
#   S1 校舍走廊  x[26..60]  z[97..101]   米色牆、長日光燈管、壁畫、灰門；西接青色大廳東牆 z[97..100]
#   C  教室      x[30..52]  z[84..97]    昏暗，一圈黑椅，東側黃色亮光壁龕；由 S1 北牆 x[36..38.5] 進入
#   D  黃色走廊  x[60..96]  z[97..101]   半牆（南側）、柱子、倒掛的木桌、天花亮洞、出口標誌
#   H  黃色大廳  x[60..96]  z[101..142]  高 9，方形天花燈陣列、壁柱、窗格；D 南側斜坡（y 0 → -2）下到廳底
#   W2 回程走廊  x[26..60]  z[139..143]  由白色挑高廳東牆 z[139.5..142.5] 出來，10 階下到 y -2 接大廳西牆
#   K  暗廳      x[60..96]  z[142..176]  高 14，南牆是室內建築立面，地上兩輛車
#   R  空房      x[64..92]  z[176..196]  由立面大門進入，一張高背椅、天窗、藍色窄門
# 最低地面 y -2.0（重生判定是 y < -2.4）。生成節點不設 owner（AGENTS.md）。

var _m_ywall: StandardMaterial3D
var _m_beige: StandardMaterial3D
var _m_ceilb: StandardMaterial3D
var _m_lino: StandardMaterial3D
var _m_lino_dark: StandardMaterial3D
var _m_stripe: StandardMaterial3D
var _m_dark: StandardMaterial3D
var _m_door: StandardMaterial3D
var _m_cgray: StandardMaterial3D
var _m_red_glow: StandardMaterial3D
var _m_pane: StandardMaterial3D
var _m_yglow: StandardMaterial3D
var _m_facade: StandardMaterial3D
var _m_car_w: StandardMaterial3D
var _m_car_r: StandardMaterial3D
var _m_mural_blue: StandardMaterial3D
var _m_mural_orange: StandardMaterial3D
var _m_mural_yellow: StandardMaterial3D
var _m_mural_sky: StandardMaterial3D
var _m_blue_glow: StandardMaterial3D


func _init_materials() -> void:
	super._init_materials()
	_m_ywall = _mat(Color(0.86, 0.74, 0.24))
	_m_beige = _mat(Color(0.84, 0.78, 0.60))
	_m_ceilb = _mat(Color(0.78, 0.72, 0.52))
	_m_lino = _mat(Color(0.72, 0.52, 0.20), 0.5)
	_m_lino_dark = _mat(Color(0.42, 0.30, 0.14), 0.55)
	_m_stripe = _mat(Color(0.30, 0.24, 0.42))
	_m_dark = _mat(Color(0.07, 0.07, 0.08))
	_m_door = _mat(Color(0.50, 0.50, 0.52))
	_m_cgray = _mat(Color(0.60, 0.56, 0.44), 0.95)
	_m_red_glow = _mat(Color(0.9, 0.10, 0.08), 0.5, 1.6)
	_m_pane = _mat(Color(0.12, 0.16, 0.28), 0.4, 0.5)
	_m_yglow = _mat(Color(0.95, 0.85, 0.30), 0.5, 1.0)
	_m_facade = _mat(Color(0.80, 0.78, 0.60))
	_m_car_w = _mat(Color(0.78, 0.78, 0.74), 0.5)
	_m_car_r = _mat(Color(0.75, 0.18, 0.10), 0.5)
	_m_mural_blue = _mat(Color(0.12, 0.30, 0.70))
	_m_mural_orange = _mat(Color(0.92, 0.45, 0.10))
	_m_mural_yellow = _mat(Color(0.96, 0.80, 0.20))
	_m_mural_sky = _mat(Color(0.62, 0.78, 0.92))
	_m_blue_glow = _mat(Color(0.30, 0.30, 1.0), 0.5, 2.0)


func _zone_env(zone: String) -> Array:
	match zone:
		"vhs_school":
			return [Color(0.66, 0.58, 0.36), 0.04, Color(0.80, 0.72, 0.50), 0.5]
		"vhs_dim":
			return [Color(0.22, 0.18, 0.10), 0.07, Color(0.40, 0.32, 0.20), 0.2]
		"vhs_yellow":
			return [Color(0.72, 0.60, 0.20), 0.03, Color(0.82, 0.72, 0.34), 0.5]
		"vhs_gym":
			return [Color(0.72, 0.62, 0.20), 0.012, Color(0.85, 0.75, 0.32), 0.55]
		"vhs_court":
			return [Color(0.14, 0.13, 0.07), 0.03, Color(0.36, 0.33, 0.20), 0.32]
		"vhs_empty":
			return [Color(0.80, 0.66, 0.42), 0.012, Color(0.88, 0.76, 0.52), 0.55]
	return super._zone_env(zone)


func _build() -> void:
	_make_roots("School")
	_build_school_corridor()
	_build_classroom()
	_build_yellow_walk()
	_build_gym_hall()
	_build_return_corridor()
	_build_court()
	_build_empty_room()
	_build_map_link()
	_build_school_props()
	# 觸發區與錄影帶翼（最東到 x=26.2）只相接不重疊
	_trigger("ZoneSchool", Vector3(43.2, 1.5, 99.0), Vector3(33.6, 3.0, 4.0), "vhs_school")
	_trigger("ZoneClassroom", Vector3(41.0, 1.5, 90.5), Vector3(21.6, 3.0, 12.4), "vhs_dim")
	_trigger("ZoneYellowWalk", Vector3(78.0, 1.7, 99.0), Vector3(36.0, 3.4, 4.0), "vhs_yellow")
	_trigger("ZoneGym", Vector3(78.0, 3.5, 121.5), Vector3(35.6, 11.4, 41.0), "vhs_gym")
	_trigger("ZoneReturn", Vector3(43.2, 0.5, 141.0), Vector3(33.6, 5.4, 3.8), "vhs_school")
	_trigger("ZoneCourt", Vector3(78.0, 5.0, 159.0), Vector3(35.6, 14.0, 33.6), "vhs_court")
	_trigger("ZoneEmptyRoom", Vector3(78.0, 1.0, 186.1), Vector3(27.6, 6.0, 19.6), "vhs_empty")


# 在牆面上畫一格窗：外框 + 玻璃 + 格線；z 為窗面所在平面
func _window(cx: float, cy: float, w: float, h: float, z: float, cols: int, rows: int) -> void:
	_box(Vector3(cx, cy, z), Vector3(w, h, 0.08), _m_pane, false)
	for i in range(cols + 1):
		var x := cx - w * 0.5 + w * i / float(cols)
		_box(Vector3(x, cy, z - 0.03), Vector3(0.06, h + 0.06, 0.05), _m_facade, false)
	for j in range(rows + 1):
		var y := cy - h * 0.5 + h * j / float(rows)
		_box(Vector3(cx, y, z - 0.03), Vector3(w + 0.06, 0.06, 0.05), _m_facade, false)


# --- S1: 校舍走廊 ---
func _build_school_corridor() -> void:
	_slab(26.0, 97.0, 60.0, 101.0, 0.0, _m_lino)
	_slab(26.0, 97.0, 60.0, 101.0, 3.2, _m_ceilb)
	_wall(true, 97.0, 26.0, 60.0, 0.0, 3.0, _m_beige, [Vector4(36.0, 38.5, 0.0, 2.6)])
	_wall(true, 101.0, 26.0, 60.0, 0.0, 3.0, _m_beige)
	# 牆腳灰色踢腳板
	_box(Vector3(43.0, 0.1, 97.17), Vector3(34.0, 0.2, 0.04), _m_door, false)
	_box(Vector3(43.0, 0.1, 100.83), Vector3(34.0, 0.2, 0.04), _m_door, false)
	for lx in [30.0, 38.0, 46.0, 54.0]:
		_glow(Vector3(lx, 2.95, 99.0), Vector3(3.0, 0.06, 0.2), _m_lamp)
		_omni(Vector3(lx, 2.5, 99.0), Color(1.0, 0.95, 0.72), 0.75, 7.0)
	# 南牆壁畫（原創圖樣與字）：藍底、橘色日輪、淺藍雙翼
	var mz := 100.8
	_box(Vector3(32.0, 1.5, mz), Vector3(3.4, 2.4, 0.04), _m_mural_blue, false)
	_box(Vector3(32.0, 1.2, mz - 0.03), Vector3(1.3, 1.3, 0.04), _m_mural_orange, false)
	_box(Vector3(32.0, 0.9, mz - 0.06), Vector3(0.8, 0.7, 0.04), _m_mural_yellow, false)
	_box(Vector3(31.0, 0.7, mz - 0.03), Vector3(1.4, 0.35, 0.04), _m_mural_sky, false, Vector3(0, 0, 0.35))
	_box(Vector3(33.0, 0.7, mz - 0.03), Vector3(1.4, 0.35, 0.04), _m_mural_sky, false, Vector3(0, 0, -0.35))
	var cap := Label3D.new()
	cap.text = "MARINA"
	cap.font_size = 64
	cap.pixel_size = 0.006
	cap.modulate = Color(0.92, 0.94, 1.0)
	cap.outline_size = 0
	cap.position = Vector3(32.0, 2.35, mz - 0.07)
	cap.rotation.y = PI
	_lights.add_child(cap)
	# 北牆喇叭盒、南牆灰色門板（只是門片，打不開）
	_box(Vector3(31.5, 2.4, 97.25), Vector3(0.32, 0.32, 0.12), _mat_pale, false)
	for dx in [44.0, 52.0]:
		_box(Vector3(dx, 1.05, 100.82), Vector3(1.0, 2.1, 0.05), _m_door, false)
		_box(Vector3(dx - 0.35, 1.0, 100.78), Vector3(0.06, 0.1, 0.05), _mat_rail, false)


# --- C: 教室 ---
func _build_classroom() -> void:
	_slab(30.0, 84.0, 52.0, 97.0, 0.0, _m_lino_dark)
	_slab(30.0, 84.0, 52.0, 97.0, 3.2, MAT_CEILING)
	_wall(true, 84.0, 30.0, 52.0, 0.0, 3.0, _m_beige)
	_wall(false, 30.0, 84.0, 97.0, 0.0, 3.0, _m_beige)
	_wall(false, 52.0, 84.0, 97.0, 0.0, 3.0, _m_beige, [Vector4(88.0, 95.0, 0.0, 2.4)])
	# 東側壁龕：黃色牆、發亮的盡頭
	_slab(52.0, 88.0, 54.5, 95.0, 0.0, _m_lino_dark)
	_slab(52.0, 88.0, 54.5, 95.0, 2.6, _m_ceilb)
	_wall(true, 88.0, 52.0, 54.5, 0.0, 2.6, _m_ywall)
	_wall(true, 95.0, 52.0, 54.5, 0.0, 2.6, _m_ywall)
	_box(Vector3(54.4, 1.3, 91.5), Vector3(0.12, 2.6, 7.0), _m_yglow)
	for pz in [89.8, 91.5, 93.2]:
		_box(Vector3(52.25, 1.3, pz), Vector3(0.5, 2.6, 0.3), _m_ywall, false)
	# 黑板
	_box(Vector3(30.2, 1.6, 90.5), Vector3(0.06, 1.3, 7.0), _m_dark, false)
	_box(Vector3(30.2, 0.95, 90.5), Vector3(0.1, 0.05, 7.1), _mat_wood, false)
	_omni(Vector3(41.0, 2.6, 90.5), Color(1.0, 0.82, 0.50), 0.45, 9.0)
	_omni(Vector3(53.3, 2.0, 91.5), Color(1.0, 0.90, 0.30), 1.4, 9.0)
	_note("ClassNote", Vector3(36.0, 1.4, 84.15), 0.0, "閱讀黑板旁的紙條", "教室紙條",
		"【教室】\n十張椅子圍成一圈，全都朝裡面。圈中間什麼都沒有。\n\n"
		+ "「點名的時候，我聽到第十一個人答『到』。」")


# --- D: 黃色走廊（南側半牆，看得到下面的大廳）---
func _build_yellow_walk() -> void:
	_slab(60.0, 97.0, 96.0, 101.0, 0.0, _m_cgray)
	_slab(60.0, 97.0, 96.0, 101.0, 3.6, _m_ceilb)
	_wall(true, 97.0, 60.0, 96.0, 0.0, 3.4, _m_ywall)
	_wall(false, 96.0, 97.0, 101.0, 0.0, 3.4, _m_ywall)
	# 南側：半牆 1.1 + 柱 + 上方整面牆（斜坡口 x[70..86] 不設半牆）
	_wall_piece(true, 101.0, 60.0, 69.75, 0.0, 1.1, _m_ywall)
	_wall_piece(true, 101.0, 86.25, 96.0, 0.0, 1.1, _m_ywall)
	_wall_piece(true, 101.0, 60.0, 96.0, 3.4, 9.0, _m_ywall)
	for px in [62.0, 66.0, 70.0, 86.0, 90.0, 94.0]:
		_box(Vector3(px, 1.7, 101.0), Vector3(0.5, 3.4, 0.5), _m_ywall)
	_box(Vector3(78.0, 1.7, 101.2), Vector3(0.7, 3.4, 0.7), _m_ywall) # 斜坡口中間的大柱
	# 半牆壓條
	_box(Vector3(64.9, 1.12, 101.0), Vector3(9.8, 0.06, 0.4), _m_white, false)
	_box(Vector3(91.1, 1.12, 101.0), Vector3(9.8, 0.06, 0.4), _m_white, false)
	# 倒掛在柱子上的木桌（桌面朝下、腳朝上；純裝飾）
	_box(Vector3(78.0, 2.3, 102.0), Vector3(1.3, 0.05, 0.8), _mat_wood, false)
	for lx in [77.45, 78.55]:
		for lz in [101.7, 102.3]:
			_box(Vector3(lx, 2.7, lz), Vector3(0.05, 0.8, 0.05), _mat_wood, false)
	# 天花亮洞、出口標誌、日光燈
	_glow(Vector3(84.0, 3.38, 99.0), Vector3(2.4, 0.04, 2.4), _m_lamp)
	_omni(Vector3(84.0, 2.6, 99.0), Color(1.0, 0.95, 0.70), 1.8, 9.0)
	_glow(Vector3(68.0, 3.3, 99.0), Vector3(2.4, 0.05, 0.22), _m_lamp)
	_omni(Vector3(68.0, 2.8, 99.0), Color(1.0, 0.95, 0.72), 0.7, 7.0)
	_box(Vector3(92.0, 2.9, 97.2), Vector3(0.5, 0.2, 0.08), _m_red_glow, false)
	_omni(Vector3(92.0, 2.5, 98.0), Color(1.0, 0.25, 0.15), 0.4, 4.0)


# --- H: 黃色大廳 ---
func _build_gym_hall() -> void:
	var x1 := 60.0
	var x2 := 96.0
	var z1 := 101.0
	var z2 := 142.0
	_slab(x1, z1, x2, z2, -2.0, _m_cream)
	_slab(x1, z1, x2, z2, 9.2, _m_ceilb)
	_wall(false, x1, z1, z2, -2.0, 11.0, _m_ywall, [Vector4(139.5, 142.5, -2.0, 0.6)])
	_wall(false, x2, z1, z2, -2.0, 11.0, _m_ywall)
	_wall(true, z2, x1, x2, -2.0, 11.0, _m_ywall, [Vector4(76.0, 80.0, -2.0, 0.6)])
	# 斜坡：z 101（y 0）→ 117（y -2），寬 x[70..86]
	var ang := atan2(2.0, 16.0)
	var ln := sqrt(16.0 * 16.0 + 2.0 * 2.0)
	var cy := -1.0 - 0.1 * cos(ang)
	_box(Vector3(78.0, cy, 109.0), Vector3(16.0, 0.2, ln + 0.3), _m_cream, true, Vector3(ang, 0, 0))
	for sx in [71.0, 74.5, 78.0, 81.5, 85.0]:
		_box(Vector3(sx, cy + 0.11 * cos(ang), 109.0 + 0.11 * sin(ang)), Vector3(0.18, 0.02, ln), _m_stripe, false, Vector3(ang, 0, 0))
	# 廳底的深色線條
	_box(Vector3(78.0, -1.99, 121.0), Vector3(36.0, 0.02, 0.2), _m_stripe, false)
	_box(Vector3(78.0, -1.99, 131.0), Vector3(36.0, 0.02, 0.2), _m_stripe, false)
	_box(Vector3(78.0, -1.99, 126.0), Vector3(0.2, 0.02, 10.0), _m_stripe, false)
	# 壁柱
	for pz in [108.0, 114.0, 120.0, 126.0, 132.0, 138.0]:
		_box(Vector3(60.4, 3.5, pz), Vector3(0.5, 11.0, 0.5), _m_ywall, false)
		_box(Vector3(95.6, 3.5, pz), Vector3(0.5, 11.0, 0.5), _m_ywall, false)
	# 南牆大窗格（玻璃外面是黑的）
	_window(78.0, 5.0, 8.0, 4.0, 141.8, 8, 4)
	# 天花方形燈陣列
	for lx in [66.0, 72.0, 78.0, 84.0, 90.0]:
		for lz in [106.0, 114.0, 122.0, 130.0, 138.0]:
			_glow(Vector3(lx, 8.98, lz), Vector3(1.1, 0.04, 1.1), _m_lamp)
	for lx in [66.0, 78.0, 90.0]:
		for lz in [108.0, 122.0, 136.0]:
			_omni(Vector3(lx, 8.0, lz), Color(1.0, 0.95, 0.70), 1.0, 14.0)
	_note("GymNote", Vector3(61.0, 1.4, 110.0), 90.0, "閱讀牆上的紙條", "黃色大廳紙條",
		"【黃色大廳】\n斜坡有三條深色線，我順著走，最後還是回到起點旁邊。\n\n"
		+ "「燈一共五十盞。我數了兩次，答案不一樣。」")


# --- W2: 白色挑高廳 → 黃色大廳的回程走廊 ---
func _build_return_corridor() -> void:
	_slab(26.0, 139.0, 48.0, 143.0, 0.0, _m_lino)
	_slab(48.0, 139.0, 60.0, 143.0, -2.0, _m_lino)
	_slab(26.0, 139.0, 60.0, 143.0, 3.2, _m_ceilb)
	_wall(true, 139.0, 26.0, 60.0, -2.0, 5.0, _m_beige)
	_wall(true, 143.0, 26.0, 60.0, -2.0, 5.0, _m_beige)
	# 10 階往下（從 x 48 的 y 0 到 x 52 的 y -2）
	_stairs(Vector3(52.0, -2.0, 141.0), Vector3(-1, 0, 0), 3.7, 10, 0.2, 0.4, _m_door, true)
	for lx in [32.0, 40.0, 54.0]:
		_glow(Vector3(lx, 2.95, 141.0), Vector3(3.0, 0.06, 0.2), _m_lamp)
		_omni(Vector3(lx, 2.5, 141.0), Color(1.0, 0.95, 0.72), 0.7, 7.0)
	for dx in [34.0, 42.0]:
		_box(Vector3(dx, 1.05, 142.82), Vector3(1.0, 2.1, 0.05), _m_door, false)


# --- K: 暗廳（室內的建築立面）---
func _build_court() -> void:
	var x1 := 60.0
	var x2 := 96.0
	# 通道 z[142..146]
	_slab(76.0, 142.0, 80.0, 146.0, -2.0, _m_lino)
	_slab(76.0, 142.0, 80.0, 146.0, 0.8, _m_ywall)
	_wall(false, 76.0, 142.0, 146.0, -2.0, 2.8, _m_ywall)
	_wall(false, 80.0, 142.0, 146.0, -2.0, 2.8, _m_ywall)
	_slab(x1, 146.0, x2, 176.0, -2.0, _mat_concrete)
	_slab(x1, 146.0, x2, 176.0, 12.2, _mat_thick)
	_wall(false, x1, 146.0, 176.0, -2.0, 14.0, _mat_thick)
	_wall(false, x2, 146.0, 176.0, -2.0, 14.0, _mat_thick)
	_wall(true, 146.0, x1, x2, -2.0, 14.0, _mat_thick, [Vector4(76.0, 80.0, -2.0, 0.6)])
	# 立面（整面牆，中間是大門 → 空房）
	_wall(true, 176.0, x1, x2, -2.0, 14.0, _m_facade, [Vector4(76.0, 80.0, -2.0, 0.8)])
	_box(Vector3(78.0, 3.6, 175.6), Vector3(36.0, 0.3, 0.5), _m_facade, false) # 腰線
	_box(Vector3(78.0, 11.8, 175.6), Vector3(36.0, 0.4, 0.5), _m_facade, false) # 簷口
	for px in [63.0, 69.0, 87.0, 93.0]:
		_box(Vector3(px, 5.0, 175.75), Vector3(0.6, 14.0, 0.3), _m_facade, false)
	_box(Vector3(75.7, -0.4, 175.7), Vector3(0.4, 3.2, 0.35), _m_facade, false)
	_box(Vector3(80.3, -0.4, 175.7), Vector3(0.4, 3.2, 0.35), _m_facade, false)
	_box(Vector3(78.0, 1.2, 175.7), Vector3(5.0, 0.4, 0.35), _m_facade, false)
	var plate := Label3D.new()
	plate.text = "NORTH ARCHIVE"
	plate.font_size = 40
	plate.pixel_size = 0.006
	plate.modulate = Color(0.22, 0.20, 0.14)
	plate.outline_size = 0
	plate.position = Vector3(78.0, 1.75, 175.5)
	plate.rotation.y = PI
	_lights.add_child(plate)
	for wx in [66.0, 72.0, 78.0, 84.0, 90.0]:
		_window(wx, 4.6, 2.0, 4.4, 175.8, 2, 4)
	for wx in [66.0, 72.0, 84.0, 90.0]:
		_window(wx, -0.2, 1.4, 1.5, 175.8, 2, 2)
	# 兩輛車
	_box(Vector3(69.5, -1.45, 170.0), Vector3(4.2, 0.7, 1.8), _m_car_w, true, Vector3(0, 0.43, 0))
	_box(Vector3(69.3, -0.9, 170.1), Vector3(2.0, 0.55, 1.6), _m_car_w, true, Vector3(0, 0.43, 0))
	_box(Vector3(87.0, -1.3, 171.5), Vector3(4.2, 0.7, 1.8), _m_car_r, false, Vector3(0.0, -0.3, 0.5))
	_box(Vector3(87.2, -0.8, 171.4), Vector3(2.0, 0.5, 1.6), _m_dark, false, Vector3(0.0, -0.3, 0.5))
	# 光：大門前一團暖光，其餘昏暗
	_omni(Vector3(78.0, 0.5, 173.0), Color(1.0, 0.85, 0.50), 2.2, 13.0)
	_omni(Vector3(78.0, 6.0, 158.0), Color(0.80, 0.80, 0.60), 0.4, 26.0)
	_omni(Vector3(78.0, 5.0, 169.0), Color(0.85, 0.85, 0.65), 1.0, 20.0)
	_omni(Vector3(78.0, 0.0, 148.0), Color(1.0, 0.85, 0.55), 0.8, 8.0)
	_note("CourtNote", Vector3(95.8, 0.6, 160.0), -90.0, "閱讀牆上的紙條", "暗廳紙條",
		"【暗廳】\n這是一棟房子的正面，擺在房間裡面。窗戶是黑的，門是開的。\n\n"
		+ "「車子停得很整齊，只有那輛紅的躺在地上。」")


# --- R: 空房 ---
func _build_empty_room() -> void:
	_slab(64.0, 176.0, 92.0, 196.0, -2.0, _m_cream)
	_slab(64.0, 176.0, 92.0, 196.0, 4.2, _m_ceilb)
	_wall(false, 64.0, 176.0, 196.0, -2.0, 6.0, _m_beige)
	_wall(false, 92.0, 176.0, 196.0, -2.0, 6.0, _m_beige, [Vector4(184.0, 188.0, -2.0, 0.9)])
	_wall(true, 196.0, 64.0, 92.0, -2.0, 6.0, _m_beige)
	# 天窗與天花條
	_glow(Vector3(80.0, 3.97, 188.0), Vector3(6.0, 0.06, 1.4), _m_lamp)
	_omni(Vector3(80.0, 3.0, 188.0), Color(1.0, 0.92, 0.65), 1.8, 18.0)
	for sx in [70.0, 90.0]:
		_box(Vector3(sx, 3.96, 186.0), Vector3(0.6, 0.06, 20.0), _mat_pale, false)
	# 南牆高窗、西牆小凹口、東側藍色窄門
	for wx in [72.0, 78.0, 86.0]:
		_box(Vector3(wx, 2.6, 195.82), Vector3(2.0, 0.9, 0.06), _m_pane, false)
	_box(Vector3(64.1, -1.2, 181.0), Vector3(0.06, 1.6, 1.0), _m_dark, false)
	_box(Vector3(89.0, -0.9, 195.85), Vector3(1.2, 2.2, 0.08), _m_blue_glow, false)
	_omni(Vector3(89.0, -0.6, 194.6), Color(0.40, 0.40, 1.0), 0.8, 5.0)
	_box(Vector3(74.0, -1.98, 186.0), Vector3(16.0, 0.02, 0.25), _m_dark, false) # 地上的黑線
	# 高背椅（碰撞只用一個小盒子）
	_box(Vector3(82.0, -1.0, 190.0), Vector3(0.5, 0.06, 0.5), _mat_wood, false)
	_box(Vector3(82.0, -0.35, 190.23), Vector3(0.5, 1.2, 0.05), _mat_wood, false)
	for lx in [81.78, 82.22]:
		for lz in [189.78, 190.22]:
			_box(Vector3(lx, -1.5, lz), Vector3(0.04, 1.0, 0.04), _mat_rail, false)
	var chair_col := CollisionShape3D.new()
	var chair_bs := BoxShape3D.new()
	chair_bs.size = Vector3(0.5, 2.0, 0.5)
	chair_col.shape = chair_bs
	chair_col.position = Vector3(82.0, -1.0, 190.0)
	_body.add_child(chair_col)
	_note("EmptyNote", Vector3(70.0, 0.4, 195.83), 180.0, "閱讀牆上的紙條", "空房紙條",
		"【空房】\n只有一張椅子，椅背比人高。天花板的光剛好打在它身上。\n\n"
		+ "「藍色那扇門我沒打開過。它每次都比上一次亮一點。」")

# --- 空房東側通道 → Blender 地圖（街道廣場邊緣 x≈124）---
func _build_map_link() -> void:
	_slab(92.0, 184.0, 126.0, 188.0, -2.0, _m_cream)
	_slab(92.0, 184.0, 126.0, 188.0, 0.9, _m_ceilb)
	_wall(true, 184.0, 92.0, 126.0, -2.0, 2.9, _m_beige)
	_wall(true, 188.0, 92.0, 126.0, -2.0, 2.9, _m_beige, [Vector4(114.0, 118.0, -2.0, 0.7)])
	for lx in [98.0, 106.0, 114.0, 122.0]:
		var t: float = (lx - 98.0) / 24.0
		_glow(Vector3(lx, 0.82, 186.0), Vector3(1.2, 0.05, 0.5), _m_lamp)
		_omni(Vector3(lx, 0.4, 186.0), Color(1.0, 0.92, 0.65).lerp(Color(0.6, 0.7, 1.0), t), 0.9, 7.0)


func _build_school_props() -> void:
	# 教室：十張椅子圍成一圈，椅面朝圓心
	var rc := Vector2(41.0, 90.5)
	for i in 10:
		var a := TAU * i / 10.0
		var p := rc + Vector2(cos(a), sin(a)) * 3.6
		var yaw := rad_to_deg(atan2(-cos(a), -sin(a)))
		_prop("chair", Vector3(p.x, 0.0, p.y), yaw)
	_prop("desk", Vector3(33.0, 0.0, 85.2), 0.0)
	_prop("trashcan", Vector3(51.2, 0.0, 84.6))
	# 走廊與大廳
	_prop("trashcan", Vector3(59.2, 0.0, 97.6))
	_prop("plant", Vector3(27.0, 0.0, 100.2))
	_prop("armchair", Vector3(94.4, 0.0, 99.2), -90.0)
	_prop("cardboard_boxes", Vector3(94.0, -2.0, 138.5), 20.0)
	_prop("box_closed", Vector3(92.8, -2.0, 139.2), 40.0)
	_prop("trashcan", Vector3(95.2, -2.0, 112.0))
	_prop("plant", Vector3(27.0, 0.0, 142.2))
