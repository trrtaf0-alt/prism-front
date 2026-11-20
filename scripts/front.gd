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
	text_at(screen, "포탑을 배치하고 에너지 코어를 지키세요.", 131, 520, 26, MUTED)
	var play := button_at(screen, "게임 시작", Rect2(132, 615, 418, 68), start_game, true)
	play.disabled = not map_error.is_empty()
	button_at(screen, "설정", Rect2(132, 698, 418, 62), show_settings.bind("menu"))
	button_at(screen, "종료", Rect2(132, 775, 418, 62), get_tree().quit)
	if not map_error.is_empty():
		text_at(screen, "맵 오류 · " + map_error, 132, 859, 21, PINK)
	text_at(screen, "v0.1", 132, 977, 19, MUTED)
	play.grab_focus()

func start_game() -> void:
	if not map_error.is_empty():
		return
	_replace_screen()
	game = true
	selected = NONE
	building = false
	_credits_shown = -1
	_credit_flash = 0.0
	flash = 0.0
	wave_callout = ""
	callout_time = 0.0
	defeat_delay = 0.0
	battle = Battle.new(map, data)
	battle.effect.connect(_battle_effect)
	battle.wave_started.connect(_wave_started)
	battle.wave_finished.connect(_wave_finished)
	battle.defeated.connect(_defeated)
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
	credits_label = text_at(screen, "", 1230, 56, 32, GOLD, 390)
	button_at(screen, "일시정지  ·  Esc", Rect2(1660, 45, 212, 57), show_pause)

	panel_at(screen, Rect2(1527, 147, 345, 235))
	text_at(screen, "웨이브 제어", 1550, 166, 21, MUTED)
	status = text_at(screen, "", 1550, 202, 24, LIGHT, 299)
	wave_button = button_at(screen, "웨이브 시작", Rect2(1550, 251, 299, 59), start_wave, true)
	result = text_at(screen, "", 1550, 323, 19, GOLD, 299)

	panel_at(screen, Rect2(1527, 400, 345, 185))
	text_at(screen, "포탑 설치", 1550, 420, 21, MUTED)
	build_button = button_at(screen, "", Rect2(1550, 467, 299, 61), toggle_build, true)
	text_at(screen, "1  설치 선택   /   우클릭  취소", 1550, 540, 17, MUTED)

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

func _update_hud() -> void:
	wave_label.text = str(battle.wave)
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
	wave_button.disabled = battle.active or battle.lost
	if battle.lost:
		status.text = "기지 코어 소실"
	elif battle.active:
		status.text = "남은 적  %d" % (battle.queued + battle.enemies.size())
	else:
		status.text = "다음 적  %d" % data.wave_count(battle.wave + 1)
	wave_button.text = "교전 중" if battle.active else "웨이브 %d 시작" % (battle.wave + 1)
	var cost := int(data.turret.cost)
	build_button.disabled = battle.lost or battle.credits < cost
	if building:
		build_button.text = "설치할 타일 선택  ·  %d" % cost
	elif battle.credits < cost:
		build_button.text = "재화 부족  ·  %d 필요" % cost
	else:
		build_button.text = "%s  ·  %d" % [data.turret.name, cost]
	var has_tower := battle.occupied.has(selected)
	tower_heading.text = data.turret.name if has_tower else "선택한 포탑"
	tower_stats.text = "공격력  %d    연사  초당 %d발\n사거리  %d칸    탄속  초당 %d칸" % [
		data.turret.damage, data.turret.shots_per_second, data.turret.range, data.turret.projectile_speed
	] if has_tower else "전장 위에 배치된 포탑을\n클릭하면 능력치를 볼 수 있습니다."
	sell_button.disabled = not has_tower or battle.lost

func toggle_build() -> void:
	if battle.lost or battle.credits < int(data.turret.cost):
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
	_update_hud()

func _physics_process(delta: float) -> void:
	if game and modal == null and not battle.lost:
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
			"pause":
				close_modal()
			"menu", "pause_settings":
				_leave_settings()
			"":
				if game and not battle.lost:
					show_pause()
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
				if battle.install(cell) and battle.credits < int(data.turret.cost):
					building = false
					selected = cell
			else:
				selected = NONE
		_sync_selection()

func _battle_effect(kind: StringName, _point: Vector2, _direction: Vector2) -> void:
	Sound.cue(kind)
	if kind == &"base":
		flash = 1.0

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
	building = false
	selected = NONE
	_sync_selection()
	field.hovered = NONE
	wave_callout = "기지 코어 붕괴"
	callout_time = 0.95
	defeat_delay = 0.95

func close_modal() -> void:
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

func show_game_over() -> void:
	var panel := _open_modal("defeat", Vector2(522, 412))
	text_at(panel, "게임 오버", 36, 27, 47, PINK)
	text_at(panel, "도달 웨이브", 39, 116, 19, MUTED)
	text_at(panel, "최고 기록", 280, 116, 19, MUTED)
	text_at(panel, str(battle.wave), 39, 148, 31, LIGHT, 222)
	text_at(panel, str(Profile.best), 280, 148, 31, GOLD, 206)
	button_at(panel, "다시 시작", Rect2(36, 229, 450, 59), start_game, true).grab_focus()
	button_at(panel, "메인 메뉴", Rect2(36, 301, 450, 59), show_menu)

func show_settings(return_to: String) -> void:
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
	text_at(panel, "최고 웨이브", 36, 423, 21, MUTED)
	var best_label := text_at(panel, str(Profile.best), 278, 418, 26, GOLD, 306)
	best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var message := text_at(panel, "", 36, 467, 17, PINK, 548)
	if Profile.save_error:
		message.text = "설정을 저장할 수 없습니다."
	button_at(panel, "닫기", Rect2(36, 514, 548, 56), _leave_settings, true).grab_focus()

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
