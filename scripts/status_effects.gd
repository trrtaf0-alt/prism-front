class_name StatusEffects
extends RefCounted

var engaged := false
var slow := 0.0
var slow_left := 0.0
var stun_left := 0.0
var shock_age := 100.0
var resistance := 0.0
var move_window := 0.0
var gravity_slow := 0.0
var gravity_slow_left := 0.0
var mark_left := 0.0
var mark_stacks := 0
var mark_bonus := 0.0

func reset() -> void:
	engaged = false
	slow = 0.0
	slow_left = 0.0
	stun_left = 0.0
	shock_age = 100.0
	resistance = 0.0
	move_window = 0.0
	gravity_slow = 0.0
	gravity_slow_left = 0.0
	mark_left = 0.0
	mark_stacks = 0
	mark_bonus = 0.0

func shock(rules: Dictionary, multiplier: float = 1.0) -> void:
	engaged = true
	shock_age = 0.0
	if stun_left <= 0.0 and move_window <= 0.0:
		stun_left = maxf(rules.shock_minimum, rules.shock_duration * pow(rules.shock_multiplier, resistance)) * multiplier
		move_window = float(rules.shock_move_window)
	resistance = minf(24.0, resistance + 1.0)

func apply(def: Dictionary, rules: Dictionary, multiplier: float = 1.0) -> void:
	if multiplier <= 0.0:
		return
	engaged = true
	if def.shock:
		shock(rules, multiplier)
	var slow_strength := float(def.slow) * multiplier
	if slow_strength > 0 and (slow_left <= 0.0 or slow_strength >= slow):
		slow = slow_strength
		slow_left = maxf(slow_left, def.status_time)
	var gravity_strength := float(def.gravity_slow) * multiplier
	if gravity_strength > 0.0 and (gravity_slow_left <= 0.0 or gravity_strength >= gravity_slow):
		gravity_slow = gravity_strength
		gravity_slow_left = float(def.status_time)

func mark(def: Dictionary, efficiency: float) -> void:
	engaged = true
	mark_stacks = mini(mark_stacks + 1, maxi(mark_stacks, int(def.mark_cap)))
	mark_bonus = maxf(mark_bonus if mark_left > 0.0 else 0.0, float(def.mark_bonus) * efficiency)
	mark_left = maxf(mark_left, def.status_time)

func boosted_damage(amount: int) -> int:
	return ceili(amount * (1.0 + mark_bonus * mark_stacks)) if mark_left > 0.0 else amount

func step(speed: float, delta: float, rules: Dictionary) -> float:
	if resistance > 0.0:
		shock_age += delta
		if shock_age >= float(rules.shock_recovery_delay):
			resistance = maxf(0.0, resistance - float(rules.shock_recovery_rate) * delta)
	var stopped := minf(delta, stun_left)
	var movable := delta - stopped
	stun_left -= stopped
	move_window = maxf(0.0, move_window - movable)
	var change := speed * _movement_time(delta, stopped)
	slow_left = maxf(0.0, slow_left - delta)
	gravity_slow_left = maxf(0.0, gravity_slow_left - delta)
	mark_left = maxf(0.0, mark_left - delta)
	if mark_left == 0.0:
		mark_stacks = 0
	engaged = resistance > 0 or slow_left > 0 or gravity_slow_left > 0 or mark_left > 0 or stun_left > 0 or move_window > 0
	return change

func predict(progress: float, speed: float, time: float) -> float:
	return progress + speed * _movement_time(time, minf(time, stun_left))

func _movement_time(time: float, stopped: float) -> float:
	var movable := time - stopped
	var slowed := clampf(slow_left - stopped, 0.0, movable)
	var forward := movable - slow * slowed
	if gravity_slow_left > stopped:
		var gravity_time := minf(movable, gravity_slow_left - stopped)
		# The speed multipliers multiply only while both slows are active.
		var overlap := minf(slowed, gravity_time)
		forward -= gravity_slow * (gravity_time - slow * overlap)
	return maxf(0.0, forward)
