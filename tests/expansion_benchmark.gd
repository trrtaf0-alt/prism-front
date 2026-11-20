extends SceneTree

const COUNTS := [100, 500, 1000]
const STARTS: Array[Vector2i] = [
	Vector2i(5, 4), Vector2i(7, 4), Vector2i(4, 4), Vector2i(5, 5), Vector2i(6, 5),
	Vector2i(7, 5), Vector2i(8, 5), Vector2i(3, 4), Vector2i(2, 4), Vector2i(2, 5),
	Vector2i(3, 5), Vector2i(4, 5), Vector2i(8, 4), Vector2i(10, 4), Vector2i(10, 5),
	Vector2i(12, 9), Vector2i(22, 12), Vector2i(5, 12), Vector2i(6, 12), Vector2i(7, 12),
	Vector2i(8, 12), Vector2i(9, 12), Vector2i(10, 12), Vector2i(11, 12), Vector2i(12, 12),
]
const IDS := [
	"tower_16", "tower_23", "tower_25", "tower_27", "tower_28",
	"tower_29", "tower_30", "tower_22", "tower_24", "tower_26",
	"tower_30", "tower_29", "tower_27", "tower_23", "tower_16",
	"tower_30", "tower_29", "tower_28", "tower_26", "tower_23",
	"tower_16", "tower_25", "tower_12", "tower_21", "tower_14",
]

class MeasuredArsenal extends TowerArsenal:
	var micros: Dictionary = {}

	func attack(sim, tower, target, def: Dictionary, direction: Vector2, efficiency: float = 1.0) -> void:
		var start := Time.get_ticks_usec()
		super(sim, tower, target, def, direction, efficiency)
		micros[def.attack] = int(micros.get(def.attack, 0)) + Time.get_ticks_usec() - start

	func update(sim, delta: float) -> void:
		var start := Time.get_ticks_usec()
		super(sim, delta)
		micros["sequences"] = int(micros.get("sequences", 0)) + Time.get_ticks_usec() - start

class MeasuredBattle extends Battle:
	var micros := {"movement": 0, "projectiles": 0, "towers": 0, "removal": 0}

	func _update_drones(delta: float) -> void:
		var start := Time.get_ticks_usec()
		super(delta)
		micros.movement += Time.get_ticks_usec() - start

	func _update_bolts(delta: float) -> void:
		var start := Time.get_ticks_usec()
		super(delta)
		micros.projectiles += Time.get_ticks_usec() - start

	func _update_towers(delta: float) -> void:
		var start := Time.get_ticks_usec()
		super(delta)
		micros.towers += Time.get_ticks_usec() - start

	func _remove_drones() -> void:
		var start := Time.get_ticks_usec()
		super()
		micros.removal += Time.get_ticks_usec() - start

var field := FieldMap.new()
var data := BattleData.new()
var armored: Dictionary
var rng := RandomNumberGenerator.new()
var ui
var level := 0
var elapsed := 0.0
var measured := 0.0
var frames: Array[float] = []
var physics: Array[float] = []
var previous := 0
var bolts := 0
var fx := 0
var strikes := 0
var ticks := 0
var base_objects := 0

func _initialize() -> void:
	call_deferred("_setup")

func _setup() -> void:
	if not field.load_map(BattleData.read_json("res://data/sample_map.json")).is_empty():
		quit(1)
		return
	armored = data.drone.duplicate()
	armored.health = 10_000_000
	if "--profile-combat" in OS.get_cmdline_user_args():
		_profile()
		return
	if "--soak" in OS.get_cmdline_user_args():
		await _soak()
		return
	if DisplayServer.get_name() == "headless":
		printerr("Rendering benchmark requires Windows graphics.")
		quit(1)
		return
	var profile = root.get_node("Profile")
	profile.fx_quality = 3
	profile.fx_particles = 0.85
	profile.fx_dim = false
	profile.fx_shake = 0.35
	var scene := load("res://scenes/Front.tscn") as PackedScene
	ui = scene.instantiate()
	root.add_child(ui)
	ui.set_process_unhandled_input(false)
	root.gui_disable_input = true
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 120
	print("Renderer: %s / %s / size %s / high quality" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version(), root.size])
	process_frame.connect(_frame)
	physics_frame.connect(_tick)
	_reset()

func _reset() -> void:
	ui.start_game()
	var sim: Battle = ui.battle
	_configure(sim, [10, 15, 25][level])
	rng.seed = 850 + level
	_fill(sim, COUNTS[level])
	frames.clear()
	physics.clear()
	elapsed = 0.0
	measured = 0.0
	bolts = 0
	fx = 0
	strikes = 0
	ticks = 0
	sim.attack_visual.connect(_tally)
	previous = Time.get_ticks_usec()
	print("Tier %d enemies, %d towers" % [COUNTS[level], sim.towers.size()])

func _tick() -> void:
	if ui.modal == null and not ui.battle.lost:
		ticks += 1

func _tally(style: String, _a: Vector2, _b: Vector2, _r: float, _t: Color, _l: float, _s: int) -> void:
	if style == "cataclysm":
		strikes += 1

func _configure(sim: Battle, tower_count: int) -> void:
	sim.credits = 10_000_000
	sim.health = BattleData.NUMBER_LIMIT
	sim.research.earn(100000)
	for id in sim.data.research.ordered:
		sim.research.purchase(id)
	for i in tower_count:
		if not sim.install(STARTS[i], IDS[i]):
			printerr("Failed stress emplacement: ", STARTS[i], " / ", IDS[i])
			quit(1)

func _fill(sim: Battle, target: int) -> void:
	while sim.enemies.size() < target:
		sim.spawn(rng.randf_range(0.5, field.length() - 4.0), armored)

func _frame() -> void:
	var now := Time.get_ticks_usec()
	var delta := (now - previous) / 1_000_000.0
	previous = now
	elapsed += delta
	var sim: Battle = ui.battle
	var view: FieldView = ui.field
	_fill(sim, COUNTS[level])
	if elapsed >= 2.0:
		frames.append(delta * 1000.0)
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		measured += delta
		bolts = maxi(bolts, sim.bolts.size())
		fx = maxi(fx, view.advanced_fx._huge.size() + view.advanced_fx._ordinary.size())
	if elapsed < 10.0:
		return
	frames.sort()
	physics.sort()
	print("%d drones: %.1f FPS; frame p95 %.2f ms; physics p95 %.2f ms; %d peak bolts; %d peak FX events; %d cataclysms; %d ticks" % [
		COUNTS[level], frames.size() / measured, frames[ceili(frames.size() * 0.95) - 1],
		physics[ceili(physics.size() * 0.95) - 1], bolts, fx, strikes, ticks,
	])
	if strikes <= 0 or ticks < 211 or not ui.modal_kind.is_empty() or sim.lost:
		printerr("Incomplete stress tier. modal=", ui.modal_kind, " lost=", sim.lost, " ticks=", ticks)
		quit(1)
		return
	level += 1
	if level < COUNTS.size():
		_reset()
	else:
		process_frame.disconnect(_frame)
		physics_frame.disconnect(_tick)
		ui.show_menu()
		await create_timer(0.90).timeout
		quit()

func _profile() -> void:
	var sim := MeasuredBattle.new(field, data)
	var attack := MeasuredArsenal.new()
	sim.arsenal = attack
	_configure(sim, 25)
	rng.seed = 852
	_fill(sim, 1000)
	var start := Time.get_ticks_usec()
	for i in 480:
		_fill(sim, 1000)
		sim.tick(1.0 / 60.0)
	print("Time for 480 physics ticks: %.1f ms" % ((Time.get_ticks_usec() - start) / 1000.0))
	print("Physics phases, ms: ", _millis(sim.micros))
	print("Attack phases, ms: ", _millis(attack.micros))
	quit()

func _millis(micros: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in micros:
		result[key] = int(micros[key]) / 1000.0
	return result

func _soak() -> void:
	print("Soak: 12 fresh simulations × 30 seconds, 500 enemies, 15 towers")
	base_objects = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var peak_delta := 0
	for trial in 12:
		_simulate_cycle(trial)
		await process_frame
		var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
		peak_delta = maxi(peak_delta, objects - base_objects)
		print("Soak cycle %d: %d objects, %.2f MiB static" % [trial + 1, objects, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
	print("Post-run peak delta from startup: %d objects" % peak_delta)
	var stable := await _single_battle_soak()
	quit(1 if peak_delta > 25 or not stable else 0)

func _single_battle_soak() -> bool:
	var sim := Battle.new(field, data)
	_configure(sim, 15)
	rng.seed = 1757
	_fill(sim, 500)
	for block in 4:
		for tick in 1800:
			if tick % 6 == 0:
				_fill(sim, 500)
			sim.tick(1.0 / 60.0)
		await process_frame
		print("Continuous sim %ds: %d drones, %d bolts, %d sequences, %d objects, %.2f MiB static" % [
			(block + 1) * 30, sim.enemies.size(), sim.bolts.size(), sim.arsenal.sequences.size(),
			int(Performance.get_monitor(Performance.OBJECT_COUNT)), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		])
	return not sim.lost and sim.enemies.size() <= 500 and sim.bolts.size() <= 1000 and sim.arsenal.sequences.size() <= 50

func _simulate_cycle(trial: int) -> void:
	var sim := Battle.new(field, data)
	_configure(sim, 15)
	rng.seed = 810 + trial
	_fill(sim, 500)
	for tick in 1800:
		if tick % 6 == 0:
			_fill(sim, 500)
		sim.tick(1.0 / 60.0)
