extends Node3D

# 全程追獵者。啟動時從全場景的靜態碰撞體烘焙導航網格（所有區域與樓梯共用一張）。
# 狀態：巡邏 → 調查（聽到）→ 凝視（遠遠看到）→ 追擊 → 搜索（跟丟）→ 折返 / 埋伏 / 回巡邏。
# 每次追擊開始時隨機抽一種「追法」：直衝攔截、被看就不動、繞到背後。

enum State { PATROL, INVESTIGATE, STARE, CHASE, SEARCH, AMBUSH }
enum Mood { RUSH, STALK, FLANK }

const HEAT_CELL := 4.0     # 熱度表格子邊長（公尺）
const NEAR_DIST := 6.0     # 進到這個距離換成近距離臉
const LIGHT_KILL_DIST := 7.0  # 牠周圍這個距離內的燈會熄掉
const MAX_CHASE_SPEED := 4.9  # 越追越快的上限，必須低於玩家跑速 5.0

@export var walk_frames: Array[Texture2D] = []  # 正式美術放這裡；留空就用程式畫的佔位圖
@export var near_texture: Texture2D
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
var _sprite: Sprite3D
var _steps: AudioStreamPlayer3D
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
var _anim_t := 0.0
var _sees := false
var _anger := 0          # 每被甩掉一次 +1，追擊速度跟著變快
var _last_seen: Vector3
var _heat := {}          # Vector3i 格子 -> 玩家待過的次數
var _heat_pos := {}      # Vector3i 格子 -> 玩家在該格最後的實際位置（保留樓層高度）
var _heat_t := 0.0
var _lights: Array[Node] = []
var _dimmed: Array[Node] = []  # 被牠弄熄的燈，離開後要點回來
var _light_t := 0.0


func _ready() -> void:
	_home = global_position
	_last_seen = _home
	_player = get_parent().get_node("Player")
	_ui = get_parent().get_node_or_null("Win95UI")
	if _ui:
		_ui.restart_requested.connect(_reset)
	_build_sprite()
	_steps = AudioStreamPlayer3D.new()
	_steps.stream = BackroomsAudio.create_carpet_footstep_stream()
	_steps.pitch_scale = 0.55  # 比玩家腳步低沉
	_steps.max_distance = 24.0
	add_child(_steps)
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
	_think(delta)
	if _move(delta):
		_anim_t += delta  # 站著不動時畫面也定格
	_light_t -= delta
	if _light_t <= 0.0:
		_light_t = 0.3
		_update_lights()
	var near := global_position.distance_to(_player.global_position) < NEAR_DIST
	# 每秒只換 5 張，動作刻意抽搐
	_sprite.texture = near_texture if near and near_texture else walk_frames[int(_anim_t * 5.0) % walk_frames.size()]


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
			_player._on_restart_requested()
			_reset()
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


func _sees_player() -> bool:
	var eye := global_position + Vector3.UP * 1.6
	var head := _player.global_position + Vector3.UP * 1.5
	var light: Light3D = _player.flashlight
	var lit := light != null and light.visible
	if eye.distance_to(head) > (sight_range_flashlight if lit else sight_range_dark):
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, head)
	query.exclude = [_player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


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
		speed = minf(chase_speed + 0.1 * _anger, MAX_CHASE_SPEED)
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
func _update_lights() -> void:
	for light in _lights:
		var close: bool = light.global_position.distance_to(global_position) < LIGHT_KILL_DIST
		if close and light.visible:
			light.visible = false
			_dimmed.append(light)
		elif not close and light in _dimmed:
			light.visible = true
			_dimmed.erase(light)


func _reset() -> void:
	global_position = _home
	_path = PackedVector3Array()
	_path_i = 0
	state = State.PATROL


func _build_sprite() -> void:
	if walk_frames.is_empty():
		walk_frames = [_placeholder(-1.0, false), _placeholder(1.0, false)]
		near_texture = _placeholder(0.0, true)
	_sprite = Sprite3D.new()
	_sprite.texture = walk_frames[0]
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y  # 永遠正臉朝玩家
	_sprite.shaded = false                                # 不吃燈光，暗處也看得到臉
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.pixel_size = 2.3 / walk_frames[0].get_height()  # 身高 2.3 公尺
	_sprite.position.y = 0.85  # 圖高一半 1.15，再扣掉導航路徑浮在地板上方的 0.3
	add_child(_sprite)


# 佔位圖：黑色人影、拖地長臂、歪脖子、過曝白臉上只有一張嘴。sway 讓手臂左右晃，near 是近距離版（臉和嘴變大）。
func _placeholder(sway: float, near: bool) -> ImageTexture:
	var img := Image.create(32, 64, false, Image.FORMAT_RGBA8)
	var face_c := Vector2(20.0, 11.0)
	var face_r := Vector2(7.0, 9.0) if near else Vector2(5.0, 7.0)
	var mouth_r := Vector2(4.0, 5.0) if near else Vector2(2.0, 3.0)
	var in_ellipse := func(p: Vector2, c: Vector2, r: Vector2) -> bool:
		return ((p - c) / r).length() < 1.0
	for y in 64:
		for x in 32:
			var p := Vector2(x, y)
			var arm_dx := sway * (y - 24) / 20.0
			var body: bool = in_ellipse.call(p, Vector2(16.0, 34.0), Vector2(5.0, 14.0)) \
				or (y >= 44 and (absf(x - 13.0) < 1.5 or absf(x - 19.0) < 1.5)) \
				or (y >= 24 and y <= 62 and (absf(x - 8.0 - arm_dx) < 1.2 or absf(x - 24.0 - arm_dx) < 1.2)) \
				or (y >= 14 and y <= 22 and absf(x - 16.0 - (22 - y) * 0.4) < 1.5)
			if in_ellipse.call(p, face_c + Vector2(0.0, 3.0), mouth_r):
				img.set_pixel(x, y, Color(0.03, 0.0, 0.0))
			elif in_ellipse.call(p, face_c, face_r):
				img.set_pixel(x, y, Color.WHITE)
			elif body:
				img.set_pixel(x, y, Color(0.02, 0.02, 0.02))
	return ImageTexture.create_from_image(img)
