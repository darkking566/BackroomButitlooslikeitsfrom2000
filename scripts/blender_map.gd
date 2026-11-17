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
