@tool
extends Node3D

const SHADER_CONCRETE := preload("res://shaders/zone2_concrete.gdshader")
const INTERACT_SCRIPT := preload("res://scripts/interactable_prop.gd")

const GREEN_CELL := 3.0
const GREEN_COLS := 13 # x: -19.5 .. +19.5 (col 6 = x 0.0)
const GREEN_ROWS := 12 # z: -36.0 .. 0.0
const GREEN_MAP: Array[String] = [
	"###### ######", # row 0  (z: -34.5) - glowing exit at col 6
	"#  L     L  #", # row 1  - open Green Hall (Img 1 & 2)
	"#  .  P  .  #", # row 2  - pillars in hall
	"#  L     L  #", # row 3
	"### ## ## ###", # row 4
	"#L  #   #  L#", # row 5
	"# # # A # # #", # row 6  - anomaly light in center
	"# #   #   # #", # row 7
	"# ### # ### #", # row 8
	"#A  L # L  .#", # row 9  - anomaly light on west wing
	"# ###   ### #", # row 10
	"###### ######", # row 11 (z: -1.5) - entry at col 6
]

var _active_zone: String = ""
var _world_env: WorldEnvironment
var _ambient_hum: AudioStreamPlayer
var _pop_stream: AudioStreamWAV
var _unlit_panel_mat: StandardMaterial3D

var _fog_color_target := Color(0.28, 0.36, 0.14)
var _fog_density_target: float = 0.065
var _ambient_color_target := Color(0.45, 0.56, 0.25)
var _hum_db_target: float = -19.0


func _ready() -> void:
	if not Engine.is_editor_hint():
		_world_env = get_parent().get_node_or_null("WorldEnvironment")
		_ambient_hum = get_parent().get_node_or_null("AmbientHum")
		_pop_stream = BackroomsAudio.create_light_pop_stream()
	_unlit_panel_mat = StandardMaterial3D.new()
	_unlit_panel_mat.albedo_color = Color(0.14, 0.16, 0.10)
	_unlit_panel_mat.roughness = 0.75
	if get_child_count() == 0:
		_build_zone3()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _active_zone == "":
		return
	var t := clampf(delta * 2.2, 0.0, 1.0)
	if _world_env and _world_env.environment:
		var env := _world_env.environment
		env.fog_light_color = env.fog_light_color.lerp(_fog_color_target, t)
		env.fog_density = lerpf(env.fog_density, _fog_density_target, t)
		env.ambient_light_color = env.ambient_light_color.lerp(_ambient_color_target, t)
	if _ambient_hum:
		_ambient_hum.volume_db = lerpf(_ambient_hum.volume_db, _hum_db_target, t)


func _make_mat(base: Color, grid: Color, rough: float = 0.88, grid_str: float = 0.0, scale: float = 1.0, noise: float = 0.07) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_CONCRETE
	mat.set_shader_parameter("base_color", base)
	mat.set_shader_parameter("grid_color", grid)
	mat.set_shader_parameter("roughness_val", rough)
	mat.set_shader_parameter("tile_grid_strength", grid_str)
	mat.set_shader_parameter("tile_scale", scale)
	mat.set_shader_parameter("noise_strength", noise)
	return mat


func _make_emissive(color: Color, energy: float = 2.2) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.4
	return mat


func _build_zone3() -> void:
	var body := StaticBody3D.new()
	body.name = "Zone3Geometry"
	add_child(body)

	var lights := Node3D.new()
	lights.name = "Zone3Lights"
	add_child(lights)

	var props := Node3D.new()
	props.name = "Zone3Props"
	add_child(props)

	_build_green_backrooms(body, lights, props)
	_build_stair_threshold(body, lights, props)
	_build_white_hall_and_courtyard(body, lights, props)
	_build_dumpster_alcove(body, lights, props)
	_build_atmosphere_triggers()


# =========================================================================
# Block A: Green-Tinted Backrooms Sector (13x12 maze = 39m x 36m, Img 1-2)
# Local space: x: -19.5 .. +19.5, z: -36.0 .. 0.0, height: 3.4
# =========================================================================
func _build_green_backrooms(body: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	var mat_wall := _make_mat(Color(0.46, 0.52, 0.22), Color(0.32, 0.37, 0.14), 0.90, 0.0, 1.0, 0.09)
	var mat_ceil := _make_mat(Color(0.42, 0.48, 0.20), Color(0.24, 0.28, 0.10), 0.92, 0.65, 1.0, 0.06)
	var mat_floor := _make_mat(Color(0.22, 0.24, 0.11), Color(0.14, 0.16, 0.07), 0.95, 0.0, 1.0, 0.10)
	var mat_trim := _make_mat(Color(0.32, 0.36, 0.15), Color(0.2, 0.22, 0.08), 0.85, 0.0, 1.0, 0.05)
	var mat_glow_panel := _make_emissive(Color(0.85, 1.0, 0.55), 2.4)
	var mat_glow_door := _make_emissive(Color(0.88, 1.0, 0.18), 2.8)

	var total_w := GREEN_COLS * GREEN_CELL # 39.0
	var total_d := GREEN_ROWS * GREEN_CELL # 36.0
	_add_box(body, Vector3(total_w, 0.2, total_d), Vector3(0.0, -0.1, -total_d * 0.5), mat_floor, true)
	_add_box(body, Vector3(total_w, 0.2, total_d), Vector3(0.0, 3.5, -total_d * 0.5), mat_ceil, true)

	for r in range(GREEN_ROWS):
		var cz := -total_d + (r + 0.5) * GREEN_CELL
		var row_str := GREEN_MAP[r]
		for c in range(GREEN_COLS):
			var cx := -total_w * 0.5 + (c + 0.5) * GREEN_CELL
			var ch := row_str[c]
			if ch == "#":
				_add_box(body, Vector3(GREEN_CELL, 3.4, GREEN_CELL), Vector3(cx, 1.7, cz), mat_wall, true)
			elif ch == "P":
				_add_box(body, Vector3(0.95, 3.4, 0.95), Vector3(cx, 1.7, cz), mat_wall, true)
			elif ch == "L":
				_add_box(body, Vector3(1.1, 0.05, 1.1), Vector3(cx, 3.38, cz), mat_glow_panel, false)
				_add_omni(lights, Vector3(cx, 2.9, cz), Color(0.76, 0.95, 0.38), 1.05, 10.5, false)
			elif ch == "A":
				_add_green_anomaly_light(lights, Vector3(cx, 3.38, cz), mat_glow_panel)

	# Wall pilasters in the North Green Hall (Img 1 & 2)
	for pz in [-3.0, -6.5, -10.5]:
		_add_box(body, Vector3(0.7, 3.4, 0.9), Vector3(-16.15, 1.7, pz), mat_wall, true)
		_add_box(body, Vector3(0.7, 3.4, 0.9), Vector3(16.15, 1.7, pz), mat_wall, true)

	# Lintel over entry (row 11, col 6) & exit (row 0, col 6)
	_add_box(body, Vector3(GREEN_CELL, 0.6, GREEN_CELL), Vector3(0.0, 3.1, -1.5), mat_wall, true)
	_add_box(body, Vector3(GREEN_CELL, 0.9, GREEN_CELL), Vector3(0.0, 2.95, -34.5), mat_wall, true)
	_add_box(body, Vector3(9.0, 0.3, 0.35), Vector3(0.0, 3.22, -32.85), mat_trim, false)

	# Note inside west alcove of Green Sector
	var green_note := _make_interactable(
		"GreenSectorNote",
		Vector3(-14.8, 0.95, -28.5),
		Vector3(0.28, 0.36, 0.06),
		"閱讀牆上的紙條",
		"note",
		"Green_Zone_Memo",
		"【綠區巡檢紀錄】\n\n"
		+ "這裡的日光燈開始變成病態的黃綠色，走道也比外面更潮濕。\n"
		+ "有時候走到某些燈下面，燈泡會突然『啪』一聲熄掉，但不要緊張，這裡沒有別的東西。\n\n"
		+ "穿過北邊盡頭發著黃綠強光的門，就能看到通往樓上的木梯和藍光通道。"
	)
	props.add_child(green_note)
	var paper_mat := StandardMaterial3D.new()
	paper_mat.albedo_color = Color(0.88, 0.85, 0.65)
	paper_mat.roughness = 0.9
	_add_box(green_note, Vector3(0.26, 0.34, 0.02), Vector3.ZERO, paper_mat, false)

	# Glowing yellow-green doorway vestibule (z: -36.0 .. -37.2)
	_add_box(body, Vector3(0.12, 2.5, 1.2), Vector3(-1.45, 1.25, -36.6), mat_glow_door, true)
	_add_box(body, Vector3(0.12, 2.5, 1.2), Vector3(1.45, 1.25, -36.6), mat_glow_door, true)
	_add_box(body, Vector3(2.9, 0.12, 1.2), Vector3(0.0, 2.5, -36.6), mat_glow_door, true)
	_add_box(body, Vector3(3.2, 0.2, 1.4), Vector3(0.0, -0.1, -36.6), mat_floor, true)

	_add_omni(lights, Vector3(0.0, 1.6, -35.8), Color(0.88, 1.0, 0.18), 2.7, 13.5, true)
	_add_omni(lights, Vector3(0.0, 2.3, -0.6), Color(0.70, 0.92, 0.30), 0.9, 6.5, false)


func _add_green_anomaly_light(lights: Node3D, panel_pos: Vector3, mat_panel: Material) -> void:
	var panel := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(1.1, 0.05, 1.1)
	panel.mesh = pm
	panel.material_override = mat_panel
	panel.position = panel_pos
	lights.add_child(panel)

	var light := OmniLight3D.new()
	light.position = panel_pos + Vector3(0, -0.45, 0)
	light.light_color = Color(0.76, 0.95, 0.38)
	light.light_energy = 1.05
	light.omni_range = 10.5
	light.shadow_enabled = false
	lights.add_child(light)

	var trig := Area3D.new()
	trig.position = Vector3(panel_pos.x, 1.5, panel_pos.z)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.8, 3.0, 2.8)
	cs.shape = box
	trig.add_child(cs)
	lights.add_child(trig)

	var triggered := {"done": false}
	trig.body_entered.connect(func(b: Node3D) -> void:
		if triggered["done"]:
			return
		if not (b.is_in_group("player") or b.name == "Player"):
			return
		triggered["done"] = true
		if _pop_stream:
			var sfx := AudioStreamPlayer3D.new()
			sfx.stream = _pop_stream
			sfx.position = panel_pos
			sfx.volume_db = -3.0
			lights.add_child(sfx)
			sfx.play()
			sfx.finished.connect(sfx.queue_free)
		var tw := create_tween()
		tw.tween_property(light, "light_energy", 1.7, 0.05)
		tw.tween_property(light, "light_energy", 0.0, 0.06)
		tw.tween_callback(func() -> void:
			panel.material_override = _unlit_panel_mat
		)
	)


# =========================================================================
# Block B: Dim Stairwell & Blue Threshold Sector (Img 3-4)
# Main Hall: x: -14.0 .. +14.0 (28m), z: -62.2 .. -37.2 (25m), height: 3.8
# Upper Dark Stair Corridor: y = 2.94, x: -18.0 .. -2.5, z: -66.0 .. -58.0
# Blue Winding Corridor: x: +2.0 .. +14.0, z: -72.0 .. -62.2
# =========================================================================
func _build_stair_threshold(body: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	var mat_wall := _make_mat(Color(0.68, 0.65, 0.56), Color(0.50, 0.48, 0.40), 0.90, 0.0, 1.0, 0.08)
	var mat_floor := _make_mat(Color(0.24, 0.22, 0.18), Color(0.15, 0.14, 0.11), 0.95, 0.0, 1.0, 0.09)
	var mat_wood := _make_mat(Color(0.42, 0.31, 0.19), Color(0.28, 0.20, 0.12), 0.80, 0.0, 1.0, 0.08)
	var mat_void := _make_mat(Color(0.04, 0.04, 0.05), Color(0.02, 0.02, 0.02), 0.98, 0.0, 1.0, 0.02)
	var mat_blue_wall := _make_mat(Color(0.22, 0.52, 0.72), Color(0.15, 0.36, 0.52), 0.78, 0.0, 1.0, 0.05)
	var mat_dim_door := _make_mat(Color(0.45, 0.46, 0.44), Color(0.3, 0.3, 0.3), 0.85, 0.0, 1.0, 0.05)

	# Floor & Ceiling
	_add_box(body, Vector3(28.0, 0.2, 25.0), Vector3(0.0, -0.1, -49.7), mat_floor, true)
	# Ceiling is split to leave a stairwell opening (x: -4.3 .. -1.3, z: -62.2 .. -58.0);
	# a single slab left only 0.86m of headroom at the top step.
	_add_box(body, Vector3(28.0, 0.2, 20.8), Vector3(0.0, 3.9, -47.6), mat_wall, true)
	_add_box(body, Vector3(9.7, 0.2, 4.2), Vector3(-9.15, 3.9, -60.1), mat_wall, true)
	_add_box(body, Vector3(15.3, 0.2, 4.2), Vector3(6.35, 3.9, -60.1), mat_wall, true)
	# Shaft walls + cap closing the opening up to the upper corridor ceiling (y = 5.94)
	_add_box(body, Vector3(0.2, 2.24, 4.2), Vector3(-4.4, 4.92, -60.1), mat_wall, true)
	_add_box(body, Vector3(0.2, 2.24, 4.2), Vector3(-1.2, 4.92, -60.1), mat_wall, true)
	_add_box(body, Vector3(3.4, 2.24, 0.2), Vector3(-2.8, 4.92, -57.9), mat_wall, true)
	_add_box(body, Vector3(3.4, 0.2, 4.4), Vector3(-2.8, 6.04, -60.0), mat_wall, true)

	# South wall (z = -37.2) connecting to glowing green doorway (x: -1.45 .. +1.45)
	_add_box(body, Vector3(12.55, 3.8, 0.3), Vector3(-7.725, 1.9, -37.2), mat_wall, true)
	_add_box(body, Vector3(12.55, 3.8, 0.3), Vector3(7.725, 1.9, -37.2), mat_wall, true)
	_add_box(body, Vector3(2.9, 1.3, 0.3), Vector3(0.0, 3.15, -37.2), mat_wall, true)

	# West & East walls + interior baffle walls to make Block B feel like a real multi-room sector
	_add_box(body, Vector3(0.3, 3.8, 25.0), Vector3(-14.0, 1.9, -49.7), mat_wall, true)
	_add_box(body, Vector3(0.3, 3.8, 25.0), Vector3(14.0, 1.9, -49.7), mat_wall, true)
	_add_box(body, Vector3(10.0, 3.8, 0.5), Vector3(-8.5, 1.9, -44.5), mat_wall, true)
	_add_box(body, Vector3(10.0, 3.8, 0.5), Vector3(8.5, 1.9, -44.5), mat_wall, true)
	_add_box(body, Vector3(0.5, 3.8, 8.0), Vector3(6.5, 1.9, -54.0), mat_wall, true)

	# Dim closed doors on West & East walls (Img 3)
	_add_box(body, Vector3(0.08, 2.35, 1.3), Vector3(-13.82, 1.18, -52.5), mat_dim_door, true)
	_add_box(body, Vector3(0.08, 2.35, 1.3), Vector3(13.82, 1.18, -50.0), mat_dim_door, true)

	# North wall (z = -62.2) with:
	# - Staircase opening at x: -4.2 .. -1.4, y: 0 .. 3.8
	# - Blue-lit doorway at x: +1.6 .. +4.4, y: 0 .. 2.8
	_add_box(body, Vector3(9.8, 3.8, 0.3), Vector3(-9.1, 1.9, -62.2), mat_wall, true)
	_add_box(body, Vector3(3.0, 3.8, 0.3), Vector3(0.1, 1.9, -62.2), mat_wall, true)
	_add_box(body, Vector3(9.6, 3.8, 0.3), Vector3(9.2, 1.9, -62.2), mat_wall, true)
	_add_box(body, Vector3(2.8, 1.0, 0.3), Vector3(3.0, 3.3, -62.2), mat_wall, true)

	# Wooden staircase climbing -Z into explorable dark upper wing (Img 3 & 4)
	var steps := 14
	var step_depth := 0.44
	var step_rise := 0.21
	var stair_start_z := -56.0
	for i in range(steps):
		var sy := (i + 0.5) * step_rise
		var sz := stair_start_z - (i + 0.5) * step_depth
		_add_box(body, Vector3(2.6, step_rise, step_depth), Vector3(-2.8, sy, sz), mat_wood, true)

	# Wooden handrail on left side of stairs (x = -4.0)
	_add_box(body, Vector3(0.12, 1.0, 0.12), Vector3(-4.0, 0.5, stair_start_z - 0.15), mat_wood, true)
	_add_box(body, Vector3(0.12, 1.0, 0.12), Vector3(-4.0, 1.8, stair_start_z - 3.1), mat_wood, true)
	_add_box(body, Vector3(0.12, 1.0, 0.12), Vector3(-4.0, 3.1, stair_start_z - 5.9), mat_wood, true)
	var rail := MeshInstance3D.new()
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(0.12, 0.12, 6.8)
	rail.mesh = rail_mesh
	rail.material_override = mat_wood
	rail.position = Vector3(-4.0, 2.38, stair_start_z - 3.05)
	rail.rotation.x = atan2(steps * step_rise, steps * step_depth)
	body.add_child(rail)

	# Upper Dark Explorable Corridor (y_floor = 2.94, x: -16.0 .. -1.4, z: -66.0 .. -62.2)
	var uy := steps * step_rise # 2.94
	_add_box(body, Vector3(14.6, 0.2, 3.8), Vector3(-8.7, uy - 0.1, -64.1), mat_void, true)
	_add_box(body, Vector3(14.6, 0.2, 3.8), Vector3(-8.7, uy + 3.0, -64.1), mat_void, true)
	_add_box(body, Vector3(14.6, 3.0, 0.3), Vector3(-8.7, uy + 1.5, -66.0), mat_void, true)
	_add_box(body, Vector3(11.8, 3.0, 0.3), Vector3(-10.1, uy + 1.5, -62.2), mat_void, true)
	_add_box(body, Vector3(0.3, 3.0, 3.8), Vector3(-1.4, uy + 1.5, -64.1), mat_void, true)
	_add_box(body, Vector3(0.3, 3.0, 3.8), Vector3(-16.0, uy + 1.5, -64.1), mat_void, true)

	var stair_note := _make_interactable(
		"UpperStairNote",
		Vector3(-15.5, uy + 0.9, -64.1),
		Vector3(0.3, 0.5, 0.5),
		"閱讀黑暗盡頭的紙條",
		"note",
		"Stair_Top_Memo",
		"【樓梯盡頭】\n\n"
		+ "這裡沒有任何出口，只有一片漆黑。\n"
		+ "樓下的藍色門口才是繼續往深處走的路。"
	)
	props.add_child(stair_note)
	var sp_mat := StandardMaterial3D.new()
	sp_mat.albedo_color = Color(0.85, 0.82, 0.68)
	_add_box(stair_note, Vector3(0.03, 0.32, 0.24), Vector3.ZERO, sp_mat, false)

	# Dim warm ceiling lights in Sub-zone B (Img 3)
	_add_omni(lights, Vector3(0.0, 3.3, -41.0), Color(0.95, 0.90, 0.72), 0.75, 13.0, false)
	_add_omni(lights, Vector3(-7.0, 3.3, -52.0), Color(0.95, 0.90, 0.72), 0.65, 12.0, false)
	_add_omni(lights, Vector3(1.5, 3.3, -55.0), Color(0.95, 0.90, 0.72), 0.70, 12.0, false)

	# Cool-blue winding maintenance corridor (x: +1.4 .. +12.0, z: -72.0 .. -62.2) (Img 4)
	_add_box(body, Vector3(10.6, 0.2, 9.8), Vector3(6.7, -0.1, -67.1), mat_blue_wall, true)
	_add_box(body, Vector3(10.6, 0.2, 9.8), Vector3(6.7, 2.9, -67.1), mat_blue_wall, true)
	_add_box(body, Vector3(0.3, 2.9, 9.8), Vector3(1.4, 1.45, -67.1), mat_blue_wall, true)
	_add_box(body, Vector3(0.3, 2.9, 9.8), Vector3(12.0, 1.45, -67.1), mat_blue_wall, true)
	# Internal blue baffle dividing vestibule -> side turn -> exit into White Hallway
	_add_box(body, Vector3(6.2, 2.9, 0.4), Vector3(4.5, 1.45, -67.1), mat_blue_wall, true)
	# Blue server/cabinet silhouettes (Img 4)
	_add_box(body, Vector3(0.75, 2.1, 1.4), Vector3(4.3, 1.05, -64.5), mat_blue_wall, true)
	_add_box(body, Vector3(1.2, 2.1, 0.8), Vector3(10.5, 1.05, -67.0), mat_blue_wall, true)
	_add_omni(lights, Vector3(3.0, 2.4, -64.5), Color(0.35, 0.78, 1.0), 2.1, 10.5, true)
	_add_omni(lights, Vector3(9.5, 2.4, -67.0), Color(0.35, 0.78, 1.0), 1.6, 10.0, false)
	_add_omni(lights, Vector3(3.5, 2.4, -70.0), Color(0.35, 0.78, 1.0), 1.5, 9.5, false)


# =========================================================================
# Block C: White Sterile Wing + Level 188 Courtyard (Img 5-7)
# Hallway: x: -1.5 .. +5.5 (7m), z: -116.0 .. -72.0 (44m), height: 3.8
# Courtyard: x: +5.5 .. +37.5 (32m), z: -116.0 .. -80.0 (36m), height: 14.0
# =========================================================================
func _build_white_hall_and_courtyard(body: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	var mat_white := _make_mat(Color(0.86, 0.88, 0.90), Color(0.72, 0.74, 0.76), 0.82, 0.0, 1.0, 0.04)
	var mat_hall_floor := _make_mat(Color(0.20, 0.19, 0.18), Color(0.14, 0.13, 0.12), 0.25, 0.0, 1.0, 0.03)
	var mat_wood_frame := _make_mat(Color(0.26, 0.17, 0.10), Color(0.18, 0.11, 0.06), 0.75, 0.0, 1.0, 0.05)
	var mat_strip := _make_emissive(Color(0.95, 0.97, 1.0), 2.3)
	var mat_win_dark := _make_mat(Color(0.05, 0.06, 0.07), Color(0.03, 0.03, 0.04), 0.20, 0.0, 1.0, 0.02)
	var mat_win_lit := _make_emissive(Color(0.95, 0.93, 0.82), 1.6)
	var mat_win_cool := _make_emissive(Color(0.76, 0.86, 0.96), 1.4)
	var mat_turf := _make_mat(Color(0.14, 0.26, 0.12), Color(0.09, 0.18, 0.08), 0.92, 0.0, 1.0, 0.09)
	var mat_walkway := _make_mat(Color(0.46, 0.47, 0.45), Color(0.32, 0.33, 0.31), 0.85, 0.0, 1.0, 0.06)
	var mat_chair := _make_mat(Color(0.22, 0.20, 0.15), Color(0.12, 0.11, 0.08), 0.70, 0.0, 1.0, 0.04)

	# --- White Sterile Hallway (x: -1.5 .. +5.5, z: -116.0 .. -72.0) ---
	_add_box(body, Vector3(7.0, 0.2, 44.0), Vector3(2.0, -0.1, -94.0), mat_hall_floor, true)
	_add_box(body, Vector3(7.0, 0.2, 44.0), Vector3(2.0, 3.9, -94.0), mat_white, true)

	# South wall (z = -72.0) connecting to Blue Corridor (x: +1.6 .. +4.4)
	_add_box(body, Vector3(3.1, 3.8, 0.3), Vector3(0.05, 1.9, -72.0), mat_white, true)
	_add_box(body, Vector3(1.1, 3.8, 0.3), Vector3(4.95, 1.9, -72.0), mat_white, true)
	_add_box(body, Vector3(2.8, 1.0, 0.3), Vector3(3.0, 3.3, -72.0), mat_white, true)

	# North wall (z = -116.0)
	_add_box(body, Vector3(7.0, 3.8, 0.3), Vector3(2.0, 1.9, -116.0), mat_white, true)

	# West wall (x = -1.5) with doorway to Dumpster Wing at z: -106.4 .. -103.6
	_add_box(body, Vector3(0.3, 3.8, 31.6), Vector3(-1.5, 1.9, -87.8), mat_white, true)
	_add_box(body, Vector3(0.3, 3.8, 9.6), Vector3(-1.5, 1.9, -111.2), mat_white, true)
	_add_box(body, Vector3(0.3, 1.1, 2.8), Vector3(-1.5, 3.25, -105.0), mat_white, true)
	_add_box(body, Vector3(0.36, 2.7, 0.15), Vector3(-1.5, 1.35, -103.55), mat_wood_frame, true)
	_add_box(body, Vector3(0.36, 2.7, 0.15), Vector3(-1.5, 1.35, -106.45), mat_wood_frame, true)
	_add_box(body, Vector3(0.36, 0.18, 3.05), Vector3(-1.5, 2.7, -105.0), mat_wood_frame, true)

	# East wall (x = +5.5) with:
	# 1) Observation Window at z: -89.2 .. -86.8, y: 1.0 .. 2.7 (Img 5 & 6)
	# 2) Open Doorway to Level 188 Courtyard at z: -106.4 .. -103.6, y: 0 .. 2.7
	_add_box(body, Vector3(0.3, 3.8, 14.8), Vector3(5.5, 1.9, -79.4), mat_white, true)
	_add_box(body, Vector3(0.3, 1.0, 2.4), Vector3(5.5, 0.5, -88.0), mat_white, true)
	_add_box(body, Vector3(0.3, 1.1, 2.4), Vector3(5.5, 3.25, -88.0), mat_white, true)
	_add_box(body, Vector3(0.3, 3.8, 14.4), Vector3(5.5, 1.9, -96.4), mat_white, true)
	_add_box(body, Vector3(0.3, 1.1, 2.8), Vector3(5.5, 3.25, -105.0), mat_white, true)
	_add_box(body, Vector3(0.3, 3.8, 9.6), Vector3(5.5, 1.9, -111.2), mat_white, true)
	# Dark square frame around observation window (Img 6)
	_add_box(body, Vector3(0.36, 0.12, 2.6), Vector3(5.5, 1.0, -88.0), mat_wood_frame, true)
	_add_box(body, Vector3(0.36, 0.12, 2.6), Vector3(5.5, 2.7, -88.0), mat_wood_frame, true)
	_add_box(body, Vector3(0.36, 1.8, 0.12), Vector3(5.5, 1.85, -86.75), mat_wood_frame, true)
	_add_box(body, Vector3(0.36, 1.8, 0.12), Vector3(5.5, 1.85, -89.25), mat_wood_frame, true)

	# Three dark wood-framed portals spanning hallway for repeating depth (Img 5)
	for pz in [-82.5, -93.5, -101.5]:
		_add_box(body, Vector3(1.2, 3.8, 0.45), Vector3(-0.9, 1.9, pz), mat_wood_frame, true)
		_add_box(body, Vector3(1.2, 3.8, 0.45), Vector3(4.9, 1.9, pz), mat_wood_frame, true)
		_add_box(body, Vector3(7.0, 0.9, 0.45), Vector3(2.0, 3.35, pz), mat_wood_frame, true)

	# Long rectangular ceiling light strips (Img 5)
	for lz in [-75.0, -78.5, -85.5, -89.0, -96.5, -104.5, -109.5, -113.0]:
		_add_box(body, Vector3(4.8, 0.05, 0.9), Vector3(2.0, 3.78, lz), mat_strip, false)
	for ly in [-76.5, -87.0, -97.5, -108.0]:
		_add_omni(lights, Vector3(2.0, 3.3, ly), Color(0.94, 0.96, 1.0), 1.35, 13.0, false)

	# Single Chair next to the observation window (Img 5 & 6)
	_build_simple_chair(body, Vector3(4.75, 0.0, -89.8), -0.35, mat_chair)
	var chair_note := _make_interactable(
		"CourtyardChairNote",
		Vector3(4.75, 0.56, -89.8),
		Vector3(0.28, 0.06, 0.24),
		"閱讀椅子上的紙條",
		"note",
		"Window_188_Memo",
		"【觀察紀錄：188 號窗庭】\n\n"
		+ "不知道是誰把這張椅子放在窗邊。\n"
		+ "對面牆上至少有一百扇一模一樣的小方窗，偶爾會有幾扇自己亮起來，但裡面什麼都沒有。\n\n"
		+ "沿著長廊繼續往前走，右轉可以直接走進中庭；左轉的木地板房間裡有垃圾箱，還連著一條沒開燈的長廊。"
	)
	props.add_child(chair_note)

	# --- Level 188 Window Courtyard (x: +5.5 .. +37.5, z: -116.0 .. -80.0, height: 14.0) ---
	_add_box(body, Vector3(32.0, 0.2, 36.0), Vector3(21.5, -0.1, -98.0), mat_walkway, true)
	# Geometric green turf patches (Img 7)
	_add_box(body, Vector3(9.5, 0.02, 10.5), Vector3(13.0, 0.005, -89.0), mat_turf, false)
	_add_box(body, Vector3(10.0, 0.02, 9.5), Vector3(28.0, 0.005, -90.0), mat_turf, false)
	_add_box(body, Vector3(10.5, 0.02, 10.5), Vector3(14.0, 0.005, -106.5), mat_turf, false)
	_add_box(body, Vector3(9.5, 0.02, 11.0), Vector3(28.5, 0.005, -107.0), mat_turf, false)

	# Courtyard ceiling (14.0m high) & 3 outer walls
	_add_box(body, Vector3(32.0, 0.2, 36.0), Vector3(21.5, 14.1, -98.0), mat_white, true)
	_add_box(body, Vector3(0.3, 14.0, 36.0), Vector3(37.5, 7.0, -98.0), mat_white, true) # East wall
	_add_box(body, Vector3(32.0, 14.0, 0.3), Vector3(21.5, 7.0, -80.0), mat_white, true) # South wall
	_add_box(body, Vector3(32.0, 14.0, 0.3), Vector3(21.5, 7.0, -116.0), mat_white, true) # North wall
	_add_box(body, Vector3(0.3, 10.2, 36.0), Vector3(5.5, 8.9, -98.0), mat_white, true) # Upper West wall

	# Window grids (6 rows x 8 cols on East, 7 cols on North/South)
	var lit_indices := {4: true, 12: true, 19: true, 27: true, 35: true, 44: true, 53: true, 62: true}
	var idx := 0
	for row in range(6):
		var wy := 1.4 + row * 2.15
		for col in range(8):
			var wz := -83.5 - col * 4.1
			var m: Material = mat_win_lit if lit_indices.has(idx) else mat_win_dark
			_add_window_tile(body, Vector3(37.33, wy, wz), Vector3(0.08, 1.35, 1.35), m, mat_wood_frame)
			idx += 1
		for col in range(7):
			var wx := 9.5 + col * 4.0
			var m_n: Material = mat_win_cool if (idx % 11 == 2) else mat_win_dark
			var m_s: Material = mat_win_lit if (idx % 13 == 4) else mat_win_dark
			_add_window_tile(body, Vector3(wx, wy, -115.83), Vector3(1.35, 1.35, 0.08), m_n, mat_wood_frame)
			_add_window_tile(body, Vector3(wx, wy, -80.17), Vector3(1.35, 1.35, 0.08), m_s, mat_wood_frame)
			idx += 1
	for row: int in [2, 3, 4, 5]:
		var wy: float = 1.4 + float(row) * 2.15
		for col in range(8):
			var wz: float = -83.5 - float(col) * 4.1
			_add_window_tile(body, Vector3(5.67, wy, wz), Vector3(0.08, 1.35, 1.35), mat_win_dark, mat_wood_frame)

	_add_omni(lights, Vector3(21.5, 11.5, -98.0), Color(0.86, 0.90, 0.95), 2.0, 36.0, false)
	_add_omni(lights, Vector3(21.5, 3.8, -90.0), Color(0.84, 0.88, 0.92), 0.85, 20.0, false)
	_add_omni(lights, Vector3(21.5, 3.8, -106.0), Color(0.84, 0.88, 0.92), 0.85, 20.0, false)


# =========================================================================
# Block D: Wood-Floor Service Wing & Dark Flashlight Corridor (Img 8)
# Main Room: x: -19.5 .. -1.5 (18m), z: -113.0 .. -97.0 (16m), height: 3.4
# Explorable Dark Corridor: x: -32.0 .. -19.5 -> south to z = -84.0
# =========================================================================
func _build_dumpster_alcove(body: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	var mat_white := _make_mat(Color(0.86, 0.87, 0.88), Color(0.72, 0.73, 0.74), 0.84, 0.0, 1.0, 0.04)
	var mat_wood_floor := _make_mat(Color(0.46, 0.28, 0.16), Color(0.32, 0.19, 0.10), 0.35, 0.25, 0.8, 0.06)
	var mat_wood_frame := _make_mat(Color(0.24, 0.15, 0.09), Color(0.16, 0.10, 0.05), 0.75, 0.0, 1.0, 0.05)
	var mat_void := _make_mat(Color(0.08, 0.08, 0.09), Color(0.04, 0.04, 0.05), 0.95, 0.0, 1.0, 0.04)
	var mat_dumpster := _make_mat(Color(0.22, 0.14, 0.12), Color(0.14, 0.09, 0.07), 0.78, 0.0, 1.0, 0.12)
	var mat_lid := _make_mat(Color(0.10, 0.10, 0.11), Color(0.06, 0.06, 0.07), 0.82, 0.0, 1.0, 0.08)
	var mat_rope := _make_mat(Color(0.55, 0.48, 0.28), Color(0.38, 0.32, 0.18), 0.92, 0.0, 1.0, 0.08)
	var mat_panel := _make_emissive(Color(0.96, 0.98, 1.0), 2.5)
	var mat_floppy := _make_mat(Color(0.12, 0.14, 0.22), Color(0.08, 0.08, 0.12), 0.55, 0.0, 1.0, 0.02)

	# Wood floor & white ceiling
	_add_box(body, Vector3(18.0, 0.2, 16.0), Vector3(-10.5, -0.1, -105.0), mat_wood_floor, true)
	_add_box(body, Vector3(18.0, 0.2, 16.0), Vector3(-10.5, 3.5, -105.0), mat_white, true)

	# South & North walls
	_add_box(body, Vector3(18.0, 3.4, 0.3), Vector3(-10.5, 1.7, -97.0), mat_white, true)
	_add_box(body, Vector3(18.0, 3.4, 0.3), Vector3(-10.5, 1.7, -113.0), mat_white, true)

	# West wall (x = -19.5) with dark opening at z: -110.5 .. -105.5 (Img 8 left)
	_add_box(body, Vector3(0.3, 3.4, 8.5), Vector3(-19.5, 1.7, -101.25), mat_white, true)
	_add_box(body, Vector3(0.3, 3.4, 2.5), Vector3(-19.5, 1.7, -111.75), mat_white, true)
	_add_box(body, Vector3(0.3, 0.7, 5.0), Vector3(-19.5, 3.05, -108.0), mat_white, true)
	_add_box(body, Vector3(0.35, 0.18, 5.2), Vector3(-19.5, 2.7, -108.0), mat_wood_frame, true)

	# Explorable Dark Flashlight Corridor:
	# Leg 1: x: -32.0 .. -19.5, z: -110.5 .. -105.5 (12.5m west)
	_add_box(body, Vector3(12.5, 0.2, 5.0), Vector3(-25.75, -0.1, -108.0), mat_void, true)
	_add_box(body, Vector3(12.5, 0.2, 5.0), Vector3(-25.75, 2.9, -108.0), mat_void, true)
	_add_box(body, Vector3(12.5, 2.9, 0.3), Vector3(-25.75, 1.45, -110.5), mat_void, true)
	_add_box(body, Vector3(8.0, 2.9, 0.3), Vector3(-23.5, 1.45, -105.5), mat_void, true)
	# Leg 2: x: -32.0 .. -27.5, z: -105.5 .. -86.0 (19.5m south, requires F flashlight!)
	_add_box(body, Vector3(4.5, 0.2, 24.5), Vector3(-29.75, -0.1, -98.25), mat_void, true)
	_add_box(body, Vector3(4.5, 0.2, 24.5), Vector3(-29.75, 2.9, -98.25), mat_void, true)
	_add_box(body, Vector3(0.3, 2.9, 24.5), Vector3(-32.0, 1.45, -98.25), mat_void, true)
	_add_box(body, Vector3(0.3, 2.9, 19.5), Vector3(-27.5, 1.45, -95.75), mat_void, true)
	_add_box(body, Vector3(4.5, 2.9, 0.3), Vector3(-29.75, 1.45, -86.0), mat_void, true)

	# Hidden crate + Floppy Disk (Memory 44) at the end of the dark corridor
	_add_box(body, Vector3(1.1, 0.85, 0.9), Vector3(-29.75, 0.425, -87.2), mat_wood_frame, true)
	var mem44 := _make_interactable(
		"Memory44Disk",
		Vector3(-29.75, 0.90, -87.2),
		Vector3(0.45, 0.3, 0.45),
		"讀取磁片 (Memory 44)",
		"computer",
		"Memory 44",
		"【磁片紀錄：Memory 44】\n"
		+ "日期：?/??/????  時間：??:??\n\n"
		+ "我打開手電筒一路走進垃圾箱房間左邊的暗廊，\n"
		+ "原本以為只是死路，結果在最裡面找到這張磁片。\n\n"
		+ "從黃色迷宮、灰白大廳、綠光房間到 188 號窗庭……\n"
		+ "這裡好像沒有盡頭，但至少每個轉角都還留著前人走過的痕跡。"
	)
	mem44.set("window_title", "Exploring - S??I")
	mem44.set("file_size", "1.44mb")
	props.add_child(mem44)
	_add_box(mem44, Vector3(0.24, 0.03, 0.24), Vector3.ZERO, mat_floppy, false)
	_add_omni(lights, Vector3(-29.75, 2.2, -87.5), Color(0.65, 0.85, 1.0), 0.35, 4.5, false)

	# Ceiling beam dividing alcove (Img 8)
	_add_box(body, Vector3(0.28, 0.38, 16.0), Vector3(-13.5, 3.22, -105.0), mat_wood_frame, false)

	# Bright ceiling light over the dumpster alcove (x = -9.5, z = -99.2)
	_add_box(body, Vector3(3.0, 0.05, 1.4), Vector3(-9.5, 3.38, -99.2), mat_panel, false)
	_add_omni(lights, Vector3(-9.5, 2.95, -99.2), Color(0.96, 0.96, 1.0), 1.65, 13.0, false)

	# Dumpster against South white wall (x = -9.5, z = -98.1)
	_add_box(body, Vector3(2.2, 1.1, 1.2), Vector3(-9.5, 0.65, -98.1), mat_dumpster, true)
	_add_box(body, Vector3(2.28, 0.16, 1.28), Vector3(-9.5, 1.24, -98.1), mat_lid, true)
	for wx in [-10.4, -8.6]:
		for wz in [-98.55, -97.65]:
			_add_box(body, Vector3(0.12, 0.12, 0.12), Vector3(wx, 0.06, wz), mat_lid, false)

	# Coiled rope on floor to the right of dumpster (Img 8)
	var rope := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.20
	torus.outer_radius = 0.38
	torus.rings = 12
	torus.ring_segments = 8
	rope.mesh = torus
	rope.material_override = mat_rope
	rope.position = Vector3(-6.2, 0.05, -98.4)
	rope.scale = Vector3(1.2, 0.45, 0.95)
	body.add_child(rope)

	var dumpster_note := _make_interactable(
		"DumpsterInspect",
		Vector3(-9.5, 0.85, -98.1),
		Vector3(2.3, 1.35, 1.3),
		"檢查垃圾箱",
		"note",
		"Dumpster_Note",
		"【金屬垃圾箱】\n\n"
		+ "蓋子被緊緊扣住，表面滿是刮痕和鐵鏽，旁邊地上還丟著一捆舊繩子。\n"
		+ "左邊那條沒開燈的暗廊好像很深……記得按 [ F ] 打開手電筒再進去看看。"
	)
	props.add_child(dumpster_note)


# =========================================================================
# Atmosphere Triggers
# =========================================================================
func _build_atmosphere_triggers() -> void:
	_add_trig("TrigGreenBackrooms", Vector3(0.0, 1.7, -18.2), Vector3(39.0, 3.4, 36.5),
		Color(0.28, 0.36, 0.14), 0.065, Color(0.45, 0.56, 0.24), -18.0)
	_add_trig("TrigStairThreshold", Vector3(0.0, 2.5, -51.0), Vector3(28.0, 6.0, 28.0),
		Color(0.18, 0.18, 0.15), 0.075, Color(0.32, 0.31, 0.26), -23.0)
	_add_trig("TrigWhiteCourtyard", Vector3(18.0, 6.5, -94.0), Vector3(40.0, 14.0, 46.0),
		Color(0.60, 0.63, 0.66), 0.025, Color(0.68, 0.71, 0.75), -27.0)
	_add_trig("TrigDumpsterRoom", Vector3(-16.0, 1.7, -101.0), Vector3(34.0, 3.4, 30.0),
		Color(0.42, 0.40, 0.38), 0.035, Color(0.58, 0.56, 0.54), -25.0)


func _add_trig(tname: String, pos: Vector3, size: Vector3, fog_col: Color, fog_dens: float, amb_col: Color, hum_db: float) -> void:
	var area := Area3D.new()
	area.name = tname
	area.position = pos
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	area.add_child(cs)
	area.body_entered.connect(func(b: Node3D) -> void:
		if b.is_in_group("player") or b.name == "Player":
			_active_zone = tname
			_fog_color_target = fog_col
			_fog_density_target = fog_dens
			_ambient_color_target = amb_col
			_hum_db_target = hum_db
	)
	area.body_exited.connect(func(b: Node3D) -> void:
		if (b.is_in_group("player") or b.name == "Player") and _active_zone == tname:
			_active_zone = ""
	)
	add_child(area)


# =========================================================================
# Geometry & Prop Helpers
# =========================================================================
func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, with_collision: bool) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.subdivide_width = clampi(int(size.x / 2.2), 0, 12)
	box.subdivide_height = clampi(int(size.y / 2.2), 0, 6)
	box.subdivide_depth = clampi(int(size.z / 2.2), 0, 12)
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)

	if with_collision:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.position = pos
		parent.add_child(cs)


func _add_window_tile(parent: Node3D, pos: Vector3, size: Vector3, glass_mat: Material, frame_mat: Material) -> void:
	_add_box(parent, size * 1.12, pos, frame_mat, false)
	var offset := Vector3.ZERO
	if size.x < 0.2:
		offset.x = -0.02 if pos.x > 21.5 else 0.02
	else:
		offset.z = 0.02 if pos.z < -98.0 else -0.02
	_add_box(parent, size, pos + offset, glass_mat, false)


func _build_simple_chair(parent: Node3D, pos: Vector3, rot_y: float, mat: Material) -> void:
	var chair := Node3D.new()
	chair.position = pos
	chair.rotation.y = rot_y
	parent.add_child(chair)
	_add_box(chair, Vector3(0.46, 0.05, 0.46), Vector3(0.0, 0.46, 0.0), mat, false)
	_add_box(chair, Vector3(0.46, 0.50, 0.05), Vector3(0.0, 0.72, 0.21), mat, false)
	for lx in [-0.19, 0.19]:
		for lz in [-0.19, 0.19]:
			_add_box(chair, Vector3(0.05, 0.46, 0.05), Vector3(lx, 0.23, lz), mat, false)


func _make_interactable(pname: String, pos: Vector3, size: Vector3, prompt: String, itype: String, fname: String, body_txt: String) -> StaticBody3D:
	var prop := StaticBody3D.new()
	prop.name = pname
	prop.position = pos
	prop.set_script(INTERACT_SCRIPT)
	prop.set("prompt_text", prompt)
	prop.set("interaction_type", itype)
	prop.set("window_title", "Exploring - Note")
	prop.set("file_name", fname)
	prop.set("file_size", "0.5kb")
	prop.set("body_text", body_txt)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	prop.add_child(cs)
	return prop


func _add_omni(parent: Node3D, pos: Vector3, color: Color, energy: float, range_val: float, cast_shadow: bool) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_val
	light.omni_attenuation = 1.4
	light.shadow_enabled = cast_shadow
	parent.add_child(light)
