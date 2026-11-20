extends SceneTree

const STEP := 1.0 / 60.0

var rules := BattleData.new()
var map := FieldMap.new()
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _run() -> void:
	_check(map.load_map(BattleData.read_json("res://data/sample_map.json")).is_empty(), "map loads")
	_check(rules.mobs.error.is_empty(), rules.mobs.error)
	if failures > 0:
		quit(1)
		return
	_registry()
	_damage_and_control()
	_exit_collision()
	_guardian()
	_split()
	_periodic()
	_rosters()
	_boss()
	_crowd()
	await _interface()
	print("Mob checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _fresh() -> Battle:
	var sim := Battle.new(map, rules)
	sim.roster_seed = 7043
	return sim

func _advance(sim: Battle, ticks: int) -> void:
	for i in ticks:
		sim.tick(STEP)

func _registry() -> void:
	var originals := 0
	for def: Dictionary in rules.mobs.definitions.values():
		originals += int(not def.child)
		var sim := _fresh()
		var unit := sim.spawn(7.0, def)
		sim.tick(STEP)
		_check(unit.progress > 7.0 and unit.position.is_equal_approx(map.position_at(unit.progress)), "valid route " + str(def.id))
		sim._apply_damage(unit, 1_000_000, Vector2.ZERO)
		sim.tick(STEP)
		_check(sim.credits == 50 + int(def.reward) and sim.research.points == int(def.reward_rp), "exact separate bounty " + str(def.id))
		sim = _fresh()
		sim.health = 999_999
		var leaks: Array[int] = []
		sim.base_damaged.connect(func(amount: int): leaks.append(amount))
		sim.spawn(map.length(), def)
		sim.tick(STEP)
		_check(leaks == [int(def.health)] and sim.health == 999_999 - int(def.health) and sim.enemies.is_empty(), "raw body leak without shield or births " + str(def.id))
		_check(sim.credits == 50 and sim.research.points == 0, "no leak reward " + str(def.id))
	_check(originals == 18 and rules.mobs.definitions.size() == 21, "18 main enemies and three child definitions")
	var base := rules.mobs.lookup("normal")
	_check(base.health == 5 and base.speed == 1.0 and base.reward == 3 and base.reward_rp == 1, "stable normal base and RP")
	var raw := BattleData.read_json("res://data/enemies.json")
	var bad := raw.duplicate(true)
	for row: Dictionary in bad.enemies:
		if row.id == "guardian":
			row.guardian.stackable = true
	_check(not EnemyRegistry.new(rules.drone, bad).error.is_empty(), "reject stacking guard data")
	bad = raw.duplicate(true)
	for row: Dictionary in bad.enemies:
		if row.id == "split_2":
			row.split_to = "split_1"
	_check(not EnemyRegistry.new(rules.drone, bad).error.is_empty(), "reject recursive split data")
	bad = raw.duplicate(true)
	for row: Dictionary in bad.enemies:
		if row.id == "brood_child":
			row.reward_rp = 12
	_check(not EnemyRegistry.new(rules.drone, bad).error.is_empty(), "reject summoned RP farming")
	var wrong := rules.drone.duplicate()
	wrong.health = 6
	_check(not EnemyRegistry.new(wrong, raw).error.is_empty(), "reject changed base HP")

func _damage_and_control() -> void:
	var sim := _fresh()
	var barrier := sim.spawn(3.0, rules.mobs.lookup("shield"))
	var control := rules.towers.lookup("tower_01").duplicate()
	control.merge({"shock": true, "slow": 0.4, "pull": 1.6, "status_time": 1.0}, true)
	sim.damage(barrier, control, 1.0, 2.0)
	_check(barrier.health == 42 and barrier.shield_hp == 24, "shield takes full incoming damage first")
	_check(is_equal_approx(barrier.status.stun_left, 0.1) and is_equal_approx(barrier.status.slow, 0.20) and is_equal_approx(barrier.status.pull, 0.8), "shield halves all three impairments")
	barrier.status.reset()
	barrier.status.resistance = 2.0
	sim.damage(barrier, control, 1.0, 2.0)
	_check(is_equal_approx(barrier.status.stun_left, 0.1 * 0.7 * 0.7), "repeated stun and shield combine")
	barrier.shield_hp = 6
	barrier.status.reset()
	control.damage = 17
	sim.damage(barrier, control, 1.0, 2.0)
	_check(barrier.health == 31 and barrier.shield_hp == 0, "breaking hit sends exact overflow to body")
	_check(is_equal_approx(barrier.status.stun_left, 0.2) and is_equal_approx(barrier.status.slow, 0.4) and is_equal_approx(barrier.status.pull, 1.6), "breaking hit applies full control")
	var innate := sim.spawn(4.0, rules.mobs.lookup("resist"))
	control.damage = 1
	sim.damage(innate, control, 1.0, 2.0)
	_check(is_equal_approx(innate.status.stun_left, 0.12), "innate impairment resistance")
	innate.give_shield(1000, 7, 5)
	innate.status.reset()
	sim.damage(innate, control, 1.0, 2.0)
	_check(innate.shield_hp == 999 and is_equal_approx(innate.status.stun_left, 0.06), "innate and granted shield multiply")
	var armored := sim.spawn(4.0, rules.mobs.lookup("armored"))
	armored.give_shield(3, 7, 5)
	sim._apply_damage(armored, 13, Vector2.ZERO)
	_check(armored.shield_hp == 0 and armored.health == 14, "armor applies to body overflow only")

func _exit_collision() -> void:
	var exit := map.path[map.path.size() - 1]
	var direction := map.heading_at(map.length())
	for distance in [0.22, 0.27]:
		var sim := _fresh()
		var unit := sim.spawn(map.length() - 0.001)
		unit.health = 1
		sim._fire(exit - direction * float(distance), direction)
		sim.tick(STEP)
		var early: bool = distance < 0.25
		_check(sim.health == (100 if early else 99) and sim.credits == (53 if early else 50), "projectile causality at exit " + str(distance))

func _guardian() -> void:
	var sim := _fresh()
	var first := sim.spawn(3.0, rules.mobs.lookup("guardian"))
	var second := sim.spawn(3.2, rules.mobs.lookup("guardian"))
	var ally := sim.spawn(3.4)
	var outside := sim.spawn(38.0)
	_advance(sim, 180)
	var carrier := ally.shield_source
	_check(ally.shield_hp == 1000 and carrier in [first.serial, second.serial], "two guardians do not stack shield")
	_check(first.shield_hp == 0 and second.shield_hp == 0 and outside.shield_hp == 0, "guardians exclude each other and distant targets")
	var shock := rules.towers.lookup("tower_06")
	sim.damage(ally, shock)
	_check(ally.health == 5 and ally.shield_hp == 998 and is_equal_approx(ally.status.stun_left, 0.1), "guarded normal inherits shield rules")
	sim._apply_damage(ally, 998, Vector2.ZERO)
	_advance(sim, 180)
	_check(ally.shield_hp == 0, "five second rearm blocks next pulse")
	_advance(sim, 180)
	_check(ally.shield_hp == 1000, "later pulse restores depleted shield")
	sim._apply_damage(first, 1_000_000, Vector2.ZERO)
	sim._apply_damage(second, 1_000_000, Vector2.ZERO)
	var newcomer := sim.spawn(ally.progress)
	_advance(sim, 720)
	_check(ally.shield_hp == 1000 and newcomer.shield_hp == 0, "existing shield survives caster death with no new grants")
	var progress := ally.progress
	sim._apply_damage(ally, 1001, Vector2.ZERO)
	_check(ally.shield_hp == 0 and ally.health == 4 and ally.progress == progress, "surviving guard barrier remains destructible")

func _split() -> void:
	var sim := _fresh()
	sim.start_wave()
	sim.queued = 0
	sim._apply_damage(sim.enemies[0], 5, Vector2.ZERO)
	var parent := sim.spawn(5.25, rules.mobs.lookup("split"))
	sim._apply_damage(parent, 75, Vector2.ZERO)
	sim._apply_damage(parent, 75, Vector2.ZERO)
	sim.tick(STEP)
	_check(sim.active and sim.enemies.size() == 4, "four first children hold wave open")
	var stage_one := sim.enemies.duplicate()
	var marks: Dictionary = {}
	for unit: Battle.Drone in stage_one:
		_check(unit.definition.id == "split_1" and unit.progress == 5.25 and unit.position.is_equal_approx(map.position_at(5.25)), "child starts exactly on parent progress")
		marks[unit.serial] = true
		sim._apply_damage(unit, 18, Vector2.ZERO)
	sim.tick(STEP)
	_check(sim.enemies.size() == 16 and sim.active and marks.size() == 4, "sixteen independent second generation kids")
	var stage_two := sim.enemies.duplicate()
	for unit: Battle.Drone in stage_two:
		_check(unit.definition.id == "split_2" and not marks.has(unit.serial), "fresh pooled identity for second child")
		sim._apply_damage(unit, 4, Vector2.ZERO)
	sim.tick(STEP)
	_check(sim.enemies.is_empty() and not sim.active and sim.credits == 92 and sim.research.points == 3, "21 total actors, no third split, unique bounty and wave reward")

func _periodic() -> void:
	var sim := _fresh()
	var regen := sim.spawn(3.0, rules.mobs.lookup("regen"))
	regen.health = 50
	var fast := sim.spawn(5.0, rules.mobs.lookup("accelerate"))
	var cloak := sim.spawn(8.9, rules.mobs.lookup("cloak"))
	var brood := sim.spawn(4.0, rules.mobs.lookup("brood"))
	_advance(sim, 100)
	_check(regen.health == 58 and fast.speed > 1.1, "regeneration timer and gradual acceleration")
	_advance(sim, 130)
	_check(cloak.hidden, "cloak has active visibility window")
	var hunter := rules.towers.lookup("tower_09").duplicate()
	var fake := Battle.Turret.new()
	fake.position = cloak.position
	hunter.range = 0.25
	_check(sim._select_target(fake, hunter, false) == null, "ordinary auto-target excludes hidden enemy")
	hunter.detect_cloak = true
	_check(sim._select_target(fake, hunter, false) == cloak, "detector can acquire hidden enemy")
	sim._apply_damage(cloak, 4, Vector2.ZERO)
	_check(cloak.health == 41, "concealment does not block area or existing hits")
	_advance(sim, 100)
	_check(not cloak.hidden and regen.health == regen.maximum_health, "cloak ends and healing caps")
	_advance(sim, 1150)
	var kids: Array[Battle.Drone] = []
	for unit in sim.enemies:
		if unit.definition.get("id") == "brood_child":
			kids.append(unit)
	_check(kids.size() == 5 and brood.mob.births_left == 0 and is_equal_approx(fast.speed, 2.35), "bounded spawn and acceleration cap")
	for child in kids:
		sim._apply_damage(child, 99, Vector2.ZERO)
	sim.tick(STEP)
	_check(sim.credits == 55 and sim.research.points == 0, "brood children pay capped currency and no RP")
	sim = _fresh()
	var booster := sim.spawn(3.0, rules.mobs.lookup("amplifier"))
	var booster_two := sim.spawn(3.1, rules.mobs.lookup("amplifier"))
	var escort := sim.spawn(3.2)
	_advance(sim, 108)
	var previous := escort.progress
	_advance(sim, 60)
	_check(is_equal_approx(escort.boost_bonus, 0.3) and is_equal_approx(escort.progress - previous, 1.3), "boost improves movement with no stacking")
	sim._apply_damage(booster, 999, Vector2.ZERO)
	sim._apply_damage(booster_two, 999, Vector2.ZERO)
	_advance(sim, 170)
	_check(escort.boost_bonus == 0.0, "boost expires after source death")

func _rosters() -> void:
	for wave in [1, 4, 5, 12, 20, 35, 44, 45, 46, 50]:
		var total := rules.wave_count(wave)
		var roster := WaveRoster.new(rules.mobs, wave, total, 7043 ^ wave)
		var replay := WaveRoster.new(rules.mobs, wave, total, 7043 ^ wave)
		var counts: Dictionary = {}
		var rp := 0
		var correct := true
		for i in total:
			var def := roster.next()
			correct = correct and def.id == replay.next().id and not def.child and def.first_wave <= wave
			counts[def.id] = counts.get(def.id, 0) + 1
			rp += int(def.reward_rp)
		_check(correct and total == roundi(10 * pow(1.2, wave - 1)), "deterministic exact wave " + str(wave))
		_check(counts.get("normal", 0) > 0 and (wave > 4 or counts.size() == 1), "ordinary enemies remain present " + str(wave))
		_check(counts.get("boss", 0) == int(wave >= 45 and wave % 5 == 0), "one scheduled boss when eligible " + str(wave))
		for id: String in counts:
			var cap := int(rules.mobs.lookup(id).wave_cap)
			_check(cap == 0 or counts[id] <= cap, "type cap " + id)
		print("Wave %d roster: %d scheduled, %.3f RP per kill, %d types" % [wave, total, float(rp) / total, counts.size()])
	var sim := _fresh()
	sim.wave = 44
	sim.start_wave()
	_advance(sim, 720)
	_check(sim.bosses.size() == 1 and sim.queued == rules.wave_count(45) - 25, "actual wave 45 schedules boss at slot 25 at fixed 0.5 s")

func _boss() -> void:
	var sim := _fresh()
	var boss := sim.spawn(27.0, rules.mobs.lookup("boss"))
	_check(boss.maximum_health == 300000 and boss.shield_hp == 18000 and sim.bosses.size() == 1, "boss stats and runtime tracking")
	sim._apply_damage(boss, 138000, Vector2.ZERO)
	_check(boss.mob.phase == 1 and boss.shield_hp == 14000 and is_equal_approx(boss.speed, 0.39), "phase two shield and movement")
	sim._apply_damage(boss, 132000, Vector2.ZERO)
	_check(boss.mob.phase == 2 and boss.shield_hp == 22000 and is_equal_approx(boss.speed, 0.525) and boss.mob.regen.amount == 1100, "phase three support and regeneration")
	_advance(sim, 90)
	_check(boss.mob.phase == 2 and boss.health > 90560, "boss heals in phase without reverting")
	sim = _fresh()
	var leaks: Array[int] = []
	sim.base_damaged.connect(func(amount: int): leaks.append(amount))
	boss = sim.spawn(map.length(), rules.mobs.lookup("boss"))
	boss.health = 50000
	sim.tick(STEP)
	_check(leaks == [50000] and sim.lost and sim.health == 0 and sim.bosses.is_empty(), "uncapped 50000 boss hit with live shield excluded")

func _crowd() -> void:
	var sim := _fresh()
	for i in 250:
		sim.spawn(5.0 + i * 0.023, rules.mobs.lookup("split"))
	for unit in sim.enemies:
		sim._apply_damage(unit, 75, Vector2.ZERO)
	sim.tick(STEP)
	_check(sim.enemies.size() == 1000, "mass birth first generation")
	for unit in sim.enemies:
		sim._apply_damage(unit, 18, Vector2.ZERO)
	sim.tick(STEP)
	_check(sim.enemies.size() == 4000, "mass birth second generation without drops")
	for unit in sim.enemies:
		sim._apply_damage(unit, 4, Vector2.ZERO)
	sim.tick(STEP)
	_check(sim.enemies.is_empty() and sim.research.points == 500 and sim._ability_units.is_empty() and sim._drone_pool.size() <= 4096, "mass retirement with bounded pool")
	var recycled := sim.spawn(3)
	_check(recycled.shield_hp == 0 and not recycled.hidden and recycled.mob.slot == -1 and recycled.boost_bonus == 0.0 and recycled.speed == 1.0, "pooled combat state is clean")

func _interface() -> void:
	var scene := load("res://scenes/Front.tscn") as PackedScene
	var ui = scene.instantiate()
	root.add_child(ui)
	await process_frame
	ui.start_game()
	var sim: Battle = ui.battle
	var ids := rules.mobs.definitions.keys()
	for i in ids.size():
		sim.spawn(i * 2.6 + 2.0, rules.mobs.lookup(ids[i]))
	var boss := sim.bosses[0]
	sim._apply_damage(boss, 138000, Vector2.ZERO)
	_advance(sim, 190)
	ui._update_hud()
	_check(ui.boss_panel.visible and ui.boss_title.text.contains("2단계") and ui.boss_values.text.contains("보호막"), "boss phase, health and shield readout")
	if "--visual" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var file := ProjectSettings.globalize_path("res://reports/mobs-roster.png")
		_check(image.save_png(file) == OK, "render and capture the live mob field")
	ui.start_game()
	_check(ui.battle.bosses.is_empty() and ui.battle.enemies.is_empty() and ui.battle._ability_units.is_empty() and not ui.boss_panel.visible, "restart clears mob state and HUD")
	ui.queue_free()
	await process_frame
