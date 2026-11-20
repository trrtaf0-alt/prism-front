class_name BattleData
extends RefCounted

const NUMBER_LIMIT: int = 9_000_000_000_000_000
const FINAL_WAVE := 50
const CAMPAIGN_RECORD := "campaign_05"

static func read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

var turret: Dictionary = read_json("res://data/turret.json")
var drone: Dictionary = read_json("res://data/drone.json")
var balance: Dictionary = read_json("res://data/balance.json")
var mobs := EnemyRegistry.new(drone, read_json("res://data/enemies.json"))
var status_rules: Dictionary = read_json("res://data/status.json")
var towers := TowerRegistry.new(turret, read_json("res://data/towers.json").get("towers", []))
var research := ResearchGraph.new(read_json("res://data/research.json").get("nodes", []), towers)

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
