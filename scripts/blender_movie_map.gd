extends Node3D
# gm_brmovie_complete（assets/models/blender_movie_map.glb，約 321×234×228 m）。貼圖全為 tools/map_textures/gen_movie.py 生成的原創圖。
# 執行時載入並生成碰撞（不把幾何寫進 .tscn）。Blender 原點 = ORIGIN，Blender Z 向上 → Godot Y。
# 連接方式：舊地圖（BlenderMap）街道廣場南邊長形建築的東端牆開一扇門 → 本腳本生成的通道（x164.6→266）→ 新地圖西側的戲院大廳（牆被挖開）。
# 新地圖的燈併進舊地圖腳本的燈池（亮度淡入淡出、怪物附近熄滅閃爍、環境光跟隨），不另建燈池。
const MAP_PATH := "res://assets/models/blender_movie_map.glb"
const LIGHTS_PATH := "res://assets/models/blender_movie_lights.json"
const ORIGIN := Vector3(489.6, -5.8, 295.95)  # 新地圖局部 (-212,4.4,-34) 對到通道終點 (277.6,-1.4,261.95)
const BR_X0 := 164.6   # 舊地圖端牆
const BR_X1 := 292.0   # 通道牆/天花板終點：穿過戲院的階梯區（階梯每階 0.3 m 玩家爬不上去），到後面的平地房間
const BR_Z0 := 258.7
const BR_Z1 := 265.2
const BR_FLOOR := -1.4
const BR_H := 2.8
const INTERACTIVES_PATH := "res://assets/models/blender_movie_interactives.json"
var _ia_names := {}
const BR_TEX := "res://assets/textures/movie_map/CONCRETEFLOOR027B.png"


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var scene := load(MAP_PATH) as PackedScene
	if scene == null:
		push_warning("blender_movie_map.glb 載入失敗")
		return
	var old := get_parent().get_node_or_null("BlenderMap")
	var ia := _read_json(INTERACTIVES_PATH)
	for e in ia:
		_ia_names[String(e["n"])] = true
	var inst := scene.instantiate() as Node3D
	inst.position = ORIGIN
	add_child(inst)
	_style_and_collide(inst, old)
	# 新地圖：把戲院西牆在通道範圍內挖開（保留地板）
	_cut(inst, AABB(Vector3(249.6, BR_FLOOR - 0.05, BR_Z0), Vector3(44.0, BR_H + 0.05, BR_Z1 - BR_Z0)), false, old)
	# 舊地圖：拆掉端室的東牆
	if old != null:
		_cut(old, AABB(Vector3(BR_X0 - 0.4, BR_FLOOR - 0.2, BR_Z0 - 0.2), Vector3(0.8, BR_H + 0.4, BR_Z1 - BR_Z0 + 0.4)), true, old)
	_build_bridge()
	# 門：交給舊地圖腳本的互動機制（開關動畫、音效、提示文字）處理
	if old != null and not ia.is_empty():
		var oia = old.get("_ia")
		if oia is Dictionary:
			for e in ia:
				oia[String(e["n"])] = e
			old.call("_setup_interactives", inst)
	_merge_lights.call_deferred()


func _read_json(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Array else []


# 新地圖的燈加進舊地圖腳本的燈池（它已經處理淡入淡出、怪物附近熄滅、環境光）
func _merge_lights() -> void:
	var bm := get_parent().get_node_or_null("BlenderMap")
	if bm == null:
		return
	var src = bm.get("_src")
	var f := FileAccess.open(LIGHTS_PATH, FileAccess.READ)
	if not (src is Array) or f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if data is Array:
		for e in data:
			src.append([e[0] + ORIGIN.x, e[1] + ORIGIN.y, e[2] + ORIGIN.z, e[3], e[4], e[5], e[6], e[7]])


func _style_and_collide(n: Node, old: Node) -> void:
	for c in n.get_children():
		_style_and_collide(c, old)
	var mi := n as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	var solid := not String(mi.name).begins_with("infodecal") and not _ia_names.has(String(mi.name))  # 會動的門不做靜態碰撞
	for i in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(i) as StandardMaterial3D
		if m == null:
			continue
		var nm := m.resource_name.to_upper()
		if nm.contains("SKY") or nm.contains("TOOLS") or nm == "MATERIAL" or nm.contains("PI_WINDOW"):
			var inv := StandardMaterial3D.new()
			inv.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			inv.albedo_color = Color(0, 0, 0, 0)
			mi.set_surface_override_material(i, inv)
			continue
		var d := m.duplicate() as StandardMaterial3D
		d.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		d.normal_enabled = false
		d.roughness = 1.0
		d.metallic = 0.0
		if nm.contains("LIGHT_NEON") or nm.contains("LIGHTS_ON"):
			d.emission_enabled = true
			d.emission = Color(1.0, 0.95, 0.75)
			d.emission_energy_multiplier = 1.4
			d.emission_texture = d.albedo_texture
		mi.set_surface_override_material(i, d)
		if solid and d.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			_collide_surface(mi, i, old, nm)


func _collide_surface(mi: MeshInstance3D, s: int, old: Node, mat_name: String) -> void:
	var arr := mi.mesh.surface_get_arrays(s)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var faces := PackedVector3Array()
	var idx := PackedInt32Array()
	if arr[Mesh.ARRAY_INDEX] != null:
		idx = arr[Mesh.ARRAY_INDEX]
	var cnt := idx.size() if idx.size() > 0 else verts.size()
	for t in range(0, cnt - 2, 3):
		var a := verts[idx[t]] if idx.size() > 0 else verts[t]
		var b := verts[idx[t + 1]] if idx.size() > 0 else verts[t + 1]
		var c := verts[idx[t + 2]] if idx.size() > 0 else verts[t + 2]
		faces.append_array([a, b, c, c, b, a])  # 雙面
	if faces.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	if old != null:
		body.set_meta("step_stream", old.call("_step_for", mat_name))  # 腳步聲依材質
	mi.add_child(body)


# 把 root 底下所有模型中「重心落在 box（世界座標）內」的三角形拿掉並重建碰撞。
# only_x_walls=true：只拿 X 方向的牆面（舊地圖端牆）；false：拿掉所有非地板（朝上）的面。
func _cut(root: Node, box: AABB, only_x_walls: bool, old: Node) -> void:
	var cut_n := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var mesh := mi.mesh as ArrayMesh
		if mesh == null or not box.intersects(mi.global_transform * mi.get_aabb()):
			continue
		var xf := mi.global_transform
		var surfs: Array = []
		var changed := false
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx := PackedInt32Array()
			if arr[Mesh.ARRAY_INDEX] != null:
				idx = arr[Mesh.ARRAY_INDEX]
			else:
				idx.resize(verts.size())
				for k in verts.size():
					idx[k] = k
			var keep := PackedInt32Array()
			for t in range(0, idx.size() - 2, 3):
				var a := xf * verts[idx[t]]
				var b := xf * verts[idx[t + 1]]
				var c := xf * verts[idx[t + 2]]
				var cen := (a + b + c) / 3.0
				var drop := false
				if box.has_point(cen):
					var nrm := (b - a).cross(c - a).normalized()
					# 新地圖：除了和通道地板同高的地面，其餘（牆、天花板、高出地面的階梯）都拿掉
					drop = absf(nrm.x) > 0.9 if only_x_walls else (absf(nrm.y) < 0.7 or cen.y > box.position.y + 0.15)  # 地板有些法線朝下，所以用絕對值
				if drop:
					changed = true
					cut_n += 1
				else:
					keep.append(idx[t])
					keep.append(idx[t + 1])
					keep.append(idx[t + 2])
			arr[Mesh.ARRAY_INDEX] = keep
			surfs.append([arr, mesh.surface_get_material(s), mi.get_surface_override_material(s)])
		if not changed:
			continue
		mesh = mesh.duplicate() as ArrayMesh
		mesh.clear_surfaces()
		for i in surfs.size():
			var a2: Array = surfs[i][0]
			if (a2[Mesh.ARRAY_INDEX] as PackedInt32Array).size() == 0:
				continue
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
			var si := mesh.get_surface_count() - 1
			mesh.surface_set_material(si, surfs[i][1])
			mi.set_surface_override_material(si, surfs[i][2])
		mi.mesh = mesh
		for ch in mi.get_children():
			if ch is StaticBody3D:
				ch.free()
		for si in mesh.get_surface_count():
			var mt := mesh.surface_get_material(si)
			_collide_surface(mi, si, old, mt.resource_name.to_upper() if mt else "")
	print("[BlenderMovieMap] 挖開三角形 ", cut_n, "（", root.name, "）")


func _build_bridge() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(BR_TEX) as Texture2D
	mat.albedo_color = Color(0.8, 0.8, 0.76)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(0.25, 0.25, 0.25)
	mat.roughness = 1.0
	var zc := (BR_Z0 + BR_Z1) * 0.5
	var w := BR_Z1 - BR_Z0
	var len := BR_X1 - BR_X0
	var xc := (BR_X0 + BR_X1) * 0.5
	_box(Vector3(xc + 1.0, BR_FLOOR - 0.2, zc), Vector3(len + 2.0, 0.4, w + 0.8), mat)  # 地板（多伸 2 m 接上新地圖地面）
	_box(Vector3(xc, BR_FLOOR + BR_H + 0.2, zc), Vector3(len, 0.4, w + 0.8), mat)       # 天花板
	_box(Vector3(xc, BR_FLOOR + BR_H * 0.5, BR_Z0 - 0.2), Vector3(len, BR_H, 0.4), mat)  # 兩側牆
	_box(Vector3(xc, BR_FLOOR + BR_H * 0.5, BR_Z1 + 0.2), Vector3(len, BR_H, 0.4), mat)
	# 日光燈：自發光燈罩 + 暗淡的燈（不開陰影）
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(1.0, 0.95, 0.8)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.95, 0.75)
	lamp.emission_energy_multiplier = 1.5
	var x := BR_X0 + 14.0
	while x < BR_X1 - 6.0:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.6, 0.06, 0.4)
		mi.mesh = bm
		mi.material_override = lamp
		mi.position = Vector3(x, BR_FLOOR + BR_H - 0.05, zc)
		add_child(mi)
		var l := OmniLight3D.new()
		l.position = Vector3(x, BR_FLOOR + BR_H - 0.5, zc)
		l.light_color = Color(1.0, 0.93, 0.78)
		l.light_energy = 0.9
		l.omni_range = 14.0
		l.omni_attenuation = 1.3
		l.shadow_enabled = false
		add_child(l)
		x += 20.0


func _box(center: Vector3, size: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = center
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)
	body.set_meta("step_stream", get_parent().get_node("BlenderMap").call("_step_for", "CONCRETE") if get_parent().has_node("BlenderMap") else null)
	add_child(body)
