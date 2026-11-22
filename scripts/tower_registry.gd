class_name TowerRegistry
extends RefCounted

const BASE := "tower_01"
const DEFAULTS := {
	"support": 0, "stage": 0, "research_id": "", "radius": 0.0, "projectile_speed": 12.0,
	"fx": "fire", "global": false, "priority": "exit", "center": "target",
	"shots": 1, "spread": 0.0, "width": 0.25, "max_targets": 0, "jump_radius": 0.0,
	"windup": 0.0, "ramp": 0.0, "duration": 0.0, "tick": 0.0, "guided": false,
	"returning": false, "split": 0, "fragment_damage": 0, "fragment_range": 0.0,
	"slow": 0.0, "gravity_slow": 0.0, "shock": false, "status_time": 0.0, "mark_bonus": 0.0,
	"mark_cap": 0,
	"economy": "", "production": 0,
}
const ATTACK_NAMES := {
	"support": "지원", "economy": "경제", "bolt": "투사체", "line": "직선 관통", "chain": "연쇄", "strike": "지연 타격",
	"cone": "부채꼴", "beam": "광선", "mark": "피해 증폭 표식", "field": "지속 광역",
	"multi": "동시 조준", "pulse": "확산 충격파", "singularity": "전역 지속장",
}

var definitions: Dictionary = {}
var ids: Array[String] = []
var error := ""

func _init(base: Dictionary, additions: Array, overrides: Dictionary = {}) -> void:
	if base.is_empty() or additions.is_empty():
		error = "기본 또는 확장 타워 데이터를 읽을 수 없습니다."
		return
	var core := base.duplicate()
	core.merge({
		"id": BASE, "interval": 1.0 / float(base.shots_per_second), "attack": "bolt",
		"description": "출구에 가까운 적의 이동을 예측해 직선탄을 발사합니다.",
	}, true)
	_add(_patched(core, overrides.get(BASE, {})))
	for item: Variant in additions:
		if not item is Dictionary:
			error = "타워 정의 형식이 올바르지 않습니다."
			return
		_add(_patched(item, overrides.get(item.get("id"), {})))

static func _patched(raw: Dictionary, patch: Dictionary) -> Dictionary:
	if patch.is_empty():
		return raw
	var updated := raw.merged(patch, true)
	if updated.has("refund") and (patch.has("cost") or patch.has("refund_ratio")):
		var ratio := float(patch.get("refund_ratio", float(raw.refund) / float(raw.cost)))
		updated.refund = floori(float(updated.cost) * ratio)
	return updated

func _add(raw: Dictionary) -> void:
	var id := str(raw.get("id", ""))
	if id.is_empty() or definitions.has(id) or not ATTACK_NAMES.has(raw.get("attack")) \
			or not raw.get("name") is String or not raw.get("color") is String \
			or float(raw.get("interval", 0)) <= 0.0 or int(raw.get("cost", 0)) <= 0 \
			or float(raw.get("damage", -1)) < 0 or float(raw.get("range", -1)) < 0:
		error = "유효하지 않은 타워 정의 · " + id
		return
	var gravity_slow := float(raw.get("gravity_slow", 0.0))
	if gravity_slow < 0.0 or gravity_slow >= 1.0:
		error = "유효하지 않은 중력 둔화 비율 · " + id
		return
	var kind := int(raw.get("support", TowerSupport.Kind.NONE))
	if kind < TowerSupport.Kind.NONE or kind > TowerSupport.Kind.COMMAND or (raw.attack == "support") != (kind != TowerSupport.Kind.NONE):
		error = "유효하지 않은 지원 타워 종류 · " + id
		return
	if raw.attack == "economy":
		var role: String = raw.get("economy", "")
		var producer := role in ["credits", "rp"]
		if float(raw.damage) != 0.0 or not role in ["credits", "rp", "credit_amp", "rp_amp", "core"] \
				or (int(raw.get("production", 0)) > 0) != producer or (float(raw.range) > 0.0) == producer:
			error = "유효하지 않은 경제 타워 정의 · " + id
			return
	var def := DEFAULTS.duplicate()
	def.merge(raw, true)
	def.refund = int(raw.get("refund", floori(float(raw.cost) * float(raw.get("refund_ratio", 1.0)))))
	def.tint = Color(str(def.color))
	definitions[id] = def
	ids.append(id)

func lookup(id: String) -> Dictionary:
	return definitions.get(id, {})

static func reach_text(def: Dictionary) -> String:
	return "전장 전체" if def.global else "%s칸" % str(float(def.range)).trim_suffix(".0")

static func category(def: Dictionary) -> String:
	if not str(def.economy).is_empty():
		return "경제 타워"
	return "버프 타워" if def.support != TowerSupport.Kind.NONE else "공격 타워"

static func attacks(def: Dictionary) -> bool:
	return def.support == TowerSupport.Kind.NONE and str(def.economy).is_empty()
