extends SceneTree

const STEP := 1.0 / 60.0
var checked := 0
var failures := 0
var ui

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checked += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _run() -> void:
	var profile = root.get_node("Profile")
	check(profile.mobile_mode, "mobile UI enabled")
	profile.file_path = "user://mobile_qa_profile.cfg"
	profile.load_profile()
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1080, 486) if "--wide-mobile" in OS.get_cmdline_user_args() else Vector2i(960, 540)
	ui = (load("res://scenes/Front.tscn") as PackedScene).instantiate()
	root.add_child(ui)
	for frame in range(5):
		await process_frame
	await _tap_control(ui.screen.get_node("StartGame"))
	if not _expect_modal("difficulty"):
		_finish()
		return
	await _tap_button(ui.modal, "제약 모드")
	if not _expect_modal("constraints"):
		_finish()
		return
	var constraints := ui.modal.get_child(0).get_child(0) as ConstraintsScreen
	constraints._difficulty.select(0)
	await _tap_control(constraints._steppers[&"boss_hp"][1])
	check(constraints._effects[&"boss_hp"].text.contains("+50%"), "touch stepper changes the challenge level")
	await _capture("android-constraints")
	await _tap_button(ui.modal, "이 설정으로 시작")
	check(ui.game and ui.battle.difficulty == &"easy" and ui.battle.constraints.count() == 1, "touch starts the selected constrained game")
	if not ui.game:
		_finish()
		return
	var sim: Battle = ui.battle
	await _tap_control(ui.catalog_button)
	if not _expect_modal("catalog"):
		_finish()
		return
	var picker := ui.modal.get_child(0).get_child(0) as MobileTowerPicker
	check(picker != null and picker._details.text.contains("기본 피해 1"), "mobile catalog presents base tower stats")
	await _tap_button(ui.modal, "전체")
	picker = ui.modal.get_child(0).get_child(0) as MobileTowerPicker
	check(picker._list.get_child_count() == sim.data.towers.ids.size(), "all existing towers are in the mobile catalog")
	await _capture("android-towers")
	var list_scroll := picker._list.get_parent() as ScrollContainer
	var next_tower := picker._list.get_child(1) as Button
	await _tap_control(next_tower)
	check(picker._selected == next_tower.get_meta("tower"), "tower row tap opens its details")
	await _tap_control(picker._list.get_child(0))
	await _swipe(_logical_to_input(list_scroll, Vector2(240, 550)), _logical_to_input(list_scroll, Vector2(240, 190)))
	check(list_scroll.scroll_vertical > 0 and picker._selected == TowerRegistry.BASE, "tower list scrolls on a swipe without choosing a tower (scroll %d, selected %s)" % [list_scroll.scroll_vertical, picker._selected])
	await _tap_button(ui.modal, "배치 준비")
	check(ui.building, "touch enters placement")
	var cell := Vector2i(8, 4)
	var at := _logical_to_input(ui, FieldView.pixel(Vector2(cell) + Vector2.ONE * 0.5))
	await _tap(at)
	check(ui.field.hovered == cell and sim.towers.is_empty(), "first field tap previews the intended tile")
	await _tap(at)
	check(sim.occupied.has(cell) and sim.credits == 40, "second field tap installs the tower exactly once")
	await _tap_control(ui.build_button)
	await _tap(at)
	check(ui.selected == cell and ui.tower_stats.visible, "tap selects existing tower and shows stats")
	await _tap_control(ui.sell_button)
	check(sim.towers.is_empty() and sim.credits == 50, "touch sells the selected tower and returns funds")
	await _field_gestures()
	await _tap_control(ui.wave_button)
	check(sim.wave == 1 and sim.active, "touch starts the wave")
	await _capture("android-battle")
	await _tap_control(ui.research_button)
	if _expect_modal("research"):
		await _research(sim)
		ui.close_modal()
	ui.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	if _expect_modal("pause"):
		await _tap_button(ui.modal, "설정")
		if _expect_modal("pause_settings"):
			check(ui.modal.find_children("*", "OptionButton", true, false).is_empty(), "mobile settings omit desktop display controls")
			await _tap_button(ui.modal, "전투 효과 설정")
			if _expect_modal("effects_settings"):
				check(ui.modal.find_children("*", "HSlider", true, false).size() == 5, "mobile effect settings include adjustable render costs")
				await _capture("android-effects")
	_finish()

func _field_gestures() -> void:
	var first := _logical_to_input(ui, Vector2(760, 514))
	var second := _logical_to_input(ui, Vector2(1000, 514))
	var outward := _logical_to_input(ui, Vector2(1180, 514))
	await _pinch(first, second, outward)
	check(ui.camera_fx.manual_zoom > 1.0 and ui.battle.towers.is_empty(), "field pinch zooms without placing or selecting")
	await _tap_control(ui.zoom_button)
	check(is_equal_approx(ui.camera_fx.manual_zoom, 1.0), "tap resets the field zoom")

func _research(sim: Battle) -> void:
	var board: ResearchBoard = ui.research_screen.board
	check(board.mobile and board.zoom > 1.0, "research starts with readable mobile cards")
	var start := _logical_to_input(board, Vector2(220, 395))
	var midpoint := _logical_to_input(board, Vector2(420, 395))
	var end := _logical_to_input(board, Vector2(575, 395))
	var old_zoom := board.zoom
	await _pinch(start, midpoint, end)
	check(board.zoom > old_zoom, "two touches zoom the research board")
	var old_offset := board.offset
	await _swipe(midpoint, end)
	check(board.offset != old_offset, "one touch drags the research board")
	var id: String = sim.research.graph.ids[0]
	sim.research.earn(sim.research.cost(id))
	board.select_node(id, true)
	var node_point := (sim.research.graph.point(id) * board.zoom) + board.offset
	var selected: Array[String] = []
	board.selected.connect(func(key: String): selected.append(key))
	await _tap(_logical_to_input(board, node_point))
	check(selected == [id] and board.focus_id == id and not ui.research_screen.cost.text.is_empty(), "a node tap selects its details once")
	await _capture("android-research")
	await _tap_control(ui.research_screen.buy)
	check(sim.research.completed.has(id) and sim.research.points == 0, "touch confirms one paid research")

func _expect_modal(kind: String) -> bool:
	var matches: bool = ui.modal_kind == kind
	check(matches, "touch reaches " + kind + " (found " + str(ui.modal_kind) + ")")
	return matches

func _tap_button(container: Control, value: String) -> void:
	for button: Button in container.find_children("*", "Button", true, false):
		if button.text == value:
			await _tap_control(button)
			return
	check(false, "button is present: " + value)

func _tap_control(control: Control) -> void:
	await _tap(_logical_to_input(control, control.size * 0.5))

func _logical_to_input(control: Control, point: Vector2) -> Vector2:
	var design_size := Vector2(root.content_scale_size)
	var device_size := Vector2(root.size)
	var fit := minf(device_size.x / design_size.x, device_size.y / design_size.y)
	var inset := (device_size - design_size * fit) * 0.5
	return inset + (control.get_global_transform_with_canvas() * point) * fit

func _tap(point: Vector2) -> void:
	_touch(0, point, true)
	await process_frame
	_touch(0, point, false)
	await process_frame

func _swipe(from: Vector2, to: Vector2) -> void:
	_touch(0, from, true)
	await process_frame
	var previous := from
	for step in range(1, 7):
		var next := from.lerp(to, step / 6.0)
		_drag(0, previous, next)
		previous = next
		await process_frame
	_touch(0, to, false)
	await process_frame

func _pinch(first: Vector2, second: Vector2, finish: Vector2) -> void:
	_touch(0, first, true)
	_touch(1, second, true)
	await process_frame
	_drag(1, second, finish)
	await process_frame
	_touch(1, finish, false)
	_touch(0, first, false)
	await process_frame

func _touch(finger: int, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.window_id = root.get_window_id()
	event.index = finger
	event.position = point
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _drag(finger: int, before: Vector2, after: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.window_id = root.get_window_id()
	event.index = finger
	event.position = after
	event.relative = after - before
	event.screen_relative = event.relative
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _capture(name: String) -> void:
	if "--visual" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var suffix := "-wide" if "--wide-mobile" in OS.get_cmdline_user_args() else ""
		var result := root.get_texture().get_image().save_png("res://reports/" + name + suffix + ".png")
		check(result == OK, "mobile layout captured: " + name)

func _finish() -> void:
	print("Mobile checks: %d, failures: %d" % [checked, failures])
	quit(int(failures > 0))
