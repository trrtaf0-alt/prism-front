class_name BattleCameraFX
extends Node2D

const LENS := preload("res://assets/battle_lens.gdshader")
const MAX_IMPULSES := 6
const ATTACKS := {
	"cataclysm": Vector4(24.0, -0.054, 18.0, 0.63),
	"charge_cataclysm": Vector4(0.0, 0.030, 4.0, 0.52),
	"nova": Vector4(16.0, -0.037, 13.0, 0.46),
	"singularity": Vector4(0.0, 0.025, -16.0, 0.58),
	"collapse_gravity": Vector4(15.0, -0.033, 18.0, 0.49),
	"doom": Vector4(10.0, -0.023, 8.0, 0.30),
	"orbit": Vector4(7.0, -0.013, 6.0, 0.26),
	"pulse": Vector4(6.0, -0.009, 6.0, 0.25),
}
const BOSS_IMPACTS := {
	&"boss_spawn": Vector4(7.0, 0.021, 9.0, 0.42),
	&"phase": Vector4(12.0, 0.028, -11.0, 0.48),
	&"boss_down": Vector4(17.0, -0.034, 13.0, 0.57),
}

class Impulse:
	var point: Vector2
	var age := 0.0
	var settings: Vector4
	var radius: float

var bounds: Rect2
var suspended := false
var _field: FieldView
var _prefs
var _exit: Vector2
var _impulses: Array[Impulse] = []
var _copy := BackBufferCopy.new()
var _lens_rect := ColorRect.new()
var _lens_material := ShaderMaterial.new()
var _lens_center := Vector2.ZERO
var _lens_radius := 0.0
var _lens_strength := 0.0
var _lens_progress := 0.0
var _lens_region := Rect2()

func setup(field: FieldView, preferences: Node) -> void:
	_field = field
	_prefs = preferences
	bounds = Rect2(FieldView.ORIGIN, Vector2(field.battle.field.size) * FieldView.CELL)
	_exit = FieldView.pixel(Vector2(field.battle.field.exit) + Vector2.ONE * 0.5)
	add_child(_copy)
	_lens_material.shader = LENS
	_lens_rect.material = _lens_material
	_lens_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lens_rect)
	_hide_lens()
	field.battle.attack_visual.connect(_attack)
	field.battle.mob_visual.connect(_mob)
	field.battle.base_damaged.connect(_base_damage)

func _attack(style: String, start: Vector2, finish: Vector2, radius: float, _tint: Color, _life: float, _stage: int) -> void:
	if not ATTACKS.has(style):
		return
	var focus := finish
	if style == "doom":
		focus = start.lerp(finish, 0.33)
	trigger(FieldView.pixel(focus), ATTACKS[style], clampf(radius * FieldView.CELL * 0.58, 125.0, 355.0))

func _mob(kind: StringName, start: Vector2, _end: Vector2, _tint: Color, _life: float) -> void:
	if BOSS_IMPACTS.has(kind):
		trigger(FieldView.pixel(start), BOSS_IMPACTS[kind], 250.0)

func _base_damage(amount: int) -> void:
	var weight := clampf(amount / 18.0, 0.3, 1.0)
	trigger(_exit, Vector4(12.0 * weight, -0.021 * weight, 7.0 * weight, 0.31), 155.0)

func trigger(point: Vector2, settings: Vector4, radius: float) -> void:
	if suspended or (_prefs.fx_shake == 0.0 and _prefs.fx_zoom == 0.0 and _prefs.fx_warp == 0.0):
		return
	var pulse := Impulse.new()
	pulse.point = point.clamp(bounds.position, bounds.end)
	pulse.settings = settings
	pulse.radius = radius
	if _impulses.size() >= MAX_IMPULSES:
		_impulses.pop_front()
	_impulses.append(pulse)

func suspend(enabled: bool) -> void:
	suspended = enabled
	if enabled:
		_impulses.clear()
		_field.transform = Transform2D.IDENTITY
		_hide_lens()

func update(delta: float) -> void:
	if suspended:
		return
	if _impulses.is_empty():
		return
	var shake := Vector2.ZERO
	var zoom := 0.0
	var warp_strength := 0.0
	var warp: Impulse
	for i in range(_impulses.size() - 1, -1, -1):
		var pulse := _impulses[i]
		pulse.age += delta
		var t := pulse.age / pulse.settings.w
		if t >= 1.0:
			_impulses.remove_at(i)
			continue
		var envelope := (1.0 - t) * (1.0 - t)
		var phase := pulse.age * 94.0 + pulse.point.x * 0.073
		shake += Vector2(sin(phase), cos(phase * 0.83)) * pulse.settings.x * envelope
		zoom += pulse.settings.y * envelope * (0.68 + 0.32 * minf(1.0, pulse.age / 0.072))
		var strength := pulse.settings.z * (1.0 - t)
		if absf(strength) > absf(warp_strength):
			warp_strength = strength
			warp = pulse
	var zoom_scale := 1.0 + clampf(zoom, -0.066, 0.049) * float(_prefs.fx_zoom)
	var displacement := shake.limit_length(26.0) * float(_prefs.fx_shake)
	_field.transform = Transform2D(0.0, Vector2.ONE * zoom_scale, 0.0, bounds.get_center() * (1.0 - zoom_scale) + displacement)
	if warp != null and _prefs.fx_warp > 0.0 and _prefs.fx_quality > 0 and DisplayServer.get_name() != "headless":
		_show_lens(warp, warp_strength * float(_prefs.fx_warp))
	else:
		_hide_lens()

func _show_lens(warp: Impulse, strength: float) -> void:
	_lens_center = _field.transform * warp.point
	_lens_radius = warp.radius
	_lens_strength = strength
	_lens_progress = warp.age / warp.settings.w
	var diameter := Vector2.ONE * _lens_radius * 2.0
	_lens_region = bounds.intersection(Rect2(_lens_center - diameter * 0.5, diameter))
	# The GL compatibility renderer shows seams with region copies on a stretched canvas.
	_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_lens_rect.position = _lens_region.position
	_lens_rect.size = _lens_region.size
	_lens_material.set_shader_parameter("region_size", _lens_region.size)
	_lens_material.set_shader_parameter("focus", _lens_center - _lens_region.position)
	_lens_material.set_shader_parameter("sample_min", bounds.position - _lens_region.position + Vector2.ONE)
	_lens_material.set_shader_parameter("sample_max", bounds.end - _lens_region.position - Vector2.ONE)
	_lens_material.set_shader_parameter("radius", _lens_radius)
	_lens_material.set_shader_parameter("strength", _lens_strength)
	_lens_material.set_shader_parameter("progress", _lens_progress)
	_lens_rect.show()

func _hide_lens() -> void:
	_copy.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
	_lens_rect.hide()
	_lens_strength = 0.0

func cell_under(point: Vector2) -> Vector2i:
	if FieldView.SCREEN.has_point(point):
		var cell := _field.cell_under(sample_point(point))
		if _field.battle.field.contains(cell):
			return cell
	return Vector2i(-1, -1)

func sample_point(point: Vector2) -> Vector2:
	if _lens_strength == 0.0 or not _lens_region.has_point(point):
		return point
	# Use the same mapping as the shader so pointer input follows the displayed cell.
	var axis := point - _lens_center
	var distance := axis.length()
	var r := distance / maxf(1.0, _lens_radius)
	var taper := smoothstep(0.035, 0.21, r) * (1.0 - smoothstep(0.72, 1.0, r))
	var ring := sin((r - (0.15 + _lens_progress * 0.88)) * 19.0)
	var warped := point + axis / maxf(1.0, distance) * ring * _lens_strength * taper
	return warped.clamp(bounds.position + Vector2.ONE, bounds.end - Vector2.ONE)
