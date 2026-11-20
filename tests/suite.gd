extends SceneTree

const STEP := 1.0 / 60
const PROFILE_PATH := "user://automated_profile.cfg"

var failed := 0
var checked := 0
var arena := FieldMap.new()
var rules := BattleData.new()
var raw_map: Dictionary

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checked += 1
	if not condition:
		failed += 1
		printerr("FAIL: " + message)

func _run() -> void:
	var profile = root.get_node("Profile")
	profile.file_path = PROFILE_PATH
	var args := OS.get_cmdline_user_args()
	if "--verify-profile" in args:
		_verify_profile(profile)
	else:
		raw_map = BattleData.read_json("res://data/sample_map.json")
		check(arena.load_map(raw_map).is_empty(), "sample map valid")
		_map_and_economy()
		_wave_rules()
		_aim_and_damage()
		_fire_rate_and_sale()
		_defeat_and_cleanup()
		await _interface(profile)
		_write_profile(profile)
	print("Checks: %d, failures: %d" % [checked, failed])
	quit(1 if failed else 0)

func _map_and_economy() -> void:
	var broken := raw_map.duplicate(true)
	broken.path[5] = [30, 3]
	check("격자 밖" in FieldMap.new().load_map(broken), "outside coordinate rejected")
	broken.path[5] = [5, 2]
	check("연결" in FieldMap.new().load_map(broken), "disconnected coordinate rejected")
	broken.path[5] = [4, 3]
	check("중복" in FieldMap.new().load_map(broken), "duplicate coordinate rejected")
	var sim := Battle.new(arena, rules)
	check(sim.health == 100 and sim.credits == 50, "starting economy and health")
	check(not sim.install(arena.start) and not sim.install(arena.exit), "endpoints block installation")
	check(not sim.install(Vector2i(1, 3)) and not sim.install(Vector2i(1, 1)), "path and obstacles block installation")
	check(not sim.install(Vector2i(-1, 3)), "out of bounds placement blocked")
	for x in 5:
		check(sim.install(Vector2i(x, 2)), "tower placement %d" % x)
	check(sim.credits == 0 and sim.towers.size() == 5, "five towers spend fifty")
	check(not sim.install(Vector2i(5, 2)), "insufficient funds")
	check(sim.sell(Vector2i(2, 2)) and sim.credits == 10, "full refund")
	check(not sim.install(Vector2i(1, 2)) and not sim.sell(Vector2i(2, 2)), "no duplicate installs or refunds")
	check(sim.install(Vector2i(2, 2)) and sim.credits == 0, "reinstall after sale")

func _wave_rules() -> void:
	var expected := [10, 12, 14, 17, 21, 25, 30, 36, 43, 52]
	for i in expected.size():
		check(rules.wave_count(i + 1) == expected[i] and rules.wave_reward(i + 1) == expected[i], "original wave formula n=%d" % (i + 1))
	check(rules.wave_count(51) == 0, "campaign has no wave 51")
	var sim := Battle.new(arena, rules)
	check(sim.start_wave() and sim.enemies.size() == 1 and sim.queued == 9, "immediate first drone")
	check(not sim.start_wave(), "no overlapping waves")
	advance(sim, 29)
	check(sim.enemies.size() == 1, "first half-second spawn boundary")
	advance(sim, 1)
	check(sim.enemies.size() == 2, "second drone spawns at half a second")
	advance(sim, 240)
	check(sim.enemies.size() == 10 and sim.queued == 0, "first wave has exactly ten drones")
	check(sim.active and sim.credits == 50, "waits for the last drone")
	advance(sim, roundi((arena.length() + 5) * 60))
	check(not sim.active and sim.health == 50 and sim.credits == 60, "leaks and first wave completion reward")
	advance(sim, 60)
	check(sim.wave == 1 and sim.enemies.is_empty() and sim.credits == 60, "next wave is manual and reward is paid only once")

func _aim_and_damage() -> void:
	var sim := Battle.new(arena, rules)
	var near := sim.spawn(1.0)
	var ahead := sim.spawn(4.0)
	sim.spawn(41.0)
	sim._update_drones(0)
	check(sim.target_for(Vector2(2.0, 4.5)) == ahead, "priority uses exit progress")
	check(sim.target_for(Vector2(1.5, 7.5)) == near, "four-tile inclusive range")
	check(sim.target_for(Vector2(1.5, 7.501)) == null, "outside four tiles rejected")
	var curve := sim.spawn(8.9)
	var origin := Vector2(9.5, 6.5)
	var lead := sim.aim_at(origin, curve)
	check(absf(lead.x) < 0.001 and lead.y < 0.0, "lead follows drone around a corner")
	sim._fire(origin + lead * Battle.BARREL_LENGTH, lead)
	for i in 28:
		sim.tick(STEP)
	check(curve.health == 4, "predicted shot makes contact through the turn")
	for i in 3:
		sim._damage_drone(curve, Vector2.UP)
	check(curve.health == 1 and sim.credits == 50, "four hits leave one health")
	sim._damage_drone(curve, Vector2.UP)
	sim._damage_drone(curve, Vector2.UP)
	check(curve.health == 0 and sim.credits == 53, "fifth hit pays once")
	sim.tick(STEP)
	check(not sim.enemies.has(curve), "dead drone removed")
	check(is_equal_approx(Battle.sweep(Vector2(-2, 0), Vector2(4, 0), 0.2), 0.45), "continuous collision detects crossing")
	check(Battle.sweep(Vector2(-2, 1), Vector2(4, 0), 0.2) == -1, "sweep rejects near miss")
	sim._fire(Vector2(0.5, 0.5), Vector2.RIGHT)
	var stray: Battle.Bolt = sim.bolts.back()
	advance(sim, 6)
	check(stray.position.is_equal_approx(Vector2(1.7, 0.5)) and stray.direction == Vector2.RIGHT, "bolt preserves straight heading and speed")
	advance(sim, 40)
	check(sim.bolts.is_empty(), "miss expires")
	var leak := sim.spawn(arena.length() - 0.005)
	leak.health = 3
	advance(sim, 1)
	check(sim.health == 97 and sim.credits == 53 and not sim.enemies.has(leak), "leak uses remaining health and gives no bounty")

func _fire_rate_and_sale() -> void:
	var sim := Battle.new(arena, rules)
	var site := Vector2i(2, 4)
	check(sim.install(site), "fire rate test tower installed")
	var fired: Array[Vector2] = []
	sim.effect.connect(func(kind: StringName, at: Vector2, _dir: Vector2) -> void:
		if kind == &"fire":
			fired.append(at)
	)
	sim.spawn(1.0)
	var ticks := 0
	while fired.is_empty() and ticks < 20:
		ticks += 1
		sim.tick(STEP)
	check(fired.size() == 1, "tower acquires drone and fires")
	advance(sim, 59)
	check(fired.size() == 1, "second shot cannot fire early")
	sim.tick(STEP)
	check(fired.size() == 2, "second shot fires after one second")
	var bolt: Battle.Bolt = sim.bolts.back()
	var origin := bolt.position
	check(sim.sell(site), "firing tower can be sold")
	sim.tick(STEP)
	check(sim.towers.is_empty() and sim.bolts.has(bolt) and not bolt.position.is_equal_approx(origin), "previous shot survives tower sale")
	advance(sim, 90)
	check(fired.size() == 2 and sim.bolts.is_empty(), "sold tower cannot fire again")

func _defeat_and_cleanup() -> void:
	var sim := Battle.new(arena, rules)
	sim.health = 3
	sim.start_wave()
	var leak := sim.spawn(arena.length())
	leak.health = 3
	advance(sim, 1)
	var distance := sim.enemies[0].progress
	advance(sim, 120)
	check(sim.lost and not sim.active and sim.health == 0 and sim.queued == 0, "defeat stops spawns")
	check(sim.enemies[0].progress == distance and sim.credits == 50 and not sim.start_wave(), "defeat freezes battle without reward")
	sim = Battle.new(arena, rules)
	sim.credits = 10000
	for x in range(30):
		sim.install(Vector2i(x, 2))
	for pass_index in 3:
		for i in 1000:
			sim.spawn(1.0 + (i % 700) * 0.01)
		advance(sim, 63)
		for drone in sim.enemies:
			drone.health = 0
		advance(sim, 64)
		check(sim.enemies.is_empty() and sim.bolts.is_empty(), "battle objects drain after crowded cycle %d" % (pass_index + 1))
		check(sim._drone_pool.size() <= 1024 and sim._bolt_pool.size() <= 1024, "bounded pools")

func _interface(profile: Node) -> void:
	profile.best = 0
	var scene := load("res://scenes/Front.tscn") as PackedScene
	var ui = scene.instantiate()
	root.add_child(ui)
	await process_frame
	check(ui.battle == null and not ui.game and ui.screen.get_child_count() > 4, "main menu loads")
	await capture("menu")
	gui_click(ui, Vector2(335, 643))
	check(ui.game, "menu start receives a viewport click")
	var sim: Battle = ui.battle
	gui_click(ui, Vector2(1700, 495))
	check(ui.building and ui.field.building, "build button enters placement mode")
	var tower_tile := FieldView.pixel(Vector2(3.5, 2.5))
	gui_click(ui, tower_tile)
	check(sim.credits == 40 and sim.occupied.has(Vector2i(3, 2)), "tile click installs")
	gui_click(ui, tower_tile)
	check(ui.selected == Vector2i(3, 2) and not ui.sell_button.disabled, "tile click selects tower")
	gui_click(ui, Vector2(1700, 819))
	check(sim.credits == 50 and sim.towers.is_empty(), "sell button refunds")
	gui_click(ui, Vector2(1700, 281))
	check(sim.wave == 1 and ui.wave_callout.contains("1"), "HUD wave control")
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	ui._unhandled_input(escape)
	var distance := sim.enemies[0].progress
	ui._physics_process(STEP)
	check(ui.modal_kind == "pause" and sim.enemies[0].progress == distance and ui.field.frozen, "escape pauses simulation")
	gui_click(ui, Vector2(960, 565))
	check(ui.modal_kind == "pause_settings", "settings can be reached from pause")
	await capture("settings")
	gui_click(ui, Vector2(875, 391))
	check(profile.master < 0.80 and profile.master > 0.0, "master slider responds to viewport input")
	gui_click(ui, Vector2(835, 472))
	check(profile.effects < 0.75 and profile.effects > 0.0, "effects slider responds to viewport input")
	var modes: Array[Node] = ui.modal.find_children("*", "OptionButton", true, false)
	var window_mode := modes[0] as OptionButton
	var resolutions := modes[1] as OptionButton
	if DisplayServer.get_name() != "headless":
		window_mode.item_selected.emit(1)
		check(profile.fullscreen and root.mode == Window.MODE_FULLSCREEN and resolutions.disabled, "fullscreen controls apply to Windows")
		window_mode.item_selected.emit(0)
		resolutions.item_selected.emit(0)
		check(not profile.fullscreen and root.mode == Window.MODE_WINDOWED and root.size == Vector2i(960, 540), "windowed resolution applies to Windows")
		resolutions.item_selected.emit(1)
	ui._unhandled_input(escape)
	check(ui.modal_kind == "pause", "escape from settings returns to pause")
	gui_click(ui, Vector2(960, 510))
	ui._physics_process(STEP)
	check(sim.enemies[0].progress > distance, "continuing resumes simulation")
	check(sim.install(Vector2i(2, 4)), "battle screenshot tower")
	for i in 8:
		sim.spawn(2.0 + i * 0.5)
	advance(sim, 71)
	gui_click(ui, FieldView.pixel(Vector2(2.5, 4.5)))
	await capture("battle")
	sim.health = 1
	sim.spawn(arena.length())
	sim.tick(STEP)
	ui._process(1.0)
	check(ui.modal_kind == "defeat" and profile.best >= 1, "defeat modal and record")
	await capture("defeat")
	gui_click(ui, Vector2(960, 593))
	check(ui.battle.credits == 50 and ui.battle.health == 100 and ui.battle.wave == 0 and ui.battle.towers.is_empty(), "restart initializes a fresh game")
	ui.show_pause()
	gui_click(ui, Vector2(960, 689))
	check(ui.battle == null and not ui.game, "return to main menu")
	var sound = root.get_node("Sound")
	for key: StringName in sound._voices:
		var player: AudioStreamPlayer = sound._voices[key]
		var clip := player.stream as AudioStreamWAV
		check(clip != null and clip.data.size() > 100 and player.bus == &"Effects", "original audio cue %s on effects bus" % key)
	if DisplayServer.get_name() != "headless":
		sound._last_time.clear()
		sound.cue(&"collapse")
		check(sound._voices[&"collapse"].playing, "Windows audio player receives playback")
		await create_timer(0.9).timeout
	ui.queue_free()
	await process_frame

func gui_click(ui: Control, logical: Vector2) -> void:
	var point := ui.get_global_transform_with_canvas() * logical
	var move := InputEventMouseMotion.new()
	move.position = point
	root.push_input(move, true)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		root.push_input(click, true)

func capture(name: String) -> void:
	if "--visual" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://reports")
	DirAccess.make_dir_recursive_absolute(folder)
	var image := root.get_texture().get_image()
	check(image.save_png(folder.path_join(name + ".png")) == OK, "captured " + name)

func _write_profile(profile: Node) -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master", "bad")
	config.set_value("audio", "effects", 7.0)
	config.set_value("display", "resolution", -9)
	config.set_value("record", "best", -99)
	check(config.save(PROFILE_PATH) == OK, "prepare invalid profile")
	profile.load_profile()
	check(profile.master == 0.8 and profile.effects == 1.0 and profile.resolution == 1 and profile.best == 0, "invalid fields recover safely")
	profile.master = 0.42
	profile.effects = 0.64
	profile.fullscreen = true
	profile.resolution = 3
	profile.record_wave(7)
	profile.record_wave(5)
	check(not profile.save_error and profile.best == 7, "settings saved and lower score ignored")
	_verify_profile(profile)

func _verify_profile(profile: Node) -> void:
	profile.load_profile()
	check(is_equal_approx(profile.master, 0.42) and is_equal_approx(profile.effects, 0.64), "volume settings persisted")
	check(profile.fullscreen and profile.resolution == 3, "display settings persisted")
	check(profile.best == 7, "best wave persisted")

func advance(sim: Battle, ticks: int) -> void:
	for i in ticks:
		sim.tick(STEP)
