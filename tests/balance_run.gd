extends SceneTree

const INITIAL: Array[Vector2i] = [
	Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 4), Vector2i(4, 4),
]
const REINFORCEMENTS: Array[Vector2i] = [
	Vector2i(4, 2), Vector2i(5, 2), Vector2i(6, 2), Vector2i(7, 2), Vector2i(8, 2),
	Vector2i(9, 2), Vector2i(10, 3), Vector2i(10, 4), Vector2i(10, 5), Vector2i(10, 6),
	Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6), Vector2i(1, 4), Vector2i(2, 4),
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var data := BattleData.new()
	var map := FieldMap.new()
	if not map.load_map(BattleData.read_json("res://data/sample_map.json")).is_empty():
		quit(1)
		return
	var sim := Battle.new(map, data)
	for cell in INITIAL:
		sim.install(cell)
	var researched_at := 0
	var placed_at := 0
	var slot := 0
	var route := ["survey", "motion", "bus", "heat", "feed", "rapid"]
	for wave in range(1, 13):
		sim.start_wave()
		var ticks := 0
		while sim.active and not sim.lost and ticks < 40000:
			ticks += 1
			sim.tick(1.0 / 60.0)
		if sim.lost or sim.active:
			printerr("Balance fixture failed wave ", wave)
			quit(1)
			return
		for id: String in route:
			sim.research.purchase(id)
		if researched_at == 0 and sim.research.unlocked.has("tower_02"):
			researched_at = wave
		var chosen := "tower_02" if researched_at > 0 else TowerRegistry.BASE
		for _i in 3:
			if slot >= REINFORCEMENTS.size() or not sim.install(REINFORCEMENTS[slot], chosen):
				break
			slot += 1
			if placed_at == 0 and chosen == "tower_02":
				placed_at = wave
		print("Wave %d: health=%d cash=%d RP earned=%d RP remaining=%d towers=%d" % [
			wave, sim.health, sim.credits, sim.research.total_earned, sim.research.points, sim.towers.size(),
		])
	print("Rapid fire researched after wave %d and installed after wave %d" % [researched_at, placed_at])
	quit(1 if researched_at == 0 or placed_at == 0 else 0)
