class_name AttackEffects
extends Node2D

const BUDGET := 400
const LIMITS := [13, 30, 55, 88]
const HUGE_LIMIT := 18
const REFRESHABLE := ["vortex", "plasma", "gravity"]

class Effect:
	var style: String
	var origin: Vector2
	var end: Vector2
	var radius: float
	var tint: Color
	var elapsed: float
	var life: float

var _ordinary: Array[Effect] = []
var _huge: Array[Effect] = []
var _pool: Array[Effect] = []
var _lines: SpriteBatch
var _rings: SpriteBatch
var _glows: SpriteBatch
var _particles: SpriteBatch
var _line_count := 0
var _ring_count := 0
var _glow_count := 0
var _particle_count := 0
var _flash := 0.0
var _flash_tint := Color.WHITE
var _tremor := 0.0
var _time := 0.0
var _style_counts: Dictionary = {}
var _preferences
var _sound
var _field: Rect2
var _cell: float

func setup(glow: Texture2D, preferences: Node, sound: Node, bounds: Rect2, cell: float) -> void:
	_field = bounds
	_cell = cell
	_preferences = preferences
	_sound = sound
	var white := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	var dot := ImageTexture.create_from_image(white)
	var beam := Image.create_empty(4, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		var strength := 1.0 - smoothstep(0.25, 1.0, absf((y - 31.5) / 31.5))
		for x in 4:
			beam.set_pixel(x, y, Color(1.0, 1.0, 1.0, strength))
	var beam_texture := ImageTexture.create_from_image(beam)
	_lines = SpriteBatch.new(beam_texture, 1.0, null)
	_rings = SpriteBatch.new(beam_texture, 2.0, null, _annulus())
	_glows = SpriteBatch.new(glow, 2.0, null)
	_particles = SpriteBatch.new(dot, 1.0, null)
	for batch: SpriteBatch in [_glows, _rings, _lines, _particles]:
		add_child(batch)

static func _annulus() -> ArrayMesh:
	const SEGMENTS := 96
	var points := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in SEGMENTS:
		var edge := Vector2.from_angle(i * TAU / SEGMENTS)
		points.append(Vector3(edge.x, edge.y, 0.0) * 0.968)
		points.append(Vector3(edge.x, edge.y, 0.0))
		uv.append(Vector2(0.5, 0.0))
		uv.append(Vector2(0.5, 1.0))
		var a := i * 2
		var b := ((i + 1) % SEGMENTS) * 2
		indices.append_array(PackedInt32Array([a, a + 1, b, b, a + 1, b + 1]))
	var surface: Array = []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = points
	surface[Mesh.ARRAY_TEX_UV] = uv
	surface[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	return mesh

func capture_mob(kind: StringName, start: Vector2, finish: Vector2, tint: Color, life: float) -> void:
	var radius := 2.7 if kind in [&"boss_spawn", &"boss_down", &"phase"] else 0.65
	capture("mob_" + String(kind), start, finish, radius, tint, life, 0)

func capture(style: String, start: Vector2, finish: Vector2, radius: float, tint: Color, life: float, _stage: int) -> void:
	var large := style.begins_with("charge_") or style in ["cataclysm", "nova", "singularity", "collapse_gravity", "doom", "orbit", "mob_boss_spawn", "mob_boss_down", "mob_phase", "support_sync"]
	var layer := _huge if large else _ordinary
	var limit: int = HUGE_LIMIT if large else LIMITS[_preferences.fx_quality]
	var from := _field.position + start * _cell
	var to := _field.position + finish * _cell
	var extent := Rect2(from.min(to), (to - from).abs()).grow(maxf(_cell, radius * _cell))
	if not _field.grow(95).intersects(extent):
		return
	if not large and style in REFRESHABLE:
		for prior in _ordinary:
			if prior.style == style and prior.origin.distance_squared_to(from) <= 38 * 38:
				prior.origin = from
				prior.end = to
				prior.elapsed = minf(prior.elapsed * 0.3, life * 0.15)
				prior.radius = radius
				return
	var style_limit := 38 if style == "spectrum" else 31
	if not large and int(_style_counts.get(style, 0)) >= style_limit:
		return
	if layer.size() >= limit:
		if not large:
			return
		_recycle(layer.pop_front())
	var rule: Effect = Effect.new() if _pool.is_empty() else _pool.pop_back()
	rule.style = style
	rule.origin = from
	rule.end = to
	rule.radius = radius
	rule.tint = tint
	rule.elapsed = 0.0
	rule.life = life
	layer.append(rule)
	_style_counts[style] = int(_style_counts.get(style, 0)) + 1
	if style in ["cataclysm", "nova", "doom", "collapse_gravity"]:
		_flash = maxf(_flash, 0.68 if style == "cataclysm" else 0.31)
		_flash_tint = tint
		_tremor = maxf(_tremor, 13.0 if style == "cataclysm" else 5.0)
		_sound.cue(&"heavy")
	elif style in ["mob_boss_spawn", "mob_phase"]:
		_sound.cue(&"charge")
	elif style == "mob_boss_down":
		_sound.cue(&"heavy")
	elif style == "mob_shield_break":
		_sound.cue(&"arc")
	elif style.begins_with("mob_"):
		return
	elif style.begins_with("charge_"):
		_sound.cue(&"charge")
	elif style in ["arc", "storm"]:
		_sound.cue(&"arc")
	else:
		_sound.cue(&"fire")

func update(delta: float) -> Vector2:
	_time += delta
	_flash = maxf(0.0, _flash - delta * 1.80)
	_tremor = maxf(0.0, _tremor - delta * 17.0)
	if not _ordinary.is_empty() or not _huge.is_empty() or _line_count + _ring_count + _glow_count + _particle_count > 0:
		_line_count = 0
		_ring_count = 0
		_glow_count = 0
		_particle_count = 0
		for batch: SpriteBatch in [_lines, _rings, _glows, _particles]:
			batch.begin(BUDGET)
		_step_layer(_huge, delta)
		_step_layer(_ordinary, delta)
		_lines.finish(_line_count)
		_rings.finish(_ring_count)
		_glows.finish(_glow_count)
		_particles.finish(_particle_count)
	queue_redraw()
	return Vector2(sin(_time * 104), cos(_time * 87)) * _tremor * _preferences.fx_shake

func _step_layer(layer: Array[Effect], delta: float) -> void:
	for i in range(layer.size() - 1, -1, -1):
		var fx := layer[i]
		fx.elapsed += delta
		if fx.elapsed >= fx.life:
			_recycle(fx)
			layer[i] = layer.back()
			layer.pop_back()
		else:
			_render(fx)

func _recycle(fx: Effect) -> void:
	_style_counts[fx.style] -= 1
	_pool.append(fx)

func _draw() -> void:
	if _flash > 0.0 and _preferences.fx_flash > 0.0:
		var intensity := 0.07 if _preferences.fx_dim else 0.22
		draw_rect(_field, Color(_flash_tint, _flash * intensity * _preferences.fx_flash))

func _render(fx: Effect) -> void:
	var t := fx.elapsed / fx.life
	var fade := (1.0 - t) * (0.56 if _preferences.fx_dim else 1.0)
	var tint := Color(fx.tint, fade)
	var at := fx.origin
	var reach := maxf(12, fx.radius * _cell)
	match fx.style:
		"support_gain", "support_link":
			_beam(at, at.lerp(fx.end, minf(1.0, t * 1.5)), 2.1, tint)
			_ring(fx.end, 16.0 + 16.0 * t, tint)
		"support_lose":
			_ring(at, 25.0 - 18.0 * t, tint)
		"support_impact":
			_glow(at, 20.0 + 10.0 * t, Color(tint, fade * 0.45))
		"support_quantum":
			_zap(at, fx.end, tint, 2.7)
			_beam(at, fx.end, 1.4, Color("#6df3dd", fade * 0.74))
			_ring(fx.end, 11.0 + 27.0 * t, tint)
		"support_sync":
			_ring(at, reach * t, Color(tint, fade * 0.55))
			_ring(at, reach * t * 0.87, Color("#fff5d0", fade * 0.32))
			_hoop(at, 51.0 + t * 35.0, 8, _time * 2.0, tint)
		"mob_grant", "mob_boost":
			_beam(at, fx.end, 3.0, Color(tint, fade * 0.78))
			_ring(fx.end, 16 + 12 * t, tint)
		"mob_shield_break":
			_ring(at, 15.0 + 29.0 * t, tint)
			_hoop(at, 18.0 + 37.0 * t, 6, 0.3 + t * 1.5, tint)
			_spray(at, 55, tint, t, 13)
		"mob_divide":
			for side in 4:
				var direction := Vector2.from_angle(side * PI * 0.5 + PI * 0.25)
				var shard := at + direction * (7.0 + 29.0 * t)
				_hoop(shard, 9.0 * (1.0 - t) + 4.0, 4, side + t, tint)
			_glow(at, 44, tint)
		"mob_boss_spawn", "mob_boss_down", "mob_phase":
			_blast(at, reach * 1.6, tint, t)
			_hoop(at, 36 + t * 82, 6, _time * 1.3, tint)
			_hoop(at, 28 + t * 114, 8, -_time * 0.6, Color(tint, fade * 0.64))
			if fx.style == "mob_boss_down":
				_spray(at, 153, tint, t, 40)
		"mob_regen", "mob_brood":
			_ring(at, 10 + 33 * t, tint)
			_glow(at, 37 + t * 14, Color(tint, fade * 0.58))
		"cataclysm":
			_terminal(fx, t, fade, true)
		"charge_cataclysm":
			_charge(fx, t, true)
		"charge_nova", "charge_doom", "charge_orbit", "charge_blast", "charge_rail":
			_charge(fx, t, false)
		"nova":
			_terminal(fx, t, fade * 0.82, false)
		"singularity", "vortex", "gravity", "collapse_gravity":
			_spiral(fx, reach, t, fade)
		"spectrum", "prism":
			var color := Color.from_hsv(fposmod(fx.end.x * 0.00092 + fx.end.y * 0.0013 + t * 0.15, 1.0), 0.58, 1.0, fade)
			var mid := at.lerp(fx.end, 0.49) + (fx.end - at).normalized().orthogonal() * 49.0
			_beam(at, mid, 6.0, color)
			_beam(mid, fx.end, 5.0, Color(fx.tint.lerp(color, 0.66), fade))
			_ring(fx.end, 9.0 + t * 20.0, color)
		"storm", "arc":
			_zap(at, fx.end, tint, 4.0 if fx.style == "storm" else 2.5)
			_ring(fx.end, 13.0 + t * 26.0, tint)
		"doom":
			var stop := _clip_end(at, fx.end)
			_beam(at, stop, 23.0 + fade * 65.0, tint)
			for i in range(1, 7):
				_ring(at.lerp(stop, i / 7.0), 18.0 + 90.0 * t, tint)
		"orbit":
			_beam(at - Vector2(0, 540), at, 35 + fade * 45, tint)
			_blast(at, reach, tint, t)
		"rail", "sniper", "laser", "photon", "mark", "holo":
			_beam(at, _clip_end(at, fx.end), 8.0 if fx.style == "rail" else 4.0, tint)
			_ring(fx.end, 8.0 + t * 18.0, tint)
			if fx.style == "holo":
				_hoop(at, 26.0 + 8 * t, 6, _time * 4.0, tint)
		"flame":
			_plume(at, fx.end, tint, t)
		"ice":
			_blast(at, reach, tint, t)
			for i in (6 if _preferences.fx_quality > 0 else 3):
				var crystal := at + Vector2.from_angle(i * TAU / 6.0) * reach * (0.25 + t * 0.65)
				_hoop(crystal, 18.0 * (1.0 - t) + 8.0, 4, i + t, tint)
		"plasma":
			_blast(at, reach, tint, t)
			_hoop(at, reach * (0.82 + 0.12 * t), 6, _time * 0.5, Color(tint, fade * 0.58))
		"muzzle":
			_beam(at, at.lerp(fx.end, 0.42), 7.0, tint)
			_glow(at, 37, tint)
		_:
			_blast(at, reach, tint, t)

func _charge(fx: Effect, t: float, terminal: bool) -> void:
	var fade := (0.5 + 0.5 * t) * (0.64 if _preferences.fx_dim else 1.0)
	var tint := Color(fx.tint, fade)
	var center := fx.end
	var size := lerpf(32, 154 if terminal else 83, t)
	_glow(center, size * 2.4, Color(tint, fade * 0.62))
	_ring(center, size * (1.27 - t * 0.30), tint)
	_hoop(center, size, 8 if terminal else 5, _time * 1.4, tint)
	_hoop(center, size * 0.67, 6, -_time * 2.1, Color(tint, fade * 0.68))
	if terminal:
		var pivot := Vector2(clampf(center.x, 270, 1270), 291)
		var lift := pivot + Vector2(0, 38.0 * (1.0 - t))
		_hoop(lift, 220.0 * t + 32.0, 6, _time * 0.52, tint)
		_hoop(lift, 104.0 * t + 20.0, 4, -_time, Color("#fff2bd", fade))
		for i in 5:
			var anchor := lift + Vector2((i - 2) * 112, -76 + absf(i - 2) * 25)
			_beam(anchor, lift, 3 + 7 * t, tint)
			_ring(anchor, 12.0 + 13 * t, tint)
		_beam(lift, center, 3 + 14 * t, Color(tint, fade * t))
	elif fx.style == "charge_rail":
		_ring(fx.origin, 18.0 + t * 20, tint)
		_ring(fx.origin, 31.0 - t * 16, tint)
	elif fx.style == "charge_blast":
		var bullet := fx.origin.lerp(center, t) - Vector2(0, sin(t * PI) * 135.0)
		_glow(bullet, 38, tint)

func _terminal(fx: Effect, t: float, fade: float, great: bool) -> void:
	var tint := Color(fx.tint, fade)
	var at := fx.origin
	var field_size := fx.radius * _cell
	_glow(at, field_size * (0.6 + t), Color(tint, fade * 0.57))
	for i in (5 if great else 3):
		var wave := maxf(0.0, t * 1.28 - i * 0.12)
		if wave > 0.0:
			_ring(at, 20.0 + field_size * wave, Color(fx.tint.lerp(Color("#f0a9ff"), i * 0.14), fade * (1.0 - i * 0.12)))
	if great:
		var above := Vector2(clampf(at.x, 270, 1270), 169)
		_beam(above, at + Vector2(0, 120), 112.0 * fade + 12.0, tint)
		_beam(Vector2(_field.position.x, at.y), Vector2(_field.end.x, at.y), fade * 43.0 + 3.0, Color("#ff8da8", fade * 0.75))
		_hoop(above + Vector2(0, 100), 100 + t * 75, 6, _time * 1.5, tint)
	_spray(at, minf(field_size, 250.0), tint, t, 55 if great else 32)

func _spiral(fx: Effect, reach: float, t: float, fade: float) -> void:
	var tint := Color(fx.tint, fade)
	var radius := minf(reach, 1200.0)
	if fx.style == "collapse_gravity":
		radius *= 0.28 + 0.74 * t
	elif fx.style == "singularity":
		radius *= (0.40 + minf(0.6, t * 3.0))
		tint.a = (0.40 if _preferences.fx_dim else 0.72) * minf(t * 10.0, 1.0)
	else:
		radius *= (0.8 + 0.2 * t)
	_glow(fx.origin, radius * 0.85, Color(tint, tint.a * 0.5))
	_ring(fx.origin, radius, Color(tint, tint.a * 0.72))
	var segments := 6 + int(_preferences.fx_quality) * 3
	for arm in (3 if _preferences.fx_quality > 0 else 2):
		var p := fx.origin
		for i in range(1, segments + 1):
			var ratio := float(i) / segments
			var angle := _time * 2.0 + arm * TAU / 3.0 + ratio * 5.3
			var q := fx.origin + Vector2.from_angle(angle) * radius * ratio
			_line(p, q, 1.0 + (1.0 - ratio) * 4.0, Color(tint, tint.a * (1.0 - ratio * 0.83)))
			p = q

func _blast(at: Vector2, reach: float, tint: Color, t: float) -> void:
	_ring(at, reach * (0.14 + t * 0.86), tint)
	if _preferences.fx_quality > 0:
		_ring(at, reach * (0.08 + 0.64 * t), Color(tint, tint.a * 0.46))
	_glow(at, reach * (0.25 + t * 0.65), Color(tint, tint.a * 0.64))
	_spray(at, minf(165, reach), tint, t, 12)

func _plume(at: Vector2, finish: Vector2, tint: Color, t: float) -> void:
	var axis := finish - at
	for i in range(1, 6):
		var r := i / 6.0
		var center := at + axis * r + axis.normalized().orthogonal() * sin(_time * 22.0 + i) * r * 28
		_glow(center, 27.0 + r * 88.0, Color(tint, tint.a * (1.0 - r * 0.62)))
		_spray(center, 42.0 + r * 40, tint, t, 5)

func _zap(at: Vector2, end: Vector2, tint: Color, width: float) -> void:
	var prior := at
	var normal := at.direction_to(end).orthogonal()
	for i in range(1, 5):
		var point := at.lerp(end, i / 4.0)
		if i < 4:
			point += normal * sin(i * 3.9 + end.y + _time * 70) * 13.0
		_beam(prior, point, width, tint)
		prior = point

func _hoop(center: Vector2, radius: float, sides: int, angle: float, tint: Color) -> void:
	var previous := center + Vector2.from_angle(angle) * radius
	for i in range(1, sides + 1):
		var point := center + Vector2.from_angle(angle + i * TAU / sides) * radius
		_line(previous, point, 2.4, tint)
		previous = point

func _beam(at: Vector2, end: Vector2, width: float, tint: Color) -> void:
	if _preferences.fx_quality > 0:
		_line(at, end, width * 2.6, Color(tint, tint.a * 0.19))
	_line(at, end, width, tint)
	if _preferences.fx_quality > 1 and not _preferences.fx_dim:
		_line(at, end, maxf(1, width * 0.22), Color(tint.lerp(Color.WHITE, 0.67), tint.a * 0.78))

func _line(at: Vector2, end: Vector2, width: float, tint: Color) -> void:
	var heading := end - at
	var length := heading.length()
	if length <= 0.001 or _line_count >= BUDGET:
		return
	_lines.item(_line_count, at.lerp(end, 0.5), heading, tint, width / length)
	_line_count += 1

func _ring(at: Vector2, radius: float, tint: Color) -> void:
	if _ring_count < BUDGET:
		_rings.item(_ring_count, at, Vector2.RIGHT * maxf(1, radius), tint)
		_ring_count += 1

func _glow(at: Vector2, radius: float, tint: Color) -> void:
	if _glow_count < BUDGET:
		_glows.item(_glow_count, at, Vector2.RIGHT * clampf(radius, 1.0, 480.0), tint)
		_glow_count += 1

func _spray(at: Vector2, reach: float, tint: Color, t: float, requested: int) -> void:
	var count := mini(BUDGET - _particle_count, roundi(requested * _preferences.fx_particles * (0.5 + _preferences.fx_quality * 0.25)))
	for i in count:
		var heading := Vector2.from_angle(i * 2.39996 + at.x * 0.18)
		var point := at + heading * reach * (0.23 + (i % 5) * 0.16) * t
		if not _field.grow(35).has_point(point):
			continue
		var length := 4.0 + 11.0 * (1.0 - t)
		_particles.item(_particle_count, point, heading * length, tint, 2.2 / length)
		_particle_count += 1

func _clip_end(start: Vector2, end: Vector2) -> Vector2:
	var d := end - start
	var factor := 1.0
	if d.x != 0.0:
		factor = minf(factor, ((_field.end.x if d.x > 0 else _field.position.x) - start.x) / d.x)
	if d.y != 0.0:
		factor = minf(factor, ((_field.end.y if d.y > 0 else _field.position.y) - start.y) / d.y)
	return start + d * maxf(0, factor)
