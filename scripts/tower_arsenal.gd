class_name TowerArsenal
extends RefCounted

class Sequence:
	var def: Dictionary
	var tower
	var point: Vector2
	var direction: Vector2
	var efficiency: float
	var elapsed := 0.0
	var tick_index := 0
	var hit: Dictionary = {}
	var anchor := -1.0

var sequences: Array[Sequence] = []
var _runners := {
	"bolt": _bolt, "line": _line, "chain": _chain, "strike": _strike,
	"cone": _cone, "beam": _beam, "mark": _mark, "field": _field,
	"multi": _multi, "pulse": _pulse, "singularity": _singularity,
}

func attack(sim, tower, target, def: Dictionary, direction: Vector2, efficiency: float = 1.0) -> void:
	_runners[def.attack].call(sim, tower, target, def, direction, efficiency)

func _bolt(sim, tower, target, def: Dictionary, direction: Vector2, efficiency: float) -> void:
	var spread := deg_to_rad(def.spread)
	for i in int(def.shots):
		var angle := lerpf(-spread * 0.5, spread * 0.5, float(i) / (float(def.shots) - 1.0)) if def.shots > 1 else 0.0
		var aim := direction.rotated(angle)
		sim._fire(tower.position + aim * sim.BARREL_LENGTH, aim, def, target, efficiency, tower.position, i == 0, tower)

func _beam(sim, tower, target, def: Dictionary, _direction: Vector2, efficiency: float) -> void:
	_visual(sim, def, tower.position, target.position)
	sim.damage(target, def, efficiency, -1.0, tower)

func _mark(sim, tower, target, def: Dictionary, _direction: Vector2, efficiency: float) -> void:
	target.status.mark(def, efficiency)
	_visual(sim, def, tower.position, target.position)

func _line(sim, tower, target, def: Dictionary, direction: Vector2, efficiency: float) -> void:
	if def.windup > 0:
		_stage(sim, tower, target.position, direction, def, efficiency)
		return
	_fire_line(sim, tower.position, direction, def, efficiency, tower)

func _fire_line(sim, origin: Vector2, direction: Vector2, def: Dictionary, efficiency: float, tower) -> void:
	var reach: float = sim.field_diagonal if def.global else float(def.range)
	var impact := origin + direction * reach
	var candidates: Array = sim.query_box(origin.min(impact), origin.max(impact), float(def.width))
	var hits: Array = []
	for drone in candidates:
		var offset: Vector2 = drone.position - origin
		var projection := offset.dot(direction)
		if projection >= 0.0 and projection <= reach and absf(offset.cross(direction)) <= float(def.width):
			if def.max_targets > 0:
				hits.append([projection, drone])
			else:
				sim.damage(drone, def, efficiency, -1.0, tower)
	if def.max_targets > 0:
		hits.sort_custom(func(a, b): return a[0] < b[0])
		for i in mini(hits.size(), int(def.max_targets)):
			sim.damage(hits[i][1], def, efficiency, -1.0, tower)
	_visual(sim, def, origin, impact, float(def.width), 0.6 if def.global else 0.24)

func _cone(sim, tower, _target, def: Dictionary, direction: Vector2, efficiency: float) -> void:
	var limit := cos(deg_to_rad(def.spread) * 0.5)
	for drone in sim.query_radius(tower.position, def.range):
		var normal: Vector2 = tower.position.direction_to(drone.position)
		if normal.dot(direction) >= limit:
			sim.damage(drone, def, efficiency, -1.0, tower)
	_visual(sim, def, tower.position, tower.position + direction * float(def.range), def.spread, 0.20)

func _multi(sim, tower, _target, def: Dictionary, _direction: Vector2, efficiency: float) -> void:
	var targets: Array = sim.enemies if def.global and def.max_targets == 0 else sim.leading_targets(tower.position, def.range, def.global, def.max_targets, def.get("detect_cloak", false))
	var stride := maxi(1, ceili(targets.size() / 13.0))
	for i in range(0, targets.size(), stride):
		_visual(sim, def, tower.position, targets[i].position, 0.0, 0.16)
	sim.barrage(targets, def, efficiency, -1.0, tower)

func _chain(sim, tower, target, def: Dictionary, _direction: Vector2, efficiency: float) -> void:
	if def.global:
		_storm(sim, tower.position, def, efficiency, tower)
		return
	var seen: Dictionary = {}
	var from: Vector2 = tower.position
	for i in int(def.max_targets):
		if target == null:
			break
		seen[target.serial] = true
		_visual(sim, def, from, target.position, 0.0, 0.22)
		from = target.position
		sim.damage(target, def, efficiency, -1.0, tower)
		target = sim.nearest_in_radius(from, def.jump_radius, seen, def.get("detect_cloak", false))

func _storm(sim, origin: Vector2, def: Dictionary, efficiency: float, tower) -> void:
	var pool: Array = sim.leading_targets(origin, 0.0, true, def.max_targets, def.get("detect_cloak", false))
	# Group the selected targets into spatially coherent strike columns.
	var columns: Dictionary = {}
	for drone in pool:
		var key := Vector2i(drone.position / (float(def.jump_radius) / sqrt(2.0)))
		if not columns.has(key):
			columns[key] = []
		columns[key].append(drone)
	for group: Array in columns.values():
		var previous: Vector2 = group[0].position
		_visual(sim, def, previous - Vector2(1.5, 5), previous, 0.15, 0.27)
		var stride := maxi(1, ceili(group.size() / 4.0))
		for i in group.size():
			var drone = group[i]
			if i > 0 and i % stride == 0:
				_visual(sim, def, previous, drone.position, 0.0, 0.22)
				previous = drone.position
	sim.barrage(pool, def, efficiency, -1.0, tower)

func _field(sim, tower, target, def: Dictionary, _direction: Vector2, efficiency: float) -> void:
	var center: Vector2 = tower.position if def.center == "self" else target.position
	var radius: float = def.radius
	if def.ramp > 0.0:
		tower.field_age = minf(def.ramp, tower.field_age + float(def.interval))
		radius *= lerpf(0.22, 1.0, tower.field_age / float(def.ramp))
	area(sim, center, radius, def, efficiency, -1.0, tower)
	_visual(sim, def, center, center, radius, maxf(0.24, float(def.interval) * 1.1))

func _strike(sim, tower, target, def: Dictionary, direction: Vector2, efficiency: float) -> void:
	var center: Vector2 = tower.position if def.center == "self" else target.position
	_stage(sim, tower, center, direction, def, efficiency)

func _pulse(sim, tower, _target, def: Dictionary, direction: Vector2, efficiency: float) -> void:
	_stage(sim, tower, tower.position, direction, def, efficiency)
	_visual(sim, def, tower.position, tower.position, def.radius, def.duration)

func _singularity(sim, tower, target, def: Dictionary, direction: Vector2, efficiency: float) -> void:
	_stage(sim, tower, target.position, direction, def, efficiency)
	var sequence: Sequence = sequences.back()
	sequence.anchor = sim.projection(target.position)
	_visual(sim, def, target.position, target.position, sim.field_diagonal * 0.46, def.duration)

func _stage(sim, tower, point: Vector2, direction: Vector2, def: Dictionary, efficiency: float) -> void:
	var sequence := Sequence.new()
	sequence.tower = tower
	sequence.point = point
	sequence.direction = direction
	sequence.def = def
	sequence.efficiency = efficiency
	sequences.append(sequence)
	if def.windup > 0:
		var source: Vector2 = tower.position
		_visual(sim, def, source, point, float(def.radius), def.windup, "charge_" + str(def.fx))

func update(sim, delta: float) -> void:
	for i in range(sequences.size() - 1, -1, -1):
		var seq := sequences[i]
		if not sim.occupied.has(seq.tower.cell) or sim.occupied[seq.tower.cell] != seq.tower:
			sequences.remove_at(i)
			continue
		seq.elapsed += delta
		if _step(sim, seq):
			sequences.remove_at(i)

func _step(sim, seq: Sequence) -> bool:
	var def := seq.def
	if def.attack == "pulse":
		var radius := minf(def.radius, float(def.radius) * seq.elapsed / float(def.duration))
		for drone in sim.query_radius(seq.point, radius):
			if not seq.hit.has(drone.serial):
				seq.hit[drone.serial] = true
				sim.damage(drone, def, seq.efficiency, -1.0, seq.tower)
		return seq.elapsed >= float(def.duration)
	if def.attack == "singularity":
		while seq.tick_index * float(def.tick) < float(def.duration) - 0.00001 and seq.elapsed + 0.00001 >= seq.tick_index * float(def.tick):
			area(sim, seq.point, 0.0, def, seq.efficiency, seq.anchor, seq.tower)
			seq.tick_index += 1
		if seq.elapsed + 0.00001 >= float(def.duration):
			_visual(sim, def, seq.point, seq.point, sim.field_diagonal * 0.62, 1.05, "collapse_gravity")
			return true
		return false
	if seq.elapsed + 0.00001 < float(def.windup):
		return false
	if def.attack == "line":
		_fire_line(sim, seq.tower.position, seq.direction, def, seq.efficiency, seq.tower)
	else:
		area(sim, seq.point, def.radius, def, seq.efficiency, -1.0, seq.tower)
		var reach: float = sim.field_diagonal * 0.59 if def.global else float(def.radius)
		_visual(sim, def, seq.point, seq.point, reach, 1.65 if def.global else 0.65)
	return true

func area(sim, center: Vector2, radius: float, def: Dictionary, efficiency: float, anchor: float = -1.0, tower = null) -> void:
	if def.pull > 0 and anchor < 0:
		anchor = sim.projection(center)
	var targets: Array = sim.enemies if def.global else sim.query_radius(center, radius)
	sim.barrage(targets, def, efficiency, anchor, tower)

func _visual(sim, def: Dictionary, start: Vector2, end: Vector2, width: float = 0.0, life: float = 0.25, style: String = "") -> void:
	var name := str(def.fx) if style.is_empty() else style
	sim.attack_visual.emit(name, start, end, width, def.tint, life, int(def.stage))
