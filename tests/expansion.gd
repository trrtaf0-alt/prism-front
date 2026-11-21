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
	var plate_atlas := AttackEffects.PLATES.get_image()
	check(plate_atlas.get_size() == Vector2i(4096, 1024) and plate_atlas.has_mipmaps(), "large effect plates import at full size with lower-resolution levels")
	_attack_details()
	_gravity_slow()
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
	check(graph.unlocks.size() == 34 and graph.ids.size() - graph.unlocks.size() == 66 and rules.towers.ids.size() == 35, "34 unlocks, 66 junctions and 35 towers")
	var distribution := [Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO]
	for id in graph.ids:
		var node: Dictionary = graph.nodes[id]
		distribution[int(node.stage)] += Vector2i(1, int(node.has("unlock")))
		check(node.has("unlock") or not graph.children[id].is_empty(), "junction opens a detectable route: " + id)
	check(distribution == [Vector2i(6, 0), Vector2i(14, 4), Vector2i(24, 8), Vector2i(26, 10), Vector2i(19, 7), Vector2i(11, 5)], "tier distribution")
	var bridge: Dictionary = graph.nodes["phase_bridge"]
	check(not graph.nodes.has("replica") and rules.towers.lookup("tower_27").is_empty(), "replica research and tower were removed")
	check(not bridge.has("unlock") and graph.children[bridge.id].has("white_web") and graph.children[bridge.id].has("interlock"), "phase bridge connects both terminal branches")
	check(ResearchGraph.satisfied(bridge.requirements, {"phase_alignment": true, "storm": true}), "storm satisfies the cross-branch input")
	check(ResearchGraph.satisfied(bridge.requirements, {"phase_alignment": true, "doom": true}), "doom satisfies the cross-branch input")
	check(not ResearchGraph.satisfied(bridge.requirements, {"storm": true, "doom": true}), "phase alignment is required for either input")
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
	check(run.completed.size() == 100 and run.unlocked.size() == 35 and run.points == 150_000 - full_cost, "all independent branches are obtainable in one run")
	for pair: Array in [["singularity", 17247], ["spectrum", 25058], ["cataclysm", 36073]]:
		var cost := graph.minimum_cost(pair[0])
		check(cost == pair[1], "minimum unique RP cost for %s = %d" % [pair[0], cost])
	check(graph.minimum_cost("cataclysm", run.completed) == 0, "completed shared prerequisites not billed")
	check(full_cost == 55874, "full web campaign cost")
	var cataclysm_plans := graph._plans("cataclysm", {}, {})
	var optics_route := false
	var control_route := false
	for plan in cataclysm_plans:
		optics_route = optics_route or (plan.has("spectrum") and not plan.has("singularity"))
		control_route = control_route or (plan.has("singularity") and not plan.has("spectrum"))
	check(optics_route and control_route, "cataclysm has a route through either existing terminal unlock")
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
		moved += stun.step(1.0, STEP, rules.status_rules)
		stun.shock(rules.status_rules)
	check(moved > 0.5 and stun.resistance > 5.0, "continuous shock still permits movement")
	var resistance := stun.resistance
	for i in 600:
		stun.step(1.0, STEP, rules.status_rules)
	check(stun.resistance < resistance, "shock resistance recovers")
	for i in 1000:
		stun.step(1.0, STEP, rules.status_rules)
	stun.shock(rules.status_rules)
	check(is_equal_approx(stun.stun_left, 0.2), "recovered hit restores original duration")
	sim.tick(STEP)
	var pooled := sim.spawn(3.0)
	check(pooled.status.resistance == 0.0 and pooled.status.stun_left == 0.0 and pooled.status.mark_stacks == 0, "pooled enemy resets effects")

func _all_towers() -> void:
	var armored := rules.drone.duplicate()
	armored.health = 50_000
	var removed := _new_battle()
	_unlock(removed)
	check(not removed.install(Vector2i(2, 4), "tower_27") and removed.credits == 5_000_000, "removed tower cannot be installed")
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
		if def.support != TowerSupport.Kind.NONE:
			continue
		var fixture: Array[Battle.Drone] = []
		for i in 11:
			fixture.append(sim.spawn(1.5 + i * 0.11, armored))
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
		touched += int(drone.health == 999966 and drone.status.stun_left > 0.0)
	check(touched == 300, "storm targets exactly 300 globally and applies shock")
	sim = _new_battle()
	_unlock(sim)
	sim.install(Vector2i(2, 4), "tower_30")
	var far := sim.spawn(50.0, armored)
	for i in 211:
		sim.tick(STEP)
	check(far.health == 900000, "cataclysm lands 100000 at remote location after windup")
	for i in 480:
		sim.tick(STEP)
	check(far.health == 800000, "cataclysm lands a second strike eight seconds later")
	sim = _new_battle()
	_unlock(sim)
	sim.install(Vector2i(2, 4), "tower_28")
	var near := sim.spawn(5.0, armored)
	far = sim.spawn(50.0, armored)
	for i in 254:
		sim.tick(STEP)
	check(near.health == 983000 and far.health == 983000, "singularity delivers twenty global ticks of 850 damage")
	check(far.position.is_equal_approx(map.position_at(far.progress)) and far.progress > 50.0 and far.progress < 53.0, "singularity slows progress along the original path")
	sim = _new_battle()
	_unlock(sim)
	sim.install(Vector2i(2, 4), "tower_29")
	var distant: Array[Battle.Drone] = []
	for i in 1000:
		distant.append(sim.spawn(1.0 + i * 0.05, armored))
	sim.tick(STEP)
	var struck := 0
	for drone in distant:
		struck += int(drone.health == 999580)
	check(struck == 1000, "spectrum deals 420 damage each to 1000 enemies despite sampled visuals")

func _gravity_slow() -> void:
	var gravity := rules.towers.lookup("tower_20")
	var freeze := rules.towers.lookup("tower_15")
	var singularity := rules.towers.lookup("tower_28")
	var status := StatusEffects.new()
	status.apply(freeze, rules.status_rules)
	status.apply(gravity, rules.status_rules)
	status.apply(singularity, rules.status_rules)
	status.apply(gravity, rules.status_rules)
	check(is_equal_approx(status.gravity_slow, 0.40) and is_equal_approx(status.gravity_slow_left, 0.24), "gravity slows use the strongest active effect without extending it")
	var expected := 0.24 * 0.32 * 0.60 + 0.26 * 0.32
	var distance := status.step(1.0, 0.5, rules.status_rules)
	var prediction := StatusEffects.new()
	prediction.apply(freeze, rules.status_rules)
	prediction.apply(singularity, rules.status_rules)
	check(is_equal_approx(distance, expected) and is_equal_approx(prediction.predict(5.0, 1.0, 0.5), 5.0 + distance), "movement and interception apply both slows until gravity expires")
	check(is_equal_approx(status.step(1.0, 0.25, rules.status_rules), 0.08), "freeze keeps its own duration after gravity expires")
	var sim := _new_battle()
	_unlock(sim)
	var armored := rules.drone.duplicate()
	armored.health = 1_000_000
	var near := sim.spawn(1.0, armored)
	var lead := sim.spawn(5.0, armored)
	var far := sim.spawn(50.0, armored)
	sim.damage(near, freeze)
	sim.install(Vector2i(2, 4), "tower_20")
	sim.tick(STEP)
	check(near.health == 999969 and lead.health == 999982 and far.health == 1_000_000, "gravity cannon hits only the local field for 18")
	var previous := near.progress
	sim.tick(STEP)
	check(is_equal_approx(near.progress - previous, STEP * 0.224) and near.position.is_equal_approx(map.position_at(near.progress)), "gravity cannon and freeze multiply without changing path")

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
		touched += int(drone.health == 996)
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
	check(target.health == 978 and shards == 16, "split bolt spawns sixteen real secondary bolts")
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
		touched += int(drone.health == 956)
	check(touched == 12 and row.back().health == 956 and row.front().health == 1000, "photon hits the leading twelve enemies globally")
	sim = _new_battle()
	_unlock(sim)
	sim.install(Vector2i(2, 4), "tower_19")
	row.clear()
	for i in 10:
		row.append(sim.spawn(1.0 + i * 0.50, stationary))
	var beyond := sim.spawn(73.0, stationary)
	sim.tick(STEP)
	touched = 0
	for drone in row:
		touched += int(drone.health == 986)
	check(touched == 4 and row.back().health == 986 and row.front().health == 1000 and beyond.health == 1000, "prism hits the leading four enemies within range")

func _interface() -> void:
	var packed := load("res://scenes/Front.tscn") as PackedScene
	var ui = packed.instantiate()
	root.add_child(ui)
	await process_frame
	ui.start_game()
	var sim: Battle = ui.battle
	_sustained_preview(ui.field.advanced_fx)
	_field_preview(ui.field.advanced_fx)
	var original_best: int = root.get_node("Profile").best
	check(ui.rp_label.text == "0" and ui.catalog_button.tooltip_text == "해금된 타워 1종", "HUD fresh research economy")
	sim.start_wave()
	var first := sim.enemies[0]
	var progress := first.progress
	_click(ui, ui.research_button.get_rect().get_center())
	check(ui.modal_kind == "research", "research opens from the HUD midwave")
	if ui.modal_kind != "research":
		ui.queue_free()
		return
	ui._physics_process(STEP)
	check(first.progress == progress and ui.field.frozen, "opening research pauses combat by default")
	check(ui.research_screen.board._states.size() == 100, "board contains all nodes")
	check(ui.research_screen._zone_buttons[0].text == "허브" and ui.research_screen._zone_buttons[5].text == "5단계", "research navigation uses concise stage labels")
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
	board.select_node("phase_bridge", true)
	check(ui.research_screen.description.text == rules.research.nodes["phase_bridge"].description and ui.research_screen.link_summary.text.contains("카타클리즘 격발 연동"), "bridge detail describes its role and links")
	await _capture("research-phase-bridge")
	board.select_node("cataclysm", true)
	check(board.highlighted.size() > 65 and ui.research_screen.buy.disabled, "terminal path and locked condition display")
	await _capture("research-network")
	sim.research.earn(100)
	board.select_node("survey", true)
	await process_frame
	_click(ui, Vector2(1642, 900))
	check(sim.research.completed.has("survey") and sim.research.points == 98, "research button completes and debits selected node")
	for id in ["motion", "bus", "heat", "feed", "rapid"]:
		sim.research.purchase(id)
	check(ui.catalog_button.tooltip_text == "해금된 타워 2종", "unlocked tower count refreshes immediately")
	ui.close_modal()
	ui._physics_process(STEP)
	check(first.progress > progress, "closing research resumes same combat")
	sim.credits = 200
	_click(ui, ui.catalog_button.get_rect().get_center())
	check(ui.modal_kind == "catalog" and _catalog_cards(ui).size() == 2, "catalog opens with unlocked towers")
	await _capture("tower-catalog")
	for button: Button in ui.modal.find_children("*", "Button", true, false):
		if button.text.begins_with("전체"):
			_click(ui, button.get_global_rect().get_center())
			break
	var all_cards := _catalog_cards(ui)
	check(all_cards.size() == 35, "catalog can show every tower on demand")
	_click(ui, all_cards[2].get_global_rect().get_center())
	check(ui.modal_kind == "research" and ui.research_screen.board.focus_id == "pierce", "locked tower links to its research")
	ui.close_modal()
	_click(ui, ui.catalog_button.get_rect().get_center())
	_click(ui, _catalog_cards(ui)[1].get_global_rect().get_center())
	check(ui.building and ui.build_id == "tower_02" and ui.modal == null, "selecting a catalog card enters placement immediately")
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
	profile.fx_zoom = 0.57
	profile.fx_warp = 0.68
	profile.fx_dim = true
	profile.save_profile()
	profile.fx_quality = 2
	profile.fx_dim = false
	profile.fx_zoom = 0.0
	profile.fx_warp = 0.0
	profile.load_profile()
	check(profile.fx_quality == 0 and is_equal_approx(profile.fx_particles, 0.13) and is_equal_approx(profile.fx_flash, 0.24) and is_equal_approx(profile.fx_shake, 0.36) and profile.fx_dim, "existing visual options persist")
	check(is_equal_approx(profile.fx_zoom, 0.57) and is_equal_approx(profile.fx_warp, 0.68), "camera options persist")
	profile.fx_quality = 2
	profile.fx_dim = false
	profile.fx_particles = 0.85
	ui.show_settings("pause_settings")
	ui.show_effect_settings()
	await _capture("effect-settings")
	ui.close_modal()
	if "--visual" in OS.get_cmdline_user_args():
		await _visual_preview(ui)
	await _camera_effects(ui)
	await _tower_audio(ui)
	await _research_stage(ui)
	ui.queue_free()
	await process_frame

func _research_stage(ui) -> void:
	ui.start_game()
	ui.show_research()
	var sim: Battle = ui.battle
	var panel: ResearchScreen = ui.research_screen
	var sound = root.get_node("Sound")
	var audible := DisplayServer.get_name() != "headless"
	var chime: AudioStreamWAV = sound._voices[&"research_stage"].stream
	check(chime.stereo and chime.get_length() > 1.5 and _pcm_peak(chime) > 1000, "research milestone has its own audible stereo chime")
	var milestones: Array[int] = []
	var nodes := sim.research.graph.nodes
	sim.research.purchased.connect(func(id: String, _unlocked: String, advanced: bool) -> void:
		if advanced:
			milestones.append(int(nodes[id].stage))
	)
	panel.board.jump(5)
	check(sim.research.highest_stage == 0 and panel._accent_stage == 0, "browsing locked stages leaves the research tint at the hub")
	sim.research.earn(100)
	check(not sim.research.purchase("rifling") and milestones.is_empty(), "unmet prerequisites do not activate a stage")
	check(sim.research.purchase("survey") and milestones.is_empty(), "hub purchases do not trigger a new stage")
	check(sim.research.purchase("rifling") and milestones == [1], "first successful purchase in a new zone advances the stage")
	if audible:
		check(sound._voices[&"research_stage"].playing, "real research purchase plays the new-stage chime")
	for node in ["needle", "motion", "bus", "heat", "field", "charge"]:
		check(sim.research.purchase(node), "stage fixture can purchase " + node)
	check(milestones == [1], "repeated and older stage purchases keep the current stage")
	check(sim.research.purchase("arc") and milestones == [1, 2], "the next stage activates once")
	await create_timer(0.65).timeout
	check(panel._accent_stage == 2 and panel.board._stage_tint.is_equal_approx(ResearchScreen.STAGE_TINTS[2]), "the visible tint reaches the highest activated stage")
	panel.board.select_node("arc")
	panel.board.overview()
	if audible and "--visual" in OS.get_cmdline_user_args():
		check(chime.save_to_wav("res://reports/research-stage-chime.wav") == OK, "save a preview of the stage chime")
	await _capture("research-stage-mid")
	ui.close_modal()
	ui.show_research()
	panel = ui.research_screen
	check(panel.board._stage_tint == ResearchScreen.STAGE_TINTS[2], "reopening preserves the current stage tint")
	_unlock(sim)
	await create_timer(0.65).timeout
	check(panel.board._stage_tint.is_equal_approx(ResearchScreen.STAGE_TINTS[5]), "latest reached stage wins a series of quick purchases")
	panel.board.select_node("cataclysm")
	panel.board.overview()
	await _capture("research-stage-terminal")
	ui.start_game()
	ui.show_research()
	check(ui.battle.research.highest_stage == 0 and ui.research_screen.board._stage_tint == ResearchScreen.STAGE_TINTS[0], "a fresh run restores the hub tint")
	ui.close_modal()

func _tower_audio(ui) -> void:
	var sound = root.get_node("Sound")
	check(sound.attack_voice("rail", 1) == &"pierce" and sound.attack_voice("rail", 3) == &"rail", "piercing cannon and railgun have different shot voices")
	check(sound.attack_voice("spectrum", 5) == &"" and sound.attack_voice("spectrum_source", 5) == &"spectrum", "multi-target optics emit one sound per source")
	var basic: AudioStreamWAV = sound._voices[&"fire"].stream
	var heavy: AudioStreamWAV = sound._voices[&"cataclysm"].stream
	var charge: AudioStreamWAV = sound._voices[&"charge_cataclysm"].stream
	check(charge.get_length() == 3.5 and heavy.get_length() > basic.get_length() * 8.0, "terminal charge matches its windup and the impact has a longer tail")
	check(_pcm_peak(heavy) > _pcm_peak(basic) * 2, "terminal attack has more headroom than a basic shot")
	var early: AudioStreamWAV = sound._voices[&"deploy_0"].stream
	var terminal: AudioStreamWAV = sound._voices[&"deploy_5"].stream
	check(terminal.get_length() > early.get_length() * 2.0 and _pcm_peak(terminal) > _pcm_peak(early), "terminal deployment locks in with a heavier startup")
	if DisplayServer.get_name() == "headless":
		return
	ui.start_game()
	ui.set_physics_process(false)
	var sim: Battle = ui.battle
	_unlock(sim)
	for pair in [[Vector2i(2, 4), "tower_01", &"deploy_0"], [Vector2i(4, 4), "tower_30", &"deploy_5"], [Vector2i(6, 4), "tower_36", &"support_deploy_6"]]:
		check(sim.install(pair[0], pair[1]) and sound._voices[pair[2]].playing, "real installation plays " + str(pair[2]))
	var profile = root.get_node("Profile")
	var quality: int = profile.fx_quality
	profile.fx_quality = 0
	var armored := rules.drone.duplicate()
	armored.health = 90_000
	sim.spawn(1.9, armored)
	for i in 12:
		sim.tick(STEP)
	check(sound._voices[&"fire"].playing and sound._voices[&"charge_cataclysm"].playing, "real basic shot and terminal windup play at low visual quality")
	for i in 210:
		sim.tick(STEP)
	check(sound._voices[&"cataclysm"].playing, "actual terminal impact plays")
	var last: int = sound._last_time[&"cataclysm"]
	sound.cue(&"cataclysm")
	check(sound._last_time[&"cataclysm"] == last, "repeated terminal audio is rate limited")
	if "--audio-preview" in OS.get_cmdline_user_args():
		await _record_tower_audio(sound)
	profile.fx_quality = quality
	ui.start_game()
	check(not sound._voices[&"cataclysm"].playing and not sound._voices[&"charge_cataclysm"].playing, "restart stops the previous battle's long effects")
	ui.set_physics_process(true)

func _pcm_peak(stream: AudioStreamWAV) -> int:
	var bytes := stream.data
	var peak := 0
	for i in range(0, bytes.size(), 2):
		peak = maxi(peak, absi(bytes.decode_s16(i)))
	return peak

func _record_tower_audio(sound) -> void:
	sound.stop_battle_cues()
	var bus := AudioServer.get_bus_index("Effects")
	var record := AudioEffectRecord.new()
	record.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(bus, record)
	record.set_recording_active(true)
	await create_timer(0.12).timeout
	for sample in [[&"deploy_0", 0.46], [&"fire", 0.24], [&"rapid", 0.22], [&"rapid", 0.25],
			[&"scatter", 0.35], [&"arc", 0.43], [&"rail", 0.53], [&"spectrum", 0.72],
			[&"deploy_5", 0.88], [&"charge_cataclysm", 3.5], [&"cataclysm", 2.1]]:
		sound.cue(sample[0])
		await create_timer(sample[1]).timeout
	record.set_recording_active(false)
	var clip := record.get_recording()
	AudioServer.remove_bus_effect(bus, AudioServer.get_bus_effect_count(bus) - 1)
	check(clip != null and clip.get_length() > 9.0 and clip.save_to_wav("res://reports/tower-audio-preview.wav") == OK, "record a real Effects bus preview")

func _camera_effects(ui) -> void:
	var profile = root.get_node("Profile")
	var previous := Vector3(profile.fx_shake, profile.fx_zoom, profile.fx_warp)
	profile.fx_shake = 1.0
	profile.fx_zoom = 1.0
	profile.fx_warp = 1.0
	ui.start_game()
	ui.set_process(false)
	ui.set_physics_process(false)
	ui.callout_time = 0.0
	var sim: Battle = ui.battle
	var camera: BattleCameraFX = ui.camera_fx
	var focus := Vector2(15.0, 8.0)
	var tint := Color("#ffca84")
	var anchor: Transform2D = ui.wave_button.get_global_transform_with_canvas()
	var cell := Vector2i(2, 4)
	check(sim.field.tile_at(cell) == ".", "camera fixture uses buildable cell")
	for i in 36:
		sim.spawn(2.0 + i * 1.2)
	ui.toggle_build()
	await _capture("camera-steady")
	sim.attack_visual.emit("cataclysm", focus, focus, 10.0, tint, 1.5, 5)
	camera.update(0.085)
	check(ui.field.scale.x < 0.97, "cataclysm pulls the camera out")
	check(ui.wave_button.get_global_transform_with_canvas() == anchor, "camera leaves HUD anchored")
	var shown: Vector2 = ui.field.transform * FieldView.pixel(Vector2(cell) + Vector2.ONE * 0.5)
	check(camera.cell_under(shown) == cell, "shifted board resolves the original grid cell")
	_click(ui, shown)
	check(sim.occupied.has(cell), "a real click places a tower during the camera kick")
	if DisplayServer.get_name() != "headless":
		check(camera._copy.copy_mode == BackBufferCopy.COPY_MODE_VIEWPORT, "lens enables back-buffer sampling during impact")
		var probe := camera._lens_center + Vector2(83, 21)
		check(camera.sample_point(probe).distance_to(probe) > 0.5, "warp shifts sampled pixels")
		check(_click_warped_cell(ui, camera, sim), "a click near a distorted grid line places the tower on the displayed tile")
	await _capture("camera-impact")
	camera.update(0.8)
	check(ui.field.transform.is_equal_approx(Transform2D.IDENTITY) and camera._copy.copy_mode == BackBufferCopy.COPY_MODE_DISABLED, "camera and lens return to rest")
	sim.mob_visual.emit(&"phase", focus, focus, tint, 1.0)
	camera.update(0.065)
	check(ui.field.scale.x > 1.01, "boss phase pushes the camera in")
	ui.show_pause()
	check(camera.suspended and ui.field.transform.is_equal_approx(Transform2D.IDENTITY), "pause stabilizes the field immediately")
	ui.close_modal()
	profile.fx_shake = 0.0
	profile.fx_zoom = 0.0
	profile.fx_warp = 0.0
	sim.attack_visual.emit("cataclysm", focus, focus, 10.0, tint, 1.5, 5)
	camera.update(0.085)
	check(ui.field.transform.is_equal_approx(Transform2D.IDENTITY) and camera._copy.copy_mode == BackBufferCopy.COPY_MODE_DISABLED, "zero-intensity settings disable camera effects")
	profile.fx_shake = previous.x
	profile.fx_zoom = previous.y
	profile.fx_warp = previous.z
	ui.set_process(true)
	ui.set_physics_process(true)

func _click_warped_cell(ui, camera: BattleCameraFX, sim: Battle) -> bool:
	var field: FieldView = ui.field
	var region := camera._lens_region
	for y in range(int(region.position.y), int(region.end.y), 5):
		for x in range(int(region.position.x), int(region.end.x), 5):
			var point := Vector2(x, y)
			var expected := camera.cell_under(point)
			if expected == field.cell_under(point) or sim.field.tile_at(expected) != ".":
				continue
			var shown := camera.sample_point(point)
			var within_cell := (field.transform.affine_inverse() * shown - FieldView.ORIGIN) / FieldView.CELL
			var fractional := within_cell.posmod(1.0)
			if fractional.x < 0.025 or fractional.x > 0.975 or fractional.y < 0.025 or fractional.y > 0.975:
				continue
			_click(ui, point)
			return sim.occupied.has(expected)
	return false

func _visual_preview(ui) -> void:
	var sim: Battle = ui.battle
	var heavy := rules.drone.duplicate()
	heavy.health = 50000
	_unlock(sim)
	sim.install(Vector2i(12, 9), "tower_30")
	sim.install(Vector2i(22, 12), "tower_28")
	sim.install(Vector2i(5, 12), "tower_29")
	ui.callout_time = 0.0
	for i in 90:
		sim.spawn(1.0 + i * 0.61, heavy)
	for i in 173:
		sim.tick(STEP)
	await _capture("terminal-charge")
	for i in 44:
		sim.tick(STEP)
	await _capture("terminal-strike")
	await create_timer(0.60).timeout
	await _capture("terminal-afterglow")
	ui.start_game()
	sim = ui.battle
	_unlock(sim)
	var sample_cells: Array[Vector2i] = []
	for y in [2, 5, 8, 11, 15]:
		for x in [1, 4, 7, 10, 13, 16, 19, 22, 26]:
			var cell := Vector2i(x, y)
			if sim.field.tile_at(cell) != ".":
				cell += Vector2i(0, 1)
			if sim.field.tile_at(cell) == ".":
				sample_cells.append(cell)
	check(sample_cells.size() >= rules.towers.ids.size(), "all tower art fits on the sample field")
	for i in mini(sample_cells.size(), rules.towers.ids.size()):
		sim.install(sample_cells[i], rules.towers.ids[i])
	check(sim.towers.size() == 35, "all 35 tower silhouettes are installed for visual QA")
	ui.callout_time = 0.0
	await _capture("tower-lineup")
	await _attack_showcase(ui)

func _sustained_preview(fx: AttackEffects) -> void:
	fx.capture("laser", Vector2(4, 2), Vector2(4, 3), 0.0, Color.CYAN, 0.25, 2)
	fx.capture("laser", Vector2(4, 2), Vector2(4, 3), 0.0, Color.CYAN, 0.25, 2)
	check(fx._style_counts.get("laser", 0) == 1, "laser pulses reuse the same visible beam")
	fx.capture("flame", Vector2(4, 2), Vector2(4, 3), 62.0, Color.ORANGE, 0.2, 2)
	fx.capture("flame", Vector2(4, 2), Vector2(5, 3), 62.0, Color.ORANGE, 0.2, 2)
	check(fx._style_counts.get("flame", 0) == 1 and fx._ordinary.back().end == FieldView.ORIGIN + Vector2(5, 3) * FieldView.CELL, "flame reuses one plume and follows its current aim")
	fx.update(0.19)
	check(fx._style_counts.get("laser", 0) == 0 and fx._style_counts.get("flame", 0) == 1, "laser leaves a short trail while flame is still visible")
	fx.update(0.2)

func _field_preview(fx: AttackEffects) -> void:
	var center := Vector2(5, 5)
	fx.capture("plasma", center, center, 9.0, Color.VIOLET, 0.24, 3)
	fx.update(0.12)
	var front := fx._rings._buffer[0]
	fx.capture("plasma", center, center, 9.0, Color.VIOLET, 0.24, 3)
	fx.update(0.13)
	fx.capture("plasma", center, center, 9.0, Color.VIOLET, 0.24, 3)
	fx.update(0.14)
	check(fx._style_counts.get("plasma", 0) == 1 and fx._rings._buffer[0] > front and fx._ring_count >= 2, "plasma refresh keeps the previous wave moving and releases a second ring")
	check(fx._plate_count == 0 and fx._glow_count == 0 and fx._line_count == 0, "plasma draws only spreading rings")
	fx.update(0.25)
	fx.capture("ice", center, center, 4.0, Color.LIGHT_SKY_BLUE, 0.55, 3)
	fx.update(0.1)
	check(fx._plate_count == 0 and fx._line_count >= 30 and fx._ring_count == 2 and fx._glow_count > 1, "freeze draws a central crystal, growing shards and two ripples")
	fx.update(0.55)

func _attack_showcase(ui) -> void:
	var test_groups := {
		"fx-mid-beams": {"ids": ["tower_08", "tower_06", "tower_11"], "cells": [Vector2i(5, 2), Vector2i(8, 5), Vector2i(11, 8)], "ticks": 10},
		"fx-mid-fields": {"ids": ["tower_14", "tower_15", "tower_19"], "cells": [Vector2i(5, 5), Vector2i(11, 8), Vector2i(17, 5)], "ticks": 12},
		"fx-cryo-plasma-waves": {"ids": ["tower_14", "tower_15"], "cells": [Vector2i(5, 5), Vector2i(11, 8)], "ticks": 38, "advance_fx": true},
		"fx-mid-projectiles": {"ids": ["tower_16", "tower_17", "tower_12"], "cells": [Vector2i(5, 2), Vector2i(11, 8), Vector2i(19, 6)], "ticks": 28},
		"fx-upper-charge": {"ids": ["tower_07", "tower_18", "tower_26"], "cells": [Vector2i(5, 2), Vector2i(11, 8), Vector2i(18, 6)], "ticks": 12},
		"fx-upper-strike": {"ids": ["tower_13", "tower_18", "tower_26"], "cells": [Vector2i(5, 2), Vector2i(11, 8), Vector2i(18, 6)], "ticks": 53},
		"fx-electrical-optics": {"ids": ["tower_23", "tower_25"], "cells": [Vector2i(12, 8), Vector2i(20, 7)], "ticks": 12},
		"fx-vortex-pulse": {"ids": ["tower_21", "tower_22"], "cells": [Vector2i(12, 8), Vector2i(20, 7)], "ticks": 23},
		"fx-nova-burst": {"ids": ["tower_24"], "cells": [Vector2i(12, 8)], "ticks": 158},
	}
	for name in test_groups:
		ui.start_game()
		ui.callout_time = 0.0
		var sim: Battle = ui.battle
		_unlock(sim)
		ui.callout_time = 0.0
		var scene: Dictionary = test_groups[name]
		for i in scene.ids.size():
			check(sim.install(scene.cells[i], scene.ids[i]), "showcase tower placed " + scene.ids[i])
		var tough := rules.mobs.lookup("normal").duplicate()
		tough.health = 200_000
		for i in 42:
			sim.spawn(2.0 + i * 1.79, tough)
		for i in int(scene.ticks):
			sim.tick(STEP)
			if scene.get("advance_fx", false):
				ui.field.advanced_fx.update(STEP)
		await _capture(name)

func _catalog_cards(ui: Control) -> Array[Button]:
	var cards: Array[Button] = []
	for button: Button in ui.modal.find_children("*", "Button", true, false):
		if not button.accessibility_name.is_empty():
			cards.append(button)
	return cards

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
