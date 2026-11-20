class_name BattleData
extends RefCounted

const NUMBER_LIMIT: int = 9_000_000_000_000_000

static func read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

var turret: Dictionary = read_json("res://data/turret.json")
var drone: Dictionary = read_json("res://data/drone.json")
var balance: Dictionary = read_json("res://data/balance.json")

func wave_count(wave: int) -> int:
	return wave_value(int(balance.first_wave_count), wave)

func wave_reward(wave: int) -> int:
	return wave_value(int(balance.first_wave_reward), wave)

func wave_value(first: int, wave: int) -> int:
	var value := first * pow(float(balance.wave_growth), wave - 1)
	if not is_finite(value) or value >= NUMBER_LIMIT:
		return NUMBER_LIMIT
	return roundi(value)

func spawn_interval(_wave: int) -> float:
	return maxf(0.001, float(balance.temporary_spawn_interval))
