extends Node

const RATE := 24000
const TOWER_AUDIO := preload("res://scripts/tower_audio.gd")
const TRACKS := {
	&"patrol": "res://assets/music/neon_watch.ogg",
	&"boss": "res://assets/music/core_eclipse.ogg",
}
const MUSIC_GAIN := 0.56
const SUPPORT_STAGES := [2, 3, 3, 4, 5, 5]
const CUES := {
	&"click": [0.08, 520.0, 780.0, 0.03, 0.21],
	&"install": [0.18, 200.0, 720.0, 0.12, 0.25],
	&"sell": [0.17, 720.0, 280.0, 0.08, 0.24],
	&"hit": [0.07, 330.0, 150.0, 0.57, 0.10],
	&"kill": [0.20, 720.0, 100.0, 0.35, 0.14],
	&"base": [0.32, 190.0, 52.0, 0.32, 0.33],
	&"wave": [0.26, 160.0, 400.0, 0.08, 0.21],
	&"clear": [0.55, 330.0, 990.0, 0.01, 0.27],
	&"collapse": [0.8, 210.0, 37.0, 0.26, 0.40],
	&"charge": [0.45, 80.0, 480.0, 0.04, 0.21],
	&"heavy": [0.82, 95.0, 28.0, 0.39, 0.42],
}

var music_track: StringName = &""
var _music: Dictionary = {}
var _music_fade: Tween
var _voices: Dictionary = {}
var _last_time: Dictionary = {}
var _retrigger := {&"hit": 85, &"kill": 96}
var _deployment: Array[StringName] = []
var _support_deployment: Array[StringName] = []
var _silent := false
var _default_music := {}
var _default_effects := {}
var _active_audio := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_silent = DisplayServer.get_name() == "headless"
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -1.0
	AudioServer.add_bus_effect(0, limiter)
	_register(&"research_stage", _research_chime(), 1)
	for kind: StringName in CUES:
		_register(kind, _synthesize(CUES[kind]), 2)
	for kind: StringName in TOWER_AUDIO.VOICES:
		var spec: Array = TOWER_AUDIO.VOICES[kind]
		_register(kind, TOWER_AUDIO.render(kind, spec), 1 if float(spec[0]) > 0.35 else 2)
		_retrigger[kind] = int(spec[7])
	for stage in range(6):
		_deployment.append(_register_deploy("deploy_%d" % stage, stage, 0))
	for index in SUPPORT_STAGES.size():
		var kind := index + 1
		_support_deployment.append(_register_deploy("support_deploy_%d" % kind, SUPPORT_STAGES[index], kind))

	for track: StringName in TRACKS:
		var player := AudioStreamPlayer.new()
		player.stream = load(TRACKS[track])
		player.bus = &"Music"
		player.volume_linear = 0.0
		add_child(player)
		_music[track] = player
		_default_music[track] = player.stream

func _register(kind: StringName, stream: AudioStreamWAV, polyphony: int) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"Effects"
	player.max_polyphony = polyphony
	add_child(player)
	_voices[kind] = player
	_default_effects[kind] = stream

func _register_deploy(id: StringName, stage: int, support: int) -> StringName:
	var spec := [
		0.28 + stage * 0.10, 300.0 - stage * 28.0 + support * 36.0,
		350.0 + stage * 28.0 + support * 48.0, 0.32, 0.38, 0.5 + stage * 0.17, 0.32 + stage * 0.046,
	]
	_register(id, TOWER_AUDIO.render(id, spec, stage), 2)
	_retrigger[id] = 92
	return id

func deploy_cue(stage: int, support: int) -> void:
	var kind := _deployment[clampi(stage, 0, _deployment.size() - 1)]
	if support > 0 and support <= _support_deployment.size():
		kind = _support_deployment[support - 1]
	cue(kind)

func stop_battle_cues() -> void:
	if _silent:
		return
	for kind: StringName in TOWER_AUDIO.VOICES:
		_voices[kind].stop()
	_voices[&"research_stage"].stop()
	_last_time.clear()

func attack_cue(style: String, _start: Vector2, _end: Vector2, _radius: float, _tint: Color, _life: float, stage: int) -> void:
	if _silent:
		return
	var kind := attack_voice(style, stage)
	if kind != &"":
		cue(kind)

func attack_voice(style: String, stage: int) -> StringName:
	if style == "rail" and stage < 3:
		return &"pierce"
	return TOWER_AUDIO.ATTACKS.get(style, &"")

func mob_cue(event: StringName, _start: Vector2, _end: Vector2, _tint: Color, _life: float) -> void:
	match event:
		&"boss_spawn", &"phase": cue(&"charge")
		&"boss_down": cue(&"heavy")
		&"shield_break": cue(&"arc")

func support_cue(event: StringName, _kind: int, _start: Vector2, _end: Vector2) -> void:
	match event:
		&"sync": cue(&"support_sync")
		&"quantum": cue(&"support_echo")

func apply_mod_audio(audio: Dictionary) -> void:
	if audio == _active_audio:
		return
	_active_audio = audio
	if _music_fade != null and _music_fade.is_running():
		_music_fade.kill()
	music_track = &""
	for id: StringName in _music:
		var player: AudioStreamPlayer = _music[id]
		player.stop()
		player.volume_linear = 0.0
		player.stream = audio.get(str(id), _default_music[id])
	for id: StringName in _voices:
		var player: AudioStreamPlayer = _voices[id]
		var stream: AudioStream = audio.get(str(id), _default_effects[id])
		if player.stream != stream:
			player.stop()
			player.stream = stream

func play_music(track: StringName = &"", seconds: float = 1.0) -> void:
	if track == music_track:
		return
	assert(track == &"" or _music.has(track), "Unknown music track")
	music_track = track
	if _silent:
		return
	if _music_fade != null and _music_fade.is_running():
		_music_fade.kill()
	_music_fade = create_tween().set_parallel()
	for id: StringName in _music:
		var player: AudioStreamPlayer = _music[id]
		if id == track and not player.playing:
			player.play()
		if player.playing:
			_music_fade.tween_property(player, "volume_linear", MUSIC_GAIN if id == track else 0.0, seconds)
	_music_fade.chain().tween_callback(_stop_inactive_music)

func _stop_inactive_music() -> void:
	for id: StringName in _music:
		if id != music_track:
			_music[id].stop()

func cue(kind: StringName) -> void:
	if _silent or not _voices.has(kind):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_time.get(kind, -2500)) < int(_retrigger.get(kind, 42)):
		return
	_last_time[kind] = now
	_voices[kind].play()

func _research_chime() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = true
	var duration := 1.65
	var samples := roundi(duration * RATE)
	var bytes := PackedByteArray()
	bytes.resize(samples * 4)
	# D minor add-nine voiced as an ascending, overlapping glass arpeggio.
	var notes := [293.665, 440.000, 698.456, 1318.510]
	var pans := [-0.35, 0.31, -0.20, 0.28]
	for i in samples:
		var t := i / float(RATE)
		var voice := Vector2.ZERO
		for n in notes.size():
			var age := t - n * 0.088
			if age <= 0.0:
				continue
			var phase := TAU * float(notes[n]) * age
			var bell := 0.74 * sin(phase) + 0.19 * sin(phase * 2.004) * exp(-4.0 * age)
			bell += 0.07 * sin(phase * 3.011) * exp(-6.5 * age)
			var gain := 0.14 * smoothstep(0.0, 0.027, age) * exp(-age * (2.8 + n * 0.20))
			var pan: float = pans[n]
			voice += Vector2(0.75 - pan * 0.5, 0.75 + pan * 0.5) * bell * gain
		voice *= 1.0 - smoothstep(1.28, duration - 0.005, t)
		bytes.encode_s16(i * 4, roundi(voice.x * 32767.0))
		bytes.encode_s16(i * 4 + 2, roundi(voice.y * 32767.0))
	stream.data = bytes
	return stream

func _synthesize(cue_data: Array) -> AudioStreamWAV:
	var duration: float = cue_data[0]
	var samples := roundi(duration * RATE)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7713
	for i in samples:
		var t := float(i) / samples
		var freq := lerpf(cue_data[1], cue_data[2], t)
		phase += TAU * freq / RATE
		var envelope := minf(t * 90.0, 1.0) * pow(1.0 - t, 2.3)
		var tone := sin(phase) * 0.72 + sin(phase * 1.501) * 0.28
		var value := lerpf(tone, rng.randf_range(-1, 1), cue_data[3]) * envelope * float(cue_data[4])
		bytes.encode_s16(i * 2, roundi(value * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	return stream
