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
const FRENZY_SPEED := 20.0  # 狂暴追獵模式：玩家跑速四倍，極高速追擊
const CLIMB_SPEED_RATIO := 0.75  # 爬牆速度佔當前移速的比例
const WALL_OFFSET := 0.42  # 與牆面保持的距離，避免穿模或穿牆
const STUCK_CHECK_TIME := 1.4  # 連續位移不足超過幾秒就判定卡住
const STUCK_MIN_MOVE := 0.35   # 判定有前進的最小位移（公尺）
const STUCK_DEDUP_RADIUS := 2.0  # 同一區域半徑內重複卡住只累加次數，不重複插標記
const STUCK_LOG_PATH := "user://monster_stuck_log.txt"

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
var _path_types := PackedInt32Array()
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
var _climbing := false           # 目前是否正在爬牆
var _climb_normal := Vector3.UP  # 正在攀爬牆面的外法線
var _climb_dir := Vector3.UP     # 當前沿牆面攀爬的方向
var _climb_t := 0.0              # 本次連續爬牆時間
var _climb_cooldown := 0.0       # 剛結束爬牆的短暫冷卻
var _climb_last_wall_pos := Vector3.ZERO
var _current_speed := 0.0
var _current_target := Vector3.ZERO
var _nav_unreachable := false
var _nav_links_count := 0
var _last_blocker_name := ""
var _last_blocker_pos := Vector3.ZERO
var _stuck_anchor := Vector3.ZERO
var _stuck_t := 0.0
var _stuck_cooldown := 0.0
var _pos_history: Array[Vector3] = []
var _pos_sample_t := 0.0
var _is_stuck := false
var _last_stuck_reason := ""
var _stuck_reports: Array[Dictionary] = []
var _debug_markers_root: Node3D
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
	_stuck_anchor = _home
	_current_target = _home
	_player = get_parent().get_node("Player")
	_ui = get_parent().get_node_or_null("Win95UI")
	if _ui:
		_ui.restart_requested.connect(_reset)
	_build_sprite()
	_build_pov()
	_debug_markers_root = Node3D.new()
	_debug_markers_root.name = "MonsterDebugMarkers"
	_debug_markers_root.top_level = true
	_debug_markers_root.visible = _ui != null and _ui.monster_debug_mode
	add_child(_debug_markers_root)
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
		var nav_map := get_world_3d().navigation_map
		var before_iter := NavigationServer3D.map_get_iteration_id(nav_map)
		var region := NavigationRegion3D.new()
		region.navigation_mesh = nm
		get_parent().add_child(region)
		_finalize_navmesh.call_deferred(before_iter)
	)


func _finalize_navmesh(before_iter: int) -> void:
	var nav_map := get_world_3d().navigation_map
	# 必須等到「加入 NavigationRegion3D 之後」的 iteration_id 增加，網格才真的同步完成
	var tries := 0
	while NavigationServer3D.map_get_iteration_id(nav_map) <= before_iter and tries < 120:
		await get_tree().physics_frame
		tries += 1
	var bm := get_parent().get_node_or_null("BlenderMap")
	if bm and bm.has_method("build_strata_nav_links"):
		var link_before := NavigationServer3D.map_get_iteration_id(nav_map)
		_nav_links_count = int(bm.call("build_strata_nav_links", nav_map))
		var t2 := 0
		while NavigationServer3D.map_get_iteration_id(nav_map) <= link_before and t2 < 30:
			await get_tree().physics_frame
			t2 += 1
	_nav_ready = true


func _physics_process(delta: float) -> void:
	if _debug_markers_root:
		_debug_markers_root.visible = _ui != null and _ui.monster_debug_mode
	if not _nav_ready or (_ui and _ui.is_popup_open()):
		return  # 玩家讀文件時動不了，怪物也暫停才公平
	if _climb_cooldown > 0.0:
		_climb_cooldown = maxf(0.0, _climb_cooldown - delta)
	if _stuck_cooldown > 0.0:
		_stuck_cooldown = maxf(0.0, _stuck_cooldown - delta)
	if state == State.UNCONSCIOUS:
		_unconscious_t -= delta
		if _unconscious_t <= 0.0:
			_wake_up_from_ragdoll()
		return
	var dist := global_position.distance_to(_player.global_position)
	if _enraged_t > 0.0:
		_enraged_t -= delta
	var moved := false
	var wants_move := false
	var frenzy: bool = _ui != null and _ui.frenzy_mode
	if frenzy:
		wants_move = true
		moved = _frenzy(delta, dist)
	elif _stagger_t > 0.0:
		_stagger_t -= delta
		_current_speed = 0.0
	else:
		_think(delta)
		var stalking_frozen := state == State.CHASE and _mood == Mood.STALK and _watched()
		wants_move = not stalking_frozen and state not in [State.STARE, State.APPARITION, State.PEEK] and (_climbing or _path_i < _path.size() or state == State.CHASE)
		moved = _move(delta)
	_update_stuck_monitor(delta, wants_move, _current_target)
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


# 狂暴追獵模式：無視視線與聲音，極高速直奔玩家；不再穿牆，改為遇牆或高低差直接爬牆追擊。
func _frenzy(delta: float, dist: float) -> bool:
	var ppos := _player.global_position
	_current_target = ppos
	state = State.CHASE
	_mood = Mood.RUSH
	if dist < catch_distance:
		_catch()
		return false
	var moved := false
	if _climbing:
		_current_speed = FRENZY_SPEED * CLIMB_SPEED_RATIO
		moved = _step_climb(delta, ppos, FRENZY_SPEED)
	else:
		_repath_t -= delta
		if _repath_t <= 0.0:
			_repath_t = 0.18
			_go_to(ppos)
			_nav_unreachable = _unreachable(ppos)
		_current_speed = FRENZY_SPEED
		var step := FRENZY_SPEED * delta
		var height_diff := ppos.y - global_position.y
		var near_path_end := _path.is_empty() or _path_i >= _path.size() or global_position.distance_to(_path[_path.size() - 1]) < 1.35
		if _climb_cooldown <= 0.0 and ((_nav_unreachable and near_path_end) or (height_diff > 0.75 and Vector2(ppos.x - global_position.x, ppos.z - global_position.z).length() < 4.5)):
			var wall_hit := _probe_wall_toward(ppos, 1.55)
			if not wall_hit.is_empty():
				_start_climb(wall_hit.normal, wall_hit.position)
				moved = _step_climb(delta, ppos, FRENZY_SPEED)
			elif _path_i < _path.size():
				moved = _move_along_path(step, true)
			else:
				moved = _move_horizontal_checked(ppos, step, true)
		elif _path_i < _path.size():
			moved = _move_along_path(step, true)
		else:
			moved = _move_horizontal_checked(ppos, step, true)
	if global_position.distance_to(ppos) < catch_distance:
		_catch()
		return false
	if not moved:
		return false
	_step_t -= delta
	if _step_t <= 0.0:
		_step_t = 0.14 if not _climbing else 0.12
		_heavy.pitch_scale = randf_range(0.42, 0.52) if _climbing else randf_range(0.28, 0.36)
		_heavy.play()
	return true


# 導航路徑的終點離目標太遠 = 牆或高度差擋住，無法僅靠地面導航抵達
func _unreachable(target_pos: Vector3) -> bool:
	if _path.is_empty():
		return true
	var end := _path[_path.size() - 1]
	return Vector2(end.x - target_pos.x, end.z - target_pos.z).length() > 1.5 or absf(end.y - target_pos.y) > 1.6


func _raycast_world(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var excludes: Array[RID] = []
	if _player:
		excludes.append(_player.get_rid())
	for pb in _phys_bones:
		if is_instance_valid(pb):
			excludes.append(pb.get_rid())
	query.exclude = excludes
	return get_world_3d().direct_space_state.intersect_ray(query)


func _record_blocker(hit: Dictionary) -> void:
	if hit.is_empty():
		return
	var col = hit.get("collider")
	if col is Node:
		var n := col as Node
		var parent_name: String = String(n.get_parent().name) if n.get_parent() else ""
		_last_blocker_name = "%s/%s" % [parent_name, n.name] if not parent_name.is_empty() else String(n.name)
	else:
		_last_blocker_name = str(col)
	_last_blocker_pos = hit.get("position", global_position)


func _probe_wall_toward(target_pos: Vector3, max_dist: float = 1.6) -> Dictionary:
	var dir := target_pos - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return {}
	dir = dir.normalized()
	var origin := global_position + Vector3.UP * 0.9
	for angle_deg in [0.0, 28.0, -28.0, 60.0, -60.0]:
		var ray_dir := dir.rotated(Vector3.UP, deg_to_rad(angle_deg))
		var hit := _raycast_world(origin, origin + ray_dir * max_dist)
		if not hit.is_empty() and absf(hit.normal.y) < 0.55:
			_record_blocker(hit)
			return hit
	return {}


func _start_climb(normal: Vector3, hit_pos: Vector3) -> void:
	# 目標在明顯下方且自己腳下已經是實心地板時，不要再貼牆往下爬（避免貼牆→撞地板→彈開→再貼牆的抽搐迴圈）
	if _current_target.y < global_position.y - 1.2:
		var floor_under := _raycast_world(global_position + Vector3.UP * 0.2, global_position + Vector3.DOWN * 1.1)
		if not floor_under.is_empty() and floor_under.normal.y > 0.6:
			_climb_cooldown = maxf(_climb_cooldown, 0.8)
			return
	_climbing = true
	_climb_normal = normal.normalized()
	_climb_dir = Vector3.UP
	_climb_t = 0.0
	_climb_last_wall_pos = hit_pos
	global_position = Vector3(hit_pos.x, global_position.y, hit_pos.z) + _climb_normal * WALL_OFFSET
	_path = PackedVector3Array()
	_path_i = 0


func _stop_climb(cooldown: float = 0.35) -> void:
	_climbing = false
	_climb_t = 0.0
	_climb_cooldown = maxf(_climb_cooldown, cooldown)
	_repath_t = 0.0


func _move_along_path(step: float, allow_climb_on_wall: bool) -> bool:
	var remaining := step
	var any_moved := false
	var safety := 0
	while remaining > 0.001 and _path_i < _path.size() and safety < 12:
		safety += 1
		var wp := _path[_path_i]
		var delta_vec := wp - global_position
		var seg_dist := delta_vec.length()
		if seg_dist < 0.05:
			_path_i += 1
			continue
		var move_dist := minf(remaining, seg_dist)
		var next_pos := global_position + delta_vec.normalized() * move_dist
		# 若此段是顯式建立的跨層 NavigationLink3D，允許沿連結垂直上下而不被樓板擋住
		var on_nav_link := (_path_i < _path_types.size() and _path_types[_path_i] == NavigationPathQueryResult3D.PATH_SEGMENT_TYPE_LINK) \
			or (_path_i > 0 and _path_i - 1 < _path_types.size() and _path_types[_path_i - 1] == NavigationPathQueryResult3D.PATH_SEGMENT_TYPE_LINK)
		if not on_nav_link:
			# 腰部高度防穿牆檢查：若路徑切角撞到實心垂直牆，絕不穿牆
			var wall_hit := _raycast_world(global_position + Vector3.UP * 0.9, next_pos + Vector3.UP * 0.9)
			if not wall_hit.is_empty() and absf(wall_hit.normal.y) < 0.55:
				_record_blocker(wall_hit)
				var hit_pos: Vector3 = wall_hit.position
				var hit_n: Vector3 = wall_hit.normal
				var safe_pos: Vector3 = Vector3(hit_pos.x, global_position.y, hit_pos.z) + hit_n * WALL_OFFSET
				if global_position.distance_to(safe_pos) > 0.005:
					global_position = safe_pos
					any_moved = true
				if allow_climb_on_wall and _climb_cooldown <= 0.0:
					_start_climb(hit_n, hit_pos)
				break
		global_position = next_pos
		remaining -= move_dist
		any_moved = true
		if global_position.distance_to(wp) < 0.05:
			_path_i += 1
	return any_moved


func _move_horizontal_checked(target_pos: Vector3, step: float, allow_climb_on_wall: bool) -> bool:
	var flat := Vector3(target_pos.x - global_position.x, 0.0, target_pos.z - global_position.z)
	var flat_dist := flat.length()
	if flat_dist < 0.05:
		return false
	var move_dist := minf(step, flat_dist)
	var dir := flat / flat_dist
	var next_pos := global_position + dir * move_dist
	# 嚴格防穿牆射線：檢查前方 WALL_OFFSET + move_dist
	var ray_from := global_position + Vector3.UP * 0.9
	var ray_to := ray_from + dir * (move_dist + WALL_OFFSET)
	var wall_hit := _raycast_world(ray_from, ray_to)
	if not wall_hit.is_empty() and absf(wall_hit.normal.y) < 0.55:
		_record_blocker(wall_hit)
		var hit_pos: Vector3 = wall_hit.position
		var hit_n: Vector3 = wall_hit.normal
		var stop_pos: Vector3 = Vector3(hit_pos.x, global_position.y, hit_pos.z) + hit_n * WALL_OFFSET
		var moved_before_hit := global_position.distance_to(stop_pos) > 0.005
		global_position = stop_pos
		if allow_climb_on_wall and _climb_cooldown <= 0.0:
			_start_climb(hit_n, hit_pos)
			return true
		return moved_before_hit
	# 檢查落腳地板，避免懸空走出虛空
	var floor_hit := _raycast_world(next_pos + Vector3.UP * 0.8, next_pos + Vector3.DOWN * 3.0)
	if not floor_hit.is_empty() and floor_hit.normal.y > 0.55:
		global_position = Vector3(next_pos.x, floor_hit.position.y + 0.3, next_pos.z)
		return true
	# 下方無地板（可能是懸崖/虛空）：不走出去
	return false


func _step_climb(delta: float, target_pos: Vector3, base_speed: float) -> bool:
	_climb_t += delta
	var climb_speed := base_speed * CLIMB_SPEED_RATIO
	var step := climb_speed * delta
	var to_target := target_pos - global_position
	var to_target_n := to_target.normalized() if to_target.length_squared() > 0.0001 else Vector3.UP
	var along := to_target - _climb_normal * to_target.dot(_climb_normal)
	# 目標在明顯下方時優先往下爬，避免在室內盲目往上爬撞天花板；目標在同高或上方時才往上爬翻牆
	if target_pos.y < global_position.y - 2.0:
		along.y = minf(along.y, -1.0)
	elif _climb_normal.dot(to_target_n) < -0.15 or target_pos.y > global_position.y - 0.15:
		along.y = maxf(along.y, 1.25)
	if along.length_squared() < 0.001:
		along = Vector3.DOWN if target_pos.y < global_position.y - 2.0 else Vector3.UP
	_climb_dir = along.normalized()

	# 檢查攀爬前進方向是否撞到天花板、轉角牆或地板
	var probe_from := global_position + _climb_normal * 0.12
	var fwd_hit := _raycast_world(probe_from, probe_from + _climb_dir * (step + 0.65))
	if not fwd_hit.is_empty():
		_record_blocker(fwd_hit)
		if fwd_hit.normal.y < -0.5:
			# 撞到天花板：改沿牆面水平橫移繞開
			var horiz := Vector3(along.x, 0.0, along.z)
			if horiz.length_squared() > 0.01:
				var horiz_dir := horiz.normalized()
				var side_hit := _raycast_world(probe_from, probe_from + horiz_dir * (step + 0.55))
				if side_hit.is_empty():
					_climb_dir = horiz_dir
				else:
					_record_blocker(side_hit)
					_report_stuck("爬牆被天花板與側牆同時擋住", target_pos)
					_drop_to_floor_from_climb(0.8)
					return false
			else:
				_report_stuck("爬牆被天花板擋住，無法再往上", target_pos)
				_drop_to_floor_from_climb(0.8)
				return false
		elif absf(fwd_hit.normal.y) < 0.55:
			# 遇到內轉角另一面牆：無縫轉貼新牆面繼續爬
			_climb_normal = fwd_hit.normal.normalized()
			global_position = fwd_hit.position + _climb_normal * WALL_OFFSET
			_climb_last_wall_pos = fwd_hit.position
			return true
		elif fwd_hit.normal.y > 0.6 and _climb_dir.y < 0.0:
			# 往下爬踩到地板：落地結束爬牆
			global_position = fwd_hit.position + Vector3.UP * 0.3
			_stop_climb(0.3)
			return true

	var next_pos := global_position + _climb_dir * step
	# 確認背後牆面是否還在
	var wall_check := _raycast_world(next_pos + _climb_normal * 0.3, next_pos - _climb_normal * 1.15)
	if not wall_check.is_empty() and absf(wall_check.normal.y) < 0.65:
		_climb_normal = _climb_normal.lerp(wall_check.normal, 0.55).normalized()
		global_position = wall_check.position + _climb_normal * WALL_OFFSET
		_climb_last_wall_pos = wall_check.position
		# 若已爬到與目標相近高度、腳下有地板且能直接看到目標，安全下牆
		if _climb_t > 0.35 and absf(global_position.y - target_pos.y) < 0.9:
			var under := _raycast_world(global_position + Vector3.UP * 0.25, global_position + Vector3.DOWN * 1.15)
			if not under.is_empty() and under.normal.y > 0.6 and _clear_line(global_position + Vector3.UP * 0.9, target_pos + Vector3.UP * 0.9):
				global_position = under.position + Vector3.UP * 0.3
				_stop_climb(0.45)
		return true

	# 牆面結束（爬到牆頂或外轉角）：嘗試翻上牆頂平台
	var top_probe := next_pos - _climb_normal * 0.85 + Vector3.UP * 0.75
	var ledge_hit := _raycast_world(top_probe, top_probe + Vector3.DOWN * 2.2)
	if not ledge_hit.is_empty() and ledge_hit.normal.y > 0.55:
		global_position = ledge_hit.position + Vector3.UP * 0.3
		_stop_climb(0.35)
		return true

	# 沒翻到平台：看看正下方有沒有安全地板可落腳
	if _drop_to_floor_from_climb(0.45):
		return true
	_report_stuck("爬牆邊緣找不到可翻越的平台或落腳地板", target_pos)
	return false


func _drop_to_floor_from_climb(cooldown: float) -> bool:
	var floor_hit := _raycast_world(global_position + Vector3.UP * 0.3, global_position + Vector3.DOWN * 12.0)
	_stop_climb(cooldown)
	if not floor_hit.is_empty() and floor_hit.normal.y > 0.55:
		global_position = floor_hit.position + Vector3.UP * 0.3
		return true
	return false


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
	# 目標不在可走範圍時，導航伺服器會自動改走到最近的可達點；同時記錄每段是否為 NavigationLink3D
	_current_target = target
	var params := NavigationPathQueryParameters3D.new()
	params.map = get_world_3d().navigation_map
	params.start_position = global_position
	params.target_position = target
	params.path_postprocessing = NavigationPathQueryParameters3D.PATH_POSTPROCESSING_CORRIDORFUNNEL
	params.metadata_flags = NavigationPathQueryParameters3D.PATH_METADATA_INCLUDE_TYPES
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(params, result)
	_path = result.path
	_path_types = result.path_types
	_path_i = 0
	_nav_unreachable = _unreachable(target)


# 回傳這一幀有沒有真的移動
func _move(delta: float) -> bool:
	var stalking := state == State.CHASE and _mood == Mood.STALK
	if stalking and _watched():
		_current_speed = 0.0
		return false  # 你盯著牠時牠一動也不動
	var speed := patrol_speed
	if state == State.CHASE:
		var bonus := 0.35 if _enraged_t > 0.0 else 0.0
		speed = minf(chase_speed + 0.1 * _anger + bonus, MAX_CHASE_SPEED)
	elif state != State.PATROL:
		speed = investigate_speed
	_current_speed = speed * CLIMB_SPEED_RATIO if _climbing else speed
	var moved := false
	if _climbing:
		moved = _step_climb(delta, _current_target, speed)
	elif _path_i < _path.size():
		moved = _move_along_path(speed * delta, state == State.CHASE)
	elif state == State.CHASE and _climb_cooldown <= 0.0 and _nav_unreachable:
		var wall_hit := _probe_wall_toward(_current_target, 1.55)
		if not wall_hit.is_empty():
			_start_climb(wall_hit.normal, wall_hit.position)
			moved = _step_climb(delta, _current_target, speed)
		else:
			moved = _move_horizontal_checked(_current_target, speed * delta, true)
	else:
		_current_speed = 0.0
		return false
	if not moved:
		return false
	# 腳步聲：走越快越密；尾隨和前往埋伏點時完全無聲
	_step_t -= delta
	if _step_t <= 0.0 and not stalking and state != State.AMBUSH:
		_step_t = 1.4 / maxf(_current_speed, 0.5)
		_steps.pitch_scale = 0.78 if _climbing else 0.55
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
	_climbing = false
	_climb_normal = Vector3.UP
	_climb_dir = Vector3.UP
	_climb_t = 0.0
	_climb_cooldown = 0.0
	_nav_unreachable = false
	_stuck_anchor = _home
	_stuck_t = 0.0
	_pos_history.clear()
	_pos_sample_t = 0.0
	_is_stuck = false
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
	# 攝影機跟著怪物的頭：面向模型正面（模型朝 +Z、攝影機朝 -Z），爬牆時視角跟著傾倒
	if _climbing and _model:
		var mb := _model.global_basis.orthonormalized()
		_pov_cam.global_position = _model.global_position + mb.y * POV_EYE_Y
		_pov_cam.global_basis = Basis(-mb.x, mb.y, -mb.z)
		return
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
	if _climbing:
		# 爬牆姿勢：雙腳貼在牆面（local +Y 朝牆外法線、local +Z 朝攀爬方向）
		var y_axis := _climb_normal.normalized()
		var z_proj := _climb_dir - y_axis * _climb_dir.dot(y_axis)
		var z_axis := z_proj.normalized() if z_proj.length_squared() > 0.0001 else Vector3.UP
		var x_axis := y_axis.cross(z_axis)
		if x_axis.length_squared() < 0.0001:
			x_axis = Vector3.RIGHT
		else:
			x_axis = x_axis.normalized()
		z_axis = x_axis.cross(y_axis).normalized()
		var target_basis := Basis(x_axis, y_axis, z_axis).orthonormalized()
		var cur_q := _model.basis.orthonormalized().get_rotation_quaternion()
		_model.basis = Basis(cur_q.slerp(target_basis.get_rotation_quaternion(), minf(delta * 14.0, 1.0)))
		_model.position = _model.position.lerp(-y_axis * WALL_OFFSET, minf(delta * 14.0, 1.0))
	else:
		# 面向：凝視/幻影/探頭/近距離時盯著玩家，移動時面向行進方向
		var face_target := _player.global_position
		var look_at_player := not moved or state == State.STARE or state == State.APPARITION or state == State.PEEK or dist < NEAR_DIST
		if not look_at_player and _path_i < _path.size():
			face_target = _path[_path_i]
		var dir := face_target - global_position
		dir.y = 0.0
		var target_yaw := _model.rotation.y
		if dir.length_squared() > 0.0001:
			target_yaw = atan2(dir.x, dir.z)
		var target_basis := Basis(Vector3.UP, target_yaw)
		var cur_q := _model.basis.orthonormalized().get_rotation_quaternion()
		_model.basis = Basis(cur_q.slerp(target_basis.get_rotation_quaternion(), minf(delta * 11.0, 1.0)))
		_model.position = _model.position.lerp(Vector3(0.0, -0.3, 0.0), minf(delta * 12.0, 1.0))
	if _anim:
		var want := "Walk" if moved and _anim.has_animation("Walk") else "Idle"
		if _anim.has_animation(want) and _anim.current_animation != want:
			_anim.play(want, 0.15)
		if want == "Walk":
			if _ui and _ui.frenzy_mode:
				_anim.speed_scale = 3.6 if _climbing else 4.2
			elif _climbing:
				_anim.speed_scale = 1.9
			elif _enraged_t > 0.0:
				_anim.speed_scale = 1.9
			else:
				_anim.speed_scale = 1.6 if state == State.CHASE else 1.0
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
		_climbing = false
		_climb_t = 0.0
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


# ==================== 怪物卡點除錯與回報系統 ====================

func _state_label() -> String:
	if _ui and _ui.frenzy_mode:
		return "狂暴追獵(爬牆)" if _climbing else "狂暴追獵"
	var base := ""
	match state:
		State.PATROL: base = "巡邏"
		State.INVESTIGATE: base = "調查"
		State.STARE: base = "凝視"
		State.CHASE: base = "追擊"
		State.SEARCH: base = "搜索"
		State.AMBUSH: base = "埋伏"
		State.APPARITION: base = "幻影"
		State.PEEK: base = "窺視"
		State.UNCONSCIOUS: base = "昏迷"
		_: base = "未知"
	return base + "(爬牆)" if _climbing else base


func _current_layer_name() -> String:
	if _ui and _ui.has_method("get_current_layer_name"):
		return _ui.call("get_current_layer_name")
	return "未知層級"


func _update_stuck_monitor(delta: float, wants_move: bool, target_pos: Vector3) -> void:
	if not wants_move:
		_stuck_anchor = global_position
		_stuck_t = 0.0
		_pos_history.clear()
		_pos_sample_t = 0.0
		_is_stuck = false
		return

	# 1. 滾動視窗偵測「原地抽搐 / 來回震盪」（每 0.2 秒取樣一次，保留最近 2.0 秒）
	_pos_sample_t += delta
	if _pos_sample_t >= 0.2:
		_pos_sample_t = 0.0
		_pos_history.append(global_position)
		if _pos_history.size() > 10:
			_pos_history.remove_at(0)
		if _pos_history.size() >= 10:
			var origin := _pos_history[0]
			var max_spread := 0.0
			for pt in _pos_history:
				max_spread = maxf(max_spread, origin.distance_to(pt))
			var net_move := global_position.distance_to(origin)
			var spread_limit := 1.8 if (_ui and _ui.frenzy_mode) else 0.9
			if max_spread < spread_limit and net_move < spread_limit * 0.75:
				_is_stuck = true
				var osc_reason := "原地抽搐／來回卡死（2 秒內活動範圍僅 %.2fm）" % max_spread
				if _nav_unreachable:
					osc_reason = "導航不可達且原地抽搐（2 秒內活動範圍 %.2fm）" % max_spread
				_report_stuck(osc_reason, target_pos)
				_pos_history.clear()
				_stuck_t = 0.0
				_stuck_anchor = global_position
				return

	# 2. 靜止卡死偵測
	if global_position.distance_to(_stuck_anchor) >= STUCK_MIN_MOVE:
		_stuck_anchor = global_position
		_stuck_t = 0.0
		_is_stuck = false
		return
	_stuck_t += delta
	if _stuck_t < STUCK_CHECK_TIME:
		return
	_is_stuck = true
	var reason := ""
	if _climbing:
		reason = "爬牆無進展（被牆角或上方障礙卡住）"
	elif _path.is_empty():
		reason = "導航網格無路徑（目前位置或目標不在可走網格）"
	elif _nav_unreachable:
		reason = "導航無法抵達目標且無法爬過障礙"
	else:
		reason = "移動受阻（連續 %.1f 秒位移不足 %.2fm）" % [STUCK_CHECK_TIME, STUCK_MIN_MOVE]
	_report_stuck(reason, target_pos)
	_stuck_t = 0.0
	_stuck_anchor = global_position


func _report_stuck(reason: String, target_pos: Vector3) -> void:
	_last_stuck_reason = reason
	if _stuck_cooldown > 0.0:
		return
	_stuck_cooldown = 2.5
	var layer_name := _current_layer_name()
	for rep in _stuck_reports:
		if rep["layer"] == layer_name and rep["pos"].distance_to(global_position) < STUCK_DEDUP_RADIUS:
			rep["count"] = int(rep["count"]) + 1
			rep["reason"] = reason
			rep["target"] = target_pos
			rep["blocker"] = _last_blocker_name
			if _ui and _ui.monster_debug_mode:
				print("[MonsterDebug] 重複卡點 #%d (x%d) %s @ %s -> %s" % [
					rep["id"], rep["count"], reason, str(global_position.snapped(Vector3(0.01, 0.01, 0.01))), str(target_pos.snapped(Vector3(0.01, 0.01, 0.01)))
				])
			return
	var report := {
		"id": _stuck_reports.size() + 1,
		"layer": layer_name,
		"pos": global_position,
		"target": target_pos,
		"state": _state_label(),
		"climbing": _climbing,
		"reason": reason,
		"blocker": _last_blocker_name,
		"blocker_pos": _last_blocker_pos,
		"count": 1,
	}
	_stuck_reports.append(report)
	_spawn_stuck_marker(report)
	var line := _format_single_stuck_report(report)
	if _ui and _ui.monster_debug_mode:
		print("[MonsterDebug] " + line)
		_append_stuck_log(line)


func _format_single_stuck_report(rep: Dictionary) -> String:
	var p: Vector3 = rep["pos"]
	var t: Vector3 = rep["target"]
	var h_dist := Vector2(t.x - p.x, t.z - p.z).length()
	var dy := t.y - p.y
	var blocker_txt: String = " | 阻擋物: %s" % rep["blocker"] if not String(rep["blocker"]).is_empty() else ""
	var count_txt: String = " (累計 %d 次)" % int(rep["count"]) if int(rep["count"]) > 1 else ""
	return "#%d 【%s】卡住座標: (%.2f, %.2f, %.2f) -> 無法前往目標: (%.2f, %.2f, %.2f) [水平 %.1fm / 高差 %+.1fm] | 狀態: %s | 原因: %s%s%s" % [
		int(rep["id"]), rep["layer"], p.x, p.y, p.z, t.x, t.y, t.z, h_dist, dy, rep["state"], rep["reason"], blocker_txt, count_txt
	]


func _spawn_stuck_marker(rep: Dictionary) -> void:
	if not _debug_markers_root:
		return
	var marker := Node3D.new()
	_debug_markers_root.add_child(marker)
	marker.global_position = rep["pos"]

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.15, 0.45, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true

	var pillar := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.14
	cyl.height = 2.6
	pillar.mesh = cyl
	pillar.material_override = mat
	pillar.position = Vector3(0.0, 1.3, 0.0)
	marker.add_child(pillar)

	var lbl := Label3D.new()
	var p: Vector3 = rep["pos"]
	lbl.text = "卡點 #%d\n%s\n(%.1f, %.1f, %.1f)" % [int(rep["id"]), rep["reason"], p.x, p.y, p.z]
	lbl.position = Vector3(0.0, 2.85, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.modulate = Color(1.0, 0.9, 0.35)
	lbl.outline_modulate = Color(0.0, 0.0, 0.0)
	lbl.outline_size = 8
	lbl.pixel_size = 0.008
	marker.add_child(lbl)


func _append_stuck_log(line: String) -> void:
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(STUCK_LOG_PATH) else FileAccess.WRITE
	var f := FileAccess.open(STUCK_LOG_PATH, mode)
	if f:
		f.seek_end()
		f.store_line("[%s] %s" % [Time.get_datetime_string_from_system(), line])
		f.close()


func get_debug_hud_text(layer_name: String) -> String:
	var p := global_position
	var t := _current_target
	var dist := p.distance_to(_player.global_position) if _player else 0.0
	var nav_txt := "不可達(轉爬牆)" if _nav_unreachable else "正常"
	var climb_txt := "爬牆中 (法線 %.1f,%.1f,%.1f)" % [_climb_normal.x, _climb_normal.y, _climb_normal.z] if _climbing else "地面"
	var stuck_line := " 狀態: 移動正常"
	if _is_stuck:
		stuck_line = " ⚠ 卡住警報: %s" % _last_stuck_reason
	elif not _stuck_reports.is_empty():
		var last: Dictionary = _stuck_reports[_stuck_reports.size() - 1]
		var lp: Vector3 = last["pos"]
		stuck_line = " 最近卡點 #%d: (%.1f, %.1f, %.1f) %s" % [int(last["id"]), lp.x, lp.y, lp.z, last["reason"]]
	return " [怪物除錯模式] %s | %s | 移速: %.1f m/s\n 怪物座標: (%.2f, %.2f, %.2f) | 距玩家: %.1fm\n 目標座標: (%.2f, %.2f, %.2f) | 導航: %s (跨層連結: %d)\n 攀爬: %s | 已記錄卡點: %d 處\n%s" % [
		layer_name, _state_label(), _current_speed,
		p.x, p.y, p.z, dist,
		t.x, t.y, t.z, nav_txt, _nav_links_count,
		climb_txt, _stuck_reports.size(),
		stuck_line
	]


func get_stuck_report_text(layer_name: String) -> String:
	if _stuck_reports.is_empty():
		var p := global_position
		var t := _current_target
		return "【%s 怪物除錯報告】目前尚未記錄到卡點。\n當前怪物座標: (%.2f, %.2f, %.2f) | 目標: (%.2f, %.2f, %.2f) | 狀態: %s" % [
			layer_name, p.x, p.y, p.z, t.x, t.y, t.z, _state_label()
		]
	var lines: PackedStringArray = ["【%s 怪物卡點報告（共 %d 處）】" % [layer_name, _stuck_reports.size()]]
	for rep in _stuck_reports:
		lines.append(_format_single_stuck_report(rep))
	return "\n".join(lines)


func clear_stuck_reports() -> void:
	_stuck_reports.clear()
	_is_stuck = false
	_last_stuck_reason = ""
	if _debug_markers_root:
		for child in _debug_markers_root.get_children():
			child.queue_free()
