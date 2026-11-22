class_name WaveRoster
extends RefCounted

const LIGHT_ESCORTS := ["normal", "swift", "swarm"]
const ESCORT_LEADERS := ["armored", "heavy", "energy", "giant"]

var in_escort := false

var _registry: EnemyRegistry
var _weights := PackedFloat64Array()
var _ids: Array[String] = []
var _caps := PackedInt32Array()
var _total := 0.0
var _cursor := 0
var _finale: bool
var _boss_id: String
var _scripted: Array
var _group := 0
var _group_used := 0
var _elite := PackedByteArray()
var _elite_total := 0.0
var _rng := RandomNumberGenerator.new()

var _amount: int
var _escort: Dictionary
var _carry := 0.0
var _group_end := 0
var _pending: Array[Dictionary] = []
var _next_pending := 0

func _init(registry: EnemyRegistry, number: int, amount: int, seed: int, escort: Dictionary = {}, terminal: int = BattleData.FINAL_WAVE,
		boss_id: String = "boss", scripted: Array = []) -> void:
	_amount = amount
	if number >= int(escort.get("first_wave", BattleData.FINAL_WAVE + 1)):
		_escort = escort
	_registry = registry
	_finale = number == terminal
	_boss_id = boss_id
	_scripted = scripted
	_rng.seed = seed
	for def: Dictionary in registry.definitions.values():
		if def.child or def.boss or number < int(def.first_wave):
			continue
		if def.weight <= 0:
			continue
		var maturity := 1.0 + minf(0.55, (number - int(def.first_wave)) * 0.045) if def.id != "normal" else 1.0
		var weight := float(def.weight) * maturity
		_ids.append(def.id)
		_weights.append(weight)
		var limit := int(def.wave_cap) if def.wave_cap > 0 else -1
		if def.has("intro_cap") and limit > 0:
			limit = mini(limit, int(def.intro_cap) + floori((number - int(def.first_wave)) / 2.0))
		_caps.append(limit)
		_total += weight
		var elite := int(int(def.first_wave) >= 20)
		_elite.append(elite)
		_elite_total += weight * elite

func next(elite_weight: float = 1.0) -> Dictionary:
	in_escort = false
	if not _scripted.is_empty():
		return _scripted_next()
	if _next_pending >= _pending.size():
		if _escort.is_empty() or _cursor == 0 or _cursor >= _amount:
			return _roll(elite_weight)
		_prepare_batch(elite_weight)
	in_escort = _next_pending < _group_end
	var unit := _pending[_next_pending]
	_next_pending += 1
	return unit

func _scripted_next() -> Dictionary:
	_cursor += 1
	if _cursor == 1 and _finale:
		return _registry.lookup(_boss_id)
	var group: Dictionary = _scripted[_group]
	_group_used += 1
	if _group_used == int(group.count):
		_group += 1
		_group_used = 0
	return _registry.lookup(group.enemy)

func next_interval(fallback: float) -> float:
	if _group >= _scripted.size():
		return fallback
	return float(_scripted[_group].get("interval", fallback))

func _prepare_batch(elite_weight: float) -> void:
	_pending.clear()
	_next_pending = 0
	_group_end = 0
	var end := _amount
	if _finale:
		# Keep batches inside the existing opening, middle and closing spawn bands.
		if _cursor < 181:
			end = mini(end, 181)
		elif _cursor < 496:
			end = mini(end, 496)
	var window := mini(maxi(1, int(_escort.window)), end - _cursor)
	var light := 0
	var leader := -1
	var armor_rank := -1
	for i in window:
		var unit := _roll(elite_weight)
		_pending.append(unit)
		light += int(unit.id in LIGHT_ESCORTS)
		var rank := ESCORT_LEADERS.find(unit.id)
		if rank > armor_rank:
			leader = i
			armor_rank = rank
	var limit := maxi(1, int(_escort.wing_limit))
	_carry += light * clampf(float(_escort.share), 0.0, 1.0)
	var wing := mini(mini(floori(_carry + 0.000001), limit), light)
	if leader < 0 or wing == 0:
		return
	_carry -= wing
	_group_end = wing + 1
	_pending.push_front(_pending.pop_at(leader))
	var next_wing := 1
	for i in range(1, _pending.size()):
		if _pending[i].id in LIGHT_ESCORTS:
			_pending.insert(next_wing, _pending.pop_at(i))
			next_wing += 1
			if next_wing == _group_end:
				break

func _roll(elite_weight: float) -> Dictionary:
	var slot := _cursor
	_cursor += 1
	if slot == 0 and _finale:
		return _registry.lookup(_boss_id)
	if slot == 0 or _ids.is_empty():
		return _registry.lookup("normal")
	var ticket := _rng.randf() * (_total + _elite_total * (elite_weight - 1.0))
	for i in _ids.size():
		ticket -= _weights[i] * (elite_weight if _elite[i] else 1.0)
		if ticket >= 0.0 and i < _ids.size() - 1:
			continue
		var def := _registry.lookup(_ids[i])
		if _caps[i] > 0:
			_caps[i] -= 1
			if _caps[i] == 0:
				_total -= _weights[i]
				_elite_total -= _weights[i] * _elite[i]
				_elite.remove_at(i)
				_weights.remove_at(i)
				_ids.remove_at(i)
				_caps.remove_at(i)
		return def
	return _registry.lookup("normal")
