class_name ResearchBoard
extends Control

signal selected(id: String)
const CARD := Vector2(226, 46)
const EDGE := Color("#31495c")
const GOLD := Color("#ffcf89")

var run: ResearchRun
var registry: TowerRegistry
var zoom := 0.80
var offset := Vector2(28, 10)
var focus_id := ""
var highlighted: Dictionary = {}
var bounds := Rect2()
var _states: Dictionary = {}
var _pressed := false
var _moved := false
var _press_point := Vector2.ZERO
var _links: Array[Dictionary] = []
var _pending_refresh := false

func _ready() -> void:
	clip_contents = true
	mouse_filter = MOUSE_FILTER_STOP
	mouse_default_cursor_shape = CURSOR_DRAG
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
		zoom = 0.9
		offset = size * 0.5 - run.graph.point(id) * zoom
		_clamp_offset()
	queue_redraw()
	selected.emit(id)

func overview() -> void:
	zoom = minf(size.x / bounds.size.x, size.y / bounds.size.y) * 0.95
	offset = (size - bounds.size * zoom) * 0.5
	queue_redraw()

func jump(stage: int) -> void:
	for id in run.graph.ids:
		if int(run.graph.nodes[id].stage) == stage:
			select_node(id, true)
			return

func _clamp_offset() -> void:
	var margin := size * 0.68
	offset = offset.clamp(size - bounds.size * zoom - margin, margin)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var anchor: Vector2 = (event.position - offset) / zoom
			var factor := 1.18 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.18
			zoom = clampf(zoom * factor, 0.10, 1.55)
			offset = event.position - anchor * zoom
			_clamp_offset()
			queue_redraw()
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
			offset += event.relative
			_clamp_offset()
			queue_redraw()
		accept_event()

func _pick(at: Vector2) -> void:
	var point := (at - offset) / zoom
	for id in run.graph.ids:
		if Rect2(run.graph.point(id) - CARD * 0.5, CARD).has_point(point):
			select_node(id)
			return

func _draw() -> void:
	var viewport := Rect2(Vector2.ZERO, size)
	draw_rect(viewport, Color("#0b1622"))
	var cadence := clampf(80.0 * zoom, 24, 100)
	for x in range(int(fposmod(offset.x, cadence)), int(size.x), roundi(cadence)):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color("#142536"))
	for y in range(int(fposmod(offset.y, cadence)), int(size.y), roundi(cadence)):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color("#142536"))
	var graph := run.graph
	var world := Rect2(-offset / zoom, size / zoom).grow(12.0)
	draw_set_transform(offset, 0, Vector2.ONE * zoom)
	for link in _links:
		if not world.intersects(link.bounds):
			continue
		var active: bool = (link.target == focus_id or highlighted.has(link.target)) and highlighted.has(link.parent)
		var tint := Color("#91dcec") if active else (Color("#466f64") if run.completed.has(link.parent) else EDGE)
		draw_polyline(link.curve, tint, (2.8 if active else 1.5) / zoom, true)
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
				border = Color("#425268")
			&"insufficient":
				border = GOLD.darkened(0.25)
			&"done":
				border = Color("#61e3ac")
		if id == focus_id:
			draw_rect(card.grow(4), Color(color, 0.24))
		draw_rect(card, Color("#172c39") if state != &"locked" else Color("#111e2b"))
		draw_rect(card, border, false, 2.0 if id == focus_id else 1.35)
		draw_rect(Rect2(at, Vector2(5.0, CARD.y)), color)
		var badge := "해금" if node.has("unlock") else "경유"
		draw_circle(at + Vector2(15, 23), 3.2, border)
		if zoom >= 0.42:
			draw_string(font, at + Vector2(25, 28), node.name, HORIZONTAL_ALIGNMENT_LEFT, 153, 17, Color("#e6f3ff"))
			draw_string(font, at + Vector2(175, 27), "완료" if state == &"done" else badge, HORIZONTAL_ALIGNMENT_RIGHT, 40, 12, border)
	draw_set_transform(Vector2.ZERO)
	draw_rect(viewport, EDGE, false)
