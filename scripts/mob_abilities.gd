class_name MobAbilities
extends RefCounted

class State:
	var slot := -1
	var spawn_at := 0.0
	var phase := 0
	var phases: Array = []
	var base_speed := 0.0
	var regen: Dictionary
	var boost: Dictionary
	var guardian: Dictionary
	var brood: Dictionary
	var regen_at := 0.0
	var boost_at := 0.0
	var guard_at := 0.0
	var brood_at := 0.0
	var births_left := 0
	var cloak_cycle := 0.0
	var hidden_for := 0.0
	var acceleration := 0.0
	var speed_limit := 0.0

	static func timer(config: Dictionary, now: float) -> float:
		return now + float(config.interval) if not config.is_empty() else INF

	func reset(def: Dictionary, now: float) -> void:
		slot = -1
		spawn_at = now
		phase = 0
		phases = def.get("phases", [])
		base_speed = float(def.speed)
		regen = def.get("regen", {})
		boost = def.get("boost", {})
		guardian = def.get("guardian", {})
		brood = def.get("brood", {})
		regen_at = timer(regen, now)
		boost_at = timer(boost, now)
		guard_at = timer(guardian, now)
		brood_at = timer(brood, now)
		births_left = int(brood.get("limit", 0))
		var cloak: Dictionary = def.get("cloak", {})
		cloak_cycle = float(cloak.get("cycle", 0))
		hidden_for = float(cloak.get("hidden", 0))
		var accel: Dictionary = def.get("acceleration", {})
		acceleration = float(accel.get("rate", 0))
		speed_limit = float(accel.get("max_speed", base_speed))

	func has_periodic() -> bool:
		return not regen.is_empty() or not boost.is_empty() or not guardian.is_empty() or births_left > 0 or not phases.is_empty()

static func periodic(sim, drone, now: float) -> void:
	var state: State = drone.mob
	if now + 0.000001 >= state.regen_at:
		var elapsed := int((now + 0.000001 - state.regen_at) / float(state.regen.interval)) + 1
		state.regen_at += elapsed * float(state.regen.interval)
		if drone.health < drone.maximum_health:
			drone.health = mini(drone.maximum_health, drone.health + elapsed * int(state.regen.amount))
			sim.mob_effect(&"regen", drone.position, drone.position, drone.tint, 0.55)
	if now + 0.000001 >= state.guard_at:
		state.guard_at = State.timer(state.guardian, now)
		sim.apply_support(drone, state.guardian, true)
	if now + 0.000001 >= state.boost_at:
		state.boost_at = State.timer(state.boost, now)
		sim.apply_support(drone, state.boost, false)
	if now + 0.000001 >= state.brood_at and state.births_left > 0:
		var count := mini(state.births_left, int((now + 0.000001 - state.brood_at) / float(state.brood.interval)) + 1)
		state.brood_at += count * float(state.brood.interval)
		state.births_left -= count
		sim.queue_birth(drone.progress, state.brood.child, count)
		sim.mob_effect(&"brood", drone.position, drone.position, drone.tint, 0.7)

static func advance_phase(sim, drone, now: float) -> void:
	var state: State = drone.mob
	if state.phase == state.phases.size():
		return
	var fraction: float = float(drone.health) / float(drone.maximum_health)
	while state.phase < state.phases.size() and fraction <= float(state.phases[state.phase].threshold):
		var phase: Dictionary = state.phases[state.phase]
		state.phase += 1
		drone.speed = state.base_speed * float(phase.get("speed_multiplier", 1))
		var phase_shield := int(phase.get("shield", 0))
		if phase_shield > drone.shield_hp:
			drone.give_shield(phase_shield, 0, 0.0)
		if phase.has("regen"):
			state.regen = phase.regen
			state.regen_at = State.timer(state.regen, now)
		if phase.has("boost"):
			state.boost = phase.boost
			state.boost_at = State.timer(state.boost, now)
		sim.mob_effect(&"phase", drone.position, drone.position, drone.tint, 2.0, true)
