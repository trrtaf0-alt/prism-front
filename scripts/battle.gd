class_name Battle
extends RefCounted

signal effect(kind: StringName, point: Vector2, direction: Vector2)
signal tower_installed(stage: int, support: int)
signal wave_started(number: int)
signal wave_finished(number: int, reward: int)
signal defeated(number: int)
signal cleared(result: Dictionary)
signal base_damaged(amount: int)
signal support_visual(event: StringName, kind: int, start: Vector2, finish: Vector2)
signal mob_visual(kind: StringName, start: Vector2, finish: Vector2, tint: Color, lifetime: float)
signal attack_visual(style: String, origin: Vector2, end: Vector2, radius: float, tint: Color, life: float, stage: int)

enum Placement { READY, OUTSIDE, OCCUPIED, TERRAIN, LOCKED, LIMIT, FUNDS, ENDED }

# All distances are measured in tiles. The display converts them to pixels.
const HIT_RADIUS := 0.21
const BARREL_LENGTH := 0.31
const ESCORT_SHIELD_SOURCE := -1

class Drone:
	var progress := 0.0
	var position := Vector2.ZERO
	var previous := Vector2.ZERO
	var exit_fraction := -1.0
	var bucket := -1
	var bucket_slot := -1
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
	var motion_skill := false
	var phase_pending := false
	var boss := false
	var primary := false
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
	var target_radius_squared := 0.0
	var definition: Dictionary
	var effective: Dictionary
	var buffs: Dictionary = {}
	var damage_multiplier := 1.0
	var speed_multiplier := 1.0
	var range_multiplier := 1.0
	var damage_remainder := 0.0
	var field_age := 0.0

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
	var owner: Turret

var support := TowerSupport.new()
var arsenal := TowerArsenal.new()
var field_diagonal: float
var research: ResearchRun
var constraints: RunConstraints
var _tower_prices: Dictionary = {}
var _tower_limit: int
var _credit_percent: int
var _rp_percent: int
var _credit_remainder := 0
var _rp_remainder := 0
var data: BattleData
var field: FieldMap
var health: int
var credits: int
var wave := 0
var queued := 0
var active := false
var lost := false
var won := false
var boss_killed := false
var boss_escaped := false
var finale_started := 0.0
var finale_boss_time := 0.0
var finale_last_spawn := 0.0
var escorts_waiting_at_boss_kill := 0
var difficulty: StringName
var primary_spawned := 0
var total_kills := 0
var total_credits := 0
var total_installs := 0
var terminal_used: Dictionary = {}
var enemies: Array[Drone] = []
var towers: Array[Turret] = []
var bolts: Array[Bolt] = []
var occupied := {}
var bosses: Array[Drone] = []
var roster_seed := randi()

var _roster: WaveRoster
var _escort_shield := 0
var _wave_enemies: Dictionary = {}
var _rp_multiplier := 1.0
var _interval := 0.5
var elapsed := 0.0
var _ability_units: Array[Drone] = []
var _births: Array[Array] = []
var _mob_fx_budget := 20

var _spawn_clock := 0.0
var _buckets: Array[Array] = []
var _used_buckets: Array[int] = []
var _used_slots := PackedInt32Array()
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
var _needs_cleanup := false
var _maximum_step := 0.0

func _init(map: FieldMap, rules: BattleData, mode: StringName = &"easy", levels: Dictionary = {}, starting_funds: int = -1) -> void:
	field = map
	data = rules
	difficulty = mode if BattleData.DIFFICULTIES.has(mode) else &"easy"
	constraints = RunConstraints.new(levels, starting_funds, int(data.balance.starting_credits))
	research = ResearchRun.new(data.research, constraints.value(&"research_price"))
	_tower_limit = constraints.value(&"tower_limit")
	_credit_percent = constraints.value(&"credits")
	_rp_percent = constraints.value(&"rp")
	health = int(data.balance.base_health)
	credits = constraints.starting_funds
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
		_used_slots.append(-1)

func tower_definition(id: String) -> Dictionary:
	var definition := data.towers.lookup(id)
	if definition.is_empty() or constraints.value(&"tower_price") == 100:
		return definition
	if not _tower_prices.has(id):
		var priced := definition.duplicate()
		priced.cost = RunConstraints.scaled(int(definition.cost), constraints.value(&"tower_price"))
		var refund_ratio := float(definition.get("refund_ratio", float(definition.refund) / float(definition.cost)))
		priced.refund = floori(float(priced.cost) * refund_ratio)
		_tower_prices[id] = priced
	return _tower_prices[id]

func tower_limit() -> int:
	return _tower_limit

func at_tower_limit() -> bool:
	return _tower_limit > 0 and towers.size() >= _tower_limit

func placement_status(cell: Vector2i, id: String) -> Placement:
	if lost or won:
		return Placement.ENDED
	if not field.contains(cell):
		return Placement.OUTSIDE
	if occupied.has(cell):
		return Placement.OCCUPIED
	if field.tile_at(cell) != ".":
		return Placement.TERRAIN
	var definition := tower_definition(id)
	if definition.is_empty() or not research.unlocked.has(id):
		return Placement.LOCKED
	if at_tower_limit():
		return Placement.LIMIT
	return Placement.READY if credits >= int(definition.cost) else Placement.FUNDS

func can_install(cell: Vector2i, id: String = TowerRegistry.BASE) -> bool:
	return placement_status(cell, id) == Placement.READY

func install(cell: Vector2i, id: String = TowerRegistry.BASE) -> bool:
	if not can_install(cell, id):
		return false
	var tower := Turret.new()
	tower.cell = cell
	tower.position = Vector2(cell) + Vector2(0.5, 0.5)
	tower.definition = tower_definition(id)
	tower.effective = tower.definition
	_cache_range(tower, float(tower.definition.range))
	towers.append(tower)
	occupied[cell] = tower
	credits -= int(tower.definition.cost)
	total_installs += 1
	if int(tower.definition.stage) == 5 and tower.definition.support == TowerSupport.Kind.NONE:
		terminal_used[id] = tower.definition.name
	support.rebuild(self)
	effect.emit(&"install", tower.position, Vector2.ZERO)
	tower_installed.emit(int(tower.definition.stage), int(tower.definition.support))
	return true

func sell(cell: Vector2i) -> bool:
	if lost or won or not occupied.has(cell):
		return false
	var tower: Turret = occupied[cell]
	occupied.erase(cell)
	towers.erase(tower)
	if tower.definition.support == TowerSupport.Kind.NONE:
		tower.buffs.clear()
		tower.damage_multiplier = 1.0
	support.rebuild(self)
	_credit(int(tower.definition.refund))
	effect.emit(&"sell", tower.position, Vector2.ZERO)
	return true

func preview_wave() -> Dictionary:
	var number := wave + 1
	if number > BattleData.FINAL_WAVE:
		return {}
	if number == BattleData.FINAL_WAVE:
		return {"boss": 1}
	var count := data.wave_count(number)
	var preview := WaveRoster.new(data.mobs, number, count, roster_seed ^ number)
	var counts := {}
	for i in count:
		var id: String = preview.next().id
		counts[id] = int(counts.get(id, 0)) + 1
	return counts

func start_wave() -> bool:
	if active or lost or won or wave >= BattleData.FINAL_WAVE:
		return false
	wave += 1
	active = true
	primary_spawned = 0
	_wave_enemies.clear()
	queued = data.wave_count(wave)
	_rp_multiplier = data.slot_rp_multiplier(wave)
	_interval = data.spawn_interval(wave)
	_spawn_clock = _interval
	_escort_shield = data.escort_shield(wave, difficulty, constraints)
	var escort: Dictionary = data.balance.escorts if _escort_shield > 0 else {}
	_roster = WaveRoster.new(data.mobs, wave, queued, roster_seed ^ wave, escort)
	if wave == BattleData.FINAL_WAVE:
		finale_started = elapsed
	wave_started.emit(wave)
	_spawn_primary(1.0)
	return true

func _spawn_primary(elite_weight: float) -> void:
	var drone := spawn(0.0, _wave_enemy(_roster.next(elite_weight)))
	drone.primary = true
	if _roster.in_escort and drone.shield_hp < _escort_shield:
		drone.give_shield(_escort_shield, ESCORT_SHIELD_SOURCE, 0.0)
	primary_spawned += 1
	queued -= 1

func _dispatch(delta: float) -> void:
	_spawn_clock -= delta
	while _spawn_clock <= 0.000001 and queued > 0:
		if wave == BattleData.FINAL_WAVE:
			var phase := bosses[0].mob.phase if not bosses.is_empty() else 2
			var escorts := primary_spawned - 1
			var stage := mini(2, maxi(phase, int(escorts >= 180) + int(escorts >= 495)))
			_spawn_primary(float(data.balance.finale_elite[stage]))
			finale_last_spawn = elapsed + _spawn_clock - finale_started
		else:
			_spawn_primary(1.0)
		_spawn_clock += _interval

func _wave_enemy(definition: Dictionary) -> Dictionary:
	var id: String = definition.id
	if not _wave_enemies.has(id):
		_wave_enemies[id] = data.enemy_for_wave(definition, wave, difficulty, constraints)
	return _wave_enemies[id]

func spawn(progress: float = 0.0, enemy_definition: Dictionary = {}) -> Drone:
	var drone: Drone = Drone.new() if _drone_pool.is_empty() else _drone_pool.pop_back()
	drone.progress = progress
	drone.position = field.position_at(progress)
	drone.previous = drone.position
	drone.exit_fraction = -1.0
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
	drone.motion_skill = drone.mob.cloak_cycle > 0.0 or drone.mob.acceleration > 0.0
	drone.phase_pending = not drone.mob.phases.is_empty()
	drone.give_shield(int(drone.definition.get("shield", 0)), 0, 0.0)
	drone.shield_ready = 0.0
	drone.armor = float(drone.definition.get("armor", 0))
	drone.control_resist = float(drone.definition.get("control_resist", 0))
	drone.boost_bonus = 0.0
	drone.boost_until = 0.0
	drone.hidden = false
	drone.boss = bool(drone.definition.get("boss", false))
	drone.primary = false
	drone.shape = maxi(0, EnemyRegistry.SHAPES.find(drone.definition.get("shape", "drone")))
	drone.scale = float(drone.definition.get("scale", 1.0))
	enemies.append(drone)
	_add_to_bucket(drone, _path_buckets[clampi(roundi(progress), 0, _path_buckets.size() - 1)])
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
	if lost or won:
		return
	elapsed += delta
	_impact_budget = 64
	_advanced_impact_budget = 4
	_mob_fx_budget = 20
	_needs_cleanup = false
	support.tick(self, delta)
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
		_dispatch(delta)
	if active and queued == 0 and enemies.is_empty():
		_finish_wave()

func _finish_wave() -> void:
	active = false
	var final := wave == BattleData.FINAL_WAVE
	if final and (not boss_killed or health <= 0):
		lost = true
		defeated.emit(wave)
		return
	var reward := _award_credits(data.wave_reward(wave))
	won = final
	wave_finished.emit(wave, reward)
	if won:
		cleared.emit(clear_record())

func clear_record() -> Dictionary:
	return {
		"wave": wave, "difficulty": str(difficulty), "seconds": elapsed, "finale": elapsed - finale_started,
		"health": health, "kills": total_kills, "credits": total_credits,
		"research": research.completed.size(), "installed": total_installs,
		"terminal": terminal_used.values(),
	}

func _update_drones(delta: float) -> void:
	_bucket_leaders.fill(null)
	_global_leader = null
	_maximum_step = 0.0
	var path := field.path
	var last_segment := path.size() - 2
	for drone in enemies:
		drone.previous = drone.position
		if drone.motion_skill:
			var mob := drone.mob
			var age := elapsed - mob.spawn_at
			if mob.cloak_cycle > 0.0:
				drone.hidden = fposmod(age, mob.cloak_cycle) >= mob.cloak_cycle - mob.hidden_for
			if mob.acceleration > 0.0:
				drone.speed = minf(mob.speed_limit, mob.base_speed + age * mob.acceleration)
		var speed := drone.speed
		if drone.boost_bonus > 0.0:
			if elapsed >= drone.boost_until:
				drone.boost_bonus = 0.0
			else:
				speed *= 1.0 + drone.boost_bonus
		var move := speed * delta
		if drone.status.engaged:
			move = drone.status.step(speed, delta, data.status_rules)
		var previous_progress := drone.progress
		drone.progress = clampf(previous_progress + move, 0.0, _path_length)
		if drone.progress >= _path_length:
			drone.exit_fraction = clampf((_path_length - previous_progress) / move, 0.0, 1.0) if move > 0.0 else 0.0
		var segment := mini(floori(drone.progress), last_segment)
		drone.position = path[segment].lerp(path[segment + 1], drone.progress - segment)
		_maximum_step = maxf(_maximum_step, absf(move))
		drone.flash = maxf(0.0, drone.flash - delta)
		var i := _path_buckets[roundi(drone.progress)]
		if drone.health <= 0 or drone.progress >= _path_length:
			_needs_cleanup = true
		if i != drone.bucket:
			_leave_bucket(drone)
			_add_to_bucket(drone, i)

func _add_to_bucket(drone: Drone, index: int) -> void:
	var bin := _buckets[index]
	if bin.is_empty():
		_used_slots[index] = _used_buckets.size()
		_used_buckets.append(index)
	drone.bucket = index
	drone.bucket_slot = bin.size()
	bin.append(drone)

func _leave_bucket(drone: Drone) -> void:
	var index := drone.bucket
	var bin := _buckets[index]
	var last: Drone = bin.back()
	last.bucket_slot = drone.bucket_slot
	bin[drone.bucket_slot] = last
	bin.pop_back()
	_bucket_leaders[index] = null
	if bin.is_empty():
		var slot := _used_slots[index]
		var final_index: int = _used_buckets.back()
		_used_buckets[slot] = final_index
		_used_slots[final_index] = slot
		_used_buckets.pop_back()
		_used_slots[index] = -1

func _remove_drones() -> void:
	var i := enemies.size() - 1
	while i >= 0:
		var drone := enemies[i]
		if drone.health <= 0:
			_recycle_drone(i)
		elif drone.progress >= _path_length:
			var remaining := drone.health
			if drone.primary and drone.boss and wave == BattleData.FINAL_WAVE:
				boss_escaped = true
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
	_leave_bucket(drone)
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
		if tower.definition.support != TowerSupport.Kind.NONE:
			continue
		tower.recoil = maxf(0.0, tower.recoil - delta)
		var due := tower.cooldown - delta * tower.speed_multiplier
		var cadence_carry := minf(0.0, due) if tower.cooldown > 0.0 and tower.speed_multiplier > 1.0 else 0.0
		tower.cooldown = maxf(0.0, due)
		if enemies.is_empty():
			tower.field_age = 0.0
			continue
		if tower.definition.id != TowerRegistry.BASE and tower.cooldown > 0.12 and tower.definition.ramp <= 0.0:
			continue
		var target := _select_target(tower, tower.effective, true)
		if target == null:
			tower.field_age = 0.0
			continue
		var direction := target_direction(tower, target, tower.definition, tower.cooldown <= 0.10)
		var angle := direction.angle()
		tower.angle = rotate_toward(tower.angle, angle, delta * 24.0)
		if tower.cooldown <= 0.000001:
			if tower.definition.id == TowerRegistry.BASE and absf(angle_difference(tower.angle, angle)) > 0.45:
				continue
			tower.cooldown = maxf(float(tower.definition.interval) + cadence_carry, _sequence_span(tower.effective) * tower.speed_multiplier)
			tower.angle = angle
			tower.recoil = 0.12
			arsenal.attack(self, tower, target, tower.effective, direction)

static func _sequence_span(def: Dictionary) -> float:
	return maxf(float(def.windup), float(def.duration))

func target_direction(tower: Turret, target: Drone, def: Dictionary, predict: bool) -> Vector2:
	if predict and def.attack == "bolt" and not def.guided:
		return aim_at(tower.position, target, float(def.projectile_speed))
	var direction := tower.position.direction_to(target.position)
	return Vector2.RIGHT if direction.is_zero_approx() else direction

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
	if _valid(_global_leader) and not _global_leader.hidden:
		return _global_leader
	for i in range(_path_buckets.size() - 1, -1, -1):
		var leader := _visible_leader(_path_buckets[i])
		if leader != null:
			_global_leader = leader
			return leader
	return null

func _visible_leader(index: int) -> Drone:
	var lead := _bucket_leaders[index]
	if _valid(lead) and not lead.hidden:
		return lead
	var progress := -1.0
	lead = null
	for drone: Drone in _buckets[index]:
		if not drone.hidden and drone.health > 0 and drone.progress < _path_length and drone.progress > progress:
			progress = drone.progress
			lead = drone
	_bucket_leaders[index] = lead
	return lead

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
	tower.full_buckets.clear()
	tower.edge_buckets.clear()
	var radius_squared := radius * radius
	tower.target_radius_squared = radius_squared
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
		var leader := _visible_leader(index)
		if leader != null and leader.progress > progress:
			best = leader
			progress = leader.progress
	var radius_squared := tower.target_radius_squared
	for index in tower.edge_buckets:
		var leader := _bucket_leaders[index]
		if leader != null and leader.progress <= progress:
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
	var enemy_speed := target.speed * (1.0 + target.boost_bonus)
	var high := origin.distance_to(target.position) / maxf(0.001, speed - enemy_speed)
	for i in 12:
		var time := (low + high) * 0.5
		var future := field.position_at(target.status.predict(target.progress, enemy_speed, time))
		if origin.distance_to(future) > BARREL_LENGTH + speed * time:
			low = time
		else:
			high = time
	var direction := origin.direction_to(field.position_at(target.status.predict(target.progress, enemy_speed, high)))
	return Vector2.RIGHT if direction.is_zero_approx() else direction

func _fire(origin: Vector2, direction: Vector2, definition: Dictionary = {}, target: Drone = null, efficiency: float = 1.0, source: Vector2 = Vector2.ZERO, show: bool = true, owner: Turret = null) -> Bolt:
	var def := data.towers.lookup(TowerRegistry.BASE) if definition.is_empty() else definition
	var bolt: Bolt = Bolt.new() if _bolt_pool.is_empty() else _bolt_pool.pop_back()
	bolt.position = origin
	bolt.direction = direction
	bolt.definition = def
	bolt.speed = float(def.projectile_speed)
	var enemy_speed := _drone_speed
	if target != null:
		enemy_speed = maxf(enemy_speed, target.speed * (1.0 + target.boost_bonus))
	var speed_margin := maxf(0.001, bolt.speed - enemy_speed)
	bolt.remaining = float(def.range) * (1.0 + enemy_speed / speed_margin) + HIT_RADIUS
	bolt.origin = source
	bolt.efficiency = efficiency
	bolt.owner = owner
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
			var style := "muzzle"
			if def.guided:
				style = "missile_launch"
			elif def.returning:
				style = "return_launch"
			elif def.split > 0:
				style = "phase_launch"
			elif def.slow > 0:
				style = "cryogenic_launch"
			elif def.shots > 1:
				style = "scatter_launch"
			attack_visual.emit(style, origin, origin + direction, def.spread, def.tint, 0.17, int(def.stage))
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
				damage(hit, def, bolt.efficiency, bolt.owner)
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
			bolt.owner = null
			bolt.hit.clear()
			if _bolt_pool.size() < 1024:
				_bolt_pool.append(bolt)
			bolts[i] = bolts.back()
			bolts.pop_back()

func _bolt_impact(bolt: Bolt, target: Drone) -> void:
	var def := bolt.definition
	if def.radius > 0 and not bolt.fragment:
		arsenal.area(self, target.position, float(def.radius), def, bolt.efficiency, bolt.owner)
		attack_visual.emit(def.fx, target.position, target.position, def.radius, def.tint, 0.58, int(def.stage))
		return
	damage(target, def, bolt.efficiency, bolt.owner)
	if def.split > 0 and not bolt.fragment:
		var fragments := def.duplicate()
		fragments.damage = def.fragment_damage
		fragments.range = def.fragment_range
		var origin := target.position
		for i in int(def.split):
			var aim := Vector2.from_angle(TAU * i / float(def.split))
			var shard := _fire(origin, aim, fragments, null, bolt.efficiency, origin, false, bolt.owner)
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
				var end_time := drone.exit_fraction
				if end_time == 0.0:
					continue
				var offset := from - drone.previous
				var speed_fraction := tick_fraction / end_time if end_time > 0.0 else tick_fraction
				var motion := to - from - (drone.position - drone.previous) * speed_fraction
				var time := sweep(offset, motion, HIT_RADIUS)
				if time >= 0.0 and time < first and (end_time < 0.0 or time * tick_fraction < end_time):
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

func damage(drone: Drone, def: Dictionary, efficiency: float = 1.0, owner: Turret = null) -> void:
	if drone.health <= 0:
		return
	var amount := _scaled_damage(def, efficiency, owner)
	var control := def if def.shock or def.slow > 0 or def.gravity_slow > 0 else {}
	_apply_damage(drone, amount, Vector2.ZERO, int(def.stage) >= 2, control, owner)

func _scaled_damage(def: Dictionary, efficiency: float, owner: Turret) -> int:
	if def.damage <= 0:
		return 0
	var base := float(def.damage) * efficiency
	if owner == null or owner.damage_multiplier == 1.0:
		return maxi(1, roundi(base))
	var raw := maxi(1, roundi(base)) * owner.damage_multiplier + owner.damage_remainder
	var whole := floori(raw + 0.000001)
	owner.damage_remainder = maxf(0.0, raw - whole)
	return whole

func barrage(targets: Array, def: Dictionary, efficiency: float, owner: Turret = null) -> void:
	if owner != null and (owner.damage_multiplier > 1.0 or support.linked.has(owner)):
		for drone: Drone in targets:
			damage(drone, def, efficiency, owner)
		return
	var amount := _scaled_damage(def, efficiency, owner)
	if not def.shock and def.slow <= 0 and def.gravity_slow <= 0:
		if amount == 0:
			return
		for drone: Drone in targets:
			# The common surviving hit needs no reward, status, phase or shield events.
			if _advanced_impact_budget <= 0 and drone.health > amount and drone.shield_hp == 0 and drone.armor == 0.0 and not drone.phase_pending and drone.status.mark_stacks == 0:
				drone.health -= amount
				drone.flash = 0.09
			else:
				_apply_damage(drone, amount, Vector2.ZERO, true)
		return
	for drone: Drone in targets:
		_apply_damage(drone, amount, Vector2.ZERO, true, def)

func _apply_damage(drone: Drone, amount: int, direction: Vector2, advanced: bool = false, control: Dictionary = {}, owner: Turret = null, final_damage: bool = false) -> void:
	if drone.health <= 0 or (amount <= 0 and control.is_empty()):
		return
	var before := drone.health + drone.shield_hp
	if not final_damage and drone.status.mark_stacks > 0:
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
		drone.health -= ceili(amount * (1.0 - drone.armor)) if not final_damage and drone.armor > 0 else amount
	if owner != null and not owner.buffs.is_empty():
		support.note_damage(self, owner, drone, before - maxi(0, drone.health) - drone.shield_hp)
	drone.flash = 0.09
	var killed := drone.health <= 0
	if killed:
		_needs_cleanup = true
		total_kills += 1
		_award_credits(int(drone.definition.reward))
		var base_rp := int(drone.definition.get("reward_rp", 0))
		_award_rp(roundi(base_rp * _rp_multiplier) if drone.primary else base_rp)
		var child: String = drone.definition.get("split_to", "")
		if not child.is_empty():
			queue_birth(drone.progress, child, EnemyRegistry.SPLIT_COUNT)
			mob_effect(&"divide", drone.position, drone.position, drone.tint, 0.55)
		if drone.boss:
			if drone.primary and wave == BattleData.FINAL_WAVE:
				boss_killed = true
				finale_boss_time = elapsed - finale_started
				escorts_waiting_at_boss_kill = queued
			mob_effect(&"boss_down", drone.position, drone.position, drone.tint, 2.1, true)
	else:
		if not control.is_empty():
			var multiplier := 1.0
			if drone.control_resist > 0.0 or drone.shield_hp > 0:
				multiplier = data.mobs.control_multiplier(drone.control_resist, drone.shield_hp > 0)
			drone.status.apply(control, data.status_rules, multiplier)
		if drone.phase_pending:
			MobAbilities.advance_phase(self, drone, elapsed)
			drone.phase_pending = drone.mob.phase < drone.mob.phases.size()
	if advanced and _advanced_impact_budget > 0:
		_advanced_impact_budget -= 1
		effect.emit(&"kill" if killed else &"hit", drone.position, direction)
	elif not advanced and _impact_budget > 0:
		_impact_budget -= 1
		effect.emit(&"kill" if killed else &"hit", drone.position, direction)

func queue_birth(progress: float, id: String, count: int) -> void:
	_births.append([progress, _wave_enemy(data.mobs.lookup(id)), count])

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
	var work: Array[Drone] = []
	# Path tiles are ordered by progress. Only the boundary tile needs a rank cutoff.
	for step in range(_track_cells.size() - 1, -1, -1):
		var bucket := _buckets[_path_buckets[step]]
		if bucket.is_empty():
			continue
		var cell := _track_cells[step]
		if not anywhere and (Vector2(cell) + Vector2(0.5, 0.5)).distance_squared_to(center) > (radius + 0.72) * (radius + 0.72):
			continue
		work.clear()
		for drone: Drone in bucket:
			if drone.health > 0 and drone.progress < _path_length and (detect_cloak or not drone.hidden) and (anywhere or drone.position.distance_squared_to(center) <= squared):
				work.append(drone)
		var left := limit - matched.size()
		if work.size() <= left:
			matched.append_array(work)
			if matched.size() == limit:
				return matched
			continue
		var ranks := PackedFloat64Array()
		ranks.resize(work.size())
		for i in work.size():
			ranks[i] = work[i].progress
		ranks.sort()
		var cutoff := ranks[ranks.size() - left]
		for drone in work:
			if drone.progress > cutoff:
				matched.append(drone)
		for drone in work:
			if matched.size() == limit:
				break
			if drone.progress == cutoff:
				matched.append(drone)
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

# Carry fractional awards within the current run so small rewards keep the same reduction.
@warning_ignore("integer_division")
func _award_credits(amount: int) -> int:
	if _credit_percent != 100:
		var total := amount * _credit_percent + _credit_remainder
		amount = total / 100
		_credit_remainder = total % 100
	total_credits += amount
	_credit(amount)
	return amount

@warning_ignore("integer_division")
func _award_rp(amount: int) -> void:
	if _rp_percent != 100:
		var total := amount * _rp_percent + _rp_remainder
		amount = total / 100
		_rp_remainder = total % 100
	research.earn(amount)

func _credit(amount: int) -> void:
	credits = mini(BattleData.NUMBER_LIMIT, credits + amount)

func _bucket_index(x: int, y: int) -> int:
	return y * field.size.x + x
