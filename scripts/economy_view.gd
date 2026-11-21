class_name EconomyView
extends Node2D

const GOLD := Color("#ffd37b")
const DATA := Color("#71eed8")
const QUANTUM := Color("#d4b8ff")
const SURGE_TIME := 0.80

var _field
var _profile
var _glow: Texture2D
var _economy: TowerEconomy
var _surge := 0.0
var _pulses: Array[Dictionary] = []
var _had_towers := false

func setup(view, profile, glow: Texture2D) -> void:
	_field = view
	_profile = profile
	_glow = glow
	_economy = view.battle.economy
	view.battle.economy_produced.connect(_on_produced)

func _on_produced(towers: Array) -> void:
	_pulses.clear()
	if _profile.fx_quality <= 0:
		return
	var limit := 12 if _profile.fx_quality == 1 else 32
	for i in mini(towers.size(), limit):
		var tower = towers[i]
		_pulses.append({
			"at": _field.pixel(tower.position), "tint": tower.definition.tint,
			"size": 78.0 if tower.definition.economy == "core" else 40.0 + 5.0 * int(tower.definition.stage),
		})
	_surge = SURGE_TIME
	queue_redraw()

func update_effects(delta: float) -> void:
	var fading := _surge > 0.0
	_surge = maxf(0.0, _surge - delta)
	var has_towers := not _economy.installed.is_empty()
	if fading or has_towers or _had_towers:
		queue_redraw()
	_had_towers = has_towers

func _draw() -> void:
	var quality: int = _profile.fx_quality
	if quality == 0:
		return
	var brightness := 0.52 if _profile.fx_dim else 1.0
	var time: float = _field.elapsed
	var connections := PackedVector2Array()
	var producer_particles := roundi(float(_profile.fx_particles) * (10 if quality == 1 else 32))
	var link_particles := roundi(float(_profile.fx_particles) * (8 if quality == 1 else 23))
	for tower in _economy.installed:
		var def: Dictionary = tower.definition
		var at: Vector2 = _field.pixel(tower.position)
		var color: Color = def.tint
		var phase: float = time + tower.cell.x * 0.27 + tower.cell.y * 0.39
		var degree := int(def.stage)
		var role: String = def.economy
		if int(def.production) > 0:
			_draw_producer(at, role, degree, color, phase, brightness, producer_particles > 0)
			producer_particles -= 1
		else:
			var targets := _economy.connected(tower)
			_draw_source(at, role, targets.size(), color, phase, brightness)
			if role != "core":
				continue
			# Batch core links, keeping dense complexes readable.
			var link_budget := 40 if quality == 1 else 120
			for target in targets:
				if connections.size() >= 2 * link_budget:
					break
				var finish: Vector2 = _field.pixel(target.position)
				connections.append(at)
				connections.append(finish)
				if link_particles > 0:
					var travel := fposmod(phase * 0.74 + link_particles * 0.17, 1.0)
					draw_circle(at.lerp(finish, travel), 2.2, Color(GOLD, 0.65 * brightness), true, -1.0, true)
					link_particles -= 1
	if not connections.is_empty():
		draw_multiline(connections, Color(GOLD, 0.30 * brightness), 1.4, true)
	for target in _economy.providers:
		var at: Vector2 = _field.pixel(target.position)
		for role in _economy.providers[target]:
			var color := DATA if role == "rp_amp" else GOLD
			var radius := 33.0 if role == "core" else 28.0
			var start := time * (0.70 if role == "core" else -0.85)
			draw_arc(at, radius, start, start + PI * 1.22, 16, Color(color, 0.62 * brightness), 1.55, true)
	if _surge > 0.0:
		var progress := 1.0 - _surge / SURGE_TIME
		for pulse in _pulses:
			var spread := float(pulse.size)
			var ink := Color(pulse.tint, _surge / SURGE_TIME * brightness * 0.78)
			draw_arc(pulse.at, 19.0 + spread * progress, 0.0, TAU, 32, ink, 2.0, true)
			if quality >= 2:
				draw_arc(pulse.at, 12.0 + spread * progress * 0.68, 0.0, TAU, 24, Color(ink, ink.a * 0.54), 1.3, true)

func _draw_producer(at: Vector2, role: String, stage: int, tint: Color, phase: float, brightness: float, particle: bool) -> void:
	var pigment := Color(tint, 0.54 * brightness)
	if role == "credits":
		if stage >= 2:
			draw_arc(at, 27.0 + 3.0 * stage, phase * 1.2, phase * 1.2 + 4.1, 22, pigment, 1.8, true)
		if stage >= 4:
			draw_texture_rect(_glow, Rect2(at - Vector2.ONE * 43, Vector2.ONE * 86), false, Color(GOLD, 0.21 * brightness))
	elif stage == 2:
		var tilt := sin(phase * 1.4) * 7.0
		draw_polyline(PackedVector2Array([at + Vector2(-19, tilt), at + Vector2(0, -11 + tilt), at + Vector2(19, tilt)]), pigment, 1.8, true)
	else:
		draw_arc(at, 31.0, phase * 1.5, phase * 1.5 + 4.2, 22, pigment, 1.6, true)
		if stage >= 4:
			draw_arc(at, 38.0, -phase, -phase + 3.3, 19, Color(QUANTUM.lerp(Color.WHITE, 0.60), 0.58 * brightness), 1.7, true)
	if particle:
		var travel := fposmod(phase * 0.75, 1.0)
		var point := at + Vector2.from_angle(phase * 1.8) * lerpf(38.0, 8.0, travel)
		draw_circle(point, 2.7 if role == "credits" else 2.1, Color(tint, brightness * sin(travel * PI)), true, -1.0, true)

func _draw_source(at: Vector2, role: String, count: int, tint: Color, phase: float, brightness: float) -> void:
	var active := 0.76 if count > 0 else 0.25
	var ink := Color(tint, active * brightness)
	draw_arc(at, 35.0, phase, phase + TAU * 0.75, 23, ink, 1.7, true)
	if role == "rp_amp":
		draw_arc(at, 41.0, -phase, -phase + PI, 16, Color(QUANTUM, ink.a * 0.64), 1.6, true)
	if role != "core" or count < 4:
		return
	draw_arc(at, 45.0, -phase * 0.76, -phase * 0.76 + TAU * 0.70, 24, ink, 1.65, true)
	if count >= 8:
		var rhythm := fposmod(phase * 0.74, 1.0)
		draw_texture_rect(_glow, Rect2(at - Vector2.ONE * 59, Vector2.ONE * 118), false, Color(GOLD, 0.28 * brightness))
		draw_arc(at, 46.0 + rhythm * 31.0, 0.0, TAU, 27, Color(GOLD, (1.0 - rhythm) * 0.52 * brightness), 1.4, true)
