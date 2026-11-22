class_name BattleData
extends RefCounted

const NUMBER_LIMIT: int = 9_000_000_000_000_000
const FINAL_WAVE := 50
const CAMPAIGN_RECORD_VERSIONS := {&"easy": 16, &"normal": 15, &"hard": 15}
const DIFFICULTIES := {&"easy": "쉬움", &"normal": "보통", &"hard": "어려움"}

static func read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

var turret: Dictionary = read_json("res://data/turret.json")
var drone: Dictionary = read_json("res://data/drone.json")
var balance: Dictionary = read_json("res://data/balance.json")
var mobs: EnemyRegistry
var final_wave := FINAL_WAVE
var boss_id := "boss"
var mod_map: FieldMap
var wave_rules: Dictionary = {}
var media: Dictionary = {}
var campaign_error := ""
var difficulty_rules := read_json("res://data/difficulty.json")
var status_rules: Dictionary = read_json("res://data/status.json")
var towers: TowerRegistry
var research: ResearchGraph

func _init(additions: Dictionary = {}) -> void:
	var campaign: Dictionary = additions.get("campaign", {})
	final_wave = int(campaign.get("final_wave", FINAL_WAVE))
	boss_id = campaign.get("boss_id", "boss")
	for row: Dictionary in campaign.get("waves", []):
		wave_rules[int(row.wave)] = row
	if campaign.has("map"):
		mod_map = FieldMap.new()
		campaign_error = mod_map.load_map(campaign.map)
	media = additions.get("media", {})
	var enemy_content := read_json("res://data/enemies.json")
	if enemy_content.get("enemies") is Array:
		enemy_content.enemies.append_array(additions.get("enemies", []))
	mobs = EnemyRegistry.new(drone, enemy_content)
	var tower_rows: Array = read_json("res://data/towers.json").get("towers", [])
	tower_rows.append_array(additions.get("towers", []))
	towers = TowerRegistry.new(turret, tower_rows, additions.get("tower_overrides", {}))
	var research_rows: Array = read_json("res://data/research.json").get("nodes", [])
	research_rows.append_array(additions.get("nodes", []))
	research = ResearchGraph.new(research_rows, towers)
	if campaign_error.is_empty():
		campaign_error = _validate_campaign()

func _validate_campaign() -> String:
	if not mobs.error.is_empty():
		return mobs.error
	if not mobs.lookup(boss_id).get("boss", false):
		return "최종 보스 ID를 확인하세요 · " + boss_id
	for number: int in wave_rules:
		var rule: Dictionary = wave_rules[number]
		var slots := wave_count(number) - int(number == final_wave)
		if number > final_wave or slots < 0:
			return "웨이브 번호 또는 적 수를 확인하세요 · %d" % number
		if not rule.has("spawns"):
			continue
		var planned := 0
		for group: Dictionary in rule.spawns:
			var enemy := mobs.lookup(group.enemy)
			if enemy.is_empty() or enemy.boss or enemy.child:
				return "편성에서 사용할 수 없는 적 · " + group.enemy
			planned += int(group.count)
		if planned != slots:
			return "웨이브 적 수와 편성 합계가 다릅니다 · %d" % number
	return ""

func make_roster(number: int, seed: int, escort: Dictionary = {}) -> WaveRoster:
	return WaveRoster.new(mobs, number, wave_count(number), seed, escort,
		final_wave, boss_id, wave_rules.get(number, {}).get("spawns", []))

func audio(kind: String) -> AudioStream:
	return media.get("audio", {}).get(kind)

func tower_sprite(id: String) -> Texture2D:
	return media.get("towers", {}).get(id)

func enemy_for_wave(base: Dictionary, wave: int, difficulty: StringName, constraints: RunConstraints = null) -> Dictionary:
	var unit := _difficulty_enemy(base, wave, difficulty)
	return constraints.enemy(unit) if constraints != null and constraints.active() else unit

func _difficulty_enemy(base: Dictionary, wave: int, difficulty: StringName) -> Dictionary:
	if base.id == "guardian":
		return base
	var tuning: Dictionary = difficulty_rules.get(str(difficulty), {})
	if tuning.is_empty():
		return base
	if bool(base.boss):
		if base.id != "boss" or not tuning.has("boss_health"):
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
	var intro: Array = base.get("intro_hp", [])
	if not intro.is_empty():
		hp *= curve(intro, wave)
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
	if wave < 1 or wave > final_wave:
		return 0
	if wave_rules.get(wave, {}).has("count"):
		return int(wave_rules[wave].count)
	if wave <= 10:
		return roundi(10.0 * pow(1.2, wave - 1))
	var k := wave - 10
	return roundi(52.0 + 8 * k + 0.3 * k * k)

func wave_reward(wave: int) -> int:
	if wave_rules.get(wave, {}).has("reward"):
		return int(wave_rules[wave].reward)
	return roundi(wave_count(wave) * curve(balance.clearance_per_slot, wave))

func slot_rp_multiplier(wave: int) -> float:
	return curve(balance.rp_scale, wave)

func escort_shield(wave: int, difficulty: StringName, constraints: RunConstraints = null) -> int:
	var config: Dictionary = balance.get("escorts", {})
	var anchors: Array = difficulty_rules.get(str(difficulty), {}).get("escort_shield", [])
	if wave < int(config.get("first_wave", FINAL_WAVE + 1)) or anchors.is_empty():
		return 0
	var amount := maxi(0, roundi(curve(anchors, wave)))
	return RunConstraints.scaled(amount, constraints.value(&"enemy_shield")) if constraints != null else amount

func spawn_interval(wave: int) -> float:
	if wave_rules.get(wave, {}).has("interval"):
		return float(wave_rules[wave].interval)
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
