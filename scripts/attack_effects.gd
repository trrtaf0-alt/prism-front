class_name AttackEffects
extends Node2D

const BUDGET := 400
const LIMITS := [13, 30, 55, 88]
const HUGE_LIMIT := 18
const REFRESHABLE := ["vortex", "plasma", "gravity", "spectrum_source", "prism_source", "photon_source", "storm_source"]
const FOLLOWING_BEAMS := ["spectrum", "prism", "photon", "storm", "storm_column"]
const TRACK_CELL := 24.0
const PLATES := preload("res://assets/attack_atlas.png")
const PLATE_LIMIT := 60

class Effect:
	var style: String
	var origin: Vector2
	var end: Vector2
	var radius: float
	var tint: Color
	var elapsed: float
	var life: float
	var tracked := false
	var track_cell: Vector4i

var _ordinary: Array[Effect] = []
var _huge: Array[Effect] = []
var _pool: Array[Effect] = []
var _lines: SpriteBatch
var _rings: SpriteBatch
var _glows: SpriteBatch
var _particles: SpriteBatch
var _plates: SpriteBatch
var _plate_count := 0
var _line_count := 0
var _ring_count := 0
var _glow_count := 0
var _particle_count := 0
var _flash := 0.0
var _flash_tint := Color.WHITE
var _tremor := 0.0
var _time := 0.0
var _style_counts: Dictionary = {}
var _tracked_beams: Dictionary = {}
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
	var plate_material := ShaderMaterial.new()
	plate_material.shader = TowerArt.SHADER
	_plates = SpriteBatch.new(PLATES, 1.0, plate_material)
	_lines = SpriteBatch.new(beam_texture, 1.0, null)
	_rings = SpriteBatch.new(beam_texture, 2.0, null, _annulus())
	_glows = SpriteBatch.new(glow, 2.0, null)
	_particles = SpriteBatch.new(dot, 1.0, null)
	for batch: SpriteBatch in [_glows, _plates, _rings, _lines, _particles]:
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
				prior.elapsed = minf(prior.elapsed * 0.45, life * 0.19)
				prior.radius = radius
				return
	var tracked := style in FOLLOWING_BEAMS
	var key := Vector4i()
	if tracked:
		var a := Vector2i((from / TRACK_CELL).round())
		var b := Vector2i((to / TRACK_CELL).round())
		key = Vector4i(a.x, a.y, b.x, b.y)
		if _tracked_beams.has(style):
			var previous: Effect = _tracked_beams[style].get(key)
			if previous != null:
				previous.origin = from
				previous.end = to
				previous.elapsed = minf(previous.elapsed, previous.life * 0.24)
				return
	var style_limit := 33 if style == "spectrum" else 28
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
	rule.tracked = tracked
	rule.track_cell = key
	if tracked:
		if not _tracked_beams.has(style):
			_tracked_beams[style] = {}
		_tracked_beams[style][key] = rule
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
	if not _ordinary.is_empty() or not _huge.is_empty() or _line_count + _ring_count + _glow_count + _particle_count + _plate_count > 0:
		_line_count = 0
		_ring_count = 0
		_glow_count = 0
		_particle_count = 0
		_plate_count = 0
		_plates.begin(PLATE_LIMIT)
		for batch: SpriteBatch in [_lines, _rings, _glows, _particles]:
			batch.begin(BUDGET)
		_step_layer(_huge, delta)
		_step_layer(_ordinary, delta)
		_lines.finish(_line_count)
		_rings.finish(_ring_count)
		_glows.finish(_glow_count)
		_particles.finish(_particle_count)
		_plates.finish(_plate_count)
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
	if fx.tracked:
		_tracked_beams[fx.style].erase(fx.track_cell)
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
		"spectrum_source", "prism_source", "photon_source", "storm_source":
			_emitter(fx, tint, t)
		"spectrum", "prism", "photon":
			_optics(fx, tint, t)
		"storm_column":
			_storm_column(fx, tint, t)
		"storm", "arc":
			_zap(at, fx.end, tint, 3.2 if fx.style == "storm" else 2.5)
			_ring(fx.end, 13.0 + t * 21.0, tint)
		"singularity_feed":
			_inflow(at, fx.end, tint, t)
		"pulse":
			_pulse(at, reach, tint, t)
		"doom":
			_doom(fx, tint, t)
		"orbit":
			if t < 0.63:
				var fall := Color(tint, fade * (1.0 - t))
				_beam(at - Vector2(0, 540), at, 27 + fade * 39, fall)
				_line(at - Vector2(17, 440), at - Vector2(3, 6), 4.0, fall)
				_line(at + Vector2(17, -440), at + Vector2(3, -6), 4.0, fall)
			_stamp(3, at, minf(reach * 1.24, 365.0), -t * 0.6, fade * 0.86)
			_blast(at, reach, tint, t)
		"rail", "sniper", "laser", "mark", "holo":
			_precision(fx, tint, t)
		"flame":
			_plume(at, fx.end, tint, t)
		"ice":
			_blast(at, reach, tint, t)
			_stamp(5, at, minf(410.0, reach * 1.5), 0.15, fade)
			for i in (6 if _preferences.fx_quality > 0 else 3):
				var crystal := at + Vector2.from_angle(i * TAU / 6.0) * reach * (0.25 + t * 0.65)
				_hoop(crystal, 18.0 * (1.0 - t) + 8.0, 4, i + t, tint)
		"blast":
			_stamp(12, at, minf(reach * (0.6 + t * 0.9), 320.0), t * 0.38, fade * 0.67)
			_blast(at, reach, tint, t)
		"plasma":
			_blast(at, reach, tint, t)
			_stamp(4, at, minf(630.0, reach * 1.4), 0.0, fade * 0.80)
			_hoop(at, reach * (0.82 + 0.12 * t), 6, _time * 0.5, Color(tint, fade * 0.58))
		"split":
			_stamp(12, at, 95.0 + t * 110.0, t * 0.8, fade)
			_blast(at, reach, tint, t)
		"muzzle", "missile_launch", "phase_launch", "cryogenic_launch", "scatter_launch":
			_launch(fx, tint, t)
		_:
			_blast(at, reach, tint, t)

func _stamp(frame: int, at: Vector2, diameter: float, angle: float, opacity: float) -> void:
	if _preferences.fx_quality < 2 or _plate_count >= PLATE_LIMIT:
		return
	_plates.item(_plate_count, at, Vector2.from_angle(angle) * diameter, Color(TowerArt.batch_color(frame), clampf(opacity, 0.0, 1.0)))
	_plate_count += 1

func _emitter(fx: Effect, tint: Color, t: float) -> void:
	var frame := 9
	match fx.style:
		"prism_source": frame = 10
		"photon_source": frame = 11
		"storm_source": frame = 8
	var angle := _time * (-1.35 if frame == 8 else 0.92)
	_stamp(frame, fx.origin, 110.0 + 50.0 * t, angle, tint.a)
	_glow(fx.origin, 48.0 + t * 34.0, Color(tint, tint.a * 0.75))
	_ring(fx.origin, 25.0 + 18.0 * t, Color(tint, tint.a * 0.75))

func _optics(fx: Effect, tint: Color, t: float) -> void:
	var at := fx.origin
	var end := fx.end
	var axis := at.direction_to(end)
	if fx.style == "photon":
		var trail := at.lerp(end, maxf(0.0, t * 1.7 - 0.6))
		_beam(trail, end, 5.5 * (1.0 - t * 0.5), tint)
		if _preferences.fx_quality >= 2:
			var front := at.lerp(end, minf(1.0, t * 1.8))
			var side := axis.orthogonal() * 7.0
			_line(front - axis * 24.0 + side, front + side, 2.0, Color(tint, tint.a * 0.68))
		_glow(end, 35.0 + 22.0 * t, Color(tint, tint.a * 0.56))
		return
	var spectral := fx.style == "spectrum"
	var hue := fposmod(end.x * 0.00092 + end.y * 0.0013, 1.0)
	var color := Color.from_hsv(hue, 0.52, 1.0, tint.a) if spectral else tint
	var mid := at.lerp(end, 0.44) + axis.orthogonal() * (sin(end.x * 0.04 + end.y) * 0.38 + 0.5) * (61.0 if spectral else 34.0)
	_beam(at, mid, 6.3 if spectral else 3.4, Color(color, tint.a * 0.83))
	_beam(mid, end, 4.6 if spectral else 3.4, Color(fx.tint.lerp(color, 0.84), tint.a))
	if spectral and _preferences.fx_quality >= 2:
		var facet := mid + axis.orthogonal() * (18.0 + t * 37.0)
		var complement := Color.from_hsv(fposmod(hue + 0.27, 1.0), 0.55, 1.0, tint.a * 0.45)
		_line(at, facet, 2.3, complement)
		_line(facet, end, 2.0, complement)
	_ring(end, 7.0 + t * 22.0, color)
	_glow(mid.lerp(end, t), 18.0, Color(color, tint.a * 0.58))

func _storm_column(fx: Effect, tint: Color, t: float) -> void:
	var end := fx.end
	if t < 0.59:
		var primary := Color(tint, tint.a * (1.0 - t * 0.98))
		_zap(fx.origin, end, primary, 6.5 - 4.0 * t)
		var split := fx.origin.lerp(end, 0.58) + Vector2(28.0, 8.0)
		_line(split, end + Vector2(15.0, -17.0), 2.6, Color("#d0f2ff", tint.a * 0.50))
	_glow(end, 52.0 + t * 36.0, Color(tint, tint.a * 0.67))
	_stamp(8, end, 67.0 + t * 108.0, 0.72, tint.a * 0.78)
	_ring(end, 17.0 + 44.0 * t, tint)
	_spray(end, 52.0, tint, t, 7)

func _inflow(at: Vector2, end: Vector2, tint: Color, t: float) -> void:
	var side := at.direction_to(end).orthogonal()
	for i in (3 if _preferences.fx_quality >= 2 else 1):
		var bend := at.lerp(end, 0.55) + side * (float(i) - 1.0) * 93.0
		_line(at, bend, 4.0 - t * 2.5, Color(tint, tint.a * 0.71))
		_line(bend, end, 4.0 - t * 3.0, tint)
	_glow(end, 70.0 + t * 38.0, tint)

func _pulse(at: Vector2, reach: float, tint: Color, t: float) -> void:
	var front := maxf(5.0, reach * t)
	_ring(at, front, tint)
	_ring(at, front * 0.78, Color(tint, tint.a * 0.51))
	_glow(at, minf(reach * 0.28, 220.0) * (0.45 + t), Color(tint, tint.a * 0.45))
	_stamp(7, at, minf(reach * 2.0, 830.0) * t, _time * 0.32, tint.a)
	if _preferences.fx_quality >= 2:
		for i in 10:
			var ray := Vector2.from_angle(i * TAU / 10.0 + _time * 0.34)
			var center := at + ray * front * 0.95
			if _field.grow(34.0).has_point(center):
				_line(center - ray * 17.0, center + ray * 9.0, 2.4, tint)

func _doom(fx: Effect, tint: Color, t: float) -> void:
	var at := fx.origin
	var stop := _clip_end(at, fx.end)
	var axis := at.direction_to(stop)
	var side := axis.orthogonal()
	var collapse := 1.0 - smoothstep(0.16, 0.96, t)
	_beam(at, stop, 12.0 + 64.0 * collapse, tint)
	for i: int in [-1, 1]:
		var offset := side * i * (17.0 + 26.0 * collapse)
		_line(at + offset, stop + offset, 3.4, Color("#ffc3d0", tint.a * 0.58))
	_stamp(13, at, 143.0 + t * 44.0, axis.angle(), tint.a)
	for i in range(1, 6):
		var point := at.lerp(stop, i / 6.0)
		var local := maxf(0.0, t * 1.6 - i * 0.06)
		_ring(point, 8.0 + 79.0 * local, Color(tint, tint.a * 0.73))
		_glow(point, 43.0 + 80.0 * local, Color(tint, tint.a * 0.45))

func _precision(fx: Effect, tint: Color, t: float) -> void:
	var at := fx.origin
	var end := _clip_end(at, fx.end)
	var axis := at.direction_to(end)
	match fx.style:
		"rail":
			_beam(at, end, 8.5, tint)
			for i: int in [-1, 1]:
				var delta := axis.orthogonal() * i * (6.0 + 11.0 * t)
				_line(at + delta, end + delta, 2.1, Color(tint, tint.a * 0.64))
			_ring(at, 13.0 + 32.0 * t, tint)
		"sniper":
			_beam(at, end, 3.1, tint)
			_glow(end, 28, tint)
		"laser":
			_beam(at, end, 5.5, tint)
			_glow(at.lerp(end, t), 30.0, Color(tint, tint.a * 0.72))
		"mark":
			_hoop(end, 16.0 + 11.0 * t, 4, _time * 1.6, tint)
			_line(at, end, 1.7, Color(tint, tint.a * 0.65))
		"holo":
			_beam(at, end, 3.4, tint)
			_stamp(10, at, 74.0 + t * 72.0, _time, tint.a)
	_ring(end, 6.5 + t * 16.0, tint)

func _launch(fx: Effect, tint: Color, t: float) -> void:
	var at := fx.origin
	var axis := at.direction_to(fx.end)
	var side := axis.orthogonal()
	match fx.style:
		"scatter_launch":
			for i in [-2, -1, 0, 1, 2]:
				var ray := axis.rotated(deg_to_rad(fx.radius) * i * 0.22)
				_line(at + ray * 8.0, at + ray * (23.0 + 34.0 * t), 3.1, tint)
		"missile_launch":
			for i: int in [-1, 1]:
				var offset := side * (7.0 + t * 9.0) * i
				_beam(at + offset - axis * 19.0, at + offset + axis * (16.0 + t * 24.0), 4.0, tint)
		"cryogenic_launch":
			_stamp(5, at + axis * 15.0 * t, 42.0 + 34.0 * t, axis.angle(), tint.a * 0.72)
			_beam(at, at + axis * 26.0, 5.0, tint)
		"phase_launch":
			_ring(at + axis * (12.0 + t * 26.0), 8.0 + t * 14.0, tint)
			_beam(at, at + axis * 29.0, 5.0, tint)
		_:
			_beam(at, at.lerp(fx.end, 0.42), 7.0, tint)
	_glow(at, 38.0 + 12.0 * t, tint)

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
		var pivot := _sky_anchor(center)
		var lift := pivot + Vector2(0, 38.0 * (1.0 - t))
		_stamp(3, lift, 182.0 + t * 380.0, _time * 0.23, fade)
		_stamp(3, center, 125.0 + t * 166.0, -_time * 0.65, fade * 0.78)
		_hoop(lift, 220.0 * t + 32.0, 6, _time * 0.52, tint)
		_hoop(lift, 104.0 * t + 20.0, 4, -_time, Color("#fff2bd", fade))
		for i in 5:
			var anchor := lift + Vector2((i - 2) * 112, -76 + absf(i - 2) * 25)
			_beam(anchor, lift, 3 + 7 * t, tint)
			_ring(anchor, 12.0 + 13 * t, tint)
		_beam(lift, center, 3 + 14 * t, Color(tint, fade * t))
	elif fx.style == "charge_nova":
		_stamp(2, center, 96.0 + 220.0 * t, _time * 0.31, fade)
		_glow(center, 42.0 + 73.0 * t, Color("#fff6c6", fade * 0.7))
	elif fx.style == "charge_rail":
		_ring(fx.origin, 18.0 + t * 20, tint)
		_ring(fx.origin, 31.0 - t * 16, tint)
	elif fx.style == "charge_blast":
		var bullet := fx.origin.lerp(center, t) - Vector2(0, sin(t * PI) * 135.0)
		_glow(bullet, 38, tint)

func _sky_anchor(center: Vector2) -> Vector2:
	return Vector2(clampf(center.x, _field.position.x + 235.0, _field.end.x - 235.0), _field.position.y + 212.0)

func _terminal(fx: Effect, t: float, fade: float, great: bool) -> void:
	var tint := Color(fx.tint, fade)
	var at := fx.origin
	var field_size := fx.radius * _cell
	_glow(at, field_size * (0.47 + t * 0.68), Color(tint, fade * 0.63))
	var spread := ease(t, 0.38)
	_stamp(3 if great else 2, at, (270.0 if great else 207.0) + spread * (566.0 if great else 410.0), _time * 0.16, fade)
	if t < 0.42:
		_glow(at, (180.0 if great else 95.0) + t * 110.0, Color("#fff0bf", fade * 0.97))
	for i in (5 if great else 3):
		var wave := maxf(0.0, t * 1.28 - i * 0.12)
		if wave > 0.0:
			_ring(at, 20.0 + field_size * wave, Color(fx.tint.lerp(Color("#f0a9ff"), i * 0.14), fade * (1.0 - i * 0.12)))
	if great:
		var above := _sky_anchor(at)
		var burn := 1.0 - smoothstep(0.08, 0.54, t)
		_stamp(3, above, 420.0 + t * 196.0, -_time * 0.38, fade * 0.84)
		if burn > 0.0:
			for i: int in [-1, 1]:
				var wing := above + Vector2(175.0 * i, -57.0 + t * 50.0)
				_beam(wing, at, 22.0 * burn, Color(tint, fade * burn * 0.64))
			_beam(above, at + Vector2(0, 102.0), 110.0 * burn + 12.0, Color(tint, fade * burn))
		_beam(Vector2(_field.position.x, at.y), Vector2(_field.end.x, at.y), fade * 39.0 + 3.0, Color("#ffb180", fade * 0.63))
		_hoop(above + Vector2(0, 100), 100 + t * 75, 6, _time * 1.5, tint)
	if _preferences.fx_quality >= 2:
		for i in 8:
			var ray := Vector2.from_angle(TAU * i / 8.0 + 0.28)
			var point := at + ray * field_size * spread * (0.16 + (i % 3) * 0.12)
			if _field.grow(40.0).has_point(point):
				_line(point - ray * 52.0, point + ray * 22.0, 2.7, Color(tint, fade * 0.67))
	_spray(at, minf(field_size, 340.0), tint, t, 64 if great else 44)

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
	if fx.style == "singularity":
		var scale := minf(radius * 0.72, 650.0)
		var unwind := smoothstep(0.72, 1.0, t)
		_stamp(1, fx.origin, scale * (1.0 - 0.49 * unwind), -_time * 0.73, tint.a * (1.22 - 0.3 * unwind))
		_stamp(6, fx.origin, minf(radius * 1.35, 800.0), _time * 0.24, tint.a * 0.56)
		_glow(fx.origin, 120.0 + 50.0 * sin(t * PI), Color("#bd9aff", tint.a * 0.82))
	elif fx.style == "collapse_gravity":
		_stamp(1, fx.origin, 150.0 + t * 630.0, -t * 1.9, tint.a)
		_stamp(12, fx.origin, 66.0 + t * 340.0, t, tint.a * 0.82)
	else:
		var frame := 0 if fx.style == "vortex" else 6
		_stamp(frame, fx.origin, minf(radius * 1.3, 670.0), _time * (0.6 if frame == 0 else -0.31), tint.a)
	_glow(fx.origin, radius * 0.85, Color(tint, tint.a * 0.5))
	_ring(fx.origin, radius, Color(tint, tint.a * 0.72))
	if _preferences.fx_quality >= 2 and fx.style != "collapse_gravity":
		_vortex_embers(fx.origin, minf(radius, 595.0), tint, fx.style != "vortex")
	var segments := 5 + int(_preferences.fx_quality) * 2
	for arm in (3 if _preferences.fx_quality > 0 else 2):
		var p := fx.origin
		for i in range(1, segments + 1):
			var ratio := float(i) / segments
			var angle := _time * 2.0 + arm * TAU / 3.0 + ratio * 5.3
			var q := fx.origin + Vector2.from_angle(angle) * radius * ratio
			_line(p, q, 1.0 + (1.0 - ratio) * 4.0, Color(tint, tint.a * (1.0 - ratio * 0.83)))
			p = q

func _vortex_embers(at: Vector2, radius: float, tint: Color, inward: bool) -> void:
	var count := mini(BUDGET - _particle_count, roundi(21.0 * float(_preferences.fx_particles)))
	for i in count:
		var phase := fposmod(float(i) * 0.235 + _time * 0.43, 1.0)
		var travel := 1.0 - phase if inward else phase
		var angle := i * 2.39996 + travel * 3.5 - _time * 1.6
		var axis := Vector2.from_angle(angle)
		var point := at + axis * radius * (0.12 + travel * 0.76)
		if not _field.grow(35.0).has_point(point):
			continue
		var envelope := sin(phase * PI)
		var color := Color(tint.lerp(Color("#d7d4ff"), 0.42), tint.a * envelope * 0.83)
		var length := 4.0 + envelope * (19.0 if inward else 15.0)
		_particles.item(_particle_count, point, axis.orthogonal() * length, color, 2.1 / length)
		_particle_count += 1

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
		if r < 0.7:
			_line(center - axis * 0.065, center + axis * 0.078, 7.0 + r * 14.0, Color("#ffb773", tint.a * (0.55 - r * 0.25)))
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
