extends SceneTree

const STEP := 1.0 / 60.0
var checked := 0
var failures := 0
var rules := BattleData.new()
var map := FieldMap.new()

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checked += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _run() -> void:
	check(map.load_map(BattleData.read_json("res://data/sample_map.json")).is_empty(), "sample map loaded")
	_base_outputs()
	_opening()
	_core_unlock_paths()
	_lifetime()
	_networks()
	_precision_and_limits()
	await _interface()
	print("Economy checks: %d, failures: %d" % [checked, failures])
	quit(int(failures > 0))

func _fixture(levels: Dictionary = {}) -> Battle:
	var sim := Battle.new(map, rules, &"easy", levels)
	sim.roster_seed = 4150
	sim.research.earn(150_000)
	for id in rules.research.ordered:
		sim.research.purchase(id)
	sim.credits = 2_000_000
	return sim

func _place(sim: Battle, cell: Vector2i, id: String) -> Battle.Turret:
	check(sim.install(cell, id), "fixture installation %s at %s" % [id, cell])
	return sim.occupied.get(cell)

func _drain(sim: Battle) -> void:
	sim._dispatch(1000.0)
	while sim.active:
		for drone in sim.enemies:
			sim._apply_damage(drone, 1_000_000_000, Vector2.ZERO)
		sim.tick(STEP)

func _base_outputs() -> void:
	var sim := Battle.new(map, rules)
	sim.research.earn(7)
	check(not sim.install(Vector2i(2, 4), "tower_37") and not sim.research.purchase("eco_gather"), "collector requires survey and its own unlock")
	check(sim.research.purchase("survey") and sim.research.purchase("eco_gather") and sim.install(Vector2i(2, 4), "tower_37"), "first collector requires 7 RP and costs 40")
	for i in 6:
		sim = _fixture()
		var id := "tower_%02d" % (37 + i)
		var tower := _place(sim, Vector2i(2, 4), id)
		var before := sim.credits
		var attack_events: Array[String] = []
		sim.attack_visual.connect(func(style, _start, _end, _radius, _color, _life, _stage): attack_events.append(style))
		check(sim.start_wave(), "producer wave starts")
		sim.tick(0.25)
		check(sim.credits == before and sim.bolts.is_empty() and attack_events.is_empty(), "producer is passive during the wave")
		_drain(sim)
		check(Vector2i(sim.economy.last_credits, sim.economy.last_rp) == [
			Vector2i(10, 0), Vector2i(500, 0), Vector2i(14_000, 0),
			Vector2i(0, 20), Vector2i(0, 480), Vector2i(0, 5_000),
		][i], "base output " + id)
		check(sim.sell(tower.cell) and sim.credits == before + 40 + sim.economy.last_credits + int(tower.definition.refund), "base refund and paid rewards " + id)

func _lifetime() -> void:
	var sim := _fixture()
	_place(sim, Vector2i(5, 4), "tower_37")
	_place(sim, Vector2i(6, 4), "tower_37")
	check(sim.start_wave(), "wave snapshots installed producers")
	check(sim.sell(Vector2i(5, 4)), "selling a producer during combat succeeds")
	_place(sim, Vector2i(5, 4), "tower_37")
	_place(sim, Vector2i(6, 5), "tower_43")
	_place(sim, Vector2i(7, 5), "tower_45")
	check(sim.economy.links.is_empty(), "boosters placed in combat are ineligible")
	_drain(sim)
	check(sim.economy.last_credits == 10, "only the producer kept for the entire wave receives base output")
	var after := sim.credits
	sim.tick(30.0)
	sim._finish_wave()
	check(sim.credits == after, "intermission and repeated finish do not pay production")
	sim.start_wave()
	check(sim.sell(Vector2i(7, 5)), "selling the core removes its production boost")
	check(sim.economy.links.size() == 1 and sim.economy.bonuses.values() == [20, 20], "sale refreshes eligible links and bonus before payout")
	_drain(sim)
	check(sim.economy.last_credits == 24, "replacement factory becomes eligible the next wave")

func _opening() -> void:
	var sim := Battle.new(map, rules)
	for cell in [Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2), Vector2i(3, 4), Vector2i(4, 4)]:
		_place(sim, cell, TowerRegistry.BASE)
	sim.start_wave()
	_play_wave(sim)
	check(sim.wave == 1 and not sim.active and sim.health == 100 and sim.research.points >= 7, "ordinary starting build earns the collection research on wave one")
	check(sim.research.purchase("survey") and sim.research.purchase("eco_gather") and sim.install(Vector2i(5, 4), "tower_37"), "collector can be purchased before wave two at ordinary income")
	sim.start_wave()
	_play_wave(sim)
	check(sim.wave == 2 and not sim.active and sim.economy.last_credits == 10, "collector pays back its first 10 credits after real combat")

func _play_wave(sim: Battle) -> void:
	for tick in 90 * 60:
		if not sim.active:
			break
		sim.tick(STEP)

func _core_unlock_paths() -> void:
	var graph := rules.research
	for branch in [["eco_reactor", "eco_credit_amp", "eco_rp_amp"],
			["eco_quantum", "eco_rp_amp", "eco_credit_amp"]]:
		var run := ResearchRun.new(graph)
		var route: Dictionary = {}
		var total := BattleData.NUMBER_LIMIT
		for plan in graph._plans("eco_core", {}, {}):
			if not plan.has(branch[0]) or not plan.has(branch[1]) or plan.has(branch[2]):
				continue
			var cost := 0
			for id: String in plan:
				cost += run.cost(id)
			if cost < total:
				total = cost
				route = plan
		check(not route.is_empty(), "industrial core has an independent route through " + branch[0])
		if route.is_empty():
			continue
		run.earn(total)
		for id: String in graph.ordered:
			if route.has(id) and id != "eco_core" and id != branch[1]:
				check(run.purchase(id), "purchase prerequisite " + id)
		check(not run.purchase("eco_core"), "top producer still needs its matching amplifier")
		check(run.purchase(branch[1]) and run.purchase("eco_core") and run.unlocked.has("tower_45")
			and not run.completed.has(branch[2]) and run.points == 0, "one complete branch unlocks the core at exact cost")

func _network(sim: Battle, production_ids: Array[String] = []) -> Battle.Turret:
	var core := _place(sim, Vector2i(5, 4), "tower_45")
	_place(sim, Vector2i(6, 4), "tower_43")
	_place(sim, Vector2i(7, 4), "tower_43")
	_place(sim, Vector2i(5, 5), "tower_44")
	_place(sim, Vector2i(6, 5), "tower_44")
	_place(sim, Vector2i(7, 5), "tower_36")
	var i := 0
	for cell in [Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 6), Vector2i(6, 6),
			Vector2i(7, 6), Vector2i(8, 6), Vector2i(2, 4), Vector2i(2, 5),
			Vector2i(3, 5), Vector2i(4, 5)]:
		var id := ("tower_37" if i < 8 else "tower_40") if production_ids.is_empty() else production_ids[i]
		_place(sim, cell, id)
		i += 1
	return core

func _networks() -> void:
	var bonuses := [0, 12, 16, 20, 24, 30, 30]
	for pair in [[0, 0], [1, 1], [2, 3], [3, 5], [4, 7], [5, 10], [6, 15]]:
		check(TowerEconomy.core_bonus(pair[1]) == bonuses[pair[0]], "core bonus for %d connections" % pair[1])
	var sim := _fixture({&"credits": 1, &"rp": -1})
	var core := _network(sim)
	check(sim.economy.connected(core).size() == 10 and sim.support.followers(sim.occupied[Vector2i(7, 5)]).is_empty(), "core counts ten producers and combat command ignores them")
	check(sim.economy.bonuses.values().count(50) == 10, "same-kind boosts do not stack; different kinds add to 50%")
	var credits_amp: Battle.Turret = sim.occupied[Vector2i(6, 4)]
	var rp_amp: Battle.Turret = sim.occupied[Vector2i(5, 5)]
	check(sim.economy.connected(credits_amp).size() == 8 and sim.economy.connected(rp_amp).size() == 2, "dedicated bonuses match the resource type")
	sim.start_wave()
	_drain(sim)
	check(sim.economy.last_credits == 150 and sim.economy.last_rp == 54, "custom award multipliers apply independently after the +50% cap")
	sim.start_wave()
	sim.sell(Vector2i(3, 4))
	check(sim.economy.connected(core).size() == 9 and sim.economy.bonuses.values().count(48) == 9, "selling one producer decreases the remaining core bonuses during its wave")

	sim = _fixture()
	var stronger := _place(sim, Vector2i(3, 11), "tower_45")
	var weaker := _place(sim, Vector2i(12, 11), "tower_45")
	_place(sim, Vector2i(1, 11), "tower_37")
	_place(sim, Vector2i(2, 11), "tower_37")
	var shared := _place(sim, Vector2i(7, 11), "tower_40")
	_place(sim, Vector2i(17, 11), "tower_40")
	check(sim.economy.connected(stronger).size() == 3 and sim.economy.connected(weaker).size() == 2, "cores count their own true range")
	check(sim.economy.bonuses[shared] == 16 and sim.economy.providers[shared]["core"][0] == stronger, "overlapping cores use only the strongest")
	sim.sell(stronger.cell)
	check(sim.economy.bonuses[shared] == 14 and sim.economy.providers[shared]["core"][0] == weaker, "sale replaces the strongest core with the next valid source")

	sim = _fixture()
	_network(sim, [
		"tower_39", "tower_39", "tower_39", "tower_38", "tower_38",
		"tower_42", "tower_42", "tower_41", "tower_41", "tower_40",
	])
	sim.start_wave()
	_drain(sim)
	check(sim.economy.last_credits == 64_500 and sim.economy.last_rp == 16_470,
		"mature complex pays both resources at the shared +50% cap")

func _precision_and_limits() -> void:
	var levels := {&"credits": 2, &"tower_price": 5, &"tower_limit": -5}
	var sim := _fixture(levels)
	var baseline := _fixture(levels)
	var producer := _place(sim, Vector2i(5, 4), "tower_37")
	var core := _place(sim, Vector2i(6, 4), "tower_45")
	check(producer.definition.cost == 20 and core.definition.cost == 22_500, "custom prices cover producers and boosters")
	var starting_difference := baseline.credits - sim.credits
	for i in 5:
		sim.start_wave()
		baseline.start_wave()
		_drain(sim)
		_drain(baseline)
	check(sim.credits - baseline.credits + starting_difference == 84, "five 16.8-credit payments carry fractions without repeated rounding")
	for x in range(1, 11):
		_place(sim, Vector2i(x, 2), "tower_37")
	check(sim.at_tower_limit() and not sim.install(Vector2i(12, 2), "tower_44"), "producers and boosters occupy the shared limit")

func _interface() -> void:
	var profile = root.get_node("Profile")
	profile.fx_quality = 3
	profile.fx_particles = 0.80
	var ui = (load("res://scenes/Front.tscn") as PackedScene).instantiate()
	root.add_child(ui)
	ui.start_game()
	var sim: Battle = ui.battle
	sim.research.earn(150_000)
	for id in sim.data.research.ordered:
		sim.research.purchase(id)
	sim.credits = 2_000_000
	var core := _network(sim)
	ui.selected = core.cell
	ui._sync_selection()
	check(ui.tower_stats.text.contains("연결 10기") and ui.tower_stats.text.contains("+30%"), "selecting core shows live connection count and strength")
	ui.show_catalog(true)
	await process_frame
	var categories: Array[String] = []
	for label: Label in ui.modal.find_children("*", "Label", true, false):
		if label.text in ["공격 타워", "버프 타워", "경제 타워"]:
			categories.append(label.text)
	check(categories == ["공격 타워", "버프 타워", "경제 타워"], "desktop catalog puts economy below combat support")
	ui.close_modal()
	sim.start_wave()
	_drain(sim)
	check(ui.wave_callout.contains("생산 완료") and ui.wave_callout.contains("RP"), "production credit and RP appear in the combat HUD")
	if "--visual" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		check(ui.field.economy_fx._pulses.size() == 13, "production renderer receives ten producers and the three effective boosters")
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://reports/economy-towers.png") == OK, "economy effects captured")
