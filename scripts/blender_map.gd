extends Node3D
# 從 Blender 匯出的 gm_br_pitfalls 地圖（assets/models/blender_map.glb，約 487×397×219 m）。
# 接在校舍翼空房東側通道盡頭（x≥109），執行時才載入、才生成碰撞，避免把幾何寫進 .tscn。
# 入口：空房東牆 → 通道 x92..126 → 街道廣場 (x≥124, z 164..234)。Blender 原點 = 此節點原點，Blender Z 向上 → Godot Y。

const MAP_PATH := "res://assets/models/blender_map.glb"
const ORIGIN := Vector3(135.0, -3.22, 186.0)  # 街道起點 (map 0,0) 對齊空房地板 y=-2；x≥109 避開 Level0


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
	# 走廊末端與廣場的導航網格之間有 ~2 m 烘不起來的縫（門口立柱），用連結補上，怪物才走得進來
	var link := NavigationLink3D.new()
	link.bidirectional = true
	link.start_position = Vector3(128.0, -1.6, 186.0)
	link.end_position = Vector3(131.5, -1.6, 186.0)
	add_child(link)


# 靠近/進入本地圖後接管環境（霧淡、環境光偏冷）：x 100→124 漸變，離開後交還給 Level0 的區域腳本
func _process(delta: float) -> void:
	var player := get_parent().get_node_or_null("Player") as Node3D
	var we := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if player == null or we == null or we.environment == null:
		return
	var w := clampf((player.position.x - 100.0) / 24.0, 0.0, 1.0)
	if w <= 0.0:
		return
	var t := 1.0 if w >= 1.0 else clampf(w * delta * 6.0, 0.0, 1.0)
	var env := we.environment
	env.fog_light_color = env.fog_light_color.lerp(Color(0.16, 0.17, 0.2), t)
	env.fog_density = lerpf(env.fog_density, 0.01, t)
	env.ambient_light_color = env.ambient_light_color.lerp(Color(0.55, 0.57, 0.64), t)
	env.ambient_light_energy = lerpf(env.ambient_light_energy, 0.55, t)


# 碰撞：每個三角形正反面各放一份。Blender/Source 的地板法線方向不可靠，
# 導航烘焙只認朝上的面，單面碰撞會讓整張地圖烘不出可走區域（怪物進不來）。
func _add_collision(n: Node) -> void:
	for c in n.get_children():
		_add_collision(c)
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var faces := (n as MeshInstance3D).mesh.get_faces()
		var both := PackedVector3Array()
		both.resize(faces.size() * 2)
		for i in range(0, faces.size(), 3):
			both[i * 2] = faces[i]
			both[i * 2 + 1] = faces[i + 1]
			both[i * 2 + 2] = faces[i + 2]
			both[i * 2 + 3] = faces[i + 2]
			both[i * 2 + 4] = faces[i + 1]
			both[i * 2 + 5] = faces[i]
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(both)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		n.add_child(body)
