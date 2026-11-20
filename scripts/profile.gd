extends Node

const PATH := "user://profile.cfg"
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080),
]

var master := 0.80
var effects := 0.75
var fullscreen := false
var resolution := 1
var best := 0
var file_path := PATH
var save_error := false
var fx_quality := 2
var fx_particles := 0.85
var fx_flash := 0.45
var fx_shake := 0.35
var fx_dim := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	if "--qa" in args or "--benchmark" in args:
		file_path = "user://test_profile.cfg"
	load_profile()
	apply_audio()
	if DisplayServer.get_name() != "headless":
		apply_display()

func load_profile() -> void:
	master = 0.80
	effects = 0.75
	fullscreen = false
	resolution = 1
	best = 0
	fx_quality = 2
	fx_particles = 0.85
	fx_flash = 0.45
	fx_shake = 0.35
	fx_dim = false
	var config := ConfigFile.new()
	if config.load(file_path) != OK:
		return
	master = _volume(config.get_value("audio", "master", master), master)
	effects = _volume(config.get_value("audio", "effects", effects), effects)
	var quality: Variant = config.get_value("visual", "quality", fx_quality)
	if quality is int:
		fx_quality = clampi(quality, 0, 2)
	fx_particles = _volume(config.get_value("visual", "particles", fx_particles), fx_particles)
	fx_flash = _volume(config.get_value("visual", "flash", fx_flash), fx_flash)
	fx_shake = _volume(config.get_value("visual", "shake", fx_shake), fx_shake)
	fx_dim = config.get_value("visual", "dim", fx_dim) == true
	var saved_mode: Variant = config.get_value("display", "fullscreen", false)
	fullscreen = saved_mode == true
	var saved_size: Variant = config.get_value("display", "resolution", resolution)
	if saved_size is int and saved_size >= 0 and saved_size < RESOLUTIONS.size():
		resolution = saved_size
	var saved_best: Variant = config.get_value("record", "best", 0)
	if saved_best is int and saved_best >= 0:
		best = mini(saved_best, BattleData.NUMBER_LIMIT)

func _volume(value: Variant, fallback: float) -> float:
	if (value is int or value is float) and is_finite(float(value)):
		return clampf(float(value), 0.0, 1.0)
	return fallback

func save_profile() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master", master)
	config.set_value("audio", "effects", effects)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "resolution", resolution)
	config.set_value("record", "best", best)
	config.set_value("visual", "quality", fx_quality)
	config.set_value("visual", "particles", fx_particles)
	config.set_value("visual", "flash", fx_flash)
	config.set_value("visual", "shake", fx_shake)
	config.set_value("visual", "dim", fx_dim)
	var temp := file_path + ".tmp"
	var error := config.save(temp)
	if error == OK:
		error = DirAccess.rename_absolute(temp, file_path)
	save_error = error != OK
	if save_error:
		push_warning("설정 및 기록을 저장할 수 없습니다. 오류 %d" % error)

func record_wave(wave: int) -> void:
	if wave > best:
		best = wave
		save_profile()

func apply_audio() -> void:
	_set_bus(0, master)
	var index := AudioServer.get_bus_index("Effects")
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, "Effects")
		AudioServer.set_bus_send(index, "Master")
	_set_bus(index, effects)

func _set_bus(index: int, value: float) -> void:
	AudioServer.set_bus_mute(index, value <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.001)))

func apply_display() -> void:
	var window := get_window()
	window.min_size = Vector2i(800, 450)
	window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	if not fullscreen:
		var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
		var selected := RESOLUTIONS[resolution]
		var ratio := minf(1.0, minf((usable.size.x - 32) / float(selected.x), (usable.size.y - 64) / float(selected.y)))
		window.size = Vector2i(Vector2(selected) * ratio)
		window.position = usable.position + (usable.size - window.size) / 2
