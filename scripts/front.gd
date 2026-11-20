extends Control

const UI_FONT := preload("res://assets/NotoSansKR.ttf")
const MARK := preload("res://assets/prism.svg")
const MINT := Color("#66f3e5")
const LIGHT := Color("#e5f3fc")
const MUTED := Color("#96adbf")
const LINE := Color("#2b4254")
const PINK := Color("#ff729a")
const GOLD := Color("#ffd18a")
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
var tower_heading: Label
var tower_stats: Label
var sell_button: Button
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
	_ui_theme.set_color("font_disabled_color", "Button", Color("#708596"))
	_ui_theme.set_constant("h_separation", "Button", 12)
	_ui_theme.set_stylebox("normal", "Button", box("#152536", "#30495c"))
	_ui_theme.set_stylebox("hover", "Button", box("#203c49", "#66f3e5"))
	_ui_theme.set_stylebox("pressed", "Button", box("#264b55", "#a1fff4"))
	_ui_theme.set_stylebox("focus", "Button", box("#00000000", "#b8fffb"))
	_ui_theme.set_stylebox("disabled", "Button", box("#101b27", "#223443"))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		_ui_theme.set_stylebox(state, "OptionButton", _ui_theme.get_stylebox(state, "Button"))
	_ui_theme.set_stylebox("panel", "PopupMenu", box("#162837", "#548090"))
	_ui_theme.set_stylebox("hover", "PopupMenu", box("#274d58", "#548090"))
	_ui_theme.set_color("font_color", "PopupMenu", LIGHT)
	_ui_theme.set_constant("v_separation", "PopupMenu", 10)
	_ui_theme.set_stylebox("slider", "HSlider", box("#1d3041", "#1d3041"))
	_ui_theme.set_stylebox("grabber_area", "HSlider", box("#307e86", "#307e86"))
	_ui_theme.set_stylebox("grabber_area_highlight", "HSlider", box("#439c9d", "#439c9d"))
	theme = _ui_theme

func box(fill: String, border: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(fill)
	style.border_color = Color(border)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
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
		button.add_theme_stylebox_override("normal", box("#174348", "#58c6c1"))
		button.add_theme_color_override("font_color", Color("#c2fff7"))
	button.pressed.connect(Sound.cue.bind(&"click"))
	button.pressed.connect(action)
	place(button, parent, rect)
	return button

func panel_at(parent: Node, rect: Rect2, fill: String = "#111d2a", border: String = "#294154") -> Panel:
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
	text_at(screen, "v0.4", 132, 977, 19, MUTED)
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
	text_at(screen, "프리즘 방어선", 48, 35, 32)
	text_at(screen, map.title + ("  /  샘플 맵" if map.sample else ""), 50, 81, 18, MUTED)
	text_at(screen, "웨이브", 579, 31, 18, MUTED)
	wave_label = text_at(screen, "", 579, 56, 32, LIGHT, 270)
	text_at(screen, "기지 체력", 886, 31, 18, MUTED)
	health_label = text_at(screen, "", 886, 56, 32, MINT)
	panel_at(screen, Rect2(1030, 77, 140, 8), "#203443", "#203443")
	health_bar = ColorRect.new()
	health_bar.color = MINT
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(health_bar, screen, Rect2(1030, 77, 140, 8))
	text_at(screen, "재화", 1230, 31, 18, MUTED)
	credits_label = text_at(screen, "", 1230, 56, 29, GOLD, 246)
	text_at(screen, "연구 포인트", 1495, 31, 18, MUTED)
	rp_label = text_at(screen, "0", 1495, 56, 29, Color("#b4a0ff"), 151)
	button_at(screen, "일시정지  ·  Esc", Rect2(1660, 45, 212, 57), show_pause)

	panel_at(screen, Rect2(1527, 147, 345, 235))
	text_at(screen, "웨이브 제어", 1550, 166, 21, MUTED)
	status = text_at(screen, "", 1550, 202, 24, LIGHT, 299)
	wave_button = button_at(screen, "웨이브 시작", Rect2(1550, 251, 299, 59), start_wave, true)
	result = text_at(screen, "", 1550, 323, 19, GOLD, 299)

	panel_at(screen, Rect2(1527, 400, 345, 185))
	text_at(screen, "타워 설치", 1550, 420, 21, MUTED)
	catalog_button = button_at(screen, "목록", Rect2(1750, 412, 99, 40), show_catalog)
	build_button = button_at(screen, "", Rect2(1550, 467, 299, 61), toggle_build, true)
	text_at(screen, "1  설치 선택   /   우클릭  취소", 1550, 540, 17, MUTED)
	research_button = button_at(screen, "연구 그물망  ·  R", Rect2(1527, 890, 345, 65), show_research, true)

	panel_at(screen, Rect2(1527, 603, 345, 265))
	tower_heading = text_at(screen, "", 1550, 624, 23, LIGHT, 299)
	tower_stats = text_at(screen, "", 1550, 674, 19, MUTED, 299)
	sell_button = button_at(screen, "포탑 판매  +%d" % int(data.turret.refund), Rect2(1550, 791, 299, 53), sell_selected)
	text_at(screen, "경로", 70, 1028, 17, MUTED)
	text_at(screen, "장애물", 170, 1028, 17, MUTED)
	text_at(screen, "생성 지점", 286, 1028, 17, MUTED)
	text_at(screen, "기지 코어", 431, 1028, 17, MUTED)
	warning_edge = panel_at(screen, Rect2(39, 138, 1458, 882), "#00000000", "#ff467d")
	warning_edge.hide()
	toast = panel_at(screen, Rect2(521, 164, 494, 63), "#112631", "#4a788a")
	toast_text = text_at(toast, "", 13, 8, 27, MINT, 468)
	toast_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.hide()
	boss_panel = panel_at(screen, Rect2(696, 1015, 792, 53), "#181e2b", "#ab7b54")
	boss_title = text_at(boss_panel, "", 14, 2, 16, GOLD, 234)
	boss_values = text_at(boss_panel, "", 250, 2, 16, LIGHT, 524)
	boss_values.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel_at(boss_panel, Rect2(14, 34, 760, 7), "#3d2934", "#3d2934")
	boss_body = ColorRect.new()
	boss_body.color = Color("#ff926f")
	boss_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(boss_body, boss_panel, Rect2(14, 34, 760, 7))
	boss_shield = ColorRect.new()
	boss_shield.color = Color("#69dfff")
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
	var blueprint := data.towers.lookup(build_id)
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
	if has_tower:
		var definition: Dictionary = battle.occupied[selected].definition
		tower_heading.text = definition.name
		var damage: String = "%d 피해" % int(definition.damage) if definition.damage > 0 else TowerRegistry.ATTACK_NAMES[definition.attack]
		tower_stats.text = "%s  ·  %s초 주기\n범위  %s%s" % [
			damage, definition.interval, TowerRegistry.reach_text(definition),
			"  ·  반경 %s칸" % definition.radius if definition.radius > 0 else "",
		]
		tower_stats.tooltip_text = definition.description
		sell_button.text = "타워 판매  +%d" % int(definition.refund)
	else:
		tower_heading.text = "선택한 타워"
		tower_stats.text = "전장 위에 배치된 타워를\n클릭하면 능력치를 볼 수 있습니다."
		tower_stats.tooltip_text = ""
		sell_button.text = "타워 판매"
	sell_button.disabled = not has_tower or battle.lost

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
			"pause", "research", "catalog":
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
	shade.color = Color(0.018, 0.035, 0.059, 0.86)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	place(shade, self, Rect2(Vector2.ZERO, Vector2(1920, 1080)))
	modal = shade
	return panel_at(modal, Rect2((Vector2(1920, 1080) - dimensions) * 0.5, dimensions), "#132331", "#4e7988")

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
	var panel := _open_modal("catalog", Vector2(1350, 838))
	text_at(panel, "타워 목록", 33, 26, 38)
	text_at(panel, "타워를 선택해 배치하거나 해금 연구로 이동하세요.", 35, 82, 20, MUTED)
	button_at(panel, "닫기", Rect2(1116, 30, 200, 54), close_modal)
	for i in data.towers.ids.size():
		var id := data.towers.ids[i]
		var def := data.towers.lookup(id)
		var ready := battle.research.unlocked.has(id)
		var affordable := battle.credits >= int(def.cost)
		var at := Vector2(34 + (i % 5) * 259, 131 + floori(i / 5.0) * 110)
		var subtitle := ("%d 재화" % int(def.cost) if affordable else "%d 재화 필요" % int(def.cost)) if ready else "연구 필요"
		var tile := button_at(panel, "%s\n%s" % [def.name, subtitle], Rect2(at, Vector2(241, 91)), _choose_tower.bind(id), ready and affordable)
		tile.add_theme_color_override("font_color", def.tint if ready else MUTED)
		tile.disabled = (ready and not affordable) or (not ready and not can_open_research())
		tile.tooltip_text = def.description

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
	for label in ["낮음", "중간", "높음"]:
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
	draw_rect(Rect2(0, 0, 1920, 1080), Color("#0b1019"))
	if game:
		draw_line(Vector2(48, 116), Vector2(1872, 116), LINE, 1.0)
		for entry: Array in [[52, "#4b8090"], [152, "#56697a"], [268, "#ff467d"], [413, "#66f3e5"]]:
			draw_rect(Rect2(entry[0], 1040, 9, 9), Color(entry[1]))
		return
	_draw_menu_art()

func _draw_menu_art() -> void:
	var center := Vector2(1315, 526)
	draw_texture_rect(_glow, Rect2(735, -50, 1160, 1160), false, Color("#1b748a"))
	var grid_offset := fmod(clock * 8.0, 64.0)
	for x in range(680, 1921, 64):
		draw_line(Vector2(x + grid_offset, 0), Vector2(x + grid_offset, 1080), Color("#172535"))
	for y in range(0, 1081, 64):
		draw_line(Vector2(680, y + grid_offset), Vector2(1920, y + grid_offset), Color("#172535"))
	for i in 4:
		var radius := 134.0 + i * 71.0
		draw_arc(center, radius, 0.0, TAU, 128, Color(MINT, 0.09), 1.2, true)
		var phase := clock * (0.08 if i % 2 == 0 else -0.11) + i * 1.7
		draw_arc(center, radius, phase, phase + 1.06, 36, Color(MINT if i % 2 == 0 else PINK, 0.36), 2.0, true)
		var marker := center + Vector2.from_angle(phase) * radius
		draw_circle(marker, 3.0 + i, Color(MINT if i % 2 == 0 else PINK, 0.65), true, -1.0, true)
	for i in 48:
		var x := 700.0 + fmod(i * 149.0 + clock * (4.0 + i % 7), 1200.0)
		var y := fmod(i * 213.0 + 21.0 * sin(clock * 0.4 + i), 1080.0)
		draw_circle(Vector2(x, y), 1.0 + i % 3, Color(MINT, 0.10 + (i % 5) * 0.034))
	var lift := Vector2(0, sin(clock * 1.1) * 9.0)
	draw_texture_rect(MARK, Rect2(center + lift - Vector2(111, 111), Vector2(222, 222)), false)
	draw_line(Vector2(681, 103), Vector2(681, 972), LINE, 1.0)
	draw_line(Vector2(132, 927), Vector2(550, 927), LINE, 1.0)
