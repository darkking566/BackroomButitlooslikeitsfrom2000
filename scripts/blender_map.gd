extends Node3D
# 從 Blender 匯出的 gm_br_pitfalls 地圖（assets/models/blender_map.glb，約 487×397×219 m）。
# 接在校舍翼空房東側通道盡頭（x≥109），執行時才載入、才生成碰撞，避免把幾何寫進 .tscn。
# 入口：空房東牆 → 通道 x92..126 → 街道廣場 (x≥124, z 164..234)。Blender 原點 = 此節點原點，Blender Z 向上 → Godot Y。

const MAP_PATH := "res://assets/models/blender_map.glb"
const INTERACTIVES_PATH := "res://assets/models/blender_map_interactives.json"
const LIGHTS_PATH := "res://assets/models/blender_map_lights.json"
const DIM_KILL_DIST := 7.0     # 怪物周圍這個距離內的燈熄滅
const DIM_FLICKER_DIST := 15.0 # 這個距離內開始亂閃
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
	_load_interactives()
	_style_materials(inst)
	_add_collision(inst)
	_setup_interactives(inst)
	# 走廊末端與廣場的導航網格之間有 ~2 m 烘不起來的縫（門口立柱），用連結補上，怪物才走得進來
	var link := NavigationLink3D.new()
	link.bidirectional = true
	link.start_position = Vector3(128.0, -1.6, 186.0)
	link.end_position = Vector3(131.5, -1.6, 186.0)
	add_child(link)
	_load_lights.call_deferred()
	_init_street_audio()


# 靠近/進入本地圖後接管環境（霧淡、環境光偏冷）：x 100→124 漸變，離開後交還給 Level0 的區域腳本
func _process(delta: float) -> void:
	var player := get_parent().get_node_or_null("Player") as Node3D
	var we := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if player == null or we == null or we.environment == null:
		return
	# 掉出地圖（最低的地面約 y=-111）：送回街道廣場
	if player.position.x > 105.0 and player.position.y < -140.0:
		player.call("_on_teleport_requested", Vector3(136.0, -1.95, 175.0), -PI * 0.5)
		return
	_update_street_audio(delta, player)
	if not _pool.is_empty():
		_update_lights(delta, player.global_position if player.position.x > 90.0 else Vector3(-9999, -9999, -9999))
	var w := clampf((player.position.x - 100.0) / 24.0, 0.0, 1.0)
	if w <= 0.0:
		return
	var t := 1.0 if w >= 1.0 else clampf(w * delta * 6.0, 0.0, 1.0)
	var env := we.environment
	env.fog_light_color = env.fog_light_color.lerp(Color(0.07, 0.075, 0.09), t)
	env.fog_density = lerpf(env.fog_density, 0.01, t)
	env.ambient_light_color = env.ambient_light_color.lerp(Color(0.55, 0.57, 0.64), t)
	# 環境光跟「附近有沒有亮著的燈」走：燈下 0.28，離燈 14 m 以上降到 0.05（不開手電筒幾乎看不見）；
	# 戶外（地面層）保底 0.14 當月光
	var base := lerpf(0.05, 0.28, _lit)
	if player.position.y > -10.0 and player.position.y < 12.0:
		base = maxf(base, 0.14)
	_amb = lerpf(_amb, base, clampf(delta * 2.0, 0.0, 1.0))
	env.ambient_light_energy = lerpf(env.ambient_light_energy, _amb, t)


# 碰撞：每個材質面各一個靜態體，三角形正反面各放一份（Blender/Source 的地板法線方向不可靠，
# 導航烘焙只認朝上的面，單面碰撞會讓整張地圖烘不出可走區域）。依材質名稱設定腳步聲種類。
func _add_collision(n: Node) -> void:
	for c in n.get_children():
		_add_collision(c)
	var mi := n as MeshInstance3D
	if mi == null or mi.mesh == null or _ia.has(String(mi.name)):
		return
	for i in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(i)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx := PackedInt32Array()
		if arr[Mesh.ARRAY_INDEX] != null:
			idx = arr[Mesh.ARRAY_INDEX]
		var faces := PackedVector3Array()
		var use_idx := idx.size() > 0
		var tri_count: int = idx.size() if use_idx else verts.size()
		faces.resize(tri_count * 2)
		for t in range(0, tri_count, 3):
			var a0: Vector3
			var a1: Vector3
			var a2: Vector3
			if use_idx:
				a0 = verts[idx[t]]
				a1 = verts[idx[t + 1]]
				a2 = verts[idx[t + 2]]
			else:
				a0 = verts[t]
				a1 = verts[t + 1]
				a2 = verts[t + 2]
			faces[t * 2] = a0
			faces[t * 2 + 1] = a1
			faces[t * 2 + 2] = a2
			faces[t * 2 + 3] = a2
			faces[t * 2 + 4] = a1
			faces[t * 2 + 5] = a0
		if faces.is_empty():
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		var m := mi.mesh.surface_get_material(i)
		body.set_meta("step_stream", _step_for(m.resource_name.to_upper() if m else ""))
		n.add_child(body)


# --- 腳步聲：依材質名稱挑種類（程式生成，同種類共用一個串流）---
var _step_cache := {}


func _step_for(nm: String) -> AudioStream:
	var kind := "concrete"
	if nm.contains("CARPET"):
		kind = "carpet"
	elif nm.contains("GRASS") or nm.contains("DIRT") or nm.contains("MOSS"):
		kind = "grass"
	elif nm.contains("WOOD") or nm.contains("PLANK") or nm.contains("BOARD") or nm.contains("PARQUET"):
		kind = "wood"
	elif nm.contains("TILE") or nm.contains("CERAMIC") or nm.contains("MARBLE") or nm.contains("KITCHEN"):
		kind = "tile"
	elif nm.contains("METAL") or nm.contains("GRATE") or nm.contains("CITADEL") or nm.contains("STEEL"):
		kind = "metal"
	elif nm.contains("GRAVEL") or nm.contains("CLIFF") or nm.contains("ROCK"):
		kind = "gravel"
	if not _step_cache.has(kind):
		_step_cache[kind] = BackroomsAudio.create_carpet_footstep_stream() if kind == "carpet" else _step_stream(kind)
	return _step_cache[kind]


func _step_stream(kind: String) -> AudioStreamWAV:
	# [噪音低通係數, 噪音衰減, 音調Hz, 音調量, 音調衰減, 起音秒數, 噪音量]
	var tbl := {
		"concrete": [0.30, 38.0, 95.0, 0.55, 30.0, 0.002, 0.9],
		"grass": [0.07, 20.0, 70.0, 0.2, 25.0, 0.02, 0.8],
		"wood": [0.18, 30.0, 150.0, 0.9, 22.0, 0.002, 0.45],
		"tile": [0.75, 50.0, 330.0, 0.25, 40.0, 0.001, 0.9],
		"metal": [0.55, 32.0, 760.0, 0.5, 14.0, 0.001, 0.7],
		"gravel": [0.9, 16.0, 60.0, 0.15, 25.0, 0.001, 1.0],
	}
	var p: Array = tbl[kind]
	var n := int(22050 * 0.32)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var x := PackedFloat32Array()
	x.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / 22050.0
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), p[0])
		var att := minf(1.0, t / maxf(p[5], 0.0005))
		var v: float = lp * exp(-t * p[1]) * p[6] + sin(TAU * p[2] * t) * exp(-t * p[4]) * p[3]
		if kind == "gravel":
			v *= 0.6 + 0.4 * sin(TAU * 38.0 * t)  # 沙沙的顆粒感
		x[i] = v * att
	return _wav(x, false)


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
var _amb := 0.14
var _lit := 0.0               # 0..1：玩家離最近一盞「亮著的燈」有多近
var _dimmed := {}              # 來源索引 -> 剩餘熄滅秒數


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
		_lit = 0.0
		for p in near:
			if not _dimmed.has(p[1]):
				_lit = clampf(1.0 - sqrt(p[0]) / 14.0, 0.0, 1.0)
				break
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
	var mon := get_parent().get_node_or_null("Monster") as Node3D
	for si in _dimmed.keys():
		_dimmed[si] -= delta
		if _dimmed[si] <= 0.0:
			_dimmed.erase(si)
	for s in POOL_SIZE:
		var si := _slot_src[s]
		var mult := 1.0
		if si >= 0 and mon != null:
			var e: Array = _src[si]
			var d := Vector3(e[0], e[1], e[2]).distance_to(mon.global_position)
			if d < DIM_KILL_DIST:
				_dimmed[si] = randf_range(10.0, 15.0)  # 牠經過的燈延遲 10–15 秒才復電（同 Level0）
			elif d < DIM_FLICKER_DIST and randf() < 0.02 and not _dimmed.has(si):
				_dimmed[si] = 0.25  # 牠接近時燈亂閃，預告牠快到了
		if si >= 0 and _dimmed.has(si):
			mult = 0.0
			if _dimmed[si] < 1.5 and randf() < 0.45:
				mult = 1.0  # 復電前先閃幾下
		_pool[s].light_energy = lerpf(_pool[s].light_energy, _slot_goal[s] * mult, maxf(k, 0.5) if mult == 0.0 else k)


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


# --- 街道氛圍音效（程式生成）：風、夜蟲、偶爾遠處的金屬聲/車聲。只在街道（地面層）響，Level0 的日光燈嗡聲同時壓低 ---
const WIND_DB := -22.0
const INSECT_DB := -29.0
const FAR_DB := -20.0
const HUM_DB := -15.5
var _wind: AudioStreamPlayer
var _insects: AudioStreamPlayer
var _far: AudioStreamPlayer
var _far_streams: Array[AudioStreamWAV] = []
var _far_t := 12.0
var _street_w := 0.0
var _hum_ducked := false
var _hush := 0.0                # 被抓後街道聲音安靜的剩餘秒數
var _caught: AudioStreamPlayer


func _init_street_audio() -> void:
	_wind = _mk_player(_wind_stream(), -80.0)
	_insects = _mk_player(_insect_stream(), -80.0)
	_far = AudioStreamPlayer.new()
	add_child(_far)
	_far_streams = [_clang_stream(), _engine_stream()]
	_caught = _mk_player(_caught_stream(), -3.0)


func _mk_player(st: AudioStreamWAV, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.volume_db = db
	add_child(p)
	return p


func _update_street_audio(delta: float, player: Node3D) -> void:
	# 街道 = 地面層（y -10..12）且已走出走廊（x 110→130 漸入）
	var target := 0.0
	if player.position.y > -10.0 and player.position.y < 12.0:
		target = clampf((player.position.x - 110.0) / 20.0, 0.0, 1.0)
	_street_w = lerpf(_street_w, target, clampf(delta * 1.5, 0.0, 1.0))
	var mon := get_parent().get_node_or_null("Monster") as Node3D
	var quiet := 1.0
	if mon != null:
		quiet = clampf((mon.global_position.distance_to(player.global_position) - 8.0) / 14.0, 0.0, 1.0)  # 怪物靠近時蟲鳴停下
	_hush = maxf(0.0, _hush - delta)
	if _hush > 0.0:
		quiet = 0.0
	var on := _street_w > 0.01
	for pl in [_wind, _insects]:
		if on and not pl.playing:
			pl.play()
		elif not on and pl.playing:
			pl.stop()
	_wind.volume_db = linear_to_db(maxf(_street_w * (0.0 if _hush > 0.0 else 1.0), 0.0001)) + WIND_DB
	_insects.volume_db = linear_to_db(maxf(_street_w * quiet, 0.0001)) + INSECT_DB
	var hum := get_parent().get_node_or_null("AmbientHum") as AudioStreamPlayer
	if hum != null:
		if _street_w > 0.01:
			hum.volume_db = lerpf(HUM_DB, -40.0, _street_w)
			_hum_ducked = true
		elif _hum_ducked:
			hum.volume_db = HUM_DB
			_hum_ducked = false
	if on:
		_far_t -= delta
		if _far_t <= 0.0:
			_far_t = randf_range(22.0, 55.0)
			_far.stream = _far_streams.pick_random()
			_far.volume_db = FAR_DB + linear_to_db(_street_w)
			_far.pitch_scale = randf_range(0.85, 1.15)
			_far.play()


func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var n := samples.size()
	var peak := 0.0001
	for v in samples:
		peak = maxf(peak, absf(v))
	var b := PackedByteArray()
	b.resize(n * 2)
	for i in n:
		b.encode_s16(i * 2, int(clampf(samples[i] / peak * 0.8, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 22050
	w.stereo = false
	w.data = b
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w


# 首尾交叉淡化成可無縫循環的長度 n
func _loopable(x: PackedFloat32Array, n: int, fade: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = x[i]
	for i in fade:
		out[i] = lerpf(x[n + i], x[i], float(i) / float(fade))
	return out


func _wind_stream() -> AudioStreamWAV:
	var n := 22050 * 8
	var fade := 22050
	var rng := RandomNumberGenerator.new()
	rng.seed = 7311
	var x := PackedFloat32Array()
	x.resize(n + fade)
	var a := 0.0
	var b := 0.0
	for i in n + fade:
		var t := float(i) / 22050.0
		a = lerpf(a, rng.randf_range(-1.0, 1.0), 0.03)
		b = lerpf(b, a, 0.1)
		var gust := 0.55 + 0.3 * sin(TAU * t / 8.0 * 1.0 + 0.7) + 0.15 * sin(TAU * t / 8.0 * 3.0)
		x[i] = b * gust
	return _wav(_loopable(x, n, fade), true)


func _insect_stream() -> AudioStreamWAV:
	var n := 22050 * 6
	var rng := RandomNumberGenerator.new()
	rng.seed = 9201
	var x := PackedFloat32Array()
	x.resize(n)
	for g in 22:
		var start := rng.randi_range(0, n - 22050)
		var f := rng.randf_range(3800.0, 5200.0)
		var amp := rng.randf_range(0.3, 1.0)
		var pulses := rng.randi_range(2, 4)
		for p in pulses:
			var p0 := start + p * 1500
			for i in 520:
				var env := sin(PI * float(i) / 520.0)
				var idx := (p0 + i) % n
				x[idx] += amp * env * sin(TAU * f * float(i) / 22050.0)
	return _wav(x, true)


func _clang_stream() -> AudioStreamWAV:
	var n := int(22050 * 2.6)
	var x := PackedFloat32Array()
	x.resize(n)
	var parts := [[212.0, 1.0, 2.2], [347.0, 0.7, 3.0], [563.0, 0.45, 4.0], [911.0, 0.25, 5.5]]
	var lp := 0.0
	for i in n:
		var t := float(i) / 22050.0
		var v := 0.0
		for pr in parts:
			v += pr[1] * sin(TAU * pr[0] * t) * exp(-t * pr[2])
		lp = lerpf(lp, v, 0.35)  # 壓掉高頻 = 聽起來很遠
		x[i] = lp
	return _wav(x, false)


func _engine_stream() -> AudioStreamWAV:
	var n := 22050 * 7
	var rng := RandomNumberGenerator.new()
	rng.seed = 4410
	var x := PackedFloat32Array()
	x.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / 22050.0
		var env := sin(PI * t / 7.0)
		env = env * env
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.05)
		x[i] = env * (lp * 0.5 + 0.6 * sin(TAU * (62.0 + 8.0 * env) * t))
	return _wav(x, false)


# --- 門與按鈕互動：Blender 的 func_door / func_door_rotating / func_button（只有帶幾何的 13 個；
#     其餘約 150 個在匯入時就沒有模型）。資料見 blender_map_interactives.json ---
const LINKS := {"OutpostDoorButton": "ThresholdBarricade"}  # 按鈕 -> 它開的門（依名稱推定）
var _ia := {}                  # 節點名 -> 設定
var _ia_body := {}             # 節點名 -> 互動體
var _sfx := {}


func _load_interactives() -> void:
	var f := FileAccess.open(INTERACTIVES_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if data is Array:
		for e in data:
			_ia[String(e["n"])] = e
	_sfx = {"click": _click_stream(), "slide": _slide_stream(), "creak": _creak_stream()}


func _setup_interactives(root: Node) -> void:
	for nm in _ia.keys():
		var mi := root.find_child(nm, true, false) as MeshInstance3D
		if mi == null:
			continue
		var e: Dictionary = _ia[nm]
		var parent := mi.get_parent()
		var body := AnimatableBody3D.new()
		body.name = "IA_" + nm
		body.set_script(load("res://scripts/interactable_prop.gd"))
		body.transform = mi.transform
		parent.add_child(body)
		parent.remove_child(mi)
		body.add_child(mi)
		mi.transform = Transform3D.IDENTITY
		var cs := CollisionShape3D.new()
		cs.shape = mi.mesh.create_convex_shape(true, true)
		body.add_child(cs)
		var snd := AudioStreamPlayer3D.new()
		snd.max_distance = 30.0
		snd.unit_size = 4.0
		body.add_child(snd)
		var kind: String = e["k"]
		var st := {"open": false, "busy": false, "home": body.position, "rot": body.rotation.y, "snd": snd}
		_ia_body[nm] = st
		var d := Vector3(e["dir"][0], e["dir"][1], e["dir"][2]).normalized()
		if kind == "func_button":
			body.set("prompt_text", "按下按鈕")
			body.set_meta("on_interact", func(pl: Node) -> void: _press(nm, body, mi, pl))
		elif kind == "func_door_rotating":
			body.set("prompt_text", "開門")
			body.set_meta("on_interact", func(_pl: Node) -> void: _toggle_rot(nm, body, float(e["dist"])))
		else:
			body.set("prompt_text", "打開" if float(e["ext"]) < 1.0 else "開門")
			body.set_meta("on_interact", func(_pl: Node) -> void: _toggle_slide(nm, body, d, maxf(float(e["ext"]) - float(e["lip"]), 0.08), float(e["speed"]), float(e["wait"])))


func _sound(nm: String, which: String, pitch: float = 1.0) -> void:
	var snd: AudioStreamPlayer3D = _ia_body[nm]["snd"]
	snd.stream = _sfx[which]
	snd.pitch_scale = pitch * randf_range(0.93, 1.07)
	snd.volume_db = -4.0
	snd.play()


func _toggle_slide(nm: String, body: AnimatableBody3D, dir: Vector3, dist: float, speed: float, wait: float) -> void:
	var st: Dictionary = _ia_body[nm]
	if st["busy"]:
		return
	st["busy"] = true
	var opening: bool = not st["open"]
	var dur := clampf(dist / maxf(speed, 0.05), 0.35, 2.5)
	var to: Vector3 = st["home"] + (dir * dist if opening else Vector3.ZERO)
	_sound(nm, "slide" if dist > 0.8 else "creak", 0.8 if dist > 0.8 else 1.0)
	var tw := create_tween()
	tw.tween_property(body, "position", to, dur).set_trans(Tween.TRANS_SINE)
	await tw.finished
	st["open"] = opening
	st["busy"] = false
	body.set("prompt_text", ("關上" if opening else "打開") if dist < 1.0 else ("關門" if opening else "開門"))
	if opening and wait > 0.0:
		await get_tree().create_timer(wait).timeout  # Source 門開著等 wait 秒會自己關
		if st["open"]:
			_toggle_slide(nm, body, dir, dist, speed, wait)


func _toggle_rot(nm: String, body: AnimatableBody3D, degrees: float) -> void:
	var st: Dictionary = _ia_body[nm]
	if st["busy"]:
		return
	st["busy"] = true
	var opening: bool = not st["open"]
	_sound(nm, "creak", 0.9)
	var tw := create_tween()
	tw.tween_property(body, "rotation:y", st["rot"] + (deg_to_rad(-degrees) if opening else 0.0), 0.9).set_trans(Tween.TRANS_SINE)
	await tw.finished
	st["open"] = opening
	st["busy"] = false
	body.set("prompt_text", "關門" if opening else "開門")


func _press(nm: String, body: AnimatableBody3D, mi: MeshInstance3D, pl: Node) -> void:
	var st: Dictionary = _ia_body[nm]
	if st["busy"]:
		return
	st["busy"] = true
	# 沿網格最薄的軸往「遠離玩家」的方向按下
	var box := mi.mesh.get_aabb().size
	var axis := Vector3.RIGHT
	var thin := box.x
	if box.y < thin:
		axis = Vector3.UP
		thin = box.y
	if box.z < thin:
		axis = Vector3.BACK
		thin = box.z
	var world_axis := (body.global_transform.basis * axis).normalized()
	if world_axis.dot(body.global_position - (pl as Node3D).global_position) < 0.0:
		world_axis = -world_axis
	var depth := minf(0.03, maxf(thin * 0.7, 0.01))
	_sound(nm, "click")
	var tw := create_tween()
	tw.tween_property(body, "global_position", body.global_position + world_axis * depth, 0.08)
	tw.tween_interval(0.25)
	tw.tween_property(body, "position", st["home"], 0.15)
	await tw.finished
	st["busy"] = false
	var target: String = LINKS.get(nm, "")
	if target != "" and _ia_body.has(target):
		var e: Dictionary = _ia[target]
		var node := find_child("IA_" + target, true, false) as AnimatableBody3D
		if node != null:
			var d := Vector3(e["dir"][0], e["dir"][1], e["dir"][2]).normalized()
			_toggle_slide(target, node, d, maxf(float(e["ext"]) - float(e["lip"]), 0.08), float(e["speed"]), float(e["wait"]))


func _click_stream() -> AudioStreamWAV:
	var n := int(22050 * 0.12)
	var x := PackedFloat32Array()
	x.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 311
	var lp := 0.0
	for i in n:
		var t := float(i) / 22050.0
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.6)
		x[i] = (lp * 0.7 + sin(TAU * 1700.0 * t) * 0.3) * exp(-t * 70.0) + sin(TAU * 220.0 * t) * exp(-t * 35.0) * 0.5
	return _wav(x, false)


func _slide_stream() -> AudioStreamWAV:
	var n := int(22050 * 1.4)
	var x := PackedFloat32Array()
	x.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5120
	var lp := 0.0
	for i in n:
		var t := float(i) / 22050.0
		var env := sin(PI * t / 1.4)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.08 + 0.05 * env)
		x[i] = env * (lp * 0.8 + sin(TAU * (90.0 + 25.0 * env) * t) * 0.5)
	return _wav(x, false)


func _creak_stream() -> AudioStreamWAV:
	var n := int(22050 * 0.9)
	var x := PackedFloat32Array()
	x.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 877
	var lp := 0.0
	for i in n:
		var t := float(i) / 22050.0
		var env := sin(PI * t / 0.9)
		var f := 260.0 + 140.0 * sin(TAU * 1.6 * t) + 90.0 * env
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.3)
		x[i] = env * (sin(TAU * f * t) * 0.45 + sin(TAU * f * 2.01 * t) * 0.2 + lp * 0.12)
	return _wav(x, false)


# 被怪物抓到：撞擊 + 失真尖嘯 + 低頻餘震，之後街道聲音靜默幾秒（monster.gd 呼叫）
func play_caught() -> void:
	if _caught == null:
		return
	_hush = 3.5
	_caught.play()


func _caught_stream() -> AudioStreamWAV:
	var n := int(22050 * 2.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6666
	var x := PackedFloat32Array()
	x.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / 22050.0
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.55)
		var hit := (sin(TAU * 52.0 * t) * exp(-t * 5.0) * 1.2 + lp * exp(-t * 16.0))
		var f := 900.0 + 700.0 * minf(t / 0.5, 1.0)
		var scr := (sin(TAU * f * t) + 0.6 * sin(TAU * f * 1.51 * t + 1.0) + 0.4 * sin(TAU * f * 2.3 * t)) * exp(-t * 2.4) * 0.5
		scr = clampf(scr * 2.2, -1.0, 1.0) * 0.55  # 削波 = 刺耳
		var rumble := sin(TAU * 34.0 * t) * exp(-t * 1.2) * 0.5 * smoothstep(0.1, 0.5, t)
		x[i] = hit + scr + rumble
	return _wav(x, false)
