@tool
extends "res://scripts/backrooms_maze.gd"

# West annex of Level 0. Reuses the maze helpers (walls, lights, floor) from the parent script.
# Row N here lines up with row N of MAZE_MAP; the Level0Annex node sits at x = -(cols + 2) * CELL_SIZE.
# Row 19 is the only link: MAZE_MAP[19][0] and ANNEX_MAP[19][20] are both open.
# '#' wall, '.' floor, 'C' pillar, 'L' steady light, 'D' dim flickering light, 'A' anomaly light
const ANNEX_MAP: PackedStringArray = [
	"#####################",
	"#L.......#....#...D.#",
	"#.........#....#....#",
	"#..C...C..#....#.##.#",
	"#.........#.........#",
	"#..C...C.....#.####.#",
	"#.........#.#.......#",
	"###.#######.#.#####.#",
	"#...#.....#.#.......#",
	"#.D.#.###.#.#.#####.#",
	"#...#.#L#...#.......#",
	"#.###.#.#.#########.#",
	"#.....#...#.........#",
	"###.###.#####.#####.#",
	"#L..#...............#",
	"#...#.#####.#######.#",
	"#...#.#...#.#.......#",
	"#.#.#.#.#.#.#.#####.#",
	"#.#...#.#...#.......#",
	"#.#####.#########....",
	"#.D...............L.#",
	"#.#####.###########.#",
	"#.....#...C...C.....#",
	"#L....#.A.....#..D..#",
	"#####################",
]


func _build_maze() -> void:
	var rows := ANNEX_MAP.size()
	var cols := ANNEX_MAP[0].length()
	var half_x := (cols - 1) * 0.5
	var half_z := (rows - 1) * 0.5

	if not Engine.is_editor_hint():
		_hum_stream = BackroomsAudio.create_fluorescent_hum_stream()
		_pop_stream = BackroomsAudio.create_light_pop_stream()

	_unlit_panel_mat = StandardMaterial3D.new()
	_unlit_panel_mat.albedo_color = Color(0.18, 0.18, 0.16)
	_unlit_panel_mat.roughness = 0.7

	var static_body := StaticBody3D.new()
	static_body.name = "AnnexGeometry"
	add_child(static_body)

	var lights_root := Node3D.new()
	lights_root.name = "AnnexLights"
	add_child(lights_root)

	_add_floor_and_ceiling(static_body, cols * CELL_SIZE, rows * CELL_SIZE)

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
		for x in cols:
			var ch := ANNEX_MAP[y][x]
			var wx := (x - half_x) * CELL_SIZE
			var wz := (y - half_z) * CELL_SIZE
			match ch:
				"#":
					_add_block(static_body, wall_mesh, wall_shape, Vector3(wx, WALL_HEIGHT * 0.5, wz))
				"C":
					_add_block(static_body, pillar_mesh, pillar_shape, Vector3(wx, WALL_HEIGHT * 0.5, wz))
				"L":
					_add_ceiling_light(lights_root, panel_mesh, Vector3(wx, 0.0, wz), false, x * 1.7 + y, false)
				"D":
					_add_ceiling_light(lights_root, panel_mesh, Vector3(wx, 0.0, wz), true, x * 2.3 + y, false)
				"A":
					_add_anomaly_light(lights_root, panel_mesh, Vector3(wx, 0.0, wz))
