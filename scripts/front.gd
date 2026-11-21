extends Control

const UI_FONT := preload("res://assets/NotoSansKR.ttf")
const MENU_CYAN := Color("#a3ebf3")
const MINT := Color("#a9c6bd")
const LIGHT := Color("#eee9dc")
const MUTED := Color("#a5a8a5")
const PINK := Color("#df8a86")
const GOLD := Color("#dcc197")
const NONE := Vector2i(-1, -1)
const BASE_BAR_WIDTH := 138.0
const BOSS_BAR_WIDTH := 600.0
const INSPECT_BAR_WIDTH := 274.0
const MOBILE_READING_SIZE := Vector2(1856, 1016)

var data := BattleData.new()
var map := FieldMap.new()
var map_error := ""
var battle: Battle
var field: FieldView
var camera_fx: BattleCameraFX
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
var placement_label: Label
var _forecast_wave := -1
var _forecast_seed := 0
var tower_heading: Label
var tower_stats: Label
var sell_button: Button
var support_button: Button
var build_button: Button
var wave_button: Button
var boss_panel: Control
var boss_title: Label
var boss_values: Label
var boss_body: ColorRect
var boss_shield: ColorRect
var zoom_button: Button
var enemy_inspector: Panel
var enemy_name: Label
var enemy_hp: Label
var enemy_shield_text: Label
var enemy_hp_fill: ColorRect
var enemy_shield_fill: ColorRect
var _enemy_pick_radius := 1.0
var _panning := false
var _touch := TouchGesture.new()
var _touch_preview := NONE
var _touch_enemy := Vector2(-1, -1)
var _codex_from_pause := false
var last_base_damage := 0
var flash := 0.0
var toast: Label
var warning_edge: Panel
var wave_callout := ""
var callout_time := 0.0
var defeat_delay := 0.0
var _credits_shown := -1
var _credit_flash := 0.0
var _ui_theme := Theme.new()
var _heading_font := FontVariation.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_init_theme()
	if Profile.mobile_mode:
		_touch.tapped.connect(_tap_battlefield)
		_touch.panned.connect(_pan_battlefield_touch)
		_touch.pinched.connect(_pinch_battlefield)
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
	for def: Dictionary in data.mobs.definitions.values():
		_enemy_pick_radius = maxf(_enemy_pick_radius, float(def.scale) * 0.5 + 0.6)
	show_menu()

func _init_theme() -> void:
	var mobile: bool = Profile.mobile_mode
	var base_font: FontFile = UI_FONT
	if mobile:
		base_font = UI_FONT.duplicate() as FontFile
		base_font.hinting = TextServer.HINTING_NORMAL
		base_font.force_autohinter = true
		base_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	var regular := FontVariation.new()
	var weight := TextServerManager.get_primary_interface().name_to_tag("wght")
	regular.base_font = base_font
	regular.variation_opentype = {weight: 500 if mobile else 460}
	regular.variation_embolden = 0.0 if mobile else 0.23
	_heading_font.base_font = base_font
	_heading_font.variation_opentype = {weight: 650}
	_heading_font.variation_embolden = 0.0 if mobile else 0.55
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
	var mobile: bool = Profile.mobile_mode
	var style := StyleBoxFlat.new()
	style.bg_color = Color(fill)
	style.border_color = Color(border)
	style.set_border_width_all(3 if mobile else 1)
	style.set_corner_radius_all(0 if mobile else 3)
	style.anti_aliasing = not mobile
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
	if Profile.mobile_mode:
		button.add_theme_font_size_override("font_size", clampi(roundi(rect.size.y * 0.39), 22, 33))
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

func mobile_reading_text(label: RichTextLabel) -> void:
	for style in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]:
		label.add_theme_font_size_override(style, 34)
	label.add_theme_constant_override("line_separation", 14)
	var gesture := TouchGesture.new()
	label.gui_input.connect(func(event: InputEvent): gesture.handle(event))
	gesture.panned.connect(func(delta: Vector2): label.get_v_scroll_bar().value -= delta.y)

func _drop(node: Node) -> void:
	if is_instance_valid(node):
		remove_child(node)
		node.queue_free()

func _replace_screen() -> void:
	if battle != null:
		Sound.stop_battle_cues()
	close_modal()
	_drop(screen)
	_drop(camera_fx)
	_drop(field)
	camera_fx = null
	field = null
	battle = null
	screen = Control.new()
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Profile.mobile_mode:
		screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(screen)
	move_child(screen, get_child_count() - 1)
	queue_redraw()

func show_menu() -> void:
	_replace_screen()
	Sound.play_music(&"patrol")
	game = false
	defeat_delay = 0.0
	text_at(screen, "PRISM FRONT", 160, 385, 84, Color("#edf5f9"))

	var mobile: bool = Profile.mobile_mode
	var play := button_at(screen, "게임 시작", Rect2(165, 550, 414, 91) if mobile else Rect2(165, 550, 330, 70), show_difficulty)
	play.name = "StartGame"
	play.add_theme_font_size_override("font_size", 38 if mobile else 27)
	_style_menu_button(play, MENU_CYAN, true)
	play.disabled = not map_error.is_empty()

	var settings := button_at(screen, "설정", Rect2(165, 664, 130, 76) if mobile else Rect2(165, 636, 102, 53), show_settings.bind("menu"))
	var codex := button_at(screen, "도감", Rect2(307, 664, 130, 76) if mobile else Rect2(279, 636, 102, 53), show_codex)
	var exit := button_at(screen, "종료", Rect2(449, 664, 130, 76) if mobile else Rect2(393, 636, 102, 53), get_tree().quit)
	for button in [settings, codex, exit]:
		_style_menu_button(button, MENU_CYAN)
		button.add_theme_stylebox_override("normal", box("#0b141d", "#293c48"))
	if map_error.is_empty():
		play.grab_focus()
	else:
		text_at(screen, "맵 오류 · " + map_error, 165, 716, 21, PINK, 580)
		settings.grab_focus()

func _style_menu_button(button: Button, accent: Color, primary: bool = false) -> void:
	var border := "#" + accent.to_html(false)
	button.add_theme_stylebox_override("normal", box("#a4dde1" if primary else "#0c141bd9", border if primary else "#344756"))
	button.add_theme_stylebox_override("hover", box("#c6f2f3" if primary else "#203b48", border))
	button.add_theme_stylebox_override("pressed", box("#82bdc4" if primary else "#274954", border))
	var focus := box("#00000000", border)
	focus.set_expand_margin_all(4.0)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_color", Color("#0b1b24") if primary else Color("#c4d4df"))
	if primary:
		for state in ["font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(state, Color("#0b1b24"))

func show_difficulty() -> void:
	var mobile: bool = Profile.mobile_mode
	var panel := _open_modal("difficulty", Vector2(932, 470) if mobile else Vector2(932, 438))
	text_at(panel, "난이도 선택", 34, 21, 40)
	_style_menu_button(button_at(panel, "돌아가기", Rect2(737, 20, 161, 64) if mobile else Rect2(768, 28, 130, 46), close_modal), MENU_CYAN)
	_style_menu_button(button_at(panel, "제약 모드", Rect2(34, 355, 264, 78) if mobile else Rect2(34, 355, 196, 48), show_constraints), MENU_CYAN)
	var colors := [MENU_CYAN, GOLD, PINK]
	var index := 0
	for mode: StringName in BattleData.DIFFICULTIES:
		var x := 34.0 + index * 292.0
		var option := button_at(panel, "", Rect2(x, 95, 280, 238), start_game.bind(mode))
		_style_menu_button(option, colors[index])
		var name_text: String = BattleData.DIFFICULTIES[mode]
		option.accessibility_name = name_text
		text_at(option, name_text, 20, 20, 35, colors[index], 240)
		var entry := Profile.campaign_record(mode)
		var progress := "최고 %d / 50" % int(entry.wave)
		if entry.fastest_clear > 0.0:
			progress = "최단 " + _duration(entry.fastest_clear)
		text_at(option, progress, 20, 183, 17, colors[index], 240)
		if mode == &"normal":
			option.grab_focus()
		index += 1

func show_constraints() -> void:
	var panel := _open_modal("constraints", Vector2(1342, 950) if Profile.mobile_mode else Vector2(1342, 860))
	var picker := ConstraintsScreen.new()
	place(picker, panel, Rect2(Vector2.ZERO, panel.size))
	picker.setup(self)

func start_game(difficulty: StringName = &"easy", levels: Dictionary = {}) -> void:
	if not map_error.is_empty():
		return
	_replace_screen()
	Sound.play_music(&"patrol")
	game = true
	selected = NONE
	building = false
	_panning = false
	_reset_battle_touch()
	build_id = TowerRegistry.BASE
	research_view.clear()
	_credits_shown = -1
	_credit_flash = 0.0
	flash = 0.0
	wave_callout = ""
	callout_time = 0.0
	defeat_delay = 0.0
	last_base_damage = 0
	battle = Battle.new(map, data, difficulty, levels)
	battle.effect.connect(_battle_effect)
	battle.tower_installed.connect(Sound.deploy_cue)
	battle.attack_visual.connect(Sound.attack_cue)
	battle.mob_visual.connect(Sound.mob_cue)
	battle.support_visual.connect(Sound.support_cue)
	battle.wave_started.connect(_wave_started)
	battle.wave_finished.connect(_wave_finished)
	battle.defeated.connect(_defeated)
	battle.cleared.connect(_cleared)
	battle.base_damaged.connect(_base_damage)
	battle.mob_visual.connect(_boss_event)
	battle.research.purchased.connect(_research_purchased)
	field = FieldView.new()
	field.battle = battle
	add_child(field)
	move_child(field, 0)
	camera_fx = BattleCameraFX.new()
	add_child(camera_fx)
	move_child(camera_fx, 1)
	camera_fx.setup(field, Profile)
	_make_hud()
	_update_hud()

func _make_hud() -> void:
	var mobile: bool = Profile.mobile_mode
	var caption_y := 14 if mobile else 22
	_hud_text(screen, "웨이브", 86, caption_y, 17, MUTED, 126)
	wave_label = _hud_text(screen, "", 86, 43, 28, LIGHT, 126)
	_hud_text(screen, "기지", 249, caption_y, 17, MUTED, 152)
	health_label = _hud_text(screen, "", 249, 43, 28, MINT, 154)
	panel_at(screen, Rect2(250, 84, BASE_BAR_WIDTH, 3), "#131d22", "#131d22")
	health_bar = ColorRect.new()
	health_bar.color = MINT
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(health_bar, screen, Rect2(250, 84, BASE_BAR_WIDTH, 3))
	_hud_text(screen, "재화", 442, caption_y, 17, MUTED, 156)
	credits_label = _hud_text(screen, "", 442, 43, 28, GOLD, 156)
	_hud_text(screen, "RP", 626, caption_y, 17, MUTED, 146)
	rp_label = _hud_text(screen, "0", 626, 43, 28, Color("#c3b5d0"), 146)
	_hud_text(screen, BattleData.DIFFICULTIES[battle.difficulty], 800, 46, 19, MUTED, 110)
	if battle.constraints.active():
		var constraint_badge := _hud_text(screen, "제약 %d종" % battle.constraints.count(), 800, 74, 17, MENU_CYAN, 110)
		constraint_badge.name = "ActiveConstraints"
		constraint_badge.mouse_filter = Control.MOUSE_FILTER_PASS
		constraint_badge.mouse_default_cursor_shape = Control.CURSOR_HELP
		constraint_badge.tooltip_text = battle.constraints.summary_text()
	zoom_button = _hud_button("100%", Rect2(924, 23, 118, 75) if mobile else Rect2(928, 38, 106, 44), _reset_zoom)
	zoom_button.tooltip_text = "두 손가락으로 확대·축소 · 눌러서 초기화" if mobile else "휠: 확대·축소  ·  휠 드래그: 이동  ·  클릭: 초기화"
	var reference := _hud_button("도감" if mobile else "도감 · K", Rect2(1052, 23, 124, 75) if mobile else Rect2(1048, 38, 124, 44), show_codex)
	reference.name = "BattleCodex"
	reference.tooltip_text = "타워와 적의 능력치 · 열람 중 전투 일시정지"

	# Center the actions on the seam between tile rows, leaving tile centers clickable.
	_hud_button("일시정지" if mobile else "일시정지 · Esc", Rect2(1692, 23, 170, 75) if mobile else Rect2(1704, 38, 158, 44), show_pause)
	wave_button = _hud_button("웨이브 시작", Rect2(1457, 23, 220, 75) if mobile else Rect2(1500, 38, 190, 44), start_wave, true)
	status = _right_hud_text("", 1190, 46, 20, LIGHT, 253 if mobile else 294)
	forecast = _right_hud_text("", 1272 if mobile else 1460, 104 if mobile else 93, 17, MINT, 590 if mobile else 402)
	result = _right_hud_text("", 1272 if mobile else 1460, 176 if mobile else 148, 17, GOLD, 590 if mobile else 402)
	_forecast_wave = -1

	build_button = _hud_button("", Rect2(1050, 970, 394, 79) if mobile else Rect2(1166, 998, 316, 44), toggle_build, true)
	build_button.toggle_mode = true
	build_button.tooltip_text = "같은 타워 배치 · 1"
	catalog_button = _hud_button("타워 선택", Rect2(1458, 970, 180, 79) if mobile else Rect2(1496, 998, 148, 44), show_catalog)
	research_button = _hud_button("연구" if mobile else "연구 · R", Rect2(1652, 970, 210, 79) if mobile else Rect2(1658, 998, 204, 44), show_research)
	build_hint = _right_hud_text("", 1275 if mobile else 1100, 931 if mobile else 1046, 16, MUTED, 587 if mobile else 762)
	placement_label = _hud_text(screen, "", 0, 0, 18, LIGHT, 0)
	placement_label.add_theme_stylebox_override("normal", box("#121a22f0", "#536b70ad"))
	placement_label.hide()
	tower_heading = _hud_text(screen, "", 86, 855 if mobile else 871, 26, LIGHT, 500)
	tower_stats = _hud_text(screen, "", 86, 894 if mobile else 911, 17, MINT, 560)
	sell_button = _hud_button("타워 판매", Rect2(86, 970, 208, 79) if mobile else Rect2(86, 998, 168, 44), sell_selected)
	support_button = _hud_button("지원 상태", Rect2(310, 970, 190, 79) if mobile else Rect2(268, 998, 144, 44), show_support_details)

	warning_edge = panel_at(screen, FieldView.SCREEN.grow(-3), "#00000000", "#ff467d")
	warning_edge.hide()
	toast = _hud_text(screen, "", 628, 146, 26, MINT, 664)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.hide()

	boss_panel = Control.new()
	boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(boss_panel, screen, Rect2(660, 867 if mobile else 904, BOSS_BAR_WIDTH, 90 if mobile else 53))
	boss_title = _hud_text(boss_panel, "", 0, 0, 18, GOLD, BOSS_BAR_WIDTH if mobile else 155)
	boss_values = _hud_text(boss_panel, "", 0 if mobile else 155, 30 if mobile else 0, 17, LIGHT, BOSS_BAR_WIDTH if mobile else 445)
	boss_values.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var boss_bar_y := 64 if mobile else 31
	panel_at(boss_panel, Rect2(0, boss_bar_y, BOSS_BAR_WIDTH, 6), "#432e32", "#432e32")
	boss_body = ColorRect.new()
	boss_body.color = Color("#e1a284")
	boss_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(boss_body, boss_panel, Rect2(0, boss_bar_y, BOSS_BAR_WIDTH, 6))
	boss_shield = ColorRect.new()
	boss_shield.color = Color("#8dbdc9")
	boss_shield.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(boss_shield, boss_panel, Rect2(0, boss_bar_y + 9, BOSS_BAR_WIDTH, 2))
	_make_enemy_inspector()

func _make_enemy_inspector() -> void:
	var mobile: bool = Profile.mobile_mode
	var width := 420.0 if mobile else INSPECT_BAR_WIDTH
	enemy_inspector = panel_at(screen, Rect2(0, 0, width + 32, 88), "#111922f5", "#536675")
	enemy_name = text_at(enemy_inspector, "", 16, 8, 28 if mobile else 22, LIGHT, width)
	enemy_hp = text_at(enemy_inspector, "", 16, 45 if mobile else 38, 24 if mobile else 18, LIGHT, width)
	enemy_hp_fill = _inspection_bar(80.0 if mobile else 67.0, width, Color("#e58b9c"))
	enemy_shield_text = text_at(enemy_inspector, "", 16, 92 if mobile else 79, 24 if mobile else 17, Color("#a6e1fa"), width)
	enemy_shield_fill = _inspection_bar(127.0 if mobile else 107.0, width, Color("#7ecdff"))
	enemy_inspector.hide()

func _inspection_bar(y: float, width: float, color: Color) -> ColorRect:
	var track := panel_at(enemy_inspector, Rect2(16, y, width, 5), "#2b3846", "#2b3846")
	var fill := ColorRect.new()
	fill.color = color
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(fill, track, Rect2(0, 0, width, 5))
	return fill

func _inspect_enemy(point: Vector2) -> void:
	if building or battle.lost or battle.won or not FieldView.SCREEN.has_point(point):
		enemy_inspector.hide()
		return
	var cursor := camera_fx.world_under(point)
	var closest := INF
	var target: Battle.Drone
	for drone in battle.query_box(cursor, cursor, _enemy_pick_radius):
		var at := MobView.visual_position(drone, battle.elapsed, FieldView.CELL)
		var distance := cursor.distance_squared_to(at)
		if distance < closest and distance <= pow(maxf(0.21, drone.scale * 0.47), 2.0):
			closest = distance
			target = drone
	if target == null:
		enemy_inspector.hide()
		return
	enemy_name.text = target.definition.name
	enemy_hp.text = "본체 HP  %s / %s" % [CombatReference.number(target.health), CombatReference.number(target.maximum_health)]
	enemy_hp_fill.size.x = enemy_hp.size.x * float(target.health) / target.maximum_health
	var shielded := target.shield_hp > 0
	enemy_shield_text.visible = shielded
	(enemy_shield_fill.get_parent() as Control).visible = shielded
	if shielded:
		enemy_shield_text.text = "보호막  %s / %s" % [CombatReference.number(target.shield_hp), CombatReference.number(target.shield_max)]
		enemy_shield_fill.size.x = enemy_shield_text.size.x * float(target.shield_hp) / maxi(1, target.shield_max)
	enemy_inspector.size.y = enemy_shield_fill.get_parent().position.y + 20.0 if shielded else enemy_hp_fill.get_parent().position.y + 21.0
	var offset := Vector2(23.0, -enemy_inspector.size.y - 14.0)
	if point.y + offset.y < 95.0:
		offset.y = 21.0
	enemy_inspector.position = (point + offset).clamp(Vector2(16, 95), FieldView.SCREEN.end - enemy_inspector.size - Vector2(16, 88))
	enemy_inspector.show()

func _reset_zoom() -> void:
	camera_fx.reset_zoom()
	_update_zoom_button()

func _update_zoom_button() -> void:
	zoom_button.text = "%d%%" % roundi(camera_fx.manual_zoom * 100.0)

func _hud_text(parent: Control, value: String, x: float, y: float, font_size: int, color: Color, width: float) -> Label:
	var mobile: bool = Profile.mobile_mode
	var tint := color.lerp(LIGHT, 0.50) if mobile and color == MUTED else color
	var label := text_at(parent, value, x, y, maxi(font_size, 24) if mobile else font_size, tint, width)
	label.add_theme_color_override("font_outline_color", Color("#080d12e6"))
	label.add_theme_constant_override("outline_size", 0 if mobile else 4)
	return label

func _right_hud_text(value: String, x: float, y: float, font_size: int, color: Color, width: float) -> Label:
	var label := _hud_text(screen, value, x, y, font_size, color, width)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label

func _hud_button(value: String, rect: Rect2, action: Callable, primary: bool = false) -> Button:
	var button := button_at(screen, value, rect, action)
	if Profile.mobile_mode:
		button.add_theme_font_size_override("font_size", 29)
		button.add_theme_stylebox_override("normal", box("#192b2b" if primary else "#121a22", "#829d95" if primary else "#586873"))
		button.add_theme_stylebox_override("disabled", box("#101820", "#34414a"))
	else:
		button.add_theme_font_size_override("font_size", 19)
		button.add_theme_stylebox_override("normal", box("#192b2bcf" if primary else "#121a22c7", "#829d958f" if primary else "#58687378"))
		button.add_theme_stylebox_override("disabled", box("#101820a3", "#34414a68"))
	return button

func _update_boss_hud() -> void:
	boss_panel.visible = not battle.bosses.is_empty()
	if battle.bosses.is_empty():
		return
	var boss := battle.bosses[0]
	boss_title.text = "%s  ·  %d단계" % [boss.definition.name, boss.mob.phase + 1]
	var mobile: bool = Profile.mobile_mode
	var health := CombatReference.number(boss.health) if mobile else str(boss.health)
	var max_health := CombatReference.number(boss.maximum_health) if mobile else str(boss.maximum_health)
	var shield := CombatReference.number(boss.shield_hp) if mobile else str(boss.shield_hp)
	boss_values.text = "본체 %s / %s" % [health, max_health]
	if boss.shield_hp > 0:
		boss_values.text += "  /  보호막 " + shield
	boss_body.size.x = BOSS_BAR_WIDTH * float(boss.health) / float(boss.maximum_health)
	boss_shield.size.x = BOSS_BAR_WIDTH * float(boss.shield_hp) / maxi(1, boss.shield_max)

func _update_hud() -> void:
	_update_boss_hud()
	wave_label.text = "%d / %d" % [battle.wave, BattleData.FINAL_WAVE]
	health_label.text = "%d / %d" % [battle.health, int(data.balance.base_health)]
	var ratio := float(battle.health) / float(data.balance.base_health)
	health_bar.size.x = BASE_BAR_WIDTH * ratio
	health_bar.color = PINK.lerp(MINT, ratio)
	health_label.modulate = Color.WHITE.lerp(Color("#ffd3df"), flash)
	if battle.credits > _credits_shown and _credits_shown >= 0:
		_credit_flash = 0.52
	_credits_shown = battle.credits
	credits_label.text = str(battle.credits)
	credits_label.modulate = Color.WHITE.lerp(Color(1.45, 1.4, 1.22), _credit_flash)
	wave_button.disabled = battle.active or battle.lost or battle.won
	if battle.won:
		status.text = "방어 성공"
	elif battle.lost:
		status.text = "방어 실패"
	elif battle.active:
		status.text = "남은 적  %d" % (battle.queued + battle.enemies.size())
	else:
		status.text = "다음 적  %d" % data.wave_count(battle.wave + 1)
	if battle.won or battle.lost:
		wave_button.text = "작전 종료"
	elif battle.active:
		wave_button.text = "보스전" if battle.wave == BattleData.FINAL_WAVE else "교전 중"
	elif battle.wave == BattleData.FINAL_WAVE - 1:
		wave_button.text = "50웨이브 시작"
	else:
		wave_button.text = "웨이브 %d 시작" % (battle.wave + 1)
	_update_forecast()
	_update_placement()
	rp_label.text = str(battle.research.points)
	research_button.disabled = not can_open_research()
	catalog_button.disabled = battle.lost or battle.won
	catalog_button.tooltip_text = "해금된 타워 %d종" % battle.research.unlocked.size()
	var has_tower := battle.occupied.has(selected)
	for control: Control in [tower_heading, tower_stats, sell_button, support_button]:
		control.visible = has_tower
	if building and not has_tower:
		var definition := battle.tower_definition(build_id)
		tower_heading.show()
		tower_stats.show()
		tower_heading.text = definition.name
		tower_stats.text = CombatReference.tower_summary(definition)
		tower_stats.tooltip_text = definition.description
	if has_tower:
		var tower: Battle.Turret = battle.occupied[selected]
		var definition := tower.definition
		tower_heading.text = definition.name
		if definition.support != TowerSupport.Kind.NONE:
			tower_stats.text = "지원 범위  %s   ·   대상  %d기\n%s" % [
				TowerRegistry.reach_text(definition), battle.support.followers(tower).size(), _support_timer(tower),
			]
		else:
			var power := float(definition.damage)
			var delay := float(definition.interval)
			var damage: String = "피해  %.2f → %.2f" % [power, power * tower.damage_multiplier] if power > 0 else TowerRegistry.ATTACK_NAMES[definition.attack]
			tower_stats.text = "%s   ·   주기  %.2f → %.2f초\n사거리  %s → %s   ·   지원  %d종" % [
				damage, delay, maxf(delay / tower.speed_multiplier, Battle._sequence_span(definition)),
				TowerRegistry.reach_text(definition), TowerRegistry.reach_text(tower.effective), tower.buffs.size(),
			]
		tower_stats.tooltip_text = definition.description
		sell_button.text = "타워 판매  +%d" % int(definition.refund)
	sell_button.disabled = not has_tower or battle.lost

func _update_placement() -> void:
	var blueprint := battle.tower_definition(build_id)
	var cost := int(blueprint.cost)
	var available := not battle.lost and not battle.won
	build_button.disabled = not available or (not building and battle.credits < cost)
	build_button.set_pressed_no_signal(building and available)
	build_button.text = "%s  ·  %d" % [blueprint.name, cost]
	build_hint.text = ""
	placement_label.hide()
	if not available:
		return
	if battle.at_tower_limit():
		build_hint.text = "타워 %d / %d기 · 설치 한도" % [battle.towers.size(), battle.tower_limit()]
	elif battle.credits < cost:
		build_hint.text = "재화 %d 부족" % (cost - battle.credits)
	elif not building and not Profile.mobile_mode:
		build_hint.text = "1  빠른 배치"
	if not building or modal != null:
		return
	if Profile.mobile_mode:
		if battle.credits >= cost and not battle.at_tower_limit():
			build_hint.text = "칸을 두 번 눌러 설치 · 배치 버튼으로 취소"
	elif battle.at_tower_limit():
		build_hint.text += "   ·   Esc 취소"
	else:
		build_hint.text = "좌클릭  배치   ·   우클릭 / Esc  취소" if battle.credits >= cost else "%s   ·   Esc  취소" % build_hint.text
	var cell := field.hovered
	var status_at_tile := battle.placement_status(cell, build_id)
	if status_at_tile == Battle.Placement.OUTSIDE:
		return
	var message := ""
	match status_at_tile:
		Battle.Placement.READY:
			if blueprint.support != TowerSupport.Kind.NONE:
				message = "지원 범위 %s" % TowerRegistry.reach_text(blueprint)
			else:
				var reach := field.path_in_range(cell, blueprint)
				message = "조준 가능한 경로 %.1f칸" % reach if reach > 0.0 else "설치 가능 · 경로가 사거리 밖"
		Battle.Placement.OCCUPIED:
			message = "이미 타워가 있습니다"
		Battle.Placement.TERRAIN:
			message = "장애물" if map.tile_at(cell) == "#" else "적 이동 경로"
		Battle.Placement.LIMIT:
			message = "설치 한도 %d기" % battle.tower_limit()
		Battle.Placement.FUNDS:
			message = "재화 %d 부족" % (cost - battle.credits)
		Battle.Placement.LOCKED:
			message = "연구 필요"
		_:
			return
	if placement_label.text != message:
		placement_label.text = message
		placement_label.reset_size()
	placement_label.add_theme_color_override("font_color", MINT if status_at_tile == Battle.Placement.READY else PINK)
	var center := field.transform * FieldView.pixel(Vector2(cell) + Vector2.ONE * 0.5)
	var x := minf(center.x + 38.0, FieldView.SCREEN.end.x - placement_label.size.x - 24.0)
	var y := clampf(center.y - 27.0, 112.0, 950.0)
	placement_label.position = Vector2(x, y)
	placement_label.show()

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
	var escort := data.escort_shield(upcoming, battle.difficulty, battle.constraints) > 0
	if upcoming == BattleData.FINAL_WAVE:
		forecast_text = "보스 1 · 지원군 %d\n단계 전환 시 보호막 갱신" % (data.wave_count(upcoming) - 1)
		if escort:
			forecast_text += " · 호위 분대"
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
			elif escort:
				forecast_text += "\n호위 분대 · 보라색 보호막"
	forecast.text = forecast_text

func toggle_build() -> void:
	if battle.lost or battle.won or (not building and battle.credits < int(battle.tower_definition(build_id).cost)):
		return
	building = not building
	_reset_battle_touch()
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
	if game and modal == null:
		camera_fx.update(delta)
		if not battle.lost and Profile.mobile_mode:
			field.hovered = _touch_preview if building else NONE
			if FieldView.SCREEN.has_point(_touch_enemy):
				_inspect_enemy(_touch_enemy)
		elif not battle.lost:
			var hovered_control := get_viewport().gui_get_hovered_control()
			var cursor := get_local_mouse_position()
			field.hovered = NONE if hovered_control is Button or _panning else camera_fx.cell_under(cursor)
			if hovered_control is Button or _panning:
				enemy_inspector.hide()
			else:
				_inspect_enemy(cursor)
		flash = maxf(0.0, flash - delta * 1.65)
		_credit_flash = maxf(0.0, _credit_flash - delta)
		callout_time = maxf(0.0, callout_time - delta)
		toast.visible = callout_time > 0.0
		toast.modulate.a = minf(1.0, callout_time * 4.0)
		toast.text = wave_callout
		warning_edge.visible = flash > 0.0
		warning_edge.modulate.a = flash
		if defeat_delay > 0:
			defeat_delay = maxf(0.0, defeat_delay - delta)
			if defeat_delay == 0:
				show_game_over()
		_update_hud()

func _input(event: InputEvent) -> void:
	if Profile.mobile_mode and game and modal == null and (event is InputEventScreenTouch or event is InputEventScreenDrag):
		if _touch.tracks(event.index) and _touch.handle(make_input_local(event)):
			get_viewport().set_input_as_handled()
			return
	if not _panning:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		_panning = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var motion := make_input_local(event) as InputEventMouseMotion
		camera_fx.pan_by(motion.relative)
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if not is_node_ready() or not Profile.mobile_mode:
		return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		_reset_battle_touch()
		if game and modal == null and not battle.lost and not battle.won:
			show_pause()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()
		return
	if _handle_shortcuts(event):
		return
	if not game or modal != null or battle.lost or battle.won:
		return
	if Profile.mobile_mode and event is InputEventScreenTouch and event.pressed:
		var touch := make_input_local(event) as InputEventScreenTouch
		if FieldView.SCREEN.has_point(touch.position) and _touch.handle(touch):
			get_viewport().set_input_as_handled()
		return
	if Profile.mobile_mode and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	_handle_battle_mouse(event)

func _back() -> void:
	match modal_kind:
		"pause", "research", "catalog", "support", "difficulty":
			close_modal()
		"constraints":
			show_difficulty()
		"codex":
			_close_codex()
		"effects_settings":
			show_settings(settings_origin)
		"menu", "pause_settings":
			_leave_settings()
		"":
			if game and not battle.lost:
				if building:
					toggle_build()
				else:
					show_pause()

func _handle_shortcuts(event: InputEvent) -> bool:
	if game and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		if modal_kind == "research":
			close_modal()
		elif modal == null:
			show_research()
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_K:
		if modal_kind == "codex":
			_close_codex()
		elif modal == null or modal_kind == "pause":
			show_codex()
		get_viewport().set_input_as_handled()
		return true
	return false

func _handle_battle_mouse(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_1:
		toggle_build()
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var factor := 1.16 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.16
			camera_fx.zoom_at(make_input_local(event).position, factor)
			_update_zoom_button()
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = camera_fx.manual_zoom > 1.0
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			building = false
			selected = NONE
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var cell := camera_fx.cell_under(make_input_local(event).position)
			if building:
				field.hovered = cell
				battle.install(cell, build_id)
			else:
				selected = cell if battle.occupied.has(cell) else NONE
		_sync_selection()

func _reset_battle_touch() -> void:
	_touch.clear()
	_touch_preview = NONE
	_touch_enemy = Vector2(-1, -1)

func _tap_battlefield(point: Vector2) -> void:
	if not FieldView.SCREEN.has_point(point):
		return
	var cell := camera_fx.cell_under(point)
	if building:
		_touch_enemy = Vector2(-1, -1)
		if cell == _touch_preview and cell != NONE:
			battle.install(cell, build_id)
		_touch_preview = cell
		field.hovered = cell
	else:
		selected = cell if battle.occupied.has(cell) else NONE
		_touch_enemy = point if selected == NONE else Vector2(-1, -1)
		_inspect_enemy(_touch_enemy)
	_sync_selection()

func _pan_battlefield_touch(delta: Vector2) -> void:
	_touch_preview = NONE
	_touch_enemy = Vector2(-1, -1)
	enemy_inspector.hide()
	if camera_fx.manual_zoom > 1.0:
		camera_fx.pan_by(delta)

func _pinch_battlefield(before: Vector2, after: Vector2, factor: float) -> void:
	camera_fx.zoom_at(before, factor)
	_pan_battlefield_touch(after - before)
	_update_zoom_button()

func _battle_effect(kind: StringName, _point: Vector2, _direction: Vector2) -> void:
	if kind != &"install":
		Sound.cue(kind)
	if kind == &"base":
		flash = 1.0

func _base_damage(amount: int) -> void:
	last_base_damage = amount
	if amount >= 25:
		wave_callout = "기지 피격  ·  %d 피해" % amount
		callout_time = 1.6

func _boss_event(kind: StringName, _start: Vector2, _end: Vector2, _tint: Color, _life: float) -> void:
	if kind == &"boss_spawn":
		Sound.play_music(&"boss", 0.55)
	elif kind == &"boss_down":
		Sound.play_music(&"patrol", 1.8)
		wave_callout = "보스 격파"
		callout_time = 2.7

func _wave_started(number: int) -> void:
	if not battle.constraints.active():
		Profile.record_wave(number, battle.difficulty)
	result.text = ""
	if number == BattleData.FINAL_WAVE:
		wave_callout = ""
		callout_time = 0.0
		toast.hide()
	else:
		wave_callout = "웨이브 %d 시작" % number
		callout_time = 1.55
	Sound.cue(&"wave")

func _wave_finished(number: int, amount: int) -> void:
	result.text = "웨이브 %d 완료  +%d" % [number, amount]
	wave_callout = "웨이브 %d 완료" % number
	callout_time = 2.0
	Sound.cue(&"clear")

func _defeated(_number: int) -> void:
	Sound.play_music()
	if modal_kind == "research":
		close_modal()
	building = false
	selected = NONE
	_sync_selection()
	field.hovered = NONE
	wave_callout = "보스 탈출" if battle.boss_escaped and battle.health > 0 else "기지 붕괴  ·  %d 피해" % last_base_damage
	callout_time = 0.95
	defeat_delay = 0.95

func close_modal() -> void:
	var was_open := modal != null
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
		if was_open and not game:
			var play := screen.get_node_or_null("StartGame") as Button
			if play != null and not play.disabled:
				play.grab_focus()
	if is_instance_valid(field):
		field.frozen = false
		camera_fx.suspend(false)

func _open_modal(kind: String, dimensions: Vector2) -> Panel:
	close_modal()
	modal_kind = kind
	for control in screen.get_children():
		if control is Button:
			control.focus_mode = Control.FOCUS_NONE
	if is_instance_valid(field):
		field.frozen = true
		_panning = false
		_reset_battle_touch()
		enemy_inspector.hide()
		placement_label.hide()
		camera_fx.suspend(true)
	var shade := ColorRect.new()
	shade.color = Color(0.018, 0.020, 0.025, 0.86) if game else Color(0.015, 0.025, 0.04, 0.73)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	if Profile.mobile_mode:
		shade.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	place(shade, self, Rect2(Vector2.ZERO, Vector2(1920, 1080)))
	modal = shade
	var panel_rect := Rect2((Vector2(1920, 1080) - dimensions) * 0.5, dimensions)
	return panel_at(modal, panel_rect, "#1a2026", "#6e7778") if game else panel_at(modal, panel_rect, "#0e1822", "#415765")

func show_pause() -> void:
	if battle.lost:
		return
	var mobile: bool = Profile.mobile_mode
	var panel := _open_modal("pause", Vector2(560, 536) if mobile else Vector2(480, 432))
	text_at(panel, "일시정지", 35, 29, 39)
	text_at(panel, "웨이브 %d  /  기지 %d" % [battle.wave, battle.health], 36, 93, 20, MUTED)
	button_at(panel, "계속하기", Rect2(36, 140, 488, 80) if mobile else Rect2(36, 152, 408, 54), close_modal, true).grab_focus()
	button_at(panel, "설정", Rect2(36, 235, 236, 78) if mobile else Rect2(36, 214, 195, 54), show_settings.bind("pause_settings"))
	button_at(panel, "도감" if mobile else "도감 · K", Rect2(288, 235, 236, 78) if mobile else Rect2(249, 214, 195, 54), show_codex)
	button_at(panel, _restart_label(), Rect2(36, 328, 488, 78) if mobile else Rect2(36, 276, 408, 54), start_game.bind(battle.difficulty))
	button_at(panel, "메인 메뉴", Rect2(36, 421, 488, 78) if mobile else Rect2(36, 338, 408, 54), show_menu)

func show_codex() -> void:
	_codex_from_pause = modal_kind == "pause"
	var panel := _open_modal("codex", MOBILE_READING_SIZE if Profile.mobile_mode else Vector2(1396, 861))
	var codex := CombatCodex.new()
	place(codex, panel, Rect2(Vector2.ZERO, panel.size))
	var wave := clampi(battle.wave, 1, BattleData.FINAL_WAVE) if game else 1
	var mode := battle.difficulty if game else &"easy"
	codex.setup(self, wave, mode, _close_codex, Profile.mobile_mode)

func _close_codex() -> void:
	if _codex_from_pause:
		show_pause()
	else:
		close_modal()

func _cleared(record: Dictionary) -> void:
	Sound.play_music()
	var constrained := battle.constraints.active()
	if not constrained:
		Profile.record_clear(record)
	var entry := Profile.campaign_record(battle.difficulty)
	callout_time = 0.0
	toast.hide()
	building = false
	_sync_selection()
	var panel := _open_modal("victory", Vector2(900, 602))
	text_at(panel, "50웨이브 클리어", 42, 28, 47, MINT)
	text_at(panel, BattleData.DIFFICULTIES[battle.difficulty], 750, 48, 23, GOLD, 105)
	var stats := [
		["총 플레이 시간", _duration(record.seconds)], ["보스전 시간", _duration(record.finale)],
		["남은 기지 HP", str(record.health)], ["총 처치", str(record.kills)],
		["획득 재화", str(record.credits)], ["완료 연구", "%d / 100" % int(record.research)],
		["타워 설치", "%d회" % int(record.installed)],
	]
	stats.append(["제약", "%d종" % battle.constraints.count()] if constrained else ["최단 기록", _duration(entry.fastest_clear)])
	for i in stats.size():
		var x := 44 + int(i % 4) * 205
		var y := 112 + floori(i / 4.0) * 110
		text_at(panel, stats[i][0], x, y, 18, MUTED)
		text_at(panel, stats[i][1], x, y + 30, 29, LIGHT)
	text_at(panel, "설치한 5단계 공격 타워", 44, 344, 19, MUTED)
	var terminal := " · ".join(PackedStringArray(record.terminal))
	text_at(panel, terminal if not terminal.is_empty() else "없음", 44, 380, 23, GOLD, 812)
	if constrained:
		text_at(panel, "제약 모드 클리어", 44, 445, 18, MENU_CYAN)
	elif Profile.save_error:
		text_at(panel, "클리어 기록을 저장하지 못했습니다.", 44, 445, 18, PINK)
	else:
		text_at(panel, "최고 방어 기록  ·  기지 HP %d" % entry.best_clear.health, 44, 445, 18, MUTED)
	button_at(panel, _restart_label(), Rect2(44, 506, 390, 62), start_game.bind(battle.difficulty), true).grab_focus()
	button_at(panel, "메인 메뉴", Rect2(466, 506, 390, 62), show_menu)

func _restart_label() -> String:
	return "일반 게임 다시 시작" if battle.constraints.active() else "다시 시작"

func _duration(seconds: float) -> String:
	var whole := maxi(0, floori(seconds))
	return "%02d:%02d:%02d" % [floori(whole / 3600.0), floori(whole / 60.0) % 60, whole % 60]

func show_game_over() -> void:
	var panel := _open_modal("defeat", Vector2(522, 412))
	text_at(panel, "보스 탈출" if battle.boss_escaped and battle.health > 0 else "게임 오버", 36, 27, 47, PINK)
	text_at(panel, "도달 웨이브", 39, 116, 19, MUTED)
	var constrained := battle.constraints.active()
	text_at(panel, "적용 제약" if constrained else "최고 기록", 280, 116, 19, MUTED)
	text_at(panel, str(battle.wave), 39, 148, 31, LIGHT, 222)
	var detail := "%d종" % battle.constraints.count() if constrained else str(Profile.campaign_record(battle.difficulty).wave)
	text_at(panel, detail, 280, 148, 31, GOLD, 206)
	button_at(panel, _restart_label(), Rect2(36, 229, 450, 59), start_game.bind(battle.difficulty), true).grab_focus()
	button_at(panel, "메인 메뉴", Rect2(36, 301, 450, 59), show_menu)

func show_settings(return_to: String) -> void:
	settings_origin = return_to
	if Profile.mobile_mode:
		_show_mobile_settings(return_to)
		return
	var panel := _open_modal(return_to, Vector2(620, 689))
	text_at(panel, "설정", 35, 24, 42)
	_settings_slider(panel, "마스터 볼륨", 124, &"master")
	_settings_slider(panel, "효과음 볼륨", 205, &"effects")
	_settings_slider(panel, "배경음악 볼륨", 286, &"music")
	text_at(panel, "화면 모드", 36, 371, 21, MUTED)
	var mode := OptionButton.new()
	mode.add_item("창모드")
	mode.add_item("전체화면")
	mode.select(int(Profile.fullscreen))
	place(mode, panel, Rect2(278, 368, 306, 44))
	text_at(panel, "창 해상도", 36, 431, 21, MUTED)
	var sizes := OptionButton.new()
	for res in Profile.RESOLUTIONS:
		sizes.add_item("%d × %d" % [res.x, res.y])
	sizes.select(Profile.resolution)
	sizes.disabled = Profile.fullscreen
	place(sizes, panel, Rect2(278, 427, 306, 44))
	mode.item_selected.connect(_set_fullscreen.bind(sizes))
	sizes.item_selected.connect(_set_resolution)
	var record_mode := battle.difficulty if battle != null else &"easy"
	var entry := Profile.campaign_record(record_mode)
	text_at(panel, "%s 최고 웨이브" % BattleData.DIFFICULTIES[record_mode], 36, 504, 21, MUTED)
	var best_label := text_at(panel, "%d / 50" % entry.wave, 278, 499, 26, GOLD, 306)
	best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var record_text := "50웨이브 미클리어" if entry.best_clear.is_empty() else "최고 기지 HP %d  ·  최단 %s" % [entry.best_clear.health, _duration(entry.fastest_clear)]
	if Profile.best > entry.wave:
		record_text += "  ·  이전 최고 %d" % Profile.best
	if Profile.save_error:
		record_text = "설정을 저장할 수 없습니다."
	text_at(panel, record_text, 36, 548, 17, PINK if Profile.save_error else MUTED, 548)
	button_at(panel, "전투 효과 설정", Rect2(36, 595, 266, 56), show_effect_settings)
	button_at(panel, "닫기", Rect2(318, 595, 266, 56), _leave_settings, true).grab_focus()

func _show_mobile_settings(return_to: String) -> void:
	var panel := _open_modal(return_to, Vector2(960, 626))
	text_at(panel, "설정", 36, 24, 50)
	_settings_slider(panel, "마스터 볼륨", 137, &"master")
	_settings_slider(panel, "효과음 볼륨", 245, &"effects")
	_settings_slider(panel, "배경음악 볼륨", 353, &"music")
	button_at(panel, "전투 효과 설정", Rect2(36, 477, 528, 91), show_effect_settings)
	button_at(panel, "닫기", Rect2(586, 477, 338, 91), _leave_settings, true)

func can_open_research() -> bool:
	return game and not battle.lost and not battle.won and (not battle.active or bool(data.balance.research_available_during_wave))

func show_research(tower_id: String = "") -> void:
	if not can_open_research():
		return
	var panel := _open_modal("research", MOBILE_READING_SIZE if Profile.mobile_mode else Vector2(1848, 1002))
	research_screen = ResearchScreen.new()
	place(research_screen, panel, Rect2(Vector2.ZERO, panel.size))
	research_screen.setup(self, battle.research, data.towers, research_view, tower_id)
	field.frozen = bool(data.balance.research_pauses_battle)

func _research_purchased(_id: String, tower_id: String, advanced_stage: bool) -> void:
	if advanced_stage:
		Sound.cue(&"research_stage")
	if not tower_id.is_empty():
		wave_callout = data.towers.lookup(tower_id).name + " 해금"
		callout_time = 2.0
		if not advanced_stage:
			Sound.cue(&"clear")
	_update_hud()

func show_catalog(show_all: bool = false) -> void:
	if battle.lost or battle.won:
		return
	if Profile.mobile_mode:
		var pane := _open_modal("catalog", MOBILE_READING_SIZE)
		var picker := MobileTowerPicker.new()
		place(picker, pane, Rect2(Vector2.ZERO, pane.size))
		picker.setup(self, show_all, build_id)
		return
	var ids: Array[String] = []
	for id in data.towers.ids:
		if show_all or battle.research.unlocked.has(id):
			ids.append(id)
	var columns := 5 if ids.size() > 12 else clampi(ids.size(), 2, 4)
	var dimensions := Vector2(maxi(1024, columns * 239 + 460), maxi(560, 151 + 100 * ceili(float(ids.size()) / columns)))
	var panel := _open_modal("catalog", dimensions)
	text_at(panel, "타워 선택", 33, 22, 34)
	var close := button_at(panel, "닫기", Rect2(dimensions.x - 146, 25, 112, 46), close_modal)
	var funds := text_at(panel, "재화 %d" % battle.credits, dimensions.x - 338, 35, 19, GOLD, 169)
	funds.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	button_at(panel, "해금됨 %d" % battle.research.unlocked.size(), Rect2(34, 82, 156, 42), show_catalog.bind(false), not show_all)
	button_at(panel, "전체 %d" % data.towers.ids.size(), Rect2(201, 82, 130, 42), show_catalog.bind(true), show_all)
	var detail_x := dimensions.x - 416.0
	panel_at(panel, Rect2(detail_x, 143, 382, dimensions.y - 170), "#101820", "#314451")
	var detail := RichTextLabel.new()
	detail.name = "TowerPreview"
	detail.bbcode_enabled = true
	detail.add_theme_font_size_override("normal_font_size", 18)
	detail.add_theme_constant_override("line_separation", 5)
	place(detail, panel, Rect2(detail_x + 18.0, 156, 346, dimensions.y - 198))
	var initial_focus := close
	for i in ids.size():
		var id := ids[i]
		var def := battle.tower_definition(id)
		var ready := battle.research.unlocked.has(id)
		var affordable := battle.credits >= int(def.cost)
		var at := Vector2(34 + (i % columns) * 239, 143 + floori(float(i) / columns) * 100)
		var subtitle := "배치 %d" % int(def.cost)
		if not ready:
			subtitle += "  ·  연구"
		elif not affordable:
			subtitle += "  ·  부족"
		var tile := button_at(panel, "", Rect2(at, Vector2(225, 91)), _choose_tower.bind(id), ready and affordable)
		var tint: Color = def.tint
		var frame := TowerArt.first_frame(id)
		for layer in [frame, frame + 1]:
			var portrait := TextureRect.new()
			portrait.texture = TowerArt.icon(layer)
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
			place(portrait, tile, Rect2(1, 10, 70, 70))
		text_at(tile, def.name, 66, 6, 20, LIGHT, 151)
		var role := _tower_role(def)
		text_at(tile, role, 66, 35, 15, tint, 151)
		text_at(tile, subtitle, 66, 60, 15, MINT if ready and affordable else MUTED, 151)
		tile.disabled = (ready and not affordable) or (not ready and not can_open_research())
		tile.tooltip_text = def.description
		tile.mouse_entered.connect(_catalog_detail.bind(detail, def))
		tile.focus_entered.connect(_catalog_detail.bind(detail, def))
		tile.accessibility_name = "%s, %s, %s" % [def.name, role, subtitle]
		if id == build_id and not tile.disabled:
			initial_focus = tile
	_catalog_detail(detail, battle.tower_definition(build_id))
	initial_focus.grab_focus()

func _catalog_detail(label: RichTextLabel, definition: Dictionary) -> void:
	label.text = CombatReference.tower_text(definition, data)
	label.scroll_to_line(0)

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
	if battle.credits < int(battle.tower_definition(id).cost):
		return
	build_id = id
	close_modal()
	selected = NONE
	building = true
	_sync_selection()

func show_effect_settings() -> void:
	var mobile: bool = Profile.mobile_mode
	var panel := _open_modal("effects_settings", Vector2(960, 919) if mobile else Vector2(692, 810))
	text_at(panel, "전투 효과 설정", 35, 24, 50 if mobile else 39)
	text_at(panel, "효과 품질", 38, 104 if mobile else 108, 32 if mobile else 22, LIGHT if mobile else MUTED)
	var quality := OptionButton.new()
	if mobile:
		quality.add_theme_font_size_override("font_size", 32)
		quality.get_popup().add_theme_font_size_override("font_size", 30)
	for label in ["최소", "낮음", "보통", "높음"]:
		quality.add_item(label)
	quality.select(Profile.fx_quality)
	quality.item_selected.connect(_set_fx_quality)
	place(quality, panel, Rect2(380, 92, 542, 67) if mobile else Rect2(320, 104, 334, 46))
	_visual_slider(panel, "파티클 밀도", "fx_particles", 174)
	_visual_slider(panel, "화면 섬광", "fx_flash", 262)
	_visual_slider(panel, "화면 흔들림", "fx_shake", 350)
	_visual_slider(panel, "순간 줌", "fx_zoom", 438)
	_visual_slider(panel, "충격 왜곡", "fx_warp", 526)
	var dim := CheckButton.new()
	dim.text = "강한 밝기 낮추기"
	if mobile:
		dim.add_theme_font_size_override("font_size", 32)
	dim.button_pressed = Profile.fx_dim
	dim.toggled.connect(_set_fx_dim)
	place(dim, panel, Rect2(36, 675, 888, 68) if mobile else Rect2(36, 614, 618, 55))
	button_at(panel, "설정으로 돌아가기", Rect2(36, 793, 888, 86) if mobile else Rect2(36, 722, 618, 54), show_settings.bind(settings_origin), true).grab_focus()

func _visual_slider(parent: Control, title: String, key: String, y: float) -> void:
	var value := float(Profile.get(key))
	var font_size := 32 if Profile.mobile_mode else 21
	text_at(parent, title, 38, y, font_size, LIGHT if Profile.mobile_mode else MUTED)
	var percent := text_at(parent, "%d%%" % roundi(value * 100), parent.size.x - 158, y, font_size, MINT, 120)
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var slider := HSlider.new()
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = value * 100.0
	slider.value_changed.connect(_set_fx_value.bind(key, percent))
	place(slider, parent, Rect2(38, y + 41, parent.size.x - 76, 45) if Profile.mobile_mode else Rect2(38, y + 37, 616, 25))

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

func _settings_slider(parent: Control, name_text: String, y: float, key: StringName) -> void:
	var value: float = Profile.get(key)
	var font_size := 32 if Profile.mobile_mode else 21
	text_at(parent, name_text, 36, y - 20, font_size, LIGHT if Profile.mobile_mode else MUTED)
	var number := text_at(parent, "%d%%" % roundi(value * 100), parent.size.x - 128, y - 22, font_size, MINT, 92)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = roundi(value * 100)
	place(slider, parent, Rect2(36, y + 18, parent.size.x - 72, 58) if Profile.mobile_mode else Rect2(36, y + 18, 548, 28))
	slider.value_changed.connect(_set_volume.bind(key, number))
	if key != &"music":
		slider.drag_ended.connect(_volume_preview)

func _set_volume(value: float, key: StringName, number: Label) -> void:
	Profile.set(key, value / 100.0)
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
	var viewport_rect := Rect2(0, 0, 1920, 1080)
	if game:
		draw_rect(viewport_rect, Color("#101316"))
	else:
		draw_rect(viewport_rect, Color("#0b121b"))
		_draw_menu_prism()

func _draw_menu_prism() -> void:
	var center := Vector2(1390, 540)
	var top := center + Vector2(0, -237)
	var right := center + Vector2(195, -18)
	var bottom := center + Vector2(0, 237)
	var left := center + Vector2(-195, 18)
	var joint := center + Vector2(33, 12)

	draw_line(Vector2(165, 359), Vector2(215, 359), Color("#83bac4"), 2.0, true)
	draw_line(center - Vector2(325, 0), center + Vector2(325, 0), Color("#1b2b39"), 1.5, true)
	draw_line(center - Vector2(0, 310), center + Vector2(0, 310), Color("#1b2b39"), 1.5, true)
	draw_colored_polygon(PackedVector2Array([top, joint, left]), Color("#1a343e"))
	draw_colored_polygon(PackedVector2Array([top, right, joint]), Color("#142631"))
	draw_colored_polygon(PackedVector2Array([right, bottom, joint]), Color("#192437"))
	draw_colored_polygon(PackedVector2Array([bottom, left, joint]), Color("#111e2b"))
	draw_polyline(PackedVector2Array([top, right, bottom, left, top]), Color("#7eaeb9"), 2.0, true)
	draw_polyline(PackedVector2Array([left, joint, right]), Color("#628692"), 1.5, true)
	draw_polyline(PackedVector2Array([top, joint, bottom]), Color("#628692"), 1.5, true)
