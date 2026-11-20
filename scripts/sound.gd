extends Node

const RATE := 24000
const CUES := {
	&"click": [0.08, 520.0, 780.0, 0.03, 0.21],
	&"install": [0.18, 200.0, 720.0, 0.12, 0.25],
	&"sell": [0.17, 720.0, 280.0, 0.08, 0.24],
	&"fire": [0.11, 1050.0, 160.0, 0.26, 0.13],
	&"hit": [0.07, 330.0, 150.0, 0.57, 0.10],
	&"kill": [0.20, 720.0, 100.0, 0.35, 0.14],
	&"base": [0.32, 190.0, 52.0, 0.32, 0.33],
	&"wave": [0.26, 160.0, 400.0, 0.08, 0.21],
	&"clear": [0.55, 330.0, 990.0, 0.01, 0.27],
	&"collapse": [0.8, 210.0, 37.0, 0.26, 0.40],
}

var _voices: Dictionary = {}
var _last_time: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for kind: StringName in CUES:
		var player := AudioStreamPlayer.new()
		player.stream = _synthesize(CUES[kind])
		player.bus = &"Effects"
		player.max_polyphony = 3
		add_child(player)
		_voices[kind] = player

func cue(kind: StringName) -> void:
	if DisplayServer.get_name() == "headless" or not _voices.has(kind):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_time.get(kind, -100)) < 42:
		return
	_last_time[kind] = now
	_voices[kind].play()

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
