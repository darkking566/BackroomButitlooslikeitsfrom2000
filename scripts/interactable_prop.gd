extends Node

@export var prompt_text: String = "檢視"
@export_enum("explorer", "note", "exit_door", "wiki_archive", "level1_exit") var interaction_type: String = "explorer"
@export var window_title: String = "Exploring - S??I"
@export var file_name: String = "Memory 43"
@export var file_size: String = "1.44mb"
@export_multiline var body_text: String = ""
@export var image_path: String = ""


func get_interact_prompt() -> String:
	return "[ E ] " + prompt_text


func interact(player: Node) -> void:
	if has_meta("on_interact"):  # 程式生成的互動物（例如 Blender 地圖的門/按鈕）直接走回呼
		(get_meta("on_interact") as Callable).call(player)
		return
	if player and player.has_method("open_prop_ui"):
		player.open_prop_ui(self)
