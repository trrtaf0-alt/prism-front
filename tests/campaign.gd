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
	_difficulty_and_escorts()
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

func _difficulty_and_escorts() -> void:
	var health := [2_400_000, 5_200_000, 9_400_000]
	var shields := [85_000, 144_500, 212_500]
	var speed := [0.115, 0.126, 0.14]
	var expected_guardian := [440, 850, 3.3]
	var index := 0
	for mode: StringName in BattleData.DIFFICULTIES:
		var guardian := rules.enemy_for_wave(rules.mobs.lookup("guardian"), 50, mode)
		check([int(guardian.health), int(guardian.guardian.shield_hp), float(guardian.guardian.interval)] == expected_guardian, "guardian uses the same nerfed tuning in " + str(mode))
		var sim := Battle.new(map, rules, mode)
		sim.wave = 49
		sim.start_wave()
		check(sim.bosses.size() == 1 and sim.bosses[0].maximum_health == health[index] and sim.bosses[0].shield_hp == shields[index] and is_equal_approx(sim.bosses[0].speed, speed[index]), "real boss uses selected difficulty " + str(mode))
		check(sim.queued == 851, "boss still occupies one primary slot")
		sim._dispatch(4.0)
		check(sim.primary_spawned == 1 + floori(4.0 / rules.spawn_interval(50)), "supporters stream from the beginning like a normal wave")
		sim._dispatch(31.0)
		check(sim.primary_spawned == 852 and sim.bosses.size() == 1 and sim.queued == 0, "all 851 escort slots arrive within 35 seconds while boss lives")
		var opener := rules.enemy_for_wave(rules.mobs.lookup("normal"), 1, mode)
		check(int(opener.health) == 5 and is_equal_approx(float(opener.speed), 1.0), "first wave retains its basic enemy stats")
		var normal := rules.enemy_for_wave(rules.mobs.lookup("normal"), 50, mode)
		check(int(normal.health) == [13, 30, 50][index], "late regular units have difficulty-appropriate health")
		var energy := rules.enemy_for_wave(rules.mobs.lookup("energy"), 50, mode)
		check(int(energy.health) == [6760, 15600, 26000][index] and int(energy.shield) == [4680, 10800, 18000][index], "late energy HP and shield scale")
		var child := rules.enemy_for_wave(rules.mobs.lookup("split_2"), 50, mode)
		check(int(child.health) == [10, 24, 40][index] and int(child.reward_rp) == 0, "generated enemies scale without introducing RP")
		index += 1
	check(rules.mobs.lookup("boss").health == 2_400_000 and rules.mobs.lookup("normal").health == 5, "difficulty does not mutate shared enemy definitions")

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
	var old := ConfigFile.new()
	old.set_value("campaign_04", "fastest_clear", 900.0)
	old.set_value("campaign_05", "fastest_clear", 700.0)
	old.set_value("campaign_06_easy", "fastest_clear", 600.0)
	old.set_value("campaign_07_easy", "fastest_clear", 500.0)
	old.set_value("visual", "quality", 1)
	old.save(profile.file_path)
	profile.load_profile()
	check(profile.fx_quality == 2 and profile.campaign_record().fastest_clear == 0.0, "legacy quality migrates without mixing campaign records")
	profile.best = 90
	profile.master = 0.42
	profile.apply_audio()
	var sound = root.get_node("Sound")
	var packed := load("res://scenes/Front.tscn") as PackedScene
	var ui = packed.instantiate()
	root.add_child(ui)
	await process_frame
	check(sound.music_track == &"patrol", "menu starts normal music")
	ui.start_game()
	check(sound.music_track == &"patrol", "entering a battle keeps normal music")
	var sim: Battle = ui.battle
	var turret := rules.towers.lookup(TowerRegistry.BASE)
	check(ui.field.path_in_range(Vector2i(1, 2), turret) > 4.0, "entry preview clips the path into firing range")
	check(ui.field.path_in_range(Vector2i(0, 17), turret) == 0.0, "remote legal position has no path coverage")
	check(is_equal_approx(ui.field.path_in_range(Vector2i(0, 17), rules.towers.lookup("tower_29")), map.length()), "global targeting previews the entire path")
	sim.roster_seed = 7043
	sim.wave = 4
	ui.field.hovered = Vector2i(8, 4)
	ui.toggle_build()
	check(ui.forecast.text.contains("신속형") and ui.placement_label.text.begins_with("조준 가능한 경로"), "HUD displays upcoming threat and placement coverage")
	if "--visual" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		ui.set_process(false)
		await RenderingServer.frame_post_draw
		var file := ProjectSettings.globalize_path("res://reports/opening-preview.png")
		check(root.get_texture().get_image().save_png(file) == OK, "opening HUD captured")
		ui.set_process(true)
	ui.toggle_build()
	sim.wave = 49
	ui._update_hud()
	check(ui.forecast.text.begins_with("보스 1 · 지원군 851"), "wave 50 forecast identifies the boss and escorts concisely")
	ui.wave_callout = "이전 알림"
	ui.callout_time = 1.0
	ui.toast.show()
	sim.elapsed = 2010.0
	sim.start_wave()
	ui._update_hud()
	check(ui.wave_callout.is_empty() and ui.callout_time == 0.0 and not ui.toast.visible, "the boss entrance clears the prior toast and does not open a new one")
	check(ui.boss_panel.visible and ui.boss_title.text == "보스  ·  1단계" and ui.wave_button.text == "보스전", "boss information stays in the health HUD")
	check(sound.music_track == &"boss", "real wave 50 boss spawn selects the boss score")
	if DisplayServer.get_name() != "headless":
		var patrol: AudioStreamPlayer = sound._music[&"patrol"]
		var boss: AudioStreamPlayer = sound._music[&"boss"]
		var patrol_clip := patrol.stream as AudioStreamOggVorbis
		var boss_clip := boss.stream as AudioStreamOggVorbis
		check(patrol_clip.loop and boss_clip.loop and patrol_clip.get_length() == 60.0 and boss_clip.get_length() > 58.0, "both stereo score resources loop")
		check(patrol.playing and boss.playing and boss.bus == &"Music", "the boss score overlaps the outgoing score during the fade")
		ui.set_physics_process(false)
		await create_timer(0.75).timeout
		check(not patrol.playing and boss.playing and boss.get_playback_position() > 0.0 and boss.volume_linear > 0.5, "fade completes and boss playback advances")
		if "--visual" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			var file := ProjectSettings.globalize_path("res://reports/boss-entrance.png")
			check(root.get_texture().get_image().save_png(file) == OK, "boss entrance captured without a popup")
		var music_bus := AudioServer.get_bus_index("Music")
		var capture := AudioEffectCapture.new()
		AudioServer.add_bus_effect(music_bus, capture)
		boss.seek(boss_clip.get_length() - 0.15)
		await create_timer(0.55).timeout
		check(boss.playing and boss.get_playback_position() < 1.5, "boss playback wraps without stopping")
		var peak := 0.0
		for frame in capture.get_buffer(capture.get_frames_available()):
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		check(peak > 0.02, "the music bus receives a non-silent mix")
		AudioServer.remove_bus_effect(music_bus, AudioServer.get_bus_effect_count(music_bus) - 1)
		ui.set_physics_process(true)
	sim._apply_damage(sim.bosses[0], 9_000_000, Vector2.ZERO)
	check(sound.music_track == &"patrol" and sim.active, "boss death returns to normal music while escorts remain")
	check(ui.wave_callout == "보스 격파", "boss kill keeps a concise combat confirmation")
	sim.queued = 0
	_drain(sim)
	check(ui.modal_kind == "victory" and ui.wave_button.disabled and not ui.can_open_research(), "victory UI differs from defeat and locks play")
	check(not ui.toast.visible and ui.callout_time == 0.0, "victory dismisses prior combat notices")
	check(sound.music_track == &"", "victory fades out the battle music")
	check(profile.best == 90 and profile.campaign_record().wave == 50 and profile.campaign_record().fastest_clear > 0.0, "legacy and campaign records stay separate")
	if "--visual" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		var file := ProjectSettings.globalize_path("res://reports/campaign-victory.png")
		check(root.get_texture().get_image().save_png(file) == OK, "victory captured")
	var shorter := sim.clear_record()
	shorter.seconds = 1500.0
	shorter.health = 85
	profile.record_clear(shorter)
	profile.record_wave(17, &"normal")
	var hard_clear := shorter.duplicate(true)
	hard_clear.difficulty = "hard"
	hard_clear.seconds = 1900.0
	profile.record_clear(hard_clear)
	profile.load_profile()
	check(profile.campaign_record(&"normal").wave == 17 and profile.campaign_record(&"normal").best_clear.is_empty() and profile.campaign_record(&"hard").fastest_clear == 1900.0, "difficulty records are saved separately")
	old.load(profile.file_path)
	check(old.get_value("campaign_04", "fastest_clear") == 900.0 and old.get_value("campaign_05", "fastest_clear") == 700.0 and old.get_value("campaign_06_easy", "fastest_clear") == 600.0 and old.get_value("campaign_07_easy", "fastest_clear") == 500.0, "previous campaign record stays on disk")
	check(profile.best == 90 and profile.campaign_record().wave == 50 and profile.campaign_record().fastest_clear == 1500.0 and profile.campaign_record().best_clear.health == 100 and profile.master == 0.42, "best defense, fastest time and settings persist")
	ui.start_game()
	check(ui.battle.wave == 0 and ui.battle.credits == 50 and ui.battle.research.points == 0 and ui.battle.total_kills == 0 and ui.battle.total_installs == 0 and not ui.battle.won and profile.campaign_record().fastest_clear == 1500.0, "restart resets campaign but retains saved record")
	var retry: Battle = ui.battle
	retry.wave = 49
	retry.start_wave()
	retry.bosses[0].progress = map.length()
	retry.tick(STEP)
	check(retry.lost and sound.music_track == &"", "boss escape fades out boss music")
	ui.show_menu()
	check(sound.music_track == &"patrol", "returning from defeat restores normal music")
	ui.show_difficulty()
	for button: Button in ui.modal.find_children("*", "Button", true, false):
		if button.accessibility_name == "어려움":
			button.pressed.emit()
			break
	check(ui.battle.difficulty == &"hard" and ui.battle.wave == 0, "hard difficulty card starts a fresh hard battle")
	ui.show_pause()
	for button: Button in ui.modal.find_children("*", "Button", true, false):
		if button.text == "다시 시작":
			button.pressed.emit()
			break
	check(ui.battle.difficulty == &"hard" and ui.battle.wave == 0, "retry preserves the chosen difficulty")
	ui.queue_free()
	await process_frame
