class_name ResearchRun
extends RefCounted

signal changed
signal purchased(id: String, unlocked: String, advanced_stage: bool)

var graph: ResearchGraph
var _cost_percent: int
var points := 0
var total_earned := 0
var highest_stage := 0
var completed: Dictionary = {}
var unlocked: Dictionary = {TowerRegistry.BASE: true}

func _init(definitions: ResearchGraph, price_percent: int = 100, starting_rp: int = 0) -> void:
	graph = definitions
	_cost_percent = price_percent
	points = starting_rp

func cost(id: String) -> int:
	return RunConstraints.scaled(int(graph.nodes[id].cost_rp), _cost_percent)

func minimum_cost(id: String) -> int:
	return graph.minimum_cost(id, completed, _cost_percent)

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
	return &"ready" if points >= cost(id) else &"insufficient"

func purchase(id: String) -> bool:
	if state(id) != &"ready":
		return false
	var node: Dictionary = graph.nodes[id]
	points -= cost(id)
	completed[id] = true
	var tower := str(node.get("unlock", {}).get("id", ""))
	if not tower.is_empty():
		unlocked[tower] = true
	var stage := int(node.stage)
	var advanced := stage > highest_stage
	highest_stage = maxi(highest_stage, stage)
	purchased.emit(id, tower, advanced)
	changed.emit()
	return true
