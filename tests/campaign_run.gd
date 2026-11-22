extends SceneTree

const STEP := 1.0 / 60.0
const EARLY: Array[Vector2i] = [
	Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 4), Vector2i(4, 4),
	Vector2i(4, 2), Vector2i(5, 2), Vector2i(6, 2), Vector2i(7, 2), Vector2i(8, 2),
	Vector2i(9, 2), Vector2i(10, 3), Vector2i(10, 4), Vector2i(10, 5), Vector2i(10, 6),
	Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6), Vector2i(1, 4), Vector2i(2, 4),
	Vector2i(6, 4), Vector2i(7, 4), Vector2i(8, 4), Vector2i(8, 5), Vector2i(7, 5),
	Vector2i(8, 6), Vector2i(12, 9), Vector2i(8, 12), Vector2i(9, 12), Vector2i(12, 12),
	Vector2i(6, 12), Vector2i(5, 12), Vector2i(15, 10), Vector2i(10, 14), Vector2i(11, 14),
]
const POLICIES := {
	"standard": [[2, 9, 12, 13, 18, 21, 25, 28, 29, 30], [9, 12, 13, 18, 21, 25], [28, 29, 30, 29, 25, 25, 29, 25]],
	"splash": [[4, 7, 12, 18, 21, 24, 25, 29, 28], [7, 12, 18, 21, 24, 25], [24, 29, 24, 29, 29, 25, 29, 25]],
	"control": [[5, 6, 9, 15, 20, 21, 23, 25, 28, 29], [6, 9, 15, 20, 21, 23, 25], [28, 28, 29, 29, 25, 25, 29]],
	"precision": [[3, 9, 11, 13, 18, 21, 25, 29], [9, 11, 13, 18, 21, 25], [29, 29, 29, 29, 25, 25]],
	"focus": [[2, 9, 14, 10, 21, 25, 28, 29], [9, 14, 10, 21, 25], [28, 28, 29, 29, 29, 25, 25]],
	"spread": [[2, 4, 6, 7, 9, 12, 15, 18, 21, 23, 25, 29, 28], [6, 7, 9, 12, 18, 21, 23, 25], [29, 28, 29, 29, 25, 25]],
	"rush": [[2, 9, 12, 13, 21, 25, 28, 30, 29], [9, 12, 13, 21, 25], [28, 30, 29, 25, 29, 25, 25]],
}

const SUPPORT_PLANS := {
	"none": {}, "pair": {31: 12, 32: 18}, "overdrive": {34: 34},
	"quantum": {35: 41}, "command": {36: 45},
	"all": {31: 12, 32: 18, 33: 25, 34: 34, 35: 41, 36: 45},
}

const PRODUCTION_PLANS := {
	"none": [],
	"cash": [[39, 26, 3], [43, 20, 1], [38, 9, 4], [37, 1, 3]],
	"research": [[42, 25, 2], [44, 22, 1], [41, 13, 3], [40, 6, 3]],
	"mixed": [[45, 29, 1], [39, 26, 3], [42, 25, 2], [43, 20, 1], [44, 22, 1],
		[41, 13, 3], [38, 9, 4], [40, 6, 3], [37, 1, 3]],
}

var production_plan := "none"
var production_credits := 0
var production_rp := 0
var production_spend := 0
var production_research := 0
var production_breakdown: Dictionary = {}
var production_guard := false
var production_seats: Array[Vector2i] = []
var support_plan := "none"
var difficulty := &"easy"
var trial_health := 0
var trial_armor := 0.0
var snapshot_path := ""
var final_quantum := 0
var final_syncs := 0
var rules := BattleData.new()
var map := FieldMap.new()
var policy := "standard"
var roster_seed := 7043
var summarize := false
var constraint_levels: Dictionary = {}
var seats: Array[Vector2i] = []
var stage := 0
var stage_two := -1.0
var stage_three := -1.0
var invested := 0
var peak_live := 0
var peak_final := 0
var living_at_boss_kill := -1
var first_buy: Dictionary = {}
var first_unlock: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	production_guard = "--production-guard" in args
	for arg in args:
		if arg.begins_with("--strategy="):
			policy = arg.trim_prefix("--strategy=")
		if arg.begins_with("--seed="):
			roster_seed = int(arg.trim_prefix("--seed="))
		if arg.begins_with("--support="):
			support_plan = arg.trim_prefix("--support=")
		if arg.begins_with("--production="):
			production_plan = arg.trim_prefix("--production=")
		if arg.begins_with("--difficulty="):
			difficulty = StringName(arg.trim_prefix("--difficulty="))
		if arg.begins_with("--constraints="):
			for token in arg.trim_prefix("--constraints=").split(",", false):
				var pair := token.split(":", false)
				if pair.size() != 2 or not RunConstraints.DEFINITIONS.has(StringName(pair[0])) or not pair[1].is_valid_int() or int(pair[1]) not in range(6):
					printerr("Invalid constraint id:level " + token)
					quit(2)
					return
				constraint_levels[StringName(pair[0])] = int(pair[1])
		if arg.begins_with("--save-finale="):
			snapshot_path = arg.trim_prefix("--save-finale=")
		if arg.begins_with("--boss-trial="):
			var values := arg.trim_prefix("--boss-trial=").split(",")
			if values.size() != 2 or not values[0].is_valid_int() or int(values[0]) <= 0 or not values[1].is_valid_float() or float(values[1]) < 0.0 or float(values[1]) > 100.0:
				printerr("Boss trial requires positive HP and armor percent between 0 and 100")
				quit(2)
				return
			trial_health = int(values[0])
			trial_armor = float(values[1]) / 100.0
	if not BattleData.DIFFICULTIES.has(difficulty) or not SUPPORT_PLANS.has(support_plan) or not POLICIES.has(policy) or not PRODUCTION_PLANS.has(production_plan) or not map.load_map(BattleData.read_json("res://data/sample_map.json")).is_empty() or not rules.mobs.error.is_empty():
		printerr("Invalid campaign fixture")
		quit(1)
		return
	if "--economy" in args:
		_economy()
		quit()
		return
	if "--rosters" in args:
		_roster_report()
		return
	if "--boss-walk" in args:
		_boss_walk()
		return
	for cell in EARLY:
		if map.tile_at(cell) == ".":
			seats.append(cell)
	for y in map.size.y:
		for x in map.size.x:
			var tile := Vector2i(x, y)
			if map.tile_at(tile) == "." and not seats.has(tile):
				seats.append(tile)
	production_seats = seats.duplicate()
	if production_guard:
		# Leave commonly used firing positions free and group producers for shared buffs.
		var anchor := Vector2i(2, map.size.y - 2)
		production_seats.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return (a - anchor).length_squared() < (b - anchor).length_squared())
	# Preserve the existing benchmark CLI and snapshot convention, where positive levels are penalties.
	var rule_levels: Dictionary = {}
	for id: StringName in constraint_levels:
		rule_levels[id] = -int(constraint_levels[id])
	var sim := Battle.new(map, rules, difficulty, rule_levels)
	var ui
	if "--visual" in args and DisplayServer.get_name() != "headless":
		var packed := load("res://scenes/Front.tscn") as PackedScene
		ui = packed.instantiate()
		root.add_child(ui)
		await process_frame
		ui.start_game(difficulty, rule_levels)
		ui.set_physics_process(false)
		ui.set_process_unhandled_input(false)
		root.gui_disable_input = true
		sim = ui.battle
	sim.roster_seed = roster_seed
	summarize = "--summary" in args
	var leaky := "--leaky" in args
	if not leaky:
		_place_opening(sim)
	for wave in range(1, BattleData.FINAL_WAVE + 1):
		if wave == BattleData.FINAL_WAVE:
			sim.support_visual.connect(_final_support_event)
		sim.start_wave()
		var trial_boss: Battle.Drone
		if wave == BattleData.FINAL_WAVE and trial_health > 0:
			trial_boss = sim.bosses[0]
			trial_boss.health = trial_health
			trial_boss.maximum_health = trial_health
			trial_boss.armor = trial_armor
			print("Boss trial %s: HP=%d armor=%.1f%%" % [difficulty, trial_health, trial_armor * 100.0])
		var ticks := 0
		while sim.active and not sim.lost and ticks < 48000:
			ticks += 1
			sim.tick(STEP)
			peak_live = maxi(peak_live, sim.enemies.size())
			if wave == 50:
				peak_final = maxi(peak_final, sim.enemies.size())
				if living_at_boss_kill < 0 and sim.boss_killed:
					living_at_boss_kill = sim.enemies.size()
				if not sim.bosses.is_empty():
					_track_phase(sim)
		if sim.lost or sim.active:
			_report_summary(sim)
			printerr("%s FAILED wave=%d at %.1fs hp=%d queued=%d enemies=%d cash=%d RP=%d spent=%d towers=%s bossEscape=%s" % [
				policy, wave, ticks * STEP, sim.health, sim.queued, sim.enemies.size(), sim.credits,
				sim.research.points, invested, _build(sim), sim.boss_escaped,
			])
			if trial_boss != null and not sim.boss_killed:
				print("Trial remaining HP=%d shield=%d phase=%d last_escort=%.2fs" % [trial_boss.health, trial_boss.shield_hp, trial_boss.mob.phase + 1, sim.finale_last_spawn])
			quit(1)
			return
		if wave == 1 and leaky:
			_place_opening(sim)
		_record_economy(sim)
		if wave == 49 and summarize:
			print("PRE_BOSS " + JSON.stringify({
				"placed": first_buy, "cash": sim.credits, "gross_spend": invested, "earned": sim.total_credits,
				"rp": sim.research.total_earned, "production_spend": production_spend,
				"production_research": production_research, "produced_credits": production_credits,
				"produced_rp": production_rp, "production_breakdown": production_breakdown,
			}))
		if wave < BattleData.FINAL_WAVE:
			_prepare(sim)
			if production_guard:
				_fill_defense_gap(sim)
			_prepare_economy(sim)
		if wave == BattleData.FINAL_WAVE - 1 and not snapshot_path.is_empty():
			var saved := _save_finale(sim)
			quit(0 if saved else 1)
			return
		if wave == BattleData.FINAL_WAVE - 1 and "--spend-reserve" in args:
			for number in [29, 25, 25, 25, 25]:
				if sim.research.unlocked.has(_id(number)):
					_buy(sim, _id(number))
		if ui != null and wave % 5 == 0:
			await process_frame
		if wave % 5 == 0 or wave >= 48:
			print("%s W%d hp=%d RP=%d earned=%d bank=%d gross_spend=%d towers=%s unlock=%s placed=%s research=%d" % [
				policy, wave, sim.health, sim.research.total_earned, sim.total_credits, sim.credits, invested,
				_build(sim), first_unlock, first_buy, sim.research.completed.size(),
			])
	_report_summary(sim)
	print("%s clear=%.2fs boss_wave=%.2fs boss_kill=%.2fs stage2=%.2fs stage3=%.2fs last_escort=%.2fs peak=%d final_peak=%d" % [
		policy, sim.elapsed, sim.elapsed - sim.finale_started, sim.finale_boss_time, stage_two, stage_three, sim.finale_last_spawn, peak_live, peak_final,
	])
	print("Difficulty %s, at boss kill: escorts queued=%d alive=%d" % [difficulty, sim.escorts_waiting_at_boss_kill, living_at_boss_kill])
	if support_plan != "none":
		print("Finale support: %d quantum strikes, %d sync starts" % [final_quantum, final_syncs])
	if ui != null and sim.won:
		await RenderingServer.frame_post_draw
		var name := "campaign-live-victory.png" if support_plan == "none" else "support-campaign-victory.png"
		if difficulty != &"easy":
			name = "campaign-%s-victory.png" % difficulty
		var filename := ProjectSettings.globalize_path("res://reports/" + name)
		if root.get_texture().get_image().save_png(filename) != OK or ui.modal_kind != "victory":
			quit(1)
			return
		await create_timer(1.0).timeout
	quit(0 if sim.won else 1)

func _save_finale(sim: Battle) -> bool:
	var result := FileAccess.open(snapshot_path, FileAccess.WRITE)
	if result == null:
		printerr("Could not write the W49 snapshot")
		return false
	var towers: Array = []
	for tower: Battle.Turret in sim.towers:
		towers.append([tower.definition.id, tower.cell.x, tower.cell.y, tower.cooldown, tower.angle])
	result.store_string(JSON.stringify({
		"difficulty": str(difficulty), "strategy": policy, "seed": sim.roster_seed,
		"health": sim.health, "credits": sim.credits, "points": sim.research.points,
		"completed": sim.research.completed.keys(), "towers": towers,
		"command_clock": sim.support.command_time, "constraints": constraint_levels,
		"credit_remainder": sim._credit_remainder, "rp_remainder": sim._rp_remainder,
	}))
	print("Saved W49 %s/%s: HP=%d cash=%d RP=%d towers=%d" % [difficulty, policy, sim.health, sim.credits, sim.research.points, sim.towers.size()])
	return true

func _final_support_event(event: StringName, _kind: int, _start: Vector2, _finish: Vector2) -> void:
	final_quantum += int(event == &"quantum")
	final_syncs += int(event == &"sync")

func _place_opening(sim: Battle) -> void:
	for i in 5:
		if sim.install(seats[i]):
			invested += int(sim.tower_definition(TowerRegistry.BASE).cost)

func _track_phase(sim: Battle) -> void:
	var next := sim.bosses[0].mob.phase
	var time := sim.elapsed - sim.finale_started
	if next > stage:
		if next >= 1 and stage_two < 0.0:
			stage_two = time
		if next >= 2:
			stage_three = time
		stage = next

func _report_summary(sim: Battle) -> void:
	if not summarize:
		return
	print("BALANCE " + JSON.stringify({
		"policy": policy, "support": support_plan, "seed": roster_seed, "difficulty": difficulty, "constraints": constraint_levels,
		"wave": sim.wave, "won": sim.won, "health": sim.health, "time": sim.elapsed,
		"boss_time": sim.finale_boss_time, "gross_spend": invested, "cash": sim.credits,
		"earned": sim.total_credits, "rp": sim.research.total_earned, "research": sim.research.completed.size(),
		"unlock": first_unlock, "placed": first_buy, "towers": _build(sim),
		"production": production_plan, "produced_credits": production_credits, "produced_rp": production_rp,
		"production_spend": production_spend, "production_research": production_research,
	}))

func _build(sim: Battle) -> Dictionary:
	var out: Dictionary = {}
	for tower in sim.towers:
		var id: String = tower.definition.id
		out[id] = int(out.get(id, 0)) + 1
	return out

func _id(number: int) -> String:
	return "tower_%02d" % number

func _research(sim: Battle, choice: String) -> void:
	var graph := rules.research
	var paths := graph._plans(graph.unlocks[choice], sim.research.completed, {})
	var cheapest := BattleData.NUMBER_LIMIT
	var selected: Dictionary = {}
	for path in paths:
		var cost := 0
		for key in path:
			cost += sim.research.cost(key)
		if cost < cheapest:
			cheapest = cost
			selected = path
	for id in graph.ordered:
		if selected.has(id):
			sim.research.purchase(id)

func _prepare(sim: Battle) -> void:
	var options: Array = POLICIES[policy]
	for number: int in SUPPORT_PLANS[support_plan]:
		if sim.wave < int(SUPPORT_PLANS[support_plan][number]):
			continue
		var id := _id(number)
		if _count(sim, id) > 0:
			continue
		var node: String = rules.research.unlocks[id]
		if sim.research.minimum_cost(node) <= sim.research.points:
			if not sim.research.unlocked.has(id):
				_research(sim, id)
				if sim.research.unlocked.has(id):
					first_unlock[number] = sim.wave
			_buy_support(sim, id)
	for index in range(0, 5):
		var before := sim.research.completed.size()
		for number: int in options[0]:
			var blueprint := _id(number)
			if not sim.research.unlocked.has(blueprint):
				_research(sim, blueprint)
				break
		if sim.research.completed.size() == before:
			break
	if policy == "spread" and sim.wave >= 47:
		for node in rules.research.ordered:
			sim.research.purchase(node)
	for tower_id in rules.research.unlocks:
		var number := int(tower_id.right(2))
		if sim.research.unlocked.has(tower_id) and not first_unlock.has(number):
			first_unlock[number] = sim.wave
	if sim.wave < 11:
		var early := _id(int(options[0][0]))
		for i in 3:
			if _count(sim, early) < 10 and _buy(sim, early):
				continue
			if sim.towers.size() >= 13 or not _buy(sim, TowerRegistry.BASE):
				break
	if sim.wave >= 11 and sim.wave < 43:
		for number: int in options[1]:
			var def := rules.towers.lookup(_id(number))
			if not sim.research.unlocked.has(def.id):
				continue
			var cap := 4 if int(def.stage) <= 3 else (3 if number in [21, 22, 24] else 2)
			if number == 10:
				cap = 2
			elif int(def.stage) == 4 and sim.wave >= 31:
				cap = 4
			if _count(sim, def.id) < cap:
				_buy(sim, def.id)
	if sim.wave >= 29:
		var wish: Dictionary = {}
		for number: int in options[2]:
			var id := _id(number)
			wish[id] = int(wish.get(id, 0)) + 1
			if _count(sim, id) >= int(wish[id]):
				continue
			if sim.research.unlocked.has(id):
				if not _buy(sim, id):
					break
	if sim.wave >= 43:
		# Spend the surplus on mature single-target support once terminal purchases settle.
		var reserve := int(sim.tower_definition(_id(30)).cost) if policy in ["rush", "standard"] and _count(sim, _id(30)) == 0 else 0
		if sim.wave >= 48 or sim.credits > reserve + 160000:
			for n in [25, 26, 21]:
				var id := _id(n)
				if _count(sim, id) < (7 if n == 25 else 4) and sim.credits >= reserve + int(sim.tower_definition(id).cost):
					_buy(sim, id)

func _prepare_economy(sim: Battle) -> void:
	# Retain a defense budget and avoid purchases too late to benefit the run.
	if sim.wave >= 43:
		return
	var reserve := 7 * maxi(0, sim.wave - 4) ** 2
	for target: Array in PRODUCTION_PLANS[production_plan]:
		var id := _id(target[0])
		var def := sim.tower_definition(id)
		if sim.wave < int(target[1]) or _count(sim, id) >= int(target[2]) or sim.credits < reserve + int(def.cost):
			continue
		if not sim.research.unlocked.has(id):
			if sim.research.minimum_cost(def.research_id) > sim.research.points:
				continue
			var before := sim.research.points
			_research(sim, id)
			production_research += before - sim.research.points
		if def.production > 0:
			if not _buy(sim, id, production_seats):
				continue
		elif not _buy_economy_support(sim, def):
			continue
		production_spend += int(def.cost)
		return

func _fill_defense_gap(sim: Battle) -> void:
	if sim.wave not in range(30, 43) or _count(sim, _id(28)) + _count(sim, _id(29)) > 0:
		return
	for number in [25, 26, 23, 22, 21, 18, 13]:
		var id := _id(number)
		if _count(sim, id) < 7 and _buy(sim, id):
			return

func _record_economy(sim: Battle) -> void:
	production_credits += sim.economy.last_credits
	production_rp += sim.economy.last_rp
	# Each column stores the pre-custom-rule contribution in hundredths.
	for tower: Battle.Turret in sim.economy.providers:
		var resource := int(tower.definition.economy == "rp")
		var base := int(tower.definition.production)
		_add_production(tower.definition.id, resource, base * 100)
		for provider: Array in sim.economy.providers[tower].values():
			_add_production(provider[0].definition.id, resource, base * int(provider[1]))

func _add_production(id: String, resource: int, hundredths: int) -> void:
	var totals: Array = production_breakdown.get_or_add(id, [0, 0])
	totals[resource] += hundredths

func _buy_economy_support(sim: Battle, def: Dictionary) -> bool:
	var best := Vector2i(-1, -1)
	var best_output := 0.0
	for cell: Vector2i in production_seats:
		if not sim.can_install(cell, def.id):
			continue
		var center := Vector2(cell) + Vector2.ONE * 0.5
		var count := 0
		var output := 0.0
		for tower: Battle.Turret in sim.economy.installed:
			var base := int(tower.definition.production)
			if base == 0 or tower.position.distance_squared_to(center) > float(def.range) ** 2:
				continue
			var role: String = tower.definition.economy
			if def.economy != "core" and role != ("credits" if def.economy == "credit_amp" else "rp"):
				continue
			count += 1
			output += base if role == "credits" else base * 4.0
		var percent := TowerEconomy.core_bonus(count) if def.economy == "core" else TowerEconomy.AMPLIFIER_BONUS
		if output * percent > best_output:
			best = cell
			best_output = output * percent
	if not sim.install(best, def.id):
		return false
	invested += int(def.cost)
	first_buy[int(def.id.right(2))] = sim.wave
	return true

func _buy_support(sim: Battle, id: String) -> void:
	var def := sim.tower_definition(id)
	if sim.credits < int(def.cost):
		return
	var best := Vector2i(-1, -1)
	var score := -1.0
	var radius_sq := float(def.range) ** 2
	for candidate in seats:
		if not sim.can_install(candidate, id):
			continue
		var weight := 0.0
		var center := Vector2(candidate) + Vector2(0.5, 0.5)
		for tower in sim.towers:
			if TowerRegistry.attacks(tower.definition) and (def.global or center.distance_squared_to(tower.position) <= radius_sq):
				weight += 1.0 + float(tower.definition.stage)
		if weight > score:
			best = candidate
			score = weight
	if sim.install(best, id):
		invested += int(def.cost)
		first_buy[int(id.get_slice("_", 1))] = sim.wave

func _count(sim: Battle, id: String) -> int:
	var result := 0
	for tower in sim.towers:
		if tower.definition.id == id:
			result += 1
	return result

func _buy(sim: Battle, id: String, candidates: Array[Vector2i] = []) -> bool:
	if not sim.research.unlocked.has(id) or sim.credits < int(sim.tower_definition(id).cost):
		return false
	for cell in (seats if candidates.is_empty() else candidates):
		if sim.install(cell, id):
			invested += int(sim.tower_definition(id).cost)
			var number := int(id.right(2))
			if not first_buy.has(number):
				first_buy[number] = sim.wave
			return true
	return false

func _roster_report() -> void:
	var output := FileAccess.open("res://reports/campaign-waves.md", FileAccess.WRITE)
	if output == null:
		quit(1)
		return
	output.store_line("# 50웨이브 편성 예시")
	output.store_line("")
	output.store_line("시드 7043에서 계산한 기본 슬롯입니다. 실전은 시드에 따라 달라지며, 분열 및 증식 개체는 추가됩니다. 50웨이브 예시는 슬롯 순서에 따라 180기와 495기에서 지원군 가중치를 전환한 표입니다. 보스의 체력 단계에 따라 이 전환이 앞당겨질 수 있습니다.")
	output.store_line("")
	output.store_line("| 웨이브 | 기본 슬롯 | 출현 수와 구성비 |")
	output.store_line("| ---: | ---: | --- |")
	for wave in range(1, 51):
		var amount := rules.wave_count(wave)
		var roster := WaveRoster.new(rules.mobs, wave, amount, 7043 ^ wave)
		var counts: Dictionary = {}
		for i in amount:
			var elite := 1.0
			if wave == 50:
				var phase := 2 if i > 495 else (1 if i > 180 else 0)
				elite = float(rules.balance.finale_elite[phase])
			var def := roster.next(elite)
			counts[def.id] = int(counts.get(def.id, 0)) + 1
		var rows: PackedStringArray = []
		for id in rules.mobs.definitions:
			if counts.has(id):
				var count := int(counts[id])
				rows.append("%s %d (%.1f%%)" % [rules.mobs.lookup(id).name if id != "normal" else "일반형", count, 100.0 * count / amount])
		output.store_line("| %d | %d | %s |" % [wave, amount, ", ".join(rows)])
	output.close()
	quit()

func _boss_walk() -> void:
	for multiplier in [1.0, 1.28]:
		var sim := Battle.new(map, rules, difficulty)
		var boss_def := rules.enemy_for_wave(rules.mobs.lookup("boss"), BattleData.FINAL_WAVE, difficulty)
		var boss := sim.spawn(0.0, boss_def)
		boss.speed *= multiplier
		while not sim.lost:
			sim.tick(STEP)
		print("Boss route %.1f tiles, fixed %.5f tiles/s: %.2f simulated seconds to leak" % [
			map.length(), boss.speed, sim.elapsed,
		])
	quit()

func _economy() -> void:
	var rp := 0
	var cash := 0
	var partial_rp := 0
	var partial_cash := 0
	for w in range(1, 50):
		var slots := rules.wave_count(w)
		var roster := WaveRoster.new(rules.mobs, w, slots, 7043 ^ w)
		for i in slots:
			var def := roster.next()
			var reward := int(def.reward) + (4 if def.id == "split" else 0)
			var points := roundi(float(def.reward_rp) * rules.slot_rp_multiplier(w))
			rp += points
			cash += reward
			if i % 20 != 19:
				partial_rp += points
				partial_cash += reward
		cash += rules.wave_reward(w)
		partial_cash += rules.wave_reward(w)
		if w in [10, 20, 30, 40, 45, 49]:
			print("Pool W%d RP=%d cash=%d 95pct_RP=%d 95pct_cash=%d" % [w, rp, cash, partial_rp, partial_cash])
