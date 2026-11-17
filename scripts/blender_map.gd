extends Node3D
# 從 Blender 匯出的 gm_br_pitfalls 地圖（assets/models/blender_map.glb，約 487×397×219 m）。
# 接在校舍翼空房東側通道盡頭（x≥109），執行時才載入、才生成碰撞，避免把幾何寫進 .tscn。
# 入口：空房東牆 → 通道 x92..126 → 街道廣場 (x≥124, z 164..234)。Blender 原點 = 此節點原點，Blender Z 向上 → Godot Y。

const MAP_PATH := "res://assets/models/blender_map.glb"
const LIGHTS_PATH := "res://assets/models/blender_map_lights.json"
const POOL_SIZE := 32          # 同時亮的燈上限（全場 2274 盞 Source 燈，只讓玩家附近的亮）
const LIGHT_RADIUS := 40.0     # 只考慮這個距離內的燈
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
	_style_materials(inst)
	_add_collision(inst)
	# 走廊末端與廣場的導航網格之間有 ~2 m 烘不起來的縫（門口立柱），用連結補上，怪物才走得進來
	var link := NavigationLink3D.new()
	link.bidirectional = true
	link.start_position = Vector3(128.0, -1.6, 186.0)
	link.end_position = Vector3(131.5, -1.6, 186.0)
	add_child(link)
	_load_lights.call_deferred()


# 靠近/進入本地圖後接管環境（霧淡、環境光偏冷）：x 100→124 漸變，離開後交還給 Level0 的區域腳本
func _process(delta: float) -> void:
	var player := get_parent().get_node_or_null("Player") as Node3D
	var we := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if player == null or we == null or we.environment == null:
		return
	if not _pool.is_empty():
		_update_lights(delta, player.global_position if player.position.x > 90.0 else Vector3(-9999, -9999, -9999))
	var w := clampf((player.position.x - 100.0) / 24.0, 0.0, 1.0)
	if w <= 0.0:
		return
	var t := 1.0 if w >= 1.0 else clampf(w * delta * 6.0, 0.0, 1.0)
	var env := we.environment
	env.fog_light_color = env.fog_light_color.lerp(Color(0.16, 0.17, 0.2), t)
	env.fog_density = lerpf(env.fog_density, 0.01, t)
	env.ambient_light_color = env.ambient_light_color.lerp(Color(0.55, 0.57, 0.64), t)
	env.ambient_light_energy = lerpf(env.ambient_light_energy, 0.4, t)


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


# --- 材質：PS1 風格（最近鄰取樣、無法線/高光），日光天空盒隱藏，日光燈管自發光 ---
func _style_materials(n: Node) -> void:
	for c in n.get_children():
		_style_materials(c)
	var mi := n as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(i) as StandardMaterial3D
		if m == null:
			continue
		var nm := m.resource_name.to_upper()
		if nm.contains("SKY") and not nm.contains("SKYSCRAPER") and not nm.contains("SKYPLASTER"):
			mi.set_surface_override_material(i, _invisible())
			continue
		var d := m.duplicate() as StandardMaterial3D
		d.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		d.normal_enabled = false
		d.metallic = 0.0
		d.metallic_specular = 0.1
		d.roughness = 1.0
		if d.albedo_texture == null:
			_fill_missing(d, nm)
		if nm.contains("FLOULIGHT") and not nm.contains("OFF"):
			d.emission_enabled = true
			d.emission = Color(1.0, 0.95, 0.75)
			d.emission_energy_multiplier = 1.6
			d.emission_texture = d.albedo_texture
		mi.set_surface_override_material(i, d)


func _invisible() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0, 0, 0, 0)
	return m


# --- 光照：Blender 的燈匯出成 JSON，玩家附近挑 POOL_SIZE 盞，淡入淡出切換，一律不開陰影 ---
var _src: Array = []           # [x,y,z,r,g,b,watt,spot]（已加 ORIGIN）
var _pool: Array[OmniLight3D] = []
var _slot_src: Array[int] = []  # 每個槽目前對應的來源索引，-1 = 閒置
var _slot_goal: Array[float] = []
var _scan_t := 0.0


func _load_lights() -> void:
	var f := FileAccess.open(LIGHTS_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if data is Array:
		for e in data:
			_src.append([e[0] + ORIGIN.x, e[1] + ORIGIN.y, e[2] + ORIGIN.z, e[3], e[4], e[5], e[6], e[7]])
	for i in POOL_SIZE:
		var l := OmniLight3D.new()
		l.shadow_enabled = false
		l.light_energy = 0.0
		l.omni_attenuation = 1.3
		add_child(l)
		_pool.append(l)
		_slot_src.append(-1)
		_slot_goal.append(0.0)


func _update_lights(delta: float, ppos: Vector3) -> void:
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.3
		var near: Array = []
		var r2 := LIGHT_RADIUS * LIGHT_RADIUS
		for i in _src.size():
			var e: Array = _src[i]
			var dx: float = e[0] - ppos.x
			var dy: float = e[1] - ppos.y
			var dz: float = e[2] - ppos.z
			var d2 := dx * dx + dy * dy * 4.0 + dz * dz  # 上下樓層的燈權重加倍，避免隔層透光
			if d2 < r2:
				near.append([d2, i])
		near.sort_custom(func(a, b): return a[0] < b[0])
		if near.size() > POOL_SIZE:
			near.resize(POOL_SIZE)
		var want := {}
		for p in near:
			want[p[1]] = true
		for s in POOL_SIZE:
			_slot_goal[s] = 0.0
			var si := _slot_src[s]
			if si >= 0 and want.has(si):
				_slot_goal[s] = _energy_of(si)
				want.erase(si)
		for s in POOL_SIZE:
			if want.is_empty():
				break
			if _slot_src[s] < 0 or (_slot_goal[s] == 0.0 and _pool[s].light_energy < 0.03):
				var ni: int = want.keys()[0]
				want.erase(ni)
				_slot_src[s] = ni
				var e: Array = _src[ni]
				_pool[s].position = Vector3(e[0], e[1], e[2])
				_pool[s].light_color = Color(e[3], e[4], e[5])
				_pool[s].omni_range = clampf(sqrt(e[6]) * 0.6, 6.0, 28.0)
				_slot_goal[s] = _energy_of(ni)
	var k := clampf(delta * 5.0, 0.0, 1.0)
	for s in POOL_SIZE:
		_pool[s].light_energy = lerpf(_pool[s].light_energy, _slot_goal[s], k)


func _energy_of(i: int) -> float:
	return clampf(0.9 + float(_src[i][6]) / 2000.0, 1.0, 3.0)


# --- 原圖缺貼圖的材質（Half-Life 2 內建貼圖，沒附在地圖包裡）：依名稱用程式生成的小圖補上 ---
var _proc_cache := {}


func _fill_missing(m: StandardMaterial3D, nm: String) -> void:
	m.albedo_color = Color.WHITE
	if nm.contains("GLASS") or nm.contains("WINDOW"):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.62, 0.74, 0.8, 0.28)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		return
	if nm.contains("TOOLSBLACK"):
		m.albedo_color = Color(0.02, 0.02, 0.02)
		return
	var real := _local_tex(nm)
	var kind := "concrete"
	if nm.contains("BRICK"):
		kind = "brick"
	elif nm.contains("CLIFF") or nm.contains("DIRT") or nm.contains("DEBRIS"):
		kind = "rock"
	elif nm.contains("GRASS"):
		kind = "grass"
	elif nm.contains("WOOD"):
		kind = "wood"
	elif nm.contains("TILE"):
		kind = "tile"
	elif nm.contains("FLUORESCENT"):
		kind = "light"
	elif nm.contains("WHITE") or nm.contains("PLASTER"):
		kind = "plaster"
	elif nm.contains("METAL") or nm.contains("CITADEL") or nm.contains("DOORBUTTON") or nm.contains("DUCT"):
		kind = "metal"
	m.albedo_texture = real if real else _proc_tex(kind)
	if kind == "light":
		m.emission_enabled = true
		m.emission = Color(1.0, 0.97, 0.85)
		m.emission_energy_multiplier = 1.4
		m.emission_texture = m.albedo_texture


func _proc_tex(kind: String) -> ImageTexture:
	if _proc_cache.has(kind):
		return _proc_cache[kind]
	var n := 64
	var img := Image.create(n, n, true, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	for y in n:
		for x in n:
			var c := Color.WHITE
			var j := rng.randf_range(-1.0, 1.0)
			match kind:
				"brick":
					var row := y / 8
					var bx := (x + (8 if row % 2 == 1 else 0)) % 16
					c = Color(0.36, 0.34, 0.31) if (y % 8 == 0 or bx == 0) else Color(0.55, 0.27, 0.2).lerp(Color(0.42, 0.2, 0.16), float((row * 7 + (x + (8 if row % 2 == 1 else 0)) / 16) % 3) / 2.0)
					c = c * (1.0 + j * 0.06)
				"rock":
					c = Color(0.38, 0.34, 0.29) * (1.0 + j * 0.22 + sin(x * 0.4 + y * 0.2) * 0.08)
				"grass":
					c = Color(0.22, 0.38, 0.14) * (1.0 + j * 0.25)
				"wood":
					c = Color(0.5, 0.34, 0.18) * (1.0 + sin(y * 1.1 + j * 0.8) * 0.14 + j * 0.05)
				"tile":
					c = Color(0.52, 0.55, 0.55) * (1.0 + j * 0.04)
					if x % 16 == 0 or y % 16 == 0:
						c = Color(0.3, 0.32, 0.32)
				"light":
					c = Color(0.95, 0.95, 0.9) * (1.0 + j * 0.02)
				"plaster":
					c = Color(0.82, 0.8, 0.74) * (1.0 + j * 0.05)
				"metal":
					c = Color(0.42, 0.44, 0.45) * (1.0 + sin(x * 0.9) * 0.05 + j * 0.07)
				_:
					c = Color(0.5, 0.5, 0.48) * (1.0 + j * 0.12)
			img.set_pixel(x, y, Color(clampf(c.r, 0.0, 1.0), clampf(c.g, 0.0, 1.0), clampf(c.b, 0.0, 1.0)))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_proc_cache[kind] = t
	return t


# 自製貼圖（tools/map_textures/gen.py 生成，原創圖樣）：assets/textures/map_fill/<材質名>.png
func _local_tex(nm: String) -> Texture2D:
	var path := "res://assets/textures/map_fill/%s.png" % nm
	return load(path) as Texture2D if ResourceLoader.exists(path) else null
