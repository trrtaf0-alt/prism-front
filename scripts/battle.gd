class_name Battle
extends RefCounted

signal effect(kind: StringName, point: Vector2, direction: Vector2)
signal wave_started(number: int)
signal wave_finished(number: int, reward: int)
signal defeated(number: int)

# All distances are measured in tiles. The display converts them to pixels.
const HIT_RADIUS := 0.21
const BARREL_LENGTH := 0.31

class Drone:
	var progress := 0.0
	var position := Vector2.ZERO
	var previous := Vector2.ZERO
	var health: int
	var flash := 0.0

class Turret:
	var cell: Vector2i
	var position: Vector2
	var angle := 0.0
	var cooldown := 0.0
	var recoil := 0.0
	var full_buckets := PackedInt32Array()
	var edge_buckets := PackedInt32Array()

class Bolt:
	var position: Vector2
	var direction: Vector2
	var remaining: float

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

var _spawn_clock := 0.0
var _buckets: Array[Array] = []
var _used_buckets: Array[int] = []
var _bucket_leaders: Array[Drone] = []
var _track_cells: Array[Vector2i] = []
var _path_length: float
var _drone_pool: Array[Drone] = []
var _bolt_pool: Array[Bolt] = []
var _range: float
var _bolt_speed: float
var _drone_speed: float
var _drone_health: int
var _damage: int
var _shot_interval: float

func _init(map: FieldMap, rules: BattleData) -> void:
	field = map
	data = rules
	health = int(data.balance.base_health)
	credits = int(data.balance.starting_credits)
	_range = float(data.turret.range)
	_bolt_speed = float(data.turret.projectile_speed)
	_drone_speed = float(data.drone.speed)
	_drone_health = int(data.drone.health)
	_damage = int(data.turret.damage)
	_shot_interval = 1.0 / float(data.turret.shots_per_second)
	_path_length = field.length()
	for point in field.path:
		_track_cells.append(Vector2i(point.floor()))
	for i in field.size.x * field.size.y:
		_buckets.append([])
		_bucket_leaders.append(null)

func can_install(cell: Vector2i) -> bool:
	return not lost and credits >= int(data.turret.cost) and field.tile_at(cell) == "." and not occupied.has(cell)

func install(cell: Vector2i) -> bool:
	if not can_install(cell):
		return false
	var tower := Turret.new()
	tower.cell = cell
	tower.position = Vector2(cell) + Vector2(0.5, 0.5)
	_cache_range(tower)
	towers.append(tower)
	occupied[cell] = tower
	credits -= int(data.turret.cost)
	effect.emit(&"install", tower.position, Vector2.ZERO)
	return true

func sell(cell: Vector2i) -> bool:
	if lost or not occupied.has(cell):
		return false
	var tower: Turret = occupied[cell]
	occupied.erase(cell)
	towers.erase(tower)
	_credit(int(data.turret.refund))
	effect.emit(&"sell", tower.position, Vector2.ZERO)
	return true

func start_wave() -> bool:
	if active or lost:
		return false
	wave = mini(wave + 1, BattleData.NUMBER_LIMIT)
	active = true
	queued = data.wave_count(wave) - 1
	_spawn_clock = data.spawn_interval(wave)
	wave_started.emit(wave)
	spawn()
	return true

func spawn(progress: float = 0.0) -> Drone:
	var drone: Drone = Drone.new() if _drone_pool.is_empty() else _drone_pool.pop_back()
	drone.progress = progress
	drone.position = field.position_at(progress)
	drone.previous = drone.position
	drone.health = _drone_health
	drone.flash = 0.0
	enemies.append(drone)
	if is_zero_approx(progress):
		effect.emit(&"spawn", drone.position, field.heading_at(progress))
	return drone

func tick(delta: float) -> void:
	if lost:
		return
	_update_drones(delta)
	_update_bolts(delta)
	_remove_drones()
	if lost:
		return
	_update_towers(delta)
	if queued > 0:
		_spawn_clock -= delta
		while _spawn_clock <= 0.000001 and queued > 0:
			queued -= 1
			_spawn_clock += data.spawn_interval(wave)
			spawn()
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
	for drone in enemies:
		drone.previous = drone.position
		drone.progress = minf(drone.progress + _drone_speed * delta, _path_length)
		drone.position = field.position_at(drone.progress)
		drone.flash = maxf(0.0, drone.flash - delta)
		var cell := Vector2i(drone.position.floor())
		var i := _bucket_index(cell.x, cell.y)
		if _buckets[i].is_empty():
			_used_buckets.append(i)
		_buckets[i].append(drone)
		var leader := _bucket_leaders[i]
		if drone.progress < _path_length and (leader == null or drone.progress > leader.progress):
			_bucket_leaders[i] = drone

func _remove_drones() -> void:
	var i := enemies.size() - 1
	while i >= 0:
		var drone := enemies[i]
		if drone.health <= 0:
			_recycle_drone(i)
		elif drone.progress >= _path_length:
			health = maxi(0, health - drone.health)
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
	if _drone_pool.size() < 1024:
		_drone_pool.append(enemies[index])
	enemies[index] = enemies.back()
	enemies.pop_back()

func _update_towers(delta: float) -> void:
	for tower in towers:
		tower.recoil = maxf(0.0, tower.recoil - delta)
		tower.cooldown = maxf(0.0, tower.cooldown - delta)
		if enemies.is_empty():
			continue
		var target := _target_in_range(tower)
		if target == null:
			continue
		var direction := tower.position.direction_to(target.position)
		if tower.cooldown <= 0.10:
			direction = aim_at(tower.position, target)
		var angle := direction.angle()
		tower.angle = rotate_toward(tower.angle, angle, delta * 24.0)
		if tower.cooldown <= 0.000001:
			# The head catches up before firing when acquiring a target behind it.
			if absf(angle_difference(tower.angle, angle)) > 0.45:
				continue
			tower.cooldown = _shot_interval
			tower.angle = angle
			tower.recoil = 0.12
			_fire(tower.position + direction * BARREL_LENGTH, direction)

func target_for(origin: Vector2) -> Drone:
	var query := Turret.new()
	query.position = origin
	_cache_range(query)
	return _target_in_range(query)

func _cache_range(tower: Turret) -> void:
	# Interior cells need only their leading drone. Boundary cells still use
	# exact circular range, including the edge itself.
	var radius_squared := _range * _range
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
				if drone.progress > progress and drone.progress < _path_length and drone.health > 0:
					best = drone
					progress = drone.progress
	var radius_squared := _range * _range
	for index in tower.edge_buckets:
		var leader := _bucket_leaders[index]
		if leader == null or leader.progress <= progress:
			continue
		for drone: Drone in _buckets[index]:
			if drone.progress > progress and drone.progress < _path_length and drone.health > 0 and tower.position.distance_squared_to(drone.position) <= radius_squared:
				best = drone
				progress = drone.progress
	return best

func aim_at(origin: Vector2, target: Drone) -> Vector2:
	# The bolt is faster than the drone, so the interception equation is monotonic,
	# even through turns. The path sampler clamps the prediction at the exit.
	var low := 0.0
	var high := origin.distance_to(target.position) / maxf(0.001, _bolt_speed - _drone_speed)
	for i in 12:
		var time := (low + high) * 0.5
		var future := field.position_at(target.progress + _drone_speed * time)
		if origin.distance_to(future) > BARREL_LENGTH + _bolt_speed * time:
			low = time
		else:
			high = time
	var direction := origin.direction_to(field.position_at(target.progress + _drone_speed * high))
	return Vector2.RIGHT if direction.is_zero_approx() else direction

func _fire(origin: Vector2, direction: Vector2) -> void:
	var bolt: Bolt = Bolt.new() if _bolt_pool.is_empty() else _bolt_pool.pop_back()
	bolt.position = origin
	bolt.direction = direction
	bolt.remaining = _range + _drone_speed * _range / maxf(0.001, _bolt_speed - _drone_speed) + HIT_RADIUS
	bolts.append(bolt)
	effect.emit(&"fire", origin, direction)

func _update_bolts(delta: float) -> void:
	var i := bolts.size() - 1
	while i >= 0:
		var bolt := bolts[i]
		var step := minf(_bolt_speed * delta, bolt.remaining)
		var end := bolt.position + bolt.direction * step
		var hit := _collide(bolt.position, end, step / (_bolt_speed * delta), delta)
		bolt.position = end
		bolt.remaining -= step
		if hit != null or bolt.remaining <= 0.00001:
			if hit != null:
				_damage_drone(hit, bolt.direction)
			else:
				effect.emit(&"miss", end, bolt.direction)
			if _bolt_pool.size() < 1024:
				_bolt_pool.append(bolt)
			bolts[i] = bolts.back()
			bolts.pop_back()
		i -= 1

func _collide(from: Vector2, to: Vector2, tick_fraction: float, delta: float) -> Drone:
	var padding := Vector2.ONE * (HIT_RADIUS + _drone_speed * delta + 0.01)
	var lo := (from.min(to) - padding).floor().max(Vector2.ZERO)
	var hi := (from.max(to) + padding).floor().min(Vector2(field.size - Vector2i.ONE))
	var first := 2.0
	var hit: Drone
	for y in range(int(lo.y), int(hi.y) + 1):
		for x in range(int(lo.x), int(hi.x) + 1):
			for drone: Drone in _buckets[_bucket_index(x, y)]:
				if drone.health <= 0:
					continue
				var offset := from - drone.previous
				var motion := to - from - (drone.position - drone.previous) * tick_fraction
				var time := sweep(offset, motion, HIT_RADIUS)
				if time >= 0.0 and time < first:
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
	if drone.health <= 0:
		return
	drone.health -= _damage
	drone.flash = 0.09
	effect.emit(&"hit", drone.position, direction)
	if drone.health <= 0:
		_credit(int(data.drone.reward))
		effect.emit(&"kill", drone.position, direction)

func _credit(amount: int) -> void:
	credits = mini(BattleData.NUMBER_LIMIT, credits + amount)

func _bucket_index(x: int, y: int) -> int:
	return y * field.size.x + x
