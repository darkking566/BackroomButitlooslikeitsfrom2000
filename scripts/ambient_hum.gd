extends AudioStreamPlayer

var _anomaly_player: AudioStreamPlayer
var _scratch_stream: AudioStreamWAV
var _whisper_stream: AudioStreamWAV
var _surge_timer: float = 18.0
var _anomaly_timer: float = 28.0
var _surge_active: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	stream = BackroomsAudio.create_fluorescent_hum_stream()
	volume_db = -15.5
	play()

	_scratch_stream = BackroomsAudio.create_wall_scratch_stream()
	_whisper_stream = BackroomsAudio.create_eerie_whisper_stream()
	_anomaly_player = AudioStreamPlayer.new()
	_anomaly_player.name = "Level0AnomalyAudio"
	_anomaly_player.volume_db = -18.0
	add_child(_anomaly_player)


func _process(delta: float) -> void:
	# Do not surge when muted inside Blackout Zone
	if volume_db < -35.0:
		_surge_active = 0.0
		return

	if _surge_active > 0.0:
		_surge_active -= delta
		volume_db = lerpf(volume_db, -9.5, clampf(delta * 4.0, 0.0, 1.0))
	else:
		_surge_timer -= delta
		if _surge_timer <= 0.0:
			_surge_active = _rng.randf_range(2.2, 3.8)
			_surge_timer = _rng.randf_range(22.0, 42.0)

	_anomaly_timer -= delta
	if _anomaly_timer <= 0.0:
		_anomaly_timer = _rng.randf_range(24.0, 48.0)
		if not _anomaly_player.playing:
			_anomaly_player.stream = _scratch_stream if _rng.randf() < 0.55 else _whisper_stream
			_anomaly_player.volume_db = _rng.randf_range(-21.0, -15.0)
			_anomaly_player.play()
