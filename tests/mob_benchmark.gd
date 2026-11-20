extends SceneTree

const SEATS: Array[Vector2i] = [
	Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2), Vector2i(8, 2),
	Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4), Vector2i(7, 4),
	Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5), Vector2i(6, 5),
	Vector2i(7, 5), Vector2i(8, 5), Vector2i(12, 9), Vector2i(5, 12),
]
const GEAR := [
	"tower_16", "tower_23", "tower_25", "tower_27", "tower_28", "tower_29", "tower_30", "tower_22",
	"tower_30", "tower_29", "tower_07", "tower_18", "tower_20", "tower_24", "tower_26", "tower_14",
]
const SIZES := [100, 500, 1000, 5000]
var tier_limit := SIZES.size()
var support_stress := false
const TYPES := ["normal", "normal", "normal", "normal", "swift", "swarm", "armored", "shield", "regen", "cloak", "resist", "accelerate", "heavy", "energy"]

class TimedBattle extends Battle:
	var micros := {"movement": 0, "projectiles": 0, "towers": 0, "support": 0}

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

	func apply_support(caster: Battle.Drone, config: Dictionary, shield: bool) -> void:
		var start := Time.get_ticks_usec()
		super(caster, config, shield)
		micros.support += Time.get_ticks_usec() - start

var rules := BattleData.new()
var map := FieldMap.new()
var random := RandomNumberGenerator.new()
var fixture: Dictionary = {}
var ui
var tier := 0
var elapsed := 0.0
var measured := 0.0
var times: Array[float] = []
var previous := 0
var ticks := 0
var peak_live := 0
var grants := 0
var impacts := 0
var quantum_hits := 0
var sync_starts := 0
var cursor := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not map.load_map(BattleData.read_json("res://data/sample_map.json")).is_empty() or not rules.mobs.error.is_empty():
		quit(1)
		return
	for id in rules.mobs.definitions:
		var def := rules.mobs.lookup(id).duplicate()
		def.health = maxi(1_000_000, int(def.health))
		fixture[id] = def
	support_stress = "--support-stress" in OS.get_cmdline_user_args()
	if support_stress or "--campaign" in OS.get_cmdline_user_args():
		tier_limit = 3
	if "--profile-combat" in OS.get_cmdline_user_args():
		_profile_combat()
		return
	if "--soak" in OS.get_cmdline_user_args():
		await _soak()
		return
	if DisplayServer.get_name() == "headless":
		printerr("Windows render mode is required for FPS.")
		quit(1)
		return
	var profile = root.get_node("Profile")
	profile.fx_quality = 3
	profile.fx_particles = 0.85
	profile.fx_dim = false
	profile.fx_shake = 0.35
	var packed := load("res://scenes/Front.tscn") as PackedScene
	ui = packed.instantiate()
	root.add_child(ui)
	root.size = Vector2i(1920, 1080)
	root.gui_disable_input = true
	ui.set_process_unhandled_input(false)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 120
	print("Renderer: ", RenderingServer.get_video_adapter_name(), " / ", root.size, " / High")
	process_frame.connect(_frame)
	physics_frame.connect(_physics)
	_reset()

func _configure(sim: Battle, tower_count: int, count: int) -> void:
	sim.health = BattleData.NUMBER_LIMIT
	sim.credits = 10_000_000
	sim.research.earn(100000)
	for id in sim.data.research.ordered:
		sim.research.purchase(id)
	for i in tower_count:
		if not sim.install(SEATS[i], GEAR[i]):
			printerr("Invalid test emplacement: ", SEATS[i], " / ", GEAR[i])
			quit(1)
	if support_stress:
		var built := 0
		for y in range(2, 16):
			for x in range(2, 25):
				if built >= 36:
					break
				var id: String = "tower_%02d" % (31 + built) if built < 6 else ["tower_01", "tower_06", "tower_09", "tower_12", "tower_13", "tower_14", "tower_18"][built % 7]
				if sim.install(Vector2i(x, y), id):
					built += 1
		sim.support.command_time = 14.0
	var support := mini(8, ceili(count / 135.0))
	for i in support:
		sim.spawn(6.0 + i * 5.8, fixture.guardian)
		sim.spawn(6.2 + i * 5.8, fixture.amplifier)
	sim.spawn(15.0, fixture.boss)
	for i in mini(12, ceili(count / 140.0)):
		sim.spawn(4.0 + i * 3, fixture.brood)

func _fill(sim: Battle, target: int) -> void:
	while sim.enemies.size() < target:
		var id: String = TYPES[cursor % TYPES.size()]
		cursor += 1
		sim.spawn(random.randf_range(0.75, map.length() - 6.0), fixture[id])

func _reset() -> void:
	ui.start_game()
	var sim: Battle = ui.battle
	var count: int = SIZES[tier]
	_configure(sim, [8, 10, 12, 16][tier], count)
	cursor = 0
	random.seed = 3550 + tier
	_fill(sim, count)
	elapsed = 0.0
	measured = 0.0
	times.clear()
	ticks = 0
	peak_live = count
	grants = 0
	impacts = 0
	quantum_hits = 0
	sync_starts = 0
	sim.support_visual.connect(_on_support_visual)
	sim.mob_visual.connect(_on_mob)
	sim.attack_visual.connect(_on_attack)
	previous = Time.get_ticks_usec()
	print("Beginning %d mobs with %d towers and one boss" % [count, sim.towers.size()])

func _on_mob(kind: StringName, _start: Vector2, _end: Vector2, _tint: Color, _life: float) -> void:
	grants += int(kind == &"grant")

func _on_attack(kind: String, _start: Vector2, _end: Vector2, _r: float, _t: Color, _l: float, _s: int) -> void:
	impacts += int(kind == "cataclysm")

func _on_support_visual(kind: StringName, _buff: int, _start: Vector2, _end: Vector2) -> void:
	quantum_hits += int(kind == &"quantum")
	sync_starts += int(kind == &"sync")

func _physics() -> void:
	ticks += 1

func _frame() -> void:
	var now := Time.get_ticks_usec()
	var delta := (now - previous) / 1_000_000.0
	previous = now
	elapsed += delta
	var sim: Battle = ui.battle
	_fill(sim, SIZES[tier])
	peak_live = maxi(peak_live, sim.enemies.size())
	if elapsed > 2.0:
		times.append(delta * 1000.0)
		measured += delta
	var limit := 12.0 if tier == SIZES.size() - 1 else 10.0
	if elapsed < limit or (tier == SIZES.size() - 1 and ticks < 250 and elapsed < 28.0):
		return
	times.sort()
	print("%d mobs: %.1f FPS; frame p95 %.2f ms; %d ticks; peak %d; %d guard links; %d cataclysm casts" % [
		SIZES[tier], times.size() / measured, times[ceili(times.size() * 0.95) - 1], ticks, peak_live, grants, impacts,
	])
	if support_stress:
		print("Support sample: %d quantum hits; %d synchronization starts" % [quantum_hits, sync_starts])
	if impacts <= 0 or grants <= 0 or sim.lost or ui.modal != null or (support_stress and (quantum_hits == 0 or sync_starts == 0)):
		printerr("Benchmark sample did not receive expected battle activity.")
		quit(1)
		return
	tier += 1
	if tier < tier_limit:
		_reset()
	else:
		process_frame.disconnect(_frame)
		physics_frame.disconnect(_physics)
		ui.show_menu()
		await create_timer(1.0).timeout
		quit()

func _profile_combat() -> void:
	var sim := TimedBattle.new(map, rules)
	_configure(sim, 16, 5000)
	random.seed = 3553
	_fill(sim, 5000)
	var start := Time.get_ticks_usec()
	for i in 360:
		sim.tick(1.0 / 60)
	var seconds := (Time.get_ticks_usec() - start) / 1_000_000.0
	print("5000 fixture, 360 physics ticks: %.3fs; timed phases in μs %s" % [seconds, sim.micros])
	quit()

func _soak() -> void:
	var baseline := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var ceiling := baseline
	for trial in 6:
		_cycle(trial)
		await process_frame
		var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
		ceiling = maxi(ceiling, objects)
		print("Restart %d: %d objects; %.2f MiB static" % [trial + 1, objects, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
	print("Maximum object increase after disposal: ", ceiling - baseline)
	quit(1 if ceiling - baseline > 40 else 0)

func _cycle(trial: int) -> void:
	var sim := Battle.new(map, rules)
	_configure(sim, 10, 1000)
	cursor = 0
	random.seed = 3550 + trial
	for i in 1800:
		if i % 15 == 0:
			_fill(sim, 1000)
		sim.tick(1.0 / 60)
