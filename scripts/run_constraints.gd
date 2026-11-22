class_name RunConstraints
extends RefCounted

const REDUCTION := [100, 90, 80, 70, 60, 50]
const BONUS_INCOME := [100, 125, 150, 175, 200, 250]
const PRICE := [100, 120, 140, 160, 180, 200]
const TOWER_LIMIT := [0, 40, 30, 25, 20, 12]
const ENEMY_DURABILITY := [100, 125, 150, 200, 300, 500]
const SPEED := [100, 110, 120, 135, 150, 175]
const BOSS_DURABILITY := [100, 150, 200, 300, 400, 600]

const DEFINITIONS := {
	&"credits": ["재화 획득", REDUCTION, BONUS_INCOME],
	&"rp": ["연구 자원 획득", REDUCTION, BONUS_INCOME],
	&"tower_price": ["타워 설치 가격", PRICE, REDUCTION],
	&"research_price": ["연구 비용", PRICE, REDUCTION],
	&"tower_limit": ["타워 설치 수", TOWER_LIMIT],
	&"enemy_hp": ["일반 적 체력", ENEMY_DURABILITY, REDUCTION],
	&"enemy_speed": ["일반 적 이동속도", SPEED, REDUCTION],
	&"enemy_shield": ["일반 적 보호막", ENEMY_DURABILITY, REDUCTION],
	&"boss_hp": ["보스 체력", BOSS_DURABILITY, REDUCTION],
	&"boss_speed": ["보스 이동속도", SPEED, REDUCTION],
	&"boss_shield": ["보스 보호막", BOSS_DURABILITY, REDUCTION],
}

var _levels: Dictionary = {}
var starting_funds: int
var starting_rp: int
var _default_funds: int

func _init(selected: Dictionary = {}, funds: int = -1, default_funds: int = 50, rp: int = 0) -> void:
	_default_funds = default_funds
	starting_funds = clampi(funds, 0, BattleData.NUMBER_LIMIT) if funds >= 0 else default_funds
	starting_rp = clampi(rp, 0, BattleData.NUMBER_LIMIT)
	for id: StringName in DEFINITIONS:
		var level := clampi(int(selected.get(id, 0)), -5, max_level(id))
		if level != 0:
			_levels[id] = level

func active() -> bool:
	return not _levels.is_empty() or starting_funds != _default_funds or starting_rp > 0

func count() -> int:
	return _levels.size()

func badge_text() -> String:
	if _levels.is_empty():
		if starting_rp > 0:
			return "시작 RP" if starting_funds == _default_funds else "시작 자원"
		return "시작자금"
	var restrictions := _levels.values().any(func(level: int): return level < 0)
	var perks := _levels.values().any(func(level: int): return level > 0)
	var category := "규칙" if restrictions and perks else ("제약" if restrictions else "특전")
	return "%s %d종" % [category, count()]

func summary_text() -> String:
	var lines := PackedStringArray()
	for id: StringName in _levels:
		var level := int(_levels[id])
		lines.append("%s · %s" % [DEFINITIONS[id][0], setting_text(id, level)])
	if starting_funds != _default_funds:
		lines.append("시작자금 · %d" % starting_funds)
	if starting_rp > 0:
		lines.append("시작 RP · %d" % starting_rp)
	return "\n".join(lines)

func value(id: StringName) -> int:
	return _at_level(id, int(_levels.get(id, 0)))

static func max_level(id: StringName) -> int:
	return 0 if id == &"tower_limit" else 5

static func _at_level(id: StringName, level: int) -> int:
	return int(DEFINITIONS[id][2 if level > 0 else 1][absi(level)])

static func effect_text(id: StringName, level: int) -> String:
	if level == 0:
		return "제한 없음" if id == &"tower_limit" else "변동 없음"
	var selected := _at_level(id, level)
	return "최대 %d기" % selected if id == &"tower_limit" else "%+d%%" % (selected - 100)

static func setting_text(id: StringName, level: int) -> String:
	if level == 0:
		return "기본 0단계 · " + effect_text(id, level)
	return "%s %+d단계 · %s" % ["제약" if level < 0 else "특전", level, effect_text(id, level)]

static func scaled(amount: int, percent: int) -> int:
	return roundi(float(amount) * percent / 100.0) if percent != 100 else amount

func enemy(definition: Dictionary) -> Dictionary:
	var boss := bool(definition.boss)
	var hp := value(&"boss_hp" if boss else &"enemy_hp")
	var speed := value(&"boss_speed" if boss else &"enemy_speed")
	var shield := value(&"boss_shield" if boss else &"enemy_shield")
	if hp == 100 and speed == 100 and shield == 100:
		return definition
	var unit := definition.duplicate(true)
	unit.health = scaled(int(unit.health), hp)
	unit.speed = float(unit.speed) * speed / 100.0
	unit.shield = scaled(int(unit.shield), shield)
	if not unit.acceleration.is_empty():
		unit.acceleration.rate *= speed / 100.0
		unit.acceleration.max_speed *= speed / 100.0
	if not unit.guardian.is_empty():
		unit.guardian.shield_hp = scaled(int(unit.guardian.shield_hp), shield)
	if shield != 100:
		for phase: Dictionary in unit.phases:
			if phase.has("shield"):
				phase.shield = scaled(int(phase.shield), shield)
	return unit
