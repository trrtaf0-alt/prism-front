extends SceneTree

const WARMUP := 2.0
const DURATION := 8.0
const TARGETS := [100, 500, 1000]

var ui: Control
var level := 0
var frame_times: Array[float] = []
var elapsed := 0.0
var measured := 0.0
var peak_bolts := 0
var peak_flares := 0
var start_usec := 0
var rng := RandomNumberGenerator.new()

func _initialize() -> void:
	call_deferred("_setup")

func _setup() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Benchmark requires the Windows graphics backend.")
		quit(1)
		return
	var scene := load("res://scenes/Front.tscn") as PackedScene
	ui = scene.instantiate()
	root.add_child(ui)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 120
	print("Renderer: %s / %s / %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version(), str(root.size)])
	process_frame.connect(_frame)
	_set_level()

func _set_level() -> void:
	ui.start_game()
	var sim: Battle = ui.get("battle")
	var target: int = TARGETS[level]
	var towers := ceili(target / 10.0)
	sim.credits = 100_000
	for segment in sim.field.path.size():
		var cell := Vector2i(sim.field.path[segment].floor())
		for offset in [Vector2i.UP, Vector2i.DOWN]:
			if towers > 0 and sim.install(cell + offset):
				towers -= 1
	rng.seed = 3401 + level
	_fill(sim, target)
	frame_times.clear()
	elapsed = 0.0
	measured = 0.0
	peak_bolts = 0
	peak_flares = 0
	start_usec = Time.get_ticks_usec()
	print("Stress tier: %d drones, %d turrets" % [target, sim.towers.size()])

func _fill(sim: Battle, target: int) -> void:
	while sim.enemies.size() < target:
		sim.spawn(rng.randf_range(0.2, sim.field.length() - 1.0))

func _frame() -> void:
	var now := Time.get_ticks_usec()
	var delta := (now - start_usec) / 1_000_000.0
	start_usec = now
	elapsed += delta
	var sim: Battle = ui.get("battle")
	var field: FieldView = ui.get("field")
	# Keep pressure constant while exercising the actual towers, bolt sweeps and effects.
	sim.health = 100
	_fill(sim, TARGETS[level])
	if elapsed >= WARMUP:
		frame_times.append(delta * 1000.0)
		measured += delta
		peak_bolts = maxi(peak_bolts, sim.bolts.size())
		peak_flares = maxi(peak_flares, field._flares.size())
	if elapsed < WARMUP + DURATION:
		return
	frame_times.sort()
	var p95 := frame_times[ceili(frame_times.size() * 0.95) - 1]
	print("%d drones: %.1f mean FPS, %.2f ms p95, %d peak bolts, %d peak FX" % [
		TARGETS[level], frame_times.size() / measured, p95, peak_bolts, peak_flares
	])
	level += 1
	if level == TARGETS.size():
		process_frame.disconnect(_frame)
		ui.show_menu()
		await create_timer(0.9).timeout
		quit()
	else:
		_set_level()
