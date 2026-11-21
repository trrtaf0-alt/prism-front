class_name TouchGesture
extends RefCounted

signal tapped(point: Vector2)
signal panned(delta: Vector2)
signal pinched(before: Vector2, after: Vector2, factor: float)

const DRAG_THRESHOLD := 22.0

var _positions: Dictionary = {}
var _origin := Vector2.ZERO
var _dragged := false
var _multiple := false

func tracks(index: int) -> bool:
	return _positions.has(index)

func clear() -> void:
	_positions.clear()

func handle(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _positions.is_empty():
				_origin = event.position
				_dragged = false
				_multiple = false
			else:
				_multiple = true
			_positions[event.index] = event.position
			return true
		if tracks(event.index):
			_positions.erase(event.index)
			if not event.canceled and not _multiple and not _dragged and event.position.distance_to(_origin) < DRAG_THRESHOLD:
				tapped.emit(event.position)
			return true
	elif event is InputEventScreenDrag and tracks(event.index):
		var previous: Vector2 = _positions[event.index]
		_positions[event.index] = event.position
		if _positions.size() == 2:
			var ids := _positions.keys()
			var other: Vector2 = _positions[ids[1] if ids[0] == event.index else ids[0]]
			var distance := previous.distance_to(other)
			if distance >= 1.0:
				pinched.emit((previous + other) * 0.5, (event.position + other) * 0.5, event.position.distance_to(other) / distance)
		elif _positions.size() == 1 and not _multiple:
			if _dragged:
				panned.emit(event.position - previous)
			elif event.position.distance_to(_origin) >= DRAG_THRESHOLD:
				_dragged = true
				panned.emit(event.position - _origin)
		return true
	return false
