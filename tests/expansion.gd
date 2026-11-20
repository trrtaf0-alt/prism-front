extends SceneTree

const STEP := 1.0 / 60.0
var rules := BattleData.new()
var map := FieldMap.new()
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _run() -> void:
	check(map.load_map(BattleData.read_json("res://data/sample_map.json")).is_empty(), "sample field loads")
	check(rules.towers.error.is_empty() and rules.research.error.is_empty(), "definitions validate: " + rules.research.error)
	if not rules.research.error.is_empty():
		quit(1)
		return
	_research()
	_status_and_economy()
	_all_towers()
	_tower_art()
	_attack_details()
	_projectile_behaviors()
	await _interface()
	print("Expansion checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _tower_art() -> void:
	var atlas := TowerArt.ATLAS.get_image()
	var frames := {}
	for id in rules.towers.ids:
		var first := TowerArt.first_frame(id)
		for frame in [first, first + 1]:
			var texture := TowerArt.icon(frame)
			var art := atlas.get_region(Rect2i(texture.region))
			check(not frames.has(frame) and art.get_used_rect().has_area(),
				"id %s has a filled, unique art layer %d" % [id, frame])
			frames[frame] = true

func _research() -> void:
	var graph := rules.research
	check(graph.ids.size() == 100 and graph.ordered.size() == 100, "100 unique reachable nodes")
	check(graph.unlocks.size() == 29 and graph.ids.size() - graph.unlocks.size() == 71 and rules.towers.ids.size() == 30, "29 unlocks, 71 junctions and 30 towers")
	var distribution := [Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO]
	for id in graph.ids:
		var node: Dictionary = graph.nodes[id]
		distribution[int(node.stage)] += Vector2i(1, int(node.has("unlock")))
		check(node.has("unlock") or not graph.children[id].is_empty(), "junction opens a detectable route: " + id)
	check(distribution == [Vector2i(6, 0), Vector2i(14, 4), Vector2i(24, 7), Vector2i(26, 8), Vector2i(20, 7), Vector2i(10, 3)], "tier distribution")
	var nested := {"all": [{"any": ["a", {"all": ["b", "c"]}]}, "d"]}
	check(not ResearchGraph.satisfied(nested, {"a": true}) and not ResearchGraph.satisfied(nested, {"b": true, "d": true}), "AND and nested conditions reject incomplete plans")
	check(ResearchGraph.satisfied(nested, {"a": true, "d": true}) and ResearchGraph.satisfied(nested, {"b": true, "c": true, "d": true}), "either nested OR path works")
	var run := ResearchRun.new(graph)
	check(not run.purchase("survey") and run.state("survey") == &"insufficient", "RP guard")
	run.earn(150_000)
	check(not run.purchase("cataclysm") and run.state("cataclysm") == &"locked", "prerequisite guard")
	check(run.purchase("survey") and not run.purchase("survey"), "one purchase only")
	check(run.completed.size() == 1 and run.unlocked.size() == 1, "no automatic unlock or completion")
	var full_cost := 0
	for id in graph.ordered:
		full_cost += int(graph.nodes[id].cost_rp)
		if id != "survey":
			check(run.purchase(id), "can purchase " + id)
	check(run.completed.size() == 100 and run.unlocked.size() == 30 and run.points == 150_000 - full_cost, "all independent branches are obtainable in one run")
	for pair: Array in [["singularity", 20000], ["spectrum", 30000], ["cataclysm", 45000]]:
		var cost := graph.minimum_cost(pair[0])
		check(cost == pair[1], "minimum unique RP cost for %s = %d" % [pair[0], cost])
	check(graph.minimum_cost("cataclysm", run.completed) == 0, "completed shared prerequisites not billed")
	check(full_cost == 48680, "full web campaign cost")
	var raw: Array = BattleData.read_json("res://data/research.json").nodes
	_bad_graph(raw, "survey", "survey", "self reference")
	_bad_graph(raw, "survey", "imaginary", "missing reference")
	_bad_graph(raw, "survey", "rifling", "cycle")
	_bad_graph(raw, "pierce", null, "orphan upper research")
	_bad_graph(raw, "pierce", {"all": []}, "empty condition")
	var duplicated := raw.duplicate(true)
	duplicated.append(raw[0])
	check(not ResearchGraph.new(duplicated, rules.towers).error.is_empty(), "duplicate research ID")
	var wrong_unlock := raw.duplicate(true)
	for node: Dictionary in wrong_unlock:
		if node.id == "rapid":
			node.unlock.id = "tower_999"
	check(not ResearchGraph.new(wrong_unlock, rules.towers).error.is_empty(), "unknown tower unlock")
	for node: Dictionary in wrong_unlock:
		if node.id == "rapid":
			node.unlock.id = "tower_03"
	check(not ResearchGraph.new(wrong_unlock, rules.towers).error.is_empty(), "duplicate tower unlock")

func _bad_graph(raw: Array, target: String, req: Variant, desc: String) -> void:
	var entries := raw.duplicate(true)
	for entry: Dictionary in entries:
		if entry.id == target:
			entry.requirements = req
	check(not ResearchGraph.new(entries, rules.towers).error.is_empty(), desc)

func _new_battle() -> Battle:
	return Battle.new(map, rules)

func _unlock(sim: Battle) -> void:
	sim.research.earn(150_000)
	for id in rules.research.ordered:
		sim.research.purchase(id)
	sim.credits = 5_000_000

func _status_and_economy() -> void:
	var sim := _new_battle()
	var tough := rules.drone.duplicate()
	tough.reward = 11
	tough.reward_rp = 8
	var alpha := sim.spawn(1.0)
	var beta := sim.spawn(1.2, tough)
	for i in 5:
		sim._damage_drone(alpha, Vector2.UP)
		sim._damage_drone(beta, Vector2.UP)
	check(sim.credits == 64 and sim.research.points == 9, "separate currency and enemy-specific rewards")
	var stun := StatusEffects.new()
	stun.shock(rules.status_rules)
	check(is_equal_approx(stun.stun_left, 0.2), "initial stun duration")
	var moved := 0.0
	for i in 120:
		moved += stun.step(moved, 1.0, STEP, rules.status_rules)
		stun.shock(rules.status_rules)
	check(moved > 0.5 and stun.resistance > 5.0, "continuous shock still permits movement")
	var resistance := stun.resistance
	for i in 600:
		stun.step(2.0, 1.0, STEP, rules.status_rules)
	check(stun.resistance < resistance, "shock resistance recovers")
	for i in 1000:
		stun.step(2.0, 1.0, STEP, rules.status_rules)
	stun.shock(rules.status_rules)
	check(is_equal_approx(stun.stun_left, 0.2), "recovered hit restores original duration")
	sim.tick(STEP)
	var pooled := sim.spawn(3.0)
	check(pooled.status.resistance == 0.0 and pooled.status.stun_left == 0.0 and pooled.status.mark_stacks == 0, "pooled enemy resets effects")

func _all_towers() -> void:
	var armored := rules.drone.duplicate()
	armored.health = 50_000
	for id in rules.towers.ids:
		var sim := _new_battle()
		sim.credits = 1_000_000
		var cell := Vector2i(2, 4)
		if id != TowerRegistry.BASE:
			check(not sim.install(cell, id), "locked tower blocked " + id)
			_unlock(sim)
		var def := rules.towers.lookup(id)
		var before := sim.credits
		check(sim.install(cell, id) and sim.credits == before - int(def.cost), "install and exact price " + id)
		var fixture: Array[Battle.Drone] = []
		for i in 11:
			fixture.append(sim.spawn(1.5 + i * 0.11, armored))
		if def.attack == "copy":
			sim.install(Vector2i(3, 4), "tower_09")
			sim.install(Vector2i(3, 5), "tower_27")
		var fx: Array[String] = []
		sim.attack_visual.connect(func(style, _a, _b, _c, _d, _e, _f): fx.append(style))
		for i in 262:
			sim.tick(STEP)
		var damage := 0
		var marked := false
		for drone in fixture:
			damage += int(armored.health) - drone.health
			marked = marked or drone.status.mark_stacks > 0
		check(marked if def.attack == "mark" else damage > 0, "real hit or mark from " + id)
		if id != TowerRegistry.BASE:
			check(not fx.is_empty(), "attack sends visual events " + id)
		if def.attack == "copy":
			check(fx.has("holo") and sim._copy_neighbors[sim.occupied[cell]].size() == 1, "copy emits and ignores other copies")
		var cash := sim.credits
		check(sim.sell(cell) and sim.credits == cash + int(def.refund), "refund " + id)

func _attack_details() -> void:
	var armored := rules.drone.duplicate()
	armored.health = 1_000_000
	var sim := _new_battle()
	_unlock(sim)
	var fixture: Array[Battle.Drone] = []
	for i in 330:
		fixture.append(sim.spawn(1.0 + i * 0.10, armored))
	sim.install(Vector2i(2, 4), "tower_23")
	sim.tick(STEP)
	var touched := 0
	for drone in fixture:
		touched += int(drone.health == 999969 and drone.status.stun_left > 0.0)
	check(touched == 300, "storm targets exactly 300 globally and applies shock")
	sim = _new_battle()
	_unlock(sim)
	sim.install(Vector2i(2, 4), "tower_30")
	var far := sim.spawn(50.0, armored)
	for i in 211:
		sim.tick(STEP)
	check(far.health == 995000, "cataclysm lands 5000 at remote location after windup")
	sim = _new_battle()
	_unlock(sim)
	var cat_site := Vector2i(2, 4)
	var copy_site := Vector2i(3, 4)
	sim.install(cat_site, "tower_30")
	sim.install(copy_site, "tower_27")
	far = sim.spawn(50.0, armored)
	for i in 211:
		sim.tick(STEP)
	check(far.health == 994250, "mirrored cataclysm applies its per-weapon 15 percent rate")
	check(is_equal_approx(sim.occupied[copy_site].mirror_timers[sim.occupied[cat_site]], 46.5), "mirrored cataclysm uses a 50 second cadence")
	sim = _new_battle()
	_unlock(sim)
	sim.install(Vector2i(2, 4), "tower_28")
	var near := sim.spawn(5.0, armored)
	far = sim.spawn(50.0, armored)
	for i in 254:
		sim.tick(STEP)
	check(near.health == 998000 and far.health == 998000, "singularity delivers 20 global damage ticks")
	check(far.position.is_equal_approx(map.position_at(far.progress)) and absf(far.progress - 50.0) < 16.0, "gravity keeps exact path coordinates")
	sim = _new_battle()
	_unlock(sim)
	sim.install(Vector2i(2, 4), "tower_29")
	var distant: Array[Battle.Drone] = []
	for i in 1000:
		distant.append(sim.spawn(1.0 + i * 0.05, armored))
	sim.tick(STEP)
	var struck := 0
	for drone in distant:
		struck += int(drone.health == 999920)
	check(struck == 1000, "spectrum hits 1000 enemies despite sampled visuals")

func _projectile_behaviors() -> void:
	var stationary := rules.drone.duplicate()
	stationary.health = 1000
	stationary.speed = 0.0
	var sim := _new_battle()
	_unlock(sim)
	var cell := Vector2i(9, 2)
	sim.install(cell, "tower_03")
	var row: Array[Battle.Drone] = []
	for i in 11:
		row.append(sim.spawn(9.1 + i * 0.22, stationary))
	sim.tick(STEP)
	var touched := 0
	for drone in row:
		touched += int(drone.health == 997)
	check(touched == 8, "piercing line damages exactly eight in order")
	sim = _new_battle()
	_unlock(sim)
	sim.install(cell, "tower_17")
	var target := sim.spawn(10, stationary)
	sim.tick(STEP)
	sim.occupied[cell].cooldown = 9.0
	for i in 85:
		sim.tick(STEP)
	check(target.health == 976, "returning bolt hits once in each direction")
	sim = _new_battle()
	_unlock(sim)
	sim.install(cell, "tower_16")
	target = sim.spawn(10, stationary)
	sim.tick(STEP)
	sim.occupied[cell].cooldown = 9.0
	var shards := 0
	for i in 12:
		sim.tick(STEP)
		shards = maxi(shards, sim.bolts.size())
	check(target.health == 985 and shards == 16, "split bolt spawns sixteen real secondary bolts")
	sim = _new_battle()
	_unlock(sim)
	var launcher := Vector2i(3, 4)
	sim.install(launcher, "tower_12")
	target = sim.spawn(8.92)
	var neighbor := sim.spawn(9.3)
	var outlier := sim.spawn(10.4)
	outlier.health = 100
	sim.tick(STEP)
	var bolt := sim.bolts[0]
	var heading := bolt.direction
	for i in 7:
		sim.tick(STEP)
	check(not bolt.direction.is_equal_approx(heading), "homing missile updates heading")
	for i in 35:
		sim.tick(STEP)
	check(not sim.enemies.has(target) and not sim.enemies.has(neighbor) and outlier.health < 100, "missile blast hits nearby enemies")
	sim = _new_battle()
	_unlock(sim)
	sim.install(Vector2i(2, 4), "tower_25")
	row.clear()
	for i in 90:
		row.append(sim.spawn(1.1 + i * 0.47, stationary))
	sim.tick(STEP)
	touched = 0
	for drone in row:
		touched += int(drone.health == 952)
	check(touched == 64, "photon cap counts hits instead of visible beams")

func _interface() -> void:
	var packed := load("res://scenes/Front.tscn") as PackedScene
	var ui = packed.instantiate()
	root.add_child(ui)
	await process_frame
	ui.start_game()
	var sim: Battle = ui.battle
	var original_best: int = root.get_node("Profile").best
	check(ui.rp_label.text == "0" and ui.catalog_button.text == "목록 1", "HUD fresh research economy")
	sim.start_wave()
	var first := sim.enemies[0]
	var progress := first.progress
	_click(ui, Vector2(1694, 922))
	check(ui.modal_kind == "research", "research opens from the HUD midwave")
	if ui.modal_kind != "research":
		ui.queue_free()
		return
	ui._physics_process(STEP)
	check(first.progress == progress and ui.field.frozen, "opening research pauses combat by default")
	check(ui.research_screen.board._states.size() == 100, "board contains all nodes")
	var board: ResearchBoard = ui.research_screen.board
	board.overview()
	check(board.bounds.size.x * board.zoom < board.size.x, "research overview fits full network")
	board.jump(5)
	check(board.focus_id == "event_horizon", "jump to terminal zone")
	var start := board.offset
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_MIDDLE
	down.pressed = true
	down.position = Vector2(550, 300)
	board._gui_input(down)
	var move := InputEventMouseMotion.new()
	move.position = Vector2(616, 351)
	move.relative = Vector2(66, 51)
	board._gui_input(move)
	down.pressed = false
	board._gui_input(down)
	check(board.offset != start, "research board pans on drag")
	var old_zoom := board.zoom
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = Vector2(550, 300)
	board._gui_input(wheel)
	check(board.zoom > old_zoom, "research board zooms with scroll wheel")
	board.overview()
	await _capture("research-overview")
	board.select_node("cataclysm", true)
	check(board.highlighted.size() > 75 and ui.research_screen.buy.disabled, "terminal path and locked condition display")
	await _capture("research-network")
	sim.research.earn(100)
	board.select_node("survey", true)
	await process_frame
	_click(ui, Vector2(1642, 900))
	check(sim.research.completed.has("survey") and sim.research.points == 98, "research button completes and debits selected node")
	for id in ["motion", "bus", "heat", "feed", "rapid"]:
		sim.research.purchase(id)
	check(ui.catalog_button.text == "목록 2", "unlocked tower count refreshes immediately")
	ui.close_modal()
	ui._physics_process(STEP)
	check(first.progress > progress, "closing research resumes same combat")
	_click(ui, ui.catalog_button.get_rect().get_center())
	check(ui.modal_kind == "catalog", "catalog opens from HUD")
	await _capture("tower-catalog")
	sim.credits = 200
	ui._choose_tower("tower_02")
	_click(ui, FieldView.pixel(Vector2(2.5, 4.5)))
	check(sim.occupied.has(Vector2i(2, 4)) and sim.occupied[Vector2i(2, 4)].definition.id == "tower_02", "selected researched tower installs at tile")
	ui.start_game()
	check(ui.battle.research.points == 0 and ui.battle.research.completed.is_empty() and ui.battle.research.unlocked.size() == 1 and ui.research_view.is_empty(), "new game resets the entire research run")
	check(root.get_node("Profile").best >= original_best, "new game preserves highest wave")
	var policy: Dictionary = ui.data.balance
	ui.battle.start_wave()
	policy.research_available_during_wave = false
	ui.show_research()
	check(ui.modal == null, "research availability policy can block active waves")
	policy.research_available_during_wave = true
	policy.research_pauses_battle = false
	ui.show_research()
	var advancing: Battle.Drone = ui.battle.enemies[0]
	var current := advancing.progress
	ui._physics_process(STEP)
	check(ui.modal_kind == "research" and not ui.field.frozen and advancing.progress > current, "live research policy advances battle")
	ui.close_modal()
	policy.research_pauses_battle = true
	var profile = root.get_node("Profile")
	profile.file_path = "user://expansion_test_profile.cfg"
	profile.fx_quality = 0
	profile.fx_particles = 0.13
	profile.fx_flash = 0.24
	profile.fx_shake = 0.36
	profile.fx_dim = true
	profile.save_profile()
	profile.fx_quality = 2
	profile.fx_dim = false
	profile.load_profile()
	check(profile.fx_quality == 0 and is_equal_approx(profile.fx_particles, 0.13) and is_equal_approx(profile.fx_flash, 0.24) and is_equal_approx(profile.fx_shake, 0.36) and profile.fx_dim, "all visual options persist")
	profile.fx_quality = 2
	profile.fx_dim = false
	profile.fx_particles = 0.85
	ui.show_settings("pause_settings")
	ui.show_effect_settings()
	await _capture("effect-settings")
	ui.close_modal()
	if "--visual" in OS.get_cmdline_user_args():
		await _visual_preview(ui)
	ui.queue_free()
	await process_frame

func _visual_preview(ui) -> void:
	var sim: Battle = ui.battle
	var heavy := rules.drone.duplicate()
	heavy.health = 50000
	_unlock(sim)
	sim.install(Vector2i(12, 9), "tower_30")
	sim.install(Vector2i(22, 12), "tower_28")
	sim.install(Vector2i(5, 12), "tower_29")
	for i in 90:
		sim.spawn(1.0 + i * 0.61, heavy)
	for i in 173:
		sim.tick(STEP)
	await _capture("terminal-charge")
	for i in 44:
		sim.tick(STEP)
	await _capture("terminal-strike")
	await create_timer(0.35).timeout
	ui.start_game()
	sim = ui.battle
	_unlock(sim)
	var sample_cells: Array[Vector2i] = []
	for y in [2, 5, 8, 11, 15]:
		for x in [2, 6, 10, 14, 18, 22, 26]:
			var cell := Vector2i(x, y)
			if sim.field.tile_at(cell) != ".":
				cell += Vector2i(0, 1)
			if sim.field.tile_at(cell) == ".":
				sample_cells.append(cell)
	check(sample_cells.size() >= rules.towers.ids.size(), "all tower art fits on the sample field")
	for i in mini(sample_cells.size(), rules.towers.ids.size()):
		sim.install(sample_cells[i], rules.towers.ids[i])
	check(sim.towers.size() == 30, "all 30 tower silhouettes are installed for visual QA")
	ui.callout_time = 0.0
	await _capture("tower-lineup")

func _click(ui: Control, logical: Vector2) -> void:
	var point := ui.get_global_transform_with_canvas() * logical
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)

func _capture(name: String) -> void:
	if "--visual" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://reports")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(name + ".png")) == OK, "capture " + name)
