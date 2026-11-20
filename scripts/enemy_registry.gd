class_name EnemyRegistry
extends RefCounted

const SHIELD_CONTROL_MULTIPLIER := 0.5
const SPLIT_COUNT := 4
const DEFAULTS := {
	"first_wave": 1, "weight": 0.0, "wave_cap": 0, "boss": false, "boss_period": 0,
	"child": false, "generation": 0, "split_to": "", "shield": 0, "armor": 0.0,
	"control_resist": 0.0, "shape": "drone", "scale": 1.0, "regen": {}, "cloak": {},
	"acceleration": {}, "guardian": {}, "boost": {}, "brood": {}, "phases": [],
}
const SHAPES := ["drone", "dart", "hex", "swarm", "cell", "split", "ring", "guardian", "relay", "tank", "calamity", "boss"]

var definitions: Dictionary = {}
var normal_weight := 61.0
var additive_control := false
var error := ""

func _init(base: Dictionary, content: Dictionary) -> void:
	if base.get("health") != 5 or base.get("speed") != 1 or base.get("reward") != 3:
		error = "일반형의 확정 수치가 변경되었습니다."
		return
	var rows: Variant = content.get("enemies")
	var mode: Variant = content.get("resistance_mode")
	if not rows is Array or rows.is_empty() or mode not in ["multiply", "additive"]:
		error = "몹 편성 데이터를 읽을 수 없습니다."
		return
	normal_weight = float(content.get("normal_weight", 61))
	additive_control = mode == "additive"
	if normal_weight <= 0.0:
		error = "일반형 출현 가중치는 양수여야 합니다."
		return
	var normal := base.duplicate()
	normal.merge({"id": "normal", "weight": normal_weight}, true)
	_register(normal)
	for row: Variant in rows:
		if not row is Dictionary or not _register(row):
			error = "몹 정의를 확인하세요 · " + str(row.get("id", "") if row is Dictionary else row)
			return
	for def: Dictionary in definitions.values():
		var target: Dictionary = definitions.get(def.split_to, {})
		if not def.split_to.is_empty() and (target.is_empty() or not target.child or target.generation != def.generation + 1 or target.reward_rp != 0):
			error = "분열 세대 또는 보상이 올바르지 않습니다 · " + def.id
			return
		if def.generation >= 2 and not def.split_to.is_empty() or def.generation == 1 and def.split_to.is_empty():
			error = "분열은 두 단계만 허용됩니다 · " + def.id
			return
		if not def.brood.is_empty():
			var child: Dictionary = definitions.get(def.brood.child, {})
			if child.is_empty() or not child.child or not child.brood.is_empty() or not child.split_to.is_empty() or child.reward_rp != 0:
				error = "재귀 증식 또는 생성체 RP를 확인하세요 · " + def.id
				return
	if definitions.get("split", {}).get("split_to") != "split_1" or definitions.get("split_1", {}).get("split_to") != "split_2":
		error = "분열형은 원본, 1차, 2차가 모두 필요합니다."

func _register(raw: Dictionary) -> bool:
	var def := DEFAULTS.duplicate()
	def.merge(raw, true)
	var id: String = str(def.get("id", ""))
	if id.is_empty() or definitions.has(id) or not def.get("name") is String or not def.get("color") is String:
		return false
	if int(def.get("health", 0)) <= 0 or float(def.get("speed", -1)) <= 0.0 or int(def.get("reward", -1)) < 0 or int(def.get("reward_rp", -1)) < 0:
		return false
	if def.first_wave < 0 or def.weight < 0 or def.wave_cap < 0 or def.shield < 0 or def.scale <= 0 or def.shape not in SHAPES:
		return false
	if def.armor < 0 or def.armor >= 1 or def.control_resist < 0 or def.control_resist >= 1 or int(def.generation) not in [0, 1, 2] or float(def.generation) != int(def.generation):
		return false
	if def.boss and (def.boss_period < 1 or def.child):
		return false
	for ability in ["regen", "cloak", "acceleration", "guardian", "boost", "brood"]:
		if not def[ability] is Dictionary:
			return false
	if not _interval_for(def.regen, ["amount"]) or not _interval_for(def.guardian, ["shield_hp", "range", "targets"]):
		return false
	if not _interval_for(def.boost, ["range", "targets", "bonus", "duration"]) or not _interval_for(def.brood, ["limit"]):
		return false
	if not def.guardian.is_empty() and (def.guardian.get("rearm", -1) < 0 or def.guardian.get("stackable", false) or not def.guardian.get("persist_after_caster_death", true)):
		return false
	if not def.brood.is_empty() and not def.brood.get("child") is String:
		return false
	if not def.cloak.is_empty() and (def.cloak.get("hidden", 0) <= 0 or def.cloak.get("cycle", 0) <= def.cloak.hidden):
		return false
	if not def.acceleration.is_empty() and (def.acceleration.get("rate", 0) <= 0 or def.acceleration.get("max_speed", 0) < def.speed):
		return false
	if def.get("base_damage_mode", "remaining_hp") != "remaining_hp" or not def.phases is Array:
		return false
	var threshold := 1.0
	for phase: Variant in def.phases:
		if not phase is Dictionary or phase.get("threshold", 0) <= 0 or phase.threshold >= threshold:
			return false
		if phase.get("shield", 0) < 0 or phase.get("speed_multiplier", 1) <= 0:
			return false
		if not _interval_for(phase.get("regen", {}), ["amount"]) or not _interval_for(phase.get("boost", {}), ["range", "targets", "bonus", "duration"]):
			return false
		threshold = float(phase.threshold)
	definitions[id] = def
	return true

static func _interval_for(config: Variant, positive: Array) -> bool:
	if not config is Dictionary:
		return false
	if config.is_empty():
		return true
	if config.get("interval", 0) <= 0:
		return false
	for key: String in positive:
		if config.get(key, 0) <= 0:
			return false
	return true

func lookup(id: String) -> Dictionary:
	return definitions.get(id, {})

func control_multiplier(resist: float, shielded: bool) -> float:
	if not shielded:
		return 1.0 - resist
	if additive_control:
		return maxf(0.0, SHIELD_CONTROL_MULTIPLIER - resist)
	return (1.0 - resist) * SHIELD_CONTROL_MULTIPLIER
