extends SceneTree

const STEP := 1.0 / 60.0
var rules := BattleData.new()
var map := FieldMap.new()
var checked := 0
var bad := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checked += 1
	if not ok:
		bad += 1
		printerr("FAIL: " + message)

func _run() -> void:
	check(map.load_map(BattleData.read_json("res://data/sample_map.json")).is_empty(), "map loads")
	check(rules.mobs.error.is_empty() and rules.research.error.is_empty(), "campaign definitions validate")
	_count_and_timing()
	_victory_conditions()
	_preview_matches_spawn()
	await _ui_and_record()
	print("Campaign checks: %d, failures: %d" % [checked, bad])
	quit(1 if bad else 0)

func _count_and_timing() -> void:
	var checkpoints := {1: 10, 10: 52, 20: 162, 30: 332, 40: 562, 49: 820, 50: 852, 51: 0}
	for wave in checkpoints:
		check(rules.wave_count(wave) == checkpoints[wave], "exact slots W%d" % wave)
	for wave in range(1, 51):
		var amount := rules.wave_count(wave)
		var roster := WaveRoster.new(rules.mobs, wave, amount, 811)
		var bosses := 0
		for i in amount:
			var unit := roster.next()
			bosses += int(unit.boss)
		check(bosses == int(wave == 50), "only one boss and only on W50, W%d" % wave)
	for wave in [1, 9, 20, 39, 49]:
		check(is_equal_approx(rules.spawn_interval(wave), maxf(0.04, 0.5 * pow(0.95, wave - 1))), "cadence W%d" % wave)
	var sim := Battle.new(map, rules)
	sim.wave = 48
	sim.start_wave()
	sim.tick(5.0)
	var delivered := 1 + floori(5.0 / rules.spawn_interval(49))
	check(sim.primary_spawned == delivered and sim.queued == 820 - delivered, "stalled frame emits all elapsed slots")
	sim._dispatch(1000.0)
	check(sim.primary_spawned == 820 and sim.queued == 0, "all original slots retained at W49")

func _preview_matches_spawn() -> void:
	var sim := Battle.new(map, rules)
	sim.roster_seed = 7043
	check(sim.preview_wave() == {"normal": 10}, "opening preview contains ten regular drones")
	sim.wave = 4
	var expected := sim.preview_wave()
	check(expected.has("swift") and expected == sim.preview_wave(), "opening threat preview is reproducible")
	sim.start_wave()
	sim._dispatch(30.0)
	var actual := {}
	for drone in sim.enemies:
		var id: String = drone.definition.id
		actual[id] = int(actual.get(id, 0)) + 1
	check(actual == expected, "preview matches actual encounter without advancing its RNG")

func _victory_conditions() -> void:
	var sim := Battle.new(map, rules)
	sim.wave = 49
	check(sim.start_wave() and sim.primary_spawned == 1 and sim.bosses.size() == 1, "boss spawns immediately and counts as a slot")
	check(not sim.start_wave(), "manual next is locked during a wave")
	sim._apply_damage(sim.bosses[0], 9_000_000, Vector2.ZERO)
	sim.tick(STEP)
	check(sim.active and sim.boss_killed and not sim.won and sim.queued > 0, "boss kill alone does not win")
	sim._dispatch(900.0)
	check(sim.queued == 0 and sim.primary_spawned == 852 and sim.enemies.size() == 851, "all scheduled escorts arrive")
	for drone in sim.enemies:
		sim._apply_damage(drone, 9_000_000, Vector2.ZERO)
	sim.tick(STEP)
	check(sim.active and not sim.won, "queued split descendants also block victory")
	var events: Array[Dictionary] = []
	sim.cleared.connect(func(record: Dictionary): events.append(record))
	_drain(sim)
	check(sim.won and not sim.active and sim.health > 0 and sim.boss_killed and events.size() == 1, "eligible final clear emitted exactly once")
	check(not sim.start_wave() and sim.wave == 50 and not sim.install(Vector2i(1, 2)), "cleared simulation stops")
	var earned := sim.total_credits
	sim.tick(2.0)
	check(events.size() == 1 and sim.total_credits == earned, "clear reward cannot be collected twice")
	sim = Battle.new(map, rules)
	sim.wave = 49
	sim.start_wave()
	sim.queued = 0
	var boss := sim.bosses[0]
	boss.health = 9
	boss.progress = map.length()
	sim.tick(STEP)
	check(sim.lost and not sim.won and sim.boss_escaped and sim.health == 91 and not sim.start_wave(), "boss escape fails even with a surviving core")

func _drain(sim: Battle) -> void:
	for i in 4:
		for drone in sim.enemies:
			sim._apply_damage(drone, 9_000_000, Vector2.ZERO)
		sim.tick(STEP)

func _ui_and_record() -> void:
	var profile = root.get_node("Profile")
	profile.file_path = "user://campaign_qa_profile.cfg"
	profile.best = 90
	profile.campaign_best = 0
	profile.best_clear = {}
	profile.fastest_clear = 0.0
	profile.master = 0.42
	var packed := load("res://scenes/Front.tscn") as PackedScene
	var ui = packed.instantiate()
	root.add_child(ui)
	await process_frame
	ui.start_game()
	var sim: Battle = ui.battle
	var turret := rules.towers.lookup(TowerRegistry.BASE)
	check(ui.field.path_in_range(Vector2i(1, 2), turret) > 4.0, "entry preview clips the path into firing range")
	check(ui.field.path_in_range(Vector2i(0, 17), turret) == 0.0, "remote legal position has no path coverage")
	check(is_equal_approx(ui.field.path_in_range(Vector2i(0, 17), rules.towers.lookup("tower_29")), map.length()), "global targeting previews the entire path")
	sim.roster_seed = 7043
	sim.wave = 4
	ui.field.hovered = Vector2i(8, 4)
	ui.toggle_build()
	check(ui.forecast.text.contains("신속형") and ui.build_hint.text.begins_with("조준 가능한 경로"), "HUD displays upcoming threat and placement coverage")
	if "--visual" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		ui.set_process(false)
		await RenderingServer.frame_post_draw
		var file := ProjectSettings.globalize_path("res://reports/opening-preview.png")
		check(root.get_texture().get_image().save_png(file) == OK, "opening HUD captured")
		ui.set_process(true)
	ui.toggle_build()
	sim.wave = 49
	sim.elapsed = 2010.0
	sim.start_wave()
	sim.queued = 0
	_drain(sim)
	check(ui.modal_kind == "victory" and ui.wave_button.disabled and not ui.can_open_research(), "victory UI differs from defeat and locks play")
	check(not ui.toast.visible and ui.callout_time == 0.0, "victory dismisses prior combat notices")
	check(profile.best == 90 and profile.campaign_best == 50 and profile.fastest_clear > 0.0, "legacy and campaign records stay separate")
	if "--visual" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		var file := ProjectSettings.globalize_path("res://reports/campaign-victory.png")
		check(root.get_texture().get_image().save_png(file) == OK, "victory captured")
	var shorter := sim.clear_record()
	shorter.seconds = 1500.0
	shorter.health = 85
	profile.record_clear(shorter)
	profile.load_profile()
	check(profile.best == 90 and profile.campaign_best == 50 and profile.fastest_clear == 1500.0 and profile.best_clear.health == 100 and profile.master == 0.42, "best defense, fastest time and settings persist")
	ui.start_game()
	check(ui.battle.wave == 0 and ui.battle.credits == 50 and ui.battle.research.points == 0 and ui.battle.total_kills == 0 and ui.battle.total_installs == 0 and not ui.battle.won and profile.fastest_clear == 1500.0, "restart resets campaign but retains saved record")
	ui.queue_free()
	await process_frame
