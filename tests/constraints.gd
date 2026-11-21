extends SceneTree

const STEP := 1.0 / 60.0
var rules := BattleData.new()
var map := FieldMap.new()
var checked := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checked += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _run() -> void:
	check(map.load_map(BattleData.read_json("res://data/sample_map.json")).is_empty(), "map loaded")
	_levels()
	_economy()
	_prices_and_limit()
	_enemies()
	_zero_and_finale()
	await _interface()
	print("Constraint checks: %d, failures: %d" % [checked, failures])
	quit(int(failures > 0))

func _levels() -> void:
	var expected := [
		[100, 90, 80, 70, 60, 50], [100, 90, 80, 70, 60, 50],
		[100, 120, 140, 160, 180, 200], [100, 120, 140, 160, 180, 200], [0, 40, 30, 25, 20, 12],
		[100, 125, 150, 200, 300, 500], [100, 110, 120, 135, 150, 175], [100, 125, 150, 200, 300, 500],
		[100, 150, 200, 300, 400, 600], [100, 110, 120, 135, 150, 175], [100, 150, 200, 300, 400, 600],
	]
	check(RunConstraints.DEFINITIONS.size() == expected.size(), "exactly eleven constraints")
	var selected_levels := RunConstraints.new({&"credits": 3, &"tower_limit": 2, &"enemy_hp": 0})
	check(selected_levels.summary_text() == "재화 감소 3단계 · -30%\n설치 수 제한 2단계 · 30기", "summary lists only active levels and formats percentages and limits")
	var ids := RunConstraints.DEFINITIONS.keys()
	for i in ids.size():
		for level in range(6):
			var selected := RunConstraints.new({ids[i]: level})
			check(selected.value(ids[i]) == expected[i][level] and selected.active() == (level > 0),
				"%s level %d uses the expected amount" % [ids[i], level])

func _economy() -> void:
	for level: int in [1, 5]:
		var sim := Battle.new(map, rules, &"easy", {&"credits": level, &"rp": level})
		check(sim.credits == 50 and sim.start_wave(), "income reductions preserve 50 starting credits and permit play")
		var awards: Array[int] = []
		sim.wave_finished.connect(func(_wave: int, amount: int): awards.append(amount))
		_drain(sim)
		var multiplier := 1.0 - 0.1 * level
		check(sim.credits == 50 + roundi(40 * multiplier) and sim.total_credits == roundi(40 * multiplier), "reduced kills and wave reward use cumulative fractions")
		check(awards == [roundi(10 * multiplier)] and sim.research.total_earned == roundi(10 * multiplier), "wave signal and awarded RP report paid amounts")
		var wallet := sim.credits
		sim.install(Vector2i(1, 2))
		sim.sell(Vector2i(1, 2))
		check(sim.credits == wallet, "income penalty does not apply to sale proceeds")

func _prices_and_limit() -> void:
	var sim := Battle.new(map, rules, &"easy", {&"tower_price": 4, &"research_price": 3, &"tower_limit": 5})
	var core := sim.tower_definition(TowerRegistry.BASE)
	var rapid := sim.tower_definition("tower_02")
	check(core.cost == 18 and core.refund == 18 and rapid.cost == 99 and rapid.refund == 74, "price inflation preserves base refund ratios")
	var root_node: String = rules.research.ids[0]
	var cost := roundi(float(rules.research.nodes[root_node].cost_rp) * 1.6)
	sim.research.earn(cost - 1)
	check(sim.research.minimum_cost(root_node) == cost and not sim.research.purchase(root_node), "inflated quote governs research eligibility")
	sim.research.earn(1)
	check(sim.research.purchase(root_node) and sim.research.points == 0, "purchase deducts the same per-node cost")
	var target: String = rules.research.unlocks["tower_30"]
	var plans := rules.research._plans(target, sim.research.completed, {})
	var best := BattleData.NUMBER_LIMIT
	for plan in plans:
		var total := 0
		for id in plan:
			total += roundi(float(rules.research.nodes[id].cost_rp) * 1.6)
		best = mini(total, best)
	check(sim.research.minimum_cost(target) == best, "minimum path adds each independently rounded price once")

	sim.credits = 100_000
	sim.research.earn(200_000)
	for id in rules.research.ordered:
		sim.research.purchase(id)
	check(sim.install(Vector2i(1, 2), "tower_31"), "support tower occupies a slot")
	for cell in _open_tiles(13).slice(1, 12):
		check(sim.install(cell), "can install before the limit")
	var extra := _open_tiles(13)[12]
	check(sim.towers.size() == 12 and sim.at_tower_limit() and sim.placement_status(extra, TowerRegistry.BASE) == Battle.Placement.LIMIT and not sim.install(extra), "support and attack towers share the cap")
	check(sim.sell(Vector2i(1, 2)) and sim.install(extra), "selling frees an installation slot")
	var normal := Battle.new(map, rules)
	check(normal.tower_limit() == 0 and normal.tower_definition(TowerRegistry.BASE).cost == 10, "new run sees original values")

func _enemies() -> void:
	var levels := {&"enemy_hp": 5, &"enemy_speed": 5, &"enemy_shield": 5, &"boss_hp": 5, &"boss_speed": 5, &"boss_shield": 5}
	var sim := Battle.new(map, rules, &"easy", levels)
	sim.wave = 49
	check(sim.start_wave(), "all combat constraints permit the finale to spawn")
	var boss := sim.bosses[0]
	check(boss.health == 48_000_000 and boss.shield_hp == 969_000 and is_equal_approx(boss.speed, 0.21), "boss receives only boss HP, shield and speed multipliers")
	var next_phase: Dictionary = boss.mob.phases[0]
	check(int(next_phase.shield) == 1_311_000 and boss.mob.regen.amount == 552, "phase shields scale with the boss shield modifier and base regeneration stays consistent")
	var original := rules.enemy_for_wave(rules.mobs.lookup("normal"), 50, &"easy")
	var regular: Dictionary = sim._wave_enemy(rules.mobs.lookup("normal"))
	check(regular.health == original.health * 5 and is_equal_approx(regular.speed, original.speed * 1.75) and regular.shield == 0, "regular enemies multiply existing difficulty and gain no new shields")
	original = rules.enemy_for_wave(rules.mobs.lookup("energy"), 50, &"easy")
	var energy: Dictionary = sim._wave_enemy(rules.mobs.lookup("energy"))
	check(energy.shield == original.shield * 5, "native shields scale once")
	var accelerating: Dictionary = sim._wave_enemy(rules.mobs.lookup("accelerate"))
	original = rules.enemy_for_wave(rules.mobs.lookup("accelerate"), 50, &"easy")
	check(is_equal_approx(accelerating.acceleration.max_speed, original.acceleration.max_speed * 1.75), "acceleration cap follows the enemy speed modifier")
	sim._dispatch(900.0)
	var escorted := false
	for enemy in sim.enemies:
		if enemy.shield_source == Battle.ESCORT_SHIELD_SOURCE:
			escorted = enemy.shield_hp == 285_000
			break
	check(escorted, "existing escort shields scale once")
	var unit_sim := Battle.new(map, rules, &"easy", levels)
	unit_sim.wave = 20
	var guard := unit_sim.spawn(8.0, unit_sim._wave_enemy(rules.mobs.lookup("guardian")))
	var ally := unit_sim.spawn(8.5, unit_sim._wave_enemy(rules.mobs.lookup("normal")))
	unit_sim.apply_support(guard, guard.mob.guardian, true)
	check(ally.shield_hp == 4_250, "existing guardian shield grants scale once")

func _zero_and_finale() -> void:
	var zeros: Dictionary = {}
	var maximum: Dictionary = {}
	for id: StringName in RunConstraints.DEFINITIONS:
		zeros[id] = 0
		maximum[id] = 5
	var baseline := Battle.new(map, rules, &"normal")
	var zero := Battle.new(map, rules, &"normal", zeros)
	baseline.roster_seed = 7043
	zero.roster_seed = 7043
	check(not zero.constraints.active(), "all zeros use ordinary run mode")
	for wave in [1, 12, 42, 50]:
		for sim: Battle in [baseline, zero]:
			sim.wave = wave - 1
			sim.start_wave()
			_drain(sim)
			sim.won = false
		check(baseline.credits == zero.credits and baseline.research.total_earned == zero.research.total_earned and baseline.total_kills == zero.total_kills, "zero mode matches ordinary rewards and composition at wave %d" % wave)
	var stress := Battle.new(map, rules, &"hard", maximum)
	for wave in range(1, BattleData.FINAL_WAVE + 1):
		check(stress.start_wave() and stress.wave == wave, "all eleven modifiers start wave %d" % wave)
		_drain(stress)
		check(not stress.active and not stress.lost and stress.queued == 0 and stress.primary_spawned == rules.wave_count(wave), "all original slots and descendants resolved at wave %d" % wave)
	check(stress.won and stress.boss_killed and not stress.start_wave(), "all eleven modifiers coexist through the victory gate")
	check(stress.health == 100 and stress.clear_record().research == 0, "stress fixture never changes locked research or leaks to base")

func _drain(sim: Battle) -> void:
	sim._dispatch(2000.0)
	while sim.active:
		for drone in sim.enemies:
			sim._apply_damage(drone, 1_000_000_000, Vector2.ZERO)
		sim.tick(STEP)

func _open_tiles(count: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = [Vector2i(1, 2)]
	for x in map.size.x:
		for y in map.size.y:
			var tile := Vector2i(x, y)
			if map.tile_at(tile) == "." and tile != tiles[0]:
				tiles.append(tile)
			if tiles.size() == count:
				return tiles
	return tiles

func _interface() -> void:
	var ui = (load("res://scenes/Front.tscn") as PackedScene).instantiate()
	root.add_child(ui)
	ui.show_difficulty()
	await process_frame
	for button: Button in ui.modal.find_children("*", "Button", true, false):
		if button.text == "제약 모드":
			button.pressed.emit()
			break
	check(ui.modal_kind == "constraints", "difficulty menu leads to constraints")
	var panel := ui.modal.get_child(0).get_child(0) as ConstraintsScreen
	check(panel._buttons.size() == 11 and not panel._levels.size(), "picker starts at 0 for all eleven constraints")
	panel._difficulty.select(2)
	_click(panel._buttons[&"credits"][5])
	_click(panel._buttons[&"tower_limit"][5])
	check(panel._effects[&"credits"].text == "-50%" and panel._effects[&"tower_limit"].text == "12기", "picker shows applied values")
	await _capture("constraints-settings")
	panel._reset()
	check(panel._levels.is_empty() and panel._buttons[&"credits"][0].button_pressed and not panel._buttons[&"credits"][5].button_pressed, "reset restores all settings visibly")
	panel._buttons[&"tower_price"][5].pressed.emit()
	panel._buttons[&"research_price"][2].pressed.emit()
	panel._start()
	check(ui.game and ui.battle.difficulty == &"hard" and ui.battle.constraints.count() == 2 and ui.build_button.text.contains("20"), "selected difficulty and displayed installation cost reach the new run")
	var badge := ui.screen.get_node_or_null("ActiveConstraints") as Label
	check(badge != null and badge.text == "제약 2종" and badge.tooltip_text == "물가 폭등 5단계 · +100%\n연구 비용 폭등 2단계 · +40%", "HUD badge reports the selected run constraints")
	if badge != null:
		var hover := InputEventMouseMotion.new()
		hover.position = badge.get_global_transform_with_canvas() * (badge.size * 0.5)
		root.push_input(hover, true)
		check(root.gui_get_hovered_control() == badge, "mouse reaches the constraint badge")
		if "--visual" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			root.warp_mouse(hover.position)
			await create_timer(0.85).timeout
			await _capture("constraints-hud-tooltip")
	var profile = root.get_node("Profile")
	var entry: Dictionary = profile.campaign_record(&"hard").duplicate(true)
	ui.battle.wave = 49
	ui.start_wave()
	_drain(ui.battle)
	check(ui.modal_kind == "victory" and profile.campaign_record(&"hard") == entry, "constraint victory and wave do not modify ordinary records")
	ui.start_game(&"hard")
	check(not ui.battle.constraints.active() and ui.build_button.text.contains("10") and ui.battle.credits == 50, "ordinary restart clears previous constraints")
	check(not ui.screen.has_node("ActiveConstraints"), "ordinary runs omit the badge and its tooltip")

func _click(button: Button) -> void:
	var point := button.get_global_transform_with_canvas() * (button.size * 0.5)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		root.push_input(click, true)

func _capture(filename: String) -> void:
	if "--visual" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://reports/" + filename + ".png") == OK, "captured settings")
