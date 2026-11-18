extends Node3D

# 全程追獵者。啟動時從全場景的靜態碰撞體烘焙導航網格（所有區域與樓梯共用一張）。
# 狀態：巡邏 → 調查（聽到）→ 凝視（遠遠看到）→ 追擊 → 搜索（跟丟）→ 折返 / 埋伏 / 回巡邏。
# 每次追擊開始時隨機抽一種「追法」：直衝攔截、被看就不動、繞到背後。

enum State { PATROL, INVESTIGATE, STARE, CHASE, SEARCH, AMBUSH, APPARITION, PEEK, UNCONSCIOUS }
enum Mood { RUSH, STALK, FLANK }

const UNCONSCIOUS_DURATION := 60.0  # 被散彈槍打飛後失去意識 1 分鐘

const HEAT_CELL := 4.0     # 熱度表格子邊長（公尺）
const NEAR_DIST := 6.0     # 進到這個距離換成近距離臉
const LIGHT_KILL_DIST := 7.0  # 牠周圍這個距離內的燈會熄掉
const LIGHT_FLICKER_DIST := 15.0  # 這個距離內的燈開始亂閃，預告牠快到了
const DREAD_DIST := 15.0   # 這個距離內畫面開始劣化（穿牆也算：你「感覺」得到牠）
const MAX_CHASE_SPEED := 4.9  # 越追越快的上限，必須低於玩家跑速 5.0
const FRENZY_SPEED := 9.0  # 狂暴模式：接近玩家跑速兩倍，跑不掉

const POV_LAYER := 20      # 怪物模型放在這個渲染層，怪物視角攝影機才不會拍到自己的頭
const POV_EYE_Y := 1.7     # 怪物視角攝影機離地高度
const POV_SIZE := Vector2(360, 270)

const MODEL_PATH := "res://assets/models/monster.glb"

@export var model_scene: PackedScene
@export var patrol_speed: float = 2.2
@export var investigate_speed: float = 3.0
@export var chase_speed: float = 4.4            # 玩家走 3.2、跑 5.0：跑得掉，但跑步很吵
@export var sight_range_dark: float = 11.0
@export var sight_range_flashlight: float = 28.0
@export var hear_range_walk: float = 6.0
@export var hear_range_sprint: float = 20.0
@export var catch_distance: float = 1.1

var state: State = State.PATROL
var _mood: Mood = Mood.RUSH
var _player: CharacterBody3D
var _ui: Node
var _model: Node3D
var _anim: AnimationPlayer
var _skel: Skeleton3D
var _head_bone := -1
var _chest_bone := -1
var _steps: AudioStreamPlayer3D
var _snap_sfx: AudioStreamPlayer3D
var _lure_sfx: AudioStreamPlayer3D
var _home: Vector3
var _nav_ready := false
var _path := PackedVector3Array()
var _path_i := 0
var _repath_t := 0.0
var _wait_t := 0.0
var _search_left := 0
var _ambush_left := 0
var _stare_t := 0.0
var _step_t := 0.0
var _sees := false
var _anger := 0          # 每被甩掉一次 +1，追擊速度跟著變快
var _last_seen: Vector3
var _heat := {}          # Vector3i 格子 -> 玩家待過的次數
var _heat_pos := {}      # Vector3i 格子 -> 玩家在該格最後的實際位置（保留樓層高度）
var _heat_t := 0.0
var _lights: Array[Node] = []
var _dimmed: Dictionary = {}  # 被牠弄熄的燈 -> 剩餘延遲復電秒數
var _light_t := 0.0
var _event_t := 60.0     # 巡邏中每 45–90 秒觸發一次「靈異事件」
var _app_t := 0.0        # 幻影最多停留的秒數
var _app_watch := 0.0    # 幻影被你盯著的累計秒數
var _snap_roll := 0.0    # 站著不動時脖子歪斜角度
var _snap_t := 2.0
var _peek_lean := 0.0    # 轉角探頭側傾角度
var _peek_t := 0.0
var _peek_watch := 0.0
var _flash_burn := 0.0   # 被手電筒直射臉部的累計秒數
var _stagger_t := 0.0    # 被手電筒照到暴走前的抽搐硬直
var _enraged_t := 0.0    # 暴走加速剩餘秒數
var _lure_t := 15.0      # 誘餌怪聲冷卻秒數
var _echo: AudioStreamPlayer3D
var _echo_left := 0      # 回聲腳步還剩幾步
var _echo_t := 0.0
var _post_mat: ShaderMaterial
var _post_base := {}
var _heavy: AudioStreamPlayer3D  # 狂暴模式的沉重腳步
var _noclip := false           # 狂暴模式下目前是否正在穿牆
var _pov_vp: SubViewport       # 怪物視角畫面（只在螢幕翻起時才渲染）
var _pov_cam: Camera3D
var _pov_panel: Control
var _pov_open := false
var _pov_tween: Tween
var _hitbox: Area3D
var _ragdoll_sim: PhysicalBoneSimulator3D
var _phys_bones: Array[PhysicalBone3D] = []
var _hips_pb: PhysicalBone3D
var _head_pb: PhysicalBone3D
var _unconscious_t: float = 0.0
var _ragdoll_sfx: AudioStreamPlayer3D


func _ready() -> void:
	_home = global_position
	_last_seen = _home
	_player = get_parent().get_node("Player")
	_ui = get_parent().get_node_or_null("Win95UI")
	if _ui:
		_ui.restart_requested.connect(_reset)
	_build_sprite()
	_build_pov()
	_steps = AudioStreamPlayer3D.new()
	_steps.stream = BackroomsAudio.create_carpet_footstep_stream()
	_steps.pitch_scale = 0.55  # 比玩家腳步低沉
	_steps.max_distance = 24.0
	add_child(_steps)
	_echo = AudioStreamPlayer3D.new()
	_echo.stream = _steps.stream  # 和玩家同一種地毯腳步，聽起來像你自己的
	_echo.top_level = true        # 位置跟著玩家背後，不跟怪物
	add_child(_echo)
	_snap_sfx = AudioStreamPlayer3D.new()
	_snap_sfx.stream = BackroomsAudio.create_light_pop_stream()
	_snap_sfx.pitch_scale = 0.52
	_snap_sfx.volume_db = -6.0
	_snap_sfx.max_distance = 18.0
	add_child(_snap_sfx)
	_lure_sfx = AudioStreamPlayer3D.new()
	_lure_sfx.stream = BackroomsAudio.create_fluorescent_hum_stream()
	_lure_sfx.top_level = true
	_lure_sfx.pitch_scale = 0.62
	_lure_sfx.volume_db = -8.0
	_lure_sfx.max_distance = 26.0
	add_child(_lure_sfx)
	_heavy = AudioStreamPlayer3D.new()
	_heavy.stream = _steps.stream
	_heavy.pitch_scale = 0.3   # 壓低成沉悶的重擊
	_heavy.volume_db = 10.0
	_heavy.unit_size = 4.0
	_heavy.max_distance = 70.0  # 很遠就聽得到牠衝過來
	add_child(_heavy)
	_ragdoll_sfx = AudioStreamPlayer3D.new()
	_ragdoll_sfx.stream = BackroomsAudio.create_ragdoll_impact_stream()
	_ragdoll_sfx.volume_db = 4.0
	_ragdoll_sfx.max_distance = 45.0
	add_child(_ragdoll_sfx)
	var filter := get_parent().get_node_or_null("PS2PostLayer/PS2Filter")
	if filter and filter.material is ShaderMaterial:
		_post_mat = filter.material
		for p in ["pixel_size", "color_levels", "vignette_strength"]:
			_post_base[p] = _post_mat.get_shader_parameter(p)
	_bake_navmesh.call_deferred()  # 等各區域腳本把幾何體生成完


func _bake_navmesh() -> void:
	_lights = get_parent().find_children("*", "OmniLight3D", true, false)
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25  # Zone 3 樓梯每階高 0.21
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, get_parent())
	NavigationServer3D.bake_from_source_geometry_data_async(nm, src, func() -> void:
		var region := NavigationRegion3D.new()
		region.navigation_mesh = nm
		get_parent().add_child(region)
		_nav_ready = true
	)


func _physics_process(delta: float) -> void:
	if not _nav_ready or (_ui and _ui.is_popup_open()):
		return  # 玩家讀文件時動不了，怪物也暫停才公平
	if state == State.UNCONSCIOUS:
		_unconscious_t -= delta
		if _unconscious_t <= 0.0:
			_wake_up_from_ragdoll()
		return
	var dist := global_position.distance_to(_player.global_position)
	if _enraged_t > 0.0:
		_enraged_t -= delta
	var moved := false
	var frenzy: bool = _ui != null and _ui.frenzy_mode
	if frenzy:
		moved = _frenzy(delta, dist)
	elif _stagger_t > 0.0:
		_stagger_t -= delta
	else:
		_think(delta)
		moved = _move(delta)
	if not frenzy:  # 狂暴時手電筒嚇不住牠
		_update_flashlight_reaction(delta, dist)
	_update_neck_snap(delta, moved)
	_update_lure(delta, dist)
	_light_t -= delta
	if _light_t <= 0.0:
		var dt := 0.12
		_light_t = dt
		_update_lights(dt)
	_update_echo(delta)
	if _post_mat:
		# 越近畫面越碎：像素變大、色階變少、四周變暗
		var k := clampf(1.0 - dist / DREAD_DIST, 0.0, 1.0)
		_post_mat.set_shader_parameter("pixel_size", lerpf(_post_base["pixel_size"], 5.0, k))
		_post_mat.set_shader_parameter("color_levels", lerpf(_post_base["color_levels"], 9.0, k))
		_post_mat.set_shader_parameter("vignette_strength", lerpf(_post_base["vignette_strength"], 0.5, k))
	_update_visual(delta, moved, dist)


func _think(delta: float) -> void:
	var ppos := _player.global_position
	var dist := global_position.distance_to(ppos)

	_heat_t -= delta
	if _heat_t <= 0.0:
		_heat_t = 0.5
		var cell := Vector3i((ppos / HEAT_CELL).floor())
		_heat[cell] = _heat.get(cell, 0) + 1
		_heat_pos[cell] = ppos

	_repath_t -= delta
	_sees = _sees_player()
	if state == State.APPARITION:
		_haunt(delta, dist)
		return
	if state == State.PEEK:
		_peek(delta, dist)
		return
	if _sees:
		_last_seen = ppos
		if state == State.AMBUSH:
			_mood = Mood.RUSH  # 埋伏被撞見：直接衝出來
			state = State.CHASE
			_repath_t = 0.0
		elif state != State.CHASE and state != State.STARE:
			_mood = [Mood.RUSH, Mood.STALK, Mood.FLANK].pick_random()
			state = State.STARE if dist > 10.0 else State.CHASE
			_stare_t = randf_range(1.2, 2.8)
			_path = PackedVector3Array()
			_repath_t = 0.0
		if state == State.STARE:
			# 遠遠站著盯你一會兒才動；你自己靠近到 6 公尺內牠就不等了
			_stare_t -= delta
			if _stare_t > 0.0 and dist > 6.0:
				return
			state = State.CHASE
		if dist < catch_distance:
			_catch()
			return
		if _repath_t <= 0.0:
			_repath_t = 0.3
			var target := ppos
			if _mood == Mood.RUSH and dist > 4.0:
				# 預判攔截：瞄準玩家幾秒後會到的位置，尋路自然繞去堵前方
				var vel := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
				target = ppos + vel * clampf(dist / chase_speed, 0.0, 2.5)
			elif _mood == Mood.FLANK and dist > 8.0:
				target = ppos + _player.global_transform.basis.z * 6.0  # 玩家背後 6 公尺
			_go_to(target)
		return
	if state == State.STARE:
		state = State.CHASE  # 凝視途中你躲開了：牠走去剛才看到你的地方
		_go_to(ppos)
	_event_t -= delta
	if state == State.PATROL and _event_t <= 0.0:
		_event_t = randf_range(45.0, 90.0)
		match randi() % 4:
			0: _appear(true)
			1: _appear(false)
			2: _echo_left = randi_range(6, 12)
			3: _start_peek()
	if state != State.CHASE and state != State.AMBUSH and _repath_t <= 0.0 and _hears_player(dist):
		_repath_t = 1.0
		state = State.INVESTIGATE
		_go_to(_near(ppos, 0.0, 2.0))  # 只聽得出大概方位
		return

	if _path_i < _path.size():
		return
	# 走到目的地了：先停一秒，再決定下一步
	_wait_t -= delta
	if _wait_t > 0.0:
		return
	_wait_t = 1.0
	if state == State.AMBUSH:
		_ambush_left -= 1  # 站著不動、不理聲音，等你自己走進視線
		if _ambush_left > 0:
			return
		state = State.PATROL
	if state == State.CHASE:
		_anger += 1
	if state == State.CHASE or state == State.INVESTIGATE:
		state = State.SEARCH
		_search_left = 3
	if state == State.SEARCH:
		_search_left -= 1
		if _search_left >= 0:
			_go_to(_hot_spot(global_position, 20.0))  # 搜附近玩家常待的地方
			return
		state = State.PATROL
		var roll := randf()
		if roll < 0.3:
			_go_to(_last_seen)  # 假裝放棄，其實折返最後看到你的地方
			return
		if roll < 0.6:
			state = State.AMBUSH  # 去你常待的地方站著等
			_ambush_left = 30
			_go_to(_hot_spot(ppos, INF))
			return
	# 巡邏：多半去玩家最常待的地方，偶爾直接晃到玩家附近（避免永遠遇不到）
	_go_to(_hot_spot(ppos, INF) if randf() < 0.6 else _near(ppos, 12.0, 25.0))


func _catch() -> void:
	var bm := get_parent().get_node_or_null("BlenderMap")  # 在 Blender 地圖裡被抓：播專屬的驚嚇音效
	if bm and bm.call("in_map", _player.global_position):
		bm.call("play_caught")
	_player._on_restart_requested()
	_reset()


# 狂暴模式：無視視線與聲音，永遠直奔玩家當下位置。導航到不了玩家時（路徑終點離玩家太遠）直接直線穿牆。
func _frenzy(delta: float, dist: float) -> bool:
	var ppos := _player.global_position
	state = State.CHASE
	_mood = Mood.RUSH
	if dist < catch_distance:
		_catch()
		return false
	_repath_t -= delta
	if _repath_t <= 0.0:
		_repath_t = 0.2
		_go_to(ppos)
		_noclip = _unreachable(ppos)
	var step := FRENZY_SPEED * delta
	if _noclip:
		global_position = global_position.move_toward(ppos + Vector3.UP * 0.3, step)
	elif _path_i < _path.size():
		global_position = global_position.move_toward(_path[_path_i], step)
		if global_position.distance_to(_path[_path_i]) < 0.05:
			_path_i += 1
	else:
		return false
	_step_t -= delta
	if _step_t <= 0.0:
		_step_t = 0.26
		_heavy.pitch_scale = randf_range(0.27, 0.33)
		_heavy.play()
	return true


# 導航路徑的終點離玩家太遠 = 牆或障礙完全擋住，繞不過去（跳躍中的高度差放寬容許）
func _unreachable(ppos: Vector3) -> bool:
	if _path.is_empty():
		return true
	var end := _path[_path.size() - 1]
	return Vector2(end.x - ppos.x, end.z - ppos.z).length() > 1.5 or absf(end.y - ppos.y) > 2.5


func _sees_player() -> bool:
	var eye := global_position + Vector3.UP * 1.6
	var head := _player.global_position + Vector3.UP * 1.5
	var light: Light3D = _player.flashlight
	var lit := light != null and light.visible
	if eye.distance_to(head) > (sight_range_flashlight if lit else sight_range_dark):
		return false
	return _clear_line(eye, head)


func _clear_line(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _snap(p: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, p)


# 幻影：瞬移到你背後（轉身才看得到）或前方霧裡（直接站在視線盡頭）
func _appear(behind: bool) -> void:
	var ppos := _player.global_position
	var cam: Camera3D = _player.camera
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() * (-1.0 if behind else 1.0)
	for i in 10:
		var p := _snap(ppos + fwd.rotated(Vector3.UP, randf_range(-0.5, 0.5)) * (randf_range(7.0, 10.0) if behind else randf_range(12.0, 22.0)))
		var d := p.distance_to(ppos)
		if absf(p.y - ppos.y - 0.3) < 1.0 and d > 6.5 and _clear_line(p + Vector3.UP * 1.6, ppos + Vector3.UP * 1.5):
			global_position = p
			_path = PackedVector3Array()
			state = State.APPARITION
			_app_t = 20.0
			_app_watch = 0.0
			return


# 幻影不追你：被你盯滿 0.6 秒後，你一移開視線牠就不見；你走到 5 公尺內牠才真的撲過來
func _haunt(delta: float, dist: float) -> void:
	_app_t -= delta
	if dist < 5.0:
		state = State.CHASE
		_mood = Mood.RUSH
		_repath_t = 0.0
	elif _watched():
		_app_watch += delta
	elif _app_watch > 0.6 or _app_t <= 0.0:
		_vanish()


func _vanish() -> void:
	var ppos := _player.global_position
	var spot := _home
	for i in 10:
		var p := _snap(_near(ppos, 30.0, 50.0))
		if p.distance_to(ppos) > 25.0:
			spot = p
			break
	global_position = spot
	_path = PackedVector3Array()
	state = State.PATROL


# 回聲腳步：你走路時，背後 3.5 公尺跟著響和你同節奏的腳步；你一停它就停
func _update_echo(delta: float) -> void:
	if _echo_left <= 0:
		return
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	if speed < 0.5:
		_echo_t = 0.25  # 你停下後，它會慢半拍才跟上
		return
	_echo_t -= delta
	if _echo_t > 0.0:
		return
	_echo_t = TAU / (_player.bob_frequency * speed)  # 和玩家自己的腳步同一個節奏公式
	var back := _player.global_transform.basis.z
	_echo.global_position = _player.global_position + back * 3.5 + Vector3.UP * 0.2
	_echo.pitch_scale = randf_range(0.85, 1.05)
	_echo.play()
	_echo_left -= 1


# 玩家的鏡頭正對著牠，而且中間沒有牆
func _watched() -> bool:
	var cam: Camera3D = _player.camera
	var to_me := (global_position + Vector3.UP * 1.2 - cam.global_position).normalized()
	return _sees and (-cam.global_transform.basis.z).dot(to_me) > 0.75


func _hears_player(dist: float) -> bool:
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	if speed < 0.5:
		return false
	return dist < (hear_range_sprint if speed > 4.0 else hear_range_walk)


func _hot_spot(center: Vector3, radius: float) -> Vector3:
	var cells: Array[Vector3i] = []
	var total := 0
	for cell: Vector3i in _heat:
		if _heat_pos[cell].distance_to(center) <= radius:
			cells.append(cell)
			total += _heat[cell]
	if cells.is_empty():
		return _near(center, 5.0, 15.0)
	var roll := randi() % total  # 待越久的格子越容易被抽中
	for cell in cells:
		roll -= _heat[cell]
		if roll < 0:
			return _heat_pos[cell]
	return center


func _near(center: Vector3, min_r: float, max_r: float) -> Vector3:
	var angle := randf() * TAU
	return center + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(min_r, max_r)


func _go_to(target: Vector3) -> void:
	# 目標不在可走範圍時，導航伺服器會自動改走到最近的可達點
	_path = NavigationServer3D.map_get_path(get_world_3d().navigation_map, global_position, target, true)
	_path_i = 0


# 回傳這一幀有沒有真的移動
func _move(delta: float) -> bool:
	if _path_i >= _path.size():
		return false
	var stalking := state == State.CHASE and _mood == Mood.STALK
	if stalking and _watched():
		return false  # 你盯著牠時牠一動也不動
	var speed := patrol_speed
	if state == State.CHASE:
		var bonus := 0.35 if _enraged_t > 0.0 else 0.0
		speed = minf(chase_speed + 0.1 * _anger + bonus, MAX_CHASE_SPEED)
	elif state != State.PATROL:
		speed = investigate_speed
	global_position = global_position.move_toward(_path[_path_i], speed * delta)
	if global_position.distance_to(_path[_path_i]) < 0.05:
		_path_i += 1
	# 腳步聲：走越快越密；尾隨和前往埋伏點時完全無聲
	_step_t -= delta
	if _step_t <= 0.0 and not stalking and state != State.AMBUSH:
		_step_t = 1.4 / speed
		_steps.play()
	return true


# shortcut: 只記錄「牠弄熄的燈」再點回來；若異常燈剛好在牠身邊被觸發熄滅，牠離開後會被誤點亮。要根治得讓異常燈自己標記已熄。
func _update_lights(dt: float) -> void:
	for light in _lights:
		var d: float = light.global_position.distance_to(global_position)
		if d < LIGHT_KILL_DIST:
			light.visible = false
			_dimmed[light] = randf_range(10.0, 15.0)  # 經過的走廊延遲 10–15 秒才復電
		elif d < LIGHT_FLICKER_DIST and randf() < 0.35:
			light.visible = false
			if not _dimmed.has(light):
				_dimmed[light] = 0.25
		elif _dimmed.has(light):
			_dimmed[light] -= dt
			if _dimmed[light] <= 0.0:
				light.visible = true
				_dimmed.erase(light)
			elif _dimmed[light] < 1.5:
				light.visible = randf() < 0.45  # 復電前先閃爍幾下


func _reset() -> void:
	_stop_ragdoll()
	global_position = _home
	_path = PackedVector3Array()
	_path_i = 0
	_echo_left = 0
	_snap_roll = 0.0
	_peek_lean = 0.0
	_flash_burn = 0.0
	_stagger_t = 0.0
	_enraged_t = 0.0
	_unconscious_t = 0.0
	_noclip = false
	_repath_t = 0.0
	state = State.PATROL


func _build_sprite() -> void:
	var scene_res := model_scene if model_scene else load(MODEL_PATH) as PackedScene
	if scene_res:
		_model = scene_res.instantiate()
		_model.position.y = -0.3  # 扣掉導航路徑浮在地板上方的 0.3 公尺，讓雙腳貼地
		add_child(_model)
		var players := _model.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty() and players[0] is AnimationPlayer:
			_anim = players[0]
			for anim_name in _anim.get_animation_list():
				var a := _anim.get_animation(anim_name)
				if a:
					a.loop_mode = Animation.LOOP_LINEAR
			if _anim.has_animation("Idle"):
				_anim.play("Idle")
		var skels := _model.find_children("*", "Skeleton3D", true, false)
		if not skels.is_empty() and skels[0] is Skeleton3D:
			_skel = skels[0]
			_head_bone = _skel.find_bone("head")
			_chest_bone = _skel.find_bone("chest")
			_skel.skeleton_updated.connect(_on_skeleton_updated)
			_build_ragdoll()
	_build_hitbox()


func _build_pov() -> void:
	if _model:
		for v in _model.find_children("*", "VisualInstance3D", true, false):
			v.layers = 1 << (POV_LAYER - 1)
	_pov_vp = SubViewport.new()
	_pov_vp.size = Vector2i(320, 240)
	_pov_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_pov_vp)
	_pov_cam = Camera3D.new()
	_pov_cam.cull_mask &= ~(1 << (POV_LAYER - 1))
	_pov_cam.fov = 95.0  # 廣角，像監視器魚眼
	_pov_cam.top_level = true
	_pov_vp.add_child(_pov_cam)

	var layer := CanvasLayer.new()
	layer.layer = 2  # 畫在 PS2 濾鏡（第 1 層）上方：靠近怪物時畫面劣化，螢幕仍看得清楚
	add_child(layer)
	_pov_panel = PanelContainer.new()
	var bezel := StyleBoxFlat.new()
	bezel.bg_color = Color(0.13, 0.13, 0.12)
	bezel.set_border_width_all(10)
	bezel.border_color = Color(0.22, 0.22, 0.2)
	bezel.set_corner_radius_all(6)
	_pov_panel.add_theme_stylebox_override("panel", bezel)
	_pov_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_pov_panel.offset_left = -POV_SIZE.x - 16
	_pov_panel.offset_top = -POV_SIZE.y - 16 - 28  # 28 = Win95 工作列高度
	_pov_panel.offset_right = -16
	_pov_panel.offset_bottom = -16 - 28
	_pov_panel.pivot_offset = Vector2(POV_SIZE.x * 0.5, POV_SIZE.y)  # 以底邊為軸往上翻
	_pov_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pov_panel.visible = false
	layer.add_child(_pov_panel)
	var screen := TextureRect.new()
	screen.texture = _pov_vp.get_texture()
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	screen.modulate = Color(1.0, 0.72, 0.68)  # 偏紅的監視器色調
	_pov_panel.add_child(screen)
	var rec := Label.new()
	rec.text = " ● REC  CAM-??"
	rec.add_theme_color_override("font_color", Color(1.0, 0.15, 0.1))
	rec.add_theme_font_size_override("font_size", 13)
	rec.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	rec.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_pov_panel.add_child(rec)


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and (k.physical_keycode == KEY_Q or k.keycode == KEY_Q):
		if _ui and _ui.is_popup_open():
			return
		_toggle_pov()


func _toggle_pov() -> void:
	_pov_open = not _pov_open
	if _pov_tween:
		_pov_tween.kill()
	_pov_tween = create_tween()
	if _pov_open:
		_pov_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_pov_panel.visible = true
		_pov_panel.scale = Vector2(1.0, 0.0)
		_pov_tween.tween_property(_pov_panel, "scale:y", 1.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_pov_tween.tween_property(_pov_panel, "scale:y", 0.0, 0.15)
		_pov_tween.tween_callback(func() -> void:
			_pov_panel.visible = false
			_pov_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		)


func _process(_delta: float) -> void:
	if not _pov_open:
		return
	_pov_panel.visible = not (_ui and _ui.is_popup_open())  # 開地圖、設定等視窗時先藏起來
	if state == State.UNCONSCIOUS and _head_pb:
		_pov_cam.global_transform = _head_pb.global_transform
		return
	# 攝影機跟著怪物的頭：面向模型正面（模型朝 +Z、攝影機朝 -Z），歪脖子時畫面也跟著歪
	var yaw := _model.rotation.y if _model else 0.0
	_pov_cam.global_position = global_position + Vector3.UP * (POV_EYE_Y - 0.3)
	_pov_cam.global_rotation = Vector3(0.0, yaw + PI, _snap_roll * 0.6)


func _on_skeleton_updated() -> void:
	if not _skel or state == State.UNCONSCIOUS:
		return
	if _head_bone >= 0 and absf(_snap_roll) > 0.001:
		var rot := _skel.get_bone_pose_rotation(_head_bone)
		_skel.set_bone_pose_rotation(_head_bone, rot * Quaternion(Vector3.FORWARD, _snap_roll))
	if _chest_bone >= 0 and absf(_peek_lean) > 0.001:
		var rot := _skel.get_bone_pose_rotation(_chest_bone)
		_skel.set_bone_pose_rotation(_chest_bone, rot * Quaternion(Vector3.FORWARD, _peek_lean))


func _update_visual(delta: float, moved: bool, dist: float) -> void:
	if not _model:
		return
	# 面向：凝視/幻影/探頭/近距離時盯著玩家，移動時面向行進方向
	var face_target := _player.global_position
	var look_at_player := not moved or state == State.STARE or state == State.APPARITION or state == State.PEEK or dist < NEAR_DIST
	if not look_at_player and _path_i < _path.size():
		face_target = _path[_path_i]
	var dir := face_target - global_position
	dir.y = 0.0
	if dir.length_squared() > 0.0001:
		var target_yaw := atan2(dir.x, dir.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, minf(delta * 10.0, 1.0))
	if _anim:
		var want := "Walk" if moved and _anim.has_animation("Walk") else "Idle"
		if _anim.has_animation(want) and _anim.current_animation != want:
			_anim.play(want, 0.15)
		if want == "Walk":
			_anim.speed_scale = 2.6 if _ui and _ui.frenzy_mode else 1.9 if _enraged_t > 0.0 else (1.6 if state == State.CHASE else 1.0)
		else:
			_anim.speed_scale = 1.0


# 轉角探頭窺視：找玩家前方附近有牆壁掩護的位置，歪身探出頭盯著玩家
func _start_peek() -> void:
	var ppos := _player.global_position
	var cam: Camera3D = _player.camera
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	for i in 10:
		var p := _snap(ppos + fwd.rotated(Vector3.UP, randf_range(-0.7, 0.7)) * randf_range(10.0, 20.0))
		if absf(p.y - ppos.y - 0.3) > 1.0 or p.distance_to(ppos) < 8.0:
			continue
		if not _clear_line(p + Vector3.UP * 1.6, ppos + Vector3.UP * 1.5):
			continue
		# 檢查左右是否有牆壁可以靠著探頭
		var right := (ppos - p).cross(Vector3.UP).normalized()
		var wall_r := not _clear_line(p + Vector3.UP * 1.4, p + Vector3.UP * 1.4 + right * 1.3)
		var wall_l := not _clear_line(p + Vector3.UP * 1.4, p + Vector3.UP * 1.4 - right * 1.3)
		if wall_r or wall_l:
			global_position = p
			_path = PackedVector3Array()
			state = State.PEEK
			_peek_lean = -0.48 if wall_r else 0.48
			_peek_t = 14.0
			_peek_watch = 0.0
			_snap_roll = 0.35 if wall_r else -0.35
			return


func _peek(delta: float, dist: float) -> void:
	_peek_t -= delta
	if dist < 5.5:
		_peek_lean = 0.0
		state = State.CHASE
		_mood = Mood.RUSH
		_repath_t = 0.0
		return
	if _watched():
		_peek_watch += delta
		if _peek_watch > 0.9:
			_peek_lean = 0.0
			if randf() < 0.5:
				state = State.CHASE
				_mood = Mood.RUSH
				_repath_t = 0.0
			else:
				_vanish()
			return
	elif _peek_t <= 0.0:
		_peek_lean = 0.0
		_vanish()


# 手電筒直射臉部：累積超過 1.2 秒會抽搐僵直並短暫暴走追擊
func _update_flashlight_reaction(delta: float, dist: float) -> void:
	var light: Light3D = _player.flashlight
	var lit := light != null and light.visible
	if lit and dist < 14.0 and _watched() and _stagger_t <= 0.0:
		_flash_burn += delta
		if _flash_burn >= 1.2:
			_flash_burn = 0.0
			_stagger_t = 0.45
			_enraged_t = 4.5
			_peek_lean = 0.0
			_snap_roll = [-1.15, 1.15].pick_random()
			if _snap_sfx:
				_snap_sfx.pitch_scale = 0.35
				_snap_sfx.play()
			state = State.CHASE
			_mood = Mood.RUSH
			_repath_t = 0.0
	else:
		_flash_burn = maxf(0.0, _flash_burn - delta * 0.5)


# 站著不動時偶爾「咔」一聲歪頭折脖子
func _update_neck_snap(delta: float, moved: bool) -> void:
	if moved and _stagger_t <= 0.0:
		_snap_roll = lerpf(_snap_roll, 0.0, minf(delta * 8.0, 1.0))
		return
	if state == State.PEEK:
		return
	_snap_t -= delta
	if _snap_t <= 0.0:
		_snap_t = randf_range(1.6, 3.8)
		_snap_roll = randf_range(-1.25, 1.25) if absf(_snap_roll) < 0.2 else 0.0
		if _snap_sfx and global_position.distance_to(_player.global_position) < 18.0:
			_snap_sfx.pitch_scale = randf_range(0.45, 0.7)
			_snap_sfx.play()


# 埋伏或搜索時在附近黑暗處發出誘餌電流怪聲
func _update_lure(delta: float, dist: float) -> void:
	if state != State.AMBUSH and state != State.SEARCH:
		return
	_lure_t -= delta
	if _lure_t > 0.0:
		return
	_lure_t = randf_range(12.0, 22.0)
	if dist > 8.0 and dist < 26.0 and _lure_sfx:
		_lure_sfx.global_position = _snap(_near(_player.global_position, 8.0, 16.0)) + Vector3.UP * 1.4
		_lure_sfx.pitch_scale = randf_range(0.55, 0.78)
		_lure_sfx.play()


func _build_hitbox() -> void:
	_hitbox = Area3D.new()
	_hitbox.name = "Hitbox"
	_hitbox.collision_layer = 2
	_hitbox.collision_mask = 0
	_hitbox.monitoring = false
	_hitbox.monitorable = true
	_hitbox.set_meta("monster", self)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.48
	cap.height = 1.85
	cs.shape = cap
	cs.position = Vector3(0.0, 0.95, 0.0)
	_hitbox.add_child(cs)
	add_child(_hitbox)


func _build_ragdoll() -> void:
	if not _skel:
		return
	_ragdoll_sim = PhysicalBoneSimulator3D.new()
	_ragdoll_sim.name = "RagdollSim"
	_ragdoll_sim.active = false
	_skel.add_child(_ragdoll_sim)

	for i in _skel.get_bone_count():
		var bname := _skel.get_bone_name(i)
		var pb := PhysicalBone3D.new()
		pb.name = "PB_" + bname
		pb.bone_name = bname
		pb.set_meta("monster", self)
		pb.collision_layer = 4
		pb.collision_mask = 1
		pb.bounce = 0.38
		pb.friction = 0.55
		pb.linear_damp = 0.04
		pb.angular_damp = 0.04
		pb.mass = 12.0 if bname in ["hips", "chest"] else (10.0 if bname == "spine" else (5.0 if bname == "head" else 3.5))

		if _skel.get_bone_parent(i) >= 0:
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			pb.set("joint_constraints/swing_span", deg_to_rad(85.0))
			pb.set("joint_constraints/twist_span", deg_to_rad(45.0))

		var bpose := _skel.get_bone_global_pose(i)
		var children := _skel.get_bone_children(i)
		var target_child := -1
		if not children.is_empty():
			target_child = children[0]
			if bname == "hips":
				var sp := _skel.find_bone("spine")
				if sp >= 0:
					target_child = sp
			elif bname == "chest":
				var nk := _skel.find_bone("neck")
				if nk >= 0:
					target_child = nk

		var cs := CollisionShape3D.new()
		if target_child >= 0:
			var cpose := _skel.get_bone_global_pose(target_child)
			var local_vec := bpose.basis.inverse() * (cpose.origin - bpose.origin)
			var blen := maxf(local_vec.length(), 0.14)
			var dir := local_vec.normalized() if local_vec.length_squared() > 0.0001 else Vector3.UP
			var q := Quaternion(Vector3.UP, dir)
			pb.body_offset = Transform3D(Basis(q), local_vec * 0.5)
			var cap := CapsuleShape3D.new()
			cap.height = maxf(blen * 0.85, 0.16)
			cap.radius = 0.15 if bname in ["hips", "spine", "chest"] else 0.065
			cs.shape = cap
		elif bname == "head":
			pb.body_offset = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.12, 0.0))
			var sph := SphereShape3D.new()
			sph.radius = 0.15
			cs.shape = sph
		else:
			pb.body_offset = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.17, 0.0))
			var cap := CapsuleShape3D.new()
			cap.height = 0.34
			cap.radius = 0.06
			cs.shape = cap

		pb.add_child(cs)
		pb.transform = bpose
		_ragdoll_sim.add_child(pb)
		_phys_bones.append(pb)
		if bname == "hips":
			_hips_pb = pb
		elif bname == "head":
			_head_pb = pb


func hit_by_shotgun(_hit_pos: Vector3, blast_dir: Vector3, pellet_count: int) -> void:
	var was_unconscious := state == State.UNCONSCIOUS
	state = State.UNCONSCIOUS
	_unconscious_t = UNCONSCIOUS_DURATION
	if not was_unconscious:
		_path = PackedVector3Array()
		_path_i = 0
		_snap_roll = 0.0
		_peek_lean = 0.0
		_stagger_t = 0.0
		_enraged_t = 0.0
		_flash_burn = 0.0
		_echo_left = 0
		_restore_all_lights()
		if _post_mat:
			for p in _post_base:
				_post_mat.set_shader_parameter(p, _post_base[p])
		if _hitbox:
			_hitbox.set_deferred("monitorable", false)
		if _anim:
			_anim.stop()
		if _ragdoll_sim:
			_ragdoll_sim.active = true
			_ragdoll_sim.physical_bones_start_simulation()
	if _ragdoll_sfx:
		_ragdoll_sfx.pitch_scale = randf_range(0.85, 1.1)
		_ragdoll_sfx.play()
	call_deferred("_apply_ragdoll_blast", blast_dir, pellet_count)


func _apply_ragdoll_blast(blast_dir: Vector3, pellet_count: int) -> void:
	if not _ragdoll_sim or not _ragdoll_sim.active:
		return
	var flat_dir := Vector3(blast_dir.x, 0.0, blast_dir.z)
	if flat_dir.length_squared() < 0.001:
		flat_dir = Vector3.FORWARD
	var base_dir := (flat_dir.normalized() + Vector3(0.0, 0.65, 0.0)).normalized()
	var launch_speed := lerpf(24.0, 38.0, clampf(float(pellet_count) / 8.0, 0.0, 1.0))
	for pb in _phys_bones:
		var jitter := Vector3(randf_range(-0.25, 0.25), randf_range(-0.08, 0.35), randf_range(-0.25, 0.25))
		var blast := (base_dir + jitter).normalized() * pb.mass * launch_speed
		pb.apply_central_impulse(blast)
		var off_center := Vector3(randf_range(-0.35, 0.35), randf_range(-0.35, 0.35), randf_range(-0.35, 0.35))
		pb.apply_impulse(blast * 0.35, off_center)


func _wake_up_from_ragdoll() -> void:
	var wake_pos := _hips_pb.global_position if _hips_pb else global_position
	_stop_ragdoll()
	global_position = _snap(wake_pos)
	state = State.PATROL
	_repath_t = 0.0
	_wait_t = 1.5


func _stop_ragdoll() -> void:
	if _ragdoll_sim and _ragdoll_sim.active:
		_ragdoll_sim.physical_bones_stop_simulation()
		_ragdoll_sim.active = false
	if _skel:
		_skel.reset_bone_poses()
	if _model:
		_model.position = Vector3(0.0, -0.3, 0.0)
		_model.rotation = Vector3.ZERO
	if _anim and _anim.has_animation("Idle"):
		_anim.play("Idle")
	if _hitbox:
		_hitbox.set_deferred("monitorable", true)


func _restore_all_lights() -> void:
	for light in _dimmed:
		if is_instance_valid(light):
			light.visible = true
	_dimmed.clear()


func on_gunshot_heard(gun_pos: Vector3) -> void:
	if state == State.UNCONSCIOUS or state == State.CHASE or not _nav_ready:
		return
	if global_position.distance_to(gun_pos) < 35.0:
		state = State.INVESTIGATE
		_go_to(_near(gun_pos, 0.0, 2.5))
		_repath_t = 1.5
