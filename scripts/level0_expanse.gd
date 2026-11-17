@tool
class_name Level0Expanse
extends Node3D
# Level 0 西翼擴展區（x: -110 .. -44, z: 34 .. 104），從拱門變體西牆 z[44..48] 進入。
#   A 連接走廊      x[-52..-44]   z[44..48]   天花 3.0
#   B 下沉會議坑    x[-76..-52]   z[34..58]   天花 4.2，中央坑底 y -1.6
#   C 挑高中庭      x[-110..-76]  z[34..70]   天花 10，二樓 U 形迴廊 y 4.5
#   D1 低矮爬行層   x[-110..-76]  z[70..104]  天花 2.2（迷宮）
#   D2 上層辦公迷宮 同上範圍      y 4.5..7.5（迷宮，角落破洞掉回 D1）
#   E 高柱長廳      x[-76..-44]   z[58..104]  天花 6，抬高平台 y 1.5
# 東南翼（從深坑東牆 z[44.2..46.3] 進入，繞一圈回到熄燈區東牆 z[70..72]）：
#   F 梯田辦公室    x[26..56]  z[34..58]  四階地台 y 0/0.8/1.6/2.4，天花 6
#   G 螺旋塔        x[56..70]  z[34..48]  塔底 y 2.4，沿牆盤旋到 y 7.2，天花 14.5
#   H 貓道倉庫      x[56..86]  z[48..82]  地面 0，貓道 y 7.2，天花 11
#   I 斜坡 + 地下檔案室 x[26..56] z[60..80] 地面 y -2.0（深坑重生判定為 y < -2.4）
# 生成節點不設 owner（AGENTS.md）。

const MAT_WALLPAPER := preload("res://materials/mat_wallpaper.tres")
const MAT_CARPET := preload("res://materials/mat_carpet.tres")
const MAT_CEILING := preload("res://materials/mat_ceiling.tres")
const MAT_FLUORESCENT := preload("res://materials/mat_fluorescent.tres")
const MAT_WET_FLOOR := preload("res://materials/mat_wet_floor.tres")
const INTERACT_SCRIPT := preload("res://scripts/interactable_prop.gd")

const WT := 0.3 # 外牆厚度
const CELL := 3.4 # D 區迷宮格
const D_X0 := -110.0
const D_Z0 := 70.0
const D_N := 10
const UP_Y := 4.5 # 二樓地板高度
const CRAWL_H := 2.2
const HOLE := Vector2i(0, 9) # 上層破洞格 (col, row)
const CRAWL_DOOR_COL := 5 # 中庭→爬行層
const UPPER_DOOR_COL := 7 # 迴廊→上層迷宮
const EAST_DOOR_ROW := 5 # 爬行層→長廳

const LEVEL0_FOG_COLOR := Color(0.50, 0.47, 0.27)
const LEVEL0_FOG_DENSITY := 0.085
const LEVEL0_AMBIENT_COLOR := Color(0.65, 0.60, 0.38)
const LEVEL0_AMBIENT_ENERGY := 0.38

var _active_zone: String = ""
var _fade_t: float = 0.0
var _world_env: WorldEnvironment
var _player: Node3D
var _body: StaticBody3D
var _lights: Node3D
var _props: Node3D

var _mat_concrete: StandardMaterial3D
var _mat_rail: StandardMaterial3D
var _mat_wood: StandardMaterial3D
var _mat_pale: StandardMaterial3D
var _mat_thick: StandardMaterial3D


func _ready() -> void:
	_init_materials()
	if get_child_count() == 0:
		_build()
	if not Engine.is_editor_hint():
		_world_env = get_parent().get_node_or_null("WorldEnvironment")
		_player = get_parent().get_node_or_null("Player")


func _init_materials() -> void:
	_mat_concrete = StandardMaterial3D.new()
	_mat_concrete.albedo_color = Color(0.55, 0.53, 0.45)
	_mat_concrete.roughness = 0.95
	_mat_rail = StandardMaterial3D.new()
	_mat_rail.albedo_color = Color(0.36, 0.34, 0.28)
	_mat_rail.metallic = 0.4
	_mat_rail.roughness = 0.6
	_mat_wood = StandardMaterial3D.new()
	_mat_wood.albedo_color = Color(0.42, 0.30, 0.18)
	_mat_wood.roughness = 0.8
	_mat_pale = StandardMaterial3D.new()
	_mat_pale.albedo_color = Color(0.84, 0.82, 0.70)
	_mat_pale.roughness = 0.85
	_mat_thick = StandardMaterial3D.new()
	_mat_thick.albedo_color = Color(0.56, 0.49, 0.34)
	_mat_thick.roughness = 0.96


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _world_env or not _world_env.environment:
		return
	if _active_zone == "":
		if _fade_t <= 0.0:
			return # 不在本腳本的區域內：交給其他區域腳本控制環境
		_fade_t -= delta
	var p := _zone_env(_active_zone)
	var t := clampf(delta * 2.5, 0.0, 1.0)
	var env := _world_env.environment
	env.fog_light_color = env.fog_light_color.lerp(p[0], t)
	env.fog_density = lerpf(env.fog_density, p[1], t)
	env.ambient_light_color = env.ambient_light_color.lerp(p[2], t)
	env.ambient_light_energy = lerpf(env.ambient_light_energy, p[3], t)


# 回傳 [霧色, 霧密度, 環境光色, 環境光強度]；子類別覆寫以加入自己的區域
func _zone_env(zone: String) -> Array:
	match zone:
		"atrium": # 挑高空間要看得到對面迴廊
			return [LEVEL0_FOG_COLOR, 0.035, LEVEL0_AMBIENT_COLOR, 0.45]
		"tower", "warehouse":
			return [LEVEL0_FOG_COLOR, 0.04, Color(0.58, 0.58, 0.48), 0.42]
		"basement":
			return [Color(0.22, 0.24, 0.16), 0.12, Color(0.32, 0.36, 0.24), 0.2]
		"crawl":
			return [Color(0.30, 0.27, 0.15), 0.11, Color(0.40, 0.36, 0.22), 0.22]
	return [LEVEL0_FOG_COLOR, LEVEL0_FOG_DENSITY, LEVEL0_AMBIENT_COLOR, LEVEL0_AMBIENT_ENERGY]


# 離開區域時不硬切，用 2 秒漸變回預設（相鄰區域之間就有過渡）
func _set_zone(z: String) -> void:
	_active_zone = z
	if z == "":
		_fade_t = 2.0


func _make_roots(prefix: String) -> void:
	_body = StaticBody3D.new()
	_body.name = prefix + "Geometry"
	add_child(_body)
	_lights = Node3D.new()
	_lights.name = prefix + "Lights"
	add_child(_lights)
	_props = Node3D.new()
	_props.name = prefix + "Props"
	add_child(_props)


func _build() -> void:
	_make_roots("Expanse")

	_build_corridor()
	_build_pit_room()
	_build_atrium()
	_build_stacked_mazes()
	_build_column_hall()
	_build_terraces()
	_build_tower()
	_build_warehouse()
	_build_basement()
	_build_props()


# --- A: 拱門 → 會議坑 ---
func _build_corridor() -> void:
	_slab(-52.0, 44.0, -44.0, 48.0, 0.0, MAT_CARPET)
	_slab(-52.0, 44.0, -44.0, 48.0, 3.2, MAT_CEILING)
	_wall(true, 44.0, -52.0, -44.3, 0.0, 3.0, MAT_WALLPAPER)
	_wall(true, 48.0, -52.0, -44.3, 0.0, 3.0, MAT_WALLPAPER)
	_light(Vector3(-48.0, 2.98, 46.0), 0.6, 6.0)


# --- B: 下沉會議坑 ---
func _build_pit_room() -> void:
	var px1 := -70.0
	var px2 := -58.0
	var pz1 := 40.0
	var pz2 := 52.0
	var pit_y := -1.6
	# 坑周地板 + 坑底
	_slab(-76.0, 34.0, -52.0, pz1, 0.0, MAT_CARPET)
	_slab(-76.0, pz2, -52.0, 58.0, 0.0, MAT_CARPET)
	_slab(-76.0, pz1, px1, pz2, 0.0, MAT_CARPET)
	_slab(px2, pz1, -52.0, pz2, 0.0, MAT_CARPET)
	_slab(px1, pz1, px2, pz2, pit_y, _mat_thick)
	_slab(-76.0, 34.0, -52.0, 58.0, 4.4, MAT_CEILING)
	# 坑壁
	_box(Vector3((px1 + px2) * 0.5, pit_y * 0.5, pz1 + 0.1), Vector3(px2 - px1, -pit_y, 0.2), _mat_pale)
	_box(Vector3((px1 + px2) * 0.5, pit_y * 0.5, pz2 - 0.1), Vector3(px2 - px1, -pit_y, 0.2), _mat_pale)
	_box(Vector3(px1 + 0.1, pit_y * 0.5, (pz1 + pz2) * 0.5), Vector3(0.2, -pit_y, pz2 - pz1), _mat_pale)
	_box(Vector3(px2 - 0.1, pit_y * 0.5, (pz1 + pz2) * 0.5), Vector3(0.2, -pit_y, pz2 - pz1), _mat_pale)
	# 南北兩道下坑樓梯（從坑底往外爬），x[-66..-62]
	_stairs(Vector3(-64.0, pit_y, pz1 + 3.2), Vector3(0, 0, -1), 4.0, 8, 0.2, 0.4, _mat_pale, true)
	_stairs(Vector3(-64.0, pit_y, pz2 - 3.2), Vector3(0, 0, 1), 4.0, 8, 0.2, 0.4, _mat_pale, true)
	# 坑邊欄杆（樓梯口留空）
	_rail(true, pz1, px1, -66.0, 0.0)
	_rail(true, pz1, -62.0, px2, 0.0)
	_rail(true, pz2, px1, -66.0, 0.0)
	_rail(true, pz2, -62.0, px2, 0.0)
	_rail(false, px1, pz1, pz2, 0.0)
	_rail(false, px2, pz1, pz2, 0.0)
	# 坑底會議桌
	_box(Vector3(-64.0, pit_y + 0.375, 46.0), Vector3(5.0, 0.75, 1.8), _mat_wood)
	# 牆
	_wall(true, 34.0, -76.0, -52.0, 0.0, 4.4, MAT_WALLPAPER)
	_wall(false, -52.0, 34.0, 58.0, 0.0, 4.4, MAT_WALLPAPER, [Vector4(44.0, 48.0, 0.0, 3.0)])
	_wall(true, 58.0, -76.0, -52.0, 0.0, 6.0, MAT_WALLPAPER, [Vector4(-66.0, -62.0, 0.0, 2.8)])
	for lx in [-70.0, -58.0]:
		for lz in [37.0, 55.0]:
			_light(Vector3(lx, 4.18, lz), 0.65, 7.5)
	_light(Vector3(-64.0, 4.18, 46.0), 0.9, 9.0)
	_note("PitNote", Vector3(-64.0, pit_y + 0.76, 46.3), 0.0, "看看會議桌上的議程", "下沉會議坑紀錄",
		"【下沉會議坑】\n地板在這裡無緣無故凹下去一截，中央擺著一張沒人的會議桌。\n\n"
		+ "「議程第一項：『如何離開』。第二項到第四十項都被劃掉了。」")


# --- C: 挑高中庭 + 二樓 U 形迴廊 ---
func _build_atrium() -> void:
	var x1 := -110.0
	var x2 := -76.0
	var z1 := 34.0
	var z2 := 70.0
	var top := 10.0
	_slab(x1, z1, x2, z2, 0.0, MAT_CARPET)
	_slab(x1, z1, x2, z2, top + 0.2, MAT_CEILING)
	# 迴廊：北 z[34..38]、西 x[-110..-106]、南 z[66..70]
	_slab(x1, z1, x2, z1 + 4.0, UP_Y, MAT_CARPET, 0.3)
	_slab(x1, z1 + 4.0, x1 + 4.0, z2 - 4.0, UP_Y, MAT_CARPET, 0.3)
	_slab(x1, z2 - 4.0, x2, z2, UP_Y, MAT_CARPET, 0.3)
	_rail(true, z1 + 4.0, x1 + 4.0, x2, UP_Y)
	_rail(false, x1 + 4.0, z1 + 4.0, z2 - 4.0, UP_Y)
	_rail(true, z2 - 4.0, x1 + 4.0, -80.0, UP_Y)
	# 沿東牆上二樓的樓梯 x[-80..-77]，24 階 × 0.1875
	_stairs(Vector3(-78.5, 0.0, 56.4), Vector3(0, 0, 1), 3.0, 24, 0.1875, 0.4, _mat_pale, false)
	_rail(false, -80.05, 56.4, 66.0, 0.0, 4.5)
	# 牆
	var crawl_cx := D_X0 + (CRAWL_DOOR_COL + 0.5) * CELL
	var upper_cx := D_X0 + (UPPER_DOOR_COL + 0.5) * CELL
	_wall(true, z1, x1, x2, 0.0, top, _mat_pale)
	_wall(false, x1, z1, z2, 0.0, top, _mat_pale)
	_wall(false, x2, z1, z2, 0.0, top, _mat_pale, [Vector4(44.0, 48.0, 0.0, 3.0)])
	_wall(true, z2, x1, x2, 0.0, top, _mat_pale, [
		Vector4(crawl_cx - 1.0, crawl_cx + 1.0, 0.0, 2.1),
		Vector4(upper_cx - 1.0, upper_cx + 1.0, UP_Y, UP_Y + 2.5),
	])
	# 中庭吊燈 + 迴廊下方燈
	for lx in [-102.0, -93.0, -84.0]:
		for lz in [44.0, 56.0]:
			_light(Vector3(lx, top - 0.05, lz), 1.1, 13.0)
	for lx in [-100.0, -88.0]:
		_light(Vector3(lx, UP_Y - 0.32, 36.0), 0.55, 6.0)
		_light(Vector3(lx, UP_Y - 0.32, 68.0), 0.55, 6.0)
	_light(Vector3(-108.0, UP_Y - 0.32, 52.0), 0.55, 6.0)
	_trigger("AtriumTrigger", Vector3((x1 + x2) * 0.5, top * 0.5, (z1 + z2) * 0.5), Vector3(x2 - x1 - 0.6, top, z2 - z1 - 0.6), "atrium")
	_note("AtriumNote", Vector3(-76.3, 1.45, 50.0), -90.0, "閱讀樓梯旁的便條", "挑高中庭紀錄",
		"【挑高中庭】\n天花板高得不像 Level 0。往上看，二樓迴廊沿著三面牆繞了一圈。\n\n"
		+ "「南邊有兩扇門：一扇矮得要彎腰，一扇在二樓。兩扇最後都通到同一個地方——只是方式不同。」")
	_note("BalconyNote", Vector3(-93.0, UP_Y + 1.0, 66.1), 180.0, "閱讀迴廊欄杆上的紙條", "二樓迴廊",
		"「從這裡看下去，地毯上的污漬排成一個箭頭。我不打算照著走。」")


# --- D1 爬行層 + D2 上層迷宮（上下疊在同一塊地上）---
func _build_stacked_mazes() -> void:
	var x2 := D_X0 + D_N * CELL # -76
	var z2 := D_Z0 + D_N * CELL # 104
	var hole := Rect2(D_X0 + HOLE.x * CELL, D_Z0 + HOLE.y * CELL, CELL, CELL)
	# D1
	_slab(D_X0, D_Z0, x2, z2, 0.0, _mat_concrete)
	_slab_hole(D_X0, D_Z0, x2, z2, CRAWL_H + 0.2, hole, MAT_CEILING)
	_maze_walls(_carve(D_N, D_N, 1337, 0.18), 0.0, CRAWL_H, _mat_concrete)
	# D2
	_slab_hole(D_X0, D_Z0, x2, z2, UP_Y, hole, MAT_CARPET, 0.3)
	_slab(D_X0, D_Z0, x2, z2, UP_Y + 3.2, MAT_CEILING)
	_maze_walls(_carve(D_N, D_N, 4242, 0.25), UP_Y, 3.0, MAT_WALLPAPER)
	# 外牆（兩層一起，0..7.7）
	var east_cz := D_Z0 + (EAST_DOOR_ROW + 0.5) * CELL
	_wall(false, D_X0, D_Z0, z2, 0.0, UP_Y + 3.2, MAT_WALLPAPER)
	_wall(true, z2, D_X0, x2, 0.0, UP_Y + 3.2, MAT_WALLPAPER)
	_wall(false, x2, D_Z0, z2, 0.0, UP_Y + 3.2, MAT_WALLPAPER, [Vector4(east_cz - 1.0, east_cz + 1.0, 0.0, 2.1)])
	# 破洞四周的坑壁（擋住樓板厚度的縫）
	var hc := hole.get_center()
	_box(Vector3(hc.x, (CRAWL_H + UP_Y) * 0.5, hole.position.y + 0.05), Vector3(CELL, UP_Y - CRAWL_H, 0.1), _mat_concrete, false)
	_box(Vector3(hole.end.x - 0.05, (CRAWL_H + UP_Y) * 0.5, hc.y), Vector3(0.1, UP_Y - CRAWL_H, CELL), _mat_concrete, false)
	# 燈：爬行層昏暗、上層正常
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 6:
		var c := Vector2i(rng.randi_range(0, D_N - 1), rng.randi_range(0, D_N - 1))
		_light(_cell_center(c, CRAWL_H - 0.02), 0.35, 5.0)
	for i in 9:
		var c := Vector2i(rng.randi_range(0, D_N - 1), rng.randi_range(0, D_N - 1))
		if c == HOLE:
			continue
		_light(_cell_center(c, UP_Y + 2.98), 0.7, 7.0)
	_light(Vector3(hc.x, 0.6, hc.y), 0.5, 4.0) # 洞底微光，讓上層看得到下面
	_trigger("CrawlTrigger", Vector3((D_X0 + x2) * 0.5, CRAWL_H * 0.5, (D_Z0 + z2) * 0.5),
		Vector3(x2 - D_X0 - 0.6, CRAWL_H, z2 - D_Z0 - 0.6), "crawl")
	_note("CrawlNote", _cell_center(Vector2i(CRAWL_DOOR_COL, 0), 1.2) + Vector3(0, 0, 1.4), 180.0,
		"閱讀低矮天花板下的紙條", "爬行層紀錄",
		"【爬行層】\n天花板只有兩公尺出頭，嗡鳴聲被壓得很近，像貼在耳邊。\n\n"
		+ "「東邊那面牆有個矮門。我是彎著腰找到的，不是看到的。」")
	_note("HoleNote", _cell_center(Vector2i(HOLE.x + 1, HOLE.y), UP_Y + 1.2) + Vector3(-1.55, 0, 0), 90.0,
		"閱讀破洞旁的紙條", "上層辦公迷宮",
		"【上層辦公迷宮】\n地板少了一整格，往下看是爬行層的水泥地。\n\n"
		+ "「跳下去不會死。只是回不來原本的路。」")


# --- E: 高柱長廳 + 抬高平台 ---
func _build_column_hall() -> void:
	var x1 := -76.0
	var x2 := -44.0
	var z1 := 58.0
	var z2 := 104.0
	_slab(x1, z1, x2, z2, 0.0, MAT_CARPET)
	_slab(x1, z1, x2, z2, 6.2, MAT_CEILING)
	# 西半邊壓低的吊頂（視覺）
	_box(Vector3(-70.0, 3.1, 81.0), Vector3(12.0, 0.2, 46.0), MAT_CEILING, false)
	# 平台 x[-60..-46] z[82..102]，高 1.5
	_box(Vector3(-53.0, 0.75, 92.0), Vector3(14.0, 1.5, 20.0), _mat_pale)
	_slab(-60.0, 82.0, -46.0, 102.0, 1.52, _mat_thick, 0.02, false)
	var ang := atan2(1.5, 6.0)
	_box(Vector3(-53.0, 0.75 - 0.1 / cos(ang), 79.0), Vector3(6.0, 0.2, 6.0 / cos(ang)), _mat_pale, true, Vector3(-ang, 0, 0))
	_stairs(Vector3(-62.8, 0.0, 92.0), Vector3(1, 0, 0), 4.0, 7, 1.5 / 7.0, 0.4, _mat_pale, true)
	_rail(true, 82.0, -60.0, -56.0, 1.5)
	_rail(true, 82.0, -50.0, -46.0, 1.5)
	_rail(true, 102.0, -60.0, -46.0, 1.5)
	_rail(false, -46.0, 82.0, 102.0, 1.5)
	_rail(false, -60.0, 82.0, 90.0, 1.5)
	_rail(false, -60.0, 94.0, 102.0, 1.5)
	# 高柱
	for cx in [-70.0, -64.0, -58.0, -52.0]:
		for cz in [64.0, 70.0, 76.0, 82.0, 88.0, 94.0, 100.0]:
			if cx > -61.0 and cz >= 76.0:
				continue # 平台與坡道範圍
			_box(Vector3(cx, 3.0, cz), Vector3(1.2, 6.0, 1.2), MAT_WALLPAPER)
	# 牆（北牆 x[-76..-52] 已由會議坑南牆提供）
	_wall(true, z1, -52.0, x2, 0.0, 6.0, MAT_WALLPAPER)
	_wall(false, x2, z1, z2, 0.0, 6.0, MAT_WALLPAPER, [Vector4(96.0, 99.0, 0.0, 2.6)]) # → 錄影帶翼小船走廊
	_wall(true, z2, x1, x2, 0.0, 6.0, MAT_WALLPAPER)
	for lz in [66.0, 80.0, 94.0]:
		_light(Vector3(-70.0, 2.98, lz), 0.55, 6.5)
		_light(Vector3(-52.0, 5.98, lz), 0.95, 10.0)
	_light(Vector3(-48.0, 5.98, 66.0), 0.8, 9.0)
	_note("HallNote", Vector3(-53.0, 2.65, 101.85), 0.0, "閱讀平台盡頭的紀錄", "高柱長廳紀錄",
		"【高柱長廳】\n柱子比任何辦公室需要的都粗。平台上的地毯很新，好像剛有人鋪過。\n\n"
		+ "「站在平台上可以數到七排柱子。下去之後我只數到六。」")


# --- F: 梯田辦公室（往東每階升 0.8）---
func _build_terraces() -> void:
	var edges: Array[float] = [26.0, 33.5, 41.0, 48.5, 56.0]
	var stair_z: Array[float] = [45.25, 38.0, 52.0] # 每道台階位置錯開，走起來要繞
	for i in 4:
		var y := i * 0.8
		var x1 := edges[i]
		var x2 := edges[i + 1]
		if i == 0:
			_slab(x1, 34.0, x2, 58.0, 0.0, MAT_CARPET)
		else:
			_box(Vector3((x1 + x2) * 0.5, y * 0.5, 46.0), Vector3(x2 - x1, y, 24.0), _mat_pale)
			_slab(x1, 34.0, x2, 58.0, y + 0.02, MAT_CARPET, 0.02, false)
		# 隔間板（避開上一道台階的落腳處）
		for pz in [38.0, 46.0, 54.0]:
			if i > 0 and absf(pz - stair_z[i - 1]) < 3.0:
				continue
			_box(Vector3(x1 + 3.75, y + 0.7, pz), Vector3(3.0, 1.4, 0.08), _mat_concrete)
			_box(Vector3(x1 + 2.25, y + 0.7, pz + 1.0), Vector3(0.08, 1.4, 2.0), _mat_concrete)
	for i in 3:
		var bx := edges[i + 1]
		var y_low := i * 0.8
		var sz := stair_z[i]
		_stairs(Vector3(bx - 1.6, y_low, sz), Vector3(1, 0, 0), 4.0, 4, 0.2, 0.4, _mat_pale, true)
		_rail(false, bx, 34.0, sz - 2.0, y_low + 0.8)
		_rail(false, bx, sz + 2.0, 58.0, y_low + 0.8)
	_slab(26.0, 34.0, 56.0, 58.0, 6.2, MAT_CEILING)
	_wall(true, 34.0, 26.0, 56.0, 0.0, 6.0, MAT_WALLPAPER)
	_wall(true, 58.0, 26.0, 56.0, 0.0, 6.0, MAT_WALLPAPER)
	_wall_piece(false, 26.45, 34.0, 58.0, 3.2, 6.0, MAT_WALLPAPER) # 深坑牆只有 3m 高，補上半截
	for lx in [29.75, 37.25, 44.75, 52.25]:
		for lz in [40.0, 52.0]:
			_light(Vector3(lx, 5.98, lz), 0.7, 8.5)
	_note("TerraceNote", Vector3(52.25, 3.1, 46.08), 180.0, "閱讀隔間板上的便利貼", "梯田辦公室紀錄",
		"【梯田辦公室】\n地板一階一階往東抬高，天花板卻沒跟著動。走到最高那一階，伸手就快摸到燈了。\n\n"
		+ "「東牆那扇門後面是一座塔。我爬了三圈，下面的地板越來越遠。」")


# --- G: 螺旋塔（沿牆逆時針盤旋）---
func _build_tower() -> void:
	var base := 2.4
	var w := 2.2 # 走道寬
	_slab(56.0, 34.0, 70.0, 48.0, base, MAT_CARPET, 0.3)
	_slab(56.0, 34.0, 70.0, 48.0, 14.7, MAT_CEILING)
	# 北側：往 +x 上到 4.0
	_stairs(Vector3(58.2, base, 34.0 + w * 0.5), Vector3(1, 0, 0), w, 8, 0.2, 0.4, _mat_pale, false)
	_slab(61.4, 34.0, 70.0, 34.0 + w, 4.0, MAT_CARPET, 0.3)
	_rail(true, 34.0 + w, 61.4, 70.0 - w, 4.0)
	# 東側：往 +z 上到 5.6
	_stairs(Vector3(70.0 - w * 0.5, 4.0, 34.0 + w), Vector3(0, 0, 1), w, 8, 0.2, 0.4, _mat_pale, false)
	_slab(70.0 - w, 39.4, 70.0, 48.0, 5.6, MAT_CARPET, 0.3)
	_rail(false, 70.0 - w, 39.4, 48.0 - w, 5.6)
	# 南側：往 -x 上到 7.2，門通倉庫貓道
	_stairs(Vector3(70.0 - w, 5.6, 48.0 - w * 0.5), Vector3(-1, 0, 0), w, 8, 0.2, 0.4, _mat_pale, false)
	_slab(56.0, 48.0 - w, 64.6, 48.0, 7.2, MAT_CARPET, 0.3)
	_rail(true, 48.0 - w, 56.0, 64.6, 7.2)
	# 牆（西牆 x=56 與梯田共用，門在塔底）
	_wall(true, 34.0, 56.0, 70.0, 0.0, 14.5, _mat_pale)
	_wall(false, 70.0, 34.0, 48.0, 0.0, 14.5, _mat_pale)
	_wall(false, 56.0, 34.0, 48.0, 0.0, 14.5, _mat_pale, [Vector4(40.0, 43.0, base, base + 2.4)])
	_wall(true, 48.0, 56.0, 70.0, 0.0, 14.5, _mat_pale, [Vector4(58.5, 60.5, 7.2, 9.7)])
	_light(Vector3(63.0, 14.48, 41.0), 1.2, 15.0)
	_light(Vector3(66.0, 3.68, 35.1), 0.45, 5.0)
	_light(Vector3(68.9, 5.28, 44.0), 0.45, 5.0)
	_trigger("TowerTrigger", Vector3(63.0, 8.5, 41.0), Vector3(13.4, 12.0, 13.4), "tower")
	_note("TowerNote", Vector3(56.2, 8.4, 46.9), 90.0, "閱讀塔頂牆上的紀錄", "螺旋塔紀錄",
		"【螺旋塔】\n樓梯貼著牆一圈一圈往上，中間是空的。從這裡往下看，塔底的地毯像一張郵票。\n\n"
		+ "「南牆的門外是貓道。別往下看——下面的貨架比你想的高。」")


# --- H: 貓道倉庫 ---
func _build_warehouse() -> void:
	var cy := 7.2
	_slab(56.0, 48.0, 86.0, 82.0, 0.0, _mat_concrete)
	_slab(56.0, 48.0, 86.0, 82.0, 11.2, MAT_CEILING)
	# 貓道 A（塔門往南）、B（東西向）、C（南北向）
	_slab(58.7, 48.0, 60.3, 64.8, cy, _mat_rail, 0.15)
	_slab(60.3, 63.2, 85.0, 64.8, cy, _mat_rail, 0.15)
	_slab(79.2, 52.0, 80.8, 78.0, cy, _mat_rail, 0.15)
	_rail(false, 58.7, 48.0, 64.8, cy)
	_rail(false, 60.3, 48.0, 63.2, cy)
	_rail(true, 63.2, 60.3, 79.2, cy)
	_rail(true, 63.2, 80.8, 85.0, cy)
	_rail(true, 64.8, 58.7, 79.2, cy)
	_rail(true, 64.8, 80.8, 83.0, cy)
	_rail(false, 85.0, 63.2, 64.8, cy)
	for rx in [79.2, 80.8]:
		_rail(false, rx, 52.0, 63.2, cy)
		_rail(false, rx, 64.8, 78.0, cy)
	_rail(true, 52.0, 79.2, 80.8, cy)
	_rail(true, 78.0, 79.2, 80.8, cy)
	# 東牆邊下到地面的長樓梯（36 階）
	_stairs(Vector3(84.0, 0.0, 79.2), Vector3(0, 0, -1), 2.0, 36, 0.2, 0.4, _mat_pale, false)
	_rail(false, 82.95, 64.8, 79.2, 0.0, cy)
	# 貨架
	for rz in [54.0, 60.0, 70.0, 76.0]:
		_box(Vector3(70.0, 3.0, rz), Vector3(14.0, 6.0, 1.2), _mat_wood)
	_wall(true, 48.0, 70.0, 86.0, 0.0, 11.0, MAT_WALLPAPER)
	_wall(false, 86.0, 48.0, 82.0, 0.0, 11.0, MAT_WALLPAPER)
	_wall(true, 82.0, 56.0, 86.0, 0.0, 11.0, MAT_WALLPAPER)
	_wall(false, 56.0, 48.0, 82.0, 0.0, 11.0, MAT_WALLPAPER, [Vector4(73.0, 77.0, 0.0, 3.0)])
	for lx in [62.0, 71.0, 80.0]:
		for lz in [56.0, 67.0, 78.0]:
			_light(Vector3(lx, 10.98, lz), 1.1, 13.0)
	_trigger("WarehouseTrigger", Vector3(71.0, 5.5, 65.0), Vector3(29.4, 11.0, 33.4), "warehouse")
	_note("CatwalkNote", Vector3(80.0, cy + 1.0, 77.85), 180.0, "閱讀貓道盡頭的紙條", "貓道倉庫紀錄",
		"【貓道倉庫】\n貨架上什麼都沒放，但每一格都有編號，最大的編號比貨架數量還多。\n\n"
		+ "「西牆下面有個門，地板從那裡開始往下斜。我不知道 Level 0 有地下室。」")


# --- I: 斜坡走廊 + 地下檔案室，樓梯回到熄燈區 ---
func _build_basement() -> void:
	var by := -2.0
	# 斜坡 x[46..56]，從 0 降到 -2.0
	var ang := atan2(-by, 10.0)
	_box(Vector3(51.0, by * 0.5 - 0.1 / cos(ang), 75.0), Vector3(10.0 / cos(ang), 0.2, 6.0), MAT_CARPET, true, Vector3(0, 0, ang))
	_slab(46.0, 72.0, 56.0, 78.0, 3.2, MAT_CEILING)
	_wall(true, 72.0, 46.0, 56.0, by, 3.0 - by, MAT_WALLPAPER)
	_wall(true, 78.0, 46.0, 56.0, by, 3.0 - by, MAT_WALLPAPER)
	# 檔案室 x[26..46] z[60..80]；西端樓梯區天花拉高到 3.0
	_slab(26.3, 60.0, 46.0, 80.0, by, _mat_concrete)
	_slab(31.0, 60.0, 46.0, 80.0, 1.4, MAT_CEILING)
	_slab(26.3, 60.0, 31.0, 80.0, 3.2, MAT_CEILING)
	_stairs(Vector3(30.0, by, 71.0), Vector3(-1, 0, 0), 2.0, 10, 0.2, 0.4, _mat_concrete, true)
	_wall(true, 60.0, 26.3, 46.0, by, 3.0 - by, _mat_concrete)
	_wall(true, 80.0, 26.3, 46.0, by, 3.0 - by, _mat_concrete)
	_wall(false, 46.0, 60.0, 80.0, by, 3.0 - by, _mat_concrete, [Vector4(72.0, 78.0, by, 1.2)])
	_wall_piece(false, 26.45, 60.0, 80.0, by, 0.0, _mat_concrete) # 熄燈區牆的下方
	_wall_piece(true, 70.0 - WT * 0.5, 26.3, 31.0, 1.2, 3.0, _mat_concrete) # 樓梯井兩側擋住高低天花的縫
	_wall_piece(true, 72.0 + WT * 0.5, 26.3, 31.0, 1.2, 3.0, _mat_concrete)
	for rz in [63.0, 66.5, 77.0]:
		_box(Vector3(38.0, by + 1.3, rz), Vector3(12.0, 2.6, 0.9), _mat_wood)
	_box(Vector3(36.0, by + 0.01, 74.5), Vector3(6.0, 0.02, 3.0), MAT_WET_FLOOR, false)
	for lx in [34.0, 42.0]:
		_light(Vector3(lx, 1.18, 65.0), 0.35, 5.5)
		_light(Vector3(lx, 1.18, 75.0), 0.35, 5.5)
	_light(Vector3(51.0, 2.98, 75.0), 0.5, 6.0)
	_trigger("BasementTrigger", Vector3(36.0, by + 1.5, 70.0), Vector3(19.4, 3.0, 19.4), "basement")
	_note("BasementNote", Vector3(38.0, by + 1.3, 66.0), 0.0, "翻看檔案架上的資料夾", "地下檔案室紀錄",
		"【地下檔案室】\n每個資料夾的標籤都寫著「Level 0」，裡面全是空白的平面圖。\n\n"
		+ "「西邊有樓梯往上，牆後面沒有燈。帶著手電筒。」")


# --- Props（Poly Pizza CC0 低模，已在 Blender 降飽和、做舊；見 assets/models/props/CREDITS.md）---
const PROP_DIR := "res://assets/models/props/"
# Godot 座標下的尺寸 (x, 高, z)，用來產生碰撞箱
const PROP_SIZE := {
	"armchair": Vector3(1.7, 1.02, 1.6), "barrel": Vector3(0.55, 0.9, 0.55),
	"box_closed": Vector3(0.42, 0.55, 0.42), "bucket": Vector3(0.27, 0.38, 0.29),
	"cardboard_boxes": Vector3(1.0, 0.97, 0.94), "coffee_machine": Vector3(0.32, 0.3, 0.4),
	"computer_screen": Vector3(0.5, 0.37, 0.13), "fridge": Vector3(0.84, 1.8, 0.83),
	"ladder": Vector3(0.37, 2.6, 0.1), "pallet": Vector3(1.2, 0.14, 1.03),
	"pallet_broken": Vector3(1.2, 0.18, 1.04), "plant": Vector3(1.1, 1.03, 0.99),
	"shelf_small": Vector3(1.4, 0.52, 0.74), "trashcan": Vector3(0.42, 0.6, 0.26),
	"boat": Vector3(1.66, 0.71, 3.2), "floor_lamp": Vector3(0.3, 1.7, 0.31),
	# 既有辦公室模型
	"desk": Vector3(1.45, 1.16, 0.78), "chair": Vector3(0.55, 0.95, 0.55), "cabinet": Vector3(0.48, 1.32, 0.62),
}
const OLD_MODELS := {
	"desk": "res://assets/models/retro_office_desk.glb",
	"chair": "res://assets/models/office_chair.glb",
	"cabinet": "res://assets/models/filing_cabinet.glb",
}
const NO_COLLIDE := ["pallet", "pallet_broken", "coffee_machine", "computer_screen", "bucket"]

var _prop_scenes := {}


func _prop(kind: String, pos: Vector3, rot_y: float = 0.0) -> void:
	if not _prop_scenes.has(kind):
		_prop_scenes[kind] = load(OLD_MODELS.get(kind, PROP_DIR + kind + ".glb"))
	var scene: PackedScene = _prop_scenes[kind]
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees.y = rot_y
	_props.add_child(body)
	if scene:
		body.add_child(scene.instantiate())
	if kind in NO_COLLIDE:
		return
	var sz: Vector3 = PROP_SIZE[kind]
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = sz
	cs.shape = bs
	cs.position.y = sz.y * 0.5
	body.add_child(cs)


func _build_props() -> void:
	# A 走廊
	_prop("trashcan", Vector3(-51.4, 0, 44.5))
	_prop("bucket", Vector3(-45.2, 0, 47.5))
	# B 會議坑：坑底圍桌的椅子、桌上咖啡機；坑外茶水角與檔案櫃
	for cx in [-66.0, -64.0, -62.0]:
		_prop("chair", Vector3(cx, -1.6, 44.4), 0.0)
		_prop("chair", Vector3(cx, -1.6, 47.6), 180.0)
	_prop("coffee_machine", Vector3(-62.4, -0.85, 46.1), 200.0)
	_prop("fridge", Vector3(-53.0, 0, 35.0), 180.0)
	_prop("trashcan", Vector3(-54.2, 0, 34.5))
	for cx in [-74.6, -74.0, -73.4, -72.8]:
		_prop("cabinet", Vector3(cx, 0, 34.5), 180.0)
	_prop("plant", Vector3(-75.2, 0, 57.2))
	_prop("cardboard_boxes", Vector3(-53.0, 0, 57.0), 15.0)
	_prop("box_closed", Vector3(-53.8, 0, 56.0), 40.0)
	# C 中庭：一組沒人坐的沙發、迴廊上的雜物
	_prop("armchair", Vector3(-101.0, 0, 50.0), 90.0)
	_prop("armchair", Vector3(-95.0, 0, 50.0), -90.0)
	_prop("plant", Vector3(-98.0, 0, 47.6))
	_prop("trashcan", Vector3(-98.0, 0, 52.4))
	_prop("ladder", Vector3(-109.75, 0, 60.0), 90.0)
	_prop("cardboard_boxes", Vector3(-108.6, UP_Y, 40.5), 10.0)
	_prop("box_closed", Vector3(-108.4, UP_Y, 42.0), 30.0)
	for cx in [-100.0, -99.4, -98.8]:
		_prop("cabinet", Vector3(cx, UP_Y, 34.5), 180.0)
	_prop("plant", Vector3(-77.0, UP_Y, 35.0))
	# D1 爬行層（雜物） / D2 上層迷宮（辦公家具），用固定種子撒在格子裡
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var skip := [HOLE, Vector2i(CRAWL_DOOR_COL, 0), Vector2i(UPPER_DOOR_COL, 0), Vector2i(D_N - 1, EAST_DOOR_ROW)]
	var crawl_kinds := ["bucket", "barrel", "cardboard_boxes", "pallet_broken", "box_closed", "pallet"]
	var office_kinds := ["desk", "cabinet", "trashcan", "plant", "chair", "cardboard_boxes"]
	for layer in 2:
		var used := skip.duplicate()
		for i in 16:
			var c := Vector2i(rng.randi_range(0, D_N - 1), rng.randi_range(0, D_N - 1))
			if c in used:
				continue
			used.append(c)
			var dir: Vector3 = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)][rng.randi_range(0, 3)]
			var kinds: Array = crawl_kinds if layer == 0 else office_kinds
			var y := 0.0 if layer == 0 else UP_Y
			var kind: String = kinds[rng.randi_range(0, kinds.size() - 1)]
			var sz: Vector3 = PROP_SIZE[kind]
			var off := maxf(0.0, 1.5 - Vector2(sz.x, sz.z).length() * 0.5) # 任意旋轉都不穿牆
			_prop(kind, _cell_center(c, y) + dir * off, rng.randf_range(0.0, 360.0))
	# E 長廳：平台上的休息區、柱邊矮櫃
	_prop("armchair", Vector3(-55.0, 1.5, 96.0), 160.0)
	_prop("armchair", Vector3(-50.5, 1.5, 96.5), -150.0)
	_prop("plant", Vector3(-47.0, 1.5, 101.0))
	_prop("desk", Vector3(-53.0, 1.5, 100.8), 180.0)
	_prop("shelf_small", Vector3(-70.0, 0, 65.6), 0.0)
	_prop("shelf_small", Vector3(-64.0, 0, 90.3), 90.0)
	_prop("cardboard_boxes", Vector3(-45.0, 0, 70.0), 5.0)
	_prop("box_closed", Vector3(-45.1, 0, 71.2), 25.0)
	_prop("bucket", Vector3(-58.0, 0, 104.0 - 0.4))

	# F 梯田辦公室：每個隔間一張桌子 + 椅子
	var edges: Array[float] = [26.0, 33.5, 41.0, 48.5]
	var stair_z: Array[float] = [45.25, 38.0, 52.0]
	for i in 4:
		for pz in [38.0, 46.0, 54.0]:
			if i > 0 and absf(pz - stair_z[i - 1]) < 3.0:
				continue
			var x1 := edges[i]
			var y := i * 0.8
			_prop("desk", Vector3(x1 + 3.9, y, pz + 0.5), 180.0)
			_prop("chair", Vector3(x1 + 3.9, y, pz + 1.5), 180.0 + rng.randf_range(-30.0, 30.0))
	_prop("plant", Vector3(27.0, 0, 35.0))
	_prop("plant", Vector3(55.0, 2.4, 57.0))
	_prop("trashcan", Vector3(27.0, 0, 57.4))
	_prop("fridge", Vector3(55.2, 2.4, 35.0), -90.0)
	_prop("coffee_machine", Vector3(55.3, 2.4 + 1.8, 35.0), -90.0)
	# G 塔底
	_prop("barrel", Vector3(68.8, 2.4, 47.0))
	_prop("bucket", Vector3(67.9, 2.4, 47.3))
	_prop("ladder", Vector3(63.0, 2.4, 47.8))
	_prop("pallet_broken", Vector3(62.5, 2.4, 40.5), 20.0)
	# H 倉庫：棧板 + 紙箱、油桶堆、貨架頂上的箱子（從貓道看得到）
	for p in [Vector3(60.0, 0, 57.0), Vector3(66.0, 0, 57.2), Vector3(74.0, 0, 73.0), Vector3(62.0, 0, 79.5)]:
		_prop("pallet", p, rng.randf_range(-10.0, 10.0))
		_prop("cardboard_boxes", p + Vector3(0, 0.14, 0), rng.randf_range(0.0, 90.0))
	for p in [Vector3(84.6, 0, 50.0), Vector3(85.2, 0, 50.7), Vector3(84.4, 0, 51.3), Vector3(78.0, 0, 81.2)]:
		_prop("barrel", p)
	_prop("pallet_broken", Vector3(80.0, 0, 66.5), 35.0)
	for rz in [54.0, 60.0, 70.0, 76.0]:
		for i in 3:
			var kind := "cardboard_boxes" if rng.randf() < 0.5 else "box_closed"
			_prop(kind, Vector3(rng.randf_range(64.0, 76.0), 6.0, rz), rng.randf_range(0.0, 90.0))
	_prop("ladder", Vector3(77.2, 0, 60.0), 90.0)
	# I 地下檔案室
	for cx in [33.0, 33.6, 34.2, 41.0, 41.6]:
		_prop("cabinet", Vector3(cx, -2.0, 60.5), 180.0)
	_prop("bucket", Vector3(36.5, -2.0, 74.2))
	_prop("box_closed", Vector3(44.6, -2.0, 61.0), 15.0)
	_prop("cardboard_boxes", Vector3(44.5, -2.0, 79.3), 0.0)
	for rz in [63.0, 66.5, 77.0]:
		_prop("box_closed", Vector3(rng.randf_range(33.0, 43.0), 0.6, rz), rng.randf_range(0.0, 90.0))

# --- 迷宮 ---
func _carve(cols: int, rows: int, seed_v: int, loops: float) -> Dictionary:
	# v[r][c]：格子 c 西側的牆；h[r][c]：格子 r 北側的牆。外框由外牆負責。
	var v: Array = []
	var h: Array = []
	for r in rows:
		var row: Array[bool] = []
		row.resize(cols + 1)
		row.fill(true)
		v.append(row)
	for r in rows + 1:
		var row: Array[bool] = []
		row.resize(cols)
		row.fill(true)
		h.append(row)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var seen := {}
	var stack: Array[Vector2i] = [Vector2i(0, 0)]
	seen[Vector2i(0, 0)] = true
	while not stack.is_empty():
		var cur: Vector2i = stack.back()
		var nbrs: Array[Vector2i] = []
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if n.x >= 0 and n.x < cols and n.y >= 0 and n.y < rows and not seen.has(n):
				nbrs.append(n)
		if nbrs.is_empty():
			stack.pop_back()
			continue
		var nx: Vector2i = nbrs[rng.randi_range(0, nbrs.size() - 1)]
		if nx.x != cur.x:
			v[cur.y][maxi(cur.x, nx.x)] = false
		else:
			h[maxi(cur.y, nx.y)][cur.x] = false
		seen[nx] = true
		stack.append(nx)
	for r in rows:
		for c in range(1, cols):
			if rng.randf() < loops:
				v[r][c] = false
	for r in range(1, rows):
		for c in cols:
			if rng.randf() < loops:
				h[r][c] = false
	assert(seen.size() == cols * rows, "maze carve must reach every cell")
	return {"v": v, "h": h, "cols": cols, "rows": rows}


func _maze_walls(m: Dictionary, y0: float, ht: float, mat: Material) -> void:
	var v: Array = m["v"]
	var h: Array = m["h"]
	var cols: int = m["cols"]
	var rows: int = m["rows"]
	# 合併連續牆段以減少節點數
	for c in range(1, cols):
		var r := 0
		while r < rows:
			if not v[r][c]:
				r += 1
				continue
			var r0 := r
			while r < rows and v[r][c]:
				r += 1
			var x := D_X0 + c * CELL
			_box(Vector3(x, y0 + ht * 0.5, D_Z0 + (r0 + r) * 0.5 * CELL), Vector3(0.2, ht, (r - r0) * CELL + 0.2), mat)
	for r in range(1, rows):
		var c := 0
		while c < cols:
			if not h[r][c]:
				c += 1
				continue
			var c0 := c
			while c < cols and h[r][c]:
				c += 1
			var z := D_Z0 + r * CELL
			_box(Vector3(D_X0 + (c0 + c) * 0.5 * CELL, y0 + ht * 0.5, z), Vector3((c - c0) * CELL + 0.2, ht, 0.2), mat)


func _cell_center(c: Vector2i, y: float) -> Vector3:
	return Vector3(D_X0 + (c.x + 0.5) * CELL, y, D_Z0 + (c.y + 0.5) * CELL)


# --- 幾何 helper ---
func _box(pos: Vector3, sz: Vector3, mat: Material, collide: bool = true, rot: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	# 大面細分（約 1m 一段），避免 PS2 頂點抖動 / 仿射貼圖扭曲
	bm.subdivide_width = clampi(int(sz.x), 0, 48)
	bm.subdivide_height = clampi(int(sz.y), 0, 8)
	bm.subdivide_depth = clampi(int(sz.z), 0, 48)
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	_body.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = sz
		cs.shape = bs
		cs.position = pos
		cs.rotation = rot
		_body.add_child(cs)


# 水平樓板，y_top 為上表面
func _slab(x1: float, z1: float, x2: float, z2: float, y_top: float, mat: Material, thick: float = 0.2, collide: bool = true) -> void:
	_box(Vector3((x1 + x2) * 0.5, y_top - thick * 0.5, (z1 + z2) * 0.5), Vector3(x2 - x1, thick, z2 - z1), mat, collide)


# 挖掉 hole 的樓板（hole 須貼齊樓板邊角或內部皆可）
func _slab_hole(x1: float, z1: float, x2: float, z2: float, y_top: float, hole: Rect2, mat: Material, thick: float = 0.2) -> void:
	var hx1 := hole.position.x
	var hz1 := hole.position.y
	var hx2 := hole.end.x
	var hz2 := hole.end.y
	if hz1 > z1:
		_slab(x1, z1, x2, hz1, y_top, mat, thick)
	if hz2 < z2:
		_slab(x1, hz2, x2, z2, y_top, mat, thick)
	if hx1 > x1:
		_slab(x1, hz1, hx1, hz2, y_top, mat, thick)
	if hx2 < x2:
		_slab(hx2, hz1, x2, hz2, y_top, mat, thick)


# along_x=true：牆沿 x 延伸、位於 z=fixed。doors: Vector4(a1, a2, y_bottom, y_top)
func _wall(along_x: bool, fixed: float, a1: float, a2: float, y0: float, ht: float, mat: Material, doors: Array = []) -> void:
	var y1 := y0 + ht
	var cur := a1
	doors.sort_custom(func(p: Vector4, q: Vector4) -> bool: return p.x < q.x)
	for d: Vector4 in doors:
		if d.x > cur:
			_wall_piece(along_x, fixed, cur, d.x, y0, y1, mat)
		if d.z > y0:
			_wall_piece(along_x, fixed, d.x, d.y, y0, d.z, mat)
		if d.w < y1:
			_wall_piece(along_x, fixed, d.x, d.y, d.w, y1, mat)
		cur = d.y
	if cur < a2:
		_wall_piece(along_x, fixed, cur, a2, y0, y1, mat)


func _wall_piece(along_x: bool, fixed: float, a1: float, a2: float, y0: float, y1: float, mat: Material) -> void:
	var mid := (a1 + a2) * 0.5
	var ln := a2 - a1
	if along_x:
		_box(Vector3(mid, (y0 + y1) * 0.5, fixed), Vector3(ln, y1 - y0, WT), mat)
	else:
		_box(Vector3(fixed, (y0 + y1) * 0.5, mid), Vector3(WT, y1 - y0, ln), mat)


# 從 start（底階前緣中心、y=地面）沿 dir 往上爬
func _stairs(start: Vector3, dir: Vector3, width: float, steps: int, rise: float, depth: float, mat: Material, solid: bool) -> void:
	for i in steps:
		var along := start + dir * ((i + 0.5) * depth)
		var top := start.y + (i + 1) * rise
		var ht := top - start.y if solid else rise
		var sz := Vector3(depth, ht, width) if absf(dir.x) > 0.5 else Vector3(width, ht, depth)
		_box(Vector3(along.x, top - ht * 0.5, along.z), sz, mat)
	_stair_ramp(_body, start, dir, width, steps, rise, depth)


# 玩家只有 move_and_slide、沒有爬階邏輯：0.2m 階緣對半徑 0.35 的膠囊來說是 ~65° 的牆。
# 在樓梯下放一片隱形斜坡，上表面剛好通過每一階前緣（約 26°），可走也不會陷進踏面。
static func _stair_ramp(parent: Node3D, start: Vector3, dir: Vector3, width: float, steps: int, rise: float, depth: float) -> void:
	var run := steps * depth
	var h := steps * rise
	var ang := atan2(h, run)
	var t := 0.1
	# 斜面從第一階前方 depth 處的地面，拉到最上一階的前緣
	var c := start + dir * ((steps - 2) * depth * 0.5) + dir * (sin(ang) * t * 0.5)
	c.y = start.y + h * 0.5 - cos(ang) * t * 0.5
	var ln := sqrt(run * run + h * h)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	cs.position = c
	if absf(dir.x) > 0.5:
		bs.size = Vector3(ln, t, width)
		cs.rotation.z = ang * signf(dir.x)
	else:
		bs.size = Vector3(width, t, ln)
		cs.rotation.x = -ang * signf(dir.z)
	cs.shape = bs
	parent.add_child(cs)


# 欄杆：沿 x（z=fixed）或沿 z（x=fixed），y=樓面高度；rise>0 時為樓梯斜扶手
func _rail(along_x: bool, fixed: float, a1: float, a2: float, y: float, rise: float = 0.0) -> void:
	var ln := a2 - a1
	var mid := (a1 + a2) * 0.5
	if rise > 0.0:
		var ang := atan2(rise, ln)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.08, 0.08, sqrt(ln * ln + rise * rise))
		mi.mesh = bm
		mi.material_override = _mat_rail
		mi.position = Vector3(fixed, y + rise * 0.5 + 1.0, mid)
		mi.rotation.x = -ang
		_body.add_child(mi)
		return
	var c := Vector3(mid, y + 0.5, fixed) if along_x else Vector3(fixed, y + 0.5, mid)
	var bar := Vector3(ln, 0.08, 0.08) if along_x else Vector3(0.08, 0.08, ln)
	_box(c + Vector3(0, 0.5, 0), bar, _mat_rail, false)
	# 1m 高擋板兼碰撞
	var panel := Vector3(ln, 1.0, 0.06) if along_x else Vector3(0.06, 1.0, ln)
	_box(c, panel, _mat_rail, true)


func _light(pos: Vector3, energy: float, rng: float) -> void:
	var panel := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.15, 0.04, 0.5)
	panel.mesh = bm
	panel.material_override = MAT_FLUORESCENT
	panel.position = pos
	_lights.add_child(panel)
	var omni := OmniLight3D.new()
	omni.position = pos - Vector3(0.0, 0.35, 0.0)
	omni.light_color = Color(0.98, 0.94, 0.72)
	omni.light_energy = energy
	omni.omni_range = rng
	omni.shadow_enabled = false
	_lights.add_child(omni)


func _trigger(t_name: String, pos: Vector3, sz: Vector3, zone_id: String) -> void:
	var area := Area3D.new()
	area.name = t_name
	area.position = pos
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = sz
	col.shape = bs
	area.add_child(col)
	add_child(area)
	area.body_entered.connect(func(b: Node) -> void:
		if b == _player:
			_set_zone(zone_id)
	)
	area.body_exited.connect(func(b: Node) -> void:
		if b == _player and _active_zone == zone_id:
			_set_zone("")
	)


func _note(node_name: String, pos: Vector3, rot_y: float, prompt: String, f_name: String, body_txt: String) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.rotation_degrees = Vector3(0.0, rot_y, 0.0)
	body.set_script(INTERACT_SCRIPT)
	body.set("prompt_text", prompt)
	body.set("interaction_type", "note")
	body.set("file_name", f_name)
	body.set("body_text", body_txt)
	_props.add_child(body)
	var paper := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.28, 0.34, 0.02)
	paper.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.90, 0.84, 0.65)
	pmat.roughness = 0.85
	paper.material_override = pmat
	body.add_child(paper)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.45, 0.5, 0.25)
	col.shape = shape
	body.add_child(col)
