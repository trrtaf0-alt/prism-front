extends SceneTree

const STEP := 1.0 / 60.0
const OPTIONS := ["baseline", "reserve_spectrum", "reserve_photon", "refit_photon", "refit_sniper", "refit_support", "refit_mark", "refit_mark_sniper", "refit_mark_trim"]
const PHOTON := "tower_25"
const SPECTRUM := "tower_29"
const SNIPER := "tower_09"
const MARK := "tower_10"
const HP := { "easy": 10_000_000, "normal": 30_000_000, "hard": 70_000_000 }

var rules := BattleData.new()
var map := FieldMap.new()
var snapshot: Dictionary
var formation := "baseline"
var time_limit := 800
var campaign_boss := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--campaign-boss":
			campaign_boss = true
		elif arg.begins_with("--snapshot="):
			snapshot = BattleData.read_json(arg.trim_prefix("--snapshot="))
		elif arg.begins_with("--formation="):
			formation = arg.trim_prefix("--formation=")
		elif arg.begins_with("--limit="):
			time_limit = int(arg.trim_prefix("--limit="))
		elif arg.begins_with("--enemy-data="):
			var tuning := BattleData.read_json(arg.trim_prefix("--enemy-data="))
			if tuning.is_empty():
				printerr("Could not read enemy difficulty data")
				quit(1)
				return
			rules.difficulty_rules = tuning
	if snapshot.is_empty() or not HP.has(snapshot.get("difficulty")) or not formation in OPTIONS or time_limit < 1:
		printerr("Provide a W49 snapshot, a valid formation, and a positive time limit")
		quit(1)
		return
	if not map.load_map(BattleData.read_json("res://data/sample_map.json")).is_empty():
		quit(1)
		return
	var sim := _restore()
	if sim == null:
		printerr("Invalid W49 snapshot or unreproducible purchase")
		quit(1)
		return
	var refit := formation.begins_with("refit_")
	if refit:
		for tower: Battle.Turret in sim.towers.duplicate():
			var id: String = tower.definition.id
			if id == SPECTRUM or (formation == "refit_mark_trim" and id in ["tower_13", "tower_18"]):
				sim.sell(tower.cell)
	if formation == "reserve_spectrum":
		_buy_until(sim, SPECTRUM, 4)
	if formation in ["refit_mark", "refit_mark_sniper", "refit_mark_trim"]:
		for node in rules.research.ordered:
			sim.research.purchase(node)
		_buy_until(sim, MARK, 4)
	if formation in ["refit_sniper", "refit_mark_sniper"]:
		_buy_until(sim, SNIPER, 36)
	if formation == "refit_support":
		_place(sim, "tower_34")
		_place(sim, "tower_35")
	if formation != "baseline":
		_buy_until(sim, PHOTON, 30)
	# Snapshot reconstruction begins at an intermission; only the selected refit spends its cash.
	var counts := {}
	var covered := 0
	var key_tiles := {}
	for tower: Battle.Turret in sim.towers:
		var id: String = tower.definition.id
		counts[id] = int(counts.get(id, 0)) + 1
		if id == MARK or tower.definition.support != TowerSupport.Kind.NONE:
			if not key_tiles.has(id):
				key_tiles[id] = []
			key_tiles[id].append([tower.cell.x + 1, tower.cell.y + 1])
		if id == PHOTON and tower.buffs.has(TowerSupport.Kind.QUANTUM) and tower.buffs.has(TowerSupport.Kind.OVERDRIVE):
			covered += 1
	print(JSON.stringify({"layout": formation, "difficulty": snapshot.difficulty, "route": snapshot.strategy, "bank": sim.credits, "counts": counts, "covered_photons": covered, "key_tiles": key_tiles}))
	sim.start_wave()
	var boss := sim.bosses[0]
	if not campaign_boss:
		boss.health = int(HP[snapshot.difficulty])
		boss.maximum_health = boss.health
		boss.armor = 0.10
	var exit_position := map.position_at(map.length())
	var furthest_progress := boss.progress
	var nearest_direct := boss.position.distance_to(exit_position)
	var ticks := 0
	var next_progress := 300
	var escort_peak := 0
	var escort_clear := -1.0
	while sim.active and ticks < time_limit * 60:
		var track_boss := not sim.boss_killed and not sim.boss_escaped
		sim.tick(STEP)
		ticks += 1
		var escorts := sim.enemies.size() - sim.bosses.size()
		escort_peak = maxi(escort_peak, escorts)
		if escort_clear < 0.0 and sim.queued == 0 and escorts == 0:
			escort_clear = ticks * STEP
		if track_boss:
			furthest_progress = maxf(furthest_progress, boss.progress)
			nearest_direct = minf(nearest_direct, boss.position.distance_to(exit_position))
		if ticks == next_progress * 60:
			print("t=%ds boss_hp=%d base=%d" % [next_progress, 0 if sim.boss_killed else boss.health, sim.health])
			next_progress += 300
	print(JSON.stringify({
		"clear": sim.won, "boss_killed": sim.boss_killed, "escape": sim.boss_escaped,
		"boss_left": 0 if sim.boss_killed else boss.health, "time": ticks * STEP,
		"boss_time": sim.finale_boss_time, "base": sim.health, "queued": sim.queued,
		"live": sim.enemies.size(),
		"closest_path_tiles": maxf(0.0, map.length() - furthest_progress),
		"closest_direct_tiles": nearest_direct,
		"furthest_tile": Vector2i(map.position_at(furthest_progress).floor()) + Vector2i.ONE,
		"escort_peak": escort_peak, "escort_clear": escort_clear,
	}))
	quit()

func _restore() -> Battle:
	var sim := Battle.new(map, rules, StringName(snapshot.difficulty))
	sim.wave = 49
	sim.health = int(snapshot.health)
	sim.roster_seed = int(snapshot.seed)
	var completed: Array = snapshot.completed
	var points := int(snapshot.points)
	for id: String in completed:
		points += int(rules.research.nodes[id].cost_rp)
	sim.research.earn(points)
	for id: String in rules.research.ordered:
		if id in completed and not sim.research.purchase(id):
			return null
	sim.credits = int(snapshot.credits)
	for row: Array in snapshot.towers:
		sim.credits += int(rules.towers.lookup(row[0]).cost)
	for row: Array in snapshot.towers:
		var cell := Vector2i(int(row[1]), int(row[2]))
		if not sim.install(cell, row[0]):
			return null
		var tower: Battle.Turret = sim.occupied[cell]
		tower.cooldown = float(row[3])
		tower.angle = float(row[4])
	sim.support.command_time = float(snapshot.command_clock)
	return sim

func _buy_until(sim: Battle, id: String, limit: int) -> void:
	for _index in limit:
		if not _place(sim, id):
			break

func _place(sim: Battle, id: String) -> bool:
	var def := rules.towers.lookup(id)
	if sim.credits < int(def.cost) or not sim.research.unlocked.has(id):
		return false
	var best := Vector2i(-1, -1)
	var score := -INF
	for y in map.size.y:
		for x in map.size.x:
			var cell := Vector2i(x, y)
			if not sim.can_install(cell, id):
				continue
			var point := Vector2(cell) + Vector2.ONE * 0.5
			var value := _attack_score(sim, def, point) if def.support == TowerSupport.Kind.NONE else _support_score(sim, def, point)
			if value > score:
				score = value
				best = cell
	return sim.install(best, id)

func _attack_score(sim: Battle, def: Dictionary, point: Vector2) -> float:
	var tags := {}
	for source: Battle.Turret in sim.support.sources:
		if source.definition.global or point.distance_squared_to(source.position) <= float(source.definition.range) ** 2:
			tags[source.definition.support] = true
	var coverage := 1.0
	if not def.global:
		var radius := float(def.range) * (TowerSupport.AIM_RANGE if tags.has(TowerSupport.Kind.AIM) else 1.0)
		coverage = 0.0
		for index in map.path.size():
			var target := map.path[index]
			if point.distance_squared_to(target) > radius * radius:
				continue
			var contribution := 1.0 if index < 38 else 0.40
			if def.id == MARK:
				for tower: Battle.Turret in sim.towers:
					if tower.definition.id == MARK and tower.position.distance_squared_to(target) <= float(tower.effective.range) ** 2:
						contribution *= 0.35
			coverage += contribution
	var weight := coverage
	for tag: int in tags:
		weight *= float(TowerSupport.DAMAGE.get(tag, 1.0)) * float(TowerSupport.SPEED.get(tag, 1.0))
	if tags.has(TowerSupport.Kind.QUANTUM):
		weight *= 1.3
	# Keep equally supported global towers off the spots that give local towers the best path coverage.
	return weight - (0.001 if def.global else 0.00001) * point.distance_squared_to(Vector2(10.5, 7.5))

func _support_score(sim: Battle, def: Dictionary, point: Vector2) -> float:
	var score := 0.0
	for tower: Battle.Turret in sim.towers:
		if tower.definition.support == TowerSupport.Kind.NONE and not tower.buffs.has(def.support) and point.distance_squared_to(tower.position) <= float(def.range) ** 2:
			score += float(tower.definition.damage) / float(tower.definition.interval)
	return score
