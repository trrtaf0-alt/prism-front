class_name WaveRoster
extends RefCounted

var _registry: EnemyRegistry
var _weights := PackedFloat64Array()
var _ids: Array[String] = []
var _caps := PackedInt32Array()
var _total := 0.0
var _cursor := 0
var _boss_slot := -1
var _boss := ""
var _rng := RandomNumberGenerator.new()

func _init(registry: EnemyRegistry, number: int, amount: int, seed: int) -> void:
	_registry = registry
	_rng.seed = seed
	for def: Dictionary in registry.definitions.values():
		if def.child or number < int(def.first_wave):
			continue
		if def.boss:
			if _boss.is_empty() and (number - int(def.first_wave)) % int(def.boss_period) == 0 and amount > 1:
				_boss = def.id
				_boss_slot = mini(24, maxi(1, floori(float(amount) / 3.0)))
			continue
		if def.weight <= 0:
			continue
		var maturity := 1.0 + minf(0.55, (number - int(def.first_wave)) * 0.045) if def.id != "normal" else 1.0
		var weight := float(def.weight) * maturity
		_ids.append(def.id)
		_weights.append(weight)
		_caps.append(int(def.wave_cap) if def.wave_cap > 0 else -1)
		_total += weight

func next() -> Dictionary:
	var slot := _cursor
	_cursor += 1
	if slot == 0 or _ids.is_empty():
		return _registry.lookup("normal")
	if slot == _boss_slot:
		return _registry.lookup(_boss)
	var ticket := _rng.randf() * _total
	for i in _ids.size():
		ticket -= _weights[i]
		if ticket >= 0.0 and i < _ids.size() - 1:
			continue
		var def := _registry.lookup(_ids[i])
		if _caps[i] > 0:
			_caps[i] -= 1
			if _caps[i] == 0:
				_total -= _weights[i]
				_weights.remove_at(i)
				_ids.remove_at(i)
				_caps.remove_at(i)
		return def
	return _registry.lookup("normal")
