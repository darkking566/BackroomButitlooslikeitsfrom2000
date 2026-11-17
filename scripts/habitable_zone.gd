@tool
extends Node3D

# 宜居地帶（Habitable Zone）— 潮濕混凝土停車場、管線走廊與倉庫卸貨區
# 獨立場景，從「閾界」切出後抵達。

const MAT_HALL_WALL := preload("res://materials/mat_hall_wall.tres")
const MAT_HALL_FLOOR := preload("res://materials/mat_hall_floor.tres")
const MAT_WET_FLOOR := preload("res://materials/mat_wet_floor.tres")
const MAT_DARK_BRICK := preload("res://materials/mat_dark_brick.tres")
const MAT_VENT_GRILL := preload("res://materials/mat_vent_grill.tres")
const MAT_FLUORESCENT := preload("res://materials/mat_fluorescent.tres")
const INTERACT_SCRIPT := preload("res://scripts/interactable_prop.gd")

const PROP_DIR := "res://assets/models/props/"
const MODEL_DIR := "res://assets/models/"

const CEIL_H := 3.6
const WALL_T := 0.4

var _flicker_lights: Array[OmniLight3D] = []
var _flicker_base: Array[float] = []
var _flicker_timer: float = 0.0
var _blackout_cooldown: float = 18.0
var _blackout_left: float = 0.0

var _mat_concrete_dark: StandardMaterial3D
var _mat_hazard: StandardMaterial3D
var _mat_pipe: StandardMaterial3D
var _mat_note_paper: StandardMaterial3D


func _ready() -> void:
	if get_child_count() == 0:
		_build_habitable_zone()
	if not Engine.is_editor_hint():
		var root := get_parent()
		if root and root.get_node_or_null("Player") == null:
			var player_scene := load("res://scenes/player.tscn") as PackedScene
			if player_scene:
				var player := player_scene.instantiate() as Node3D
				if player:
					player.position = Vector3(0.0, 0.05, 4.0)
					root.add_child.call_deferred(player)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _flicker_lights.is_empty():
		return

	_flicker_timer += delta
	_blackout_cooldown -= delta
	if _blackout_cooldown <= 0.0:
		_blackout_left = randf_range(1.2, 2.6)
		_blackout_cooldown = randf_range(22.0, 38.0)

	if _blackout_left > 0.0:
		_blackout_left -= delta
		for i in _flicker_lights.size():
			var l := _flicker_lights[i]
			if is_instance_valid(l):
				l.light_energy = _flicker_base[i] * (0.12 if int(_flicker_timer * 19.0 + i) % 3 == 0 else 0.04)
		return

	for i in _flicker_lights.size():
		var l := _flicker_lights[i]
		if not is_instance_valid(l):
			continue
		var wave := sin(_flicker_timer * (7.0 + float(i) * 3.1) + float(i) * 1.7)
		var jitter := 1.0 if wave > -0.78 else 0.25
		l.light_energy = _flicker_base[i] * jitter


func _build_habitable_zone() -> void:
	_init_local_materials()

	var geo := StaticBody3D.new()
	geo.name = "HabitableGeometry"
	add_child(geo)

	var lights := Node3D.new()
	lights.name = "HabitableLights"
	add_child(lights)

	var props := Node3D.new()
	props.name = "HabitableProps"
	add_child(props)

	# 1. 主空間：地下混凝土停車場／卸貨大廳 (x: -24..24, z: -20..20)
	_build_main_garage(geo, lights, props)

	# 2. 北側：管線維修走廊與 M.E.G. 小型補給站 (x: -14..14, z: -34..-20)
	_build_north_corridor(geo, lights, props)

	# 3. 南側：積水車道斜坡封鎖區 (x: -8..8, z: 20..30)
	_build_south_ramp(geo, lights, props)


func _init_local_materials() -> void:
	_mat_concrete_dark = StandardMaterial3D.new()
	_mat_concrete_dark.albedo_color = Color(0.24, 0.26, 0.28)
	_mat_concrete_dark.roughness = 0.92

	_mat_hazard = StandardMaterial3D.new()
	_mat_hazard.albedo_color = Color(0.68, 0.56, 0.14)
	_mat_hazard.roughness = 0.85

	_mat_pipe = StandardMaterial3D.new()
	_mat_pipe.albedo_color = Color(0.26, 0.29, 0.30)
	_mat_pipe.metallic = 0.45
	_mat_pipe.roughness = 0.55

	_mat_note_paper = StandardMaterial3D.new()
	_mat_note_paper.albedo_color = Color(0.88, 0.84, 0.68)
	_mat_note_paper.roughness = 0.9


func _build_main_garage(geo: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	# 地板與天花板
	_add_box(geo, Vector3(48.0, 0.2, 40.0), Vector3(0.0, -0.1, 0.0), MAT_HALL_FLOOR, true)
	_add_box(geo, Vector3(48.0, 0.2, 40.0), Vector3(0.0, CEIL_H + 0.1, 0.0), _mat_concrete_dark, true)

	# 四周外牆（北牆 z=-20 留寬度 6m 通道往北側走廊；南牆 z=20 留寬度 8m 通道往南側斜坡）
	_add_box(geo, Vector3(WALL_T, CEIL_H, 40.0), Vector3(-24.0, CEIL_H * 0.5, 0.0), MAT_HALL_WALL, true)
	_add_box(geo, Vector3(WALL_T, CEIL_H, 40.0), Vector3(24.0, CEIL_H * 0.5, 0.0), MAT_HALL_WALL, true)

	# 北牆 (z = -20)，中間 x: -3..3 開口
	_add_box(geo, Vector3(21.0, CEIL_H, WALL_T), Vector3(-13.5, CEIL_H * 0.5, -20.0), MAT_HALL_WALL, true)
	_add_box(geo, Vector3(21.0, CEIL_H, WALL_T), Vector3(13.5, CEIL_H * 0.5, -20.0), MAT_HALL_WALL, true)

	# 南牆 (z = 20)，中間 x: -4..4 開口
	_add_box(geo, Vector3(20.0, CEIL_H, WALL_T), Vector3(-14.0, CEIL_H * 0.5, 20.0), MAT_HALL_WALL, true)
	_add_box(geo, Vector3(20.0, CEIL_H, WALL_T), Vector3(14.0, CEIL_H * 0.5, 20.0), MAT_HALL_WALL, true)

	# 天花板橫樑（沿 X 方向）
	for bz in [-14.0, -7.0, 0.0, 7.0, 14.0]:
		_add_box(geo, Vector3(47.6, 0.35, 0.45), Vector3(0.0, CEIL_H - 0.18, bz), _mat_concrete_dark, false)

	# 混凝土方柱陣列 + 底部警示條
	var pillar_xs := [-16.0, -8.0, 0.0, 8.0, 16.0]
	var pillar_zs := [-12.0, -4.0, 4.0, 12.0]
	for px in pillar_xs:
		for pz in pillar_zs:
			# 避開中心出生點附近 (0, 4) 與 (0, -4) 讓視線開闊一點
			if absf(px) < 1.0 and absf(pz) < 5.0:
				continue
			_add_box(geo, Vector3(0.9, CEIL_H, 0.9), Vector3(px, CEIL_H * 0.5, pz), MAT_HALL_WALL, true)
			_add_box(geo, Vector3(0.96, 0.22, 0.96), Vector3(px, 0.75, pz), _mat_hazard, false)

	# 積水區（純視覺反光薄片，抬高 1.5cm 並細分網格避免與地板產生 Z-fighting 閃爍）
	_add_box(geo, Vector3(11.0, 0.01, 7.5), Vector3(-11.0, 0.015, -6.5), MAT_WET_FLOOR, false)
	_add_box(geo, Vector3(9.5, 0.01, 8.0), Vector3(11.5, 0.015, 7.0), MAT_WET_FLOOR, false)
	_add_box(geo, Vector3(6.5, 0.01, 5.5), Vector3(0.5, 0.015, 12.5), MAT_WET_FLOOR, false)

	# 頭頂管線
	_add_pipe(geo, Vector3(-22.0, 3.15, -10.0), Vector3(22.0, 3.15, -10.0), 0.12)
	_add_pipe(geo, Vector3(-22.0, 3.05, 10.0), Vector3(22.0, 3.05, 10.0), 0.10)

	# 日光燈條與冷白燈光（只留 2 盞主要燈開陰影，符合復古風格與效能規範）
	var light_positions := [
		Vector3(0.0, CEIL_H - 0.15, 0.0),
		Vector3(-12.0, CEIL_H - 0.15, -8.0),
		Vector3(12.0, CEIL_H - 0.15, -8.0),
		Vector3(-12.0, CEIL_H - 0.15, 8.0),
		Vector3(12.0, CEIL_H - 0.15, 8.0),
		Vector3(0.0, CEIL_H - 0.15, -15.0),
		Vector3(0.0, CEIL_H - 0.15, 15.0),
	]
	for idx in light_positions.size():
		var lp: Vector3 = light_positions[idx]
		_add_box(geo, Vector3(1.6, 0.06, 0.28), lp + Vector3(0.0, 0.12, 0.0), MAT_FLUORESCENT, false)
		var cast_shadow := (idx == 0 or idx == 3)
		var flicker := (idx == 1 or idx == 4)
		var energy := 1.45 if idx == 0 else 1.1
		_add_omni(lights, lp - Vector3(0.0, 0.25, 0.0), Color(0.84, 0.90, 0.98), energy, 13.5, cast_shadow, flicker)

	# 入口附近的線索桌與模型
	_spawn_model(props, MODEL_DIR + "retro_office_desk.glb", "GarageDesk", Vector3(-3.2, 0.0, 1.5), 90.0, Vector3(1.5, 0.78, 0.8))
	_spawn_model(props, MODEL_DIR + "office_chair.glb", "GarageChair", Vector3(-2.3, 0.0, 1.4), -75.0, Vector3(0.65, 0.95, 0.65))
	_add_note_prop(props, "HabitableIntroNote", Vector3(-3.2, 0.80, 1.5),
		"閱讀桌上的「宜居地帶」生存簡報", "M.E.G. 宜居地帶簡報",
		"【層級名稱：宜居地帶】\n\n"
		+ "如果你剛從「閾界」的黃色迷宮切出，歡迎來到相對安全卻依然危機四伏的「宜居地帶」。\n"
		+ "這裡呈現為無止盡的混凝土倉庫與地下停車場，地面常見積水，頭頂管線會持續滴水。\n\n"
		+ "• 照明警告：供電並不穩定，整區燈光偶爾會同時閃爍或短暫跳電。\n"
		+ "• 建議：隨時準備好手電筒 [F]，並可按 [M] 開啟導航終端機切換層級。"
	)

	# 倉庫棧板、紙箱與鐵桶群組
	_spawn_model(props, PROP_DIR + "pallet.glb", "Pallet_1", Vector3(6.2, 0.0, -2.5), 15.0, Vector3(1.2, 0.18, 1.0))
	_spawn_model(props, PROP_DIR + "box_closed.glb", "Crate_1", Vector3(6.2, 0.16, -2.5), 10.0, Vector3(0.7, 0.7, 0.7))
	_spawn_model(props, PROP_DIR + "cardboard_boxes.glb", "Cardboard_1", Vector3(7.4, 0.0, -3.1), -25.0, Vector3(0.9, 0.8, 0.9))
	_spawn_model(props, PROP_DIR + "barrel.glb", "Barrel_1", Vector3(14.5, 0.0, -10.5), 0.0, Vector3(0.6, 0.9, 0.6))
	_spawn_model(props, PROP_DIR + "barrel.glb", "Barrel_2", Vector3(15.2, 0.0, -10.1), 40.0, Vector3(0.6, 0.9, 0.6))
	_spawn_model(props, PROP_DIR + "pallet_broken.glb", "PalletBroken_1", Vector3(-14.0, 0.0, 6.0), 32.0, Vector3(1.2, 0.18, 1.0))
	_spawn_model(props, PROP_DIR + "shelf_small.glb", "Shelf_1", Vector3(-19.5, 0.0, -12.0), 90.0, Vector3(1.2, 1.8, 0.5))
	_spawn_model(props, PROP_DIR + "ladder.glb", "Ladder_1", Vector3(-23.2, 0.0, 2.0), 90.0, Vector3(0.6, 2.2, 0.4))
	_spawn_model(props, MODEL_DIR + "breaker_box.glb", "MainBreakerBox", Vector3(-23.6, 1.35, -3.5), 90.0, Vector3(0.35, 0.7, 0.5))
	_add_interactive_box(props, "BreakerInteract", Vector3(-23.4, 1.35, -3.5), Vector3(0.7, 1.2, 0.8),
		"檢查牆上的配電箱", "配電室維修紀錄",
		"【配電箱狀態：電壓不穩】\n\n"
		+ "裡面的斷路器標籤全被水漬泡爛了，只剩一張手寫貼紙：\n"
		+ "「別去修北邊走廊盡頭的總開關，跳電幾秒鐘燈自己會回來。在黑暗裡站著別動就好。」"
	)

	# 返回「閾界」的門（在西牆附近）
	_spawn_model(props, MODEL_DIR + "exit_sign.glb", "ReturnExitSign", Vector3(-18.0, 2.8, 0.0), 90.0, Vector3(0.5, 0.25, 0.2))
	_add_box(geo, Vector3(0.25, 2.4, 1.4), Vector3(-23.7, 1.2, 0.0), MAT_DARK_BRICK, true)
	var ret_body := StaticBody3D.new()
	ret_body.name = "ReturnToThresholdDoor"
	ret_body.position = Vector3(-23.4, 1.2, 0.0)
	ret_body.set_script(INTERACT_SCRIPT)
	ret_body.set("prompt_text", "推開標著「閾界」的鐵門（返回上一層）")
	ret_body.set_meta("on_interact", func(_player: Node) -> void:
		get_tree().change_scene_to_file("res://scenes/backrooms_level0_test.tscn")
	)
	var ret_col := CollisionShape3D.new()
	var ret_shape := BoxShape3D.new()
	ret_shape.size = Vector3(0.6, 2.4, 1.5)
	ret_col.shape = ret_shape
	ret_body.add_child(ret_col)
	props.add_child(ret_body)


func _build_north_corridor(geo: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	# 北側管線倉庫走廊 (x: -10..10, z: -34..-20)
	_add_box(geo, Vector3(20.0, 0.2, 14.0), Vector3(0.0, -0.1, -27.0), MAT_HALL_FLOOR, true)
	_add_box(geo, Vector3(20.0, 0.2, 14.0), Vector3(0.0, CEIL_H + 0.1, -27.0), _mat_concrete_dark, true)
	_add_box(geo, Vector3(WALL_T, CEIL_H, 14.0), Vector3(-10.0, CEIL_H * 0.5, -27.0), MAT_HALL_WALL, true)
	_add_box(geo, Vector3(WALL_T, CEIL_H, 14.0), Vector3(10.0, CEIL_H * 0.5, -27.0), MAT_HALL_WALL, true)
	_add_box(geo, Vector3(20.0, CEIL_H, WALL_T), Vector3(0.0, CEIL_H * 0.5, -34.0), MAT_HALL_WALL, true)

	_add_pipe(geo, Vector3(-9.5, 3.1, -25.0), Vector3(9.5, 3.1, -25.0), 0.14)
	_add_pipe(geo, Vector3(-9.5, 2.9, -29.0), Vector3(9.5, 2.9, -29.0), 0.11)

	_add_omni(lights, Vector3(0.0, CEIL_H - 0.35, -27.0), Color(0.78, 0.88, 0.96), 1.0, 12.0, false, true)

	_spawn_model(props, MODEL_DIR + "filing_cabinet.glb", "NorthCabinet_1", Vector3(8.8, 0.0, -32.2), -90.0, Vector3(0.6, 1.4, 0.7))
	_spawn_model(props, PROP_DIR + "fridge.glb", "NorthFridge", Vector3(-8.5, 0.0, -32.2), 90.0, Vector3(0.8, 1.7, 0.8))
	_spawn_model(props, PROP_DIR + "box_closed.glb", "SupplyCrate", Vector3(-3.0, 0.0, -32.4), 12.0, Vector3(0.8, 0.8, 0.8))
	_add_note_prop(props, "SupplyOutpostNote", Vector3(-3.0, 0.82, -32.4),
		"翻看補給箱上的物資清單", "流浪者補給紀錄",
		"【物資清點：宜居地帶北側前哨】\n\n"
		+ "• 杏仁水 x 6 瓶（已分裝）\n"
		+ "• 電池 x 2 組（手電筒備用）\n"
		+ "• 罐頭食品 x 3\n\n"
		+ "「比黃色迷宮好多了，至少這裡真的找得到補給箱，也不用一直聞發霉的地毯味。"
		+ "只是剛才跳電的時候，我好像聽見積水那頭也有腳步聲……」"
	)


func _build_south_ramp(geo: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	# 南側積水車道區 (x: -8..8, z: 20..30)
	_add_box(geo, Vector3(16.0, 0.2, 10.0), Vector3(0.0, -0.1, 25.0), MAT_WET_FLOOR, true)
	_add_box(geo, Vector3(16.0, 0.2, 10.0), Vector3(0.0, CEIL_H + 0.1, 25.0), _mat_concrete_dark, true)
	_add_box(geo, Vector3(WALL_T, CEIL_H, 10.0), Vector3(-8.0, CEIL_H * 0.5, 25.0), MAT_HALL_WALL, true)
	_add_box(geo, Vector3(WALL_T, CEIL_H, 10.0), Vector3(8.0, CEIL_H * 0.5, 25.0), MAT_HALL_WALL, true)
	_add_box(geo, Vector3(16.0, CEIL_H, WALL_T), Vector3(0.0, CEIL_H * 0.5, 30.0), MAT_DARK_BRICK, true)

	# 通風柵欄與紅光出口牌
	_add_box(geo, Vector3(2.4, 0.9, 0.15), Vector3(0.0, 2.2, 29.75), MAT_VENT_GRILL, false)
	_spawn_model(props, MODEL_DIR + "exit_sign.glb", "SouthExitSign", Vector3(0.0, 3.0, 29.6), 180.0, Vector3(0.5, 0.25, 0.2))
	_add_omni(lights, Vector3(0.0, 2.7, 29.0), Color(1.0, 0.22, 0.18), 0.75, 7.5, false, false)

	_add_interactive_box(props, "SouthGateNote", Vector3(0.0, 1.3, 29.4), Vector3(1.6, 1.6, 0.6),
		"查看封鎖牆前的警示牌", "封鎖區警示",
		"【前方區域尚未開放】\n\n"
		+ "混凝土牆後方傳來低沉的機械聲與水聲。\n"
		+ "也許再往深處走，會通往下一座尚未繪製的層級……"
	)


# --- Geometry & Prop Helpers ---

func _add_box(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material, with_col: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	# 依尺寸自動細分，避免大型平面在 PS1 仿射著色器下隨視角嚴重扭曲或 Z-fighting
	bm.subdivide_width = clampi(int(sz.x / 2.0) - 1, 0, 24)
	bm.subdivide_height = clampi(int(sz.y / 2.0) - 1, 0, 8)
	bm.subdivide_depth = clampi(int(sz.z / 2.0) - 1, 0, 24)
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)

	if with_col:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = sz
		col.shape = shape
		col.position = pos
		parent.add_child(col)


func _add_pipe(parent: Node3D, from_pos: Vector3, to_pos: Vector3, radius: float) -> void:
	var diff := to_pos - from_pos
	var length := diff.length()
	if length < 0.01:
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = 8
	mi.mesh = cm
	mi.material_override = _mat_pipe
	mi.position = (from_pos + to_pos) * 0.5
	mi.rotation.z = PI * 0.5
	parent.add_child(mi)


func _add_omni(parent: Node3D, pos: Vector3, col: Color, energy: float, rng: float, cast_shadow: bool, flicker: bool) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = col
	light.light_energy = energy
	light.omni_range = rng
	light.omni_attenuation = 1.4
	light.shadow_enabled = cast_shadow
	parent.add_child(light)
	if flicker:
		_flicker_lights.append(light)
		_flicker_base.append(energy)


func _spawn_model(parent: Node3D, path: String, node_name: String, pos: Vector3, yaw_deg: float, col_size: Vector3) -> void:
	if not ResourceLoader.exists(path):
		return
	var packed := load(path) as PackedScene
	if not packed:
		return
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.rotation_degrees.y = yaw_deg
	var inst := packed.instantiate()
	body.add_child(inst)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = col_size
	col.shape = shape
	col.position = Vector3(0.0, col_size.y * 0.5, 0.0)
	body.add_child(col)
	parent.add_child(body)


func _add_note_prop(parent: Node3D, node_name: String, pos: Vector3, prompt: String, title: String, body_txt: String) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.set_script(INTERACT_SCRIPT)
	body.set("prompt_text", prompt)
	body.set("interaction_type", "note")
	body.set("file_name", title)
	body.set("body_text", body_txt)

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.32, 0.02, 0.42)
	mi.mesh = bm
	mi.material_override = _mat_note_paper
	body.add_child(mi)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.45, 0.25, 0.55)
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)


func _add_interactive_box(parent: Node3D, node_name: String, pos: Vector3, col_size: Vector3, prompt: String, title: String, body_txt: String) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.set_script(INTERACT_SCRIPT)
	body.set("prompt_text", prompt)
	body.set("interaction_type", "note")
	body.set("file_name", title)
	body.set("body_text", body_txt)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = col_size
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
