@tool
extends Node3D

const MAT_DARK_BRICK := preload("res://materials/mat_dark_brick.tres")
const MAT_WET_FLOOR := preload("res://materials/mat_wet_floor.tres")
const MAT_HALL_WALL := preload("res://materials/mat_hall_wall.tres")
const MAT_HALL_FLOOR := preload("res://materials/mat_hall_floor.tres")
const MAT_TEAL_TRIM := preload("res://materials/mat_teal_trim.tres")
const MAT_MAGENTA_RING := preload("res://materials/mat_magenta_ring.tres")
const MAT_VENT_GRILL := preload("res://materials/mat_vent_grill.tres")
const INTERACT_SCRIPT := preload("res://scripts/interactable_prop.gd")

const LEVEL0_FOG_COLOR := Color(0.32, 0.29, 0.16)
const ZONE2_FOG_COLOR := Color(0.18, 0.20, 0.23)
const LEVEL0_AMBIENT_COLOR := Color(0.55, 0.50, 0.30)
const ZONE2_AMBIENT_COLOR := Color(0.32, 0.35, 0.40)

var _in_zone2: bool = false
var _blend: float = 0.0
var _world_env: WorldEnvironment
var _ambient_hum: AudioStreamPlayer


func _ready() -> void:
	if get_child_count() == 0:
		_build_zone2()
	if not Engine.is_editor_hint():
		_world_env = get_parent().get_node_or_null("WorldEnvironment")
		_ambient_hum = get_parent().get_node_or_null("AmbientHum")


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var target := 1.0 if _in_zone2 else 0.0
	if absf(_blend - target) < 0.002:
		return
	_blend = lerpf(_blend, target, clampf(delta * 2.2, 0.0, 1.0))

	if _world_env and _world_env.environment:
		var env := _world_env.environment
		env.fog_light_color = LEVEL0_FOG_COLOR.lerp(ZONE2_FOG_COLOR, _blend)
		env.fog_density = lerpf(0.085, 0.075, _blend)
		env.ambient_light_color = LEVEL0_AMBIENT_COLOR.lerp(ZONE2_AMBIENT_COLOR, _blend)

	if _ambient_hum:
		_ambient_hum.volume_db = lerpf(-15.5, -26.0, _blend)


func _build_zone2() -> void:
	var body := StaticBody3D.new()
	body.name = "Zone2Geometry"
	add_child(body)

	var lights := Node3D.new()
	lights.name = "Zone2Lights"
	add_child(lights)

	# --- Part 1: Dark Wet Transition Tunnel (x: 16.9 -> 24.9, z centered at 7.8) ---
	_add_box(body, Vector3(8.0, 0.2, 5.2), Vector3(20.9, -0.1, 7.8), MAT_WET_FLOOR, Vector3i(8, 0, 5), true)
	_add_box(body, Vector3(8.0, 0.2, 5.2), Vector3(20.9, 3.1, 7.8), MAT_DARK_BRICK, Vector3i(8, 0, 5), true)
	_add_box(body, Vector3(8.0, 3.0, 0.3), Vector3(20.9, 1.5, 5.35), MAT_DARK_BRICK, Vector3i(8, 3, 0), true)
	_add_box(body, Vector3(8.0, 3.0, 0.3), Vector3(20.9, 1.5, 10.25), MAT_DARK_BRICK, Vector3i(8, 3, 0), true)
	_add_box(body, Vector3(0.3, 3.0, 1.0), Vector3(17.05, 1.5, 6.0), MAT_DARK_BRICK, Vector3i(0, 3, 1), true)
	_add_box(body, Vector3(0.3, 3.0, 1.0), Vector3(17.05, 1.5, 9.6), MAT_DARK_BRICK, Vector3i(0, 3, 1), true)
	_add_box(body, Vector3(0.3, 3.8, 1.4), Vector3(24.9, 1.9, 5.9), MAT_DARK_BRICK, Vector3i(0, 3, 1), true)
	_add_box(body, Vector3(0.3, 3.8, 1.4), Vector3(24.9, 1.9, 9.7), MAT_DARK_BRICK, Vector3i(0, 3, 1), true)
	_add_box(body, Vector3(0.3, 1.2, 2.4), Vector3(24.9, 3.2, 7.8), MAT_DARK_BRICK, Vector3i(0, 1, 2), true)

	var probe := ReflectionProbe.new()
	probe.position = Vector3(20.9, 1.5, 7.8)
	probe.size = Vector3(8.6, 3.4, 5.4)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)

	_add_omni(lights, Vector3(18.5, 2.4, 7.8), Color(0.85, 0.88, 0.90), 0.55, 6.5, false)
	_add_omni(lights, Vector3(25.3, 1.5, 7.8), Color(0.20, 0.95, 0.85), 2.3, 9.5, true)

	# --- Part 2: Gray Pillar Atrium Hall (x: 24.9 -> 46.9, z: -1.2 -> 16.8) ---
	_add_box(body, Vector3(22.0, 0.2, 18.0), Vector3(35.9, -0.1, 7.8), MAT_HALL_FLOOR, Vector3i(22, 0, 18), true)
	_add_box(body, Vector3(22.0, 0.2, 18.0), Vector3(35.9, 3.9, 7.8), MAT_HALL_WALL, Vector3i(22, 0, 18), true)
	_add_box(body, Vector3(0.3, 3.8, 18.6), Vector3(47.05, 1.9, 7.8), MAT_HALL_WALL, Vector3i(0, 3, 18), true)
	_add_box(body, Vector3(9.7, 3.8, 0.3), Vector3(29.75, 1.9, -1.35), MAT_HALL_WALL, Vector3i(10, 3, 0), true)
	_add_box(body, Vector3(9.5, 3.8, 0.3), Vector3(42.15, 1.9, -1.35), MAT_HALL_WALL, Vector3i(10, 3, 0), true)
	_add_box(body, Vector3(2.8, 1.0, 0.3), Vector3(36.0, 3.3, -1.35), MAT_HALL_WALL, Vector3i(3, 1, 0), true)
	_add_box(body, Vector3(22.0, 3.8, 0.3), Vector3(35.9, 1.9, 16.95), MAT_HALL_WALL, Vector3i(22, 3, 0), true)
	_add_box(body, Vector3(0.3, 3.8, 6.4), Vector3(24.9, 1.9, 2.0), MAT_HALL_WALL, Vector3i(0, 3, 6), true)
	_add_box(body, Vector3(0.3, 3.8, 6.4), Vector3(24.9, 1.9, 13.6), MAT_HALL_WALL, Vector3i(0, 3, 6), true)

	_add_box(body, Vector3(21.6, 0.08, 0.75), Vector3(35.9, 3.76, 4.5), MAT_TEAL_TRIM, Vector3i(12, 0, 0), false)
	_add_box(body, Vector3(21.6, 0.08, 0.75), Vector3(35.9, 3.76, 11.1), MAT_TEAL_TRIM, Vector3i(12, 0, 0), false)
	_add_box(body, Vector3(21.6, 0.45, 0.06), Vector3(35.9, 3.45, 16.77), MAT_TEAL_TRIM, Vector3i(12, 0, 0), false)
	_add_box(body, Vector3(21.6, 0.45, 0.06), Vector3(35.9, 3.45, -1.17), MAT_TEAL_TRIM, Vector3i(12, 0, 0), false)
	_add_box(body, Vector3(3.8, 2.1, 0.06), Vector3(34.5, 1.4, 16.77), MAT_VENT_GRILL, Vector3i(2, 1, 0), false)

	var col_mesh := CylinderMesh.new()
	col_mesh.top_radius = 0.50
	col_mesh.bottom_radius = 0.50
	col_mesh.height = 3.8
	col_mesh.radial_segments = 12
	col_mesh.rings = 4

	var col_shape := CylinderShape3D.new()
	col_shape.radius = 0.50
	col_shape.height = 3.8

	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 0.53
	ring_mesh.bottom_radius = 0.53
	ring_mesh.height = 0.22
	ring_mesh.radial_segments = 12
	ring_mesh.rings = 1

	for cx in [30.0, 36.0, 42.0]:
		for cz in [4.5, 11.1]:
			var mi := MeshInstance3D.new()
			mi.mesh = col_mesh
			mi.material_override = MAT_HALL_WALL
			mi.position = Vector3(cx, 1.9, cz)
			body.add_child(mi)

			var cs := CollisionShape3D.new()
			cs.shape = col_shape
			cs.position = mi.position
			body.add_child(cs)

			var ring := MeshInstance3D.new()
			ring.mesh = ring_mesh
			ring.material_override = MAT_MAGENTA_RING
			ring.position = Vector3(cx, 2.85, cz)
			body.add_child(ring)

			_add_omni(lights, Vector3(cx, 2.85, cz), Color(1.0, 0.15, 0.85), 0.95, 5.5, false)

	_add_omni(lights, Vector3(30.5, 3.4, 7.8), Color(0.86, 0.90, 0.95), 1.35, 13.5, false)
	_add_omni(lights, Vector3(38.5, 3.4, 7.8), Color(0.86, 0.90, 0.95), 1.35, 13.5, false)
	_add_omni(lights, Vector3(44.5, 3.4, 7.8), Color(0.82, 0.86, 0.92), 1.0, 12.0, false)

	_build_column_note()
	_build_exit_door(lights)
	_build_everpine_portal(lights)

	var trigger := Area3D.new()
	trigger.name = "Zone2AtmosphereTrigger"
	trigger.position = Vector3(32.2, 1.9, 7.75)
	var trig_shape := CollisionShape3D.new()
	var trig_box := BoxShape3D.new()
	trig_box.size = Vector3(30.0, 3.8, 18.5)
	trig_shape.shape = trig_box
	trigger.add_child(trig_shape)
	trigger.body_entered.connect(_on_trigger_entered)
	trigger.body_exited.connect(_on_trigger_exited)
	add_child(trigger)


func _build_column_note() -> void:
	var note_body := StaticBody3D.new()
	note_body.name = "ColumnNote"
	note_body.position = Vector3(29.48, 1.42, 4.5)
	note_body.set_script(INTERACT_SCRIPT)
	note_body.set("prompt_text", "閱讀柱子上的紙條")
	note_body.set("interaction_type", "note")
	note_body.set("window_title", "Exploring - Note")
	note_body.set("file_name", "Memo_07")
	note_body.set("file_size", "0.4kb")
	note_body.set("body_text",
		"【維修備忘 #07】\n\n"
		+ "這裡的氣味跟黃色區域不一樣，沒有發霉地毯味，只剩潮濕水泥跟臭氧味。\n\n"
		+ "柱子上的粉紅燈環一直在響，但別去數有幾根。\n"
		+ "往最東邊盡頭的綠色指示燈門走，那裡有對外控制鎖。"
	)
	add_child(note_body)

	var paper_mat := StandardMaterial3D.new()
	paper_mat.albedo_color = Color(0.92, 0.88, 0.70)
	paper_mat.roughness = 0.9

	var paper_mesh := BoxMesh.new()
	paper_mesh.size = Vector3(0.03, 0.34, 0.26)
	var paper_mi := MeshInstance3D.new()
	paper_mi.mesh = paper_mesh
	paper_mi.material_override = paper_mat
	note_body.add_child(paper_mi)

	var note_col := CollisionShape3D.new()
	var note_shape := BoxShape3D.new()
	note_shape.size = Vector3(0.25, 0.55, 0.45)
	note_col.shape = note_shape
	note_body.add_child(note_col)


func _build_exit_door(lights: Node3D) -> void:
	var door := StaticBody3D.new()
	door.name = "GateExitDoor"
	door.position = Vector3(46.84, 1.25, 7.8)
	door.set_script(INTERACT_SCRIPT)
	door.set("prompt_text", "檢查盡頭控制鐵門")
	door.set("interaction_type", "exit_door")
	add_child(door)

	var door_mat := StandardMaterial3D.new()
	door_mat.albedo_color = Color(0.20, 0.22, 0.24)
	door_mat.metallic = 0.75
	door_mat.roughness = 0.45

	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.32, 0.34, 0.36)
	frame_mat.roughness = 0.65

	var led_mat := StandardMaterial3D.new()
	led_mat.albedo_color = Color(0.15, 0.95, 0.45)
	led_mat.emission_enabled = true
	led_mat.emission = Color(0.15, 0.95, 0.45)
	led_mat.emission_energy_multiplier = 3.2

	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(0.10, 2.5, 1.5)
	var slab := MeshInstance3D.new()
	slab.mesh = slab_mesh
	slab.material_override = door_mat
	door.add_child(slab)

	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(0.16, 2.68, 1.72)
	var frame := MeshInstance3D.new()
	frame.mesh = frame_mesh
	frame.material_override = frame_mat
	frame.position = Vector3(0.03, 0.04, 0.0)
	door.add_child(frame)

	var led_mesh := BoxMesh.new()
	led_mesh.size = Vector3(0.06, 0.14, 0.28)
	var led := MeshInstance3D.new()
	led.mesh = led_mesh
	led.material_override = led_mat
	led.position = Vector3(-0.08, 0.25, 1.05)
	door.add_child(led)

	var door_col := CollisionShape3D.new()
	var door_shape := BoxShape3D.new()
	door_shape.size = Vector3(0.45, 2.6, 1.8)
	door_col.shape = door_shape
	door.add_child(door_col)

	_add_omni(lights, Vector3(46.2, 1.6, 8.85), Color(0.20, 0.95, 0.48), 0.95, 4.5, false)


func _on_trigger_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		_in_zone2 = true


func _on_trigger_exited(body: Node3D) -> void:
	if body is CharacterBody3D:
		_in_zone2 = false


func _add_box(parent: StaticBody3D, size: Vector3, pos: Vector3, mat: Material, subdiv: Vector3i, with_col: bool) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.subdivide_width = subdiv.x
	mesh.subdivide_height = subdiv.y
	mesh.subdivide_depth = subdiv.z

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)

	if with_col:
		var shape := BoxShape3D.new()
		shape.size = size
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = pos
		parent.add_child(col)


func _add_omni(parent: Node3D, pos: Vector3, col: Color, energy: float, rng: float, shadow: bool) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = col
	light.light_energy = energy
	light.omni_range = rng
	light.shadow_enabled = shadow
	parent.add_child(light)


func _build_everpine_portal(lights: Node3D) -> void:
	# 創意實體出口：Zone 2 南牆上「不該存在的結霜商場櫥窗自動門」（通往「常青商場」）
	var portal := StaticBody3D.new()
	portal.name = "EverpineMallFrostedDoor"
	portal.position = Vector3(35.9, 0.0, 16.65)
	portal.set_script(INTERACT_SCRIPT)
	portal.set("prompt_text", "推開結霜的商場自動門（切入「常青商場」）")
	portal.set_meta("on_interact", func(_player: Node) -> void:
		get_tree().change_scene_to_file("res://scenes/everpine_mall.tscn")
	)
	add_child(portal)

	var mat_frame := StandardMaterial3D.new()
	mat_frame.albedo_color = Color(0.18, 0.22, 0.28)
	mat_frame.metallic = 0.65
	mat_frame.roughness = 0.40

	var mat_frosted := StandardMaterial3D.new()
	mat_frosted.albedo_color = Color(0.28, 0.56, 0.74)
	mat_frosted.emission_enabled = true
	mat_frosted.emission = Color(0.22, 0.52, 0.76)
	mat_frosted.emission_energy_multiplier = 1.65
	mat_frosted.roughness = 0.25

	var mat_neon := StandardMaterial3D.new()
	mat_neon.albedo_color = Color(0.45, 0.95, 1.0)
	mat_neon.emission_enabled = true
	mat_neon.emission = Color(0.35, 0.92, 1.0)
	mat_neon.emission_energy_multiplier = 2.8

	var mat_pine := StandardMaterial3D.new()
	mat_pine.albedo_color = Color(0.08, 0.24, 0.16)
	mat_pine.roughness = 0.9

	var mat_blue_tile := StandardMaterial3D.new()
	mat_blue_tile.albedo_color = Color(0.22, 0.42, 0.64)
	mat_blue_tile.metallic = 0.14
	mat_blue_tile.roughness = 0.28

	for spec in [
		# 雙開自動門鋁框
		[Vector3(2.50, 2.55, 0.18), Vector3(0.0, 1.275, 0.06), mat_frame],
		# 左右結霜玻璃門扇
		[Vector3(1.06, 2.28, 0.08), Vector3(-0.58, 1.16, -0.02), mat_frosted],
		[Vector3(1.06, 2.28, 0.08), Vector3(0.58, 1.16, -0.02), mat_frosted],
		# 門頂冰藍霓虹商場招牌條
		[Vector3(2.35, 0.24, 0.18), Vector3(0.0, 2.70, -0.04), mat_neon],
		# 玻璃內若隱若現的三株深綠松樹剪影
		[Vector3(0.32, 0.95, 0.04), Vector3(-0.58, 0.85, -0.06), mat_pine],
		[Vector3(0.38, 1.20, 0.04), Vector3(0.58, 0.95, -0.06), mat_pine],
		# 從商場門底滲出到灰色大廳的藍色地磚（抬高 2.5cm 防 Z-fighting）
		[Vector3(2.80, 0.03, 1.85), Vector3(0.0, 0.025, -0.95), mat_blue_tile],
	]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec[0]
		mi.mesh = bm
		mi.position = spec[1]
		mi.material_override = spec[2]
		portal.add_child(mi)

	_add_omni(lights, Vector3(35.9, 2.2, 15.6), Color(0.38, 0.86, 1.0), 1.8, 9.5, false)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.55, 2.60, 0.55)
	col.shape = shape
	col.position = Vector3(0.0, 1.30, -0.05)
	portal.add_child(col)
