extends Node

@export var prompt_text: String = "檢視"
@export_enum("explorer", "note", "exit_door", "wiki_archive") var interaction_type: String = "explorer"
@export var window_title: String = "Exploring - S??I"
@export var file_name: String = "Memory 43"
@export var file_size: String = "1.44mb"
@export_multiline var body_text: String = ""
@export var image_path: String = ""


func get_interact_prompt() -> String:
	return "[ E ] " + prompt_text


func interact(player: Node) -> void:
	if player and player.has_method("open_prop_ui"):
		player.open_prop_ui(self)
