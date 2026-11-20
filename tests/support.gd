extends SceneTree

const Kind := TowerSupport.Kind
const STEP := 1.0 / 60.0
const HOST := Vector2i(2, 4)
const SUPPORT_CELLS: Array[Vector2i] = [Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4), Vector2i(8, 4)]
var rules := BattleData.new()
var map := FieldMap.new()
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	check(map.load_map(BattleData.read_json("res://data/sample_map.json")).is_empty(), "map loads")
	_modifiers()
	_range_and_speed()
	_quantum()
	_command()
	if "--visual" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await _visual()
	print("Support checks: %d, failures: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + description)

func _new_battle() -> Battle:
	var sim := Battle.new(map, rules)
	_unlock(sim)
	return sim

func _unlock(sim: Battle) -> void:
	sim.credits = 5_000_000
	sim.research.earn(60_000)
	for id in rules.research.ordered:
		sim.research.purchase(id)

func _heavy(sim: Battle, progress: float = 4.0) -> Battle.Drone:
	var heavy := rules.mobs.lookup("normal").duplicate()
	heavy.health = 10_000
	heavy.speed = 0.0
	return sim.spawn(progress, heavy)

func _modifiers() -> void:
	var sim := _new_battle()
	sim.install(HOST)
	var tower: Battle.Turret = sim.occupied[HOST]
	var events: Array[StringName] = []
	sim.support_visual.connect(func(event, _kind, _a, _b): events.append(event))
	var boost := [Vector2(1, 1.15), Vector2(1, 1.15), Vector2(1.25, 1.15), Vector2(1.75, 1.495), Vector2(1.75, 1.495), Vector2(2.10, 1.71925)]
	for i in SUPPORT_CELLS.size():
		check(sim.install(SUPPORT_CELLS[i], "tower_%d" % (31 + i)), "support %d installs" % (i + 31))
		var pair: Vector2 = boost[i]
		check(is_equal_approx(tower.damage_multiplier, pair.x) and is_equal_approx(tower.speed_multiplier, pair.y), "modifiers after installing %d" % (i + 31))
		check(sim.occupied[SUPPORT_CELLS[i]].buffs.is_empty(), "support tower cannot receive a buff")
	check(tower.effective.range == 5 and tower.definition.range == 4, "range grows without mutating base data")
	check(tower.buffs.size() == 5 and not tower.buffs.has(Kind.QUANTUM), "single target cannot activate quantum")
	sim.install(Vector2i(0, 2), "tower_29")
	check(tower.buffs.has(Kind.QUANTUM) and sim.support.followers(sim.occupied[SUPPORT_CELLS[4]]).size() == 2, "two eligible recipients activate links")
	check(not sim.occupied[Vector2i(0, 2)].buffs.has(Kind.AIM), "global attack ignores range effect")
	sim.install(Vector2i(1, 4), "tower_31")
	var speed := tower.speed_multiplier
	var old_events := events.size()
	sim.sell(SUPPORT_CELLS[0])
	check(tower.buffs[Kind.TACTICAL].cell == Vector2i(1, 4) and tower.speed_multiplier == speed and events.size() == old_events, "identical provider handoff is stable")
	sim.sell(Vector2i(1, 4))
	check(not tower.buffs.has(Kind.TACTICAL) and tower.speed_multiplier < speed and events.back() == &"lose", "last provider sale removes the buff immediately")
	sim.sell(SUPPORT_CELLS[1])
	check(tower.effective.range == 4, "range cache immediately recovers after removal")

func _range_and_speed() -> void:
	var sim := _new_battle()
	sim.install(Vector2i(3, 2))
	var tower: Battle.Turret = sim.occupied[Vector2i(3, 2)]
	var target := _heavy(sim, 7.5)
	check(sim._select_target(tower, tower.effective, true) == null, "target outside default range")
	sim.install(Vector2i(4, 2), "tower_32")
	check(sim._select_target(tower, tower.effective, true) == target, "boosted range changes real targeting")
	for i in 90:
		sim.tick(STEP)
	check(target.health < 10_000, "boosted projectile reaches extended target")
	sim.install(Vector2i(3, 4), "tower_14")
	check(is_equal_approx(sim.occupied[Vector2i(3, 4)].effective.radius, 11.25), "self-centered field covers the boosted reach")
	sim = _new_battle()
	sim.install(HOST)
	tower = sim.occupied[HOST]
	sim.install(Vector2i(3, 4), "tower_33")
	target = _heavy(sim)
	for i in 4:
		sim.damage(target, tower.definition, 1.0, tower)
	check(target.health == 9995, "fractional +25% is retained across one-damage hits")
	sim = _new_battle()
	sim.install(HOST)
	sim.install(Vector2i(3, 4), "tower_31")
	_heavy(sim)
	var shots: Array[float] = []
	var capture_shot := func(event, _from, _direction):
		if event == &"fire":
			shots.append(sim.elapsed)
	sim.effect.connect(capture_shot)
	for i in 420:
		sim.tick(STEP)
	sim.effect.disconnect(capture_shot)
	check(shots.size() >= 8, "tactical produces actual recurring shots")
	if shots.size() >= 8:
		check(absf((shots[7] - shots[0]) / 7.0 - 1.0 / 1.15) <= STEP, "actual shot spacing follows 1.15 rate")

func _quantum() -> void:
	var sim := _new_battle()
	sim.install(HOST)
	sim.install(Vector2i(1, 4), "tower_09")
	sim.install(Vector2i(3, 4), "tower_35")
	sim.install(Vector2i(4, 4), "tower_35")
	var owner: Battle.Turret = sim.occupied[HOST]
	var partner: Battle.Turret = sim.occupied[Vector2i(1, 4)]
	check(sim.support.linked.size() == 2 and sim.support.linked.has(owner) and sim.support.linked.has(partner), "quantum links both attack towers")
	var hits: Array[Vector2] = []
	sim.support_visual.connect(func(event, _kind, _from, target):
		if event == &"quantum":
			hits.append(target))
	var target_1 := _heavy(sim)
	var target_2 := _heavy(sim, 6.0)
	var doomed := sim.spawn(3.0)
	var weapon := owner.definition.duplicate()
	weapon.damage = 60
	sim.barrage([target_1, target_2], weapon, 1.0, owner)
	weapon.damage = 40
	sim.damage(target_1, weapon, 1.0, owner)
	sim.damage(target_2, weapon, 1.0, partner)
	sim.damage(doomed, weapon, 1.0, owner)
	sim.support.tick(sim, 1.99)
	check(hits.is_empty(), "quantum waits for the two-second window")
	sim.support.tick(sim, 0.01)
	check(target_1.health == 9860 and target_2.health == 9884 and hits.size() == 2, "independent 40% hits use one live target per attacker")
	check(doomed.health <= 0, "dead target stays ineligible")
	sim.support.tick(sim, 2.0)
	check(hits.size() == 2, "quantum does not feed itself")
	var original = owner.buffs[Kind.QUANTUM]
	sim.sell(original.cell)
	check(owner.buffs.has(Kind.QUANTUM) and owner.buffs[Kind.QUANTUM] != original, "duplicate quantum providers are nonstacking and hand off")
	for i in 90:
		sim.tick(STEP)
	check(not sim.support.linked[partner].hits.is_empty(), "real partner firing participates in quantum")
	sim.sell(Vector2i(4, 4))
	check(sim.support.linked.is_empty(), "quantum sale clears windows")
	var lone := _new_battle()
	lone.install(HOST)
	lone.install(Vector2i(3, 4), "tower_35")
	check(lone.support.linked.is_empty(), "quantum requires at least two attack towers")

func _command() -> void:
	var sim := _new_battle()
	sim.install(HOST)
	_heavy(sim)
	sim.install(Vector2i(3, 4), "tower_31")
	sim.install(Vector2i(4, 4), "tower_34")
	sim.install(Vector2i(27, 16), "tower_36")
	sim.install(Vector2i(26, 16), "tower_36")
	var tower: Battle.Turret = sim.occupied[HOST]
	var regular := tower.speed_multiplier
	check(is_equal_approx(regular, 1.71925) and is_equal_approx(tower.damage_multiplier, 1.68), "one global Command applies regardless of distance")
	sim.support.tick(sim, 14.99)
	check(not sim.support.synchronized, "sync waits full period")
	sim.support.tick(sim, 0.01)
	check(sim.support.synchronized and tower.speed_multiplier == 1.9 and is_equal_approx(sim.support.time_to_sync(), 5.0), "sync starts at 15s and hits the 1.9 cap")
	sim.sell(Vector2i(27, 16))
	check(sim.support.synchronized and tower.speed_multiplier == 1.9, "core handoff does not reset phase")
	sim.support.tick(sim, 4.99)
	check(sim.support.synchronized, "sync lasts until the full five seconds elapse")
	sim.support.tick(sim, 0.01)
	check(not sim.support.synchronized and is_equal_approx(tower.speed_multiplier, regular), "sync end restores original product")
	sim.support.tick(sim, 10.0)
	check(sim.support.synchronized, "next sync starts at 30s")
	sim.sell(Vector2i(26, 16))
	check(not sim.support.synchronized and not tower.buffs.has(Kind.COMMAND), "last command sale immediately removes all global effects")

func _visual() -> void:
	var scene := load("res://scenes/Front.tscn") as PackedScene
	var ui = scene.instantiate()
	root.add_child(ui)
	await process_frame
	ui.set_physics_process(false)
	var profile = root.get_node("Profile")
	profile.fx_quality = 3
	for i in SUPPORT_CELLS.size():
		ui.start_game()
		var sim: Battle = ui.battle
		_unlock(sim)
		sim.install(Vector2i(5, 2), "tower_09")
		sim.install(Vector2i(7, 2), "tower_13")
		var cell := Vector2i(6, 4)
		sim.install(cell, "tower_%d" % (31 + i))
		ui.callout_time = 0.0
		var enemy := _heavy(sim, 7.4)
		if i == 5:
			sim.support.tick(sim, 15.0)
		for tick in (121 if i == 4 else 25):
			sim.tick(STEP)
		if i == 4:
			check(sim.support.linked.size() == 2 and enemy.health < 10000, "rendered quantum fixture uses both linked attackers")
		ui.selected = cell
		ui._sync_selection()
		check(ui.tower_stats.text.contains("대상  2기"), "selected support reports actual coverage %d" % (31 + i))
		await _capture("support-%d" % (31 + i))
		if i == 5:
			ui.selected = Vector2i(5, 2)
			ui._sync_selection()
			ui.show_support_details()
			check(ui.modal_kind == "support", "recipient support detail displays")
			await _capture("support-recipient")
			ui.close_modal()
			var attack: Battle.Turret = sim.occupied[Vector2i(5, 2)]
			var before := attack.speed_multiplier
			profile.fx_quality = 0
			profile.fx_dim = true
			await _capture("support-minimal")
			check(before == attack.speed_multiplier and sim.support.synchronized and enemy.health > 0, "minimal and dim settings preserve simulation")
	ui.start_game()
	var combined: Battle = ui.battle
	_unlock(combined)
	combined.install(HOST, "tower_09")
	combined.install(Vector2i(0, 2), "tower_13")
	for i in SUPPORT_CELLS.size():
		combined.install(SUPPORT_CELLS[i], "tower_%d" % (31 + i))
	_heavy(combined)
	combined.support.tick(combined, 15.0)
	ui.selected = HOST
	ui.callout_time = 0.0
	ui._sync_selection()
	profile.fx_quality = 3
	profile.fx_dim = false
	for i in 28:
		combined.tick(STEP)
	check(combined.occupied[HOST].buffs.size() == 6, "six active modifiers displayed together")
	await _capture("support-stacked")
	ui.show_support_details()
	await _capture("support-stacked-details")
	ui.queue_free()
	await process_frame

func _capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var file := ProjectSettings.globalize_path("res://reports/" + name + ".png")
	check(root.get_texture().get_image().save_png(file) == OK, "visual capture " + name)
