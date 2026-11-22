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
	var bonuses := [100, 125, 150, 175, 200, 250]
	var discounts := [100, 90, 80, 70, 60, 50]
	var selected_levels := RunConstraints.new({&"credits": 3, &"tower_limit": -2, &"enemy_hp": 0}, 250)
	check(selected_levels.summary_text() == "재화 획득 · 특전 +3단계 · +75%\n타워 설치 수 · 제약 -2단계 · 최대 30기\n시작자금 · 250", "summary lists active rules and starting funds")
	check(RunConstraints.new({&"tower_limit": 5}).value(&"tower_limit") == 0, "installation cap has no positive stages")
	var ids := RunConstraints.DEFINITIONS.keys()
	for i in ids.size():
		for level in range(6):
			var selected := RunConstraints.new({ids[i]: -level})
			check(selected.value(ids[i]) == expected[i][level] and selected.active() == (level > 0),
				"%s level %d uses the expected amount" % [ids[i], level])
			var perk := RunConstraints.new({ids[i]: level})
			var expected_perk: int = bonuses[level] if i < 2 else (0 if i == 4 else discounts[level])
			check(perk.value(ids[i]) == expected_perk and perk.active() == (level > 0 and i != 4),
				"%s positive level %d uses the expected amount" % [ids[i], level])

func _economy() -> void:
	for level: int in [1, 5]:
		var sim := Battle.new(map, rules, &"easy", {&"credits": -level, &"rp": -level})
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
	var mixed := Battle.new(map, rules, &"easy", {&"credits": 5, &"rp": -2}, 250)
	check(mixed.credits == 250 and mixed.total_credits == 0 and mixed.start_wave(), "starting funds are granted independently of income")
	_drain(mixed)
	check(mixed.credits == 350 and mixed.total_credits == 100 and mixed.research.total_earned == 8, "kill and clearance credit perks coexist with an RP penalty")
	var zero_funds := Battle.new(map, rules, &"normal", {}, 0)
	check(zero_funds.credits == 0 and zero_funds.constraints.active() and zero_funds.constraints.count() == 0, "zero funds alone makes a custom run")
	var starting_rp := Battle.new(map, rules, &"easy", {&"rp": -5}, -1, 30)
	check(starting_rp.research.points == 30 and starting_rp.research.total_earned == 0 and starting_rp.credits == 50, "starting RP is separate from funds and earned RP")
	starting_rp.start_wave()
	_drain(starting_rp)
	check(starting_rp.research.points == 35 and starting_rp.research.total_earned == 5, "RP income restriction only changes subsequent earnings")

func _prices_and_limit() -> void:
	var sim := Battle.new(map, rules, &"easy", {&"tower_price": -4, &"research_price": -3, &"tower_limit": -5})
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
	var discounted := Battle.new(map, rules, &"easy", {&"tower_price": 5, &"research_price": 5, &"tower_limit": -1}, 20)
	check(discounted.research.cost(root_node) == 1 and discounted.research.minimum_cost(root_node) == 1, "research quotes and plans use the same perk")
	check(discounted.install(Vector2i(1, 2)) and discounted.credits == 15 and discounted.sell(Vector2i(1, 2)) and discounted.credits == 20, "discounted installation and refund preserve the existing rates")

func _enemies() -> void:
	var levels := {&"enemy_hp": -5, &"enemy_speed": -5, &"enemy_shield": -5, &"boss_hp": -5, &"boss_speed": -5, &"boss_shield": -5}
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
	var perks := RunConstraints.new({&"enemy_hp": 5, &"enemy_speed": 4, &"enemy_shield": 5, &"boss_hp": 5, &"boss_speed": 5, &"boss_shield": 5})
	var base_boss := rules.enemy_for_wave(rules.mobs.lookup("boss"), 50, &"easy")
	var reduced_boss := rules.enemy_for_wave(rules.mobs.lookup("boss"), 50, &"easy", perks)
	check(reduced_boss.health == roundi(base_boss.health * 0.5) and is_equal_approx(reduced_boss.speed, base_boss.speed * 0.5)
		and reduced_boss.shield == roundi(base_boss.shield * 0.5) and reduced_boss.phases[0].shield == roundi(base_boss.phases[0].shield * 0.5), "boss perks independently reduce final boss stats and phase shields")
	var base_normal := rules.enemy_for_wave(rules.mobs.lookup("normal"), 50, &"easy")
	var reduced_normal := rules.enemy_for_wave(rules.mobs.lookup("normal"), 50, &"easy", perks)
	check(reduced_normal.health == roundi(base_normal.health * 0.5) and is_equal_approx(reduced_normal.speed, base_normal.speed * 0.6)
		and reduced_normal.shield == 0, "ordinary enemy perks are independent and preserve zero shields")
	check(rules.enemy_for_wave(rules.mobs.lookup("energy"), 50, &"easy", perks).shield == roundi(energy.shield * 0.1), "enemy shield perk reduces existing native shields")
	check(rules.escort_shield(50, &"easy", perks) == roundi(rules.escort_shield(50, &"easy") * 0.5), "enemy shield perk also reduces existing escort shields")

func _zero_and_finale() -> void:
	var zeros: Dictionary = {}
	var maximum: Dictionary = {}
	for id: StringName in RunConstraints.DEFINITIONS:
		zeros[id] = 0
		maximum[id] = -5 if id == &"tower_limit" or id == &"boss_hp" else 5
	var baseline := Battle.new(map, rules, &"normal")
	var zero := Battle.new(map, rules, &"normal", zeros, 50)
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
		if button.text == "커스텀 규칙":
			button.pressed.emit()
			break
	check(ui.modal_kind == "constraints", "difficulty menu leads to constraints")
	var panel := ui.modal.get_child(0).get_child(0) as ConstraintsScreen
	check(panel._steppers.size() == 11 and panel._levels.is_empty() and panel._funds.text == "50", "picker starts at 0 for all eleven rules and 50 funds")
	panel._difficulty.select(2)
	_click(panel._steppers[&"credits"][1])
	_click(panel._steppers[&"tower_limit"][0])
	_click(panel._presets[5000])
	check(panel._effects[&"credits"].text == "특전 +1단계 · +25%" and panel._effects[&"tower_limit"].text == "제약 -1단계 · 최대 40기", "picker displays signed levels, categories and values")
	check(panel._funds.text == "5000" and panel._presets[5000].button_pressed, "recommended funds can be selected by mouse")
	_set_amount_text(panel._starting_rp, "125")
	await _capture("starting-rp-settings")
	panel._reset()
	check(panel._levels.is_empty() and panel._presets[50].button_pressed and panel._starting_rp.text == "0" and panel._steppers[&"tower_limit"][1].disabled, "reset restores neutral stages, default funds and zero starting RP")
	for invalid in ["", "-1", "1.5", "abc", "9000000000000001", "99999999999999999999999"]:
		_set_amount_text(panel._funds, invalid)
		check(panel._start_button.disabled, "invalid funds cannot start a game")
	_set_amount_text(panel._funds, "9000000000000000")
	check(not panel._start_button.disabled and panel._parse_amount(panel._funds.text) == BattleData.NUMBER_LIMIT, "the existing economy cap is a valid direct input")
	for invalid in ["", "-1", "1.5", "9000000000000001"]:
		_set_amount_text(panel._starting_rp, invalid)
		check(panel._start_button.disabled and panel._summary.text.begins_with("시작 RP"), "invalid starting RP cannot start a game")
	panel._start()
	check(not ui.game, "invalid input is rejected at game start")
	_set_amount_text(panel._funds, "1234")
	_set_amount_text(panel._starting_rp, "125")
	panel._select(&"tower_price", -5)
	panel._select(&"research_price", 2)
	panel._start()
	check(ui.game and ui.battle.difficulty == &"hard" and ui.battle.constraints.count() == 2 and ui.build_button.text.contains("20"), "selected difficulty and displayed installation cost reach the new run")
	check(ui.battle.credits == 1234 and ui.battle.research.points == 125 and ui.rp_label.text == "125" and ui.battle.research.cost(rules.research.ids[0]) == 2, "typed funds, RP and research discount reach the new run")
	var badge := ui.screen.get_node_or_null("ActiveConstraints") as Label
	check(badge != null and badge.text == "규칙 2종" and badge.tooltip_text == "타워 설치 가격 · 제약 -5단계 · +100%\n연구 비용 · 특전 +2단계 · -20%\n시작자금 · 1234\n시작 RP · 125", "HUD badge reports rules and both starting resources")
	if badge != null:
		var hover := InputEventMouseMotion.new()
		hover.position = badge.get_global_transform_with_canvas() * (badge.size * 0.5)
		root.push_input(hover, true)
		check(root.gui_get_hovered_control() == badge, "mouse reaches the constraint badge")
		if "--visual" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			root.warp_mouse(hover.position)
			await create_timer(0.85).timeout
			await _capture("custom-rules-hud")
	var profile = root.get_node("Profile")
	var entry: Dictionary = profile.campaign_record(&"hard").duplicate(true)
	ui.battle.wave = 49
	ui.start_wave()
	_drain(ui.battle)
	check(ui.modal_kind == "victory" and profile.campaign_record(&"hard") == entry, "constraint victory and wave do not modify ordinary records")
	ui.start_game(&"hard", {}, 0)
	ui.start_wave()
	badge = ui.screen.get_node_or_null("ActiveConstraints") as Label
	check(badge != null and badge.text == "시작자금" and badge.tooltip_text == "시작자금 · 0" and profile.campaign_record(&"hard") == entry, "funds-only run has a badge and does not modify the ordinary record")
	ui.start_game(&"hard", {}, 50, 125)
	ui.start_wave()
	badge = ui.screen.get_node_or_null("ActiveConstraints") as Label
	check(badge != null and badge.text == "시작 RP" and badge.tooltip_text == "시작 RP · 125" and profile.campaign_record(&"hard") == entry, "RP-only run is also separate from ordinary records")
	ui.start_game(&"hard")
	check(not ui.battle.constraints.active() and ui.build_button.text.contains("10") and ui.battle.credits == 50 and ui.battle.research.points == 0, "ordinary restart clears previous constraints and RP")
	check(not ui.screen.has_node("ActiveConstraints"), "ordinary runs omit the badge and its tooltip")

func _set_amount_text(input: LineEdit, value: String) -> void:
	input.text = value
	input.text_changed.emit(value)

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
