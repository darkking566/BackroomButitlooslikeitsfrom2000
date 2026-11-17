extends CanvasLayer

const Level0WikiData := preload("res://scripts/level0_wiki_data.gd")

signal window_closed
signal restart_requested
signal teleport_requested(target_pos: Vector3, yaw_rad: float)

const COL_BG := Color(0.753, 0.753, 0.753)       # #C0C0C0
const COL_LIGHT := Color(1.0, 1.0, 1.0)          # #FFFFFF
const COL_HIGHLIGHT := Color(0.875, 0.875, 0.875)
const COL_SHADOW := Color(0.502, 0.502, 0.502)   # #808080
const COL_DARK := Color(0.20, 0.20, 0.20)        # #333333
const COL_NAVY := Color(0.0, 0.0, 0.502)         # #000080
const COL_BLUE := Color(0.063, 0.518, 0.816)     # #1084D0

const COL_PAPER := Color(0.91, 0.86, 0.68)
const COL_PAPER_BORDER := Color(0.45, 0.40, 0.28)
const COL_INK := Color(0.15, 0.13, 0.10)

var _crosshair: ColorRect
var _prompt_panel: PanelContainer
var _prompt_label: Label
var _taskbar: PanelContainer
var _task_label: Label
var _clock_label: Label

var _overlay: Control
var _explorer_group: Control
var _left_title_label: Label
var _file_list: VBoxContainer
var _right_title_label: Label
var _doc_image: TextureRect
var _doc_text: RichTextLabel

var _note_group: Control
var _note_image: TextureRect
var _note_body: RichTextLabel

var _exit_dialog: PanelContainer
var _exit_body: Label

var _map_group: Control
var _map_canvas: Control

var _is_open: bool = false


func _ready() -> void:
	layer = 2
	_build_hud()
	_build_overlay()
	_overlay.visible = false


func is_popup_open() -> bool:
	return _is_open


func is_map_open() -> bool:
	return _is_open and _map_group != null and _map_group.visible


func set_prompt(text: String) -> void:
	if text.is_empty() or _is_open:
		_prompt_panel.visible = false
	else:
		_prompt_label.text = " " + text + " "
		_prompt_panel.visible = true


func show_explorer(title: String, file_name: String, file_size: String, doc_title: String, doc_body: String, image_path: String = "") -> void:
	_is_open = true
	_prompt_panel.visible = false
	_overlay.visible = true
	_explorer_group.visible = true
	_note_group.visible = false
	_exit_dialog.visible = false

	_left_title_label.text = " " + title
	_clear_file_list()
	_add_file_item(" [磁片]  %-16s %s" % [file_name, file_size], func() -> void:
		_set_document(doc_title, doc_body, image_path)
	, true)
	_set_document(doc_title, doc_body, image_path)
	_task_label.text = " " + title


func show_wiki_archive() -> void:
	_is_open = true
	_prompt_panel.visible = false
	_overlay.visible = true
	_explorer_group.visible = true
	_note_group.visible = false
	_exit_dialog.visible = false

	var win_title := "M.E.G. Archive - Level 0 (Wiki)"
	_left_title_label.text = " " + win_title
	_clear_file_list()

	for i in Level0WikiData.ENTRIES.size():
		var entry: Dictionary = Level0WikiData.ENTRIES[i]
		var label_txt := " [檔]  %-20s %s" % [entry["file"], entry["size"]]
		var captured_entry := entry
		_add_file_item(label_txt, func() -> void:
			_set_document(captured_entry["title"], captured_entry["body"], captured_entry["image"])
		, i == 0)

	if not Level0WikiData.ENTRIES.is_empty():
		var first: Dictionary = Level0WikiData.ENTRIES[0]
		_set_document(first["title"], first["body"], first["image"])
	_task_label.text = " " + win_title


func _clear_file_list() -> void:
	for child in _file_list.get_children():
		child.queue_free()


func _add_file_item(label_txt: String, on_press: Callable, grab_focus: bool) -> void:
	var btn := Button.new()
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.flat = false
	btn.text = label_txt
	btn.add_theme_color_override("font_color", Color.BLACK)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	btn.add_theme_color_override("font_focus_color", Color.WHITE)
	btn.add_theme_stylebox_override("normal", _make_solid_box(COL_LIGHT))
	btn.add_theme_stylebox_override("hover", _make_solid_box(COL_NAVY))
	btn.add_theme_stylebox_override("pressed", _make_solid_box(COL_NAVY))
	btn.add_theme_stylebox_override("focus", _make_solid_box(COL_NAVY))
	btn.add_theme_font_size_override("font_size", 13)
	btn.pressed.connect(on_press)
	_file_list.add_child(btn)
	if grab_focus:
		btn.grab_focus()


func _set_document(doc_title: String, doc_body: String, image_path: String) -> void:
	_right_title_label.text = " " + doc_title
	_doc_text.text = doc_body
	_apply_texture(_doc_image, image_path)


func _apply_texture(rect: TextureRect, image_path: String) -> void:
	if image_path.is_empty() or not ResourceLoader.exists(image_path):
		rect.texture = null
		rect.visible = false
		return
	var tex := load(image_path) as Texture2D
	if tex:
		rect.texture = tex
		rect.visible = true
	else:
		rect.texture = null
		rect.visible = false


func show_note(_note_title: String, note_body: String, image_path: String = "") -> void:
	_is_open = true
	_prompt_panel.visible = false
	_overlay.visible = true
	_explorer_group.visible = false
	_note_group.visible = true
	_exit_dialog.visible = false

	_apply_texture(_note_image, image_path)
	_note_body.text = note_body


func show_exit_dialog(found_pc: bool, elapsed_sec: float) -> void:
	_is_open = true
	_prompt_panel.visible = false
	_overlay.visible = true
	_explorer_group.visible = false
	_note_group.visible = false
	_exit_dialog.visible = true

	var mins := int(elapsed_sec) / 60
	var secs := int(elapsed_sec) % 60
	var pc_status := "已讀取 (Memory 43)" if found_pc else "未讀取 (可回黃色走廊電腦查看)"
	_exit_body.text = (
		"偵測到樓層邊界門禁。\n\n"
		+ "• 探索時間：%02d 分 %02d 秒\n" % [mins, secs]
		+ "• 舊電腦線索：%s\n\n" % pc_status
		+ "要繼續留在目前空間探索，還是回到起點重新開始？"
	)
	_task_label.text = " System Alert - Gate 0.5"


func show_level1_exit(elapsed_sec: float) -> void:
	_is_open = true
	_prompt_panel.visible = false
	_overlay.visible = true
	_explorer_group.visible = false
	_note_group.visible = false
	_exit_dialog.visible = true
	if _map_group:
		_map_group.visible = false

	var mins := int(elapsed_sec) / 60
	var secs := int(elapsed_sec) % 60
	_exit_body.text = (
		"你縱身投入了閃爍的牆壁，成功切出 Level 0！\n"
		+ "（存活時間：%02d 分 %02d 秒）\n\n" % [mins, secs]
		+ "「既然你走到了這一步，便意味著你已跨過了那道閾界——歡迎來到後室（Level 1）。」"
	)
	_task_label.text = " Noclip Detected - Level 1"


func show_map(player_pos: Vector3, player_yaw: float) -> void:
	_is_open = true
	_prompt_panel.visible = false
	_overlay.visible = true
	_explorer_group.visible = false
	_note_group.visible = false
	_exit_dialog.visible = false
	_map_group.visible = true
	_map_canvas.set_player(player_pos, player_yaw)
	_task_label.text = " M.E.G. Level 0 導航地圖與快速傳送"


func close_popup() -> void:
	if not _is_open:
		return
	_is_open = false
	_overlay.visible = false
	_explorer_group.visible = false
	_note_group.visible = false
	_exit_dialog.visible = false
	if _map_group:
		_map_group.visible = false
	_task_label.text = " WASD 移動 | Shift 慢跑 | F 手電筒 | E 互動 | M 地圖傳送 | Esc 滑鼠"
	window_closed.emit()


func _build_hud() -> void:
	var ch_wrap := CenterContainer.new()
	ch_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	ch_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ch_wrap)

	var ch_bg := ColorRect.new()
	ch_bg.custom_minimum_size = Vector2(6, 6)
	ch_bg.color = Color(0, 0, 0, 0.75)
	ch_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch_wrap.add_child(ch_bg)

	_crosshair = ColorRect.new()
	_crosshair.custom_minimum_size = Vector2(4, 4)
	_crosshair.color = Color(1, 1, 1, 0.9)
	_crosshair.position = Vector2(1, 1)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch_bg.add_child(_crosshair)

	_prompt_panel = PanelContainer.new()
	_prompt_panel.add_theme_stylebox_override("panel", _make_raised_box(COL_BG))
	_prompt_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_panel.offset_left = -130
	_prompt_panel.offset_right = 130
	_prompt_panel.offset_top = -76
	_prompt_panel.offset_bottom = -44
	_prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_panel.visible = false
	add_child(_prompt_panel)

	_prompt_label = Label.new()
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_color_override("font_color", Color.BLACK)
	_prompt_label.add_theme_font_size_override("font_size", 14)
	_prompt_panel.add_child(_prompt_label)

	_taskbar = PanelContainer.new()
	_taskbar.add_theme_stylebox_override("panel", _make_raised_box(COL_BG))
	_taskbar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_taskbar.offset_top = -28
	_taskbar.offset_bottom = 0
	_taskbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_taskbar)

	var tb_row := HBoxContainer.new()
	tb_row.add_theme_constant_override("separation", 6)
	_taskbar.add_child(tb_row)

	var start_btn := PanelContainer.new()
	start_btn.add_theme_stylebox_override("panel", _make_raised_box(COL_BG))
	tb_row.add_child(start_btn)
	var start_lbl := Label.new()
	start_lbl.text = " Start "
	start_lbl.add_theme_color_override("font_color", Color.BLACK)
	start_lbl.add_theme_font_size_override("font_size", 13)
	start_btn.add_child(start_lbl)

	var task_box := PanelContainer.new()
	task_box.add_theme_stylebox_override("panel", _make_sunken_box(COL_BG))
	task_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tb_row.add_child(task_box)
	_task_label = Label.new()
	_task_label.text = " WASD 移動 | Shift 慢跑 | F 手電筒 | E 互動 | M 地圖傳送 | Esc 滑鼠"
	_task_label.add_theme_color_override("font_color", Color.BLACK)
	_task_label.add_theme_font_size_override("font_size", 12)
	_task_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	task_box.add_child(_task_label)

	var clock_box := PanelContainer.new()
	clock_box.add_theme_stylebox_override("panel", _make_sunken_box(COL_BG))
	tb_row.add_child(clock_box)
	_clock_label = Label.new()
	_clock_label.text = "  ??:?? ?/??/????  "
	_clock_label.add_theme_color_override("font_color", Color.BLACK)
	_clock_label.add_theme_font_size_override("font_size", 12)
	_clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	clock_box.add_child(_clock_label)


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.offset_bottom = -28
	add_child(_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.42)
	_overlay.add_child(dim)

	# --- 1. Dual-pane Win95 Explorer Window (for 90s PC) ---
	_explorer_group = CenterContainer.new()
	_explorer_group.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(_explorer_group)

	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 14)
	_explorer_group.add_child(pair)

	var left_win := _create_win95_window(Vector2(340, 420), "Exploring - S??I")
	pair.add_child(left_win["frame"])
	_left_title_label = left_win["title_label"]
	var left_content: VBoxContainer = left_win["content"]

	var hdr_row := HBoxContainer.new()
	hdr_row.add_theme_constant_override("separation", 2)
	left_content.add_child(hdr_row)
	hdr_row.add_child(_make_column_header("Name", 190))
	hdr_row.add_child(_make_column_header("Size", 120))

	var left_white := PanelContainer.new()
	left_white.add_theme_stylebox_override("panel", _make_sunken_box(COL_LIGHT))
	left_white.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_content.add_child(left_white)

	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_white.add_child(left_scroll)

	_file_list = VBoxContainer.new()
	_file_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(_file_list)

	var right_win := _create_win95_window(Vector2(440, 480), "Document")
	pair.add_child(right_win["frame"])
	_right_title_label = right_win["title_label"]
	var right_content: VBoxContainer = right_win["content"]

	var right_white := PanelContainer.new()
	right_white.add_theme_stylebox_override("panel", _make_sunken_box(COL_LIGHT))
	right_white.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_content.add_child(right_white)

	var doc_pad := MarginContainer.new()
	doc_pad.add_theme_constant_override("margin_left", 10)
	doc_pad.add_theme_constant_override("margin_right", 10)
	doc_pad.add_theme_constant_override("margin_top", 10)
	doc_pad.add_theme_constant_override("margin_bottom", 10)
	right_white.add_child(doc_pad)

	var doc_vbox := VBoxContainer.new()
	doc_vbox.add_theme_constant_override("separation", 8)
	doc_pad.add_child(doc_vbox)

	_doc_image = TextureRect.new()
	_doc_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_doc_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_doc_image.custom_minimum_size = Vector2(0, 175)
	_doc_image.visible = false
	doc_vbox.add_child(_doc_image)

	_doc_text = RichTextLabel.new()
	_doc_text.fit_content = false
	_doc_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_doc_text.add_theme_color_override("default_color", Color.BLACK)
	_doc_text.add_theme_font_size_override("normal_font_size", 14)
	doc_vbox.add_child(_doc_text)

	var close_hint := Label.new()
	close_hint.text = "按 [ E ] / [ Esc ] 或右上角 [ X ] 關閉視窗"
	close_hint.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15))
	close_hint.add_theme_font_size_override("font_size", 12)
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right_content.add_child(close_hint)

	# --- 2. Aged Paper Note Viewer (for physical wall/column notes) ---
	_note_group = CenterContainer.new()
	_note_group.set_anchors_preset(Control.PRESET_FULL_RECT)
	_note_group.visible = false
	_overlay.add_child(_note_group)

	var note_vbox := VBoxContainer.new()
	note_vbox.add_theme_constant_override("separation", 10)
	_note_group.add_child(note_vbox)

	var paper_panel := PanelContainer.new()
	paper_panel.custom_minimum_size = Vector2(440, 380)
	var paper_style := StyleBoxFlat.new()
	paper_style.bg_color = COL_PAPER
	paper_style.border_width_left = 2
	paper_style.border_width_top = 2
	paper_style.border_width_right = 4
	paper_style.border_width_bottom = 5
	paper_style.border_color = COL_PAPER_BORDER
	paper_style.content_margin_left = 24
	paper_style.content_margin_right = 24
	paper_style.content_margin_top = 22
	paper_style.content_margin_bottom = 22
	paper_panel.add_theme_stylebox_override("panel", paper_style)
	note_vbox.add_child(paper_panel)

	var note_inner := VBoxContainer.new()
	note_inner.add_theme_constant_override("separation", 10)
	paper_panel.add_child(note_inner)

	_note_image = TextureRect.new()
	_note_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_note_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_note_image.custom_minimum_size = Vector2(0, 170)
	_note_image.visible = false
	note_inner.add_child(_note_image)

	_note_body = RichTextLabel.new()
	_note_body.fit_content = false
	_note_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_note_body.add_theme_color_override("default_color", COL_INK)
	_note_body.add_theme_font_size_override("normal_font_size", 16)
	note_inner.add_child(_note_body)

	var note_btn_wrap := CenterContainer.new()
	note_vbox.add_child(note_btn_wrap)
	var note_close_btn := _make_win95_button("  放下紙條 [ E / Esc ]  ")
	note_close_btn.pressed.connect(close_popup)
	note_btn_wrap.add_child(note_close_btn)

	# --- 3. Exit Door Terminal Dialog ---
	var dialog_center := CenterContainer.new()
	dialog_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(dialog_center)

	var exit_win := _create_win95_window(Vector2(420, 240), "System Alert - Gate 0.5")
	_exit_dialog = exit_win["frame"]
	_exit_dialog.visible = false
	dialog_center.add_child(_exit_dialog)
	var exit_content: VBoxContainer = exit_win["content"]

	var body_panel := PanelContainer.new()
	body_panel.add_theme_stylebox_override("panel", _make_sunken_box(COL_LIGHT))
	body_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	exit_content.add_child(body_panel)

	var body_pad := MarginContainer.new()
	body_pad.add_theme_constant_override("margin_left", 12)
	body_pad.add_theme_constant_override("margin_right", 12)
	body_pad.add_theme_constant_override("margin_top", 10)
	body_pad.add_theme_constant_override("margin_bottom", 10)
	body_panel.add_child(body_pad)

	_exit_body = Label.new()
	_exit_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_exit_body.add_theme_color_override("font_color", Color.BLACK)
	_exit_body.add_theme_font_size_override("font_size", 14)
	body_pad.add_child(_exit_body)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 10)
	exit_content.add_child(btn_row)

	var btn_continue := _make_win95_button(" 繼續探索 ")
	btn_continue.pressed.connect(close_popup)
	btn_row.add_child(btn_continue)

	var btn_restart := _make_win95_button(" 重新開始 ")
	btn_restart.pressed.connect(func():
		close_popup()
		restart_requested.emit()
	)
	btn_row.add_child(btn_restart)

	# --- 4. M.E.G. Overview Map & Fast Travel Window ---
	_map_group = CenterContainer.new()
	_map_group.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_group.visible = false
	_overlay.add_child(_map_group)

	var map_win := _create_win95_window(Vector2(760, 480), "M.E.G. Map & Fast Travel - Level 0")
	_map_group.add_child(map_win["frame"])
	var map_content: VBoxContainer = map_win["content"]

	var map_hbox := HBoxContainer.new()
	map_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_hbox.add_theme_constant_override("separation", 8)
	map_content.add_child(map_hbox)

	var map_frame := PanelContainer.new()
	map_frame.add_theme_stylebox_override("panel", _make_sunken_box(Color(0.08, 0.09, 0.08)))
	map_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_hbox.add_child(map_frame)

	_map_canvas = MapCanvas.new()
	_map_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_frame.add_child(_map_canvas)

	var tp_panel := PanelContainer.new()
	tp_panel.custom_minimum_size = Vector2(235, 0)
	tp_panel.add_theme_stylebox_override("panel", _make_sunken_box(COL_LIGHT))
	map_hbox.add_child(tp_panel)

	var tp_scroll := ScrollContainer.new()
	tp_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tp_panel.add_child(tp_scroll)

	var tp_list := VBoxContainer.new()
	tp_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tp_list.add_theme_constant_override("separation", 4)
	tp_scroll.add_child(tp_list)

	var tp_hdr := Label.new()
	tp_hdr.text = " 點擊區域立即傳送："
	tp_hdr.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	tp_hdr.add_theme_font_size_override("font_size", 13)
	tp_list.add_child(tp_hdr)

	var waypoints: Array[Dictionary] = [
		{"name": "1. 起點（黃色走廊）", "pos": Vector3(-26.0, 0.05, 18.2), "yaw": -PI * 0.5},
		{"name": "2. M.E.G. 檔案終端機", "pos": Vector3(-13.5, 0.05, 12.2), "yaw": 0.0},
		{"name": "3. 變體交匯處（地毯）", "pos": Vector3(-16.0, 0.05, 42.5), "yaw": PI},
		{"name": "4. 拱門變體（Arches）", "pos": Vector3(-32.0, 0.05, 44.5), "yaw": 0.0},
		{"name": "5. 柱廳變體（Pillars）", "pos": Vector3(-23.2, 0.05, 58.1), "yaw": PI},
		{"name": "6. 深坑變體（Pitfalls）", "pos": Vector3(5.5, 0.05, 42.5), "yaw": -PI * 0.5},
		{"name": "7. 熄燈區（Blackout）", "pos": Vector3(15.0, 0.05, 58.5), "yaw": PI},
		{"name": "8. 閃爍牆壁出口 (Lv1)", "pos": Vector3(23.5, 0.05, 77.5), "yaw": PI},
		{"name": "9. 紅室前緣（警告區）", "pos": Vector3(-3.0, 0.05, 54.0), "yaw": PI},
		{"name": "10. 紅室深處（死循環）", "pos": Vector3(-2.6, 0.05, 70.0), "yaw": PI},
		{"name": "11. Zone 2 過渡大廳", "pos": Vector3(21.0, 0.05, 7.8), "yaw": -PI * 0.5},
		{"name": "12. Zone 3 綠廳", "pos": Vector3(51.6, 0.05, -4.5), "yaw": 0.0},
		{"name": "13. 西翼：下沉會議坑", "pos": Vector3(-55.0, 0.05, 46.0), "yaw": PI * 0.5},
		{"name": "14. 西翼：挑高中庭", "pos": Vector3(-80.0, 0.05, 46.0), "yaw": PI * 0.5},
		{"name": "15. 西翼：二樓迴廊", "pos": Vector3(-90.0, 4.55, 68.0), "yaw": PI * 0.5},
		{"name": "16. 西翼：低矮爬行層", "pos": Vector3(-91.3, 0.05, 72.0), "yaw": PI},
		{"name": "17. 西翼：上層辦公迷宮", "pos": Vector3(-84.5, 4.55, 72.0), "yaw": PI},
		{"name": "18. 西翼：高柱長廳", "pos": Vector3(-64.0, 0.05, 61.0), "yaw": PI},
		{"name": "19. 東南翼：梯田辦公室", "pos": Vector3(28.0, 0.05, 45.25), "yaw": -PI * 0.5},
		{"name": "20. 東南翼：螺旋塔底", "pos": Vector3(58.0, 2.45, 41.5), "yaw": -PI * 0.5},
		{"name": "21. 東南翼：塔頂貓道口", "pos": Vector3(60.0, 7.25, 46.9), "yaw": PI},
		{"name": "22. 東南翼：倉庫地面", "pos": Vector3(60.0, 0.05, 79.0), "yaw": -PI * 0.5},
		{"name": "23. 東南翼：地下檔案室", "pos": Vector3(44.0, -1.95, 75.0), "yaw": PI * 0.5},
	]
	for wp in waypoints:
		var btn := _make_win95_button(" " + wp["name"])
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var t_pos: Vector3 = wp["pos"]
		var t_yaw: float = wp["yaw"]
		btn.pressed.connect(func() -> void:
			close_popup()
			teleport_requested.emit(t_pos, t_yaw)
		)
		tp_list.add_child(btn)

	var map_hint := Label.new()
	map_hint.text = "紅點 = 目前位置 | 按 [ M ] / [ Esc ] 關閉地圖"
	map_hint.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15))
	map_hint.add_theme_font_size_override("font_size", 12)
	map_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	map_content.add_child(map_hint)


func _create_win95_window(win_size: Vector2, title: String) -> Dictionary:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = win_size
	frame.add_theme_stylebox_override("panel", _make_raised_box(COL_BG))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	frame.add_child(vbox)

	var title_wrap := Control.new()
	title_wrap.custom_minimum_size = Vector2(0, 24)
	vbox.add_child(title_wrap)

	var grad := Gradient.new()
	grad.set_color(0, COL_NAVY)
	grad.set_color(1, COL_BLUE)
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.width = 64
	grad_tex.height = 1

	var title_bg := TextureRect.new()
	title_bg.texture = grad_tex
	title_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_wrap.add_child(title_bg)

	var title_hbox := HBoxContainer.new()
	title_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_wrap.add_child(title_hbox)

	var title_lbl := Label.new()
	title_lbl.text = " " + title
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_color_override("font_color", Color.WHITE)
	title_lbl.add_theme_font_size_override("font_size", 13)
	title_hbox.add_child(title_lbl)

	var close_btn := _make_win95_button("X")
	close_btn.custom_minimum_size = Vector2(22, 20)
	close_btn.pressed.connect(close_popup)
	title_hbox.add_child(close_btn)

	var content := VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	vbox.add_child(content)

	return {"frame": frame, "title_label": title_lbl, "content": content}


func _make_column_header(text: String, min_w: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(min_w, 24)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", _make_raised_box(COL_SHADOW.lerp(COL_BG, 0.45)))
	var l := Label.new()
	l.text = " " + text
	l.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	l.add_theme_font_size_override("font_size", 13)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


func _make_win95_button(label_text: String) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.add_theme_color_override("font_color", Color.BLACK)
	btn.add_theme_color_override("font_hover_color", Color.BLACK)
	btn.add_theme_color_override("font_pressed_color", Color.BLACK)
	btn.add_theme_stylebox_override("normal", _make_raised_box(COL_BG))
	btn.add_theme_stylebox_override("hover", _make_raised_box(COL_HIGHLIGHT))
	btn.add_theme_stylebox_override("pressed", _make_sunken_box(COL_BG))
	btn.add_theme_stylebox_override("focus", _make_raised_box(COL_BG))
	btn.add_theme_font_size_override("font_size", 13)
	return btn


func _make_raised_box(fill: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = COL_DARK
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb


func _make_sunken_box(fill: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = COL_SHADOW
	sb.content_margin_left = 2
	sb.content_margin_right = 2
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb


func _make_solid_box(fill: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	return sb


class MapCanvas extends Control:
	var _player_pos := Vector3.ZERO
	var _player_yaw: float = 0.0

	func set_player(pos: Vector3, yaw: float) -> void:
		_player_pos = pos
		_player_yaw = yaw
		queue_redraw()

	func _world_to_map(wx: float, wz: float) -> Vector2:
		# World bounds: x [-112 .. +88], z [-40 .. +106]
		var nx := (wx + 112.0) / 200.0
		var nz := (wz + 40.0) / 146.0
		var pad := 14.0
		var w := size.x - pad * 2.0
		var h := size.y - pad * 2.0
		var scale := minf(w, h)
		var ox := (size.x - scale * (200.0 / 146.0)) * 0.5
		if scale * (200.0 / 146.0) > w:
			scale = w / (200.0 / 146.0)
			ox = pad
		var oy := (size.y - scale) * 0.5
		return Vector2(ox + nx * scale * (200.0 / 146.0), oy + nz * scale)

	func _draw_zone(x1: float, z1: float, x2: float, z2: float, fill: Color, label: String) -> void:
		var p1 := _world_to_map(x1, z1)
		var p2 := _world_to_map(x2, z2)
		var rect := Rect2(p1, p2 - p1)
		draw_rect(rect, fill, true)
		draw_rect(rect, Color(0.85, 0.85, 0.85, 0.45), false, 1.0)
		if not label.is_empty():
			draw_string(ThemeDB.fallback_font, p1 + Vector2(4, 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.95, 0.95, 0.95))

	func _draw() -> void:
		_draw_zone(-87.1, -32.5, -32.5, 32.5, Color(0.42, 0.39, 0.19, 0.85), "西側迷宮")
		_draw_zone(-32.5, -32.5, 32.5, 32.5, Color(0.62, 0.57, 0.25, 0.9), "Level 0 主迷宮")
		_draw_zone(32.5, -2.0, 56.0, 16.0, Color(0.32, 0.36, 0.42, 0.9), "Zone 2")
		_draw_zone(32.5, -37.0, 71.0, -1.5, Color(0.28, 0.40, 0.18, 0.9), "Zone 3")
		_draw_zone(-24.0, 38.5, 4.0, 46.5, Color(0.55, 0.50, 0.22, 0.95), "交匯處")
		_draw_zone(-44.0, 34.5, -24.0, 50.5, Color(0.76, 0.74, 0.62, 0.95), "拱門")
		_draw_zone(-36.0, 50.5, -10.0, 76.5, Color(0.52, 0.47, 0.22, 0.95), "柱廳")
		_draw_zone(4.0, 34.5, 26.0, 56.5, Color(0.35, 0.32, 0.16, 0.95), "深坑")
		_draw_zone(4.0, 56.5, 26.0, 80.5, Color(0.10, 0.10, 0.12, 0.98), "熄燈區")
		_draw_zone(-8.0, 50.5, 2.0, 62.5, Color(0.52, 0.22, 0.16, 0.95), "紅前")
		_draw_zone(-8.0, 62.5, 2.0, 92.5, Color(0.65, 0.08, 0.07, 0.95), "紅室")
		_draw_zone(-76.0, 34.0, -52.0, 58.0, Color(0.50, 0.45, 0.24, 0.95), "會議坑")
		_draw_zone(-110.0, 34.0, -76.0, 70.0, Color(0.72, 0.68, 0.48, 0.95), "挑高中庭")
		_draw_zone(-110.0, 70.0, -76.0, 104.0, Color(0.38, 0.36, 0.28, 0.95), "爬行層/上層迷宮")
		_draw_zone(-76.0, 58.0, -44.0, 104.0, Color(0.58, 0.53, 0.26, 0.95), "高柱長廳")
		_draw_zone(-52.0, 44.0, -44.0, 48.0, Color(0.55, 0.50, 0.22, 0.95), "")
		_draw_zone(26.0, 34.0, 56.0, 58.0, Color(0.60, 0.55, 0.30, 0.95), "梯田辦公室")
		_draw_zone(56.0, 34.0, 70.0, 48.0, Color(0.74, 0.70, 0.52, 0.95), "螺旋塔")
		_draw_zone(56.0, 48.0, 86.0, 82.0, Color(0.42, 0.40, 0.32, 0.95), "貓道倉庫")
		_draw_zone(26.0, 60.0, 56.0, 80.0, Color(0.26, 0.28, 0.20, 0.95), "地下檔案室")

		var pm := _world_to_map(_player_pos.x, _player_pos.z)
		var fwd := Vector2(-sin(_player_yaw), -cos(_player_yaw))
		draw_line(pm, pm + fwd * 14.0, Color(0.2, 1.0, 1.0), 2.0)
		draw_circle(pm, 4.5, Color(1.0, 0.2, 0.2))
		draw_arc(pm, 5.5, 0.0, TAU, 16, Color.WHITE, 1.2)
