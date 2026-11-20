class_name ResearchRun
extends RefCounted

signal changed
signal purchased(id: String, unlocked: String)

var graph: ResearchGraph
var points := 0
var total_earned := 0
var completed: Dictionary = {}
var unlocked: Dictionary = {TowerRegistry.BASE: true}

func _init(definitions: ResearchGraph) -> void:
	graph = definitions

func earn(amount: int) -> void:
	if amount <= 0:
		return
	points = mini(BattleData.NUMBER_LIMIT, points + amount)
	total_earned = mini(BattleData.NUMBER_LIMIT, total_earned + amount)
	changed.emit()

func state(id: String) -> StringName:
	if completed.has(id):
		return &"done"
	if not graph.nodes.has(id):
		return &"missing"
	var node: Dictionary = graph.nodes[id]
	if not ResearchGraph.satisfied(node.requirements, completed):
		return &"locked"
	return &"ready" if points >= int(node.cost_rp) else &"insufficient"

func purchase(id: String) -> bool:
	if state(id) != &"ready":
		return false
	var node: Dictionary = graph.nodes[id]
	points -= int(node.cost_rp)
	completed[id] = true
	var tower := str(node.get("unlock", {}).get("id", ""))
	if not tower.is_empty():
		unlocked[tower] = true
	purchased.emit(id, tower)
	changed.emit()
	return true
