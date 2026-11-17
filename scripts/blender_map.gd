extends Node3D
# 從 Blender 匯出的 gm_br_pitfalls 地圖（assets/models/blender_map.glb，約 487×397×219 m）。
# 放在 Level0 遠東側（x ≥ 483），執行時才載入、才生成碰撞，避免把幾何寫進 .tscn。
# 入口：地圖(M)傳送清單 37+。Blender 原點 = 此節點原點，Blender Z 向上 → Godot Y。

const MAP_PATH := "res://assets/models/blender_map.glb"
const ORIGIN := Vector3(700.0, 0.0, 0.0)  # Level0 最東約 x=100，錯開避免重疊


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var scene := load(MAP_PATH) as PackedScene
	if scene == null:
		push_warning("blender_map.glb 載入失敗")
		return
	var inst := scene.instantiate() as Node3D
	inst.position = ORIGIN
	add_child(inst)
	_add_collision(inst)
	# 去程：校舍翼空房北牆（x78, z196）；回程：地圖街道起點背後
	_make_door(Vector3(78.0, -2.0, 195.85), "推開藍色的門（前往另一個地方）", ORIGIN + Vector3(0, 1.4, 0), -0.6)
	_make_door(ORIGIN + Vector3(0, 1.3, 3.0), "推開藍色的門（回到 Level 0）", Vector3(78.0, -1.95, 191.5), 0.0)


# 發光藍色門板 + 門框；E 互動 → portal 傳送
func _make_door(pos: Vector3, prompt: String, target: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.set_script(load("res://scripts/interactable_prop.gd"))
	body.set("prompt_text", prompt)
	body.set("interaction_type", "portal")
	body.set("portal_pos", target)
	body.set("portal_yaw", yaw)
	add_child(body)
	var slab := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.4, 2.3, 0.1)
	slab.mesh = bm
	slab.position.y = 1.15
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.45, 0.9)
	m.emission_enabled = true
	m.emission = Color(0.3, 0.5, 1.0)
	m.emission_energy_multiplier = 1.4
	slab.material_override = m
	body.add_child(slab)
	var frame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(1.7, 2.5, 0.06)
	frame.mesh = fm
	frame.position = Vector3(0, 1.25, 0.03)
	var m2 := StandardMaterial3D.new()
	m2.albedo_color = Color(0.1, 0.1, 0.12)
	frame.material_override = m2
	body.add_child(frame)
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.4, 2.3, 0.3)
	col.shape = sh
	col.position.y = 1.15
	body.add_child(col)


# 進入本地圖後接管環境（霧淡、環境光偏冷）；離開後交還給 Level0 的區域腳本
func _process(_delta: float) -> void:
	var player := get_parent().get_node_or_null("Player") as Node3D
	var we := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if player == null or we == null or we.environment == null or player.position.x < 400.0:
		return
	var env := we.environment
	env.fog_light_color = Color(0.16, 0.17, 0.2)
	env.fog_density = 0.01
	env.ambient_light_color = Color(0.55, 0.57, 0.64)
	env.ambient_light_energy = 0.32


func _add_collision(n: Node) -> void:
	for c in n.get_children():
		_add_collision(c)
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		(n as MeshInstance3D).create_trimesh_collision()
