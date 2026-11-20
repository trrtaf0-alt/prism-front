class_name BattleData
extends RefCounted

const NUMBER_LIMIT: int = 9_000_000_000_000_000
const FINAL_WAVE := 50
const CAMPAIGN_RECORD := "campaign_08"
const DIFFICULTIES := {&"easy": "쉬움", &"normal": "보통", &"hard": "어려움"}

static func read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

var turret: Dictionary = read_json("res://data/turret.json")
var drone: Dictionary = read_json("res://data/drone.json")
var balance: Dictionary = read_json("res://data/balance.json")
var mobs := EnemyRegistry.new(drone, read_json("res://data/enemies.json"))
var difficulty_rules := read_json("res://data/difficulty.json")
var status_rules: Dictionary = read_json("res://data/status.json")
var towers := TowerRegistry.new(turret, read_json("res://data/towers.json").get("towers", []))
var research := ResearchGraph.new(read_json("res://data/research.json").get("nodes", []), towers)

func enemy_for_wave(base: Dictionary, wave: int, difficulty: StringName) -> Dictionary:
	if base.id == "guardian":
		return base
	var tuning: Dictionary = difficulty_rules.get(str(difficulty), {})
	if tuning.is_empty():
		return base
	if bool(base.boss):
		if not tuning.has("boss_health"):
			return base
		var boss := base.duplicate(true)
		boss.health = int(tuning.boss_health)
		boss.speed = float(tuning.boss_speed)
		boss.shield = roundi(float(base.shield) * float(tuning.boss_shield))
		boss.regen.amount = roundi(float(base.regen.amount) * float(tuning.boss_regen))
		for phase: Dictionary in boss.phases:
			phase.shield = roundi(float(phase.shield) * float(tuning.boss_shield))
			phase.regen.amount = roundi(float(phase.regen.amount) * float(tuning.boss_regen))
		return boss
	var hp := curve(tuning.hp, wave)
	var speed := curve(tuning.speed, wave)
	if hp == 1.0 and speed == 1.0:
		return base
	var unit := base.duplicate(true)
	unit.health = roundi(float(base.health) * hp)
	unit.shield = roundi(float(base.shield) * hp)
	unit.speed = float(base.speed) * speed
	if not unit.acceleration.is_empty():
		unit.acceleration.rate *= speed
		unit.acceleration.max_speed *= speed
	if not unit.regen.is_empty():
		unit.regen.amount = roundi(float(unit.regen.amount) * hp)
	for phase: Dictionary in unit.phases:
		phase.shield = roundi(float(phase.shield) * hp)
		if phase.has("regen"):
			phase.regen.amount = roundi(float(phase.regen.amount) * hp)
	return unit

func wave_count(wave: int) -> int:
	if wave < 1 or wave > FINAL_WAVE:
		return 0
	if wave <= 10:
		return roundi(10.0 * pow(1.2, wave - 1))
	var k := wave - 10
	return roundi(52.0 + 8 * k + 0.3 * k * k)

func wave_reward(wave: int) -> int:
	return roundi(wave_count(wave) * curve(balance.clearance_per_slot, wave))

func slot_rp_multiplier(wave: int) -> float:
	return curve(balance.rp_scale, wave)

func spawn_interval(wave: int) -> float:
	return maxf(0.04, 0.5 * pow(0.95, maxi(0, wave - 1)))

static func curve(anchors: Array, wave: int) -> float:
	var previous: Array = anchors[0]
	if wave <= int(previous[0]):
		return float(previous[1])
	for point: Array in anchors:
		if wave <= int(point[0]):
			return lerpf(float(previous[1]), float(point[1]), float(wave - int(previous[0])) / float(int(point[0]) - int(previous[0])))
		previous = point
	return float(previous[1])
