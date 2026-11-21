class_name ResearchBoard
extends Control

signal selected(id: String)
const CARD := Vector2(226, 46)
const EDGE := Color("#414b50")
const GOLD := Color("#dcc197")

var run: ResearchRun
var mobile := false
var _gesture := TouchGesture.new()
var zoom := 0.80
var overview_mode := false
var offset := Vector2(28, 10)
var focus_id := ""
var highlighted: Dictionary = {}
var bounds := Rect2()
var _states: Dictionary = {}
var _stage_tint := Color("#a9c6bd")
var _pressed := false
var _moved := false
var _press_point := Vector2.ZERO
var _links: Array[Dictionary] = []
var _pending_refresh := false

func _ready() -> void:
	clip_contents = true
	mouse_filter = MOUSE_FILTER_STOP
	mouse_default_cursor_shape = CURSOR_DRAG
	if mobile:
		zoom = 1.35
		_gesture.tapped.connect(_pick)
		_gesture.panned.connect(_pan)
		_gesture.pinched.connect(_zoom_from)
	for id in run.graph.ids:
		var point := run.graph.point(id)
		bounds = bounds.expand(point + CARD * 0.5 + Vector2(32, 88))
		for parent: String in run.graph.parents[id]:
			var start := run.graph.point(parent) + Vector2(CARD.x * 0.5, 0)
			var destination := point - Vector2(CARD.x * 0.5, 0)
			var dx := maxf(28, (destination.x - start.x) * 0.45)
			var curve := Curve2D.new()
			curve.add_point(start, Vector2.ZERO, Vector2(dx, 0))
			curve.add_point(destination, Vector2(-dx, 0), Vector2.ZERO)
			_links.append({
				"parent": parent, "target": id, "end": destination,
				"bounds": Rect2(start.min(destination), (destination - start).abs()).grow(12),
				"curve": curve.tessellate(3, 15),
			})
	run.changed.connect(_schedule_refresh)
	refresh()

func _schedule_refresh() -> void:
	if not _pending_refresh:
		_pending_refresh = true
		refresh.call_deferred()

func refresh() -> void:
	_pending_refresh = false
	for id in run.graph.ids:
		_states[id] = run.state(id)
	queue_redraw()

func select_node(id: String, pan_to: bool = false) -> void:
	focus_id = id
	highlighted = run.graph.ancestors(id)
	if pan_to:
		overview_mode = false
		zoom = 1.35 if mobile else 0.9
		var alignment := 0.38 if int(run.graph.nodes[id].stage) == 0 else 0.74
		offset = size * Vector2(alignment, 0.5) - run.graph.point(id) * zoom
		_clamp_offset()
	queue_redraw()
	selected.emit(id)

func overview() -> void:
	overview_mode = true
	zoom = size.x / bounds.size.x * 0.94
	offset = (size - bounds.size * _view_scale()) * 0.5
	queue_redraw()

func _view_scale() -> Vector2:
	var vertical := 0.84 * size.y / bounds.size.y if overview_mode else zoom
	return Vector2(zoom, vertical)

func jump(stage: int) -> void:
	for id in run.graph.ids:
		if int(run.graph.nodes[id].stage) == stage:
			select_node(id, true)
			return

func _clamp_offset() -> void:
	var margin := size * 0.68
	offset = offset.clamp(size - bounds.size * _view_scale() - margin, margin)

func _gui_input(event: InputEvent) -> void:
	if mobile and (_gesture.handle(event) or event.device == InputEvent.DEVICE_ID_EMULATION):
		accept_event()
		return
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var factor := 1.18 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.18
			_zoom_from(event.position, event.position, factor)
			accept_event()
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			if event.pressed:
				_pressed = true
				_moved = event.button_index == MOUSE_BUTTON_MIDDLE
				_press_point = event.position
			else:
				if _pressed and not _moved:
					_pick(event.position)
				_pressed = false
			accept_event()
	elif event is InputEventMouseMotion and _pressed:
		_moved = _moved or event.position.distance_squared_to(_press_point) > 25.0
		if _moved:
			_pan(event.relative)
		accept_event()

func _pan(delta: Vector2) -> void:
	offset += delta
	_clamp_offset()
	queue_redraw()

func _zoom_from(before: Vector2, after: Vector2, factor: float) -> void:
	var anchor := (before - offset) / _view_scale()
	overview_mode = false
	zoom = clampf(zoom * factor, 0.10, 2.4 if mobile else 1.55)
	offset = after - anchor * _view_scale()
	_clamp_offset()
	queue_redraw()

func _pick(at: Vector2) -> void:
	var point := (at - offset) / _view_scale()
	for id in run.graph.ids:
		if Rect2(run.graph.point(id) - CARD * 0.5, CARD).has_point(point):
			select_node(id)
			return
	if mobile and not overview_mode:
		var nearest := ""
		var distance := INF
		for id in run.graph.ids:
			var center := run.graph.point(id)
			var card := Rect2(center - CARD * 0.5, CARD).grow(14.0 / zoom)
			if card.has_point(point) and point.distance_squared_to(center) < distance:
				distance = point.distance_squared_to(center)
				nearest = id
		if not nearest.is_empty():
			select_node(nearest)

func set_stage_tint(color: Color) -> void:
	_stage_tint = color
	queue_redraw()

func _draw() -> void:
	var viewport := Rect2(Vector2.ZERO, size)
	var base := Color("#111519")
	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]),
		PackedColorArray([base.lerp(_stage_tint, 0.096), base.lerp(_stage_tint, 0.054), base, base.lerp(_stage_tint, 0.025)])
	)
	var grid := Color("#1c2227").lerp(_stage_tint, 0.05)
	var cadence := clampf(80.0 * zoom, 24, 100)
	for x in range(int(fposmod(offset.x, cadence)), int(size.x), roundi(cadence)):
		draw_line(Vector2(x, 0), Vector2(x, size.y), grid)
	for y in range(int(fposmod(offset.y, cadence)), int(size.y), roundi(cadence)):
		draw_line(Vector2(0, y), Vector2(size.x, y), grid)
	var graph := run.graph
	var view_scale := _view_scale()
	var world := Rect2(-offset / view_scale, size / view_scale).grow(12.0)
	draw_set_transform(offset, 0, view_scale)
	for link in _links:
		if not world.intersects(link.bounds):
			continue
		var active: bool = (link.target == focus_id or highlighted.has(link.target)) and highlighted.has(link.parent)
		var tint := Color("#a9c6bd") if active else (Color("#466f64") if run.completed.has(link.parent) else EDGE)
		var thickness := (1.05 if active else 0.7) / view_scale.y if overview_mode else (2.8 if active else 1.5) / zoom
		draw_polyline(link.curve, tint, thickness, true)
		if zoom > 0.45:
			var destination: Vector2 = link.end
			draw_colored_polygon(PackedVector2Array([destination, destination + Vector2(-8, 4), destination + Vector2(-8, -4)]), tint)
	var font := get_theme_default_font()
	for id in graph.ids:
		var node: Dictionary = graph.nodes[id]
		var at := graph.point(id) - CARD * 0.5
		var card := Rect2(at, CARD)
		if not world.intersects(card):
			continue
		var color := Color(graph.COLORS[int(node.lane)])
		var state: StringName = _states.get(id, &"locked")
		var border := color
		match state:
			&"locked":
				border = Color("#475156")
			&"insufficient":
				border = GOLD.darkened(0.25)
			&"done":
				border = Color("#83b09d")
		if id == focus_id:
			draw_rect(card.grow(4), Color(color, 0.24))
		var fill := Color("#212b30") if state != &"locked" else Color("#171e24")
		if overview_mode:
			fill = fill.lerp(color, 0.30)
		draw_rect(card, fill)
		draw_rect(card, border, false, 2.0 if id == focus_id else 1.35)
		draw_rect(Rect2(at, Vector2(5.0, CARD.y)), color)
		var badge := "해금" if node.has("unlock") else "경유"
		draw_circle(at + Vector2(15, 23), 3.2, border)
		if mobile and not overview_mode and zoom >= 0.95:
			# Rasterize text at its display size so pinch zoom doesn't scale the glyph bitmap.
			draw_set_transform(Vector2.ZERO)
			var anchor := (offset + (at + Vector2(25, 0)) * view_scale).round()
			var width := (CARD.x - 33.0) * zoom
			draw_string(font, anchor + Vector2(0, roundf(20.0 * zoom)), node.name, HORIZONTAL_ALIGNMENT_LEFT, width, roundi(21.0 * zoom), Color("#f4f2e9"))
			var badge_tint := border.lerp(Color("#f4f2e9"), 0.60)
			draw_string(font, anchor + Vector2(0, roundf(39.0 * zoom)), "완료" if state == &"done" else badge, HORIZONTAL_ALIGNMENT_LEFT, width, roundi(17.0 * zoom), badge_tint)
			draw_set_transform(offset, 0, view_scale)
		elif not mobile and zoom >= 0.42:
			draw_string(font, at + Vector2(25, 28), node.name, HORIZONTAL_ALIGNMENT_LEFT, 153, 17, Color("#eee9dc"))
			draw_string(font, at + Vector2(175, 27), "완료" if state == &"done" else badge, HORIZONTAL_ALIGNMENT_RIGHT, 40, 12, border)
	draw_set_transform(Vector2.ZERO)
	if overview_mode:
		var prior_stage := -1
		for id in graph.ids:
			var stage := int(graph.nodes[id].stage)
			if stage == prior_stage:
				continue
			prior_stage = stage
			var x := maxf(10.0, graph.point(id).x * zoom + offset.x - 18.0)
			draw_string(font, Vector2(x, 29), graph.ZONES[stage], HORIZONTAL_ALIGNMENT_LEFT, -1, 22 if mobile else 16, Color("#c5ccc9") if mobile else Color("#a5a8a5"))
	draw_rect(viewport, EDGE.lerp(_stage_tint, 0.30), false)
