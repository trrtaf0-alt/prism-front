class_name ResearchScreen
extends Control

const INK := Color("#eee9dc")
const MUTED := Color("#a5a8a5")
const MINT := Color("#a9c6bd")
const GOLD := Color("#dcc197")
const STAGE_TINTS := [MINT, Color("#80d8c4"), Color("#80baff"), Color("#b69bf2"), Color("#ed9cbd"), Color("#f0ca88")]

var front
var run: ResearchRun
var registry: TowerRegistry
var board: ResearchBoard
var balance_label: Label
var heading: Label
var description: Label
var requirements: Label
var outcome: Label
var cost: Label
var link_summary: Label
var buy: Button
var _title: Label
var _detail_frame: StyleBoxFlat
var _zone_buttons: Array[Button] = []
var _accent := MINT
var _accent_stage := 0
var _accent_tween: Tween
var _minimum := -1
var _completed_count := -1
var _last_focus := ""
var _pending_refresh := false

func setup(owner_ui: Control, session: ResearchRun, tower_registry: TowerRegistry, view: Dictionary, jump_tower: String) -> void:
	front = owner_ui
	run = session
	registry = tower_registry
	mouse_filter = MOUSE_FILTER_IGNORE
	var mobile: bool = owner_ui.get_tree().root.get_node("Profile").mobile_mode
	_title = front.text_at(self, "연구", 36, 23, 43)
	var controls := "한 손가락 이동  ·  두 손가락 확대·축소" if mobile else "드래그로 이동  ·  휠로 확대/축소  ·  R / Esc 닫기"
	front.text_at(self, controls, 39, 82, 24 if mobile else 18, MUTED)
	balance_label = front.text_at(self, "", 875, 40, 25, GOLD, 540)
	balance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	front.button_at(self, "전투로 돌아가기", Rect2(1510, 20, 304, 78) if mobile else Rect2(1510, 32, 304, 59), front.close_modal, true)
	board = ResearchBoard.new()
	board.run = run
	board.mobile = mobile
	front.place(board, self, Rect2(36, 203, 1132, 728) if mobile else Rect2(36, 183, 1328, 746))
	board.selected.connect(_select)
	for i in ResearchGraph.ZONES.size():
		_zone_buttons.append(front.button_at(self, ResearchGraph.ZONES[i], Rect2(36 + i * 151, 126, 143, 65) if mobile else Rect2(36 + i * 151, 121, 139, 44), board.jump.bind(i)))
	front.button_at(self, "전체 보기", Rect2(946, 126, 180, 65) if mobile else Rect2(1216, 121, 148, 44), board.overview)
	var search := OptionButton.new()
	search.add_item("타워 연구 찾기")
	for id in registry.ids:
		if id != TowerRegistry.BASE:
			search.add_item(registry.lookup(id).name)
			search.set_item_metadata(search.item_count - 1, id)
	search.get_popup().max_size = Vector2i(460, 590)
	search.item_selected.connect(_jump_to_tower.bind(search))
	front.place(search, self, Rect2(1192, 126, 620, 65) if mobile else Rect2(1392, 121, 420, 44))
	var panel_rect := Rect2(1192, 203, 620, 728) if mobile else Rect2(1392, 183, 420, 746)
	var panel: Panel = front.panel_at(self, panel_rect, "#191e23", "#414649")
	_detail_frame = panel.get_theme_stylebox("panel") as StyleBoxFlat
	if mobile:
		_make_mobile_details(panel)
	else:
		heading = front.text_at(panel, "", 23, 19, 28, INK, 374)
		cost = front.text_at(panel, "", 23, 63, 23, GOLD, 374)
		description = _wrap(panel, 107, 19, MUTED)
		front.text_at(panel, "선행 조건", 23, 214, 19, MINT)
		requirements = _wrap(panel, 246, 18, INK)
		front.text_at(panel, "연구 결과", 23, 414, 19, MINT)
		outcome = _wrap(panel, 449, 18, INK)
		link_summary = _wrap(panel, 533, 16, MUTED)
		buy = front.button_at(panel, "연구 완료", Rect2(23, 650, 374, 60), _purchase, true)
		for i in ResearchGraph.LANES.size():
			front.text_at(self, ResearchGraph.LANES[i], 40 + i * 186, 947, 16, Color(ResearchGraph.COLORS[i]))
		front.text_at(self, "녹색 완료  ·  금색 RP 부족  ·  회색 선행 조건 미충족", 985, 947, 16, MUTED)
	_accent_stage = run.highest_stage
	_apply_accent(STAGE_TINTS[_accent_stage])
	run.changed.connect(_schedule_refresh)
	if not view.is_empty():
		board.zoom = view.zoom
		board.offset = view.offset
		board.overview_mode = bool(view.get("overview", false))
	var initial := str(view.get("focus", run.graph.ids[0]))
	if run.graph.unlocks.has(jump_tower):
		board.select_node(run.graph.unlocks[jump_tower], true)
	else:
		board.select_node(initial)

func _make_mobile_details(panel: Panel) -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	front.place(scroll, panel, Rect2(22, 18, 576, 598))
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 12)
	scroll.add_child(details)
	heading = _mobile_detail(details, "", 34, INK)
	cost = _mobile_detail(details, "", 26, GOLD)
	description = _mobile_detail(details, "", 25, MUTED)
	_mobile_detail(details, "선행 조건", 26, MINT)
	requirements = _mobile_detail(details, "", 24, INK)
	_mobile_detail(details, "연구 결과", 26, MINT)
	outcome = _mobile_detail(details, "", 24, INK)
	link_summary = _mobile_detail(details, "", 22, MUTED)
	buy = front.button_at(panel, "연구 완료", Rect2(22, 627, 576, 79), _purchase, true)
	front.text_at(self, "녹색 완료  ·  금색 RP 부족  ·  회색 선행 조건 미충족", 37, 941, 22, MUTED)

func _mobile_detail(parent: VBoxContainer, value: String, font_size: int, tint: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _wrap(parent: Control, y: int, font_size: int, color: Color) -> Label:
	var label: Label = front.text_at(parent, "", 23, y, font_size, color, 374)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	return label

func view_state() -> Dictionary:
	return {"zoom": board.zoom, "offset": board.offset, "focus": board.focus_id, "overview": board.overview_mode}

func _jump_to_tower(index: int, picker: OptionButton) -> void:
	if index > 0:
		var tower_id: String = picker.get_item_metadata(index)
		board.select_node(run.graph.unlocks[tower_id], true)
		picker.select(0)

func _select(_id: String) -> void:
	_refresh()

func _schedule_refresh() -> void:
	if not _pending_refresh:
		_pending_refresh = true
		_refresh.call_deferred()

func _refresh() -> void:
	_pending_refresh = false
	if _accent_stage != run.highest_stage:
		_zone_buttons[_accent_stage].remove_theme_color_override("font_color")
		_accent_stage = run.highest_stage
		if _accent_tween != null and _accent_tween.is_running():
			_accent_tween.kill()
		_accent_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_accent_tween.tween_method(_apply_accent, _accent, STAGE_TINTS[_accent_stage], 0.58)
	var id := board.focus_id
	var node: Dictionary = run.graph.nodes[id]
	var state := run.state(id)
	var def: Dictionary = front.battle.tower_definition(str(node.get("unlock", {}).get("id", "")))
	balance_label.text = "%d RP     ·     연구 %d / %d" % [run.points, run.completed.size(), run.graph.ids.size()]
	heading.text = node.name
	if _last_focus != id or _completed_count != run.completed.size():
		_minimum = run.minimum_cost(id)
		_last_focus = id
		_completed_count = run.completed.size()
	cost.text = "%d RP    ·    남은 최소 %d RP" % [run.cost(id), _minimum]
	requirements.text = run.graph.requirement_text(node.requirements, run.completed)
	if def.is_empty():
		description.text = node.get("description", "%s 계열의 연결 연구입니다." % ResearchGraph.LANES[int(node.lane)])
		outcome.text = "연결된 후속 연구의 선행 조건을 충족합니다."
	else:
		description.text = def.description
		outcome.text = "%s 해금  ·  설치 %d 재화" % [def.name, int(def.cost)]
	var links: PackedStringArray = []
	for child: String in run.graph.children[id]:
		links.append(run.graph.nodes[child].name)
	link_summary.text = "후속  " + "  ·  ".join(links) if not links.is_empty() else ""
	var states := {&"done": "완료됨", &"ready": "연구 완료", &"locked": "선행 조건 미충족", &"insufficient": "연구 포인트 부족"}
	buy.text = states[state]
	buy.disabled = state != &"ready"

func _apply_accent(color: Color) -> void:
	_accent = color
	_title.add_theme_color_override("font_color", INK.lerp(color, 0.28))
	_zone_buttons[_accent_stage].add_theme_color_override("font_color", INK.lerp(color, 0.58))
	_detail_frame.border_color = Color("#414649").lerp(color, 0.31)
	_detail_frame.bg_color = Color("#191e23").lerp(color, 0.043)
	board.set_stage_tint(color)

func _purchase() -> void:
	if run.purchase(board.focus_id):
		board.refresh()
		_refresh()
