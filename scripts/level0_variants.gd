@tool
extends Node3D

const WALL_H: float = 3.0
const MAT_WALLPAPER := preload("res://materials/mat_wallpaper.tres")
const MAT_CARPET := preload("res://materials/mat_carpet.tres")
const MAT_CEILING := preload("res://materials/mat_ceiling.tres")
const MAT_FLUORESCENT := preload("res://materials/mat_fluorescent.tres")
const MAT_WET_FLOOR := preload("res://materials/mat_wet_floor.tres")
const MAT_VENT_GRILL := preload("res://materials/mat_vent_grill.tres")
const INTERACT_SCRIPT := preload("res://scripts/interactable_prop.gd")

const LEVEL0_FOG_COLOR := Color(0.50, 0.47, 0.27)
const LEVEL0_FOG_DENSITY := 0.085
const LEVEL0_AMBIENT_COLOR := Color(0.65, 0.60, 0.38)
const LEVEL0_AMBIENT_ENERGY := 0.38
const LEVEL0_HUM_DB := -15.5

var _active_zone: String = ""
var _world_env: WorldEnvironment
var _ambient_hum: AudioStreamPlayer
var _player: CharacterBody3D
var _red_loop_count: int = 0
var _pit_cooldown: float = 0.0
var _shifting_blocks: Array[Dictionary] = []
var _flicker_wall_mat: StandardMaterial3D
var _flicker_time: float = 0.0

var _mat_pale_wall: StandardMaterial3D
var _mat_thick_carpet: StandardMaterial3D
var _mat_unlit_panel: StandardMaterial3D
var _mat_pit_black: StandardMaterial3D
var _mat_red_wall: StandardMaterial3D
var _mat_red_carpet: StandardMaterial3D
var _mat_peel_red: StandardMaterial3D
var _mat_white_light: StandardMaterial3D
var _mat_trash_red: StandardMaterial3D
var _mat_bucket_grey: StandardMaterial3D


func _ready() -> void:
	_init_materials()
	if get_child_count() == 0:
		_build_variants()
	if not Engine.is_editor_hint():
		_world_env = get_parent().get_node_or_null("WorldEnvironment")
		_ambient_hum = get_parent().get_node_or_null("AmbientHum")
		_player = get_parent().get_node_or_null("Player")


func _init_materials() -> void:
	_mat_pale_wall = StandardMaterial3D.new()
	_mat_pale_wall.albedo_color = Color(0.84, 0.82, 0.74)
	_mat_pale_wall.roughness = 0.85

	_mat_thick_carpet = StandardMaterial3D.new()
	_mat_thick_carpet.albedo_color = Color(0.56, 0.49, 0.34)
	_mat_thick_carpet.roughness = 0.96

	_mat_unlit_panel = StandardMaterial3D.new()
	_mat_unlit_panel.albedo_color = Color(0.14, 0.14, 0.13)
	_mat_unlit_panel.roughness = 0.75

	_mat_pit_black = StandardMaterial3D.new()
	_mat_pit_black.albedo_color = Color(0.01, 0.01, 0.01)
	_mat_pit_black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_mat_red_wall = StandardMaterial3D.new()
	_mat_red_wall.albedo_color = Color(0.58, 0.09, 0.07)
	_mat_red_wall.roughness = 0.88

	_mat_red_carpet = StandardMaterial3D.new()
	_mat_red_carpet.albedo_color = Color(0.42, 0.06, 0.05)
	_mat_red_carpet.roughness = 0.98

	_mat_peel_red = StandardMaterial3D.new()
	_mat_peel_red.albedo_color = Color(0.46, 0.05, 0.05)
	_mat_peel_red.roughness = 0.92

	_mat_white_light = StandardMaterial3D.new()
	_mat_white_light.albedo_color = Color(1.0, 0.95, 0.95)
	_mat_white_light.emission_enabled = true
	_mat_white_light.emission = Color(1.0, 0.90, 0.88)
	_mat_white_light.emission_energy_multiplier = 2.6

	_mat_trash_red = StandardMaterial3D.new()
	_mat_trash_red.albedo_color = Color(0.38, 0.08, 0.08)
	_mat_trash_red.roughness = 0.65

	_mat_bucket_grey = StandardMaterial3D.new()
	_mat_bucket_grey.albedo_color = Color(0.48, 0.48, 0.46)
	_mat_bucket_grey.roughness = 0.6


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _player:
		return

	if _pit_cooldown > 0.0:
		_pit_cooldown -= delta

	# Flickering exit wall pulse
	_flicker_time += delta
	if _flicker_wall_mat:
		var pulse := 0.5 + 0.5 * sin(_flicker_time * 13.0) * sin(_flicker_time * 29.0)
		_flicker_wall_mat.emission_energy_multiplier = 0.35 + pulse * 1.4

	# Edge Displacement: shift Pillar Hall blocks when player looks away & is far enough
	var cam_fwd := -_player.global_transform.basis.z
	for blk in _shifting_blocks:
		blk["cd"] = maxf(0.0, blk["cd"] - delta)
		if blk["cd"] > 0.0:
			continue
		var node: Node3D = blk["node"]
		var to_blk := (node.global_position - _player.global_position)
		to_blk.y = 0.0
		var dist := to_blk.length()
		if dist > 8.5 and cam_fwd.dot(to_blk.normalized()) < -0.25:
			var next_pos: Vector3 = blk["pos_b"] if blk["at_a"] else blk["pos_a"]
			if _player.global_position.distance_to(next_pos) > 7.0:
				node.position = next_pos
				blk["at_a"] = not blk["at_a"]
				blk["cd"] = 12.0

	# Pitfall check inside Pitfalls zone (x: 4..26, z: 34.5..56.5)
	if _pit_cooldown <= 0.0 and _player.position.y < -2.4:
		_pit_cooldown = 1.5
		_player._on_restart_requested()
		return

	# Red room dead-loop check (x: -8..2, z > 87)
	if _active_zone == "red_deep" and _player.position.z > 87.0:
		_red_loop_count += 1
		if _red_loop_count >= 3:
			_red_loop_count = 0
			_set_active_zone("")
			_player._on_restart_requested()
			return
		_player.position.z -= 12.0

	# Atmosphere & camera tilt blending
	var target_fog := LEVEL0_FOG_COLOR
	var target_density := LEVEL0_FOG_DENSITY
	var target_amb := LEVEL0_AMBIENT_COLOR
	var target_amb_e := LEVEL0_AMBIENT_ENERGY
	var target_hum := LEVEL0_HUM_DB
	var target_roll := 0.0

	match _active_zone:
		"blackout":
			target_fog = Color(0.03, 0.03, 0.03)
			target_density = 0.16
			target_amb = Color(0.05, 0.05, 0.05)
			target_amb_e = 0.12
			target_hum = -60.0
		"red_warn":
			target_fog = Color(0.45, 0.22, 0.16)
			target_density = 0.10
			target_amb = Color(0.60, 0.28, 0.20)
			target_amb_e = 0.36
		"red_deep":
			target_fog = Color(0.32, 0.03, 0.02)
			target_density = 0.12
			target_amb = Color(0.55, 0.08, 0.06)
			target_amb_e = 0.42
			target_hum = -11.0
			target_roll = deg_to_rad(3.5)

	var t := clampf(delta * 2.5, 0.0, 1.0)
	if _active_zone != "" and _world_env and _world_env.environment:
		var env := _world_env.environment
		env.fog_light_color = env.fog_light_color.lerp(target_fog, t)
		env.fog_density = lerpf(env.fog_density, target_density, t)
		env.ambient_light_color = env.ambient_light_color.lerp(target_amb, t)
		env.ambient_light_energy = lerpf(env.ambient_light_energy, target_amb_e, t)
	if _active_zone != "" and _ambient_hum:
		_ambient_hum.volume_db = lerpf(_ambient_hum.volume_db, target_hum, t)
	if _player and _player.camera:
		_player.camera.rotation.z = lerpf(_player.camera.rotation.z, target_roll, t)


func _set_active_zone(zone_name: String) -> void:
	_active_zone = zone_name
	if zone_name == "":
		_red_loop_count = 0
		if _world_env and _world_env.environment:
			var env := _world_env.environment
			env.fog_light_color = LEVEL0_FOG_COLOR
			env.fog_density = LEVEL0_FOG_DENSITY
			env.ambient_light_color = LEVEL0_AMBIENT_COLOR
			env.ambient_light_energy = LEVEL0_AMBIENT_ENERGY
		if _ambient_hum:
			_ambient_hum.volume_db = LEVEL0_HUM_DB


func _build_variants() -> void:
	var body := StaticBody3D.new()
	body.name = "VariantsGeometry"
	add_child(body)

	var lights := Node3D.new()
	lights.name = "VariantsLights"
	add_child(lights)

	var props := Node3D.new()
	props.name = "VariantsProps"
	add_child(props)

	_build_hub(body, lights, props)
	_build_arches(body, lights, props)
	_build_pillars(body, lights, props)
	_build_pitfalls(body, lights, props)
	_build_blackout(body, lights, props)
	_build_red_rooms(body, lights, props)


# --- Hub: connects BackroomsMaze[24][5] (-18.2, 32.5) to all 5 variant zones ---
func _build_hub(body: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	# Entry neck: x [-19.5 .. -16.9], z [32.5 .. 38.5]
	_add_room_box(body, Vector3(-18.2, -0.1, 35.5), Vector3(2.6, 0.2, 6.0), MAT_CARPET)
	_add_room_box(body, Vector3(-18.2, WALL_H + 0.1, 35.5), Vector3(2.6, 0.2, 6.0), MAT_CEILING)
	_add_wall(body, Vector3(-19.65, WALL_H * 0.5, 35.5), Vector3(0.3, WALL_H, 6.0), MAT_WALLPAPER)
	_add_wall(body, Vector3(-16.75, WALL_H * 0.5, 35.5), Vector3(0.3, WALL_H, 6.0), MAT_WALLPAPER)

	# Main Hub: x [-24.0 .. +4.0], z [38.5 .. 46.5]
	_add_room_box(body, Vector3(-10.0, -0.1, 42.5), Vector3(28.0, 0.2, 8.0), MAT_CARPET)
	_add_room_box(body, Vector3(-10.0, WALL_H + 0.1, 42.5), Vector3(28.0, 0.2, 8.0), MAT_CEILING)
	# North wall of Hub (split around entry neck x [-19.5 .. -16.9])
	_add_wall(body, Vector3(-21.75, WALL_H * 0.5, 38.35), Vector3(4.5, WALL_H, 0.3), MAT_WALLPAPER)
	_add_wall(body, Vector3(-6.45, WALL_H * 0.5, 38.35), Vector3(20.9, WALL_H, 0.3), MAT_WALLPAPER)
	# South wall of Hub (openings at Pillars x [-22..-14] and RedRooms x [-5..+1])
	_add_wall(body, Vector3(-23.0, WALL_H * 0.5, 46.65), Vector3(2.0, WALL_H, 0.3), MAT_WALLPAPER)
	_add_wall(body, Vector3(-9.5, WALL_H * 0.5, 46.65), Vector3(9.0, WALL_H, 0.3), MAT_WALLPAPER)
	_add_wall(body, Vector3(2.5, WALL_H * 0.5, 46.65), Vector3(3.0, WALL_H, 0.3), MAT_WALLPAPER)

	for lx in [-18.2, -10.0, -2.0]:
		_add_light_panel(lights, Vector3(lx, WALL_H - 0.02, 42.5), Color(0.98, 0.94, 0.74), 0.72, 7.5)

	_add_note(props, "HubSign", Vector3(-16.9, 1.45, 38.65), 0.0,
		"閱讀牆上的探索指引", "M.E.G. 勘查路標",
		"【Level 0 變體交匯處】\n"
		+ "• 往西：拱門變體（空間穩定，可喘息）\n"
		+ "• 往西南：柱廳變體（極易迷失）\n"
		+ "• 往東：深坑變體（小心腳下！）→ 再往南：熄燈區\n"
		+ "• 往南：紅室前緣（危險！見紅即刻折返）",
		"res://assets/textures/wiki/level0_og.jpg"
	)
	_add_carpet_sample(props, Vector3(-14.0, 0.02, 42.5))


# --- Zone A: Arches (img_2 / level0_arches.jpg) ---
# x: -44 .. -24, z: 34.5 .. 50.5
func _build_arches(body: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	_add_room_box(body, Vector3(-34.0, -0.1, 42.5), Vector3(20.0, 0.2, 16.0), _mat_thick_carpet)
	_add_room_box(body, Vector3(-34.0, WALL_H + 0.1, 42.5), Vector3(20.0, 0.2, 16.0), MAT_CEILING)

	# Outer walls (pale cream)
	_add_wall(body, Vector3(-34.0, WALL_H * 0.5, 34.35), Vector3(20.0, WALL_H, 0.3), _mat_pale_wall)
	_add_wall(body, Vector3(-34.0, WALL_H * 0.5, 50.65), Vector3(20.0, WALL_H, 0.3), _mat_pale_wall)
	_add_wall(body, Vector3(-44.15, WALL_H * 0.5, 42.5), Vector3(0.3, WALL_H, 16.0), _mat_pale_wall)
	# East wall splits around Hub opening z [38.5 .. 46.5]
	_add_wall(body, Vector3(-23.85, WALL_H * 0.5, 36.5), Vector3(0.3, WALL_H, 4.0), _mat_pale_wall)
	_add_wall(body, Vector3(-23.85, WALL_H * 0.5, 48.5), Vector3(0.3, WALL_H, 4.0), _mat_pale_wall)

	# Row of 5 Arched Openings at z = 40.5 (running West-East from x = -42 to -26)
	# Behind z < 40.5 is the inner lit yellow room, just like level0_arches.jpg!
	for i in 5:
		var cx := -42.0 + i * 3.2
		# Pillar on left of bay
		_add_wall(body, Vector3(cx, WALL_H * 0.5, 40.5), Vector3(0.55, WALL_H, 0.45), _mat_pale_wall)
		# Half wall below arch (walk-up/sit height)
		_add_wall(body, Vector3(cx + 1.6, 0.52, 40.5), Vector3(2.65, 1.04, 0.35), _mat_pale_wall)
		# Arch header + stepped corners
		_add_wall(body, Vector3(cx + 1.6, 2.72, 40.5), Vector3(2.65, 0.56, 0.45), _mat_pale_wall)
		_add_wall(body, Vector3(cx + 0.55, 2.28, 40.5), Vector3(0.55, 0.36, 0.45), _mat_pale_wall)
		_add_wall(body, Vector3(cx + 2.65, 2.28, 40.5), Vector3(0.55, 0.36, 0.45), _mat_pale_wall)
	# End pillar
	_add_wall(body, Vector3(-26.0, WALL_H * 0.5, 40.5), Vector3(0.55, WALL_H, 0.45), _mat_pale_wall)

	# Red trash bin & grey bucket on south-east side (matching level0_arches.jpg left foreground)
	_add_cylinder_prop(body, Vector3(-28.5, 0.42, 49.4), 0.32, 0.84, _mat_trash_red)
	_add_cylinder_prop(body, Vector3(-27.7, 0.24, 49.5), 0.20, 0.48, _mat_bucket_grey)

	for lx in [-39.0, -33.0, -27.0]:
		_add_light_panel(lights, Vector3(lx, WALL_H - 0.02, 45.5), Color(0.98, 0.96, 0.85), 0.80, 8.0)
		_add_light_panel(lights, Vector3(lx, WALL_H - 0.02, 37.5), Color(0.96, 0.96, 0.68), 0.72, 7.5)

	_add_note(props, "ArchesNote", Vector3(-30.8, 1.15, 40.7), 0.0,
		"檢視拱門邊的拍立得與紀錄", "拱門變體紀錄",
		"【拱門變體 (Arches)】\n"
		+ "蒼白牆壁上的拱形孔洞，地毯較厚但空間最穩定。\n\n"
		+ "「……摔進一層前，全仗著那些拱門才喘上口氣。好歹活下來了，管它值不值……」",
		"res://assets/textures/wiki/level0_arches.jpg"
	)


# --- Zone B: Pillars (img_3 / level0_pillars.jpg) ---
# Neck: x [-22..-14], z [46.5..50.5]; Hall: x [-36..-10], z [50.5..76.5]
func _build_pillars(body: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	_add_room_box(body, Vector3(-18.0, -0.1, 48.5), Vector3(8.0, 0.2, 4.0), MAT_CARPET)
	_add_room_box(body, Vector3(-18.0, WALL_H + 0.1, 48.5), Vector3(8.0, 0.2, 4.0), MAT_CEILING)
	_add_wall(body, Vector3(-22.15, WALL_H * 0.5, 48.5), Vector3(0.3, WALL_H, 4.0), MAT_WALLPAPER)
	_add_wall(body, Vector3(-13.85, WALL_H * 0.5, 48.5), Vector3(0.3, WALL_H, 4.0), MAT_WALLPAPER)

	_add_room_box(body, Vector3(-23.0, -0.1, 63.5), Vector3(26.0, 0.2, 26.0), MAT_CARPET)
	_add_room_box(body, Vector3(-23.0, WALL_H + 0.1, 63.5), Vector3(26.0, 0.2, 26.0), MAT_CEILING)
	# North wall split around neck x [-22..-14]
	_add_wall(body, Vector3(-29.0, WALL_H * 0.5, 50.35), Vector3(14.0, WALL_H, 0.3), MAT_WALLPAPER)
	_add_wall(body, Vector3(-12.0, WALL_H * 0.5, 50.35), Vector3(4.0, WALL_H, 0.3), MAT_WALLPAPER)
	_add_wall(body, Vector3(-23.0, WALL_H * 0.5, 76.65), Vector3(26.0, WALL_H, 0.3), MAT_WALLPAPER)
	_add_wall(body, Vector3(-36.15, WALL_H * 0.5, 63.5), Vector3(0.3, WALL_H, 26.0), MAT_WALLPAPER)
	_add_wall(body, Vector3(-9.85, WALL_H * 0.5, 63.5), Vector3(0.3, WALL_H, 26.0), MAT_WALLPAPER)

	# 4x4 checkerboard of square pillars + ceiling vents
	for gx in 4:
		for gz in 4:
			var px := -31.0 + gx * 5.2
			var pz := 55.5 + gz * 5.2
			_add_wall(body, Vector3(px, WALL_H * 0.5, pz), Vector3(1.5, WALL_H, 1.5), MAT_WALLPAPER)
			if (gx + gz) % 2 == 0:
				_add_light_panel(lights, Vector3(px + 2.6, WALL_H - 0.02, pz), Color(0.98, 0.94, 0.72), 0.72, 8.0)
			else:
				_add_vent_tile(body, Vector3(px + 2.6, WALL_H - 0.01, pz))

	_add_note(props, "PillarsNote", Vector3(-20.6, 1.45, 56.28), 0.0,
		"閱讀柱面上的 14 天紀錄", "柱廳變體紀錄",
		"【柱廳變體 (Pillars)】\n"
		+ "棋盤狀排列的巨型立柱房間，身後路徑會頻繁變動。\n\n"
		+ "「我在裡面困了十四天。順著行進方向睡、左手始終貼牆——但那地方實在太大。"
		+ "多虧有杏仁水，沒有它，真不知該怎麼熬下來……」",
		"res://assets/textures/wiki/level0_pillars.jpg"
	)
	_add_almond_water(props, "AlmondWater_Pillars", Vector3(-24.2, 0.0, 62.0))
	_add_shifting_pillar(body, Vector3(-28.4, WALL_H * 0.5, 58.1), Vector3(-28.4, WALL_H * 0.5, 60.7))
	_add_shifting_pillar(body, Vector3(-18.0, WALL_H * 0.5, 63.3), Vector3(-15.4, WALL_H * 0.5, 63.3))


# --- Zone C: Pitfalls (img_4 / level0_pitfalls.webp) ---
# x: +4 .. +26 (22m), z: 34.5 .. 56.5 (22m)
func _build_pitfalls(body: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	_add_room_box(body, Vector3(15.0, WALL_H + 0.1, 45.5), Vector3(22.0, 0.2, 22.0), MAT_CEILING)
	_add_wall(body, Vector3(15.0, WALL_H * 0.5, 34.35), Vector3(22.0, WALL_H, 0.3), MAT_WALLPAPER)
	_add_wall(body, Vector3(26.15, WALL_H * 0.5, 45.5), Vector3(0.3, WALL_H, 22.0), MAT_WALLPAPER)
	# West wall splits around Hub opening z [38.5 .. 46.5]
	_add_wall(body, Vector3(3.85, WALL_H * 0.5, 36.5), Vector3(0.3, WALL_H, 4.0), MAT_WALLPAPER)
	_add_wall(body, Vector3(3.85, WALL_H * 0.5, 51.5), Vector3(0.3, WALL_H, 10.0), MAT_WALLPAPER)
	# South wall splits around Blackout opening x [12 .. 18]
	_add_wall(body, Vector3(8.0, WALL_H * 0.5, 56.65), Vector3(8.0, WALL_H, 0.3), MAT_WALLPAPER)
	_add_wall(body, Vector3(22.0, WALL_H * 0.5, 56.65), Vector3(8.0, WALL_H, 0.3), MAT_WALLPAPER)

	# Build floor with a 4x4 grid of 2.0m x 2.0m open pits!
	# Walkable perimeter & bridges:
	# X strips: [4..7], [9..11.5], [13.5..16.5], [18.5..21], [23..26]
	# Z strips: [34.5..37.5], [39.5..42], [44..46.5], [48.5..51], [53..56.5]
	var x_strips: Array[Vector2] = [
		Vector2(4.0, 7.0), Vector2(9.0, 11.5), Vector2(13.5, 16.5), Vector2(18.5, 21.0), Vector2(23.0, 26.0)
	]
	var z_strips: Array[Vector2] = [
		Vector2(34.5, 37.5), Vector2(39.5, 42.0), Vector2(44.0, 46.5), Vector2(48.5, 51.0), Vector2(53.0, 56.5)
	]
	for xs in x_strips:
		_add_room_box(body, Vector3((xs.x + xs.y) * 0.5, -0.1, 45.5), Vector3(xs.y - xs.x, 0.2, 22.0), MAT_CARPET)
	for zs in z_strips:
		_add_room_box(body, Vector3(15.0, -0.1, (zs.x + zs.y) * 0.5), Vector3(22.0, 0.2, zs.y - zs.x), MAT_CARPET)

	# Pit shafts (walls going down to y = -6)
	var pit_x: Array[Vector2] = [Vector2(7.0, 9.0), Vector2(11.5, 13.5), Vector2(16.5, 18.5), Vector2(21.0, 23.0)]
	var pit_z: Array[Vector2] = [Vector2(37.5, 39.5), Vector2(42.0, 44.0), Vector2(46.5, 48.5), Vector2(51.0, 53.0)]
	for px in pit_x:
		for pz in pit_z:
			var cx := (px.x + px.y) * 0.5
			var cz := (pz.x + pz.y) * 0.5
			_add_visual_box(body, Vector3(cx, -3.1, pz.x), Vector3(2.0, 6.0, 0.1), _mat_pit_black)
			_add_visual_box(body, Vector3(cx, -3.1, pz.y), Vector3(2.0, 6.0, 0.1), _mat_pit_black)
			_add_visual_box(body, Vector3(px.x, -3.1, cz), Vector3(0.1, 6.0, 2.0), _mat_pit_black)
			_add_visual_box(body, Vector3(px.y, -3.1, cz), Vector3(0.1, 6.0, 2.0), _mat_pit_black)

	for lx in [9.0, 15.0, 21.0]:
		_add_light_panel(lights, Vector3(lx, WALL_H - 0.02, 41.0), Color(0.96, 0.93, 0.70), 0.72, 8.0)
		_add_light_panel(lights, Vector3(lx, WALL_H - 0.02, 50.0), Color(0.96, 0.93, 0.70), 0.72, 8.0)

	_add_note(props, "PitfallsNote", Vector3(4.15, 1.45, 38.0), 90.0,
		"閱讀深坑警告便條", "深坑變體紀錄",
		"【深坑變體 (Pitfalls)】\n"
		+ "網格狀排列的漆黑深坑，光線只能穿透數英尺，墜入者沒有生還報告。\n\n"
		+ "「……我不認為那些洞口通向任何地方。後室中的事物並不總是合理的——"
		+ "這裡鮮少存在邏輯和意義。」",
		"res://assets/textures/wiki/level0_pitfalls.webp"
	)


# --- Zone D: Blackout Zone (img_5 / level0_blackout.jpg) ---
# x: +4 .. +26, z: 56.5 .. 80.5
func _build_blackout(body: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	_add_room_box(body, Vector3(15.0, -0.1, 68.5), Vector3(22.0, 0.2, 24.0), MAT_CARPET)
	_add_room_box(body, Vector3(15.0, WALL_H + 0.1, 68.5), Vector3(22.0, 0.2, 24.0), MAT_CEILING)
	_add_wall(body, Vector3(3.85, WALL_H * 0.5, 68.5), Vector3(0.3, WALL_H, 24.0), MAT_WALLPAPER)
	_add_wall(body, Vector3(26.15, WALL_H * 0.5, 68.5), Vector3(0.3, WALL_H, 24.0), MAT_WALLPAPER)
	_add_wall(body, Vector3(15.0, WALL_H * 0.5, 80.65), Vector3(22.0, WALL_H, 0.3), MAT_WALLPAPER)

	# Interior maze walls & dead ceiling panels (no lights!)
	_add_wall(body, Vector3(10.0, WALL_H * 0.5, 63.0), Vector3(7.0, WALL_H, 0.4), MAT_WALLPAPER)
	_add_wall(body, Vector3(19.5, WALL_H * 0.5, 67.5), Vector3(8.0, WALL_H, 0.4), MAT_WALLPAPER)
	_add_wall(body, Vector3(11.0, WALL_H * 0.5, 73.0), Vector3(9.0, WALL_H, 0.4), MAT_WALLPAPER)

	# Unlit ceiling panels & wet puddle slabs
	for lx in [9.0, 15.0, 21.0]:
		for lz in [62.0, 70.0, 76.0]:
			_add_visual_box(body, Vector3(lx, WALL_H - 0.02, lz), Vector3(1.15, 0.04, 0.5), _mat_unlit_panel)
	_add_visual_box(body, Vector3(13.0, 0.01, 65.5), Vector3(5.5, 0.02, 4.0), MAT_WET_FLOOR)
	_add_visual_box(body, Vector3(18.0, 0.01, 75.5), Vector3(6.0, 0.02, 4.5), MAT_WET_FLOOR)

	# One faint distant glimmer on the far south-east corner as a visual beacon
	_add_light_panel(lights, Vector3(23.5, WALL_H - 0.02, 78.5), Color(0.85, 0.88, 0.72), 0.25, 4.5)

	_add_zone_trigger("BlackoutTrigger", Vector3(15.0, 1.5, 68.5), Vector3(21.4, 3.0, 23.4), "blackout")

	_add_note(props, "BlackoutNote", Vector3(12.2, 1.45, 57.1), 0.0,
		"閱讀熄燈區邊緣的便條", "熄燈區紀錄",
		"【熄燈區 (Blackout Zone)】\n"
		+ "完全無照明的死寂區域，螢光燈不再嗡鳴，低洼處有積液。請按 [ F ] 開啟手電筒！\n\n"
		+ "「……那些破灯煩人歸煩人，可真要沒了，你反倒會想念它們。」",
		"res://assets/textures/wiki/level0_blackout.jpg"
	)
	_add_flickering_exit_wall(props, Vector3(23.5, WALL_H * 0.5, 80.42))


# --- Zone E: Red Rooms (img_6 / level0_redroom.webp) ---
# Neck: x [-5..+1], z [46.5..50.5]; Warning: [50.5..62.5]; Deep Red: [62.5..92.5]
func _build_red_rooms(body: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	# Neck + Warning threshold (x [-8..+2], z [46.5..62.5])
	_add_room_box(body, Vector3(-2.0, -0.1, 48.5), Vector3(6.0, 0.2, 4.0), MAT_CARPET)
	_add_room_box(body, Vector3(-2.0, WALL_H + 0.1, 48.5), Vector3(6.0, 0.2, 4.0), MAT_CEILING)
	_add_wall(body, Vector3(-5.15, WALL_H * 0.5, 48.5), Vector3(0.3, WALL_H, 4.0), MAT_WALLPAPER)
	_add_wall(body, Vector3(1.15, WALL_H * 0.5, 48.5), Vector3(0.3, WALL_H, 4.0), MAT_WALLPAPER)

	_add_room_box(body, Vector3(-3.0, -0.1, 56.5), Vector3(10.0, 0.2, 12.0), _mat_thick_carpet)
	_add_room_box(body, Vector3(-3.0, WALL_H + 0.1, 56.5), Vector3(10.0, 0.2, 12.0), MAT_CEILING)
	_add_wall(body, Vector3(-6.6, WALL_H * 0.5, 50.35), Vector3(2.8, WALL_H, 0.3), MAT_WALLPAPER)
	_add_wall(body, Vector3(1.5, WALL_H * 0.5, 50.35), Vector3(1.0, WALL_H, 0.3), MAT_WALLPAPER)
	_add_wall(body, Vector3(-8.15, WALL_H * 0.5, 56.5), Vector3(0.3, WALL_H, 12.0), MAT_WALLPAPER)
	_add_wall(body, Vector3(2.15, WALL_H * 0.5, 56.5), Vector3(0.3, WALL_H, 12.0), MAT_WALLPAPER)

	# Peeling wallpaper patches exposing blood-red underneath
	_add_visual_box(body, Vector3(-7.98, 1.3, 55.0), Vector3(0.04, 1.5, 2.2), _mat_peel_red)
	_add_visual_box(body, Vector3(1.98, 1.5, 59.0), Vector3(0.04, 1.8, 2.6), _mat_peel_red)

	# Deep Red Room (x [-8..+2], z [62.5..92.5])
	_add_room_box(body, Vector3(-3.0, -0.1, 77.5), Vector3(10.0, 0.2, 30.0), _mat_red_carpet)
	_add_room_box(body, Vector3(-3.0, WALL_H + 0.1, 77.5), Vector3(10.0, 0.2, 30.0), _mat_red_wall)
	_add_wall(body, Vector3(-8.15, WALL_H * 0.5, 77.5), Vector3(0.3, WALL_H, 30.0), _mat_red_wall)
	_add_wall(body, Vector3(2.15, WALL_H * 0.5, 77.5), Vector3(0.3, WALL_H, 30.0), _mat_red_wall)
	_add_wall(body, Vector3(-3.0, WALL_H * 0.5, 92.65), Vector3(10.0, WALL_H, 0.3), _mat_red_wall)

	# Red Room pillars & white fluorescent panels casting red glow (matching level0_redroom.webp)
	for pz in [66.5, 73.5, 80.5, 87.5]:
		_add_wall(body, Vector3(-4.5, WALL_H * 0.5, pz), Vector3(1.4, WALL_H, 1.4), _mat_red_wall)
		_add_wall(body, Vector3(-0.8, WALL_H * 0.5, pz + 2.5), Vector3(1.4, WALL_H, 1.4), _mat_red_wall)
		_add_light_panel(lights, Vector3(-2.5, WALL_H - 0.02, pz), Color(1.0, 0.15, 0.10), 0.95, 8.5, _mat_white_light)

	_add_zone_trigger("RedWarnTrigger", Vector3(-3.0, 1.5, 56.5), Vector3(9.4, 3.0, 11.4), "red_warn")
	_add_zone_trigger("RedDeepTrigger", Vector3(-3.0, 1.5, 77.5), Vector3(9.4, 3.0, 29.4), "red_deep")

	_add_note(props, "RedRoomNote", Vector3(-7.85, 1.45, 53.0), 90.0,
		"閱讀紅室前的警告紙條", "紅室警告",
		"【紅室 (Red Rooms) — 極度危險】\n"
		+ "牆紙剝落露出血紅、地毯變重且色調轉紅。\n"
		+ "一旦深入便會陷入死循環——請立刻轉身離開！\n\n"
		+ "「……等大多數人意識到自己已經在裡面，早就來不及了……」",
		"res://assets/textures/wiki/level0_redroom.webp"
	)


# --- Geometry & Trigger Helpers (no owner set per AGENTS.md) ---
func _add_room_box(body: StaticBody3D, pos: Vector3, sz: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	body.add_child(mi)

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = sz
	cs.shape = bs
	cs.position = pos
	body.add_child(cs)


func _add_wall(body: StaticBody3D, pos: Vector3, sz: Vector3, mat: Material) -> void:
	_add_room_box(body, pos, sz, mat)


func _add_visual_box(parent: Node3D, pos: Vector3, sz: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _add_cylinder_prop(body: StaticBody3D, pos: Vector3, radius: float, height: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	body.add_child(mi)

	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = radius
	cy.height = height
	cs.shape = cy
	cs.position = pos
	body.add_child(cs)


func _add_vent_tile(parent: Node3D, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.65, 0.03, 0.65)
	mi.mesh = bm
	mi.material_override = MAT_VENT_GRILL
	mi.position = pos
	parent.add_child(mi)


func _add_light_panel(lights: Node3D, pos: Vector3, color: Color, energy: float, rng: float, panel_mat: Material = MAT_FLUORESCENT) -> void:
	var panel := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.15, 0.04, 0.5)
	panel.mesh = bm
	panel.material_override = panel_mat
	panel.position = pos
	lights.add_child(panel)

	var omni := OmniLight3D.new()
	omni.position = pos - Vector3(0.0, 0.35, 0.0)
	omni.light_color = color
	omni.light_energy = energy
	omni.omni_range = rng
	omni.shadow_enabled = false
	lights.add_child(omni)


func _add_note(props: Node3D, node_name: String, pos: Vector3, rot_y: float, prompt: String, f_name: String, body_txt: String, img_path: String) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.rotation_degrees = Vector3(0.0, rot_y, 0.0)
	body.set_script(INTERACT_SCRIPT)
	body.set("prompt_text", prompt)
	body.set("interaction_type", "note")
	body.set("file_name", f_name)
	body.set("body_text", body_txt)
	body.set("image_path", img_path)
	props.add_child(body)

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


func _add_zone_trigger(t_name: String, pos: Vector3, sz: Vector3, zone_id: String) -> void:
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
			_set_active_zone(zone_id)
	)
	area.body_exited.connect(func(b: Node) -> void:
		if b == _player and _active_zone == zone_id:
			_set_active_zone("")
	)


func _add_shifting_pillar(parent: Node3D, pos_a: Vector3, pos_b: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.position = pos_a
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.5, WALL_H, 1.5)
	mi.mesh = bm
	mi.material_override = MAT_WALLPAPER
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	sb.add_child(cs)
	parent.add_child(sb)
	_shifting_blocks.append({"node": sb, "pos_a": pos_a, "pos_b": pos_b, "at_a": true, "cd": 0.0})


func _add_almond_water(props: Node3D, node_name: String, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.set_script(INTERACT_SCRIPT)
	body.set("prompt_text", "拾取並檢視「杏仁水」")
	body.set("interaction_type", "note")
	body.set("file_name", "杏仁水")
	body.set("body_text",
		"【物資：杏仁水 (Almond Water)】\n\n"
		+ "散發著微弱甜香的瓶裝液體，是在 Level 0 熬過長期迷失與脫水的救命物資。\n"
		+ "（注意：切勿飲用地毯裡擠出的受污染液體！）"
	)
	props.add_child(body)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.82, 0.88)
	mat.roughness = 0.25
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.065
	cm.height = 0.24
	mi.mesh = cm
	mi.material_override = mat
	mi.position = Vector3(0.0, 0.12, 0.0)
	body.add_child(mi)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.35, 0.4, 0.35)
	col.shape = shape
	col.position = Vector3(0.0, 0.2, 0.0)
	body.add_child(col)


func _add_carpet_sample(props: Node3D, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "DampCarpetSpot"
	body.position = pos
	body.set_script(INTERACT_SCRIPT)
	body.set("prompt_text", "檢查潮濕的地毯")
	body.set("interaction_type", "note")
	body.set("file_name", "潮濕的柏柏爾地毯")
	body.set("body_text",
		"【地毯樣本觀察】\n"
		+ "整層樓由一張無縫柏柏爾地毯鋪成，滲有鹽水、杏仁水、液態痛苦與福馬林。\n\n"
		+ "「想想看，好不容易從『黃色地獄』撿回一條命，結果卻死於什麼不明不白的地毯病，"
		+ "或是被纖維堵了腸子。拜託了，別吃地毯……」"
	)
	props.add_child(body)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.34, 0.29, 0.17)
	mat.roughness = 0.95
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.1, 0.02, 1.1)
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.1, 0.2, 1.1)
	col.shape = shape
	body.add_child(col)


func _add_flickering_exit_wall(props: Node3D, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "FlickeringWallExit"
	body.position = pos
	body.set_script(INTERACT_SCRIPT)
	body.set("prompt_text", "投入閃爍的牆壁（切出至 Level 1）")
	body.set("interaction_type", "level1_exit")
	props.add_child(body)

	_flicker_wall_mat = StandardMaterial3D.new()
	_flicker_wall_mat.albedo_color = Color(0.75, 0.78, 0.65)
	_flicker_wall_mat.emission_enabled = true
	_flicker_wall_mat.emission = Color(0.85, 0.92, 0.72)
	_flicker_wall_mat.emission_energy_multiplier = 0.8

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.4, 2.8, 0.14)
	mi.mesh = bm
	mi.material_override = _flicker_wall_mat
	body.add_child(mi)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.4, 2.8, 0.3)
	col.shape = shape
	body.add_child(col)
