@tool
extends Node3D

const CELL_SIZE: float = 2.6
const WALL_HEIGHT: float = 3.0

const MAT_WALLPAPER := preload("res://materials/mat_wallpaper.tres")
const MAT_CARPET := preload("res://materials/mat_carpet.tres")
const MAT_CEILING := preload("res://materials/mat_ceiling.tres")
const MAT_FLUORESCENT := preload("res://materials/mat_fluorescent.tres")

const SCENE_DESK_PATH := "res://assets/models/retro_office_desk.glb"
const SCENE_CHAIR_PATH := "res://assets/models/office_chair.glb"
const SCENE_CABINET_PATH := "res://assets/models/filing_cabinet.glb"
const SCENE_BREAKER_PATH := "res://assets/models/breaker_box.glb"
const INTERACT_SCRIPT := preload("res://scripts/interactable_prop.gd")

# 25x25 Expanded Level 0 Maze (~65m x 65m):
# '#' = wall, '.' = open floor, 'P' = spawn (2,19), 'C' = pillar
# 'L' = steady fluorescent light, 'D' = dim flickering light
# 'A' = anomaly light (snaps OFF with electrical pop when approached)
# Note: row 15 col 24 opens Eastward into Zone 2; row 19 col 0 opens Westward into Level0Annex
const MAZE_MAP: PackedStringArray = [
	"#########################",
	"#L........#..D......#..D#",
	"#..C...C..#..#..##..#...#",
	"#.........#.....#.......#",
	"#..C...C.....#..#..###..#",
	"#.........#..#..........#",
	"#..C..A...#..####.###.###",
	"#.........#.............#",
	"#.##...##.#..#..D..#..#.#",
	"#.#L...L#....#.....#..#.#",
	"#.#.....#.####..####..#.#",
	"#....#...........#......#",
	"#####.######.######.#####",
	"#L...#...L..#..#....#...#",
	"#....#......#..#.##.#.#.#",
	"#.##.###.##.#..L....A....",
	"#.#.......#.#..#.####.#.#",
	"#.#..L....#.#..#....#...#",
	"#.#.......#....#.##.#.###",
	"..P..#....####.#..L.#...#",
	"#.##.#.#.......#....#.#.#",
	"#....#.#..###..###.##.#.#",
	"#.D..#L...#.........#...#",
	"#.........#..D...L....D.#",
	"#####.###################",
]

var _flicker_lights: Array[Dictionary] = []
var _flicker_time: float = 0.0
var _hum_stream: AudioStreamWAV
var _pop_stream: AudioStreamWAV
var _unlit_panel_mat: StandardMaterial3D


func _ready() -> void:
	if get_child_count() == 0:
		_build_maze()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _flicker_lights.is_empty():
		return
	_flicker_time += delta
	for item in _flicker_lights:
		var light: OmniLight3D = item["light"]
		var phase: float = item["phase"]
		var wave := sin((_flicker_time + phase) * 17.0) * sin((_flicker_time + phase) * 43.0)
		var dip := 0.25 if wave > 0.72 else 1.0
		light.light_energy = 0.55 * dip


func _build_maze() -> void:
	var rows := MAZE_MAP.size()
	var cols := MAZE_MAP[0].length()
	var half_x := (cols - 1) * 0.5
	var half_z := (rows - 1) * 0.5
	var total_w := cols * CELL_SIZE
	var total_d := rows * CELL_SIZE

	if not Engine.is_editor_hint():
		_hum_stream = BackroomsAudio.create_fluorescent_hum_stream()
		_pop_stream = BackroomsAudio.create_light_pop_stream()

	_unlit_panel_mat = StandardMaterial3D.new()
	_unlit_panel_mat.albedo_color = Color(0.18, 0.18, 0.16)
	_unlit_panel_mat.roughness = 0.7

	var static_body := StaticBody3D.new()
	static_body.name = "MazeGeometry"
	add_child(static_body)

	var lights_root := Node3D.new()
	lights_root.name = "MazeLights"
	add_child(lights_root)

	var props_root := Node3D.new()
	props_root.name = "MazeProps"
	add_child(props_root)

	_add_floor_and_ceiling(static_body, total_w, total_d)

	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(CELL_SIZE, WALL_HEIGHT, CELL_SIZE)
	wall_mesh.subdivide_width = 2
	wall_mesh.subdivide_height = 3
	wall_mesh.subdivide_depth = 2

	var wall_shape := BoxShape3D.new()
	wall_shape.size = wall_mesh.size

	var pillar_mesh := BoxMesh.new()
	pillar_mesh.size = Vector3(1.0, WALL_HEIGHT, 1.0)
	pillar_mesh.subdivide_width = 1
	pillar_mesh.subdivide_height = 3
	pillar_mesh.subdivide_depth = 1

	var pillar_shape := BoxShape3D.new()
	pillar_shape.size = pillar_mesh.size

	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(1.15, 0.04, 0.5)

	for y in rows:
		var row_str := MAZE_MAP[y]
		for x in cols:
			var ch := row_str[x]
			var world_x := (x - half_x) * CELL_SIZE
			var world_z := (y - half_z) * CELL_SIZE

			if ch == "#":
				_add_block(static_body, wall_mesh, wall_shape, Vector3(world_x, WALL_HEIGHT * 0.5, world_z))
			elif ch == "C":
				_add_block(static_body, pillar_mesh, pillar_shape, Vector3(world_x, WALL_HEIGHT * 0.5, world_z))
			elif ch == "L":
				# Keep only 3 key lights casting real-time shadows per AGENTS.md
				var cast_shadow := Vector2i(x, y) in [Vector2i(5, 17), Vector2i(9, 13), Vector2i(15, 15)]
				_add_ceiling_light(lights_root, panel_mesh, Vector3(world_x, 0.0, world_z), false, x * 1.7 + y, cast_shadow)
			elif ch == "D":
				_add_ceiling_light(lights_root, panel_mesh, Vector3(world_x, 0.0, world_z), true, x * 2.3 + y, false)
			elif ch == "A":
				_add_anomaly_light(lights_root, panel_mesh, Vector3(world_x, 0.0, world_z))

	_populate_props(props_root, half_x, half_z)


func _grid_to_world(gx: float, gz: float, half_x: float, half_z: float) -> Vector3:
	return Vector3((gx - half_x) * CELL_SIZE, 0.0, (gz - half_z) * CELL_SIZE)


func _populate_props(props_root: Node3D, half_x: float, half_z: float) -> void:
	# 1. Main Abandoned Office Desk + Chair (Memory 43) in Office Suite (9, 16)
	var desk1_pos := _grid_to_world(9.2, 16.0, half_x, half_z)
	_spawn_desk(props_root, "OfficeDesk_43", desk1_pos, -90.0, true,
		"檢視舊電腦磁片資料", "Exploring - S??I", "Memory 43", "1.44mb",
		"【磁片紀錄：Memory 43】\n日期：?/??/????  時間：??:??\n\n"
		+ "這裡比我想像的大太多了。北邊是一整片望不到頭的柱廳，\n"
		+ "再往東北走，整區的日光燈都燒壞了，黑得伸手不見五指。\n\n"
		+ "唯有最東邊走廊上方掛著一塊紅色的 EXIT 燈牌。\n"
		+ "如果你拿著手電筒看到這段紀錄——往東邊 EXIT 走吧。"
	)
	_spawn_chair(props_root, "Chair_43", desk1_pos + Vector3(-0.95, 0.0, 0.15), -68.0)

	# 2. Second Office Desk + Chair (Memory 41) in Office Suite (5.8, 17.5)
	var desk2_pos := _grid_to_world(5.0, 18.0, half_x, half_z)
	_spawn_desk(props_root, "OfficeDesk_41", desk2_pos, 0.0, false,
		"檢視桌上的舊電腦", "Exploring - A:\\", "Memory 41", "720kb",
		"【磁片紀錄：Memory 41】\n\n"
		+ "第 4 天。同事們昨天說要去檢查東北角的配電箱，結果一直沒回來。\n"
		+ "剛才經過東邊長廊時，頭頂的燈在我背後突然「啪」一聲熄掉了。\n"
		+ "我確定這層樓的電路根本沒有接在任何總表上。"
	)
	_spawn_chair(props_root, "Chair_41", desk2_pos + Vector3(0.2, 0.0, 0.95), 25.0)

	# 2b. M.E.G. Wiki Archive Terminal in Office Suite (6.8, 16.0)
	var desk_meg_pos := _grid_to_world(6.8, 16.0, half_x, half_z)
	_spawn_desk(props_root, "OfficeDesk_MEG", desk_meg_pos, 0.0, true,
		"瀏覽 M.E.G.「閾界」檔案庫", "M.E.G. Archive - 閾界", "00_閾界_檔案.txt", "4.2kb", ""
	)
	var meg_desk := props_root.get_node_or_null("OfficeDesk_MEG")
	if meg_desk:
		meg_desk.set("interaction_type", "wiki_archive")

	# 3. Filing Cabinets along Office & Pillar Hall walls
	_spawn_cabinet(props_root, "Cabinet_1", _grid_to_world(3.0, 16.2, half_x, half_z) + Vector3(-0.85, 0.0, 0.0), -90.0)
	_spawn_cabinet(props_root, "Cabinet_2", _grid_to_world(3.0, 16.2, half_x, half_z) + Vector3(-0.85, 0.0, 0.55), -90.0)
	_spawn_cabinet(props_root, "Cabinet_3", _grid_to_world(1.0, 5.0, half_x, half_z) + Vector3(-0.85, 0.0, 0.0), -90.0)

	# 4. Blackout Sector Breaker Box (19, 1) on North wall
	var breaker_pos := _grid_to_world(19.0, 1.0, half_x, half_z) + Vector3(0.0, 1.45, -1.18)
	_spawn_breaker(props_root, breaker_pos)

	# 5. Pillar Hall Wall Note on Pillar (3, 4)
	var note_pos := _grid_to_world(3.0, 4.0, half_x, half_z) + Vector3(-0.52, 1.42, 0.0)
	_spawn_paper_note(props_root, "PillarNote_02", note_pos, "閱讀柱子上的便條", "Memo_02",
		"【留給後來的人】\n\n"
		+ "這片柱廳的燈光跟霧氣會讓人失去方向感。\n"
		+ "如果迷路了，記得貼著南邊牆壁往東南角走——\n"
		+ "聽見遠處突然跳電的時候，你離 EXIT 就不遠了。"
	)

	_add_og_details(props_root, half_x, half_z)


func _add_og_details(parent: Node3D, half_x: float, half_z: float) -> void:
	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.52, 0.45, 0.24)
	trim_mat.roughness = 0.78

	var outlet_mat := StandardMaterial3D.new()
	outlet_mat.albedo_color = Color(0.76, 0.72, 0.56)
	outlet_mat.roughness = 0.65

	var trim_x_mesh := BoxMesh.new()
	trim_x_mesh.size = Vector3(CELL_SIZE, 0.08, 0.03)
	var trim_z_mesh := BoxMesh.new()
	trim_z_mesh.size = Vector3(0.03, 0.08, CELL_SIZE)
	var outlet_mesh := BoxMesh.new()
	outlet_mesh.size = Vector3(0.11, 0.16, 0.025)

	# Add OGLevel0-style baseboard trim & outlets along visible walls in rows 16..24, cols 0..10
	for y in range(16, 25):
		for x in range(0, 11):
			if MAZE_MAP[y][x] != "#":
				continue
			var wx := (x - half_x) * CELL_SIZE
			var wz := (y - half_z) * CELL_SIZE
			var half_c := CELL_SIZE * 0.5 + 0.015
			if y > 0 and MAZE_MAP[y - 1][x] != "#":
				_place_deco(parent, trim_x_mesh, trim_mat, Vector3(wx, 0.16, wz - half_c), 0.0)
			if y < MAZE_MAP.size() - 1 and MAZE_MAP[y + 1][x] != "#":
				_place_deco(parent, trim_x_mesh, trim_mat, Vector3(wx, 0.16, wz + half_c), 0.0)
				if (x + y) % 4 == 0:
					_place_deco(parent, outlet_mesh, outlet_mat, Vector3(wx, 0.34, wz + half_c), 0.0)
			if x > 0 and MAZE_MAP[y][x - 1] != "#":
				_place_deco(parent, trim_z_mesh, trim_mat, Vector3(wx - half_c, 0.16, wz), 0.0)
			if x < MAZE_MAP[0].length() - 1 and MAZE_MAP[y][x + 1] != "#":
				_place_deco(parent, trim_z_mesh, trim_mat, Vector3(wx + half_c, 0.16, wz), 0.0)
				if (x + y) % 5 == 0:
					_place_deco(parent, outlet_mesh, outlet_mat, Vector3(wx + half_c, 0.34, wz), 90.0)


func _place_deco(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot_y: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = Vector3(0.0, rot_y, 0.0)
	parent.add_child(mi)


func _spawn_desk(parent: Node3D, node_name: String, pos: Vector3, rot_y: float, with_light: bool,
		prompt: String, win_title: String, f_name: String, f_size: String, body_txt: String) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.rotation_degrees = Vector3(0.0, rot_y, 0.0)
	body.set_script(INTERACT_SCRIPT)
	body.set("prompt_text", prompt)
	body.set("interaction_type", "explorer")
	body.set("window_title", win_title)
	body.set("file_name", f_name)
	body.set("file_size", f_size)
	body.set("body_text", body_txt)
	parent.add_child(body)

	var desk_scene := load(SCENE_DESK_PATH) as PackedScene
	if desk_scene:
		var model := desk_scene.instantiate()
		body.add_child(model)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.45, 1.16, 0.78)
	col.shape = shape
	col.position = Vector3(0.0, 0.58, 0.0)
	body.add_child(col)

	if with_light:
		var light := OmniLight3D.new()
		light.position = Vector3(-0.08, 1.0, 0.35)
		light.light_color = Color(0.18, 0.85, 0.38)
		light.light_energy = 0.4
		light.omni_range = 2.6
		body.add_child(light)


func _spawn_chair(parent: Node3D, node_name: String, pos: Vector3, rot_y: float) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.rotation_degrees = Vector3(0.0, rot_y, 0.0)
	parent.add_child(body)
	var chair_scene := load(SCENE_CHAIR_PATH) as PackedScene
	if chair_scene:
		body.add_child(chair_scene.instantiate())

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.55, 0.95, 0.55)
	col.shape = shape
	col.position = Vector3(0.0, 0.475, 0.0)
	body.add_child(col)


func _spawn_cabinet(parent: Node3D, node_name: String, pos: Vector3, rot_y: float) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.rotation_degrees = Vector3(0.0, rot_y, 0.0)
	parent.add_child(body)
	var cab_scene := load(SCENE_CABINET_PATH) as PackedScene
	if cab_scene:
		body.add_child(cab_scene.instantiate())

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.48, 1.32, 0.62)
	col.shape = shape
	col.position = Vector3(0.0, 0.66, 0.0)
	body.add_child(col)


func _spawn_breaker(parent: Node3D, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "BreakerBox"
	body.position = pos
	body.set_script(INTERACT_SCRIPT)
	body.set("prompt_text", "檢查停電區配電箱")
	body.set("interaction_type", "note")
	body.set("file_name", "Breaker_Log")
	body.set("body_text",
		"【配電箱檢修標籤】\n\n"
		+ "東北區（B-04 迴路）主保險絲已完全熔斷。\n"
		+ "備註：沒有任何外部電力來源接入此箱體，\n"
		+ "請勿嘗試徒手重置。"
	)
	parent.add_child(body)
	var breaker_scene := load(SCENE_BREAKER_PATH) as PackedScene
	if breaker_scene:
		body.add_child(breaker_scene.instantiate())

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.55, 0.80, 0.25)
	col.shape = shape
	body.add_child(col)

	var led_light := OmniLight3D.new()
	led_light.position = Vector3(-0.15, 0.22, 0.18)
	led_light.light_color = Color(1.0, 0.15, 0.10)
	led_light.light_energy = 0.5
	led_light.omni_range = 2.4
	body.add_child(led_light)


func _spawn_paper_note(parent: Node3D, node_name: String, pos: Vector3, prompt: String, title: String, body_txt: String) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.set_script(INTERACT_SCRIPT)
	body.set("prompt_text", prompt)
	body.set("interaction_type", "note")
	body.set("file_name", title)
	body.set("body_text", body_txt)
	parent.add_child(body)

	var paper_mat := StandardMaterial3D.new()
	paper_mat.albedo_color = Color(0.92, 0.88, 0.70)
	paper_mat.roughness = 0.9

	var paper_mesh := BoxMesh.new()
	paper_mesh.size = Vector3(0.03, 0.34, 0.26)
	var paper_mi := MeshInstance3D.new()
	paper_mi.mesh = paper_mesh
	paper_mi.material_override = paper_mat
	body.add_child(paper_mi)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.25, 0.55, 0.45)
	col.shape = shape
	body.add_child(col)


func _add_floor_and_ceiling(parent: StaticBody3D, total_w: float, total_d: float) -> void:
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(total_w, 0.2, total_d)
	floor_mesh.subdivide_width = 64
	floor_mesh.subdivide_depth = 64

	var floor_shape := BoxShape3D.new()
	floor_shape.size = floor_mesh.size

	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = floor_mesh
	floor_mi.material_override = MAT_CARPET
	floor_mi.position = Vector3(0.0, -0.1, 0.0)
	parent.add_child(floor_mi)

	var floor_col := CollisionShape3D.new()
	floor_col.shape = floor_shape
	floor_col.position = floor_mi.position
	parent.add_child(floor_col)

	var ceil_mesh := BoxMesh.new()
	ceil_mesh.size = Vector3(total_w, 0.2, total_d)
	ceil_mesh.subdivide_width = 64
	ceil_mesh.subdivide_depth = 64

	var ceil_mi := MeshInstance3D.new()
	ceil_mi.mesh = ceil_mesh
	ceil_mi.material_override = MAT_CEILING
	ceil_mi.position = Vector3(0.0, WALL_HEIGHT + 0.1, 0.0)
	parent.add_child(ceil_mi)

	var ceil_col := CollisionShape3D.new()
	ceil_col.shape = floor_shape
	ceil_col.position = ceil_mi.position
	parent.add_child(ceil_col)


func _add_block(parent: StaticBody3D, mesh: BoxMesh, shape: BoxShape3D, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = MAT_WALLPAPER
	mi.position = pos
	parent.add_child(mi)

	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = pos
	parent.add_child(col)


func _add_ceiling_light(parent: Node3D, panel_mesh: BoxMesh, pos: Vector3, is_dim: bool, phase: float, cast_shadow: bool = false) -> void:
	var panel := MeshInstance3D.new()
	panel.mesh = panel_mesh
	panel.material_override = MAT_FLUORESCENT
	panel.position = Vector3(pos.x, WALL_HEIGHT - 0.02, pos.z)
	parent.add_child(panel)

	var light := OmniLight3D.new()
	light.position = Vector3(pos.x, WALL_HEIGHT - 0.26, pos.z)
	light.omni_range = 6.8 if is_dim else 9.5
	light.light_energy = 0.55 if is_dim else 1.55
	light.light_color = Color(0.92, 0.85, 0.60) if is_dim else Color(1.0, 0.95, 0.78)
	light.shadow_enabled = cast_shadow
	parent.add_child(light)

	if is_dim:
		_flicker_lights.append({"light": light, "phase": phase})
		if not Engine.is_editor_hint() and _hum_stream != null:
			var buzz := AudioStreamPlayer3D.new()
			buzz.stream = _hum_stream
			buzz.position = light.position
			buzz.volume_db = -10.0
			buzz.max_distance = 11.0
			buzz.pitch_scale = 1.06
			buzz.autoplay = true
			parent.add_child(buzz)


func _add_anomaly_light(parent: Node3D, panel_mesh: BoxMesh, pos: Vector3) -> void:
	var panel := MeshInstance3D.new()
	panel.mesh = panel_mesh
	panel.material_override = MAT_FLUORESCENT
	panel.position = Vector3(pos.x, WALL_HEIGHT - 0.02, pos.z)
	parent.add_child(panel)

	var light := OmniLight3D.new()
	light.position = Vector3(pos.x, WALL_HEIGHT - 0.26, pos.z)
	light.omni_range = 9.0
	light.light_energy = 1.5
	light.light_color = Color(1.0, 0.95, 0.78)
	light.shadow_enabled = false
	parent.add_child(light)

	if Engine.is_editor_hint():
		return

	var pop_player := AudioStreamPlayer3D.new()
	pop_player.stream = _pop_stream
	pop_player.position = light.position
	pop_player.volume_db = -2.0
	pop_player.max_distance = 18.0
	parent.add_child(pop_player)

	var trigger := Area3D.new()
	trigger.position = Vector3(pos.x, 1.5, pos.z)
	var trig_col := CollisionShape3D.new()
	var trig_box := BoxShape3D.new()
	trig_box.size = Vector3(5.0, 3.0, 5.0)
	trig_col.shape = trig_box
	trigger.add_child(trig_col)
	parent.add_child(trigger)

	var state := {"done": false}
	trigger.body_entered.connect(func(body: Node3D) -> void:
		if state["done"] or not (body is CharacterBody3D):
			return
		state["done"] = true
		pop_player.play()
		light.light_energy = 2.6
		get_tree().create_timer(0.07).timeout.connect(func() -> void:
			if is_instance_valid(light):
				light.visible = false
			if is_instance_valid(panel):
				panel.material_override = _unlit_panel_mat
		)
	)
