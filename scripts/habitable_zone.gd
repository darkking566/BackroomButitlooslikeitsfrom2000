@tool
extends Node3D

# 宜居地帶（Habitable Zone）— 潮濕混凝土停車場、管線走廊與倉庫卸貨區
# 獨立場景，從「閾界」切出後抵達。

const MAT_HALL_WALL := preload("res://materials/mat_hall_wall.tres")
const MAT_HALL_FLOOR := preload("res://materials/mat_hall_floor.tres")
const MAT_PUDDLE_WATER := preload("res://materials/mat_puddle_water.tres")
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

var _vent_player: AudioStreamPlayer
var _drip_player: AudioStreamPlayer3D
var _breaker_player: AudioStreamPlayer
var _drip_timer: float = 2.8

var _west_breaker_on: bool = false
var _north_breaker_on: bool = false
var _south_door_open: bool = false
var _south_door_node: StaticBody3D
var _south_door_light: OmniLight3D
var _west_lamp_mat: StandardMaterial3D
var _north_lamp_mat: StandardMaterial3D
var _south_lamp_mat: StandardMaterial3D
var _west_breaker_body: StaticBody3D
var _north_breaker_body: StaticBody3D
var _south_door_prompt_body: StaticBody3D
const PUDDLE_SPOTS: Array[Vector3] = [
	Vector3(-11.0, 0.2, -6.5),
	Vector3(11.5, 0.2, 7.0),
	Vector3(0.5, 0.2, 12.5),
]

var _mat_concrete_dark: StandardMaterial3D
var _mat_hazard: StandardMaterial3D
var _mat_pipe: StandardMaterial3D
var _mat_note_paper: StandardMaterial3D
var _mat_paint_white: StandardMaterial3D


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
		if root and root.get_node_or_null("Monster") == null:
			var monster_script := load("res://scripts/monster.gd")
			if monster_script:
				var monster := Node3D.new()
				monster.name = "Monster"
				monster.position = Vector3(16.0, 0.0, -14.0)
				monster.set_script(monster_script)
				root.add_child.call_deferred(monster)
		_setup_garage_audio(root)


func _setup_garage_audio(root: Node) -> void:
	if root:
		var old_hum := root.get_node_or_null("AmbientHum")
		if old_hum and old_hum is AudioStreamPlayer:
			(old_hum as AudioStreamPlayer).stop()
			old_hum.set_process(false)

	_vent_player = AudioStreamPlayer.new()
	_vent_player.name = "GarageVentHum"
	_vent_player.stream = BackroomsAudio.create_garage_vent_hum_stream()
	_vent_player.volume_db = -14.0
	add_child(_vent_player)
	_vent_player.play()

	_drip_player = AudioStreamPlayer3D.new()
	_drip_player.name = "WaterDrip3D"
	_drip_player.stream = BackroomsAudio.create_water_drip_stream()
	_drip_player.volume_db = -9.0
	_drip_player.max_distance = 26.0
	_drip_player.position = PUDDLE_SPOTS[0]
	add_child(_drip_player)

	_breaker_player = AudioStreamPlayer.new()
	_breaker_player.name = "PowerTripAudio"
	_breaker_player.stream = BackroomsAudio.create_power_trip_stream()
	_breaker_player.volume_db = -10.0
	add_child(_breaker_player)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	_drip_timer -= delta
	if _drip_timer <= 0.0 and _drip_player:
		_drip_timer = randf_range(2.4, 5.8)
		_drip_player.position = PUDDLE_SPOTS[randi() % PUDDLE_SPOTS.size()]
		_drip_player.pitch_scale = randf_range(0.86, 1.22)
		_drip_player.play()

	if _flicker_lights.is_empty():
		return

	_flicker_timer += delta
	_blackout_cooldown -= delta
	if _blackout_cooldown <= 0.0:
		_blackout_left = randf_range(1.2, 2.6)
		_blackout_cooldown = randf_range(22.0, 38.0)
		if _breaker_player:
			_breaker_player.play()

	if _vent_player:
		var target_db := -22.0 if _blackout_left > 0.0 else -14.0
		_vent_player.volume_db = lerpf(_vent_player.volume_db, target_db, clampf(delta * 5.0, 0.0, 1.0))

	if _south_door_open and _south_door_node and _south_door_node.position.y < 3.9:
		_south_door_node.position.y = minf(_south_door_node.position.y + delta * 1.8, 3.9)

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

	# 4. 東側：地下二層（B2）車道斜坡＋挑高大型貨架倉庫 (x: 24..76)
	_build_b2_warehouse(geo, lights, props)

	# 5. B2 最東側：暖橘燈發電機房＋深層貨梯出口 (x: 76..94)
	_build_generator_room(geo, lights, props)

	# 6. 西側：員工休息室／小型監控室 (x: -36..-24, z: -18..-4)
	_build_west_breakroom(geo, lights, props)


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

	_mat_paint_white = StandardMaterial3D.new()
	_mat_paint_white.albedo_color = Color(0.56, 0.57, 0.54)
	_mat_paint_white.roughness = 0.95


func _build_main_garage(geo: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	# 地板與天花板
	_add_box(geo, Vector3(48.0, 0.2, 40.0), Vector3(0.0, -0.1, 0.0), MAT_HALL_FLOOR, true)
	_add_box(geo, Vector3(48.0, 0.2, 40.0), Vector3(0.0, CEIL_H + 0.1, 0.0), _mat_concrete_dark, true)

	# 四周外牆（西牆 x=-24 於 z:-12.6..-9.4 留 3.2m 往員工休息室；東牆 x=24 留 6m 往 B2 斜坡）
	_add_box(geo, Vector3(WALL_T, CEIL_H, 7.4), Vector3(-24.0, CEIL_H * 0.5, -16.3), MAT_HALL_WALL, true)
	_add_box(geo, Vector3(WALL_T, CEIL_H, 29.4), Vector3(-24.0, CEIL_H * 0.5, 5.3), MAT_HALL_WALL, true)
	_add_box(geo, Vector3(WALL_T, 0.9, 3.2), Vector3(-24.0, CEIL_H - 0.45, -11.0), MAT_HALL_WALL, true)
	_add_box(geo, Vector3(WALL_T, CEIL_H, 17.0), Vector3(24.0, CEIL_H * 0.5, -11.5), MAT_HALL_WALL, true)
	_add_box(geo, Vector3(WALL_T, CEIL_H, 17.0), Vector3(24.0, CEIL_H * 0.5, 11.5), MAT_HALL_WALL, true)

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

	# 反射探針讓積水能倒映柱子與日光燈
	var probe := ReflectionProbe.new()
	probe.position = Vector3(0.0, CEIL_H * 0.5, 0.0)
	probe.size = Vector3(48.0, CEIL_H + 0.5, 40.0)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)

	# 積水區（半透明不規則水窪 + 動態波紋反光，可隱約透出底下地磚）
	_add_puddle(geo, Vector3(-11.0, 0.015, -6.5), Vector2(11.0, 8.0))
	_add_puddle(geo, Vector3(11.5, 0.015, 7.0), Vector2(10.0, 8.5))
	_add_puddle(geo, Vector3(0.5, 0.015, 12.5), Vector2(7.0, 6.0))

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

	# 入口附近的線索桌與 M.E.G. 檔案庫終端機
	_spawn_model(props, MODEL_DIR + "retro_office_desk.glb", "GarageDesk", Vector3(-3.2, 0.0, 1.5), 90.0, Vector3(1.5, 0.78, 0.8))
	_spawn_model(props, PROP_DIR + "computer_screen.glb", "GarageScreen", Vector3(-3.2, 0.78, 1.85), 90.0, Vector3(0.45, 0.45, 0.4))
	_add_wiki_terminal(props, "GarageWikiTerminal", Vector3(-3.2, 1.0, 1.85), Vector3(0.65, 0.65, 0.65), "瀏覽 M.E.G.「宜居地帶」檔案庫")
	_spawn_model(props, MODEL_DIR + "office_chair.glb", "GarageChair", Vector3(-2.3, 0.0, 1.4), -75.0, Vector3(0.65, 0.95, 0.65))
	_add_note_prop(props, "HabitableIntroNote", Vector3(-3.2, 0.80, 1.1),
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

	# 廢棄車輛、三角錐與大型垃圾子車（Blender 降飽和做舊，CC0）
	_spawn_model(props, PROP_DIR + "car_sedan.glb", "CarSedan_1", Vector3(-12.5, 0.0, 12.0), 18.0, Vector3(2.1, 1.5, 4.3))
	_add_note_prop(props, "CarWarningNote", Vector3(-11.2, 0.92, 11.4),
		"查看轎車引擎蓋上的紙條", "車主留下的紙條",
		"【別在停車場久留】\n\n"
		+ "車門鎖死了，但引擎還是微溫的。別把燈照向東邊的柱子太久……\n"
		+ "每次燈開始亂閃的時候，柱陣後面都有東西在跟著腳步聲移動。"
	)
	_spawn_model(props, PROP_DIR + "car_suv.glb", "CarSUV_1", Vector3(12.2, 0.0, -14.5), -95.0, Vector3(4.5, 1.65, 2.25))
	_build_parking_lines(geo)
	_spawn_model(props, PROP_DIR + "dumpster.glb", "Dumpster_1", Vector3(22.2, 0.0, -6.5), -90.0, Vector3(1.0, 1.58, 1.9))
	_spawn_model(props, PROP_DIR + "dumpster.glb", "Dumpster_2", Vector3(22.2, 0.0, 14.0), -90.0, Vector3(1.0, 1.58, 1.9))
	_spawn_model(props, PROP_DIR + "traffic_cone.glb", "Cone_1", Vector3(-4.5, 0.0, -5.2), 0.0, Vector3(0.55, 0.72, 0.55))
	_spawn_model(props, PROP_DIR + "traffic_cone.glb", "Cone_2", Vector3(4.2, 0.0, 18.8), 15.0, Vector3(0.55, 0.72, 0.55))
	_spawn_model(props, PROP_DIR + "traffic_cone.glb", "Cone_3", Vector3(-4.2, 0.0, 18.8), -20.0, Vector3(0.55, 0.72, 0.55))
	_spawn_model(props, MODEL_DIR + "breaker_box.glb", "MainBreakerBox", Vector3(-23.6, 1.35, -3.5), 90.0, Vector3(0.35, 0.7, 0.5))
	_west_lamp_mat = _add_status_lamp(props, Vector3(-23.55, 2.05, -3.5), false)
	_west_breaker_body = _add_breaker_switch(props, "BreakerInteract", Vector3(-23.4, 1.35, -3.5), Vector3(0.7, 1.2, 0.8),
		"啟動西區配電箱開關", "west"
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
	_spawn_model(props, MODEL_DIR + "breaker_box.glb", "NorthBreakerBox", Vector3(2.8, 1.35, -33.6), 0.0, Vector3(0.5, 0.7, 0.35))
	_north_lamp_mat = _add_status_lamp(props, Vector3(2.8, 2.05, -33.55), false)
	_north_breaker_body = _add_breaker_switch(props, "NorthBreakerInteract", Vector3(2.8, 1.35, -33.4), Vector3(0.8, 1.2, 0.7),
		"啟動北區管線配電箱", "north"
	)
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
	_add_box(geo, Vector3(16.0, 0.2, 10.0), Vector3(0.0, -0.1, 25.0), MAT_HALL_FLOOR, true)
	_add_puddle(geo, Vector3(0.0, 0.015, 25.0), Vector2(14.5, 9.0))
	_add_box(geo, Vector3(16.0, 0.2, 10.0), Vector3(0.0, CEIL_H + 0.1, 25.0), _mat_concrete_dark, true)
	_add_box(geo, Vector3(WALL_T, CEIL_H, 10.0), Vector3(-8.0, CEIL_H * 0.5, 25.0), MAT_HALL_WALL, true)
	_add_box(geo, Vector3(WALL_T, CEIL_H, 10.0), Vector3(8.0, CEIL_H * 0.5, 25.0), MAT_HALL_WALL, true)

	# 南牆 (z = 30) 中央留 3.6m 電動捲門開口
	_add_box(geo, Vector3(6.2, CEIL_H, WALL_T), Vector3(-4.9, CEIL_H * 0.5, 30.0), MAT_DARK_BRICK, true)
	_add_box(geo, Vector3(6.2, CEIL_H, WALL_T), Vector3(4.9, CEIL_H * 0.5, 30.0), MAT_DARK_BRICK, true)
	_add_box(geo, Vector3(3.6, 0.8, WALL_T), Vector3(0.0, 3.2, 30.0), MAT_DARK_BRICK, true)

	# 電動捲門本體（復電後可開啟升起）
	_south_door_node = StaticBody3D.new()
	_south_door_node.name = "SouthShutterDoor"
	_south_door_node.position = Vector3(0.0, 1.4, 30.0)
	_south_door_node.set_script(INTERACT_SCRIPT)
	_south_door_node.set("prompt_text", "操作電動捲門（斷電中：0/2）")
	_south_door_node.set_meta("on_interact", func(player: Node) -> void:
		_on_south_door_interact(player)
	)
	var door_mi := MeshInstance3D.new()
	var door_bm := BoxMesh.new()
	door_bm.size = Vector3(3.6, 2.8, 0.22)
	door_bm.subdivide_width = 1
	door_bm.subdivide_height = 1
	door_mi.mesh = door_bm
	door_mi.material_override = MAT_VENT_GRILL
	_south_door_node.add_child(door_mi)
	var door_col := CollisionShape3D.new()
	var door_shape := BoxShape3D.new()
	door_shape.size = Vector3(3.6, 2.8, 0.4)
	door_col.shape = door_shape
	_south_door_node.add_child(door_col)
	props.add_child(_south_door_node)
	_south_door_prompt_body = _south_door_node

	# 門邊狀態燈與出口牌
	_south_lamp_mat = _add_status_lamp(props, Vector3(2.2, 1.55, 29.75), false)
	_spawn_model(props, MODEL_DIR + "exit_sign.glb", "SouthExitSign", Vector3(0.0, 3.15, 29.65), 180.0, Vector3(0.5, 0.25, 0.2))
	_south_door_light = OmniLight3D.new()
	_south_door_light.position = Vector3(0.0, 2.7, 29.0)
	_south_door_light.light_color = Color(1.0, 0.22, 0.18)
	_south_door_light.light_energy = 0.85
	_south_door_light.omni_range = 7.5
	lights.add_child(_south_door_light)

	# 捲門後方：M.E.G. 地下安全避難所 (x: -5..5, z: 30..39)
	_add_box(geo, Vector3(10.0, 0.2, 9.0), Vector3(0.0, -0.1, 34.5), MAT_HALL_FLOOR, true)
	_add_box(geo, Vector3(10.0, 0.2, 9.0), Vector3(0.0, CEIL_H + 0.1, 34.5), _mat_concrete_dark, true)
	_add_box(geo, Vector3(WALL_T, CEIL_H, 9.0), Vector3(-5.0, CEIL_H * 0.5, 34.5), MAT_HALL_WALL, true)
	_add_box(geo, Vector3(WALL_T, CEIL_H, 9.0), Vector3(5.0, CEIL_H * 0.5, 34.5), MAT_HALL_WALL, true)
	_add_box(geo, Vector3(10.0, CEIL_H, WALL_T), Vector3(0.0, CEIL_H * 0.5, 39.0), MAT_HALL_WALL, true)
	_add_omni(lights, Vector3(0.0, 3.1, 34.5), Color(1.0, 0.86, 0.62), 1.35, 11.0, false, false)

	_spawn_model(props, MODEL_DIR + "retro_office_desk.glb", "ShelterDesk", Vector3(0.0, 0.0, 37.2), 180.0, Vector3(1.5, 0.78, 0.8))
	_spawn_model(props, PROP_DIR + "computer_screen.glb", "ShelterScreen", Vector3(0.3, 0.78, 37.2), 180.0, Vector3(0.5, 0.45, 0.4))
	_spawn_model(props, PROP_DIR + "armchair.glb", "ShelterCouch", Vector3(-3.3, 0.0, 34.5), 90.0, Vector3(1.7, 1.0, 1.6))
	_spawn_model(props, PROP_DIR + "shelf_small.glb", "ShelterShelf", Vector3(3.8, 0.0, 35.0), -90.0, Vector3(1.2, 1.8, 0.5))
	_add_note_prop(props, "ShelterLogNote", Vector3(-0.2, 0.80, 37.2),
		"閱讀避難所桌上的終端日誌", "M.E.G. 宜居地帶前哨日誌",
		"【恭喜抵達：宜居地帶安全前哨】\n\n"
		+ "你成功修復了西區與北區的配電開關，並開啟了南側電動捲門。\n"
		+ "在無盡的潮濕混凝土迷宮中，這間備用發電機供電的避難所是目前最穩定的歇腳處。\n\n"
		+ "（你可以隨時按 [M] 開啟導航終端機返回「閾界」，或繼續探索這座停車場。）"
	)


func _build_b2_warehouse(geo: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	# 1. 車道斜坡 (x: 24..40, z: -3..3)，從 y=0.0 緩降至 y=-4.0
	var ramp_len := 16.0
	var drop := 4.0
	var slope_ang := atan2(-drop, ramp_len)
	var diag_len := sqrt(ramp_len * ramp_len + drop * drop)
	_add_rotated_box(geo, Vector3(diag_len + 0.4, 0.25, 6.0), Vector3(32.0, -drop * 0.5 - 0.12, 0.0), Vector3(0.0, 0.0, slope_ang), MAT_HALL_FLOOR, true)
	# 斜坡兩側矮護欄與外牆
	_add_box(geo, Vector3(16.0, 8.0, WALL_T), Vector3(32.0, -0.2, -3.2), MAT_HALL_WALL, true)
	_add_box(geo, Vector3(16.0, 8.0, WALL_T), Vector3(32.0, -0.2, 3.2), MAT_HALL_WALL, true)
	_add_box(geo, Vector3(16.0, 0.25, 6.4), Vector3(32.0, 3.6, 0.0), _mat_concrete_dark, true)
	_add_omni(lights, Vector3(25.0, 3.0, 0.0), Color(0.84, 0.90, 0.98), 0.9, 10.0, false, false)
	_add_omni(lights, Vector3(33.5, 1.0, 0.0), Color(0.75, 0.86, 0.96), 0.85, 11.0, false, true)
	_spawn_model(props, PROP_DIR + "traffic_cone.glb", "RampCone_1", Vector3(24.3, 0.0, -2.5), 0.0, Vector3(0.55, 0.72, 0.55))
	_spawn_model(props, PROP_DIR + "traffic_cone.glb", "RampCone_2", Vector3(24.3, 0.0, 2.5), 25.0, Vector3(0.55, 0.72, 0.55))

	# 2. B2 挑高大型貨架倉庫 (x: 40..76, z: -18..18, 地板 y=-4.0, 天花 y=2.0，挑高 6m)
	var by := -4.0
	var b2_h := 6.0
	_add_box(geo, Vector3(36.0, 0.2, 36.0), Vector3(58.0, by - 0.1, 0.0), MAT_HALL_FLOOR, true)
	_add_box(geo, Vector3(36.0, 0.2, 36.0), Vector3(58.0, by + b2_h + 0.1, 0.0), _mat_concrete_dark, true)
	# B2 四周牆壁（西牆 x=40 中間 z:-3..3 留斜坡開口）
	_add_box(geo, Vector3(WALL_T, b2_h, 15.0), Vector3(40.0, by + b2_h * 0.5, -10.5), MAT_HALL_WALL, true)
	_add_box(geo, Vector3(WALL_T, b2_h, 15.0), Vector3(40.0, by + b2_h * 0.5, 10.5), MAT_HALL_WALL, true)
	_add_box(geo, Vector3(WALL_T, 1.8, 6.0), Vector3(40.0, by + b2_h - 0.9, 0.0), MAT_HALL_WALL, true)
	_add_box(geo, Vector3(WALL_T, b2_h, 15.0), Vector3(76.0, by + b2_h * 0.5, -10.5), MAT_HALL_WALL, true)
	_add_box(geo, Vector3(WALL_T, b2_h, 15.0), Vector3(76.0, by + b2_h * 0.5, 10.5), MAT_HALL_WALL, true)
	_add_box(geo, Vector3(WALL_T, 1.8, 6.0), Vector3(76.0, by + b2_h - 0.9, 0.0), MAT_HALL_WALL, true)
	_add_box(geo, Vector3(36.0, b2_h, WALL_T), Vector3(58.0, by + b2_h * 0.5, -18.0), MAT_HALL_WALL, true)
	_add_box(geo, Vector3(36.0, b2_h, WALL_T), Vector3(58.0, by + b2_h * 0.5, 18.0), MAT_HALL_WALL, true)

	# B2 反射探針與中央積水
	var b2_probe := ReflectionProbe.new()
	b2_probe.position = Vector3(58.0, by + b2_h * 0.5, 0.0)
	b2_probe.size = Vector3(36.0, b2_h + 0.5, 36.0)
	b2_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(b2_probe)
	_add_puddle(geo, Vector3(54.0, by + 0.015, 0.0), Vector2(10.0, 6.5))

	# B2 挑高混凝土柱與冷白燈
	for px in [48.0, 60.0, 70.0]:
		for pz in [-9.0, 9.0]:
			_add_box(geo, Vector3(1.0, b2_h, 1.0), Vector3(px, by + b2_h * 0.5, pz), MAT_HALL_WALL, true)
			_add_box(geo, Vector3(1.06, 0.25, 1.06), Vector3(px, by + 0.8, pz), _mat_hazard, false)
	for lx in [46.0, 58.0, 70.0]:
		for lz in [-10.0, 0.0, 10.0]:
			var lp := Vector3(lx, by + b2_h - 0.15, lz)
			_add_box(geo, Vector3(1.8, 0.06, 0.3), lp + Vector3(0.0, 0.1, 0.0), MAT_FLUORESCENT, false)
			_add_omni(lights, lp - Vector3(0.0, 0.3, 0.0), Color(0.80, 0.89, 0.98), 1.35, 15.0, false, lx == 70.0 and lz == 0.0)

	# B2 多層工業貨架陣列（兩排通道 + 堆放木箱/棧板/鐵桶）
	for rx in [50.0, 58.0, 66.0]:
		for rz in [-13.5, -5.5, 5.5, 13.5]:
			_add_warehouse_rack(geo, props, Vector3(rx, by, rz))

	# B2 工頭辦公桌與檔案紀錄
	_spawn_model(props, MODEL_DIR + "retro_office_desk.glb", "B2Desk", Vector3(44.5, by, -14.5), 0.0, Vector3(1.5, 0.78, 0.8))
	_spawn_model(props, PROP_DIR + "computer_screen.glb", "B2Screen", Vector3(44.2, by + 0.78, -14.5), 0.0, Vector3(0.5, 0.45, 0.4))
	_spawn_model(props, PROP_DIR + "car_suv.glb", "B2CargoSUV", Vector3(68.0, by, 1.5), 165.0, Vector3(4.5, 1.65, 2.25))
	_add_note_prop(props, "B2WarehouseNote", Vector3(44.9, by + 0.80, -14.5),
		"閱讀 B2 貨架倉庫的盤點表", "B2 大型倉庫盤點紀錄",
		"【宜居地帶 — B2 地下倉庫區】\n\n"
		+ "這裡的天花板比一樓停車場高出許多，整排貨架上堆滿了沒有標籤的密封木箱。\n"
		+ "我們試著撬開過三個箱子：第一個裡面全是杏仁水，第二個是空白的錄影帶，第三個……是空的，但箱蓋內側有抓痕。\n\n"
		+ "「別在晚上走進最東邊的貨架通道。」"
	)


func _build_generator_room(geo: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	# B2 發電機房／鍋爐室 (x: 76..94, z: -10..10, 地板 y=-4.0, 天花 y=1.0)
	var by := -4.0
	var gh := 5.0
	_add_box(geo, Vector3(18.0, 0.2, 20.0), Vector3(85.0, by - 0.1, 0.0), MAT_DARK_BRICK, true)
	_add_box(geo, Vector3(18.0, 0.2, 20.0), Vector3(85.0, by + gh + 0.1, 0.0), _mat_concrete_dark, true)
	_add_box(geo, Vector3(18.0, gh, WALL_T), Vector3(85.0, by + gh * 0.5, -10.0), MAT_DARK_BRICK, true)
	_add_box(geo, Vector3(18.0, gh, WALL_T), Vector3(85.0, by + gh * 0.5, 10.0), MAT_DARK_BRICK, true)
	_add_box(geo, Vector3(WALL_T, gh, 20.0), Vector3(94.0, by + gh * 0.5, 0.0), MAT_DARK_BRICK, true)

	# 暖橘色工業燈光（與冷白倉庫形成強烈對比）
	_add_omni(lights, Vector3(82.0, by + gh - 0.4, -4.5), Color(1.0, 0.56, 0.22), 1.45, 13.0, false, false)
	_add_omni(lights, Vector3(82.0, by + gh - 0.4, 4.5), Color(1.0, 0.52, 0.20), 1.45, 13.0, false, true)
	_add_omni(lights, Vector3(91.5, by + 3.2, 0.0), Color(1.0, 0.24, 0.18), 0.9, 8.0, false, false)

	# 兩座大型柴油發電機／鍋爐機組
	for gz in [-5.8, 5.8]:
		_add_box(geo, Vector3(5.2, 0.35, 2.8), Vector3(83.5, by + 0.175, gz), _mat_concrete_dark, true)
		_add_box(geo, Vector3(4.2, 1.8, 2.0), Vector3(83.5, by + 1.25, gz), _mat_pipe, true)
		_add_box(geo, Vector3(4.3, 0.2, 2.1), Vector3(83.5, by + 0.55, gz), _mat_hazard, false)
		_add_status_lamp(props, Vector3(81.35, by + 1.55, gz), true)
		# 排氣管直通天花板
		var pipe_mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.22
		cm.bottom_radius = 0.22
		cm.height = 3.2
		cm.radial_segments = 10
		pipe_mi.mesh = cm
		pipe_mi.position = Vector3(84.6, by + 3.4, gz)
		pipe_mi.material_override = _mat_pipe
		geo.add_child(pipe_mi)

	# 東端深層貨梯出口 (x = 91.5..93.8, z = -2..2)
	_add_box(geo, Vector3(2.4, 3.2, 0.18), Vector3(92.4, by + 1.6, -2.0), MAT_VENT_GRILL, true)
	_add_box(geo, Vector3(2.4, 3.2, 0.18), Vector3(92.4, by + 1.6, 2.0), MAT_VENT_GRILL, true)
	_add_box(geo, Vector3(0.2, 3.2, 4.0), Vector3(93.6, by + 1.6, 0.0), MAT_VENT_GRILL, true)
	_spawn_model(props, MODEL_DIR + "exit_sign.glb", "ElevatorExitSign", Vector3(91.1, by + 3.3, 0.0), -90.0, Vector3(0.5, 0.25, 0.2))
	_add_status_lamp(props, Vector3(91.15, by + 1.4, -2.2), true)
	_add_interactive_box(props, "CargoElevatorCall", Vector3(91.15, by + 1.3, -2.2), Vector3(0.6, 1.0, 0.6),
		"按下深層貨梯按鈕（通往：管道區）", "深層貨梯終端",
		"【深層貨梯 — 目標層級：管道區】\n\n"
		+ "貨梯面板的指示燈已經亮起，代表這裡就是「宜居地帶」通往下一層的正式出口。\n"
		+ "（目前「管道區」尚未施工完成，預計於下一次擴建後開放搭乘！）"
	)


func _build_west_breakroom(geo: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	# 西側員工休息室／監控室 (x: -36..-24, z: -18..-4)
	_add_box(geo, Vector3(12.0, 0.2, 14.0), Vector3(-30.0, -0.1, -11.0), MAT_HALL_FLOOR, true)
	_add_box(geo, Vector3(12.0, 0.2, 14.0), Vector3(-30.0, CEIL_H + 0.1, -11.0), _mat_concrete_dark, true)
	_add_box(geo, Vector3(WALL_T, CEIL_H, 14.0), Vector3(-36.0, CEIL_H * 0.5, -11.0), MAT_HALL_WALL, true)
	_add_box(geo, Vector3(12.0, CEIL_H, WALL_T), Vector3(-30.0, CEIL_H * 0.5, -18.0), MAT_HALL_WALL, true)
	_add_box(geo, Vector3(12.0, CEIL_H, WALL_T), Vector3(-30.0, CEIL_H * 0.5, -4.0), MAT_HALL_WALL, true)

	# 偏綠的舊式日光燈管與微弱閃爍
	_add_box(geo, Vector3(1.5, 0.06, 0.28), Vector3(-30.0, CEIL_H - 0.05, -11.0), MAT_FLUORESCENT, false)
	_add_omni(lights, Vector3(-30.0, CEIL_H - 0.35, -11.0), Color(0.76, 0.94, 0.80), 1.15, 11.5, false, false)

	_spawn_model(props, MODEL_DIR + "retro_office_desk.glb", "BreakDesk", Vector3(-34.6, 0.0, -14.5), 90.0, Vector3(1.5, 0.78, 0.8))
	_spawn_model(props, PROP_DIR + "computer_screen.glb", "BreakMonitor", Vector3(-34.6, 0.78, -14.5), 90.0, Vector3(0.5, 0.45, 0.4))
	_add_wiki_terminal(props, "BreakWikiTerminal", Vector3(-34.6, 1.0, -14.5), Vector3(0.65, 0.65, 0.65), "使用監控終端查閱 M.E.G. 檔案庫")
	_spawn_model(props, PROP_DIR + "coffee_machine.glb", "BreakCoffee", Vector3(-34.6, 0.78, -14.0), 90.0, Vector3(0.35, 0.4, 0.35))
	_spawn_model(props, PROP_DIR + "fridge.glb", "BreakFridge", Vector3(-34.8, 0.0, -6.5), 90.0, Vector3(0.8, 1.7, 0.8))
	_spawn_model(props, PROP_DIR + "armchair.glb", "BreakCouch", Vector3(-30.0, 0.0, -5.8), 180.0, Vector3(1.7, 1.0, 1.6))
	_spawn_model(props, PROP_DIR + "plant.glb", "BreakPlant", Vector3(-25.4, 0.0, -5.2), 0.0, Vector3(0.5, 0.9, 0.5))
	_spawn_model(props, MODEL_DIR + "filing_cabinet.glb", "BreakCabinet", Vector3(-29.5, 0.0, -17.1), 0.0, Vector3(0.6, 1.4, 0.7))
	_add_note_prop(props, "GuardLogNote", Vector3(-34.5, 0.80, -15.0),
		"閱讀值班桌上的警衛交接簿", "地下停車場值班紀錄",
		"【交接事項 — 夜班】\n\n"
		+ "1. 西牆外面的主配電箱最近常跳脫，記得順手推上去。\n"
		+ "2. 東邊車道斜坡下去是 B2 貨架區，沒有必要不要在跳電時下去。\n"
		+ "3. 咖啡機已經壞了三週，但每到凌晨三點還是會自己滴出黑水——別喝。"
	)


func _add_wiki_terminal(parent: Node3D, node_name: String, pos: Vector3, col_size: Vector3, prompt: String) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.set_script(INTERACT_SCRIPT)
	body.set("prompt_text", prompt)
	body.set("interaction_type", "wiki_archive")
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = col_size
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)


func _add_warehouse_rack(geo: StaticBody3D, props: Node3D, base_pos: Vector3) -> void:
	# 寬 4.2m、深 1.5m、高 4.0m 的兩層工業貨架
	var w := 4.2
	var d := 1.5
	var h := 4.0
	for sx in [-w * 0.46, w * 0.46]:
		for sz in [-d * 0.44, d * 0.44]:
			_add_box(geo, Vector3(0.14, h, 0.14), base_pos + Vector3(sx, h * 0.5, sz), _mat_pipe, false)
	_add_box(geo, Vector3(w, 0.12, d), base_pos + Vector3(0.0, 1.6, 0.0), _mat_concrete_dark, true)
	_add_box(geo, Vector3(w, 0.12, d), base_pos + Vector3(0.0, 3.2, 0.0), _mat_concrete_dark, false)
	# 整體貨架碰撞箱，避免玩家卡進鋼柱縫裡
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(w, h, d)
	col.shape = shape
	col.position = base_pos + Vector3(0.0, h * 0.5, 0.0)
	geo.add_child(col)
	# 貨架上擺放箱子與鐵桶
	_spawn_model(props, PROP_DIR + "box_closed.glb", "RackBoxA", base_pos + Vector3(-1.1, 1.66, 0.0), 8.0, Vector3(0.1, 0.1, 0.1))
	_spawn_model(props, PROP_DIR + "cardboard_boxes.glb", "RackBoxB", base_pos + Vector3(0.9, 1.66, 0.0), -12.0, Vector3(0.1, 0.1, 0.1))
	_spawn_model(props, PROP_DIR + "barrel.glb", "RackBarrel", base_pos + Vector3(0.0, 3.26, 0.0), 0.0, Vector3(0.1, 0.1, 0.1))


func _add_rotated_box(parent: Node3D, sz: Vector3, pos: Vector3, rot_rad: Vector3, mat: Material, with_col: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	bm.subdivide_width = clampi(int(sz.x / 2.0) - 1, 0, 16)
	bm.subdivide_depth = clampi(int(sz.z / 2.0) - 1, 0, 16)
	mi.mesh = bm
	mi.position = pos
	mi.rotation = rot_rad
	mi.material_override = mat
	parent.add_child(mi)
	if with_col:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = sz
		col.shape = shape
		col.position = pos
		col.rotation = rot_rad
		parent.add_child(col)


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


func _build_parking_lines(geo: StaticBody3D) -> void:
	# 中央雙黃虛線（標示南北主車道）
	for lz in [-16.0, -12.0, -8.0, -4.0, 0.0, 4.0, 8.0, 12.0, 16.0]:
		_add_box(geo, Vector3(0.12, 0.008, 2.0), Vector3(-0.18, 0.006, lz), _mat_hazard, false)
		_add_box(geo, Vector3(0.12, 0.008, 2.0), Vector3(0.18, 0.006, lz), _mat_hazard, false)

	# 西側與東側停車格白線
	for pz in [-15.0, -11.5, -8.0, 8.0, 11.5, 15.0]:
		_add_box(geo, Vector3(4.6, 0.008, 0.11), Vector3(-12.5, 0.006, pz), _mat_paint_white, false)
		_add_box(geo, Vector3(4.6, 0.008, 0.11), Vector3(12.5, 0.006, pz), _mat_paint_white, false)


func _add_puddle(parent: Node3D, pos: Vector3, sz: Vector2) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = sz
	pm.subdivide_width = clampi(int(sz.x / 1.5) - 1, 0, 16)
	pm.subdivide_depth = clampi(int(sz.y / 1.5) - 1, 0, 16)
	mi.mesh = pm
	mi.position = pos
	mi.material_override = MAT_PUDDLE_WATER
	parent.add_child(mi)


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


func _add_status_lamp(parent: Node3D, pos: Vector3, is_green: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var col := Color(0.2, 0.95, 0.4) if is_green else Color(0.95, 0.18, 0.15)
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.0

	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.16
	mi.mesh = sm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mat


func _add_breaker_switch(parent: Node3D, node_name: String, pos: Vector3, col_size: Vector3, prompt: String, side: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.set_script(INTERACT_SCRIPT)
	body.set("prompt_text", prompt)
	body.set_meta("on_interact", func(player: Node) -> void:
		_on_breaker_interact(player, side)
	)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = col_size
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
	return body


func _on_breaker_interact(player: Node, side: String) -> void:
	var changed := false
	if side == "west" and not _west_breaker_on:
		_west_breaker_on = true
		changed = true
		if _west_lamp_mat:
			_west_lamp_mat.albedo_color = Color(0.2, 0.95, 0.4)
			_west_lamp_mat.emission = Color(0.2, 0.95, 0.4)
		if _west_breaker_body:
			_west_breaker_body.set("prompt_text", "西區配電箱（已復電）")
	elif side == "north" and not _north_breaker_on:
		_north_breaker_on = true
		changed = true
		if _north_lamp_mat:
			_north_lamp_mat.albedo_color = Color(0.2, 0.95, 0.4)
			_north_lamp_mat.emission = Color(0.2, 0.95, 0.4)
		if _north_breaker_body:
			_north_breaker_body.set("prompt_text", "北區配電箱（已復電）")

	if changed and _breaker_player:
		_breaker_player.play()

	var count := int(_west_breaker_on) + int(_north_breaker_on)
	if count >= 2:
		if _south_lamp_mat:
			_south_lamp_mat.albedo_color = Color(0.2, 0.95, 0.4)
			_south_lamp_mat.emission = Color(0.2, 0.95, 0.4)
		if _south_door_light:
			_south_door_light.light_color = Color(0.25, 0.95, 0.45)
		if _south_door_prompt_body and not _south_door_open:
			_south_door_prompt_body.set("prompt_text", "開啟南側電動捲門（供電正常）")

	var msg := "【配電狀態：%d / 2】\n\n" % count
	if count >= 2:
		msg += "兩處配電箱皆已復電！南側積水區盡頭的電動捲門指示燈已轉綠，現在可以過去開門了。"
	elif side == "west":
		msg += "西區配電箱已推上開關。\n貼紙提示還有一處開關在「北邊管線走廊」深處。"
	else:
		msg += "北區管線配電箱已推上開關。\n還差西牆附近的主配電箱尚未復電。"

	_show_inline_note(player, "配電控制紀錄", msg)


func _on_south_door_interact(player: Node) -> void:
	var count := int(_west_breaker_on) + int(_north_breaker_on)
	if count < 2:
		_show_inline_note(player, "電動捲門（斷電中）",
			"【供電不足：%d / 2】\n\n" % count
			+ "捲門馬達沒有反應。需要先去啟動停車場「西牆」與「北側走廊盡頭」的兩處配電箱復電。"
		)
		return
	if not _south_door_open:
		_south_door_open = true
		if _breaker_player:
			_breaker_player.play()
		if _south_door_prompt_body:
			_south_door_prompt_body.set("prompt_text", "電動捲門（已開啟）")


func _show_inline_note(player: Node, title: String, body_txt: String) -> void:
	var dummy := Node.new()
	dummy.set_script(INTERACT_SCRIPT)
	dummy.set("interaction_type", "note")
	dummy.set("file_name", title)
	dummy.set("body_text", body_txt)
	if player and player.has_method("open_prop_ui"):
		player.open_prop_ui(dummy)
	dummy.queue_free()
