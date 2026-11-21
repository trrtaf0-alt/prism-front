extends SceneTree

const STEP := 1.0 / 60.0
const SECONDS := 24
const SITE := Vector2i(7, 6)
const SUPPORT_SITE := Vector2i(7, 5)
const MIXED_CELLS := [Vector2i(6, 6), SITE, Vector2i(8, 6)]
const MIXED_ATTACKS := ["tower_09", "tower_14", "tower_29"]
const CASES := ["single", "lane", "field"]

var rules := BattleData.new()
var map := FieldMap.new()
var failed := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not map.load_map(BattleData.read_json("res://data/sample_map.json")).is_empty() 			or not rules.towers.error.is_empty() or not rules.research.error.is_empty():
		printerr("Could not load tower balance fixtures")
		quit(1)
		return
	var reference := _measure("", "field", true)
	print("id,stage,credits,rp,single_dps,lane_dps,field_dps,targets_hit,stall_pct,support_field_gain")
	for id in rules.towers.ids:
		var def := rules.towers.lookup(id)
		var price := int(def.cost)
		var rp := rules.research.minimum_cost(def.research_id) if not def.research_id.is_empty() else 0
		if def.support != TowerSupport.Kind.NONE or def.attack == "mark":
			var boosted := _measure(id, "field", true)
			print("%s,%d,%d,%d,,,,,,%.2f" % [id, def.stage, price, rp, boosted.x - reference.x])
			continue
		var single := _measure(id, CASES[0])
		var lane := _measure(id, CASES[1])
		var field := _measure(id, CASES[2])
		print("%s,%d,%d,%d,%.2f,%.2f,%.2f,%d,%.2f," % [
			id, def.stage, price, rp, single.x, lane.x, field.x, int(field.y), field.z,
		])
	quit(1 if failed else 0)

func _measure(id: String, layout: String, mixed: bool = false) -> Vector3:
	var sim := Battle.new(map, rules)
	sim.credits = 2_000_000
	for tower_id in rules.towers.ids:
		sim.research.unlocked[tower_id] = true
	if mixed:
		for i in MIXED_CELLS.size():
			_install(sim, MIXED_CELLS[i], MIXED_ATTACKS[i])
		if not id.is_empty():
			_install(sim, SUPPORT_SITE, id)
	else:
		_install(sim, SITE, id)
	var model := rules.drone.duplicate()
	model.health = 2_000_000
	model.speed = 0.18
	model.armor = 0.10
	var start_progress: Array[float] = []
	match layout:
		"single":
			start_progress.append(14.0)
		"lane":
			for i in 30:
				start_progress.append(8.0 + i * 0.37)
		"field":
			for i in 60:
				start_progress.append(3.0 + i * 1.19)
	var targets: Array[Battle.Drone] = []
	for start in start_progress:
		targets.append(sim.spawn(start, model))
	for i in SECONDS * 60:
		sim.tick(STEP)
	var damage := 0
	var touched := 0
	var progress := 0.0
	for i in targets.size():
		var unit := targets[i]
		if unit.health < int(model.health):
			damage += int(model.health) - unit.health
			touched += 1
		progress += unit.progress - start_progress[i]
	var unimpeded := float(model.speed) * SECONDS * targets.size()
	return Vector3(float(damage) / SECONDS, touched, 100.0 * (1.0 - progress / unimpeded))

func _install(sim: Battle, cell: Vector2i, id: String) -> void:
	if not sim.install(cell, id):
		failed = true
		printerr("Could not install %s at %s" % [id, cell])