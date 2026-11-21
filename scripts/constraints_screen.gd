class_name ConstraintsScreen
extends Control

const MUTED := Color("#a4b3ba")
const RESTRICTION := Color("#f1aa9c")
const PERK := Color("#8ee6ca")
const FUNDS_PRESETS := [10, 50, 250, 1000, 5000]

var _host
var _levels: Dictionary = {}
var _effects: Dictionary = {}
var _steppers: Dictionary = {}
var _presets: Dictionary = {}
var _difficulty: OptionButton
var _funds: LineEdit
var _funds_note: Label
var _summary: Label
var _start_button: Button
var _default_funds: int

func setup(host: Control) -> void:
	_host = host
	_default_funds = int(_host.data.balance.starting_credits)
	mouse_filter = MOUSE_FILTER_IGNORE
	_host.text_at(self, "커스텀 규칙", 36, 18, 45)
	_host.text_at(self, "−5~−1 제약   ·   0 기본   ·   +1~+5 특전", 38, 79, 26, MUTED)
	_host.text_at(self, "난이도", 1088, 44, 28, MUTED)
	_difficulty = OptionButton.new()
	_difficulty.add_theme_font_size_override("font_size", 30)
	_difficulty.get_popup().add_theme_font_size_override("font_size", 30)
	for mode: StringName in BattleData.DIFFICULTIES:
		_difficulty.add_item(BattleData.DIFFICULTIES[mode])
		_difficulty.set_item_metadata(_difficulty.item_count - 1, mode)
	_difficulty.select(1)
	_host.place(_difficulty, self, Rect2(1200, 25, 258, 75))
	_host.button_at(self, "돌아가기", Rect2(1490, 25, 218, 75), _host.show_difficulty)

	var index := 0
	for id: StringName in RunConstraints.DEFINITIONS:
		var left_column := index < 5
		var row := index if left_column else index - 5
		_make_stepper(id, Vector2(36 if left_column else 884, 246 + row * 106))
		index += 1

	_make_funds()
	_summary = _host.text_at(self, "", 38, 914, 26, MUTED, 1020)
	_host.button_at(self, "모두 초기화", Rect2(1094, 893, 264, 85), _reset)
	_start_button = _host.button_at(self, "이 설정으로 시작", Rect2(1376, 893, 332, 85), _start, true)
	_refresh_summary()
	_start_button.grab_focus()

func _make_stepper(id: StringName, at: Vector2) -> void:
	var row: Panel = _host.panel_at(self, Rect2(at, Vector2(824, 98)), "#111c27", "#283d4d")
	_host.text_at(row, RunConstraints.DEFINITIONS[id][0], 20, 8, 31, Color("#eee9dc"))
	var value: Label = _host.text_at(row, RunConstraints.setting_text(id, 0), 20, 53, 28, MUTED)
	_effects[id] = value
	var less: Button = _host.button_at(row, "−", Rect2(574, 11, 110, 76), _adjust.bind(id, -1))
	var more: Button = _host.button_at(row, "+", Rect2(700, 11, 104, 76), _adjust.bind(id, 1))
	less.add_theme_font_size_override("font_size", 33)
	more.add_theme_font_size_override("font_size", 33)
	less.accessibility_name = "%s 단계 낮추기" % RunConstraints.DEFINITIONS[id][0]
	more.accessibility_name = "%s 단계 높이기" % RunConstraints.DEFINITIONS[id][0]
	more.disabled = RunConstraints.max_level(id) == 0
	_steppers[id] = [less, more]

func _make_funds() -> void:
	var panel: Panel = _host.panel_at(self, Rect2(36, 132, 1672, 98), "#111c27", "#283d4d")
	_host.text_at(panel, "시작자금", 20, 27, 32)
	var group := ButtonGroup.new()
	group.allow_unpress = true
	for i in FUNDS_PRESETS.size():
		var amount: int = FUNDS_PRESETS[i]
		var preset: Button = _host.button_at(panel, CombatReference.number(amount), Rect2(180 + i * 114, 11, 104, 76), _set_funds.bind(amount))
		preset.add_theme_font_size_override("font_size", 27)
		preset.toggle_mode = true
		preset.button_group = group
		_presets[amount] = preset
	_funds = LineEdit.new()
	_funds.placeholder_text = "금액 직접 입력"
	_funds.accessibility_name = "시작자금 직접 입력"
	_funds.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_funds.select_all_on_focus = true
	_funds.add_theme_font_size_override("font_size", 34)
	_funds.add_theme_stylebox_override("normal", _host.box("#0b141d", "#526773"))
	_host.place(_funds, panel, Rect2(770, 11, 450, 76))
	_funds_note = _host.text_at(panel, "금액 직접 입력", 1240, 29, 26, MUTED, 412)
	_funds.text_changed.connect(func(_text: String): _refresh_summary())
	_funds.text_submitted.connect(func(_text: String): _funds.release_focus())
	_set_funds(_default_funds)

func _adjust(id: StringName, delta: int) -> void:
	_select(id, clampi(int(_levels.get(id, 0)) + delta, -5, RunConstraints.max_level(id)))

func _select(id: StringName, level: int) -> void:
	if level == 0:
		_levels.erase(id)
	else:
		_levels[id] = level
	var label: Label = _effects[id]
	label.text = RunConstraints.setting_text(id, level)
	label.add_theme_color_override("font_color", RESTRICTION if level < 0 else (PERK if level > 0 else MUTED))
	_steppers[id][0].disabled = level == -5
	_steppers[id][1].disabled = level >= RunConstraints.max_level(id)
	_refresh_summary()

func _set_funds(amount: int) -> void:
	_funds.text = str(amount)
	_refresh_summary()

func _funds_amount() -> int:
	var digits := _funds.text.strip_edges()
	if digits.is_empty():
		return -1
	var amount := 0
	for i in digits.length():
		var digit := digits.unicode_at(i) - 48
		if digit < 0 or digit > 9:
			return -1
		amount = amount * 10 + digit
		if amount > BattleData.NUMBER_LIMIT:
			return -1
	return amount

func _refresh_summary() -> void:
	var funds := _funds_amount()
	for amount: int in _presets:
		_presets[amount].set_pressed_no_signal(funds == amount)
	_funds_note.text = "금액 직접 입력" if funds >= 0 else "정수만 입력 · 0~9,000조"
	_funds_note.add_theme_color_override("font_color", MUTED if funds >= 0 else RESTRICTION)
	if _start_button == null:
		return
	_start_button.disabled = funds < 0
	var rule_count := _levels.size()
	var funds_changed := funds >= 0 and funds != _default_funds
	if rule_count > 0:
		_summary.text = "%d종 적용 · 일반 기록과 별개" % rule_count
	else:
		_summary.text = "시작자금 변경 · 일반 기록과 별개" if funds_changed else "기본 규칙"

func _reset() -> void:
	for id: StringName in _levels.keys():
		_select(id, 0)
	_set_funds(_default_funds)

func _start() -> void:
	var funds := _funds_amount()
	if funds >= 0:
		_host.start_game(StringName(_difficulty.get_selected_metadata()), _levels, funds)
