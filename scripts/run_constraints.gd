class_name RunConstraints
extends RefCounted

const INCOME := [100, 90, 80, 70, 60, 50]
const PRICE := [100, 120, 140, 160, 180, 200]
const TOWER_LIMIT := [0, 40, 30, 25, 20, 12]
const ENEMY_DURABILITY := [100, 125, 150, 200, 300, 500]
const SPEED := [100, 110, 120, 135, 150, 175]
const BOSS_DURABILITY := [100, 150, 200, 300, 400, 600]

const DEFINITIONS := {
	&"credits": ["재화 감소", INCOME],
	&"rp": ["연구 자원 감소", INCOME],
	&"tower_price": ["물가 폭등", PRICE],
	&"research_price": ["연구 비용 폭등", PRICE],
	&"tower_limit": ["설치 수 제한", TOWER_LIMIT],
	&"enemy_hp": ["적 체력 증가", ENEMY_DURABILITY],
	&"enemy_speed": ["적 속도 증가", SPEED],
	&"enemy_shield": ["적 보호막 증가", ENEMY_DURABILITY],
	&"boss_hp": ["보스 체력 증가", BOSS_DURABILITY],
	&"boss_speed": ["보스 이동속도 증가", SPEED],
	&"boss_shield": ["보스 보호막 증가", BOSS_DURABILITY],
}

var _levels: Dictionary = {}

func _init(selected: Dictionary = {}) -> void:
	for id: StringName in DEFINITIONS:
		var level := clampi(int(selected.get(id, 0)), 0, 5)
		if level > 0:
			_levels[id] = level

func active() -> bool:
	return not _levels.is_empty()

func count() -> int:
	return _levels.size()

func value(id: StringName) -> int:
	return int(DEFINITIONS[id][1][_levels.get(id, 0)])

static func effect_text(id: StringName, level: int) -> String:
	if level == 0:
		return "꺼짐"
	var selected := int(DEFINITIONS[id][1][level])
	return "%d기" % selected if id == &"tower_limit" else "%+d%%" % (selected - 100)

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
