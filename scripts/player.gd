extends CharacterBody3D

@export var walk_speed: float = 3.2
@export var sprint_speed: float = 5.0
@export var acceleration: float = 10.0
@export var gravity: float = 12.0
@export var mouse_sensitivity: float = 0.0022
@export var bob_frequency: float = 2.2
@export var bob_amplitude: float = 0.04

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight
@onready var interact_ray: RayCast3D = get_node_or_null("Head/Camera3D/InteractRay")
@onready var footstep_player: AudioStreamPlayer = get_node_or_null("FootstepPlayer")

var _bob_time: float = 0.0
var _camera_base_y: float = 0.0
var _pitch: float = 0.0
var _ignore_mouse_frames: int = 3
var _step_primed: bool = true

var _win95_ui: CanvasLayer
var _spawn_pos: Vector3
var _spawn_rot: Vector3
var _elapsed_time: float = 0.0
var _found_pc_clue: bool = false
var _current_target: Node = null


func _ready() -> void:
	_spawn_pos = position
	_spawn_rot = rotation
	_camera_base_y = camera.position.y
	if flashlight:
		flashlight.visible = false
	if footstep_player:
		footstep_player.stream = BackroomsAudio.create_carpet_footstep_stream()
		footstep_player.volume_db = -7.0
	_win95_ui = get_parent().get_node_or_null("Win95UI")
	if _win95_ui:
		_win95_ui.window_closed.connect(_on_ui_closed)
		_win95_ui.restart_requested.connect(_on_restart_requested)
		_win95_ui.teleport_requested.connect(_on_teleport_requested)
	_capture_mouse()


func _capture_mouse() -> void:
	_ignore_mouse_frames = 3
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_ui_closed() -> void:
	_capture_mouse()


func _on_restart_requested() -> void:
	position = _spawn_pos
	rotation = _spawn_rot
	_pitch = 0.0
	head.rotation.x = 0.0
	velocity = Vector3.ZERO
	_elapsed_time = 0.0
	_found_pc_clue = false
	_capture_mouse()


func _on_teleport_requested(target_pos: Vector3, yaw_rad: float) -> void:
	var variants := get_parent().get_node_or_null("Level0Variants")
	if variants and variants.has_method("_set_active_zone"):
		variants._set_active_zone("")
	position = target_pos
	rotation = Vector3(0.0, yaw_rad, 0.0)
	_pitch = 0.0
	head.rotation.x = 0.0
	if camera:
		camera.rotation.z = 0.0
	velocity = Vector3.ZERO
	_capture_mouse()


func open_prop_ui(prop: Node) -> void:
	if prop.get("interaction_type") == "portal":
		_on_teleport_requested(prop.get("portal_pos"), prop.get("portal_yaw"))
		return
	if not _win95_ui:
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var kind: String = prop.get("interaction_type")
	var img_val = prop.get("image_path")
	var img_path: String = img_val if img_val is String else ""
	if kind == "exit_door":
		_win95_ui.show_exit_dialog(_found_pc_clue, _elapsed_time)
	elif kind == "level1_exit":
		_win95_ui.show_level1_exit(_elapsed_time)
	elif kind == "wiki_archive":
		_found_pc_clue = true
		_win95_ui.show_wiki_archive()
	elif kind == "note":
		_win95_ui.show_note(prop.get("file_name"), prop.get("body_text"), img_path)
	else:
		_found_pc_clue = true
		_win95_ui.show_explorer(
			prop.get("window_title"),
			prop.get("file_name"),
			prop.get("file_size"),
			prop.get("file_name") + " - Notepad",
			prop.get("body_text"),
			img_path
		)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key_ev := event as InputEventKey
	if _win95_ui and _win95_ui.is_popup_open():
		if _matches_key(key_ev, KEY_ESCAPE) or _matches_key(key_ev, KEY_E) or (_matches_key(key_ev, KEY_M) and _win95_ui.is_map_open()):
			_win95_ui.close_popup()
			get_viewport().set_input_as_handled()
		return

	if _matches_key(key_ev, KEY_ESCAPE):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			_capture_mouse()
	elif _matches_key(key_ev, KEY_M) and _win95_ui:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_win95_ui.show_map(position, rotation.y)
		get_viewport().set_input_as_handled()
	elif _matches_key(key_ev, KEY_F) and flashlight:
		flashlight.visible = not flashlight.visible
	elif _matches_key(key_ev, KEY_E) and _current_target and _current_target.has_method("interact"):
		_current_target.interact(self)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _win95_ui and _win95_ui.is_popup_open():
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if _ignore_mouse_frames > 0:
			return
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clamp(_pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-80.0), deg_to_rad(80.0))
		head.rotation.x = _pitch
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			_capture_mouse()


func _physics_process(delta: float) -> void:
	_elapsed_time += delta
	if _ignore_mouse_frames > 0:
		_ignore_mouse_frames -= 1

	if _win95_ui and _win95_ui.is_popup_open():
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	_update_interact_target()

	if not is_on_floor():
		velocity.y -= gravity * delta

	var input_dir := _get_move_input()
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var is_sprinting := _is_key_down(KEY_SHIFT)
	var target_speed := sprint_speed if is_sprinting else walk_speed

	if direction != Vector3.ZERO:
		velocity.x = lerpf(velocity.x, direction.x * target_speed, acceleration * delta)
		velocity.z = lerpf(velocity.z, direction.z * target_speed, acceleration * delta)
	else:
		velocity.x = lerpf(velocity.x, 0.0, acceleration * delta)
		velocity.z = lerpf(velocity.z, 0.0, acceleration * delta)

	move_and_slide()
	_update_head_bob(delta)


func _update_interact_target() -> void:
	_current_target = null
	if interact_ray and interact_ray.is_colliding():
		var col := interact_ray.get_collider()
		if col and col.has_method("interact"):
			_current_target = col
	if _win95_ui:
		if _current_target and _current_target.has_method("get_interact_prompt"):
			_win95_ui.set_prompt(_current_target.get_interact_prompt())
		else:
			_win95_ui.set_prompt("")


func _matches_key(event: InputEventKey, key: Key) -> bool:
	return event.physical_keycode == key or event.keycode == key


func _is_key_down(key: Key) -> bool:
	return Input.is_physical_key_pressed(key) or Input.is_key_pressed(key)


func _get_move_input() -> Vector2:
	var x := 0.0
	var y := 0.0
	if _is_key_down(KEY_A) or _is_key_down(KEY_LEFT):
		x -= 1.0
	if _is_key_down(KEY_D) or _is_key_down(KEY_RIGHT):
		x += 1.0
	if _is_key_down(KEY_W) or _is_key_down(KEY_UP):
		y -= 1.0
	if _is_key_down(KEY_S) or _is_key_down(KEY_DOWN):
		y += 1.0
	return Vector2(x, y).limit_length(1.0)


func _update_head_bob(delta: float) -> void:
	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and horiz_speed > 0.25:
		_bob_time += delta * horiz_speed
		var bob_wave := sin(_bob_time * bob_frequency)
		camera.position.y = _camera_base_y + bob_wave * bob_amplitude
		camera.position.x = cos(_bob_time * bob_frequency * 0.5) * (bob_amplitude * 0.45)

		if bob_wave < -0.75 and _step_primed:
			_step_primed = false
			_play_footstep()
		elif bob_wave > 0.0:
			_step_primed = true
	else:
		_step_primed = true
		camera.position.y = lerpf(camera.position.y, _camera_base_y, 8.0 * delta)
		camera.position.x = lerpf(camera.position.x, 0.0, 8.0 * delta)


func _play_footstep() -> void:
	if footstep_player and footstep_player.stream:
		footstep_player.pitch_scale = randf_range(0.88, 1.12)
		footstep_player.volume_db = randf_range(-9.5, -6.5)
		footstep_player.play()
