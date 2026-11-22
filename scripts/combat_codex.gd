class_name CombatCodex
extends Control

var _host: Control
var _entries: ItemList
var _detail: RichTextLabel
var _tower_tab: Button
var _enemy_tab: Button
var _wave_controls: Control
var _wave_label: Label
var _wave: SpinBox
var _difficulty: OptionButton
var _difficulty_x := 226.0
var _title_size := 30
var _enemies := false

func setup(host: Control, initial_wave: int, initial_mode: StringName, close: Callable, mobile: bool) -> void:
	_host = host
	_title_size = 44 if mobile else 30
	mouse_filter = MOUSE_FILTER_IGNORE
	_host.text_at(self, "도감", 36, 26, 50 if mobile else 39)
	_host.button_at(self, "닫기", Rect2(size.x - 220, 24, 184, 82) if mobile else Rect2(1260, 27, 100, 48), close)
	var tower_tab_rect := Rect2(204, 24, 208, 82) if mobile else Rect2(36, 95, 150, 48)
	var enemy_tab_rect := Rect2(428, 24, 208, 82) if mobile else Rect2(198, 95, 150, 48)
	_tower_tab = _host.button_at(self, "타워  %d" % _host.data.towers.ids.size(), tower_tab_rect, _populate.bind(false))
	var enemy_count: int = _enemy_ids().size()
	_enemy_tab = _host.button_at(self, "적  %d" % enemy_count, enemy_tab_rect, _populate.bind(true))
	var group := ButtonGroup.new()
	for button in [_tower_tab, _enemy_tab]:
		button.toggle_mode = true
		button.button_group = group

	_entries = ItemList.new()
	_entries.fixed_icon_size = Vector2i.ONE * (44 if mobile else 30)
	_entries.add_theme_font_size_override("font_size", 34 if mobile else 23)
	_entries.add_theme_constant_override("v_separation", 27 if mobile else 15)
	_entries.add_theme_stylebox_override("panel", _host.box("#101820", "#314451"))
	var list_rect := Rect2(36, 132, 416, size.y - 168) if mobile else Rect2(36, 158, 312, 669)
	_host.place(_entries, self, list_rect)
	_entries.item_selected.connect(_show_entry)
	if mobile:
		_enable_mobile_list(list_rect)

	var body := Rect2(478, 132, size.x - 514, size.y - 168) if mobile else Rect2(370, 158, 990, 669)
	_host.panel_at(self, body, "#111921", "#314451")
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	if mobile:
		_host.mobile_reading_text(_detail)
	else:
		_detail.add_theme_font_size_override("normal_font_size", 24)
		_detail.add_theme_constant_override("line_separation", 8)
	_host.place(_detail, self, body.grow(-32.0) if mobile else Rect2(402, 183, 926, 616))

	_wave_controls = Control.new()
	_wave_controls.mouse_filter = MOUSE_FILTER_IGNORE
	_host.place(_wave_controls, self, Rect2(720, 24, 770, 82) if mobile else Rect2(370, 95, 990, 48))
	_wave_label = _host.text_at(_wave_controls, "웨이브", 0, 18 if mobile else 9, 31 if mobile else 23)
	_wave = SpinBox.new()
	_wave.min_value = 1
	_wave.max_value = _host.data.final_wave
	_wave.value = initial_wave
	if mobile:
		_wave.get_line_edit().add_theme_font_size_override("font_size", 33)
	_host.place(_wave, _wave_controls, Rect2(122, 0, 168, 82) if mobile else Rect2(90, 0, 120, 48))
	_difficulty = OptionButton.new()
	for mode: StringName in BattleData.DIFFICULTIES:
		_difficulty.add_item(BattleData.DIFFICULTIES[mode])
		_difficulty.set_item_metadata(_difficulty.item_count - 1, mode)
		if mode == initial_mode:
			_difficulty.select(_difficulty.item_count - 1)
	if mobile:
		_difficulty_x = 310.0
		_difficulty.add_theme_font_size_override("font_size", 32)
		_difficulty.get_popup().add_theme_font_size_override("font_size", 30)
	_host.place(_difficulty, _wave_controls, Rect2(_difficulty_x, 0, 216, 82) if mobile else Rect2(_difficulty_x, 0, 150, 48))
	_wave.value_changed.connect(_refresh)
	_difficulty.item_selected.connect(_refresh)
	_populate(false)
	_tower_tab.grab_focus()

func _enable_mobile_list(rect: Rect2) -> void:
	var input_area := Control.new()
	_host.place(input_area, self, rect)
	var gesture := TouchGesture.new()
	input_area.gui_input.connect(func(event: InputEvent): gesture.handle(event))
	gesture.panned.connect(func(delta: Vector2): _entries.get_v_scroll_bar().value -= delta.y)
	gesture.tapped.connect(func(point: Vector2):
		var index := _entries.get_item_at_position(point, true)
		if index >= 0:
			_entries.select(index)
			_show_entry(index)
	)

func _populate(enemies: bool) -> void:
	_enemies = enemies
	_tower_tab.set_pressed_no_signal(not enemies)
	_enemy_tab.set_pressed_no_signal(enemies)
	_wave_controls.visible = enemies
	_entries.clear()
	var ids: Array = _enemy_ids() if enemies else _host.data.towers.ids
	for id: String in ids:
		var def: Dictionary = _host.data.mobs.lookup(id) if enemies else _host.data.towers.lookup(id)
		var sprite: Texture2D = _host.data.media.get("enemies", {}).get(id) if enemies else _host.data.tower_sprite(id)
		var index := _entries.add_item(def.name, sprite)
		_entries.set_item_metadata(index, id)
		_entries.set_item_custom_fg_color(index, Color(str(def.color)).lerp(Color.WHITE, 0.36))
	if _entries.item_count > 0:
		_entries.select(0)
		_entries.ensure_current_is_visible()
		_show_entry(0)

func _enemy_ids() -> Array:
	var data: BattleData = _host.data
	return data.mobs.definitions.keys().filter(func(id: String) -> bool:
		return id == data.boss_id or not data.mobs.lookup(id).boss
	)

func _refresh(_value: float) -> void:
	var selected := _entries.get_selected_items()
	if not selected.is_empty():
		_show_entry(selected[0])

func _show_entry(index: int) -> void:
	var id: String = _entries.get_item_metadata(index)
	var data: BattleData = _host.data
	var battle: Battle = _host.battle
	if _enemies:
		var mode: StringName = _difficulty.get_selected_metadata()
		var def := data.mobs.lookup(id)
		_wave_label.visible = not def.boss
		_wave.visible = not def.boss
		_difficulty.position.x = 0.0 if def.boss else _difficulty_x
		_detail.text = CombatReference.enemy_text(def, data, int(_wave.value), mode, battle.constraints if battle != null else null, _title_size)
	else:
		_detail.text = CombatReference.tower_text(battle.tower_definition(id) if battle != null else data.towers.lookup(id), data, _title_size)
	_detail.scroll_to_line(0)
