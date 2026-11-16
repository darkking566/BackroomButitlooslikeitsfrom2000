extends AudioStreamPlayer


func _ready() -> void:
	stream = BackroomsAudio.create_fluorescent_hum_stream()
	volume_db = -15.5
	play()
