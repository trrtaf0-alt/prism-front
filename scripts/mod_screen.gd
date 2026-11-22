class_name ModScreen
extends Control

const FILTERS := ["*.zip;Prism Front ZIP;application/zip,application/x-zip-compressed"]
const MUTED := Color("#a4b3ba")
const ACTIVE := Color("#8ee6ca")
const WARNING := Color("#f1aa9c")

var _host
var _library: ModLibrary
var _list: ItemList
var _title: Label
var _status: Label
var _detail: RichTextLabel
var _switch: CheckButton
var _delete: Button
var _confirm: ColorRect
var _picker: FileDialog
var _selected := ""

func setup(host: Control, library: ModLibrary, mobile: bool) -> void:
	_host = host
	_library = library
	mouse_filter = MOUSE_FILTER_IGNORE
	_host.text_at(self, "모드 관리", 32, 22, 48)
	_host.text_at(self, "다음 게임 시작 시 적용 · 재시작 필요 없음", 34, 88, 28, MUTED)
	_host.button_at(self, "모드 추가", Rect2(937, 27, 239, 82), _select_file, true)
	_host.button_at(self, "닫기", Rect2(1196, 27, 192, 82), _host.close_modal)
	_host.button_at(self, "전체 활성화", Rect2(33, 145, 239, 74), _toggle_all.bind(true))
	_host.button_at(self, "전체 비활성화", Rect2(282, 145, 239, 74), _toggle_all.bind(false))
	var list_rect := Rect2(33, 236, 488, 626)
	_list = ItemList.new()
	_list.add_theme_font_size_override("font_size", 31)
	_list.add_theme_constant_override("v_separation", 25)
	_list.add_theme_stylebox_override("panel", _host.box("#101820", "#40525f"))
	_host.place(_list, self, list_rect)
	_list.item_selected.connect(_select_row)
	if mobile:
		var input_area := Control.new()
		_host.place(input_area, self, list_rect)
		var gesture := TouchGesture.new()
		input_area.gui_input.connect(func(event: InputEvent): gesture.handle(event))
		gesture.panned.connect(func(delta: Vector2): _list.get_v_scroll_bar().value -= delta.y)
		gesture.tapped.connect(func(point: Vector2):
			var index := _list.get_item_at_position(point, true)
			if index >= 0:
				_list.select(index)
				_select_row(index)
		)

	_host.panel_at(self, Rect2(545, 145, 843, 717), "#101820", "#40525f")
	_title = _host.text_at(self, "", 574, 160, 38, Color("#f4f2e9"), 788)
	_detail = RichTextLabel.new()
	_detail.add_theme_font_size_override("normal_font_size", 29)
	_detail.add_theme_constant_override("line_separation", 11)
	if mobile:
		_host.mobile_reading_text(_detail)
	_host.place(_detail, self, Rect2(574, 231, 788, 517))
	_switch = CheckButton.new()
	_switch.text = "활성화"
	_switch.add_theme_font_size_override("font_size", 31)
	_host.place(_switch, self, Rect2(574, 769, 374, 74))
	_switch.toggled.connect(_toggle)
	_delete = _host.button_at(self, "삭제", Rect2(1111, 769, 251, 74), _confirm_delete)
	_status = _host.text_at(self, library.storage_error, 33, 881, 26, MUTED, 1355)
	if OS.has_feature("windows"):
		get_window().files_dropped.connect(_import_paths)
	_refresh()

func cancel() -> bool:
	if is_instance_valid(_confirm):
		_dismiss_confirm()
		return true
	return false

func _refresh() -> void:
	var ids := _library.packages.keys()
	ids.sort()
	if not ids.has(_selected):
		_selected = "" if ids.is_empty() else ids[0]
	_list.clear()
	for id: String in ids:
		var index := _list.add_item(str(_library.packages[id].manifest.name))
		_list.set_item_metadata(index, id)
		if _library.problems.has(id):
			_list.set_item_custom_fg_color(index, WARNING)
		elif _library.applied.has(id):
			_list.set_item_custom_fg_color(index, ACTIVE)
		if id == _selected:
			_list.select(index)
			_list.ensure_current_is_visible()
	_detail_for_selection()

func _select_row(index: int) -> void:
	_selected = _list.get_item_metadata(index)
	_detail_for_selection()

func _detail_for_selection() -> void:
	var package: Dictionary = _library.packages.get(_selected, {})
	_switch.visible = not package.is_empty()
	_delete.visible = _switch.visible
	if package.is_empty():
		_title.text = "설치된 모드 없음"
		_detail.text = "모드 추가에서 ZIP 파일을 선택하세요."
		if OS.has_feature("windows"):
			_detail.text += "\n이 화면에 ZIP 파일을 끌어다 놓을 수도 있습니다."
		return
	var manifest: Dictionary = package.manifest
	_title.text = manifest.name
	_switch.set_pressed_no_signal(_library.requested.has(_selected))
	_switch.disabled = package.get("invalid", false)
	var content := PackedStringArray()
	for key in ModLibrary.KEYS:
		var count: int = package.get(key, []).size()
		if count > 0:
			content.append("%s %d개" % [ModLibrary.CONTENT_NAMES[key], count])
	var state := "활성화됨" if _library.applied.has(_selected) else "비활성화"
	if _library.problems.has(_selected):
		state = "적용 보류 · " + _library.problems[_selected]
	var lines := PackedStringArray([
		"제작자 %s  ·  버전 %s" % [manifest.author, manifest.version],
		"콘텐츠   " + (" · ".join(content) if not content.is_empty() else "—"),
		"상태   " + state,
	])
	if not manifest.get("requires", []).is_empty():
		lines.append("필요 모드   " + ", ".join(PackedStringArray(manifest.requires)))
	lines.append("")
	lines.append(manifest.description)
	_detail.text = "\n".join(lines)
	_detail.scroll_to_line(0)

func _select_file() -> void:
	var filters := PackedStringArray(FILTERS)
	var result := DisplayServer.file_dialog_show("모드 ZIP 선택", "", "", false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, filters, _files_selected, get_window().get_window_id())
	if result == OK:
		return
	if OS.has_feature("android"):
		_message("기기 파일 선택기를 열 수 없습니다.", true)
		return
	if not is_instance_valid(_picker):
		_picker = FileDialog.new()
		_picker.title = "모드 ZIP 선택"
		_picker.access = FileDialog.ACCESS_FILESYSTEM
		_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_picker.filters = filters
		_picker.file_selected.connect(func(path: String): _import_paths(PackedStringArray([path])))
		add_child(_picker)
	_picker.popup_centered_ratio(0.70)

func _files_selected(success: bool, paths: PackedStringArray, _filter: int) -> void:
	if success and is_inside_tree():
		_import_paths(paths)

func _import_paths(paths: PackedStringArray) -> void:
	if not is_inside_tree() or _host.modal_kind != "mods" or is_instance_valid(_confirm):
		return
	var installed := 0
	var errors := PackedStringArray()
	for path in paths:
		var error := _library.install(path)
		if error.is_empty():
			installed += 1
			_selected = _library.packages.keys().back()
		else:
			errors.append(error)
	_refresh()
	var message := []
	if installed > 0:
		message.append("%d개 설치 완료 · 목록에서 활성화하세요." % installed)
	if not errors.is_empty():
		message.append(errors[0])
	_message("  ".join(PackedStringArray(message)), not errors.is_empty())

func _toggle(enabled: bool) -> void:
	var error := _library.set_enabled(_selected, enabled)
	if enabled and error.is_empty():
		error = _library.problems.get(_selected, "")
	_refresh()
	_message(error if not error.is_empty() else "다음 게임에 적용됩니다.", not error.is_empty())

func _toggle_all(enabled: bool) -> void:
	var error := _library.set_all(enabled)
	_refresh()
	if not error.is_empty():
		_message(error, true)
	elif enabled:
		var effective := _library.applied.size()
		var pending := _library.requested.size() - effective
		_message("다음 게임에 적용 %d개 · 보류 %d개" % [effective, pending], pending > 0)
	else:
		_message("다음 게임은 기본 콘텐츠로 시작합니다.", false)

func _confirm_delete() -> void:
	_confirm = ColorRect.new()
	_confirm.color = Color("#070b12ea")
	_host.place(_confirm, self, Rect2(Vector2.ZERO, size))
	var panel: Panel = _host.panel_at(_confirm, Rect2(336, 295, 750, 324), "#1b252d", "#6e7778")
	_host.text_at(panel, "모드를 삭제할까요?", 34, 30, 38)
	_host.text_at(panel, _library.packages[_selected].manifest.name, 35, 99, 31, WARNING, 680)
	_host.button_at(panel, "취소", Rect2(34, 209, 320, 80), _dismiss_confirm).grab_focus()
	_host.button_at(panel, "삭제 확인", Rect2(369, 209, 347, 80), _delete_confirmed.bind(_selected), true)

func _dismiss_confirm() -> void:
	remove_child(_confirm)
	_confirm.queue_free()
	_confirm = null

func _delete_confirmed(id: String) -> void:
	var error := _library.remove(id)
	_dismiss_confirm()
	_refresh()
	_message(error if not error.is_empty() else "모드를 삭제했습니다.", not error.is_empty())

func _message(message: String, failed: bool) -> void:
	_status.text = message
	_status.add_theme_color_override("font_color", WARNING if failed else MUTED)
