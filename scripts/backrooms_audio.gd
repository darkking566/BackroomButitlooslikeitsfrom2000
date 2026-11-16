class_name BackroomsAudio
extends RefCounted


static func create_fluorescent_hum_stream() -> AudioStreamWAV:
	var mix_rate := 22050
	var duration_sec := 2.0
	var sample_count := int(mix_rate * duration_sec)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 42017
	var lp_noise := 0.0

	for i in sample_count:
		var t := float(i) / float(mix_rate)
		# 60 Hz mains + 120 Hz ballast buzz + subtle upper harmonics
		var hum := 0.22 * sin(TAU * 60.0 * t)
		hum += 0.34 * sin(TAU * 120.0 * t + 0.4)
		hum += 0.14 * sin(TAU * 180.0 * t + 1.1)
		hum += 0.08 * sin(TAU * 240.0 * t)
		hum += 0.04 * sin(TAU * 360.0 * t)

		# Very soft filtered electrical hiss
		lp_noise = lerpf(lp_noise, rng.randf_range(-1.0, 1.0), 0.06)
		var sample := clampf((hum * 0.32) + (lp_noise * 0.045), -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample * 32767.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = sample_count
	wav.data = bytes
	return wav


static func create_carpet_footstep_stream() -> AudioStreamWAV:
	var mix_rate := 22050
	var duration_sec := 0.14
	var sample_count := int(mix_rate * duration_sec)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 9001
	var lp := 0.0
	var phase := 0.0

	for i in sample_count:
		var t := float(i) / float(mix_rate)
		var progress := float(i) / float(sample_count)
		# Soft heel thud dropping from 110 Hz -> 42 Hz
		var freq := lerpf(110.0, 42.0, minf(progress * 2.5, 1.0))
		phase += TAU * freq / float(mix_rate)
		var thud := sin(phase) * exp(-t * 28.0)

		# Muffled damp carpet brush
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.13)
		var brush := lp * exp(-t * 18.0)

		# Smooth de-click attack/release envelope
		var attack := minf(t / 0.008, 1.0)
		var tail := clampf((duration_sec - t) / 0.02, 0.0, 1.0)
		var sample := clampf((thud * 0.55 + brush * 0.45) * attack * tail, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample * 32767.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = bytes
	return wav


static func create_wall_scratch_stream() -> AudioStreamWAV:
	var mix_rate := 22050
	var duration_sec := 1.1
	var sample_count := int(mix_rate * duration_sec)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var lp := 0.0
	var hp_prev := 0.0

	for i in sample_count:
		var t := float(i) / float(mix_rate)
		var env := sin(PI * clampf(t / duration_sec, 0.0, 1.0)) * (0.5 + 0.5 * sin(TAU * 7.5 * t))
		var raw := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, raw, 0.25)
		var hp := lp - hp_prev * 0.65
		hp_prev = lp
		var sample := clampf(hp * env * 0.45, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample * 32767.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = bytes
	return wav


static func create_eerie_whisper_stream() -> AudioStreamWAV:
	var mix_rate := 22050
	var duration_sec := 1.8
	var sample_count := int(mix_rate * duration_sec)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 60606
	var lp := 0.0

	for i in sample_count:
		var t := float(i) / float(mix_rate)
		var env := sin(PI * clampf(t / duration_sec, 0.0, 1.0))
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.14)
		var formant := 0.6 * sin(TAU * 310.0 * t + sin(TAU * 2.2 * t) * 1.4) + 0.4 * sin(TAU * 520.0 * t)
		var sample := clampf((lp * 0.28 + formant * 0.14) * env, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample * 32767.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = bytes
	return wav


static func create_light_pop_stream() -> AudioStreamWAV:
	var mix_rate := 22050
	var duration_sec := 0.24
	var sample_count := int(mix_rate * duration_sec)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)

	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 7711
	var lp := 0.0

	for i in sample_count:
		var t := float(i) / float(mix_rate)
		# Sharp electrical pop + short 120Hz buzz decay
		var pop := sin(TAU * 180.0 * t) * exp(-t * 45.0)
		var buzz := sin(TAU * 120.0 * t) * exp(-t * 16.0) * 0.4
		lp = lerpf(lp, rng2.randf_range(-1.0, 1.0), 0.35)
		var spark := lp * exp(-t * 28.0) * 0.75
		var sample := clampf(pop + buzz + spark, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample * 32767.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = bytes
	return wav
