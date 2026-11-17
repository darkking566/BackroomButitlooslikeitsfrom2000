extends RefCounted
## BlenderMap 區域細節補全（道具、互動筆記、環境貼片、局域補光）。
## 所有座標皆為世界座標；道具透過物理射線貼合實際地面與牆面，不硬編寫死高度。

const INTERACT_SCRIPT := preload("res://scripts/interactable_prop.gd")
const PROP_DIR := "res://assets/models/props/"

const OLD_MODELS := {
	"desk": "res://assets/models/retro_office_desk.glb",
	"chair": "res://assets/models/office_chair.glb",
	"cabinet": "res://assets/models/filing_cabinet.glb",
	"breaker_box": "res://assets/models/breaker_box.glb",
	"exit_sign": "res://assets/models/exit_sign.glb",
}

const PROP_SIZE := {
	"armchair": Vector3(1.7, 1.02, 1.6),
	"barrel": Vector3(0.55, 0.9, 0.55),
	"box_closed": Vector3(0.42, 0.55, 0.42),
	"breaker_box": Vector3(0.45, 0.65, 0.18),
	"bucket": Vector3(0.27, 0.38, 0.29),
	"cabinet": Vector3(0.48, 1.32, 0.62),
	"cardboard_boxes": Vector3(1.0, 0.97, 0.94),
	"chair": Vector3(0.55, 0.95, 0.55),
	"coffee_machine": Vector3(0.32, 0.3, 0.4),
	"computer_screen": Vector3(0.5, 0.37, 0.13),
	"desk": Vector3(1.45, 1.16, 0.78),
	"exit_sign": Vector3(0.45, 0.22, 0.12),
	"floor_lamp": Vector3(0.3, 1.7, 0.31),
	"fridge": Vector3(0.84, 1.8, 0.83),
	"ladder": Vector3(0.37, 2.6, 0.1),
	"pallet": Vector3(1.2, 0.14, 1.03),
	"pallet_broken": Vector3(1.2, 0.18, 1.04),
	"plant": Vector3(1.1, 1.03, 0.99),
	"shelf_small": Vector3(1.4, 0.52, 0.74),
	"trashcan": Vector3(0.42, 0.6, 0.26),
}

const NO_COLLIDE := ["pallet", "pallet_broken", "coffee_machine", "computer_screen", "bucket", "breaker_box", "exit_sign"]

var _root: Node3D
var _space: PhysicsDirectSpaceState3D
var _prop_scenes := {}


static func build(map_node: Node3D) -> void:
	var builder := new()
	builder._run(map_node)


func _run(map_node: Node3D) -> void:
	var existing := map_node.get_node_or_null("MapDetails")
	if existing:
		existing.queue_free()
	_root = Node3D.new()
	_root.name = "MapDetails"
	map_node.add_child(_root)
	_space = map_node.get_world_3d().direct_space_state
	_build_wp38()


# --- 共用幾何與放置工具 ---

func _floor_y(x: float, y_hint: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, y_hint + 1.5, z), Vector3(x, y_hint - 2.5, z))
	var hit := _space.intersect_ray(q)
	if hit.is_empty():
		return y_hint
	return (hit["position"] as Vector3).y


func _wall_hit(origin: Vector3, dir: Vector3, max_dist: float = 12.0) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir.normalized() * max_dist)
	return _space.intersect_ray(q)


func _prop(kind: String, pos: Vector3, rot_y: float = 0.0, snap_floor: bool = true, rot_x: float = 0.0) -> Node3D:
	if not _prop_scenes.has(kind):
		_prop_scenes[kind] = load(OLD_MODELS.get(kind, PROP_DIR + kind + ".glb"))
	var scene: PackedScene = _prop_scenes[kind]
	var y := _floor_y(pos.x, pos.y, pos.z) if snap_floor else pos.y
	var body := StaticBody3D.new()
	body.position = Vector3(pos.x, y, pos.z)
	body.rotation_degrees = Vector3(rot_x, rot_y, 0.0)
	_root.add_child(body)
	if scene:
		body.add_child(scene.instantiate())
	if kind in NO_COLLIDE:
		return body
	var sz: Vector3 = PROP_SIZE.get(kind, Vector3(0.5, 0.5, 0.5))
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = sz
	cs.shape = bs
	cs.position.y = sz.y * 0.5
	body.add_child(cs)
	return body


func _note(node_name: String, pos: Vector3, rot_y: float, prompt: String, f_name: String, body_txt: String, flat: bool = false) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.rotation_degrees = Vector3(-90.0 if flat else 0.0, rot_y, 0.0)
	body.set_script(INTERACT_SCRIPT)
	body.set("prompt_text", prompt)
	body.set("interaction_type", "note")
	body.set("file_name", f_name)
	body.set("body_text", body_txt)
	_root.add_child(body)
	var paper := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.28, 0.34, 0.015)
	paper.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.88, 0.82, 0.64)
	pmat.roughness = 0.85
	paper.material_override = pmat
	body.add_child(paper)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.45, 0.45, 0.25)
	col.shape = shape
	body.add_child(col)


func _wet_patch(pos: Vector3, size_xz: Vector2, rot_y: float = 0.0) -> void:
	var y := _floor_y(pos.x, pos.y, pos.z)
	var pmat := StandardMaterial3D.new()
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.albedo_color = Color(0.07, 0.07, 0.05, 0.72)
	pmat.roughness = 0.08
	pmat.metallic = 0.25
	for i in 2:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.5
		cm.bottom_radius = 0.5
		cm.height = 0.008
		cm.radial_segments = 12
		mi.mesh = cm
		mi.material_override = pmat
		var s := 1.0 if i == 0 else 0.72
		mi.scale = Vector3(size_xz.x * s, 1.0, size_xz.y * s)
		mi.position = Vector3(pos.x + (0.22 if i == 1 else 0.0), y + 0.006 + i * 0.002, pos.z - (0.18 if i == 1 else 0.0))
		mi.rotation_degrees.y = rot_y + i * 38.0
		_root.add_child(mi)


func _accent_light(pos: Vector3, col: Color, energy: float, rng: float) -> void:
	var omni := OmniLight3D.new()
	omni.position = pos
	omni.light_color = col
	omni.light_energy = energy
	omni.omni_range = rng
	omni.shadow_enabled = false  # 嚴格控制即時陰影數量，補光一律不開陰影
	_root.add_child(omni)


# --- 傳送點 38：地圖 高層 1（x51, y22.74, z134）---
func _build_wp38() -> void:
	var base_y := 22.74

	# 1) 東側牆凹槽：廢棄的 M.E.G. 臨時觀察點（貼齊東側實際牆面）
	var east_hit := _wall_hit(Vector3(51.0, base_y + 0.8, 134.0), Vector3.RIGHT, 10.0)
	if not east_hit.is_empty():
		var wx: float = (east_hit["position"] as Vector3).x
		var fy := _floor_y(wx - 0.8, base_y, 134.0)
		_prop("desk", Vector3(wx - 0.55, fy, 134.0), -90.0, false)
		_prop("coffee_machine", Vector3(wx - 0.48, fy + 0.76, 134.48), -70.0, false)
		_prop("chair", Vector3(wx - 1.32, fy, 134.05), 112.0, false)
		_prop("trashcan", Vector3(wx - 0.55, fy, 135.1), 15.0, false)
		_prop("floor_lamp", Vector3(wx - 0.45, fy, 132.75), 25.0, false)
		_accent_light(Vector3(wx - 0.55, fy + 1.55, 132.75), Color(1.0, 0.84, 0.55), 0.55, 4.5)
		_note(
			"WP38_DeskNote",
			Vector3(wx - 0.68, fy + 0.77, 134.18),
			-82.0,
			"閱讀桌上的 M.E.G. 觀察筆記",
			"高層觀察點 #38 紀錄",
			"【M.E.G. 高層巡檢紀錄 — 第 38 號點位】\n"
			+ "這處高層走廊的地板總是帶著一點潮氣，但上面並沒有管線。\n"
			+ "我們試著關掉走廊北側的配電箱，頭頂的日光燈依然在響——\n"
			+ "嗡嗡聲其實是從腳底下的那一層傳上來的。\n\n"
			+ "※ 若你在低矮樑柱後方聽到腳步聲，請立刻往南側或西側撤離。",
			true
		)

	# 2) 南側後方凹槽（傳送點正後方）：堆放的物資與舊檔案架
	var south_hit := _wall_hit(Vector3(51.0, base_y + 0.8, 134.0), Vector3.BACK, 10.0)
	if not south_hit.is_empty():
		var sz: float = (south_hit["position"] as Vector3).z
		_prop("shelf_small", Vector3(50.2, base_y, sz - 0.48), 180.0)
		var sy := _floor_y(50.2, base_y, sz - 0.48)
		_prop("box_closed", Vector3(49.85, sy + 0.52, sz - 0.48), 12.0, false)
		_prop("cardboard_boxes", Vector3(51.8, base_y, sz - 0.65), -18.0)
		_prop("pallet", Vector3(51.7, base_y, sz - 1.55), 8.0)
		_prop("barrel", Vector3(48.8, base_y, sz - 0.55), 35.0)

	# 3) 北側走廊：漏水積水、梯子與西側牆配電箱
	_wet_patch(Vector3(49.6, base_y, 125.2), Vector2(2.3, 1.8), 14.0)
	_prop("bucket", Vector3(49.55, base_y, 125.15), 22.0)

	var west_hit := _wall_hit(Vector3(51.0, base_y + 1.2, 127.5), Vector3.LEFT, 10.0)
	if not west_hit.is_empty():
		var wwx: float = (west_hit["position"] as Vector3).x
		_prop("breaker_box", Vector3(wwx + 0.08, base_y + 1.35, 127.5), 90.0, false)
		_prop("ladder", Vector3(wwx + 0.42, base_y, 129.0), 90.0, true, -10.0)
		_note(
			"WP38_WallNote",
			Vector3(wwx + 0.03, base_y + 1.35, 126.75),
			90.0,
			"查看牆上的檢修便條",
			"配電箱檢修便條",
			"【維修組留】\n這座配電箱已經斷開主迴路了，別再浪費時間拉閘。\n"
			+ "天花板滲水點（北側樑下）的水桶每兩小時就會滿一次，但樓上沒有水塔。"
		)
