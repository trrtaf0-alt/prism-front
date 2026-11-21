class_name MobileTowerPicker
extends Control

const MARGIN := 30.0
const LIST_WIDTH := 560.0

var _front
var _scroll: ScrollContainer
var _list: VBoxContainer
var _details: RichTextLabel
var _action: Button
var _group := ButtonGroup.new()
var _selected := ""
var _gesture := TouchGesture.new()

func setup(host: Control, show_all: bool, initial: String) -> void:
	_front = host
	mouse_filter = MOUSE_FILTER_IGNORE
	var battle: Battle = _front.battle
	_front.text_at(self, "타워 선택", MARGIN, 23, 50)
	var funds: Label = _front.text_at(self, "재화 %s" % CombatReference.number(battle.credits), size.x - 715, 40, 32, Color("#dcc197"), 470)
	funds.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_front.button_at(self, "닫기", Rect2(size.x - 224, 23, 194, 82), _front.close_modal)
	_front.button_at(self, "해금됨", Rect2(MARGIN, 122, 273, 76), _front.show_catalog.bind(false), not show_all)
	_front.button_at(self, "전체", Rect2(317, 122, 273, 76), _front.show_catalog.bind(true), show_all)

	var list_rect := Rect2(MARGIN, 217, LIST_WIDTH, size.y - 247)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_front.place(_scroll, self, list_rect)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	var touch_area := Control.new()
	_front.place(touch_area, self, list_rect)
	touch_area.gui_input.connect(_gesture.handle)
	_gesture.panned.connect(func(delta: Vector2): _scroll.scroll_vertical -= roundi(delta.y))
	_gesture.tapped.connect(_tap_tower)

	var detail_x := LIST_WIDTH + 2 * MARGIN
	var detail_width := size.x - detail_x - MARGIN
	_front.panel_at(self, Rect2(detail_x, 122, detail_width, size.y - 260), "#101820", "#314451")
	_details = RichTextLabel.new()
	_details.bbcode_enabled = true
	_front.mobile_reading_text(_details)
	_front.place(_details, self, Rect2(detail_x + 34, 151, detail_width - 68, size.y - 318))
	_action = _front.button_at(self, "", Rect2(detail_x, size.y - 120, detail_width, 90), _choose, true)

	var first: Button
	var initial_button: Button
	for id in battle.data.towers.ids:
		var unlocked := battle.research.unlocked.has(id)
		if not show_all and not unlocked:
			continue
		var def := battle.tower_definition(id)
		var button := _add_tower(id, def, unlocked)
		if first == null:
			first = button
		if id == initial:
			initial_button = button
	if initial_button == null:
		initial_button = first
	if initial_button != null:
		_select(str(initial_button.get_meta("tower")))
		initial_button.set_pressed_no_signal(true)

func _add_tower(id: String, def: Dictionary, unlocked: bool) -> Button:
	var button := Button.new()
	button.text = "%s  ·  %d%s" % [def.name, def.cost, "" if unlocked else "  ·  연구"]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 94.0
	button.add_theme_font_size_override("font_size", 32)
	button.add_theme_color_override("font_color", def.tint.lightened(0.27))
	button.toggle_mode = true
	button.button_group = _group
	button.set_meta("tower", id)
	button.pressed.connect(_select.bind(id))
	_list.add_child(button)
	return button

func _tap_tower(point: Vector2) -> void:
	if not Rect2(Vector2.ZERO, _scroll.size).has_point(point):
		return
	var list_point := point - _list.position
	for row: Button in _list.get_children():
		if row.get_rect().has_point(list_point):
			row.set_pressed_no_signal(true)
			_select(str(row.get_meta("tower")))
			return

func _select(id: String) -> void:
	_selected = id
	var battle: Battle = _front.battle
	var def := battle.tower_definition(id)
	_details.text = CombatReference.tower_text(def, battle.data, 44)
	_details.scroll_to_line(0)
	if battle.research.unlocked.has(id):
		_action.text = "배치 준비" if battle.credits >= int(def.cost) else "재화 %d 부족" % (int(def.cost) - battle.credits)
		_action.disabled = battle.credits < int(def.cost)
	else:
		_action.text = "연구 보기"
		_action.disabled = not _front.can_open_research()

func _choose() -> void:
	if not _selected.is_empty():
		_front._choose_tower(_selected)
