class_name TowerSupport
extends RefCounted

enum Kind { NONE, TACTICAL, AIM, RESONANCE, OVERDRIVE, QUANTUM, COMMAND }
const DAMAGE_CAP := 2.25
const SPEED_CAP := 1.9
const QUANTUM_PERIOD := 2.0
const SYNC_PERIOD := 15.0
const SYNC_DURATION := 5.0
const QUANTUM_SHARE := 0.40
const DAMAGE := {Kind.RESONANCE: 1.25, Kind.OVERDRIVE: 1.4, Kind.COMMAND: 1.2}
const SPEED := {Kind.TACTICAL: 1.15, Kind.OVERDRIVE: 1.3, Kind.COMMAND: 1.15}
const SYNC_SPEED := 1.20
const AIM_RANGE := 1.25

var sources: Dictionary = {}
var linked: Dictionary = {}
var command
var command_time := 0.0
var synchronized := false
var _visual_hits := 0

func rebuild(sim) -> void:
	sources.clear()
	var attacks: Array = []
	var supports: Array = []
	for tower in sim.towers:
		if tower.definition.support == Kind.NONE:
			attacks.append(tower)
		else:
			supports.append(tower)
			sources[tower] = []
	var had_command := command != null
	command = null
	var assignments := {}
	for tower in attacks:
		assignments[tower] = {}
	for source in supports:
		var kind: int = source.definition.support
		if kind == Kind.COMMAND and command == null:
			command = source
		var radius_sq := float(source.definition.range) ** 2
		var eligible: Array = []
		for tower in attacks:
			if kind == Kind.AIM and tower.definition.global:
				continue
			if source.definition.global or source.position.distance_squared_to(tower.position) <= radius_sq:
				eligible.append(tower)
		if kind == Kind.QUANTUM and eligible.size() < 2:
			continue
		for tower in eligible:
			if assignments[tower].has(kind):
				continue
			assignments[tower][kind] = source
			sources[source].append(tower)
	if command == null or not had_command:
		command_time = 0.0
		synchronized = false
	var next_linked := {}
	for tower in attacks:
		var next: Dictionary = assignments[tower]
		for kind: int in next:
			if not tower.buffs.has(kind):
				sim.support_visual.emit(&"gain", kind, next[kind].position, tower.position)
		for kind: int in tower.buffs:
			if not next.has(kind):
				sim.support_visual.emit(&"lose", kind, tower.position, tower.position)
		tower.buffs = next
		_update_modifiers(sim, tower)
		if next.has(Kind.QUANTUM):
			next_linked[tower] = linked.get(tower, {"time": 0.0, "hits": {}})
	linked = next_linked

func _update_modifiers(sim, tower) -> void:
	var damage := 1.0
	var speed := 1.0
	for kind: int in tower.buffs:
		damage *= float(DAMAGE.get(kind, 1.0))
		speed *= float(SPEED.get(kind, 1.0))
	if synchronized and tower.buffs.has(Kind.COMMAND):
		speed *= SYNC_SPEED
	tower.damage_multiplier = minf(DAMAGE_CAP, damage)
	tower.speed_multiplier = minf(SPEED_CAP, speed)
	var boosted_range: bool = tower.buffs.has(Kind.AIM)
	var range_multiplier := AIM_RANGE if boosted_range else 1.0
	if tower.range_multiplier == range_multiplier:
		return
	tower.range_multiplier = range_multiplier
	tower.effective = tower.definition
	if boosted_range:
		tower.effective = tower.definition.duplicate()
		tower.effective.range *= range_multiplier
		if tower.effective.center == "self" and tower.effective.attack in ["field", "pulse"]:
			tower.effective.radius *= range_multiplier
	sim._cache_range(tower, float(tower.effective.range))

func tick(sim, delta: float) -> void:
	_visual_hits = 12
	if command != null and (sim.active or not sim.enemies.is_empty()):
		var previous := synchronized
		command_time += delta
		synchronized = command_time + 0.000001 >= SYNC_PERIOD and fposmod(command_time + 0.000001, SYNC_PERIOD) < SYNC_DURATION
		if previous != synchronized:
			for tower in sources[command]:
				_update_modifiers(sim, tower)
			sim.support_visual.emit(&"sync" if synchronized else &"lose", Kind.COMMAND, command.position, command.position)
	for tower in linked:
		var record: Dictionary = linked[tower]
		record.time += delta
		if record.time + 0.000001 < QUANTUM_PERIOD:
			continue
		record.time = maxf(0.0, record.time - QUANTUM_PERIOD)
		var best
		var highest := 0
		for serial in record.hits:
			var entry: Array = record.hits[serial]
			var target = entry[0]
			if target.serial == serial and sim._valid(target) and int(entry[1]) > highest:
				best = target
				highest = int(entry[1])
		record.hits.clear()
		var extra := roundi(highest * QUANTUM_SHARE)
		if best != null and extra > 0:
			sim.support_visual.emit(&"quantum", Kind.QUANTUM, tower.position, best.position)
			sim._apply_damage(best, extra, Vector2.ZERO, true, {}, null, true)

func note_damage(sim, tower, drone, amount: int) -> void:
	if amount <= 0 or tower == null:
		return
	if linked.has(tower):
		var hits: Dictionary = linked[tower].hits
		if hits.has(drone.serial):
			hits[drone.serial][1] += amount
		else:
			hits[drone.serial] = [drone, amount]
	if _visual_hits > 0 and tower.buffs.has(Kind.RESONANCE):
		_visual_hits -= 1
		sim.support_visual.emit(&"impact", Kind.RESONANCE, drone.position, drone.position)

func followers(source) -> Array:
	return sources.get(source, [])

func time_to_sync() -> float:
	var phase := fposmod(command_time + 0.000001, SYNC_PERIOD)
	return maxf(0.0, (SYNC_DURATION if synchronized else SYNC_PERIOD) - phase)

func time_to_quantum(tower) -> float:
	return QUANTUM_PERIOD - float(linked.get(tower, {}).get("time", 0.0))
