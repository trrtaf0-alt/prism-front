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
var _enemies := false

func setup(host: Control, initial_wave: int, initial_mode: StringName, close: Callable) -> void:
	_host = host
	mouse_filter = MOUSE_FILTER_IGNORE
	_host.text_at(self, "도감", 36, 26, 39)
	_host.button_at(self, "닫기", Rect2(1260, 27, 100, 48), close)
	_tower_tab = _host.button_at(self, "타워  %d" % _host.data.towers.ids.size(), Rect2(36, 95, 150, 48), _populate.bind(false))
	_enemy_tab = _host.button_at(self, "적  %d" % _host.data.mobs.definitions.size(), Rect2(198, 95, 150, 48), _populate.bind(true))
	var group := ButtonGroup.new()
	for button in [_tower_tab, _enemy_tab]:
		button.toggle_mode = true
		button.button_group = group

	_entries = ItemList.new()
	_entries.add_theme_font_size_override("font_size", 23)
	_entries.add_theme_constant_override("v_separation", 15)
	_entries.add_theme_stylebox_override("panel", _host.box("#101820", "#314451"))
	_host.place(_entries, self, Rect2(36, 158, 312, 669))
	_entries.item_selected.connect(_show_entry)

	_host.panel_at(self, Rect2(370, 158, 990, 669), "#111921", "#314451")
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.add_theme_font_size_override("normal_font_size", 24)
	_detail.add_theme_constant_override("line_separation", 8)
	_host.place(_detail, self, Rect2(402, 183, 926, 616))

	_wave_controls = Control.new()
	_wave_controls.mouse_filter = MOUSE_FILTER_IGNORE
	_host.place(_wave_controls, self, Rect2(370, 95, 990, 48))
	_wave_label = _host.text_at(_wave_controls, "웨이브", 0, 9, 23)
	_wave = SpinBox.new()
	_wave.min_value = 1
	_wave.max_value = BattleData.FINAL_WAVE
	_wave.value = initial_wave
	_host.place(_wave, _wave_controls, Rect2(90, 0, 120, 48))
	_difficulty = OptionButton.new()
	for mode: StringName in BattleData.DIFFICULTIES:
		_difficulty.add_item(BattleData.DIFFICULTIES[mode])
		_difficulty.set_item_metadata(_difficulty.item_count - 1, mode)
		if mode == initial_mode:
			_difficulty.select(_difficulty.item_count - 1)
	_host.place(_difficulty, _wave_controls, Rect2(226, 0, 150, 48))
	_wave.value_changed.connect(_refresh)
	_difficulty.item_selected.connect(_refresh)
	_populate(false)
	_tower_tab.grab_focus()

func _populate(enemies: bool) -> void:
	_enemies = enemies
	_tower_tab.set_pressed_no_signal(not enemies)
	_enemy_tab.set_pressed_no_signal(enemies)
	_wave_controls.visible = enemies
	_entries.clear()
	var ids: Array = _host.data.mobs.definitions.keys() if enemies else _host.data.towers.ids
	for id: String in ids:
		var def: Dictionary = _host.data.mobs.lookup(id) if enemies else _host.data.towers.lookup(id)
		var index := _entries.add_item(def.name)
		_entries.set_item_metadata(index, id)
		_entries.set_item_custom_fg_color(index, Color(str(def.color)).lerp(Color.WHITE, 0.36))
	if _entries.item_count > 0:
		_entries.select(0)
		_entries.ensure_current_is_visible()
		_show_entry(0)

func _refresh(_value: float) -> void:
	var selected := _entries.get_selected_items()
	if not selected.is_empty():
		_show_entry(selected[0])

func _show_entry(index: int) -> void:
	var id: String = _entries.get_item_metadata(index)
	var data: BattleData = _host.data
	if _enemies:
		var mode: StringName = _difficulty.get_selected_metadata()
		var def := data.mobs.lookup(id)
		_wave_label.visible = not def.boss
		_wave.visible = not def.boss
		_difficulty.position.x = 0.0 if def.boss else 226.0
		_detail.text = CombatReference.enemy_text(def, data, int(_wave.value), mode)
	else:
		_detail.text = CombatReference.tower_text(data.towers.lookup(id), data)
	_detail.scroll_to_line(0)
