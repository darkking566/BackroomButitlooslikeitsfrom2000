@tool
extends Node3D
# Level 0 西翼擴展區（x: -110 .. -44, z: 34 .. 104），從拱門變體西牆 z[44..48] 進入。
#   A 連接走廊      x[-52..-44]   z[44..48]   天花 3.0
#   B 下沉會議坑    x[-76..-52]   z[34..58]   天花 4.2，中央坑底 y -1.6
#   C 挑高中庭      x[-110..-76]  z[34..70]   天花 10，二樓 U 形迴廊 y 4.5
#   D1 低矮爬行層   x[-110..-76]  z[70..104]  天花 2.2（迷宮）
#   D2 上層辦公迷宮 同上範圍      y 4.5..7.5（迷宮，角落破洞掉回 D1）
#   E 高柱長廳      x[-76..-44]   z[58..104]  天花 6，抬高平台 y 1.5
# 生成節點不設 owner（AGENTS.md）。

const MAT_WALLPAPER := preload("res://materials/mat_wallpaper.tres")
const MAT_CARPET := preload("res://materials/mat_carpet.tres")
const MAT_CEILING := preload("res://materials/mat_ceiling.tres")
const MAT_FLUORESCENT := preload("res://materials/mat_fluorescent.tres")
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
	if Engine.is_editor_hint() or _active_zone == "" or not _world_env or not _world_env.environment:
		return
	var fog := LEVEL0_FOG_COLOR
	var dens := LEVEL0_FOG_DENSITY
	var amb := LEVEL0_AMBIENT_COLOR
	var amb_e := LEVEL0_AMBIENT_ENERGY
	match _active_zone:
		"atrium": # 挑高空間要看得到對面迴廊
			dens = 0.035
			amb_e = 0.45
		"crawl":
			fog = Color(0.30, 0.27, 0.15)
			dens = 0.11
			amb = Color(0.40, 0.36, 0.22)
			amb_e = 0.22
	var t := clampf(delta * 2.5, 0.0, 1.0)
	var env := _world_env.environment
	env.fog_light_color = env.fog_light_color.lerp(fog, t)
	env.fog_density = lerpf(env.fog_density, dens, t)
	env.ambient_light_color = env.ambient_light_color.lerp(amb, t)
	env.ambient_light_energy = lerpf(env.ambient_light_energy, amb_e, t)


func _set_zone(z: String) -> void:
	_active_zone = z
	if z == "" and _world_env and _world_env.environment:
		var env := _world_env.environment
		env.fog_light_color = LEVEL0_FOG_COLOR
		env.fog_density = LEVEL0_FOG_DENSITY
		env.ambient_light_color = LEVEL0_AMBIENT_COLOR
		env.ambient_light_energy = LEVEL0_AMBIENT_ENERGY


func _build() -> void:
	_body = StaticBody3D.new()
	_body.name = "ExpanseGeometry"
	add_child(_body)
	_lights = Node3D.new()
	_lights.name = "ExpanseLights"
	add_child(_lights)
	_props = Node3D.new()
	_props.name = "ExpanseProps"
	add_child(_props)

	_build_corridor()
	_build_pit_room()
	_build_atrium()
	_build_stacked_mazes()
	_build_column_hall()


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
	_box(Vector3(-53.0, 0.75 - 0.1 / cos(ang), 79.0), Vector3(6.0, 0.2, 6.0 / cos(ang)), _mat_pale, true, -ang)
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
	_wall(false, x2, z1, z2, 0.0, 6.0, MAT_WALLPAPER)
	_wall(true, z2, x1, x2, 0.0, 6.0, MAT_WALLPAPER)
	for lz in [66.0, 80.0, 94.0]:
		_light(Vector3(-70.0, 2.98, lz), 0.55, 6.5)
		_light(Vector3(-52.0, 5.98, lz), 0.95, 10.0)
	_light(Vector3(-48.0, 5.98, 66.0), 0.8, 9.0)
	_note("HallNote", Vector3(-53.0, 2.65, 101.85), 0.0, "閱讀平台盡頭的紀錄", "高柱長廳紀錄",
		"【高柱長廳】\n柱子比任何辦公室需要的都粗。平台上的地毯很新，好像剛有人鋪過。\n\n"
		+ "「站在平台上可以數到七排柱子。下去之後我只數到六。」")


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
func _box(pos: Vector3, sz: Vector3, mat: Material, collide: bool = true, rot_x: float = 0.0) -> void:
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
	mi.rotation.x = rot_x
	_body.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = sz
		cs.shape = bs
		cs.position = pos
		cs.rotation.x = rot_x
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
