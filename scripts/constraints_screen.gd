class_name ConstraintsScreen
extends Control

const MUTED := Color("#a4b3ba")
const ACCENT := Color("#a3ebf3")

var _host
var _levels: Dictionary = {}
var _buttons: Dictionary = {}
var _effects: Dictionary = {}
var _difficulty: OptionButton
var _summary: Label

func setup(host: Control) -> void:
	_host = host
	mouse_filter = MOUSE_FILTER_IGNORE
	_host.text_at(self, "제약 모드", 38, 22, 40)
	_host.text_at(self, "0은 꺼짐 · 1~5단계를 조합해 이번 게임에 적용", 40, 87, 20, MUTED)
	_host.button_at(self, "돌아가기", Rect2(1190, 26, 114, 48), _host.show_difficulty)
	_host.text_at(self, "난이도", 884, 85, 20, MUTED)
	_difficulty = OptionButton.new()
	for mode: StringName in BattleData.DIFFICULTIES:
		_difficulty.add_item(BattleData.DIFFICULTIES[mode])
		_difficulty.set_item_metadata(_difficulty.item_count - 1, mode)
	_difficulty.select(1)
	_host.place(_difficulty, self, Rect2(987, 72, 183, 51))

	var index := 0
	for id: StringName in RunConstraints.DEFINITIONS:
		var column := int(index >= 5)
		var row := index - column * 5
		_make_row(id, Vector2(38 + column * 640, 143 + row * 102))
		index += 1

	_summary = _host.text_at(self, "", 38, 787, 21, MUTED)
	_host.button_at(self, "모두 초기화", Rect2(830, 774, 184, 57), _reset)
	var start: Button = _host.button_at(self, "이 설정으로 시작", Rect2(1030, 774, 274, 57), _start, true)
	_refresh_summary()
	start.grab_focus()

func _make_row(id: StringName, at: Vector2) -> void:
	var row: Panel = _host.panel_at(self, Rect2(at, Vector2(626, 89)), "#111c27", "#283d4d")
	_host.text_at(row, RunConstraints.DEFINITIONS[id][0], 18, 7, 23)
	var value: Label = _host.text_at(row, RunConstraints.effect_text(id, 0), 421, 10, 20, MUTED, 186)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_effects[id] = value
	var group := ButtonGroup.new()
	var choices: Array[Button] = []
	for level in range(6):
		var button: Button = _host.button_at(row, str(level), Rect2(18 + level * 99, 44, 91, 34), _select.bind(id, level))
		button.add_theme_font_size_override("font_size", 17)
		button.add_theme_stylebox_override("pressed", _host.box("#294a54", "#9bdbe1"))
		button.toggle_mode = true
		button.button_group = group
		button.accessibility_name = "%s %d단계, %s" % [RunConstraints.DEFINITIONS[id][0], level, RunConstraints.effect_text(id, level)]
		choices.append(button)
	choices[0].set_pressed_no_signal(true)
	_buttons[id] = choices

func _select(id: StringName, level: int) -> void:
	if level == 0:
		_levels.erase(id)
	else:
		_levels[id] = level
	var label: Label = _effects[id]
	label.text = RunConstraints.effect_text(id, level)
	label.add_theme_color_override("font_color", ACCENT if level > 0 else MUTED)
	_refresh_summary()

func _refresh_summary() -> void:
	_summary.text = "%d / %d개 제약 적용" % [_levels.size(), RunConstraints.DEFINITIONS.size()]

func _reset() -> void:
	for id: StringName in _buttons:
		var choices: Array[Button] = _buttons[id]
		for level in choices.size():
			choices[level].set_pressed_no_signal(level == 0)
		_select(id, 0)

func _start() -> void:
	_host.start_game(StringName(_difficulty.get_selected_metadata()), _levels)
