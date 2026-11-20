class_name StatusEffects
extends RefCounted

var slow := 0.0
var slow_left := 0.0
var stun_left := 0.0
var shock_age := 100.0
var resistance := 0.0
var move_window := 0.0
var pull := 0.0
var pull_left := 0.0
var anchor := 0.0
var mark_left := 0.0
var mark_stacks := 0
var mark_bonus := 0.0

func reset() -> void:
	slow = 0.0
	slow_left = 0.0
	stun_left = 0.0
	shock_age = 100.0
	resistance = 0.0
	move_window = 0.0
	pull = 0.0
	pull_left = 0.0
	anchor = 0.0
	mark_left = 0.0
	mark_stacks = 0
	mark_bonus = 0.0

func shock(rules: Dictionary) -> void:
	shock_age = 0.0
	var duration := maxf(rules.shock_minimum, rules.shock_duration * pow(rules.shock_multiplier, resistance))
	resistance = minf(24.0, resistance + 1.0)
	if stun_left <= 0.0 and move_window <= 0.0:
		stun_left = duration
		move_window = float(rules.shock_move_window)

func apply(def: Dictionary, rules: Dictionary, gravity_anchor: float) -> void:
	if def.shock:
		shock(rules)
	if def.slow > 0 and (slow_left <= 0.0 or def.slow >= slow):
		slow = float(def.slow)
		slow_left = maxf(slow_left, def.status_time)
	if def.pull > 0 and gravity_anchor >= 0.0 and (pull_left <= 0.0 or def.pull >= pull):
		pull = float(def.pull)
		pull_left = float(def.status_time)
		anchor = gravity_anchor

func mark(def: Dictionary, efficiency: float) -> void:
	mark_stacks = mini(mark_stacks + 1, maxi(mark_stacks, int(def.mark_cap)))
	mark_bonus = maxf(mark_bonus if mark_left > 0.0 else 0.0, float(def.mark_bonus) * efficiency)
	mark_left = maxf(mark_left, def.status_time)

func boosted_damage(amount: int) -> int:
	return ceili(amount * (1.0 + mark_bonus * mark_stacks)) if mark_left > 0.0 else amount

func step(progress: float, speed: float, delta: float, rules: Dictionary) -> float:
	shock_age += delta
	if resistance > 0.0 and shock_age >= float(rules.shock_recovery_delay):
		resistance = maxf(0.0, resistance - float(rules.shock_recovery_rate) * delta)
	var movable := maxf(0.0, delta - stun_left)
	stun_left = maxf(0.0, stun_left - delta)
	move_window = maxf(0.0, move_window - movable)
	var change := speed * (movable - slow * minf(movable, slow_left))
	if pull_left > 0.0 and movable > 0.0:
		change += move_toward(progress, anchor, pull * minf(movable, pull_left)) - progress
	slow_left = maxf(0.0, slow_left - delta)
	pull_left = maxf(0.0, pull_left - delta)
	mark_left = maxf(0.0, mark_left - delta)
	if mark_left == 0.0:
		mark_stacks = 0
	return change

func predict(progress: float, speed: float, time: float) -> float:
	var movable := maxf(0.0, time - stun_left)
	var forward := speed * (movable - slow * minf(movable, slow_left))
	var drift := move_toward(progress, anchor, pull * minf(movable, pull_left)) - progress
	return progress + forward + drift
