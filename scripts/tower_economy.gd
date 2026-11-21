class_name TowerEconomy
extends RefCounted

const AMPLIFIER_BONUS := 20
const CORE_BASE := 10
const CORE_PER_LINK := 2
const CORE_CAP := 30

var installed: Array = []
var links: Dictionary = {}
var bonuses: Dictionary = {}
var providers: Dictionary = {}
var last_credits := 0
var last_rp := 0

static func core_bonus(count: int) -> int:
	return mini(CORE_CAP, CORE_BASE + CORE_PER_LINK * count) if count > 0 else 0

func rebuild(towers: Array, active_wave: int = 0) -> void:
	installed.clear()
	links.clear()
	bonuses.clear()
	providers.clear()
	var sources: Array = []
	for tower in towers:
		var role: String = tower.definition.economy
		if role.is_empty():
			continue
		installed.append(tower)
		if active_wave != 0 and tower.economy_wave != active_wave:
			continue
		if int(tower.definition.production) > 0:
			providers[tower] = {}
			bonuses[tower] = 0
		else:
			sources.append(tower)

	for source in sources:
		var role: String = source.definition.economy
		var resource := "credits" if role == "credit_amp" else "rp"
		var radius_sq := float(source.definition.range) ** 2
		var targets: Array = []
		for tower in bonuses:
			if role != "core" and resource != tower.definition.economy:
				continue
			if source.position.distance_squared_to(tower.position) <= radius_sq:
				targets.append(tower)
		links[source] = targets
		var bonus := core_bonus(targets.size()) if role == "core" else AMPLIFIER_BONUS
		for target in targets:
			var current: Dictionary = providers[target]
			var prior := int(current.get(role, [null, 0])[1])
			if bonus > prior:
				current[role] = [source, bonus]
				bonuses[target] += bonus - prior

func connected(source) -> Array:
	return links.get(source, [])

func preview_core(position: Vector2, radius: float) -> int:
	var count := 0
	for tower in installed:
		if int(tower.definition.production) > 0 and position.distance_squared_to(tower.position) <= radius * radius:
			count += 1
	return count

func produce(sim) -> void:
	last_credits = 0
	last_rp = 0
	if bonuses.is_empty():
		return
	var credits_hundredths := 0
	var rp_hundredths := 0
	var emitters := {}
	for tower in bonuses:
		var amount := int(tower.definition.production) * (100 + int(bonuses[tower]))
		if tower.definition.economy == "credits":
			credits_hundredths += amount
		else:
			rp_hundredths += amount
		emitters[tower] = true
		for provider: Array in providers[tower].values():
			emitters[provider[0]] = true
	last_credits = sim._award_credits(0, credits_hundredths)
	last_rp = sim._award_rp(0, rp_hundredths)
	sim.economy_produced.emit(emitters.keys())
