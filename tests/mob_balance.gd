extends SceneTree

const BASIC: Array[Vector2i] = [
	Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 4), Vector2i(4, 4),
]
const GROW: Array[Vector2i] = [
	Vector2i(4, 2), Vector2i(5, 2), Vector2i(6, 2), Vector2i(7, 2), Vector2i(8, 2),
	Vector2i(9, 2), Vector2i(10, 3), Vector2i(10, 4), Vector2i(10, 5), Vector2i(10, 6),
	Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6), Vector2i(1, 4), Vector2i(2, 4),
	Vector2i(6, 4), Vector2i(7, 4), Vector2i(8, 4), Vector2i(8, 5), Vector2i(7, 5),
	Vector2i(8, 6), Vector2i(12, 9), Vector2i(8, 12), Vector2i(9, 12), Vector2i(12, 12),
	Vector2i(6, 12), Vector2i(5, 12), Vector2i(15, 10), Vector2i(10, 14), Vector2i(11, 14),
]
const GOALS := [20000, 30000, 45000]
const IDS := ["tower_02", "tower_09", "tower_12", "tower_13", "tower_24"]

var rules := BattleData.new()
var map := FieldMap.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not map.load_map(BattleData.read_json("res://data/sample_map.json")).is_empty() or not rules.mobs.error.is_empty():
		quit(1)
		return
	_economy()
	var passed := _autoplay()
	var boss_passed := _boss_trial()
	quit(0 if passed and boss_passed else 1)

func _economy() -> void:
	var total_rp := 0
	var total_enemies := 0
	var goal := 0
	var total_spawn_time := 0.0
	for wave in range(1, BattleData.FINAL_WAVE):
		var slots := rules.wave_count(wave)
		var roster := WaveRoster.new(rules.mobs, wave, slots, 7043 ^ wave)
		for i in slots:
			var def := roster.next()
			if i > 0:
				total_spawn_time += rules.spawn_interval(wave)
			total_rp += roundi(float(def.reward_rp) * rules.slot_rp_multiplier(wave))
			total_enemies += 1
			if goal < GOALS.size() and total_rp >= GOALS[goal]:
				print("At 100%% kills: %d RP in wave %d after %d scheduled kills (%.2f hours of spawns)" % [
					GOALS[goal], wave, total_enemies, total_spawn_time / 3600.0,
				])
				goal += 1
	print("Total attainable RP at wave 49: ", total_rp)

func _buy_route(sim: Battle, tower: String) -> void:
	var graph := rules.research
	var id: String = graph.unlocks[tower]
	var plans := graph._plans(id, sim.research.completed, {})
	var best: Dictionary = {}
	var cost := INF
	for plan in plans:
		var price := 0
		for step: String in plan:
			price += int(graph.nodes[step].cost_rp)
		if price < cost:
			best = plan
			cost = price
	for step in graph.ordered:
		if best.has(step):
			sim.research.purchase(step)

func _autoplay() -> bool:
	var sim := Battle.new(map, rules)
	sim.roster_seed = 7043
	for cell in BASIC:
		sim.install(cell)
	var slot := 0
	var maximum := 24
	for wave in range(1, maximum + 1):
		sim.start_wave()
		var ticks := 0
		while sim.active and not sim.lost and ticks < 50000:
			ticks += 1
			sim.tick(1.0 / 60)
		print("Run wave %d: HP %d, total RP %d, credits %d, %d towers" % [
			wave, sim.health, sim.research.total_earned, sim.credits, sim.towers.size(),
		])
		if sim.lost or sim.active:
			return false
		for tower in IDS:
			if not sim.research.unlocked.has(tower):
				_buy_route(sim, tower)
				break
		for i in 3:
			if slot >= GROW.size():
				break
			var chosen := TowerRegistry.BASE
			for j in range(IDS.size() - 1, -1, -1):
				var id: String = IDS[j]
				if sim.research.unlocked.has(id) and sim.credits >= int(rules.towers.lookup(id).cost):
					chosen = id
					break
			if wave > 6 and chosen == TowerRegistry.BASE:
				break
			if not sim.install(GROW[slot], chosen):
				break
			slot += 1
		_upgrade(sim, 4 if wave >= 16 else 2)
	return sim.research.unlocked.has("tower_13")

func _upgrade(sim: Battle, limit: int) -> void:
	for attempt in limit:
		var origin: Battle.Turret
		for tower in sim.towers:
			if origin == null or int(tower.definition.cost) < int(origin.definition.cost):
				origin = tower
		if origin == null:
			return
		var chosen := ""
		for i in range(IDS.size() - 1, -1, -1):
			var id: String = IDS[i]
			var new_cost := int(rules.towers.lookup(id).cost)
			if new_cost > int(origin.definition.cost) and sim.research.unlocked.has(id) and sim.credits + int(origin.definition.refund) >= new_cost:
				if new_cost <= 60 and sim.wave >= 10:
					continue
				chosen = id
				break
		if chosen.is_empty():
			return
		var cell := origin.cell
		sim.sell(cell)
		sim.install(cell, chosen)

func _boss_trial() -> bool:
	var sim := Battle.new(map, rules)
	sim.credits = 3_000_000
	sim.research.earn(90000)
	for id in rules.research.ordered:
		sim.research.purchase(id)
	var ids := ["tower_30", "tower_29", "tower_28", "tower_30", "tower_29", "tower_28", "tower_30", "tower_29"]
	for i in ids.size():
		sim.install(GROW[i], ids[i])
	sim.spawn(0.0, rules.mobs.lookup("boss"))
	var seconds := 0
	for i in 48000:
		if i % 30 == 0:
			sim.spawn(0.0, rules.mobs.lookup("normal"))
		sim.tick(1.0 / 60)
		if sim.lost or sim.bosses.is_empty():
			seconds = i / 60
			break
	var killed := not sim.lost and sim.bosses.is_empty()
	print("Terminal tower fixture: boss %s in %d simulated seconds using %d towers" % [
		"defeated" if killed else "survived", seconds, sim.towers.size(),
	])
	return killed
