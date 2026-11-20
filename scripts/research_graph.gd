class_name ResearchGraph
extends RefCounted

const ZONES := ["허브", "1단계", "2단계", "3단계", "4단계", "5단계"]
const LANES := ["탄도 · 관통", "연사 · 다중", "에너지 · 전기", "광역 · 폭발", "제어 · 지원"]
const COLORS := ["#f5c078", "#6ddfc4", "#7dcaff", "#ff9a9c", "#c9a9ff"]

var nodes: Dictionary = {}
var ids: Array[String] = []
var ordered: Array[String] = []
var parents: Dictionary = {}
var children: Dictionary = {}
var unlocks: Dictionary = {}
var error := ""

func _init(entries: Array, towers: TowerRegistry) -> void:
	if entries.is_empty():
		error = "연구 데이터를 읽을 수 없습니다."
		return
	for item: Variant in entries:
		if not item is Dictionary or not item.get("id") is String 				or item.id.is_empty() or nodes.has(item.id):
			error = "연구 ID가 비어 있거나 중복되었습니다."
			return
		var stage := int(item.get("stage", -1))
		var lane := int(item.get("lane", -1))
		var pos: Variant = item.get("position")
		if stage < 0 or stage >= ZONES.size() or lane < 0 or lane >= LANES.size() 				or not pos is Array or pos.size() != 2 or float(item.get("cost_rp", 0)) < 1:
			error = "연구 속성이 올바르지 않습니다 · " + item.id
			return
		nodes[item.id] = item
		ids.append(item.id)
		children[item.id] = []
	for id in ids:
		var item: Dictionary = nodes[id]
		var refs: Dictionary = {}
		var requirement: Variant = item.get("requirements")
		if not item.has("requirements") or (requirement == null and int(item.stage) > 0) or not _read_requirements(requirement, id, refs, true):
			error = "잘못된 연구 선행 조건 · " + id
			return
		parents[id] = refs.keys()
		for parent: String in parents[id]:
			children[parent].append(id)
		if item.has("unlock"):
			var unlock: Variant = item.unlock
			if not unlock is Dictionary or unlock.get("type") != "tower":
				error = "알 수 없는 연구 보상 · " + id
				return
			var tower_id := str(unlock.get("id", ""))
			var def := towers.lookup(tower_id)
			if tower_id == TowerRegistry.BASE or def.is_empty() or unlocks.has(tower_id) or def.research_id != id:
				error = "중복 또는 잘못된 타워 해금 · " + id
				return
			unlocks[tower_id] = id
	for tower_id in towers.ids:
		if tower_id != TowerRegistry.BASE and not unlocks.has(tower_id):
			error = "타워 해금 연구가 없습니다 · " + tower_id
			return
	var left: Dictionary = {}
	var queue: Array[String] = []
	for id in ids:
		left[id] = parents[id].size()
		if left[id] == 0:
			queue.append(id)
	var reachable: Dictionary = {}
	for i in ids.size():
		if i >= queue.size():
			error = "연구 순환 의존성 또는 접근할 수 없는 노드가 있습니다."
			return
		var id := queue[i]
		if not satisfied(nodes[id].requirements, reachable):
			error = "접근할 수 없는 연구 · " + id
			return
		reachable[id] = true
		ordered.append(id)
		for child: String in children[id]:
			left[child] -= 1
			if left[child] == 0:
				queue.append(child)

func _read_requirements(expr: Variant, id: String, refs: Dictionary, root: bool = false) -> bool:
	if expr == null:
		return root
	if expr is String:
		if expr == id or not nodes.has(expr):
			return false
		refs[expr] = true
		return true
	if not expr is Dictionary or expr.size() != 1:
		return false
	var op: String = expr.keys()[0]
	if op not in ["all", "any"] or not expr[op] is Array or expr[op].is_empty():
		return false
	for term: Variant in expr[op]:
		if not _read_requirements(term, id, refs):
			return false
	return true

static func satisfied(expr: Variant, completed: Dictionary) -> bool:
	if expr == null:
		return true
	if expr is String:
		return completed.has(expr)
	if expr.has("all"):
		for term: Variant in expr.all:
			if not satisfied(term, completed):
				return false
		return true
	for term: Variant in expr.any:
		if satisfied(term, completed):
			return true
	return false

func point(id: String) -> Vector2:
	var coords: Array = nodes[id].position
	return Vector2(coords[0], coords[1])

func requirement_text(expr: Variant, completed: Dictionary) -> String:
	if expr == null:
		return "선행 연구 없음"
	if expr is String:
		return "%s %s" % ["✓" if completed.has(expr) else "○", nodes[expr].name]
	var all: bool = expr.has("all")
	var terms: PackedStringArray = []
	for term: Variant in (expr.all if all else expr.any):
		terms.append(requirement_text(term, completed))
	return "(%s)" % (" AND " if all else " OR ").join(terms)

func ancestors(id: String) -> Dictionary:
	var found: Dictionary = {}
	var pending: Array = parents.get(id, []).duplicate()
	while not pending.is_empty():
		var next: String = pending.pop_back()
		if not found.has(next):
			found[next] = true
			pending.append_array(parents[next])
	return found

func minimum_cost(id: String, completed: Dictionary = {}) -> int:
	var memo: Dictionary = {}
	var best := BattleData.NUMBER_LIMIT
	for plan: Dictionary in _plans(id, completed, memo):
		var cost := 0
		for step: String in plan:
			cost += int(nodes[step].cost_rp)
		best = mini(best, cost)
	return best

# Keep alternative node sets until joining branches. Shared prerequisites are paid once.
func _plans(expr: Variant, completed: Dictionary, memo: Dictionary) -> Array[Dictionary]:
	if expr == null:
		return [{}]
	if expr is String:
		if completed.has(expr):
			return [{}]
		if memo.has(expr):
			return memo[expr]
		var paths: Array[Dictionary] = []
		for incoming in _plans(nodes[expr].requirements, completed, memo):
			var plan := incoming.duplicate()
			plan[expr] = true
			paths.append(plan)
		memo[expr] = paths
		return paths
	var plans: Array[Dictionary] = []
	if expr.has("any"):
		for alternative: Variant in expr.any:
			for plan in _plans(alternative, completed, memo):
				_add_plan(plans, plan)
		return plans
	plans.append({})
	for term: Variant in expr.all:
		var combined: Array[Dictionary] = []
		var choices := _plans(term, completed, memo)
		for base in plans:
			for choice in choices:
				var plan := base.duplicate()
				plan.merge(choice)
				_add_plan(combined, plan)
		plans = combined
	return plans

static func _add_plan(plans: Array[Dictionary], option: Dictionary) -> void:
	for plan in plans:
		if _includes(option, plan):
			return
	for i in range(plans.size() - 1, -1, -1):
		if _includes(plans[i], option):
			plans.remove_at(i)
	plans.append(option)

static func _includes(large: Dictionary, small: Dictionary) -> bool:
	if large.size() < small.size():
		return false
	for key in small:
		if not large.has(key):
			return false
	return true
