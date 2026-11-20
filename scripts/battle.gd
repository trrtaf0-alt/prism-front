class_name Battle
extends RefCounted

signal effect(kind: StringName, point: Vector2, direction: Vector2)
signal wave_started(number: int)
signal wave_finished(number: int, reward: int)
signal defeated(number: int)
signal base_damaged(amount: int)
signal mob_visual(kind: StringName, start: Vector2, finish: Vector2, tint: Color, lifetime: float)
signal attack_visual(style: String, origin: Vector2, end: Vector2, radius: float, tint: Color, life: float, stage: int)

# All distances are measured in tiles. The display converts them to pixels.
const HIT_RADIUS := 0.21
const BARREL_LENGTH := 0.31

class Drone:
	var progress := 0.0
	var position := Vector2.ZERO
	var previous := Vector2.ZERO
	var health: int
	var flash := 0.0
	var serial := 0
	var definition: Dictionary
	var maximum_health: int
	var speed: float
	var tint: Color
	var status := StatusEffects.new()
	var mob := MobAbilities.State.new()
	var shield_hp := 0
	var shield_max := 0
	var shield_source := 0
	var shield_rearm := 0.0
	var shield_ready := 0.0
	var armor := 0.0
	var control_resist := 0.0
	var boost_bonus := 0.0
	var boost_until := 0.0
	var hidden := false
	var boss := false
	var shape := 0
	var scale := 1.0

	func give_shield(amount: int, source: int, rearm: float) -> void:
		shield_hp = amount
		shield_max = amount
		shield_source = source
		shield_rearm = rearm

class Turret:
	var cell: Vector2i
	var position: Vector2
	var angle := 0.0
	var cooldown := 0.0
	var recoil := 0.0
	var full_buckets := PackedInt32Array()
	var edge_buckets := PackedInt32Array()
	var definition: Dictionary
	var field_age := 0.0
	var mirror_timers: Dictionary = {}
	var mirror_fields: Dictionary = {}

class Bolt:
	var position: Vector2
	var direction: Vector2
	var remaining: float
	var definition: Dictionary
	var speed: float
	var origin: Vector2
	var efficiency: float
	var guided_target: Drone
	var target_serial := 0
	var reversed := false
	var hit: Dictionary = {}
	var fragment := false

var arsenal := TowerArsenal.new()
var field_diagonal: float
var research: ResearchRun
var data: BattleData
var field: FieldMap
var health: int
var credits: int
var wave := 0
var queued := 0
var active := false
var lost := false
var enemies: Array[Drone] = []
var towers: Array[Turret] = []
var bolts: Array[Bolt] = []
var occupied := {}
var bosses: Array[Drone] = []
var roster_seed := randi()

var _roster: WaveRoster
var elapsed := 0.0
var _ability_units: Array[Drone] = []
var _births: Array[Array] = []
var _mob_fx_budget := 20

var _spawn_clock := 0.0
var _buckets: Array[Array] = []
var _used_buckets: Array[int] = []
var _bucket_leaders: Array[Drone] = []
var _track_cells: Array[Vector2i] = []
var _path_buckets := PackedInt32Array()
var _path_length: float
var _drone_pool: Array[Drone] = []
var _bolt_pool: Array[Bolt] = []
var _range: float
var _drone_speed: float
var _damage: int
var _global_leader: Drone
var _serial := 0
var _impact_budget := 64
var _advanced_impact_budget := 4
var _sorted_buckets: Dictionary = {}
var _needs_cleanup := false
var _maximum_step := 0.0
var _copy_neighbors: Dictionary = {}

func _init(map: FieldMap, rules: BattleData) -> void:
	field = map
	data = rules
	research = ResearchRun.new(data.research)
	health = int(data.balance.base_health)
	credits = int(data.balance.starting_credits)
	_range = float(data.turret.range)
	_drone_speed = float(data.drone.speed)
	_damage = int(data.turret.damage)
	_path_length = field.length()
	field_diagonal = Vector2(field.size).length()
	for point in field.path:
		var cell := Vector2i(point.floor())
		_track_cells.append(cell)
		_path_buckets.append(_bucket_index(cell.x, cell.y))
	for i in field.size.x * field.size.y:
		_buckets.append([])
		_bucket_leaders.append(null)

func can_install(cell: Vector2i, id: String = TowerRegistry.BASE) -> bool:
	var definition := data.towers.lookup(id)
	return not lost and research.unlocked.has(id) and not definition.is_empty() 		and credits >= int(definition.cost) and field.tile_at(cell) == "." and not occupied.has(cell)

func install(cell: Vector2i, id: String = TowerRegistry.BASE) -> bool:
	if not can_install(cell, id):
		return false
	var tower := Turret.new()
	tower.cell = cell
	tower.position = Vector2(cell) + Vector2(0.5, 0.5)
	tower.definition = data.towers.lookup(id)
	_cache_range(tower, float(tower.definition.range))
	towers.append(tower)
	occupied[cell] = tower
	credits -= int(tower.definition.cost)
	_refresh_copies()
	effect.emit(&"install", tower.position, Vector2.ZERO)
	return true

func sell(cell: Vector2i) -> bool:
	if lost or not occupied.has(cell):
		return false
	var tower: Turret = occupied[cell]
	occupied.erase(cell)
	towers.erase(tower)
	_credit(int(tower.definition.refund))
	_refresh_copies()
	effect.emit(&"sell", tower.position, Vector2.ZERO)
	return true

func start_wave() -> bool:
	if active or lost:
		return false
	wave = mini(wave + 1, BattleData.NUMBER_LIMIT)
	active = true
	queued = data.wave_count(wave) - 1
	_spawn_clock = data.spawn_interval(wave)
	_roster = WaveRoster.new(data.mobs, wave, queued + 1, roster_seed ^ wave)
	wave_started.emit(wave)
	spawn(0.0, _roster.next())
	return true

func spawn(progress: float = 0.0, enemy_definition: Dictionary = {}) -> Drone:
	var drone: Drone = Drone.new() if _drone_pool.is_empty() else _drone_pool.pop_back()
	drone.progress = progress
	drone.position = field.position_at(progress)
	drone.previous = drone.position
	_serial += 1
	drone.serial = _serial
	drone.definition = data.drone if enemy_definition.is_empty() else enemy_definition
	drone.maximum_health = int(drone.definition.health)
	drone.health = drone.maximum_health
	drone.speed = float(drone.definition.speed)
	drone.tint = Color(str(drone.definition.color))
	drone.flash = 0.0
	drone.status.reset()
	drone.mob.reset(drone.definition, elapsed)
	drone.give_shield(int(drone.definition.get("shield", 0)), 0, 0.0)
	drone.shield_ready = 0.0
	drone.armor = float(drone.definition.get("armor", 0))
	drone.control_resist = float(drone.definition.get("control_resist", 0))
	drone.boost_bonus = 0.0
	drone.boost_until = 0.0
	drone.hidden = false
	drone.boss = bool(drone.definition.get("boss", false))
	drone.shape = maxi(0, EnemyRegistry.SHAPES.find(drone.definition.get("shape", "drone")))
	drone.scale = float(drone.definition.get("scale", 1.0))
	enemies.append(drone)
	if drone.mob.has_periodic():
		drone.mob.slot = _ability_units.size()
		_ability_units.append(drone)
	if drone.boss:
		bosses.append(drone)
		mob_effect(&"boss_spawn", drone.position, drone.position, drone.tint, 2.4, true)
	if is_zero_approx(progress):
		effect.emit(&"spawn", drone.position, field.heading_at(progress))
	return drone

func tick(delta: float) -> void:
	if lost:
		return
	elapsed += delta
	_impact_budget = 64
	_advanced_impact_budget = 4
	_mob_fx_budget = 20
	_needs_cleanup = false
	_update_drones(delta)
	_update_bolts(delta)
	if _needs_cleanup:
		_remove_drones()
	if lost:
		return
	_needs_cleanup = false
	arsenal.update(self, delta)
	_update_towers(delta)
	if _needs_cleanup:
		_remove_drones()
	for drone in _ability_units:
		MobAbilities.periodic(self, drone, elapsed)
	_flush_births()
	if queued > 0:
		_spawn_clock -= delta
		while _spawn_clock <= 0.000001 and queued > 0:
			queued -= 1
			_spawn_clock += data.spawn_interval(wave)
			spawn(0.0, _roster.next())
	if active and queued == 0 and enemies.is_empty():
		active = false
		var reward := data.wave_reward(wave)
		_credit(reward)
		wave_finished.emit(wave, reward)

func _update_drones(delta: float) -> void:
	for i in _used_buckets:
		_buckets[i].clear()
		_bucket_leaders[i] = null
	_used_buckets.clear()
	_sorted_buckets.clear()
	_global_leader = null
	_maximum_step = 0.0
	var path := field.path
	var last_segment := path.size() - 2
	for drone in enemies:
		drone.previous = drone.position
		var mob := drone.mob
		if mob.cloak_cycle > 0.0:
			drone.hidden = fposmod(elapsed - mob.spawn_at, mob.cloak_cycle) >= mob.cloak_cycle - mob.hidden_for
		if mob.acceleration > 0.0:
			drone.speed = minf(mob.speed_limit, mob.base_speed + (elapsed - mob.spawn_at) * mob.acceleration)
		if drone.boost_bonus > 0.0 and elapsed >= drone.boost_until:
			drone.boost_bonus = 0.0
		var speed := drone.speed * (1.0 + drone.boost_bonus)
		var move := speed * delta
		if drone.status.engaged:
			move = drone.status.step(drone.progress, speed, delta, data.status_rules)
		drone.progress = clampf(drone.progress + move, 0.0, _path_length)
		var segment := mini(floori(drone.progress), last_segment)
		drone.position = path[segment].lerp(path[segment + 1], drone.progress - segment)
		_maximum_step = maxf(_maximum_step, absf(move))
		drone.flash = maxf(0.0, drone.flash - delta)
		var i := _path_buckets[roundi(drone.progress)]
		if drone.health <= 0 or drone.progress >= _path_length:
			_needs_cleanup = true
		if _buckets[i].is_empty():
			_used_buckets.append(i)
		_buckets[i].append(drone)
		var leader := _bucket_leaders[i]
		if not drone.hidden and drone.progress < _path_length and (leader == null or drone.progress > leader.progress):
			_bucket_leaders[i] = drone
		if not drone.hidden and drone.health > 0 and drone.progress < _path_length and (_global_leader == null or drone.progress > _global_leader.progress):
			_global_leader = drone

func _remove_drones() -> void:
	var i := enemies.size() - 1
	while i >= 0:
		var drone := enemies[i]
		if drone.health <= 0:
			_recycle_drone(i)
		elif drone.progress >= _path_length:
			var remaining := drone.health
			health = maxi(0, health - remaining)
			base_damaged.emit(remaining)
			effect.emit(&"base", drone.position, Vector2.ZERO)
			_recycle_drone(i)
			if health == 0:
				lost = true
				active = false
				queued = 0
				effect.emit(&"collapse", drone.position, Vector2.ZERO)
				defeated.emit(wave)
				return
		i -= 1

func _recycle_drone(index: int) -> void:
	var drone := enemies[index]
	var slot := drone.mob.slot
	if slot >= 0:
		var last: Drone = _ability_units.back()
		_ability_units[slot] = last
		last.mob.slot = slot
		_ability_units.pop_back()
		drone.mob.slot = -1
	if drone.boss:
		bosses.erase(drone)
	if _drone_pool.size() < 4096:
		_drone_pool.append(drone)
	enemies[index] = enemies.back()
	enemies.pop_back()

func _update_towers(delta: float) -> void:
	for tower in towers:
		tower.recoil = maxf(0.0, tower.recoil - delta)
		tower.cooldown = maxf(0.0, tower.cooldown - delta)
		if tower.definition.attack == "copy":
			_update_copy(tower, delta)
			continue
		if enemies.is_empty():
			tower.field_age = 0.0
			continue
		var target := _select_target(tower, tower.definition, true)
		if target == null:
			tower.field_age = 0.0
			continue
		var direction := target_direction(tower, target, tower.definition, tower.cooldown <= 0.10)
		var angle := direction.angle()
		tower.angle = rotate_toward(tower.angle, angle, delta * 24.0)
		if tower.cooldown <= 0.000001:
			if tower.definition.id == TowerRegistry.BASE and absf(angle_difference(tower.angle, angle)) > 0.45:
				continue
			tower.cooldown = float(tower.definition.interval)
			tower.angle = angle
			tower.recoil = 0.12
			arsenal.attack(self, tower, target, tower.definition, direction)

func target_direction(tower: Turret, target: Drone, def: Dictionary, predict: bool) -> Vector2:
	if predict and def.attack == "bolt" and not def.guided:
		return aim_at(tower.position, target, float(def.projectile_speed))
	var direction := tower.position.direction_to(target.position)
	return Vector2.RIGHT if direction.is_zero_approx() else direction

func _refresh_copies() -> void:
	_copy_neighbors.clear()
	for tower in towers:
		if tower.definition.attack != "copy":
			continue
		var neighbors: Array[Turret] = []
		var radius := float(tower.definition.range)
		for other in towers:
			if other.definition.attack != "copy" and other.position.distance_squared_to(tower.position) <= radius * radius:
				neighbors.append(other)
		neighbors.sort_custom(func(a: Turret, b: Turret): return tower.position.distance_squared_to(a.position) < tower.position.distance_squared_to(b.position))
		neighbors.resize(mini(neighbors.size(), int(tower.definition.max_targets)))
		for prior: Variant in tower.mirror_timers.keys():
			if not neighbors.has(prior):
				tower.mirror_timers.erase(prior)
				tower.mirror_fields.erase(prior)
		_copy_neighbors[tower] = neighbors

func _update_copy(tower: Turret, delta: float) -> void:
	for other: Turret in _copy_neighbors.get(tower, []):
		var timer := maxf(0.0, float(tower.mirror_timers.get(other, 0.0)) - delta)
		tower.mirror_timers[other] = timer
		if timer > 0.000001 or enemies.is_empty():
			continue
		var def := other.definition
		var target := _select_target(tower, def, false)
		if target == null:
			tower.mirror_fields.erase(other)
			continue
		var final_weapon := int(def.stage) == 5
		var efficiency := float(tower.definition.terminal_efficiency if final_weapon else tower.definition.copy_efficiency)
		var cadence := float(tower.definition.terminal_cadence if final_weapon else tower.definition.copy_cadence)
		var override: Dictionary = tower.definition.copy_overrides.get(def.id, {})
		efficiency = float(override.get("damage", efficiency))
		cadence = float(override.get("interval", cadence))
		var direction := target_direction(tower, target, def, true)
		tower.angle = direction.angle()
		tower.recoil = 0.12
		tower.mirror_timers[other] = float(def.interval) * cadence
		attack_visual.emit("holo", tower.position, other.position, 0, tower.definition.tint, 0.25, 4)
		tower.field_age = float(tower.mirror_fields.get(other, 0.0))
		arsenal.attack(self, tower, target, def, direction, efficiency)
		if def.ramp > 0.0:
			tower.mirror_fields[other] = tower.field_age

func _select_target(tower: Turret, def: Dictionary, cached: bool) -> Drone:
	if def.get("detect_cloak", false):
		return _nearest_leading(tower.position, float(def.range), def.global, true)
	var target := _global_target() if def.global else (_target_in_range(tower) if cached else _nearest_leading(tower.position, float(def.range)))
	if target != null:
		return target
	var global_coverage: bool = def.global and (def.attack in ["strike", "singularity"] or def.attack == "multi" and def.max_targets == 0)
	var local_coverage: bool = def.center == "self" and def.attack in ["field", "pulse"]
	if global_coverage or local_coverage:
		return _nearest_leading(tower.position, float(def.range), def.global, true)
	return target

func _global_target() -> Drone:
	if not _valid(_global_leader) or _global_leader.hidden:
		_global_leader = _nearest_leading(Vector2.ZERO, 0.0, true)
	return _global_leader

func _nearest_leading(origin: Vector2, radius: float, anywhere: bool = false, detect_cloak: bool = false) -> Drone:
	var best: Drone
	for drone in query_radius(origin, radius, anywhere):
		if (detect_cloak or not drone.hidden) and (best == null or drone.progress > best.progress):
			best = drone
	return best

func _valid(drone: Drone) -> bool:
	return drone != null and drone.health > 0 and drone.progress < _path_length

func target_for(origin: Vector2) -> Drone:
	var query := Turret.new()
	query.position = origin
	query.definition = data.towers.lookup(TowerRegistry.BASE)
	_cache_range(query, _range)
	return _target_in_range(query)

func _cache_range(tower: Turret, radius: float) -> void:
	# Interior cells need only their leading drone. Boundary cells still use
	# exact circular range, including the edge itself.
	var radius_squared := radius * radius
	var half_tile := Vector2(0.5, 0.5)
	for cell in _track_cells:
		var offset := (tower.position - (Vector2(cell) + half_tile)).abs()
		var nearest := (offset - half_tile).max(Vector2.ZERO)
		var farthest := offset + half_tile
		var index := _bucket_index(cell.x, cell.y)
		if farthest.length_squared() <= radius_squared:
			tower.full_buckets.append(index)
		elif nearest.length_squared() <= radius_squared:
			tower.edge_buckets.append(index)

func _target_in_range(tower: Turret) -> Drone:
	var best: Drone
	var progress := -1.0
	for index in tower.full_buckets:
		var leader := _bucket_leaders[index]
		if leader == null or leader.progress <= progress:
			continue
		if leader.health > 0:
			best = leader
			progress = leader.progress
		else:
			for drone: Drone in _buckets[index]:
				if not drone.hidden and drone.progress > progress and drone.progress < _path_length and drone.health > 0:
					best = drone
					progress = drone.progress
	var radius_squared := pow(float(tower.definition.range), 2.0)
	for index in tower.edge_buckets:
		var leader := _bucket_leaders[index]
		if leader == null or leader.progress <= progress:
			continue
		for drone: Drone in _buckets[index]:
			if not drone.hidden and drone.progress > progress and drone.progress < _path_length and drone.health > 0 and tower.position.distance_squared_to(drone.position) <= radius_squared:
				best = drone
				progress = drone.progress
	return best

func aim_at(origin: Vector2, target: Drone, speed: float = 12.0) -> Vector2:
	# The bolt is faster than the drone, so the interception equation is monotonic,
	# even through turns. The path sampler clamps the prediction at the exit.
	var low := 0.0
	var max_drift := target.status.pull * target.status.pull_left
	var enemy_speed := target.speed * (1.0 + target.boost_bonus)
	var high := (origin.distance_to(target.position) + max_drift) / maxf(0.001, speed - enemy_speed)
	for i in 12:
		var time := (low + high) * 0.5
		var future := field.position_at(target.status.predict(target.progress, enemy_speed, time))
		if origin.distance_to(future) > BARREL_LENGTH + speed * time:
			low = time
		else:
			high = time
	var direction := origin.direction_to(field.position_at(target.status.predict(target.progress, enemy_speed, high)))
	return Vector2.RIGHT if direction.is_zero_approx() else direction

func _fire(origin: Vector2, direction: Vector2, definition: Dictionary = {}, target: Drone = null, efficiency: float = 1.0, source: Vector2 = Vector2.ZERO, show: bool = true) -> Bolt:
	var def := data.towers.lookup(TowerRegistry.BASE) if definition.is_empty() else definition
	var bolt: Bolt = Bolt.new() if _bolt_pool.is_empty() else _bolt_pool.pop_back()
	bolt.position = origin
	bolt.direction = direction
	bolt.definition = def
	bolt.speed = float(def.projectile_speed)
	var speed_margin := maxf(0.001, bolt.speed - _drone_speed)
	bolt.remaining = float(def.range) * (1.0 + _drone_speed / speed_margin) + HIT_RADIUS
	bolt.origin = source
	bolt.efficiency = efficiency
	bolt.guided_target = target if def.guided else null
	bolt.target_serial = bolt.guided_target.serial if bolt.guided_target != null else 0
	bolt.reversed = false
	bolt.hit.clear()
	bolt.fragment = false
	bolts.append(bolt)
	if show:
		if def.id == TowerRegistry.BASE:
			effect.emit(&"fire", origin, direction)
		else:
			attack_visual.emit("muzzle", origin, origin + direction, 0, def.tint, 0.13, int(def.stage))
	return bolt

func _update_bolts(delta: float) -> void:
	if delta <= 0.0:
		return
	for i in range(bolts.size() - 1, -1, -1):
		var bolt := bolts[i]
		var def := bolt.definition
		if def.guided:
			var detect: bool = def.get("detect_cloak", false)
			if not _valid(bolt.guided_target) or bolt.guided_target.serial != bolt.target_serial or (bolt.guided_target.hidden and not detect):
				bolt.guided_target = _nearest_leading(bolt.position, bolt.remaining, false, detect)
				bolt.target_serial = bolt.guided_target.serial if bolt.guided_target != null else 0
			if bolt.guided_target != null:
				var angle := bolt.position.angle_to_point(bolt.guided_target.position)
				bolt.direction = Vector2.from_angle(rotate_toward(bolt.direction.angle(), angle, delta * 12.0))
		var step := minf(bolt.speed * delta, bolt.remaining)
		var end := bolt.position + bolt.direction * step
		var hit := _collide(bolt.position, end, step / (bolt.speed * delta), delta, bolt.hit)
		var spent := hit != null
		if def.returning:
			while hit != null:
				damage(hit, def, bolt.efficiency)
				bolt.hit[hit.serial] = true
				hit = _collide(bolt.position, end, step / (bolt.speed * delta), delta, bolt.hit)
			spent = false
		elif hit != null:
			_bolt_impact(bolt, hit)
		bolt.position = end
		bolt.remaining -= step
		if def.returning and not bolt.reversed and bolt.remaining <= 0.00001:
			bolt.reversed = true
			bolt.hit.clear()
			bolt.remaining = end.distance_to(bolt.origin)
			bolt.direction = end.direction_to(bolt.origin)
			continue
		if spent or bolt.remaining <= 0.00001:
			if not spent and _impact_budget > 0:
				_impact_budget -= 1
				effect.emit(&"miss", end, bolt.direction)
			bolt.guided_target = null
			bolt.hit.clear()
			if _bolt_pool.size() < 1024:
				_bolt_pool.append(bolt)
			bolts[i] = bolts.back()
			bolts.pop_back()

func _bolt_impact(bolt: Bolt, target: Drone) -> void:
	var def := bolt.definition
	if def.radius > 0 and not bolt.fragment:
		arsenal.area(self, target.position, float(def.radius), def, bolt.efficiency)
		attack_visual.emit(def.fx, target.position, target.position, def.radius, def.tint, 0.58, int(def.stage))
		return
	damage(target, def, bolt.efficiency)
	if def.split > 0 and not bolt.fragment:
		var fragments := def.duplicate()
		fragments.damage = def.fragment_damage
		fragments.range = def.fragment_range
		var origin := target.position
		for i in int(def.split):
			var aim := Vector2.from_angle(TAU * i / float(def.split))
			var shard := _fire(origin, aim, fragments, null, bolt.efficiency, origin, false)
			shard.fragment = true
			shard.hit[target.serial] = true
		attack_visual.emit("split", origin, origin, float(def.fragment_range) * 0.55, def.tint, 0.36, int(def.stage))

func _collide(from: Vector2, to: Vector2, tick_fraction: float, delta: float, visited: Dictionary = {}) -> Drone:
	var padding := Vector2.ONE * (HIT_RADIUS + maxf(_maximum_step, _drone_speed * delta) + 0.01)
	var lo := (from.min(to) - padding).floor().max(Vector2.ZERO)
	var hi := (from.max(to) + padding).floor().min(Vector2(field.size - Vector2i.ONE))
	var first := 2.0
	var hit: Drone
	for y in range(int(lo.y), int(hi.y) + 1):
		for x in range(int(lo.x), int(hi.x) + 1):
			for drone: Drone in _buckets[_bucket_index(x, y)]:
				if drone.health <= 0 or visited.has(drone.serial):
					continue
				var offset := from - drone.previous
				var motion := to - from - (drone.position - drone.previous) * tick_fraction
				var time := sweep(offset, motion, HIT_RADIUS)
				if time >= 0.0 and time < first:
					if time == 0.0:
						return drone
					first = time
					hit = drone
	return hit

static func sweep(offset: Vector2, motion: Vector2, radius: float) -> float:
	var c := offset.length_squared() - radius * radius
	if c <= 0.0:
		return 0.0
	var a := motion.length_squared()
	var b := offset.dot(motion)
	var discriminant := b * b - a * c
	if a <= 0.0 or b >= 0.0 or discriminant < 0.0:
		return -1.0
	var time := (-b - sqrt(discriminant)) / a
	return time if time >= 0.0 and time <= 1.0 else -1.0

func _damage_drone(drone: Drone, direction: Vector2) -> void:
	_apply_damage(drone, _damage, direction)

func damage(drone: Drone, def: Dictionary, efficiency: float = 1.0, anchor: float = -1.0) -> void:
	if drone.health <= 0:
		return
	var amount := maxi(1, roundi(float(def.damage) * efficiency)) if def.damage > 0 else 0
	var control := def if def.shock or def.slow > 0 or def.pull > 0 else {}
	_apply_damage(drone, amount, Vector2.ZERO, int(def.stage) >= 2, control, anchor)

func barrage(targets: Array, def: Dictionary, efficiency: float, anchor: float = -1.0) -> void:
	var amount := maxi(1, roundi(float(def.damage) * efficiency)) if def.damage > 0 else 0
	var control := def if def.shock or def.slow > 0 or def.pull > 0 else {}
	for drone: Drone in targets:
		_apply_damage(drone, amount, Vector2.ZERO, true, control, anchor)

func _apply_damage(drone: Drone, amount: int, direction: Vector2, advanced: bool = false, control: Dictionary = {}, anchor: float = -1.0) -> void:
	if drone.health <= 0 or (amount <= 0 and control.is_empty()):
		return
	if drone.status.mark_stacks > 0:
		amount = drone.status.boosted_damage(amount)
	if drone.shield_hp > 0 and amount > 0:
		var absorbed := mini(amount, drone.shield_hp)
		drone.shield_hp -= absorbed
		amount -= absorbed
		if drone.shield_hp == 0:
			drone.shield_ready = elapsed + drone.shield_rearm
			drone.shield_source = 0
			mob_effect(&"shield_break", drone.position, drone.position, Color("#78e4ff"), 0.58)
	if amount > 0:
		drone.health -= ceili(amount * (1.0 - drone.armor)) if drone.armor > 0 else amount
	drone.flash = 0.09
	var killed := drone.health <= 0
	if killed:
		_needs_cleanup = true
		_credit(int(drone.definition.reward))
		research.earn(int(drone.definition.get("reward_rp", 0)))
		var child: String = drone.definition.get("split_to", "")
		if not child.is_empty():
			queue_birth(drone.progress, child, EnemyRegistry.SPLIT_COUNT)
			mob_effect(&"divide", drone.position, drone.position, drone.tint, 0.55)
		if drone.boss:
			mob_effect(&"boss_down", drone.position, drone.position, drone.tint, 2.1, true)
	else:
		if not control.is_empty():
			var multiplier := data.mobs.control_multiplier(drone.control_resist, drone.shield_hp > 0)
			drone.status.apply(control, data.status_rules, anchor, multiplier)
		if drone.mob.phase < drone.mob.phases.size():
			MobAbilities.advance_phase(self, drone, elapsed)
	if advanced and _advanced_impact_budget > 0:
		_advanced_impact_budget -= 1
		effect.emit(&"kill" if killed else &"hit", drone.position, direction)
	elif not advanced and _impact_budget > 0:
		_impact_budget -= 1
		effect.emit(&"kill" if killed else &"hit", drone.position, direction)

func queue_birth(progress: float, id: String, count: int) -> void:
	_births.append([progress, data.mobs.lookup(id), count])

func _flush_births() -> void:
	# Retired units can be reused after every combat and support query finished.
	for birth in _births:
		for i in int(birth[2]):
			spawn(float(birth[0]), birth[1])
	_births.clear()

func mob_effect(kind: StringName, start: Vector2, finish: Vector2, tint: Color, lifetime: float, major: bool = false) -> void:
	if major or _mob_fx_budget > 0:
		if not major:
			_mob_fx_budget -= 1
		mob_visual.emit(kind, start, finish, tint, lifetime)

func apply_support(caster: Drone, config: Dictionary, shield: bool) -> void:
	var left := int(config.targets)
	var radius := float(config.range)
	var squared := radius * radius
	var padding := Vector2.ONE * (radius + 0.00001)
	var min_cell := (caster.position - padding).floor()
	var max_cell := (caster.position + padding).floor()
	var links := 0
	var nominal := int(config.get("shield_hp", 0))
	var rearm := float(config.get("rearm", 0))
	var bonus := float(config.get("bonus", 0))
	var duration := float(config.get("duration", 0))
	for index in _used_buckets:
		var x := index % field.size.x
		var y := floori(float(index) / field.size.x)
		if x < min_cell.x or x > max_cell.x or y < min_cell.y or y > max_cell.y:
			continue
		for target: Drone in _buckets[index]:
			if target == caster or not _valid(target):
				continue
			if shield and (target.shield_hp > 0 or target.shield_ready > elapsed or not target.mob.guardian.is_empty() or target.boss):
				continue
			if not shield and target.boost_bonus > bonus and target.boost_until > elapsed:
				continue
			if caster.position.distance_squared_to(target.position) > squared:
				continue
			if shield:
				target.give_shield(nominal, caster.serial, rearm)
			else:
				target.boost_bonus = bonus
				target.boost_until = maxf(target.boost_until, elapsed + duration)
			if links < 2:
				links += 1
				mob_effect(&"grant" if shield else &"boost", caster.position, target.position, caster.tint, 0.6)
			left -= 1
			if left == 0:
				return

func query_box(first: Vector2, last: Vector2, padding: float = 0.0) -> Array[Drone]:
	var pad := Vector2.ONE * (padding + 0.00001)
	var low := (first - pad).floor().max(Vector2.ZERO)
	var high := (last + pad).floor().min(Vector2(field.size - Vector2i.ONE))
	var matches: Array[Drone] = []
	for index in _used_buckets:
		var y := floori(float(index) / field.size.x)
		var x := index % field.size.x
		if x < low.x or x > high.x or y < low.y or y > high.y:
			continue
		for drone: Drone in _buckets[index]:
			if _valid(drone):
				matches.append(drone)
	return matches

func query_radius(center: Vector2, radius: float, anywhere: bool = false) -> Array[Drone]:
	var matches: Array[Drone] = []
	if anywhere:
		for drone in enemies:
			if _valid(drone):
				matches.append(drone)
		return matches
	var squared := radius * radius
	for drone in query_box(center, center, radius):
		if drone.position.distance_squared_to(center) <= squared:
			matches.append(drone)
	return matches

func leading_targets(center: Vector2, radius: float, anywhere: bool, limit: int, detect_cloak: bool = false) -> Array[Drone]:
	if limit <= 0:
		return query_radius(center, radius, anywhere)
	var matched: Array[Drone] = []
	var squared := radius * radius
	# Each orthogonal path tile owns one non-overlapping progress interval.
	# Only the bucket crossing the selection limit needs its drones sorted.
	for step in range(_track_cells.size() - 1, -1, -1):
		var cell := _track_cells[step]
		var index := _bucket_index(cell.x, cell.y)
		var bucket := _buckets[index]
		if bucket.is_empty():
			continue
		if not anywhere and (Vector2(cell) + Vector2(0.5, 0.5)).distance_squared_to(center) > (radius + 0.72) * (radius + 0.72):
			continue
		if bucket.size() > limit - matched.size():
			if not _sorted_buckets.has(index):
				var ordered := bucket.duplicate()
				ordered.sort_custom(func(a: Drone, b: Drone): return a.progress > b.progress)
				_sorted_buckets[index] = ordered
			bucket = _sorted_buckets[index]
		for drone: Drone in bucket:
			if _valid(drone) and (detect_cloak or not drone.hidden) and (anywhere or drone.position.distance_squared_to(center) <= squared):
				matched.append(drone)
				if matched.size() == limit:
					return matched
	return matched

func nearest_in_radius(center: Vector2, radius: float, seen: Dictionary, detect_cloak: bool = false) -> Drone:
	var nearest: Drone
	var distance := INF
	for drone in query_radius(center, radius):
		var squared := drone.position.distance_squared_to(center)
		if (detect_cloak or not drone.hidden) and not seen.has(drone.serial) and squared < distance:
			nearest = drone
			distance = squared
	return nearest

func projection(point: Vector2) -> float:
	var closest := INF
	var progress := 0.0
	for i in range(field.path.size() - 1):
		var start := field.path[i]
		var direction := field.path[i + 1] - start
		var offset := point - start
		var part := clampf(offset.dot(direction), 0, 1)
		var distance := (offset - direction * part).length_squared()
		if distance < closest:
			closest = distance
			progress = i + part
	return progress

func _credit(amount: int) -> void:
	credits = mini(BattleData.NUMBER_LIMIT, credits + amount)

func _bucket_index(x: int, y: int) -> int:
	return y * field.size.x + x
