@tool
extends Node3D

# 常青商場（Everpine Mall）— 停滯在冬夜的復古封閉式購物中心
# 由 Blender 場景轉換匯入之獨立層級，遵守 PS2 低解析度貼圖過濾與低即時陰影規範。

const EVERPINE_GLB_PATH := "res://assets/models/everpine_mall_ps2.glb"
const INTERACT_SCRIPT := preload("res://scripts/interactable_prop.gd")

# 從 Blender 791 盞原場景燈光中空間抽樣出的 28 盞關鍵室內補光（已換算 Godot 座標，全關陰影）
const SAMPLED_LIGHTS: Array = [
	[Vector3(0.0, 4.6, 0.0), Color(1.00, 0.87, 0.75)],
	[Vector3(4.9, 5.2, -7.3), Color(1.00, 0.87, 0.75)],
	[Vector3(-4.9, 5.2, -7.3), Color(1.00, 0.87, 0.75)],
	[Vector3(-4.9, 5.2, 7.3), Color(1.00, 0.87, 0.75)],
	[Vector3(4.9, 5.2, 7.3), Color(1.00, 0.87, 0.75)],
	[Vector3(-35.4, 4.6, 3.7), Color(1.00, 0.87, 0.75)],
	[Vector3(-35.4, 4.6, -20.7), Color(1.00, 0.87, 0.75)],
	[Vector3(-34.1, 0.4, -15.2), Color(1.00, 0.87, 0.75)],
	[Vector3(-41.5, 5.2, -17.1), Color(1.00, 0.87, 0.75)],
	[Vector3(-29.3, 5.2, -17.1), Color(1.00, 0.87, 0.75)],
	[Vector3(32.9, 4.6, 2.4), Color(1.00, 0.87, 0.75)],
	[Vector3(28.0, 5.2, -2.4), Color(1.00, 0.87, 0.75)],
	[Vector3(37.8, 5.2, 7.3), Color(1.00, 0.87, 0.75)],
	[Vector3(43.9, 5.0, -16.8), Color(0.57, 0.41, 1.00)],
	[Vector3(39.6, 5.0, -20.4), Color(0.57, 0.41, 1.00)],
	[Vector3(-67.1, 4.6, 2.4), Color(1.00, 0.87, 0.75)],
	[Vector3(-67.1, 4.6, -23.2), Color(1.00, 0.87, 0.75)],
	[Vector3(-67.1, 5.2, -13.4), Color(1.00, 0.87, 0.75)],
	[Vector3(-67.1, 4.9, -39.0), Color(1.00, 0.87, 0.75)],
	[Vector3(-35.4, 4.9, 57.3), Color(1.00, 0.87, 0.75)],
	[Vector3(35.4, 4.9, 57.3), Color(1.00, 0.87, 0.75)],
	[Vector3(3.4, 8.2, 74.4), Color(0.99, 0.91, 0.80)],
	[Vector3(24.1, 8.2, 74.4), Color(0.99, 0.91, 0.80)],
	[Vector3(44.8, 8.2, 74.4), Color(0.99, 0.91, 0.80)],
	[Vector3(-17.4, 8.2, 74.4), Color(0.99, 0.91, 0.80)],
	[Vector3(-20.1, 8.2, 85.3), Color(0.99, 0.91, 0.80)],
	[Vector3(-38.1, 8.2, 74.4), Color(0.99, 0.91, 0.80)],
	[Vector3(-58.8, 8.2, 74.4), Color(0.99, 0.91, 0.80)],
]


var _flicker_lights: Array[OmniLight3D] = []
var _flicker_base: Array[float] = []
var _flicker_timer: float = 0.0
var _last_safe_pos: Vector3 = Vector3(0.0, 0.25, 3.0)


func _ready() -> void:
	_build_everpine_mall()
	if not Engine.is_editor_hint():
		var root := get_parent()
		if root and root.get_node_or_null("Player") == null:
			var player_scene := load("res://scenes/player.tscn") as PackedScene
			if player_scene:
				var player := player_scene.instantiate() as Node3D
				if player:
					player.position = Vector3(0.0, 0.25, 3.0)
					root.add_child.call_deferred(player)
		if root and root.get_node_or_null("Monster") == null:
			var monster_script := load("res://scripts/monster.gd")
			if monster_script:
				var monster := Node3D.new()
				monster.name = "Monster"
				monster.position = Vector3(24.0, 0.05, -8.0)
				monster.set_script(monster_script)
				root.add_child.call_deferred(monster)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# 防掉出地圖外兜底機制：紀錄玩家最後安全立足點，若意外跌出邊界立刻拉回
	var root := get_parent()
	if root:
		var player := root.get_node_or_null("Player") as CharacterBody3D
		if player:
			if player.is_on_floor() and player.position.y > -7.5:
				_last_safe_pos = player.position + Vector3(0.0, 0.2, 0.0)
			elif player.position.y < -10.5:
				player.position = _last_safe_pos
				player.velocity = Vector3.ZERO

	if _flicker_lights.is_empty():
		return
	_flicker_timer += delta
	for i in _flicker_lights.size():
		var l := _flicker_lights[i]
		if not is_instance_valid(l):
			continue
		var wave := sin(_flicker_timer * (6.5 + float(i) * 2.9) + float(i) * 1.9)
		var jitter := 1.0 if wave > -0.82 else 0.32
		l.light_energy = _flicker_base[i] * jitter


func _build_everpine_mall() -> void:
	if get_node_or_null("EverpineMallModel") == null:
		_build_mall_model()
	if get_node_or_null("MallLights") == null:
		_build_mall_lights()
	if get_node_or_null("MallInteractables") == null:
		_build_mall_interactables()
	if get_node_or_null("MallReflectionProbes") == null:
		_build_reflection_probes()


func _build_mall_model() -> void:
	if not ResourceLoader.exists(EVERPINE_GLB_PATH):
		push_warning("EverpineMall: 找不到模型 %s" % EVERPINE_GLB_PATH)
		return
	var packed := load(EVERPINE_GLB_PATH) as PackedScene
	if packed == null:
		push_warning("EverpineMall: 無法載入 %s" % EVERPINE_GLB_PATH)
		return
	var inst := packed.instantiate()
	inst.name = "EverpineMallModel"
	add_child(inst)
	_apply_ps2_materials_and_collision(inst)


func _apply_ps2_materials_and_collision(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		if mesh != null:
			var is_clip_bounds := ("ClipBounds" in mi.name)
			if is_clip_bounds:
				# 原場景天空盒邊界空氣牆：隱藏外觀，只保留雙面實體碰撞防掉出地圖
				mi.visible = false
			else:
				for s in mesh.get_surface_count():
					var mat := mi.get_active_material(s)
					if mat is StandardMaterial3D:
						var sm := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
						sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
						var mname := mat.resource_name.to_lower()
						if "DoorJambs" in mi.name or "jamb" in mname:
							# 自動補封的門框內壁採雙面顯示，不論從門內或門外看都完全密合
							sm.cull_mode = BaseMaterial3D.CULL_DISABLED
						elif "water" in mname:
							sm.metallic = 0.28
							sm.roughness = 0.10
							sm.metallic_specular = 0.88
						elif "floor_tiles_blue" in mname or "floor_tiles_wave" in mname:
							sm.metallic = 0.14
							sm.roughness = 0.28
							sm.metallic_specular = 0.78
						elif "glass" in mname:
							sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
							sm.albedo_color.a = minf(sm.albedo_color.a, 0.45)
						mi.set_surface_override_material(s, sm)
			# 為世界幾何、空氣牆、地形與固定設施建立雙面碰撞體；貼花 (Decals) 不建立碰撞
			if not ("Decal" in mi.name):
				mi.create_trimesh_collision()
				for col_child in mi.get_children():
					if col_child is StaticBody3D:
						for shape_node in col_child.get_children():
							if shape_node is CollisionShape3D and shape_node.shape is ConcavePolygonShape3D:
								(shape_node.shape as ConcavePolygonShape3D).backface_collision = true
	for child in node.get_children():
		_apply_ps2_materials_and_collision(child)


func _build_mall_lights() -> void:
	var lights_root := Node3D.new()
	lights_root.name = "MallLights"
	add_child(lights_root)

	# 1. 微弱冬夜月光補光（壓低能量以免無陰影平行光穿透屋頂照亮整個室內）
	var sky_sun := DirectionalLight3D.new()
	sky_sun.name = "WinterSkyFill"
	sky_sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	sky_sun.light_color = Color(0.55, 0.68, 0.90)
	sky_sun.light_energy = 0.06
	sky_sun.shadow_enabled = false
	lights_root.add_child(sky_sun)

	# 2. 抽樣自原 Blender 場景的商場室內補光（全關陰影，保留明暗對比與手電筒探索感）
	_flicker_lights.clear()
	_flicker_base.clear()
	for i in SAMPLED_LIGHTS.size():
		var item: Array = SAMPLED_LIGHTS[i]
		var omni := OmniLight3D.new()
		omni.name = "MallLight_%02d" % i
		omni.position = item[0]
		omni.light_color = item[1]
		var is_purple: bool = item[1].b > 0.95 and item[1].r < 0.7
		var base_energy := 1.65 if is_purple else 1.15
		omni.light_energy = base_energy
		omni.omni_range = 21.0
		omni.omni_attenuation = 1.55
		omni.shadow_enabled = false
		lights_root.add_child(omni)
		# 讓少數遠處走廊燈帶點微弱日光燈閃爍，增添詭異感
		if i in [5, 10, 15, 19]:
			_flicker_lights.append(omni)
			_flicker_base.append(base_energy)


func _build_reflection_probes() -> void:
	# 反射探針必須在模型與燈光都建立之後才加入（見 PS2_LEVEL_PIPELINE.md）
	var probes := Node3D.new()
	probes.name = "MallReflectionProbes"
	add_child(probes)

	var atrium_probe := ReflectionProbe.new()
	atrium_probe.name = "AtriumReflectionProbe"
	atrium_probe.position = Vector3(0.0, 4.2, 0.0)
	atrium_probe.size = Vector3(48.0, 16.0, 48.0)
	atrium_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	atrium_probe.intensity = 0.65
	probes.add_child(atrium_probe)

	var b1_probe := ReflectionProbe.new()
	b1_probe.name = "B1FoodCourtReflectionProbe"
	b1_probe.position = Vector3(-34.0, -1.0, -15.0)
	b1_probe.size = Vector3(36.0, 14.0, 36.0)
	b1_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	b1_probe.intensity = 0.65
	probes.add_child(b1_probe)


func _build_mall_interactables() -> void:
	var props := Node3D.new()
	props.name = "MallInteractables"
	add_child(props)

	# 中央松林中庭：M.E.G. 商場導覽終端機
	var kiosk := StaticBody3D.new()
	kiosk.name = "EverpineInfoTerminal"
	kiosk.position = Vector3(2.8, 0.0, 1.2)
	kiosk.set_script(INTERACT_SCRIPT)
	props.add_child(kiosk)

	var base_mesh := MeshInstance3D.new()
	var base_box := BoxMesh.new()
	base_box.size = Vector3(0.75, 1.05, 0.55)
	base_mesh.mesh = base_box
	base_mesh.position = Vector3(0.0, 0.525, 0.0)
	var mat_body := StandardMaterial3D.new()
	mat_body.albedo_color = Color(0.68, 0.67, 0.62)
	mat_body.roughness = 0.82
	base_mesh.material_override = mat_body
	kiosk.add_child(base_mesh)

	var screen_mesh := MeshInstance3D.new()
	var screen_box := BoxMesh.new()
	screen_box.size = Vector3(0.54, 0.40, 0.36)
	screen_mesh.mesh = screen_box
	screen_mesh.position = Vector3(0.0, 1.26, 0.0)
	var mat_screen := StandardMaterial3D.new()
	mat_screen.albedo_color = Color(0.10, 0.36, 0.42)
	mat_screen.emission_enabled = true
	mat_screen.emission = Color(0.22, 0.72, 0.80)
	mat_screen.emission_energy_multiplier = 1.2
	screen_mesh.material_override = mat_screen
	kiosk.add_child(screen_mesh)

	var col := CollisionShape3D.new()
	var col_shape := BoxShape3D.new()
	col_shape.size = Vector3(0.8, 1.5, 0.6)
	col.shape = col_shape
	col.position = Vector3(0.0, 0.75, 0.0)
	kiosk.add_child(col)

	kiosk.set("prompt_text", "[E] 查閱「常青商場」M.E.G. 導覽終端")
	kiosk.set("interact_callback", func(ui: Node) -> void:
		if ui and ui.has_method("show_note"):
			ui.call(
				"show_note",
				"M.E.G. 商場導覽終端 — 常青商場",
				"【層級名稱：常青商場】\n\n"
				+ "• 你目前位於「中央松林中庭（藍磚區）」。\n"
				+ "• 本商場為封閉式復古購物中心，包含東側商店街、南側黑毯區、西側波紋磚長廊與西北下沉藍磚美食區。\n"
				+ "• 按 [M] 開啟 M.E.G. 地圖可快速傳送至各區段，或切換前往「閾界」與「宜居地帶」。\n"
				+ "• 按 [F] 可開關手電筒探索較暗的店面與走廊。"
			)
	)
