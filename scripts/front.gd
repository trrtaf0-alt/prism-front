extends Control

const UI_FONT := preload("res://assets/NotoSansKR.ttf")
const MARK := preload("res://assets/prism.svg")
const MINT := Color("#a9c6bd")
const LIGHT := Color("#eee9dc")
const MUTED := Color("#a5a8a5")
const LINE := Color("#3b3e3f")
const PINK := Color("#df8a86")
const GOLD := Color("#dcc197")
const NONE := Vector2i(-1, -1)

var data := BattleData.new()
var map := FieldMap.new()
var map_error := ""
var battle: Battle
var field: FieldView
var screen: Control
var modal: Control
var modal_kind := ""
var game := false
var selected := NONE
var building := false
var build_id := TowerRegistry.BASE
var rp_label: Label
var catalog_button: Button
var research_button: Button
var research_screen: ResearchScreen
var research_view: Dictionary = {}
var settings_origin := "menu"

var wave_label: Label
var health_label: Label
var credits_label: Label
var health_bar: ColorRect
var status: Label
var result: Label
var forecast: Label
var build_hint: Label
var _forecast_wave := -1
var _forecast_seed := 0
var tower_heading: Label
var tower_stats: Label
var sell_button: Button
var support_button: Button
var build_button: Button
var wave_button: Button
var boss_panel: Panel
var boss_title: Label
var boss_values: Label
var boss_body: ColorRect
var boss_shield: ColorRect
var last_base_damage := 0
var flash := 0.0
var toast: Panel
var toast_text: Label
var warning_edge: Panel
var wave_callout := ""
var callout_time := 0.0
var defeat_delay := 0.0
var clock := 0.0
var _credits_shown := -1
var _credit_flash := 0.0
var _glow: ImageTexture
var _ui_theme := Theme.new()
var _heading_font := FontVariation.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow = FieldView.make_glow()
	_init_theme()
	var map_path := "res://data/map.json"
	if not FileAccess.file_exists(map_path):
		map_path = "res://data/sample_map.json"
	map_error = map.load_map(BattleData.read_json(map_path))
	if not data.towers.error.is_empty() or not data.research.error.is_empty():
		map_error = "%s %s" % [data.towers.error, data.research.error]
	if not data.mobs.error.is_empty():
		map_error = data.mobs.error
	if not map_error.is_empty():
		push_error(map_error)
	show_menu()

func _init_theme() -> void:
	var regular := FontVariation.new()
	var weight := TextServerManager.get_primary_interface().name_to_tag("wght")
	regular.base_font = UI_FONT
	regular.variation_opentype = {weight: 460}
	regular.variation_embolden = 0.23
	_heading_font.base_font = UI_FONT
	_heading_font.variation_opentype = {weight: 650}
	_heading_font.variation_embolden = 0.55
	_ui_theme.default_font = regular
	_ui_theme.default_font_size = 22
	_ui_theme.set_color("font_color", "Label", LIGHT)
	_ui_theme.set_color("font_color", "Button", LIGHT)
	_ui_theme.set_color("font_hover_color", "Button", Color.WHITE)
	_ui_theme.set_color("font_disabled_color", "Button", Color("#797d7c"))
	_ui_theme.set_constant("h_separation", "Button", 12)
	_ui_theme.set_stylebox("normal", "Button", box("#20252a", "#414649"))
	_ui_theme.set_stylebox("hover", "Button", box("#303a3b", "#a9c6bd"))
	_ui_theme.set_stylebox("pressed", "Button", box("#354341", "#bbd0c5"))
	_ui_theme.set_stylebox("focus", "Button", box("#00000000", "#dcc197"))
	_ui_theme.set_stylebox("disabled", "Button", box("#14181d", "#2e3337"))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		_ui_theme.set_stylebox(state, "OptionButton", _ui_theme.get_stylebox(state, "Button"))
	_ui_theme.set_stylebox("panel", "PopupMenu", box("#20262b", "#626e6d"))
	_ui_theme.set_stylebox("hover", "PopupMenu", box("#34413f", "#626e6d"))
	_ui_theme.set_color("font_color", "PopupMenu", LIGHT)
	_ui_theme.set_constant("v_separation", "PopupMenu", 10)
	_ui_theme.set_stylebox("slider", "HSlider", box("#252b30", "#252b30"))
	_ui_theme.set_stylebox("grabber_area", "HSlider", box("#5b7771", "#5b7771"))
	_ui_theme.set_stylebox("grabber_area_highlight", "HSlider", box("#77968c", "#77968c"))
	theme = _ui_theme

func box(fill: String, border: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(fill)
	style.border_color = Color(border)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	return style

func place(control: Control, parent: Node, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size
	parent.add_child(control)

func text_at(parent: Node, value: String, x: float, y: float, font_size: int, color: Color = LIGHT, width: float = 0.0) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	if font_size >= 29:
		label.add_theme_font_override("font", _heading_font)
	label.add_theme_color_override("font_color", color)
	if width > 0:
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	place(label, parent, Rect2(x, y, width, 0))
	return label

func button_at(parent: Node, value: String, rect: Rect2, action: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = value
	if primary:
		button.add_theme_stylebox_override("normal", box("#35433f", "#849991"))
		button.add_theme_color_override("font_color", Color("#edf3eb"))
	button.pressed.connect(Sound.cue.bind(&"click"))
	button.pressed.connect(action)
	place(button, parent, rect)
	return button

func panel_at(parent: Node, rect: Rect2, fill: String = "#171c21", border: String = "#353a3c") -> Panel:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", box(fill, border))
	place(panel, parent, rect)
	return panel

func _drop(node: Node) -> void:
	if is_instance_valid(node):
		remove_child(node)
		node.queue_free()

func _replace_screen() -> void:
	close_modal()
	_drop(screen)
	_drop(field)
	field = null
	battle = null
	screen = Control.new()
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	move_child(screen, get_child_count() - 1)

func show_menu() -> void:
	_replace_screen()
	game = false
	defeat_delay = 0.0
	var icon := TextureRect.new()
	icon.texture = MARK
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(icon, screen, Rect2(128, 108, 58, 58))
	text_at(screen, "PRISM FRONT", 208, 116, 31, MINT)
	text_at(screen, "프리즘\n방어선", 125, 209, 102)
	text_at(screen, "50웨이브 동안 에너지 코어를 지키세요.", 131, 520, 26, MUTED)
	var play := button_at(screen, "게임 시작", Rect2(132, 615, 418, 68), start_game, true)
	play.disabled = not map_error.is_empty()
	button_at(screen, "설정", Rect2(132, 698, 418, 62), show_settings.bind("menu"))
	button_at(screen, "종료", Rect2(132, 775, 418, 62), get_tree().quit)
	if not map_error.is_empty():
		text_at(screen, "맵 오류 · " + map_error, 132, 859, 21, PINK)
	text_at(screen, "v0.5", 132, 977, 19, MUTED)
	play.grab_focus()

func start_game() -> void:
	if not map_error.is_empty():
		return
	_replace_screen()
	game = true
	selected = NONE
	building = false
	build_id = TowerRegistry.BASE
	research_view.clear()
	_credits_shown = -1
	_credit_flash = 0.0
	flash = 0.0
	wave_callout = ""
	callout_time = 0.0
	defeat_delay = 0.0
	last_base_damage = 0
	battle = Battle.new(map, data)
	battle.effect.connect(_battle_effect)
	battle.wave_started.connect(_wave_started)
	battle.wave_finished.connect(_wave_finished)
	battle.defeated.connect(_defeated)
	battle.cleared.connect(_cleared)
	battle.base_damaged.connect(_base_damage)
	battle.mob_visual.connect(_mob_announcement)
	battle.research.purchased.connect(_research_purchased)
	field = FieldView.new()
	field.battle = battle
	add_child(field)
	move_child(field, 0)
	_make_hud()
	_update_hud()

func _make_hud() -> void:
	text_at(screen, "웨이브", 34, 15, 18, MUTED)
	wave_label = text_at(screen, "", 106, 8, 26, LIGHT, 138)
	text_at(screen, "기지", 278, 15, 18, MUTED)
	health_label = text_at(screen, "", 328, 8, 26, MINT)
	panel_at(screen, Rect2(492, 24, 140, 6), "#303437", "#303437")
	health_bar = ColorRect.new()
	health_bar.color = MINT
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(health_bar, screen, Rect2(492, 24, 140, 6))
	text_at(screen, "재화", 672, 15, 18, MUTED)
	credits_label = text_at(screen, "", 727, 8, 26, GOLD, 190)
	text_at(screen, "RP", 944, 15, 18, MUTED)
	rp_label = text_at(screen, "0", 987, 8, 26, Color("#c3b5d0"), 162)
	button_at(screen, "일시정지  ·  Esc", Rect2(1726, 8, 160, 39), show_pause)

	panel_at(screen, Rect2(1614, 68, 272, 934))
	panel_at(screen, Rect2(1630, 316, 240, 1), "#3b3e3f", "#3b3e3f")
	status = text_at(screen, "", 1630, 100, 22, LIGHT, 240)
	wave_button = button_at(screen, "웨이브 시작", Rect2(1630, 144, 240, 54), start_wave, true)
	forecast = text_at(screen, "", 1630, 213, 15, MINT, 240)
	result = text_at(screen, "", 1630, 267, 16, GOLD, 240)
	_forecast_wave = -1

	text_at(screen, "타워 설치", 1630, 359, 20, MUTED)
	catalog_button = button_at(screen, "목록", Rect2(1782, 352, 88, 40), show_catalog)
	build_button = button_at(screen, "", Rect2(1630, 411, 240, 54), toggle_build, true)
	build_hint = text_at(screen, "", 1630, 478, 16, MUTED, 240)
	research_button = button_at(screen, "연구 그물망  ·  R", Rect2(1630, 895, 240, 52), show_research, true)

	panel_at(screen, Rect2(1630, 542, 240, 1), "#3b3e3f", "#3b3e3f")
	tower_heading = text_at(screen, "", 1630, 580, 21, LIGHT, 240)
	tower_stats = text_at(screen, "", 1630, 627, 17, MUTED, 240)
	sell_button = button_at(screen, "포탑 판매  +%d" % int(data.turret.refund), Rect2(1630, 755, 240, 49), sell_selected)
	support_button = button_at(screen, "지원 상태", Rect2(1630, 819, 240, 49), show_support_details)
	text_at(screen, "경로", 70, 1028, 17, MUTED)
	text_at(screen, "장애물", 170, 1028, 17, MUTED)
	text_at(screen, "생성 지점", 286, 1028, 17, MUTED)
	text_at(screen, "기지 코어", 431, 1028, 17, MUTED)
	warning_edge = panel_at(screen, Rect2(FieldView.ORIGIN, Vector2(map.size) * FieldView.CELL).grow(6), "#00000000", "#ff467d")
	warning_edge.hide()
	toast = panel_at(screen, Rect2(567, 87, 494, 63), "#1a2025", "#66615a")
	toast_text = text_at(toast, "", 13, 8, 27, MINT, 468)
	toast_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.hide()
	boss_panel = panel_at(screen, Rect2(696, 1015, 792, 53), "#1c2226", "#9f8068")
	boss_title = text_at(boss_panel, "", 14, 2, 16, GOLD, 234)
	boss_values = text_at(boss_panel, "", 250, 2, 16, LIGHT, 524)
	boss_values.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel_at(boss_panel, Rect2(14, 34, 760, 7), "#432e32", "#432e32")
	boss_body = ColorRect.new()
	boss_body.color = Color("#e1a284")
	boss_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(boss_body, boss_panel, Rect2(14, 34, 760, 7))
	boss_shield = ColorRect.new()
	boss_shield.color = Color("#8dbdc9")
	boss_shield.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(boss_shield, boss_panel, Rect2(14, 43, 760, 3))

func _update_boss_hud() -> void:
	boss_panel.visible = not battle.bosses.is_empty()
	if battle.bosses.is_empty():
		return
	var boss := battle.bosses[0]
	boss_title.text = "%s  ·  %d단계" % [boss.definition.name, boss.mob.phase + 1]
	var shield_text := "  /  보호막 %d" % boss.shield_hp if boss.shield_hp > 0 else ""
	boss_values.text = "본체 %d / %d%s" % [boss.health, boss.maximum_health, shield_text]
	boss_body.size.x = 760.0 * float(boss.health) / float(boss.maximum_health)
	boss_shield.size.x = 760.0 * float(boss.shield_hp) / maxi(1, boss.shield_max)

func _update_hud() -> void:
	_update_boss_hud()
	wave_label.text = "%d / %d" % [battle.wave, BattleData.FINAL_WAVE]
	health_label.text = "%d / %d" % [battle.health, int(data.balance.base_health)]
	var ratio := float(battle.health) / float(data.balance.base_health)
	health_bar.size.x = 140 * ratio
	health_bar.color = PINK.lerp(MINT, ratio)
	health_label.modulate = Color.WHITE.lerp(Color("#ffd3df"), flash)
	if battle.credits > _credits_shown and _credits_shown >= 0:
		_credit_flash = 0.52
	_credits_shown = battle.credits
	credits_label.text = str(battle.credits)
	credits_label.modulate = Color.WHITE.lerp(Color(1.45, 1.4, 1.22), _credit_flash)
	wave_button.disabled = battle.active or battle.lost or battle.won
	if battle.won:
		status.text = "최종 방어 성공"
	elif battle.lost:
		status.text = "방어 실패"
	elif battle.active:
		status.text = "남은 적  %d" % (battle.queued + battle.enemies.size())
	else:
		status.text = "다음 적  %d" % data.wave_count(battle.wave + 1)
	if battle.won or battle.lost:
		wave_button.text = "작전 종료"
	elif battle.active:
		wave_button.text = "최종 보스전" if battle.wave == BattleData.FINAL_WAVE else "교전 중"
	elif battle.wave == BattleData.FINAL_WAVE - 1:
		wave_button.text = "50웨이브  ·  최종 보스"
	else:
		wave_button.text = "웨이브 %d 시작" % (battle.wave + 1)
	_update_forecast()
	var blueprint := data.towers.lookup(build_id)
	var hint := "1  설치 선택   /   우클릭  취소"
	if building:
		if battle.can_install(field.hovered, build_id):
			if blueprint.support != TowerSupport.Kind.NONE:
				hint = "지원 범위  " + TowerRegistry.reach_text(blueprint)
				build_hint.modulate = Color.WHITE
			else:
				var reach := field.path_in_range(field.hovered, blueprint)
				hint = "조준 가능한 경로  %.1f칸" % reach if reach > 0.0 else "이 위치에서는 경로에 닿지 않음"
				build_hint.modulate = Color.WHITE if reach > 0.0 else PINK
		else:
			hint = "빈 타일에 마우스를 올리세요"
			build_hint.modulate = Color.WHITE
	elif battle.wave == 0 and battle.towers.is_empty():
		hint = "진입로 가까이에 포탑을 놓으세요"
		build_hint.modulate = Color.WHITE
	else:
		build_hint.modulate = Color.WHITE
	build_hint.text = hint
	var cost := int(blueprint.cost)
	rp_label.text = str(battle.research.points)
	research_button.disabled = not can_open_research()
	catalog_button.disabled = battle.lost
	catalog_button.text = "목록 %d" % battle.research.unlocked.size()
	build_button.disabled = battle.lost or battle.credits < cost
	if building:
		build_button.text = "설치할 타일 선택  ·  %d" % cost
	elif battle.credits < cost:
		build_button.text = "재화 부족  ·  %d 필요" % cost
	else:
		build_button.text = "%s  ·  %d" % [blueprint.name, cost]
	var has_tower := battle.occupied.has(selected)
	support_button.visible = has_tower
	if has_tower:
		var tower: Battle.Turret = battle.occupied[selected]
		var definition := tower.definition
		tower_heading.text = definition.name
		if definition.support != TowerSupport.Kind.NONE:
			tower_stats.text = "지원 범위  %s\n대상  %d기\n%s" % [
				TowerRegistry.reach_text(definition), battle.support.followers(tower).size(), _support_timer(tower),
			]
		else:
			var power := float(definition.damage)
			var delay := float(definition.interval)
			var damage: String = "피해  %.2f → %.2f" % [power, power * tower.damage_multiplier] if power > 0 else TowerRegistry.ATTACK_NAMES[definition.attack]
			tower_stats.text = "%s\n주기  %.2f → %.2f초\n사거리  %s → %s\n지원 효과  %d종" % [
				damage, delay, maxf(delay / tower.speed_multiplier, Battle._sequence_span(definition)),
				TowerRegistry.reach_text(definition), TowerRegistry.reach_text(tower.effective), tower.buffs.size(),
			]
		tower_stats.tooltip_text = definition.description
		sell_button.text = "타워 판매  +%d" % int(definition.refund)
	else:
		tower_heading.text = "선택한 타워"
		tower_stats.text = "배치한 타워를 클릭하면\n능력치를 볼 수 있습니다."
		tower_stats.tooltip_text = ""
		sell_button.text = "타워 판매"
	sell_button.disabled = not has_tower or battle.lost

func _update_forecast() -> void:
	forecast.visible = not (battle.active or battle.lost or battle.won)
	if not forecast.visible:
		return
	var upcoming := battle.wave + 1
	if _forecast_wave == upcoming and _forecast_seed == battle.roster_seed:
		return
	_forecast_wave = upcoming
	_forecast_seed = battle.roster_seed
	var forecast_text := ""
	if upcoming == BattleData.FINAL_WAVE:
		forecast_text = "종결 보스 1 · 지원군 %d\n체력 단계마다 보호막 갱신" % (data.wave_count(upcoming) - 1)
	else:
		var counts := battle.preview_wave()
		var threats: Array = counts.keys()
		threats.erase("normal")
		threats.sort_custom(func(a: String, b: String) -> bool:
			return counts[a] > counts[b])
		var summary := PackedStringArray()
		for i in mini(2, threats.size()):
			var id: String = threats[i]
			summary.append("%s %d" % [data.mobs.lookup(id).name, counts[id]])
		if summary.is_empty():
			forecast_text = "일반형만 등장\n진입로와 굽은 길을 노려보세요"
		else:
			forecast_text = "주요 적  " + " · ".join(summary)
			if counts.has("swift") and upcoming <= 9:
				forecast_text += "\n신속형 대응 · 속사포 / 냉각포"
			elif counts.has("armored") and upcoming <= 9:
				forecast_text += "\n중장갑 대응 · 관통포"
	forecast.text = forecast_text

func toggle_build() -> void:
	if battle.lost or battle.credits < int(data.towers.lookup(build_id).cost):
		return
	building = not building
	selected = NONE
	_sync_selection()

func sell_selected() -> void:
	if battle.sell(selected):
		selected = NONE
		_sync_selection()

func start_wave() -> void:
	battle.start_wave()

func _sync_selection() -> void:
	field.selected = selected
	field.building = building
	field.build_id = build_id
	_update_hud()

func _physics_process(delta: float) -> void:
	var live_research := modal_kind == "research" and not bool(data.balance.research_pauses_battle)
	if game and (modal == null or live_research) and not battle.lost:
		battle.tick(delta)

func _process(delta: float) -> void:
	if not game or modal == null:
		clock += delta
	if game and modal == null:
		if not battle.lost:
			field.hovered = field.cell_under(get_local_mouse_position())
		flash = maxf(0.0, flash - delta * 1.65)
		_credit_flash = maxf(0.0, _credit_flash - delta)
		callout_time = maxf(0.0, callout_time - delta)
		toast.visible = callout_time > 0.0
		toast.modulate.a = minf(1.0, callout_time * 4.0)
		toast_text.text = wave_callout
		warning_edge.visible = flash > 0.0
		warning_edge.modulate.a = flash
		if defeat_delay > 0:
			defeat_delay = maxf(0.0, defeat_delay - delta)
			if defeat_delay == 0:
				show_game_over()
		_update_hud()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		match modal_kind:
			"pause", "research", "catalog", "support":
				close_modal()
			"effects_settings":
				show_settings(settings_origin)
			"menu", "pause_settings":
				_leave_settings()
			"":
				if game and not battle.lost:
					show_pause()
		get_viewport().set_input_as_handled()
		return
	if game and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		if modal_kind == "research":
			close_modal()
		elif modal == null:
			show_research()
		get_viewport().set_input_as_handled()
		return
	if not game or modal != null or battle.lost:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_1:
		toggle_build()
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			building = false
			selected = NONE
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var cell := field.cell_under(make_input_local(event).position)
			if battle.occupied.has(cell):
				selected = cell
				building = false
			elif building:
				if battle.install(cell, build_id) and battle.credits < int(data.towers.lookup(build_id).cost):
					building = false
					selected = cell
			else:
				selected = NONE
		_sync_selection()

func _battle_effect(kind: StringName, _point: Vector2, _direction: Vector2) -> void:
	Sound.cue(kind)
	if kind == &"base":
		flash = 1.0

func _base_damage(amount: int) -> void:
	last_base_damage = amount
	if amount >= 25:
		wave_callout = "기지 피격  ·  %d 피해" % amount
		callout_time = 1.6

func _mob_announcement(kind: StringName, _start: Vector2, _end: Vector2, _tint: Color, _life: float) -> void:
	if kind == &"boss_spawn":
		wave_callout = "종결 보스 출현"
		callout_time = 2.7
	elif kind == &"boss_down":
		wave_callout = "종결 보스 격파"
		callout_time = 2.7

func _wave_started(number: int) -> void:
	Profile.record_wave(number)
	result.text = ""
	wave_callout = "웨이브 %d 시작" % number
	callout_time = 1.55
	Sound.cue(&"wave")

func _wave_finished(number: int, amount: int) -> void:
	result.text = "웨이브 %d 완료  +%d" % [number, amount]
	wave_callout = "웨이브 %d 클리어" % number
	callout_time = 2.0
	Sound.cue(&"clear")

func _defeated(_number: int) -> void:
	if modal_kind == "research":
		close_modal()
	building = false
	selected = NONE
	_sync_selection()
	field.hovered = NONE
	wave_callout = "종결 보스 탈출" if battle.boss_escaped and battle.health > 0 else "기지 코어 붕괴  ·  %d 피해" % last_base_damage
	callout_time = 0.95
	defeat_delay = 0.95

func close_modal() -> void:
	if is_instance_valid(research_screen):
		research_view = research_screen.view_state()
		research_screen = null
	_drop(modal)
	modal = null
	modal_kind = ""
	if is_instance_valid(screen):
		for control in screen.get_children():
			if control is Button:
				control.focus_mode = Control.FOCUS_ALL
	if is_instance_valid(field):
		field.frozen = false

func _open_modal(kind: String, dimensions: Vector2) -> Panel:
	close_modal()
	modal_kind = kind
	for control in screen.get_children():
		if control is Button:
			control.focus_mode = Control.FOCUS_NONE
	if is_instance_valid(field):
		field.frozen = true
	var shade := ColorRect.new()
	shade.color = Color(0.018, 0.020, 0.025, 0.86)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	place(shade, self, Rect2(Vector2.ZERO, Vector2(1920, 1080)))
	modal = shade
	return panel_at(modal, Rect2((Vector2(1920, 1080) - dimensions) * 0.5, dimensions), "#1a2026", "#6e7778")

func show_pause() -> void:
	if battle.lost:
		return
	var panel := _open_modal("pause", Vector2(480, 432))
	text_at(panel, "일시정지", 35, 29, 39)
	text_at(panel, "웨이브 %d  /  기지 %d" % [battle.wave, battle.health], 36, 93, 20, MUTED)
	button_at(panel, "계속하기", Rect2(36, 152, 408, 54), close_modal, true).grab_focus()
	button_at(panel, "설정", Rect2(36, 214, 408, 54), show_settings.bind("pause_settings"))
	button_at(panel, "다시 시작", Rect2(36, 276, 408, 54), start_game)
	button_at(panel, "메인 메뉴", Rect2(36, 338, 408, 54), show_menu)

func _cleared(record: Dictionary) -> void:
	Profile.record_clear(record)
	callout_time = 0.0
	toast.hide()
	building = false
	_sync_selection()
	var panel := _open_modal("victory", Vector2(900, 660))
	text_at(panel, "50웨이브 클리어", 42, 28, 47, MINT)
	text_at(panel, "종결 보스를 격파하고 기지 코어를 지켰습니다.", 43, 103, 21, LIGHT)
	var stats := [
		["총 플레이 시간", _duration(record.seconds)], ["최종 보스전", _duration(record.finale)],
		["남은 기지 HP", str(record.health)], ["총 처치", str(record.kills)],
		["획득 재화", str(record.credits)], ["완료 연구", "%d / 100" % int(record.research)],
		["타워 설치", "%d회" % int(record.installed)], ["최단 기록", _duration(Profile.fastest_clear)],
	]
	for i in stats.size():
		var x := 44 + int(i % 4) * 205
		var y := 170 + floori(i / 4.0) * 110
		text_at(panel, stats[i][0], x, y, 18, MUTED)
		text_at(panel, stats[i][1], x, y + 30, 29, LIGHT)
	text_at(panel, "설치한 종결 타워", 44, 402, 19, MUTED)
	var terminal := " · ".join(PackedStringArray(record.terminal))
	text_at(panel, terminal if not terminal.is_empty() else "없음", 44, 438, 23, GOLD, 812)
	if Profile.save_error:
		text_at(panel, "클리어 기록을 저장하지 못했습니다.", 44, 503, 18, PINK)
	else:
		text_at(panel, "최고 방어 기록  ·  기지 HP %d" % Profile.best_clear.health, 44, 503, 18, MUTED)
	button_at(panel, "다시 시작", Rect2(44, 564, 390, 62), start_game, true).grab_focus()
	button_at(panel, "메인 메뉴", Rect2(466, 564, 390, 62), show_menu)

func _duration(seconds: float) -> String:
	var whole := maxi(0, floori(seconds))
	return "%02d:%02d:%02d" % [floori(whole / 3600.0), floori(whole / 60.0) % 60, whole % 60]

func show_game_over() -> void:
	var panel := _open_modal("defeat", Vector2(522, 412))
	text_at(panel, "보스 탈출" if battle.boss_escaped and battle.health > 0 else "게임 오버", 36, 27, 47, PINK)
	text_at(panel, "도달 웨이브", 39, 116, 19, MUTED)
	text_at(panel, "최고 기록", 280, 116, 19, MUTED)
	text_at(panel, str(battle.wave), 39, 148, 31, LIGHT, 222)
	text_at(panel, str(Profile.best), 280, 148, 31, GOLD, 206)
	button_at(panel, "다시 시작", Rect2(36, 229, 450, 59), start_game, true).grab_focus()
	button_at(panel, "메인 메뉴", Rect2(36, 301, 450, 59), show_menu)

func show_settings(return_to: String) -> void:
	settings_origin = return_to
	var panel := _open_modal(return_to, Vector2(620, 608))
	text_at(panel, "설정", 35, 24, 42)
	_settings_slider(panel, "마스터 볼륨", 124, Profile.master, true)
	_settings_slider(panel, "효과음 볼륨", 205, Profile.effects, false)
	text_at(panel, "화면 모드", 36, 290, 21, MUTED)
	var mode := OptionButton.new()
	mode.add_item("창모드")
	mode.add_item("전체화면")
	mode.select(int(Profile.fullscreen))
	place(mode, panel, Rect2(278, 287, 306, 44))
	text_at(panel, "창 해상도", 36, 350, 21, MUTED)
	var sizes := OptionButton.new()
	for res in Profile.RESOLUTIONS:
		sizes.add_item("%d × %d" % [res.x, res.y])
	sizes.select(Profile.resolution)
	sizes.disabled = Profile.fullscreen
	place(sizes, panel, Rect2(278, 346, 306, 44))
	mode.item_selected.connect(_set_fullscreen.bind(sizes))
	sizes.item_selected.connect(_set_resolution)
	text_at(panel, "캠페인 최고 웨이브", 36, 423, 21, MUTED)
	var best_label := text_at(panel, "%d / 50" % Profile.campaign_best, 278, 418, 26, GOLD, 306)
	best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var record_text := "50웨이브 미클리어" if Profile.best_clear.is_empty() else "최고 기지 HP %d  ·  최단 %s" % [Profile.best_clear.health, _duration(Profile.fastest_clear)]
	if Profile.best > Profile.campaign_best:
		record_text += "  ·  이전 최고 %d" % Profile.best
	if Profile.save_error:
		record_text = "설정을 저장할 수 없습니다."
	text_at(panel, record_text, 36, 467, 17, PINK if Profile.save_error else MUTED, 548)
	button_at(panel, "전투 효과 설정", Rect2(36, 514, 266, 56), show_effect_settings)
	button_at(panel, "닫기", Rect2(318, 514, 266, 56), _leave_settings, true).grab_focus()

func can_open_research() -> bool:
	return game and not battle.lost and not battle.won and (not battle.active or bool(data.balance.research_available_during_wave))

func show_research(tower_id: String = "") -> void:
	if not can_open_research():
		return
	var panel := _open_modal("research", Vector2(1848, 1002))
	research_screen = ResearchScreen.new()
	place(research_screen, panel, Rect2(Vector2.ZERO, panel.size))
	research_screen.setup(self, battle.research, data.towers, research_view, tower_id)
	field.frozen = bool(data.balance.research_pauses_battle)

func _research_purchased(_id: String, tower_id: String) -> void:
	if not tower_id.is_empty():
		wave_callout = data.towers.lookup(tower_id).name + " 해금"
		callout_time = 2.0
		Sound.cue(&"clear")
	_update_hud()

func show_catalog() -> void:
	if battle.lost:
		return
	var panel := _open_modal("catalog", Vector2(1610, 838))
	text_at(panel, "타워 목록", 33, 26, 38)
	text_at(panel, "타워를 선택해 배치하거나 해금 연구로 이동하세요.", 35, 82, 20, MUTED)
	button_at(panel, "닫기", Rect2(1376, 30, 200, 54), close_modal)
	var detail := text_at(panel, "", 35, 789, 18, MUTED, 1536)
	for i in data.towers.ids.size():
		var id := data.towers.ids[i]
		var def := data.towers.lookup(id)
		var ready := battle.research.unlocked.has(id)
		var affordable := battle.credits >= int(def.cost)
		var at := Vector2(34 + (i % 6) * 259, 131 + floori(i / 6.0) * 110)
		var subtitle := "설치 %d" % int(def.cost)
		if not ready:
			subtitle += "  ·  잠김"
		elif not affordable:
			subtitle += "  ·  재화 부족"
		var tile := button_at(panel, "", Rect2(at, Vector2(241, 91)), _choose_tower.bind(id), ready and affordable)
		var tint: Color = def.tint
		var frame := TowerArt.first_frame(id)
		for layer in [frame, frame + 1]:
			var portrait := TextureRect.new()
			portrait.texture = TowerArt.icon(layer)
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
			place(portrait, tile, Rect2(1, 6, 79, 79))
		text_at(tile, def.name, 76, 6, 20, LIGHT, 157)
		var role := _tower_role(def)
		text_at(tile, role, 76, 35, 15, tint, 157)
		text_at(tile, subtitle, 76, 60, 15, MINT if ready and affordable else MUTED, 157)
		tile.disabled = (ready and not affordable) or (not ready and not can_open_research())
		tile.tooltip_text = def.description
		tile.mouse_entered.connect(_catalog_detail.bind(detail, def))
		tile.focus_entered.connect(_catalog_detail.bind(detail, def))
		tile.accessibility_name = "%s, %s, %s" % [def.name, role, subtitle]

func _catalog_detail(label: Label, definition: Dictionary) -> void:
	label.text = "%s  ·  %s" % [definition.name, definition.description]
	label.modulate = definition.tint

func _support_timer(tower: Battle.Turret) -> String:
	match int(tower.definition.support):
		TowerSupport.Kind.QUANTUM:
			var followers := battle.support.followers(tower)
			if followers.is_empty():
				return "연결 대기 · 활성 연결 없음"
			var remaining := TowerSupport.QUANTUM_PERIOD
			for follower in followers:
				remaining = minf(remaining, battle.support.time_to_quantum(follower))
			return "다음 연동까지 %.1f초" % remaining
		TowerSupport.Kind.COMMAND:
			if battle.support.command != tower:
				return "다른 코어가 동기화 주관 중"
			return ("동기화 종료까지 %.1f초" if battle.support.synchronized else "동기화까지 %.1f초") % battle.support.time_to_sync()
	return "범위 내 공격 타워를 강화합니다"

func show_support_details() -> void:
	var tower: Battle.Turret = battle.occupied.get(selected)
	if tower == null:
		return
	var panel := _open_modal("support", Vector2(690, 630))
	text_at(panel, tower.definition.name, 38, 24, 34, LIGHT, 602)
	var close := button_at(panel, "전장으로 돌아가기", Rect2(38, 543, 614, 53), close_modal, true)
	close.grab_focus()
	if tower.definition.support != TowerSupport.Kind.NONE:
		text_at(panel, tower.definition.description, 38, 87, 21, tower.definition.tint, 614)
		text_at(panel, "범위  %s   ·   적용 대상 %d기" % [TowerRegistry.reach_text(tower.definition), battle.support.followers(tower).size()], 38, 141, 21, LIGHT, 614)
		text_at(panel, _support_timer(tower), 38, 196, 20, MUTED, 614)
		return
	text_at(panel, "피해 ×%.2f   ·   공격 속도 ×%.2f   ·   사거리 %s" % [
		tower.damage_multiplier, tower.speed_multiplier, TowerRegistry.reach_text(tower.effective),
	], 38, 86, 21, LIGHT, 612)
	var row := 0
	for kind: int in tower.buffs:
		var source: Battle.Turret = tower.buffs[kind]
		text_at(panel, "%s (%d, %d)" % [source.definition.name, source.cell.x + 1, source.cell.y + 1], 38, 140 + row * 62, 20, source.definition.tint, 610)
		var detail: String = source.definition.description
		if kind == TowerSupport.Kind.COMMAND and battle.support.synchronized:
			detail += " · 작동 중"
		text_at(panel, detail, 38, 166 + row * 62, 17, MUTED, 610)
		row += 1
	if row == 0:
		text_at(panel, "현재 적용 중인 지원 효과가 없습니다.", 38, 150, 20, MUTED)

func _tower_role(def: Dictionary) -> String:
	if def.support != TowerSupport.Kind.NONE:
		return "지원  ·  " + TowerRegistry.reach_text(def)
	match def.id:
		"tower_01": return "기본 단일 표적"
		"tower_02": return "속사 · 신속형 대응"
		"tower_03": return "직선 관통 · 밀집 대응"
		"tower_04": return "산탄 · 밀집 대응"
		"tower_05": return "이동 둔화 · 신속형 대응"
	return str(TowerRegistry.ATTACK_NAMES[def.attack])

func _choose_tower(id: String) -> void:
	if not battle.research.unlocked.has(id):
		show_research(id)
		return
	if battle.credits < int(data.towers.lookup(id).cost):
		return
	build_id = id
	close_modal()
	selected = NONE
	building = true
	_sync_selection()

func show_effect_settings() -> void:
	var panel := _open_modal("effects_settings", Vector2(692, 638))
	text_at(panel, "전투 효과 설정", 35, 24, 39)
	text_at(panel, "효과 품질", 38, 108, 22, MUTED)
	var quality := OptionButton.new()
	for label in ["최소", "낮음", "보통", "높음"]:
		quality.add_item(label)
	quality.select(Profile.fx_quality)
	quality.item_selected.connect(_set_fx_quality)
	place(quality, panel, Rect2(320, 104, 334, 46))
	_visual_slider(panel, "파티클 밀도", "fx_particles", 174)
	_visual_slider(panel, "화면 섬광", "fx_flash", 262)
	_visual_slider(panel, "화면 흔들림", "fx_shake", 350)
	var dim := CheckButton.new()
	dim.text = "강한 밝기 낮추기"
	dim.button_pressed = Profile.fx_dim
	dim.toggled.connect(_set_fx_dim)
	place(dim, panel, Rect2(36, 438, 618, 55))
	button_at(panel, "설정으로 돌아가기", Rect2(36, 550, 618, 54), show_settings.bind(settings_origin), true).grab_focus()

func _visual_slider(parent: Control, title: String, key: String, y: float) -> void:
	var value := float(Profile.get(key))
	text_at(parent, title, 38, y, 21, MUTED)
	var percent := text_at(parent, "%d%%" % roundi(value * 100), 534, y, 21, MINT, 120)
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var slider := HSlider.new()
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = value * 100.0
	slider.value_changed.connect(_set_fx_value.bind(key, percent))
	place(slider, parent, Rect2(38, y + 37, 616, 25))

func _set_fx_quality(index: int) -> void:
	Profile.fx_quality = index
	Profile.save_profile()

func _set_fx_dim(enabled: bool) -> void:
	Profile.fx_dim = enabled
	Profile.save_profile()

func _set_fx_value(value: float, key: String, percent: Label) -> void:
	Profile.set(key, value / 100.0)
	percent.text = "%d%%" % roundi(value)
	Profile.save_profile()

func _settings_slider(parent: Node, name_text: String, y: float, value: float, master: bool) -> void:
	text_at(parent, name_text, 36, y - 20, 21, MUTED)
	var number := text_at(parent, "%d%%" % roundi(value * 100), 492, y - 22, 21, MINT, 92)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = roundi(value * 100)
	place(slider, parent, Rect2(36, y + 18, 548, 28))
	slider.value_changed.connect(_set_volume.bind(master, number))
	slider.drag_ended.connect(_volume_preview)

func _set_volume(value: float, master: bool, number: Label) -> void:
	if master:
		Profile.master = value / 100.0
	else:
		Profile.effects = value / 100.0
	number.text = "%d%%" % roundi(value)
	Profile.apply_audio()
	Profile.save_profile()

func _volume_preview(changed: bool) -> void:
	if changed:
		Sound.cue(&"install")

func _set_fullscreen(index: int, sizes: OptionButton) -> void:
	Profile.fullscreen = index == 1
	sizes.disabled = Profile.fullscreen
	Profile.apply_display()
	Profile.save_profile()
	Sound.cue(&"click")

func _set_resolution(index: int) -> void:
	Profile.resolution = index
	Profile.apply_display()
	Profile.save_profile()
	Sound.cue(&"click")

func _leave_settings() -> void:
	if modal_kind == "pause_settings":
		show_pause()
	else:
		close_modal()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1920, 1080), Color("#101316"))
	if game:
		draw_rect(Rect2(0, 0, 1920, 53), Color("#0a0d10"))
		draw_rect(Rect2(0, 1021, 1920, 59), Color("#0a0d10"))
		draw_line(Vector2(34, 52), Vector2(1886, 52), LINE, 1.0)
		for entry: Array in [[52, "#667069"], [152, "#62605a"], [268, "#b77a7d"], [413, "#a9c6bd"]]:
			draw_rect(Rect2(entry[0], 1040, 9, 9), Color(entry[1]))
		return
	_draw_menu_art()

func _draw_menu_art() -> void:
	var center := Vector2(1315, 526)
	draw_rect(Rect2(688, 58, 1174, 964), Color("#10151a"))
	draw_texture_rect(_glow, Rect2(698, 30, 1100, 1020), false, Color("#78604a"))
	draw_texture_rect(_glow, Rect2(995, 246, 832, 712), false, Color("#435c60"))
	for i in 3:
		var radius := 185.0 + 78.0 * i
		draw_arc(center, radius, 0.0, TAU, 128, Color("#4c4b45"), 1.0, true)
	var angle := -0.48 + sin(clock * 0.2) * 0.09
	draw_line(center - Vector2.from_angle(angle) * 470.0, center + Vector2.from_angle(angle) * 470.0, Color("#675c4d"), 1.0, true)
	draw_texture_rect(MARK, Rect2(center - Vector2(111, 111), Vector2(222, 222)), false, Color("#b0babc"))
	draw_rect(Rect2(688, 58, 1174, 964), LINE, false, 1.0)
	draw_rect(Rect2(688, 58, 1174, 41), Color("#0b0e11"))
	draw_rect(Rect2(688, 981, 1174, 41), Color("#0b0e11"))
	draw_line(Vector2(132, 927), Vector2(550, 927), LINE, 1.0)
