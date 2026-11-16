@tool
extends Node3D

const SHADER_CONCRETE := preload("res://shaders/zone2_concrete.gdshader")
const INTERACT_SCRIPT := preload("res://scripts/interactable_prop.gd")

var _active_zone: String = ""
var _world_env: WorldEnvironment
var _ambient_hum: AudioStreamPlayer

var _fog_color_target := Color(0.28, 0.36, 0.14)
var _fog_density_target: float = 0.075
var _ambient_color_target := Color(0.45, 0.56, 0.25)
var _hum_db_target: float = -19.0


func _ready() -> void:
	if get_child_count() == 0:
		_build_zone3()
	if not Engine.is_editor_hint():
		_world_env = get_parent().get_node_or_null("WorldEnvironment")
		_ambient_hum = get_parent().get_node_or_null("AmbientHum")


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _active_zone == "":
		return
	var t := clampf(delta * 2.5, 0.0, 1.0)
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

	_build_green_backrooms(body, lights)
	_build_stair_threshold(body, lights)
	_build_white_hall_and_courtyard(body, lights, props)
	_build_dumpster_alcove(body, lights, props)
	_build_atmosphere_triggers()


# =========================================================================
# Sub-zone A: Green-Tinted Backrooms + Glowing Yellow-Green Doorway (Img 1-2)
# Local space: x: -7.0 .. +7.0, z: -14.0 .. 0.0, height: 3.2
# =========================================================================
func _build_green_backrooms(body: StaticBody3D, lights: Node3D) -> void:
	var mat_wall := _make_mat(Color(0.46, 0.52, 0.22), Color(0.32, 0.37, 0.14), 0.90, 0.0, 1.0, 0.09)
	var mat_ceil := _make_mat(Color(0.42, 0.48, 0.20), Color(0.24, 0.28, 0.10), 0.92, 0.65, 1.0, 0.06)
	var mat_floor := _make_mat(Color(0.22, 0.24, 0.11), Color(0.14, 0.16, 0.07), 0.95, 0.0, 1.0, 0.10)
	var mat_trim := _make_mat(Color(0.32, 0.36, 0.15), Color(0.2, 0.22, 0.08), 0.85, 0.0, 1.0, 0.05)
	var mat_glow_panel := _make_emissive(Color(0.85, 1.0, 0.55), 2.4)
	var mat_glow_door := _make_emissive(Color(0.88, 1.0, 0.18), 2.8)

	# Floor & Ceiling
	_add_box(body, Vector3(14.0, 0.2, 14.0), Vector3(0.0, -0.1, -7.0), mat_floor, true)
	_add_box(body, Vector3(14.0, 0.2, 14.0), Vector3(0.0, 3.3, -7.0), mat_ceil, true)

	# South wall (z = 0.0) with 2.8m doorway at x: -1.4 .. +1.4 connecting to Zone2Hall
	_add_box(body, Vector3(5.6, 3.2, 0.3), Vector3(-4.2, 1.6, 0.0), mat_wall, true)
	_add_box(body, Vector3(5.6, 3.2, 0.3), Vector3(4.2, 1.6, 0.0), mat_wall, true)
	_add_box(body, Vector3(2.8, 0.4, 0.3), Vector3(0.0, 3.0, 0.0), mat_wall, true)

	# West & East walls
	_add_box(body, Vector3(0.3, 3.2, 14.0), Vector3(-7.0, 1.6, -7.0), mat_wall, true)
	_add_box(body, Vector3(0.3, 3.2, 14.0), Vector3(7.0, 1.6, -7.0), mat_wall, true)

	# North wall (z = -14.0) with glowing doorway at x: -1.3 .. +1.3, y: 0 .. 2.5
	_add_box(body, Vector3(5.7, 3.2, 0.3), Vector3(-4.15, 1.6, -14.0), mat_wall, true)
	_add_box(body, Vector3(5.7, 3.2, 0.3), Vector3(4.15, 1.6, -14.0), mat_wall, true)
	_add_box(body, Vector3(2.6, 0.7, 0.3), Vector3(0.0, 2.85, -14.0), mat_wall, true)

	# Recessed wall pillars / bays (Img 1 & Img 2)
	for pz in [-3.5, -8.5, -12.0]:
		_add_box(body, Vector3(0.7, 3.2, 0.9), Vector3(-6.5, 1.6, pz), mat_wall, true)
		_add_box(body, Vector3(0.7, 3.2, 0.9), Vector3(6.5, 1.6, pz), mat_wall, true)
	# Overhead soffit / baseboard trim around North glowing doorway
	_add_box(body, Vector3(7.0, 0.35, 0.4), Vector3(0.0, 3.02, -13.75), mat_trim, false)
	_add_box(body, Vector3(14.0, 0.14, 0.08), Vector3(0.0, 0.07, -13.82), mat_trim, false)

	# Square ceiling light panels (Img 1)
	for lx in [-3.2, 3.2]:
		for lz in [-4.0, -10.0]:
			_add_box(body, Vector3(1.1, 0.05, 1.1), Vector3(lx, 3.18, lz), mat_glow_panel, false)
			_add_omni(lights, Vector3(lx, 2.75, lz), Color(0.76, 0.95, 0.38), 1.15, 9.5, false)

	# Glowing yellow-green doorway vestibule (z: -14.0 .. -15.2)
	_add_box(body, Vector3(0.12, 2.5, 1.2), Vector3(-1.3, 1.25, -14.6), mat_glow_door, true)
	_add_box(body, Vector3(0.12, 2.5, 1.2), Vector3(1.3, 1.25, -14.6), mat_glow_door, true)
	_add_box(body, Vector3(2.6, 0.12, 1.2), Vector3(0.0, 2.5, -14.6), mat_glow_door, true)
	_add_box(body, Vector3(2.8, 0.2, 1.4), Vector3(0.0, -0.1, -14.6), mat_floor, true)

	# Key shadow-casting light in the glowing doorway (casts dramatic beam like Img 2)
	_add_omni(lights, Vector3(0.0, 1.6, -14.3), Color(0.88, 1.0, 0.18), 2.5, 11.0, true)
	# Subtle green light leaking into Zone 2 North doorway
	_add_omni(lights, Vector3(0.0, 2.3, -0.6), Color(0.70, 0.92, 0.30), 0.9, 6.5, false)


# =========================================================================
# Sub-zone B: Dim Staircase & Blue-Lit Threshold (Img 3-4)
# Local space: x: -6.5 .. +6.5, z: -24.0 .. -15.2, height: 3.6
# =========================================================================
func _build_stair_threshold(body: StaticBody3D, lights: Node3D) -> void:
	var mat_wall := _make_mat(Color(0.68, 0.65, 0.56), Color(0.50, 0.48, 0.40), 0.90, 0.0, 1.0, 0.08)
	var mat_floor := _make_mat(Color(0.24, 0.22, 0.18), Color(0.15, 0.14, 0.11), 0.95, 0.0, 1.0, 0.09)
	var mat_wood := _make_mat(Color(0.42, 0.31, 0.19), Color(0.28, 0.20, 0.12), 0.80, 0.0, 1.0, 0.08)
	var mat_void := _make_mat(Color(0.03, 0.03, 0.04), Color(0.02, 0.02, 0.02), 0.98, 0.0, 1.0, 0.02)
	var mat_blue_wall := _make_mat(Color(0.22, 0.52, 0.72), Color(0.15, 0.36, 0.52), 0.78, 0.0, 1.0, 0.05)
	var mat_dim_door := _make_mat(Color(0.45, 0.46, 0.44), Color(0.3, 0.3, 0.3), 0.85, 0.0, 1.0, 0.05)

	# Floor & Ceiling
	_add_box(body, Vector3(13.0, 0.2, 8.8), Vector3(0.0, -0.1, -19.6), mat_floor, true)
	_add_box(body, Vector3(13.0, 0.2, 8.8), Vector3(0.0, 3.7, -19.6), mat_wall, true)

	# South wall (z = -15.2) connecting to glowing green doorway (x: -1.3 .. +1.3)
	_add_box(body, Vector3(5.2, 3.6, 0.3), Vector3(-3.9, 1.8, -15.2), mat_wall, true)
	_add_box(body, Vector3(5.2, 3.6, 0.3), Vector3(3.9, 1.8, -15.2), mat_wall, true)
	_add_box(body, Vector3(2.6, 1.1, 0.3), Vector3(0.0, 3.05, -15.2), mat_wall, true)

	# West & East walls
	_add_box(body, Vector3(0.3, 3.6, 8.8), Vector3(-6.5, 1.8, -19.6), mat_wall, true)
	_add_box(body, Vector3(0.3, 3.6, 8.8), Vector3(6.5, 1.8, -19.6), mat_wall, true)

	# Dim closed door on West wall (Img 3)
	_add_box(body, Vector3(0.08, 2.25, 1.25), Vector3(-6.32, 1.12, -21.5), mat_dim_door, true)

	# North wall (z = -24.0) with:
	# - Staircase opening at x: -3.2 .. -0.8, y: 0 .. 3.6
	# - Blue-lit doorway at x: +1.4 .. +4.0, y: 0 .. 2.7
	_add_box(body, Vector3(3.3, 3.6, 0.3), Vector3(-4.85, 1.8, -24.0), mat_wall, true)
	_add_box(body, Vector3(2.2, 3.6, 0.3), Vector3(0.3, 1.8, -24.0), mat_wall, true)
	_add_box(body, Vector3(2.5, 3.6, 0.3), Vector3(5.25, 1.8, -24.0), mat_wall, true)
	_add_box(body, Vector3(2.6, 0.9, 0.3), Vector3(2.7, 3.15, -24.0), mat_wall, true)

	# Wooden staircase climbing -Z into dark upper void (Img 3 & 4)
	var steps := 10
	var step_depth := 0.42
	var step_rise := 0.22
	var stair_start_z := -19.8
	for i in range(steps):
		var sy := (i + 0.5) * step_rise
		var sz := stair_start_z - (i + 0.5) * step_depth
		_add_box(body, Vector3(2.2, step_rise, step_depth), Vector3(-2.0, sy, sz), mat_wood, true)
	# Upper dark stairwell landing & pitch-black void box
	_add_box(body, Vector3(2.4, 0.2, 3.5), Vector3(-2.0, steps * step_rise - 0.1, -25.75), mat_void, true)
	_add_box(body, Vector3(0.3, 4.2, 3.5), Vector3(-3.35, 2.1, -25.75), mat_void, true)
	_add_box(body, Vector3(0.3, 4.2, 3.5), Vector3(-0.65, 2.1, -25.75), mat_void, true)
	_add_box(body, Vector3(2.7, 0.2, 3.5), Vector3(-2.0, 4.2, -25.75), mat_void, true)
	_add_box(body, Vector3(2.7, 4.2, 0.3), Vector3(-2.0, 2.1, -27.5), mat_void, true)

	# Wooden handrail on left side of stairs (x = -3.05)
	_add_box(body, Vector3(0.12, 1.0, 0.12), Vector3(-3.05, 0.5, stair_start_z - 0.15), mat_wood, true)
	_add_box(body, Vector3(0.12, 1.0, 0.12), Vector3(-3.05, 1.5, stair_start_z - 2.2), mat_wood, true)
	_add_box(body, Vector3(0.12, 1.0, 0.12), Vector3(-3.05, 2.5, stair_start_z - 4.0), mat_wood, true)
	var rail := MeshInstance3D.new()
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(0.12, 0.12, 4.7)
	rail.mesh = rail_mesh
	rail.material_override = mat_wood
	rail.position = Vector3(-3.05, 1.98, stair_start_z - 2.1)
	rail.rotation.x = atan2(steps * step_rise, steps * step_depth)
	body.add_child(rail)

	# Dim warm ceiling light in center of Sub-zone B (Img 3)
	_add_omni(lights, Vector3(-1.5, 3.2, -18.8), Color(0.95, 0.90, 0.72), 0.65, 9.0, false)

	# Cool-blue lit vestibule (x: +1.0 .. +4.4, z: -24.0 .. -27.5) leading to White Hallway (Img 4)
	_add_box(body, Vector3(3.4, 0.2, 3.5), Vector3(2.7, -0.1, -25.75), mat_blue_wall, true)
	_add_box(body, Vector3(3.4, 0.2, 3.5), Vector3(2.7, 2.8, -25.75), mat_blue_wall, true)
	_add_box(body, Vector3(0.3, 2.8, 3.5), Vector3(1.15, 1.4, -25.75), mat_blue_wall, true)
	_add_box(body, Vector3(0.3, 2.8, 3.5), Vector3(4.25, 1.4, -25.75), mat_blue_wall, true)
	# Blue cabinet silhouette inside right side of vestibule (Img 4)
	_add_box(body, Vector3(0.65, 2.0, 1.1), Vector3(3.75, 1.0, -25.7), mat_blue_wall, true)
	_add_omni(lights, Vector3(2.7, 2.3, -25.6), Color(0.35, 0.78, 1.0), 1.9, 8.5, true)


# =========================================================================
# Sub-zone C: White Sterile Hallway + Chair & Window + Level 188 Courtyard (Img 5-7)
# Hallway: x: -1.0 .. +5.0, z: -47.5 .. -27.5, height: 3.6
# Courtyard: x: +5.0 .. +23.0, z: -46.0 .. -26.0, height: 9.6
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

	# --- White Sterile Hallway (x: -1.0 .. +5.0, z: -47.5 .. -27.5) ---
	_add_box(body, Vector3(6.0, 0.2, 20.0), Vector3(2.0, -0.1, -37.5), mat_hall_floor, true)
	_add_box(body, Vector3(6.0, 0.2, 20.0), Vector3(2.0, 3.7, -37.5), mat_white, true)

	# South wall (z = -27.5) connecting to Blue Vestibule (x: +1.4 .. +4.0)
	_add_box(body, Vector3(2.4, 3.6, 0.3), Vector3(0.2, 1.8, -27.5), mat_white, true)
	_add_box(body, Vector3(1.0, 3.6, 0.3), Vector3(4.5, 1.8, -27.5), mat_white, true)
	_add_box(body, Vector3(2.6, 0.9, 0.3), Vector3(2.7, 3.15, -27.5), mat_white, true)

	# North wall (z = -47.5)
	_add_box(body, Vector3(6.0, 3.6, 0.3), Vector3(2.0, 1.8, -47.5), mat_white, true)

	# West wall (x = -1.0) with doorway to Dumpster Alcove at z: -44.4 .. -41.6
	_add_box(body, Vector3(0.3, 3.6, 14.1), Vector3(-1.0, 1.8, -34.55), mat_white, true)
	_add_box(body, Vector3(0.3, 3.6, 3.1), Vector3(-1.0, 1.8, -45.95), mat_white, true)
	_add_box(body, Vector3(0.3, 0.9, 2.8), Vector3(-1.0, 3.15, -43.0), mat_white, true)
	# Dark brown wood frame around Dumpster Alcove doorway
	_add_box(body, Vector3(0.36, 2.7, 0.15), Vector3(-1.0, 1.35, -41.55), mat_wood_frame, true)
	_add_box(body, Vector3(0.36, 2.7, 0.15), Vector3(-1.0, 1.35, -44.45), mat_wood_frame, true)
	_add_box(body, Vector3(0.36, 0.18, 3.05), Vector3(-1.0, 2.7, -43.0), mat_wood_frame, true)

	# East wall (x = +5.0) with:
	# 1) Observation Window at z: -35.1 .. -32.9, y: 1.0 .. 2.7 (Img 5 & 6)
	# 2) Open Doorway to Level 188 Courtyard at z: -44.4 .. -41.6, y: 0 .. 2.7
	_add_box(body, Vector3(0.3, 3.6, 5.4), Vector3(5.0, 1.8, -30.2), mat_white, true)
	_add_box(body, Vector3(0.3, 1.0, 2.2), Vector3(5.0, 0.5, -34.0), mat_white, true) # below window
	_add_box(body, Vector3(0.3, 0.9, 2.2), Vector3(5.0, 3.15, -34.0), mat_white, true) # above window
	_add_box(body, Vector3(0.3, 3.6, 6.5), Vector3(5.0, 1.8, -38.35), mat_white, true)
	_add_box(body, Vector3(0.3, 0.9, 2.8), Vector3(5.0, 3.15, -43.0), mat_white, true) # above courtyard door
	_add_box(body, Vector3(0.3, 3.6, 3.1), Vector3(5.0, 1.8, -45.95), mat_white, true)
	# Dark square frame around observation window (Img 6)
	_add_box(body, Vector3(0.36, 0.12, 2.4), Vector3(5.0, 1.0, -34.0), mat_wood_frame, true)
	_add_box(body, Vector3(0.36, 0.12, 2.4), Vector3(5.0, 2.7, -34.0), mat_wood_frame, true)
	_add_box(body, Vector3(0.36, 1.8, 0.12), Vector3(5.0, 1.85, -32.85), mat_wood_frame, true)
	_add_box(body, Vector3(0.36, 1.8, 0.12), Vector3(5.0, 1.85, -35.15), mat_wood_frame, true)

	# Dark wood-framed portal spanning hallway at z = -37.5 (Img 5)
	_add_box(body, Vector3(1.1, 3.6, 0.45), Vector3(-0.3, 1.8, -37.5), mat_wood_frame, true)
	_add_box(body, Vector3(1.1, 3.6, 0.45), Vector3(4.3, 1.8, -37.5), mat_wood_frame, true)
	_add_box(body, Vector3(6.0, 0.85, 0.45), Vector3(2.0, 3.18, -37.5), mat_wood_frame, true)

	# Long rectangular ceiling light strips (Img 5)
	for lz in [-30.0, -33.0, -36.0, -40.5, -44.0]:
		_add_box(body, Vector3(4.2, 0.05, 0.85), Vector3(2.0, 3.58, lz), mat_strip, false)
	_add_omni(lights, Vector3(2.0, 3.2, -31.5), Color(0.94, 0.96, 1.0), 1.35, 11.0, false)
	_add_omni(lights, Vector3(2.0, 3.2, -36.0), Color(0.94, 0.96, 1.0), 1.25, 10.5, false)
	_add_omni(lights, Vector3(2.0, 3.2, -43.0), Color(0.94, 0.96, 1.0), 1.25, 10.5, false)

	# Single Chair next to the observation window (Img 5 & 6)
	_build_simple_chair(body, Vector3(4.3, 0.0, -35.6), -0.35, mat_chair)
	var chair_note := _make_interactable(
		"CourtyardChairNote",
		Vector3(4.3, 0.56, -35.6),
		Vector3(0.28, 0.06, 0.24),
		"閱讀椅子上的紙條",
		"note",
		"Window_188_Memo",
		"【觀察紀錄：188 號窗庭】\n\n"
		+ "不知道是誰把這張椅子放在窗邊。\n"
		+ "對面牆上至少有一百扇一模一樣的小方窗，偶爾會有幾扇自己亮起來，但裡面什麼都沒有。\n\n"
		+ "往前走右轉可以直接走進中庭；左轉的木地板房間裡有個生鏽的垃圾箱。"
	)
	props.add_child(chair_note)

	# --- Level 188 Window Courtyard (x: +5.0 .. +23.0, z: -46.0 .. -26.0, height: 9.6) ---
	# Geometric green/grey patterned floor (Img 7)
	_add_box(body, Vector3(18.0, 0.2, 20.0), Vector3(14.0, -0.1, -36.0), mat_walkway, true)
	# Turf patches laid cleanly just above floor (-0.09..0.005)
	_add_box(body, Vector3(5.2, 0.02, 6.0), Vector3(9.5, 0.005, -31.0), mat_turf, false)
	_add_box(body, Vector3(5.6, 0.02, 5.2), Vector3(17.5, 0.005, -32.0), mat_turf, false)
	_add_box(body, Vector3(6.0, 0.02, 5.8), Vector3(10.5, 0.005, -40.5), mat_turf, false)
	_add_box(body, Vector3(5.0, 0.02, 6.2), Vector3(18.0, 0.005, -40.8), mat_turf, false)

	# Courtyard ceiling (9.6m high) & 3 outer walls
	_add_box(body, Vector3(18.0, 0.2, 20.0), Vector3(14.0, 9.7, -36.0), mat_white, true)
	_add_box(body, Vector3(0.3, 9.6, 20.0), Vector3(23.0, 4.8, -36.0), mat_white, true) # East wall
	_add_box(body, Vector3(18.0, 9.6, 0.3), Vector3(14.0, 4.8, -26.0), mat_white, true) # South wall
	_add_box(body, Vector3(18.0, 9.6, 0.3), Vector3(14.0, 4.8, -46.0), mat_white, true) # North wall
	# Upper West wall above the 3.6m hallway (y: 3.6 .. 9.6)
	_add_box(body, Vector3(0.3, 6.0, 20.0), Vector3(5.0, 6.6, -36.0), mat_white, true)

	# Window grids on East, South, North walls (Img 6 & 7)
	var lit_indices := {3: true, 7: true, 10: true, 14: true, 18: true}
	var idx := 0
	for row in range(4):
		var wy := 1.4 + row * 2.1
		# East wall (facing -X)
		for col in range(5):
			var wz := -29.0 - col * 3.5
			var m: Material = mat_win_lit if lit_indices.has(idx) else mat_win_dark
			_add_window_tile(body, Vector3(22.83, wy, wz), Vector3(0.08, 1.25, 1.25), m, mat_wood_frame)
			idx += 1
		# North & South walls (facing +Z / -Z)
		for col in range(4):
			var wx := 8.0 + col * 3.8
			var m_n: Material = mat_win_cool if (idx % 9 == 2) else mat_win_dark
			var m_s: Material = mat_win_lit if (idx % 11 == 4) else mat_win_dark
			_add_window_tile(body, Vector3(wx, wy, -45.83), Vector3(1.25, 1.25, 0.08), m_n, mat_wood_frame)
			_add_window_tile(body, Vector3(wx, wy, -26.17), Vector3(1.25, 1.25, 0.08), m_s, mat_wood_frame)
			idx += 1
	# Upper West wall windows (rows 2 & 3 above hallway)
	for row: int in [2, 3]:
		var wy: float = 1.4 + float(row) * 2.1
		for col in range(5):
			var wz: float = -29.0 - float(col) * 3.5
			_add_window_tile(body, Vector3(5.17, wy, wz), Vector3(0.08, 1.25, 1.25), mat_win_dark, mat_wood_frame)

	_add_omni(lights, Vector3(14.0, 7.8, -36.0), Color(0.86, 0.90, 0.95), 1.65, 22.0, false)
	_add_omni(lights, Vector3(14.0, 3.0, -34.0), Color(0.84, 0.88, 0.92), 0.75, 14.0, false)


# =========================================================================
# Sub-zone D: Wood-Floor Dumpster Alcove (Img 8)
# Local space: x: -11.0 .. -1.0, z: -48.0 .. -38.0, height: 3.2
# =========================================================================
func _build_dumpster_alcove(body: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	var mat_white := _make_mat(Color(0.86, 0.87, 0.88), Color(0.72, 0.73, 0.74), 0.84, 0.0, 1.0, 0.04)
	var mat_wood_floor := _make_mat(Color(0.46, 0.28, 0.16), Color(0.32, 0.19, 0.10), 0.35, 0.25, 0.8, 0.06)
	var mat_wood_frame := _make_mat(Color(0.24, 0.15, 0.09), Color(0.16, 0.10, 0.05), 0.75, 0.0, 1.0, 0.05)
	var mat_void := _make_mat(Color(0.03, 0.03, 0.03), Color(0.02, 0.02, 0.02), 0.98, 0.0, 1.0, 0.02)
	var mat_dumpster := _make_mat(Color(0.22, 0.14, 0.12), Color(0.14, 0.09, 0.07), 0.78, 0.0, 1.0, 0.12)
	var mat_lid := _make_mat(Color(0.10, 0.10, 0.11), Color(0.06, 0.06, 0.07), 0.82, 0.0, 1.0, 0.08)
	var mat_rope := _make_mat(Color(0.55, 0.48, 0.28), Color(0.38, 0.32, 0.18), 0.92, 0.0, 1.0, 0.08)
	var mat_panel := _make_emissive(Color(0.96, 0.98, 1.0), 2.5)

	# Wood floor & white ceiling
	_add_box(body, Vector3(10.0, 0.2, 10.0), Vector3(-6.0, -0.1, -43.0), mat_wood_floor, true)
	_add_box(body, Vector3(10.0, 0.2, 10.0), Vector3(-6.0, 3.3, -43.0), mat_white, true)

	# South & North walls
	_add_box(body, Vector3(10.0, 3.2, 0.3), Vector3(-6.0, 1.6, -38.0), mat_white, true)
	_add_box(body, Vector3(10.0, 3.2, 0.3), Vector3(-6.0, 1.6, -48.0), mat_white, true)

	# West wall (x = -11.0) with dark void opening at z: -46.2 .. -42.2 (Img 8 left)
	_add_box(body, Vector3(0.3, 3.2, 4.2), Vector3(-11.0, 1.6, -40.1), mat_white, true)
	_add_box(body, Vector3(0.3, 3.2, 1.8), Vector3(-11.0, 1.6, -47.1), mat_white, true)
	_add_box(body, Vector3(0.3, 0.6, 4.0), Vector3(-11.0, 2.9, -44.2), mat_white, true)
	_add_box(body, Vector3(0.35, 0.18, 4.2), Vector3(-11.0, 2.6, -44.2), mat_wood_frame, true)
	# Pitch-dark stub corridor behind the opening
	_add_box(body, Vector3(3.6, 0.2, 4.2), Vector3(-12.9, -0.1, -44.2), mat_void, true)
	_add_box(body, Vector3(3.6, 0.2, 4.2), Vector3(-12.9, 2.7, -44.2), mat_void, true)
	_add_box(body, Vector3(3.6, 2.8, 0.3), Vector3(-12.9, 1.35, -42.1), mat_void, true)
	_add_box(body, Vector3(3.6, 2.8, 0.3), Vector3(-12.9, 1.35, -46.3), mat_void, true)
	_add_box(body, Vector3(0.3, 2.8, 4.2), Vector3(-14.7, 1.35, -44.2), mat_void, true)

	# Ceiling beam dividing alcove (Img 8)
	_add_box(body, Vector3(0.25, 0.35, 10.0), Vector3(-7.6, 3.05, -43.0), mat_wood_frame, false)

	# Bright ceiling light over the dumpster alcove (x = -5.5, z = -39.5)
	_add_box(body, Vector3(2.4, 0.05, 1.2), Vector3(-5.8, 3.18, -39.8), mat_panel, false)
	_add_omni(lights, Vector3(-5.8, 2.8, -39.8), Color(0.96, 0.96, 1.0), 1.5, 9.5, false)

	# Dumpster against South white wall (x = -6.0, z = -39.0)
	_add_box(body, Vector3(2.1, 1.05, 1.15), Vector3(-6.0, 0.62, -39.0), mat_dumpster, true)
	_add_box(body, Vector3(2.18, 0.16, 1.22), Vector3(-6.0, 1.20, -39.0), mat_lid, true)
	for wx in [-6.85, -5.15]:
		for wz in [-39.45, -38.55]:
			_add_box(body, Vector3(0.12, 0.12, 0.12), Vector3(wx, 0.06, wz), mat_lid, false)

	# Coiled rope on floor to the right of dumpster (Img 8)
	var rope := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.18
	torus.outer_radius = 0.34
	torus.rings = 12
	torus.ring_segments = 8
	rope.mesh = torus
	rope.material_override = mat_rope
	rope.position = Vector3(-3.6, 0.05, -39.3)
	rope.scale = Vector3(1.2, 0.45, 0.95)
	body.add_child(rope)

	var dumpster_note := _make_interactable(
		"DumpsterInspect",
		Vector3(-6.0, 0.85, -39.0),
		Vector3(2.2, 1.3, 1.25),
		"檢查垃圾箱",
		"note",
		"Dumpster_Note",
		"【金屬垃圾箱】\n\n"
		+ "蓋子被緊緊扣住，表面滿是刮痕和鐵鏽，旁邊地上還丟著一捆舊繩子。\n"
		+ "明明在封閉的室內走廊裡，卻不知道為什麼會有大型戶外垃圾箱……\n\n"
		+ "左邊那扇沒有門的暗廊深處，傳來非常微弱的電流嗡嗡聲。"
	)
	props.add_child(dumpster_note)


# =========================================================================
# Atmosphere Triggers
# =========================================================================
func _build_atmosphere_triggers() -> void:
	_add_trig("TrigGreenBackrooms", Vector3(0.0, 1.6, -7.2), Vector3(14.0, 3.2, 14.5),
		Color(0.28, 0.36, 0.14), 0.080, Color(0.45, 0.56, 0.24), -18.0)
	_add_trig("TrigStairThreshold", Vector3(0.0, 1.8, -19.6), Vector3(13.0, 3.6, 9.0),
		Color(0.18, 0.18, 0.15), 0.095, Color(0.32, 0.31, 0.26), -23.0)
	_add_trig("TrigWhiteCourtyard", Vector3(10.0, 4.5, -37.5), Vector3(26.0, 9.5, 22.0),
		Color(0.60, 0.63, 0.66), 0.035, Color(0.68, 0.71, 0.75), -27.0)
	_add_trig("TrigDumpsterRoom", Vector3(-6.0, 1.6, -43.0), Vector3(10.0, 3.2, 10.0),
		Color(0.42, 0.40, 0.38), 0.045, Color(0.58, 0.56, 0.54), -25.0)


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
		offset.x = -0.02 if pos.x > 14.0 else 0.02
	else:
		offset.z = 0.02 if pos.z < -36.0 else -0.02
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
