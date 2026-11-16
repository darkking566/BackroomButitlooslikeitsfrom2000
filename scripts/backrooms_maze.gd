@tool
extends Node3D

const CELL_SIZE: float = 2.6
const WALL_HEIGHT: float = 3.0

const MAT_WALLPAPER := preload("res://materials/mat_wallpaper.tres")
const MAT_CARPET := preload("res://materials/mat_carpet.tres")
const MAT_CEILING := preload("res://materials/mat_ceiling.tres")
const MAT_FLUORESCENT := preload("res://materials/mat_fluorescent.tres")

# 13x13 Level 0 Maze:
# '#' = wall, '.' = open floor, 'P' = player spawn, 'C' = pillar
# 'L' = steady fluorescent light, 'D' = dim flickering buzzing light
# Note: row 9 col 12 opens Eastward into Zone 2
const MAZE_MAP: PackedStringArray = [
	"#############",
	"#L....#L...D#",
	"#.##..#.##..#",
	"#.#L....#L..#",
	"#.#.###.#.#.#",
	"#...L...#...#",
	"###..C..#.###",
	"#L..#...L..D#",
	"#.#.#.#.#.#.#",
	"#P..L.#.#....",
	"#.##..#.#.###",
	"#D....L...L.#",
	"#############",
]

var _flicker_lights: Array[Dictionary] = []
var _flicker_time: float = 0.0
var _hum_stream: AudioStreamWAV


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
		light.light_energy = 0.65 * dip


func _build_maze() -> void:
	var rows := MAZE_MAP.size()
	var cols := MAZE_MAP[0].length()
	var half_x := (cols - 1) * 0.5
	var half_z := (rows - 1) * 0.5
	var total_w := cols * CELL_SIZE
	var total_d := rows * CELL_SIZE

	if not Engine.is_editor_hint():
		_hum_stream = BackroomsAudio.create_fluorescent_hum_stream()

	var static_body := StaticBody3D.new()
	static_body.name = "MazeGeometry"
	add_child(static_body)

	var lights_root := Node3D.new()
	lights_root.name = "MazeLights"
	add_child(lights_root)

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
				var cast_shadow := Vector2i(x, y) in [Vector2i(4, 9), Vector2i(4, 5), Vector2i(8, 7)]
				_add_ceiling_light(lights_root, panel_mesh, Vector3(world_x, 0.0, world_z), false, x * 1.7 + y, cast_shadow)
			elif ch == "D":
				_add_ceiling_light(lights_root, panel_mesh, Vector3(world_x, 0.0, world_z), true, x * 2.3 + y, false)


func _add_floor_and_ceiling(parent: StaticBody3D, total_w: float, total_d: float) -> void:
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(total_w, 0.2, total_d)
	floor_mesh.subdivide_width = 34
	floor_mesh.subdivide_depth = 34

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
	ceil_mesh.subdivide_width = 34
	ceil_mesh.subdivide_depth = 34

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
	light.omni_range = 7.2 if is_dim else 9.0
	light.light_energy = 0.65 if is_dim else 1.55
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
