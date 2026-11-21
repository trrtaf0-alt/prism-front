class_name CombatReference
extends RefCounted

static func number(value: float) -> String:
	var parts := String.num(value, 3).trim_suffix(".0").split(".")
	var digits := parts[0]
	for i in range(digits.length() - 3, 0, -3):
		digits = digits.insert(i, ",")
	return digits + "." + parts[1] if parts.size() > 1 else digits

static func percent(value: float) -> String:
	return number(value * 100.0) + "%"

static func tower_summary(def: Dictionary) -> String:
	var reach := TowerRegistry.reach_text(def)
	if def.support != TowerSupport.Kind.NONE:
		return "%s\n지원 범위 %s" % [def.description, reach]
	var hit := "기본 피해 %s  ·  주기 %s초" % [number(def.damage), number(def.interval)]
	if def.attack == "mark":
		hit = "받는 피해 +%s  ·  최대 %d중첩" % [percent(def.mark_bonus), def.mark_cap]
	return "%s\n사거리 %s  ·  %s" % [hit, reach, TowerRegistry.ATTACK_NAMES[def.attack]]

static func tower_text(def: Dictionary, data: BattleData) -> String:
	var rows := PackedStringArray([_heading(def.name), tower_summary(def)])
	var tier := "시작 타워" if def.stage == 0 else "%d단계" % def.stage
	rows.append("%s  ·  설치 %s  ·  판매 +%s" % [tier, number(def.cost), number(def.refund)])
	if not def.research_id.is_empty():
		rows.append("해금 연구  %s" % data.research.nodes[def.research_id].name)
	rows.append("")
	if def.support == TowerSupport.Kind.NONE:
		rows.append(def.description)
	if def.support != TowerSupport.Kind.NONE:
		rows.append("공격 타워에 적용 · 같은 계열 효과는 중복되지 않음")
		match int(def.support):
			TowerSupport.Kind.AIM:
				rows.append("전역 타워의 사거리에는 적용되지 않음")
			TowerSupport.Kind.QUANTUM:
				rows.append("범위에 공격 타워 2기 이상 필요 · 최대 단일 표적 피해의 %s를 %s초마다 추가 적용" % [percent(TowerSupport.QUANTUM_SHARE), number(TowerSupport.QUANTUM_PERIOD)])
		return "\n".join(rows)
	if def.attack == "mark":
		rows.append("표식 시전 주기  %s초" % number(def.interval))
	if def.attack == "bolt":
		var path := "유도" if def.guided else ("왕복" if def.returning else "직선")
		rows.append("탄속  %s칸/초  ·  %s  ·  %d발" % [number(def.projectile_speed), path, int(def.shots)])
	if def.radius > 0.0:
		rows.append("영향 반경  %s칸" % number(def.radius))
	if def.attack == "line":
		rows.append("공격 폭  %s칸" % number(def.width * 2.0))
	if def.max_targets > 0:
		rows.append("최대 표적  %d기" % int(def.max_targets))
	elif def.attack in ["line", "multi", "pulse", "singularity", "strike", "field", "cone"]:
		rows.append("영향 범위 내 대상 수 제한 없음")
	if def.jump_radius > 0.0:
		rows.append("연쇄 거리  %s칸" % number(def.jump_radius))
	if def.spread > 0.0:
		rows.append("확산 각도  %s°" % number(def.spread))
	if def.windup > 0.0:
		rows.append("충전·지연  %s초" % number(def.windup))
	if def.ramp > 0.0:
		rows.append("최대 범위까지  %s초" % number(def.ramp))
	if def.duration > 0.0:
		rows.append("지속 시간  %s초" % number(def.duration))
	if def.tick > 0.0:
		rows.append("지속 피해 간격  %s초" % number(def.tick))
	if def.split > 0:
		rows.append("보조탄  %d발  ·  피해 %s  ·  최대 %s칸" % [def.split, number(def.fragment_damage), number(def.fragment_range)])
	if def.slow > 0.0:
		rows.append("냉각  %s 둔화  ·  %s초" % [percent(def.slow), number(def.status_time)])
	if def.gravity_slow > 0.0:
		rows.append("중력 둔화  %s  ·  %s초  ·  냉각과 중첩" % [percent(def.gravity_slow), number(def.status_time)])
	if def.mark_bonus > 0.0:
		rows.append("표식 지속  %s초" % number(def.status_time))
	if def.shock:
		rows.append("첫 경직  %s초  ·  연속 피격 시 경직 시간 ×%s  ·  기본 최소 %s초" % [
			number(data.status_rules.shock_duration), number(data.status_rules.shock_multiplier),
			number(data.status_rules.shock_minimum),
		])
	rows.append("자동 조준  출구에 가까운 적 우선")
	return "\n".join(rows)

static func enemy_text(base: Dictionary, data: BattleData, wave: int, mode: StringName) -> String:
	var actual_wave := BattleData.FINAL_WAVE if base.boss else wave
	var unit := data.enemy_for_wave(base, actual_wave, mode)
	var appearance := "능력으로 생성" if unit.child else "%d웨이브부터 편성" % int(unit.first_wave)
	if unit.boss:
		appearance = "%d웨이브에 1기" % BattleData.FINAL_WAVE
	var rp := int(unit.reward_rp) if unit.child else roundi(float(unit.reward_rp) * data.slot_rp_multiplier(actual_wave))
	var rows := PackedStringArray([_heading(unit.name), appearance])
	if not unit.child and not unit.boss and wave < int(unit.first_wave):
		rows.append("선택한 웨이브에는 아직 등장하지 않습니다.")
	rows.append("")
	rows.append("[b]%s · %d웨이브[/b]" % [BattleData.DIFFICULTIES[mode], actual_wave])
	rows.append("본체 HP  %s  ·  자체 보호막  %s" % [number(unit.health), number(unit.shield)])
	rows.append("이동 속도  %s칸/초  ·  처치 재화  %s  ·  RP  %d" % [number(unit.speed), number(unit.reward), rp])
	rows.append("본체 피해 감소  %s  ·  고유 방해 저항  %s" % [percent(unit.armor), percent(unit.control_resist)])
	if not unit.child and not unit.boss:
		rows.append("기본 편성 가중치  %s%s" % [number(unit.weight), "  ·  웨이브 상한 %d기" % int(unit.wave_cap) if unit.wave_cap > 0 else ""])
		if unit.has("intro_cap"):
			rows.append("첫 편성 상한  %d기  ·  2웨이브마다 1기 증가" % int(unit.intro_cap))
	if wave >= int(unit.first_wave) and unit.id in WaveRoster.LIGHT_ESCORTS + WaveRoster.ESCORT_LEADERS:
		var escort := data.escort_shield(wave, mode)
		if escort > 0:
			rows.append("호위 분대 편입 시 보호막  %d" % escort)
	rows.append("")
	rows.append("[b]특징[/b]")
	if unit.shield > 0:
		rows.append("보호막이 남아 있는 동안 방해 효과 %s 감소" % percent(1.0 - EnemyRegistry.SHIELD_CONTROL_MULTIPLIER))
	_append_recovery(rows, unit.regen, unit.boost)
	if not unit.cloak.is_empty():
		rows.append("은신  %s초 주기로 %s초간 자동 조준 회피" % [number(unit.cloak.cycle), number(unit.cloak.hidden)])
	if not unit.acceleration.is_empty():
		rows.append("가속  초당 +%s칸/초  ·  최대 %s칸/초" % [number(unit.acceleration.rate), number(unit.acceleration.max_speed)])
	if not unit.guardian.is_empty():
		var guard: Dictionary = unit.guardian
		rows.append("보호막 공급  %s초마다 %s칸 내 최대 %d기에게 %d" % [number(guard.interval), number(guard.range), guard.targets, guard.shield_hp])
		rows.append("파괴 후 %s초 뒤 재부여 가능 · 중첩 없음 · 공급자가 죽어도 유지" % number(guard.rearm))
	if not unit.split_to.is_empty():
		rows.append("처치 시 %s %d기 생성" % [data.mobs.lookup(unit.split_to).name, EnemyRegistry.SPLIT_COUNT])
	if not unit.brood.is_empty():
		rows.append("%s초마다 %s 생성  ·  최대 %d기" % [number(unit.brood.interval), data.mobs.lookup(unit.brood.child).name, unit.brood.limit])
	for i in unit.phases.size():
		var phase: Dictionary = unit.phases[i]
		rows.append("")
		rows.append("[b]%d단계 · 본체 HP %s 이하[/b]" % [i + 2, percent(phase.threshold)])
		rows.append("보호막 %s  ·  이동 속도 ×%s" % [number(phase.get("shield", 0)), number(phase.get("speed_multiplier", 1.0))])
		_append_recovery(rows, phase.get("regen", {}), phase.get("boost", {}))
	rows.append("출구에 도달하면 남은 본체 HP만큼 기지에 피해")
	return "\n".join(rows)

static func _append_recovery(rows: PackedStringArray, regen: Dictionary, boost: Dictionary) -> void:
	if not regen.is_empty():
		rows.append("재생  %s초마다 본체 HP %d" % [number(regen.interval), int(regen.amount)])
	if not boost.is_empty():
		rows.append("가속 지원  %s초마다 %s칸 내 최대 %d기에게 +%s, %s초간" % [
			number(boost.interval), number(boost.range), int(boost.targets), percent(boost.bonus), number(boost.duration),
		])

static func _heading(title: String) -> String:
	return "[font_size=30][b]%s[/b][/font_size]" % title
