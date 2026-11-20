extends RefCounted
## Duration, initial and final pitch, metal, air, sub, gain, retrigger interval in ms.
const VOICES := {
	&"fire": [0.14, 590, 128, 0.22, 0.30, 0.35, 0.23, 76],
	&"rapid": [0.105, 960, 216, 0.31, 0.39, 0.20, 0.19, 82],
	&"scatter": [0.25, 300, 66, 0.26, 0.75, 0.72, 0.31, 140],
	&"cryo": [0.28, 940, 415, 0.72, 0.22, 0.13, 0.23, 135],
	&"pierce": [0.25, 370, 84, 0.62, 0.25, 0.64, 0.31, 130],
	&"arc": [0.34, 790, 123, 0.85, 0.62, 0.45, 0.31, 195],
	&"charge_blast": [0.28, 464, 207, 0.24, 0.32, 0.20, 0.20, 140],
	&"blast": [0.50, 203, 42, 0.26, 0.79, 0.97, 0.43, 220],
	&"flame": [0.36, 155, 92, 0.10, 0.92, 0.25, 0.24, 305],
	&"sniper": [0.32, 1170, 98, 0.56, 0.22, 0.64, 0.34, 150],
	&"mark": [0.31, 690, 1040, 0.34, 0.06, 0.10, 0.19, 190],
	&"laser": [0.24, 830, 524, 0.64, 0.07, 0.23, 0.20, 210],
	&"missile": [0.44, 236, 760, 0.32, 0.84, 0.37, 0.33, 180],
	&"charge_rail": [0.18, 190, 790, 0.53, 0.17, 0.38, 0.23, 120],
	&"rail": [0.46, 455, 52, 0.70, 0.41, 1.16, 0.44, 215],
	&"plasma": [0.37, 278, 126, 0.62, 0.20, 0.63, 0.27, 265],
	&"ice": [0.51, 728, 194, 0.85, 0.34, 0.55, 0.31, 270],
	&"return_launch": [0.39, 320, 255, 0.92, 0.17, 0.62, 0.30, 150],
	&"phase_launch": [0.29, 392, 655, 0.80, 0.25, 0.50, 0.27, 150],
	&"split": [0.32, 700, 162, 0.96, 0.33, 0.40, 0.29, 190],
	&"charge_orbit": [0.75, 120, 810, 0.63, 0.19, 0.45, 0.29, 385],
	&"orbit": [0.86, 244, 39, 0.68, 0.70, 1.32, 0.49, 290],
	&"prism": [0.43, 607, 432, 0.70, 0.16, 0.44, 0.28, 285],
	&"gravity": [0.45, 130, 46, 0.42, 0.31, 0.88, 0.29, 300],
	&"vortex": [0.71, 127, 59, 0.62, 0.68, 0.89, 0.34, 540],
	&"pulse": [0.85, 194, 41, 0.53, 0.49, 1.34, 0.54, 400],
	&"storm": [0.67, 570, 46, 0.89, 0.88, 1.17, 0.47, 465],
	&"photon": [0.34, 1046, 349, 0.89, 0.12, 0.61, 0.34, 275],
	&"charge_nova": [2.20, 72, 342, 0.58, 0.46, 1.02, 0.42, 770],
	&"nova": [1.37, 250, 33, 0.65, 0.76, 1.55, 0.64, 460],
	&"charge_doom": [0.80, 112, 555, 0.72, 0.46, 0.80, 0.38, 390],
	&"doom": [0.99, 350, 45, 0.83, 0.56, 1.53, 0.58, 440],
	&"singularity": [1.74, 129, 36, 0.65, 0.57, 1.53, 0.48, 770],
	&"gravity_end": [1.16, 159, 30, 0.73, 0.63, 1.64, 0.64, 530],
	&"spectrum": [0.69, 760, 254, 0.99, 0.14, 0.96, 0.44, 385],
	&"charge_cataclysm": [3.50, 58, 360, 0.70, 0.52, 1.23, 0.49, 1150],
	&"cataclysm": [2.00, 296, 28, 0.83, 0.84, 1.87, 0.76, 680],
	&"support_sync": [0.85, 220, 512, 0.80, 0.18, 1.10, 0.43, 430],
	&"support_echo": [0.31, 570, 827, 0.72, 0.11, 0.38, 0.22, 250],
}

const ATTACKS := {
	"muzzle": &"rapid", "scatter_launch": &"scatter", "cryogenic_launch": &"cryo",
	"missile_launch": &"missile", "phase_launch": &"phase_launch", "return_launch": &"return_launch",
	"charge_blast": &"charge_blast", "blast": &"blast", "arc": &"arc",
	"laser": &"laser", "flame": &"flame", "sniper": &"sniper", "mark": &"mark",
	"charge_rail": &"charge_rail", "rail": &"rail", "plasma": &"plasma", "ice": &"ice",
	"split": &"split", "charge_orbit": &"charge_orbit", "orbit": &"orbit",
	"prism_source": &"prism", "gravity": &"gravity", "vortex": &"vortex", "pulse": &"pulse",
	"storm_source": &"storm", "photon_source": &"photon", "charge_nova": &"charge_nova",
	"nova": &"nova", "charge_doom": &"charge_doom", "doom": &"doom",
	"singularity": &"singularity", "collapse_gravity": &"gravity_end", "spectrum_source": &"spectrum",
	"charge_cataclysm": &"charge_cataclysm", "cataclysm": &"cataclysm",
}

const RATE := 28000

static func render(id: StringName, spec: Array, stage: int = -1) -> AudioStreamWAV:
	var duration: float = spec[0]
	var samples := roundi(duration * RATE)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	var phase := 0.0
	var sub_phase := 0.0
	var filtered := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = maxi(1, absi(hash(id)))
	var rising := String(id).begins_with("charge_")
	var deploy := stage >= 0
	var tail_power := 2.1 + minf(1.0, 0.4 / duration)
	var pitch_start: float = spec[1]
	var pitch_end: float = spec[2]
	var metal: float = spec[3]
	var air: float = spec[4]
	var sub: float = spec[5]
	var gain: float = spec[6]
	for i in samples:
		var time := i / float(RATE)
		var progress := i / float(samples)
		var freq := lerpf(pitch_start, pitch_end, progress * progress if rising else 1.0 - exp(-5.2 * progress))
		phase += TAU * freq / RATE
		sub_phase += TAU * lerpf(33.0 + sub * 38.0, 28.0, minf(1.0, progress * 2.2)) / RATE
		var raw := rng.randf_range(-1.0, 1.0)
		filtered = lerpf(filtered, raw, 0.075 + air * 0.11)
		var bite := exp(-time * (24.0 if deploy else 11.0))
		var tail := pow(1.0 - progress, tail_power)
		var edge := minf(time / 0.006, 1.0) * minf((duration - time) / 0.025, 1.0)
		var tone := sin(phase + metal * 1.8 * sin(phase * 1.495))
		var machinery := sin(phase * 1.007) * sin(time * (22.0 + 16.0 * metal))
		var rumble := sin(sub_phase) * 0.78 + sin(sub_phase * 2.02) * 0.22
		var value: float
		if deploy:
			var contact := bite + _tap(time - 0.07 - 0.028 * stage, 32.0) * 0.77
			var boot := _tap(time - 0.13 - 0.043 * stage, 4.0 + 2.3 / duration)
			var chord := 0.47 * sin(phase) + 0.30 * sin(phase * 1.498) + 0.23 * sin(phase * 2.0)
			value = ((0.68 * filtered + sub * 0.38 * rumble) * contact + chord * boot * (0.23 + 0.04 * stage)) * (1.0 - progress)
		elif rising:
			var sweep := smoothstep(0.0, 0.82, progress) * (0.72 + 0.28 * sin(time * (13.0 + 24.0 * progress)))
			value = (0.31 * tone + 0.38 * metal * machinery + air * 0.42 * filtered + sub * 0.36 * rumble) * sweep
		else:
			value = (0.38 * tone + 0.21 * metal * machinery + air * (0.32 * raw * bite + 0.78 * filtered) + sub * 0.46 * rumble) * tail
			value += sub * 0.09 * _tap(time - 0.16, 6.0) * rumble * tail
		bytes.encode_s16(i * 2, roundi(tanh(value * 1.26) * gain * edge * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	return stream

static func _tap(time: float, decay: float) -> float:
	return smoothstep(0.0, 0.014, time) * exp(-maxf(0.0, time) * decay)
