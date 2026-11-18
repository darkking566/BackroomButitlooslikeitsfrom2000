class_name Shotgun
extends Node3D

const FIRE_COOLDOWN: float = 0.75
const PELLET_COUNT: int = 10
const SPREAD_DEG: float = 5.5
const MAX_RANGE: float = 45.0
const BASE_POS: Vector3 = Vector3(0.24, -0.22, -0.42)

var _gun_pivot: Node3D
var _pump_mesh: MeshInstance3D
var _muzzle_flash: Node3D
var _muzzle_light: OmniLight3D
var _blast_sfx: AudioStreamPlayer
var _pump_sfx: AudioStreamPlayer

var _cooldown: float = 0.0
var _recoil: float = 0.0
var _flash_t: float = 0.0
var _pump_delay: float = -1.0
var _pump_anim: float = 0.0
var _bob_phase: float = 0.0
var _move_speed: float = 0.0


func _ready() -> void:
	position = BASE_POS
	_build_viewmodel()
	_blast_sfx = AudioStreamPlayer.new()
	_blast_sfx.stream = BackroomsAudio.create_shotgun_blast_stream()
	_blast_sfx.volume_db = -3.0
	add_child(_blast_sfx)
	_pump_sfx = AudioStreamPlayer.new()
	_pump_sfx.stream = BackroomsAudio.create_shotgun_pump_stream()
	_pump_sfx.volume_db = -6.0
	add_child(_pump_sfx)


func _build_viewmodel() -> void:
	_gun_pivot = Node3D.new()
	add_child(_gun_pivot)

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.16, 0.17, 0.19)
	metal.roughness = 0.45
	metal.metallic = 0.75

	var dark_metal := StandardMaterial3D.new()
	dark_metal.albedo_color = Color(0.09, 0.09, 0.1)
	dark_metal.roughness = 0.55
	dark_metal.metallic = 0.65

	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.28, 0.16, 0.09)
	wood.roughness = 0.8

	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.82, 0.65, 0.24)
	brass.metallic = 0.8

	# 機匣
	_add_box(_gun_pivot, Vector3(0.055, 0.072, 0.22), Vector3(0.0, 0.0, 0.02), metal)
	# 木質槍托
	var stock := _add_box(_gun_pivot, Vector3(0.05, 0.075, 0.26), Vector3(0.0, -0.025, 0.24), wood)
	stock.rotation_degrees.x = 8.0
	# 主槍管
	_add_cyl(_gun_pivot, 0.015, 0.46, Vector3(0.0, 0.022, -0.31), dark_metal)
	# 下方彈倉管
	_add_cyl(_gun_pivot, 0.013, 0.36, Vector3(0.0, -0.008, -0.26), metal)
	# 黃銅準星
	_add_box(_gun_pivot, Vector3(0.006, 0.012, 0.008), Vector3(0.0, 0.041, -0.52), brass)

	# 護木（射擊後前後拉動退殼）
	_pump_mesh = _add_box(_gun_pivot, Vector3(0.058, 0.052, 0.15), Vector3(0.0, -0.01, -0.23), wood)

	# 槍口火光
	_muzzle_flash = Node3D.new()
	_muzzle_flash.position = Vector3(0.0, 0.022, -0.56)
	_muzzle_flash.visible = false
	_gun_pivot.add_child(_muzzle_flash)

	var flash_mat := StandardMaterial3D.new()
	flash_mat.albedo_color = Color(1.0, 0.82, 0.35)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 0.68, 0.2)
	flash_mat.emission_energy_multiplier = 4.5
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_add_box(_muzzle_flash, Vector3(0.14, 0.025, 0.02), Vector3.ZERO, flash_mat)
	_add_box(_muzzle_flash, Vector3(0.025, 0.14, 0.02), Vector3.ZERO, flash_mat)

	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = Color(1.0, 0.72, 0.32)
	_muzzle_light.light_energy = 5.0
	_muzzle_light.omni_range = 8.0
	_muzzle_flash.add_child(_muzzle_light)


func _add_box(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = sz
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _add_cyl(parent: Node3D, rad: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = rad
	m.bottom_radius = rad
	m.height = h
	m.radial_segments = 8
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees.x = 90.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func set_move_bob(horiz_speed: float) -> void:
	_move_speed = horiz_speed


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_muzzle_flash.visible = false
	if _pump_delay > 0.0:
		_pump_delay -= delta
		if _pump_delay <= 0.0:
			_pump_delay = -1.0
			_pump_anim = 1.0
			if _pump_sfx:
				_pump_sfx.pitch_scale = randf_range(0.95, 1.05)
				_pump_sfx.play()
	if _pump_anim > 0.0:
		_pump_anim = maxf(0.0, _pump_anim - delta * 3.4)

	_recoil = lerpf(_recoil, 0.0, minf(delta * 10.0, 1.0))

	if _move_speed > 0.25:
		_bob_phase += delta * _move_speed * 2.2
	else:
		_bob_phase = lerpf(_bob_phase, 0.0, minf(delta * 6.0, 1.0))

	var bob_x := cos(_bob_phase * 0.5) * 0.008 if _move_speed > 0.25 else 0.0
	var bob_y := sin(_bob_phase) * 0.01 if _move_speed > 0.25 else 0.0
	var pump_slide := sin(_pump_anim * PI) * 0.075
	var pump_tilt := sin(_pump_anim * PI) * 0.14

	_gun_pivot.position = Vector3(bob_x, bob_y - _recoil * 0.02, _recoil * 0.11)
	_gun_pivot.rotation = Vector3(_recoil * 0.28 + pump_tilt, 0.0, -pump_tilt * 0.7)
	_pump_mesh.position.z = -0.23 + pump_slide


func try_fire(camera: Camera3D, player: Node3D, ui: Node) -> bool:
	if _cooldown > 0.0 or not camera:
		return false

	_cooldown = FIRE_COOLDOWN
	_recoil = 1.0
	_flash_t = 0.055
	_pump_delay = 0.22
	_muzzle_flash.visible = true
	_muzzle_flash.rotation.z = randf() * TAU

	if _blast_sfx:
		_blast_sfx.pitch_scale = randf_range(0.92, 1.06)
		_blast_sfx.play()
	if player.has_method("apply_recoil"):
		player.apply_recoil(0.052)

	var space := camera.get_world_3d().direct_space_state
	var origin := camera.global_position
	var basis := camera.global_transform.basis
	var forward := -basis.z
	var spread_rad := deg_to_rad(SPREAD_DEG)

	var hit_monster: Node = null
	var hit_count := 0
	var hit_sum := Vector3.ZERO
	var excl := [player.get_rid()]

	for i in PELLET_COUNT:
		var ang := randf() * TAU
		var r := sqrt(randf()) * spread_rad
		var dir := (forward + basis.x * (cos(ang) * tan(r)) + basis.y * (sin(ang) * tan(r))).normalized()
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * MAX_RANGE)
		q.exclude = excl
		q.collide_with_areas = true
		q.collide_with_bodies = true
		var res := space.intersect_ray(q)
		if res.is_empty():
			continue

		var col: Object = res.collider
		var pos: Vector3 = res.position
		if col and col.has_meta("monster"):
			hit_monster = col.get_meta("monster")
			hit_count += 1
			hit_sum += pos
		elif col is PhysicalBone3D:
			var pb := col as PhysicalBone3D
			if pb.has_meta("monster"):
				hit_monster = pb.get_meta("monster")
				hit_count += 1
				hit_sum += pos
		else:
			_spawn_impact_spark(pos + res.normal * 0.02)

	if hit_monster and hit_count > 0 and hit_monster.has_method("hit_by_shotgun"):
		hit_monster.hit_by_shotgun(hit_sum / float(hit_count), forward, hit_count)
		if ui and ui.has_method("flash_hitmarker"):
			ui.flash_hitmarker()
	else:
		var m := player.get_parent().get_node_or_null("Monster")
		if m and m.has_method("on_gunshot_heard"):
			m.on_gunshot_heard(player.global_position)

	return true


func _spawn_impact_spark(pos: Vector3) -> void:
	var root := get_tree().current_scene
	if not root:
		return
	var spark := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.045, 0.045, 0.045)
	spark.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.65, 0.2)
	mat.emission_energy_multiplier = 2.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark.material_override = mat
	spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(spark)
	spark.global_position = pos
	var tw := spark.create_tween()
	tw.tween_property(spark, "scale", Vector3.ZERO, 0.22)
	tw.tween_callback(spark.queue_free)
