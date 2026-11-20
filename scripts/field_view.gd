class_name FieldView
extends Node2D

const CELL := 52.0
const ORIGIN := Vector2(34, 68)
const MINT := Color("#50f6ed")
const PINK := Color("#ff467d")
const GOLD := Color("#ffc879")
const MAX_EFFECTS := 160
const BOLT_TEXTURE := preload("res://assets/bolt.png")
const SHOCKWAVE := preload("res://assets/shockwave.png")
const NEON_SHADER := preload("res://assets/neon.gdshader")

class Flare:
	var point: Vector2
	var direction: Vector2
	var kind: StringName
	var age := 0.0
	var duration: float
	var color: Color

var battle: Battle
var hovered := Vector2i(-1, -1)
var selected := Vector2i(-1, -1)
var building := false
var build_id := TowerRegistry.BASE
var advanced_fx := AttackEffects.new()
var support_fx := SupportView.new()
var _preferences
var frozen := false
var elapsed := 0.0
var _flares: Array[Flare] = []
var _available: Array[Flare] = []
var _glow: ImageTexture
var _turret_color: Color
var _drone_color: Color
var _tower_material: ShaderMaterial
var _tower_halos: SpriteBatch
var _dim_towers := false
var _bases: SpriteBatch
var _heads: SpriteBatch
var _mobs := MobView.new()
var _bolts: SpriteBatch
var _overlay: Node2D
var _sparks: SpriteBatch
var _rings: SpriteBatch
var _effect_glows: SpriteBatch
var _aim_cell := Vector2i(-1, -1)
var _aim_tower := ""
var _aim_lines := PackedVector2Array()
var _aim_length := 0.0

func _ready() -> void:
	_preferences = get_tree().root.get_node("Profile")
	var floor_canvas := Node2D.new()
	floor_canvas.show_behind_parent = true
	add_child(floor_canvas)
	floor_canvas.draw.connect(_draw_floor.bind(floor_canvas))
	_glow = make_glow()
	_turret_color = Color(battle.data.turret.color)
	_drone_color = Color(battle.data.drone.color)
	var material_mask := ShaderMaterial.new()
	material_mask.shader = NEON_SHADER
	_tower_material = ShaderMaterial.new()
	_tower_material.shader = TowerArt.SHADER
	_tower_material.set_shader_parameter("emission", 0.68)
	var emission_material := CanvasItemMaterial.new()
	emission_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_tower_halos = SpriteBatch.new(_glow, 2.0, emission_material)
	add_child(_tower_halos)
	_bases = SpriteBatch.new(TowerArt.ATLAS, CELL, _tower_material)
	_heads = SpriteBatch.new(TowerArt.ATLAS, CELL, _tower_material)
	_bolts = SpriteBatch.new(BOLT_TEXTURE, 55.0, material_mask)
	add_child(_bases)
	add_child(_heads)
	_mobs.setup(material_mask, CELL)
	add_child(_mobs)
	add_child(_bolts)
	_overlay = Node2D.new()
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)
	var white := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	_effect_glows = SpriteBatch.new(_glow, 2.0, emission_material)
	_rings = SpriteBatch.new(SHOCKWAVE, 2.0, null)
	var dot := ImageTexture.create_from_image(white)
	_sparks = SpriteBatch.new(dot, 1.0, null)
	for batch: SpriteBatch in [_effect_glows, _rings, _sparks]:
		add_child(batch)
	var bounds := Rect2(ORIGIN, Vector2(battle.field.size) * CELL)
	advanced_fx.setup(_glow, _preferences, get_tree().root.get_node("Sound"), bounds, CELL)
	support_fx.setup(self, battle, _preferences)
	add_child(support_fx)
	add_child(advanced_fx)
	battle.support_visual.connect(_support_effect)
	battle.attack_visual.connect(advanced_fx.capture)
	battle.mob_visual.connect(advanced_fx.capture_mob)
	battle.effect.connect(impact)

static func make_glow() -> ImageTexture:
	var image := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var r := Vector2(x - 31.5, y - 31.5).length() / 31.5
			image.set_pixel(x, y, Color(1, 1, 1, pow(maxf(0.0, 1.0 - r), 2.7)))
	return ImageTexture.create_from_image(image)

static func pixel(point: Vector2) -> Vector2:
	return ORIGIN + point * CELL

func cell_under(point: Vector2) -> Vector2i:
	return Vector2i(((point - position - ORIGIN) / CELL).floor())

func _draw_floor(canvas: Node2D) -> void:
	var map := battle.field
	var extent := Vector2(map.size) * CELL
	var bounds := Rect2(ORIGIN, extent)
	canvas.draw_rect(bounds.grow(12), Color("#090c10"))
	canvas.draw_rect(bounds, Color("#0c1016"))
	for y in map.size.y:
		for x in range(y % 2, map.size.x, 2):
			var tile_origin := ORIGIN + Vector2(x, y) * CELL
			canvas.draw_rect(Rect2(tile_origin, Vector2.ONE * CELL), Color("#10151c"))
	canvas.draw_texture_rect(_glow, bounds, false, Color("#242d3a"))
	for y in map.size.y:
		for x in map.size.x:
			if map.tile_at(Vector2i(x, y)) != "#":
				continue
			var at := ORIGIN + Vector2(x, y) * CELL
			var plate := Rect2(at + Vector2(4, 4), Vector2.ONE * (CELL - 8.0))
			canvas.draw_rect(plate, Color("#0a0e14"))
			canvas.draw_rect(plate, Color("#26313a"), false, 1.0)
			canvas.draw_line(plate.position + Vector2(1, 1), plate.position + Vector2(16, 1), Color("#40515a"), 1.5)
	var track := PackedVector2Array()
	for point in map.path:
		track.append(pixel(point))
	canvas.draw_polyline(track, Color("#080d12"), 20.0, true)
	canvas.draw_polyline(track, Color("#1c2630"), 16.0, true)
	canvas.draw_polyline(track, Color("#2d3d48"), 1.3, true)
	for i in range(1, track.size() - 1):
		var direction := track[i + 1] - track[i]
		if i % 5 != 0 and direction == track[i] - track[i - 1]:
			continue
		var at := track[i]
		var forward := direction.normalized()
		var side := forward.orthogonal()
		canvas.draw_polyline(PackedVector2Array([at - forward * 4 + side * 4, at + forward * 3, at - forward * 4 - side * 4]), Color("#526772"), 1.2, true)
	canvas.draw_rect(bounds, Color("#3d4140"), false, 1.0)
	for corner: Vector2 in [Vector2.ZERO, Vector2(extent.x, 0), Vector2(0, extent.y), extent]:
		var at := ORIGIN + corner
		var inward := Vector2(1 if corner.x == 0 else -1, 1 if corner.y == 0 else -1)
		var brass := Color("#82735e")
		canvas.draw_line(at, at + Vector2(22 * inward.x, 0), brass, 2.0)
		canvas.draw_line(at, at + Vector2(0, 22 * inward.y), brass, 2.0)

func impact(kind: StringName, point: Vector2, direction: Vector2) -> void:
	var critical := kind in [&"base", &"collapse", &"install", &"sell"]
	var limit := mini(MAX_EFFECTS, 70 + 45 * _preferences.fx_quality)
	if _flares.size() >= limit:
		if not critical:
			return
		_available.append(_flares.pop_front())
	var flare: Flare = Flare.new() if _available.is_empty() else _available.pop_back()
	flare.kind = kind
	flare.point = pixel(point)
	flare.direction = direction
	flare.age = 0.0
	flare.duration = 0.30
	flare.color = _turret_color
	match kind:
		&"fire":
			flare.duration = 0.11
		&"miss":
			flare.duration = 0.15
		&"spawn", &"hit", &"kill", &"base", &"collapse":
			flare.color = _drone_color
		&"sell":
			flare.color = GOLD
	if kind == &"collapse":
		flare.duration = 0.92
	_flares.append(flare)

func _process(delta: float) -> void:
	if frozen:
		return
	elapsed += delta
	var i := _flares.size() - 1
	while i >= 0:
		var flare := _flares[i]
		flare.age += delta
		if flare.age >= flare.duration:
			_available.append(flare)
			_flares[i] = _flares.back()
			_flares.pop_back()
		i -= 1
	_update_batches()
	_update_flares()
	position = advanced_fx.update(delta)
	queue_redraw()
	_overlay.queue_redraw()
	support_fx.queue_redraw()

func _update_batches() -> void:
	var dim: bool = _preferences.fx_dim
	if _dim_towers != dim:
		_dim_towers = dim
		_tower_material.set_shader_parameter("emission", 0.29 if dim else 0.68)
	var halos: bool = _preferences.fx_quality > 0
	var glow_strength := 0.46 if dim else 1.0
	_tower_halos.begin(battle.towers.size() if halos else 0)
	_bases.begin(battle.towers.size())
	_heads.begin(battle.towers.size())
	for i in battle.towers.size():
		var tower := battle.towers[i]
		var at := pixel(tower.position)
		var id: String = tower.definition.id
		var aim := Vector2.from_angle(tower.angle + TowerArt.rotation_offset(id, elapsed))
		var scale := TowerArt.size_for_stage(int(tower.definition.stage))
		var frame := TowerArt.first_frame(id)
		var weight := float(tower.definition.stage)
		var recoil := tower.recoil / 0.12
		var breath := 0.91 + 0.09 * sin(elapsed * 2.8 + i * 0.79)
		var lit_base := TowerArt.batch_color(frame)
		lit_base.g = 0.43 * breath
		var lit_head := TowerArt.batch_color(frame + 1)
		lit_head.g = lerpf(0.65 + 0.045 * weight, 1.0, recoil) * breath
		_bases.item(i, at, Vector2.RIGHT * scale, lit_base)
		_heads.item(i, at - aim * (tower.recoil * 31.0), aim * scale, lit_head)
		if halos:
			var radius := 31.0 + weight * 8.0 + recoil * 11.0
			var power := (0.34 + 0.041 * weight + 0.26 * recoil) * breath * glow_strength
			_tower_halos.item(i, at, Vector2.RIGHT * radius, Color(tower.definition.tint, power))
	_tower_halos.finish()
	_bases.finish()
	_heads.finish()
	_mobs.submit(battle, ORIGIN, _preferences.fx_dim)
	var traces := 0
	var detail: bool = _preferences.fx_quality >= 2
	_bolts.begin(battle.bolts.size() + (mini(80, battle.bolts.size()) if detail else 0))
	for i in battle.bolts.size():
		var bolt := battle.bolts[i]
		_bolts.item(i, pixel(bolt.position), bolt.direction * (0.68 if bolt.fragment else 1.0), bolt.definition.tint)
		if detail and traces < 80 and not bolt.fragment and (bolt.definition.guided or bolt.definition.returning):
			var stretch := 1.58 if bolt.definition.guided else 1.30
			var back := pixel(bolt.position) - bolt.direction * (34.0 if bolt.definition.guided else 22.0)
			_bolts.item(battle.bolts.size() + traces, back, bolt.direction * stretch, Color(bolt.definition.tint, 0.54), 0.62)
			traces += 1
	_bolts.finish(battle.bolts.size() + traces)

func path_in_range(cell: Vector2i, def: Dictionary) -> float:
	var range_key := "%s:%s" % [def.id, def.range]
	if cell == _aim_cell and range_key == _aim_tower:
		return _aim_length
	_aim_cell = cell
	_aim_tower = range_key
	_aim_lines.clear()
	_aim_length = 0.0
	var center := Vector2(cell) + Vector2(0.5, 0.5)
	var path := battle.field.path
	var radius_sq := float(def.range) * float(def.range)
	for i in path.size() - 1:
		var from := path[i]
		var step := path[i + 1] - from
		var projection := (center - from).dot(step)
		var distance_sq := center.distance_squared_to(from + step * projection)
		var offset := sqrt(maxf(0.0, radius_sq - distance_sq))
		var enter := 0.0 if def.global else maxf(0.0, projection - offset)
		var leave := 1.0 if def.global else minf(1.0, projection + offset)
		if leave > enter:
			_aim_lines.append(pixel(from + step * enter))
			_aim_lines.append(pixel(from + step * leave))
			_aim_length += leave - enter
	return _aim_length

func _draw() -> void:
	var map := battle.field
	if building:
		var extent := Vector2(map.size) * CELL
		var grid := Color("#46535860")
		for x in range(1, map.size.x):
			var top := ORIGIN + Vector2(x * CELL, 0)
			draw_line(top, top + Vector2(0, extent.y), grid)
		for y in range(1, map.size.y):
			var left := ORIGIN + Vector2(0, y * CELL)
			draw_line(left, left + Vector2(extent.x, 0), grid)
	_draw_portals()
	var focus := selected if map.contains(selected) else (hovered if building and battle.can_install(hovered, build_id) else Vector2i(-1, -1))
	if map.contains(focus):
		var at := pixel(Vector2(focus) + Vector2(0.5, 0.5))
		var turret = battle.occupied.get(focus)
		var def: Dictionary = turret.effective if turret != null else battle.data.towers.lookup(build_id)
		if turret != null and turret.range_multiplier > 1.0:
			draw_arc(at, float(turret.definition.range) * CELL, 0, TAU, 96, Color("#82948082"), 1.2, true)
		var tint: Color = def.tint
		if def.global:
			var area := Rect2(ORIGIN, Vector2(battle.field.size) * CELL).grow(-2.0)
			draw_rect(area, Color(tint, 0.075))
			draw_rect(area, Color(tint, 0.78), false, 2.3)
		else:
			var radius := float(def.range) * CELL
			draw_circle(at, radius, Color(tint, 0.075), true, -1.0, true)
			draw_arc(at, radius, 0, TAU, 96, Color(tint, 0.6), 1.6, true)
		if def.support == TowerSupport.Kind.NONE:
			path_in_range(focus, def)
		if def.support == TowerSupport.Kind.NONE and not _aim_lines.is_empty():
			draw_multiline(_aim_lines, Color(tint, 0.34), 15.0, true)
			draw_multiline(_aim_lines, Color(tint, 0.95), 4.0, true)
	if map.contains(hovered) and not battle.lost:
		var at := pixel(Vector2(hovered))
		var color := MINT if not building or battle.can_install(hovered, build_id) else PINK
		var tile := Rect2(at + Vector2(2, 2), Vector2.ONE * (CELL - 4.0))
		draw_rect(tile, Color(color, 0.12))
		draw_rect(tile, Color(color, 0.76), false, 1.5)
		if building and focus == hovered and not battle.occupied.has(hovered):
			var art_size := CELL * TowerArt.size_for_stage(int(battle.data.towers.lookup(build_id).stage))
			var silhouette := Rect2(tile.get_center() - Vector2.ONE * art_size * 0.5, Vector2.ONE * art_size)
			var frame := TowerArt.first_frame(build_id)
			draw_texture_rect(TowerArt.icon(frame), silhouette, false, Color(1, 1, 1, 0.72))
			draw_texture_rect(TowerArt.icon(frame + 1), silhouette, false, Color(1, 1, 1, 0.84))
	if battle.occupied.has(selected):
		draw_arc(pixel(battle.occupied[selected].position), 21.0, 0, TAU, 32, battle.occupied[selected].definition.tint, 2.0, true)

func _support_effect(event: StringName, kind: int, start: Vector2, finish: Vector2) -> void:
	if _preferences.fx_quality == 0:
		return
	var life := 0.38
	var radius := 0.55
	match event:
		&"sync":
			life = 1.5
			radius = battle.field_diagonal
		&"quantum":
			life = 0.32
			var receiver: Battle.Turret = battle.occupied.get(Vector2i(start.floor()))
			if receiver != null and receiver.buffs.has(kind):
				var provider: Battle.Turret = receiver.buffs[kind]
				advanced_fx.capture("support_link", provider.position, start, 0.35, SupportView.AQUA, life, 0)
		&"impact":
			life = 0.16
	advanced_fx.capture("support_" + str(event), start, finish, radius, SupportView.COLORS[kind], life, 0)

func _draw_overlay() -> void:
	for tower in battle.towers:
		var stage := int(tower.definition.stage)
		if stage < 3:
			continue
		var at := pixel(tower.position)
		var tint: Color = tower.definition.tint
		var radius := CELL * (0.55 + 0.052 * stage)
		var hit := tower.recoil / 0.12
		var windup := float(tower.definition.windup)
		var fired_ago := float(tower.definition.interval) - tower.cooldown
		var charge := fired_ago / windup if windup > 0.0 and tower.cooldown > 0.0 and fired_ago < windup else 0.0
		var brightness := 0.52 if _preferences.fx_dim else 1.0
		if hit > 0.0:
			_overlay.draw_arc(at, radius + 9.0 * (1.0 - hit), tower.angle - 0.95, tower.angle + 0.95, 16, Color(tint, hit * brightness * 0.58), 2.3, true)
		if stage < 4 or _preferences.fx_quality == 0:
			continue
		var orbit_count := 3 if stage == 5 else 2
		for i in orbit_count:
			var phase := elapsed * (0.6 + charge) + i * TAU / orbit_count
			var r := radius + 6.0 * charge
			var accent := Color(tint, (0.27 + charge * 0.48) * brightness)
			_overlay.draw_arc(at, r, phase, phase + (1.20 if stage == 5 else 0.72), 16, accent, 1.8 + charge, true)
			if stage == 5 and _preferences.fx_particles > 0.0:
				_overlay.draw_circle(at + Vector2.from_angle(phase) * r, 2.4, accent, true, -1.0, true)

func _draw_portals() -> void:
	var start := pixel(Vector2(battle.field.start) + Vector2(0.5, 0.5))
	var goal := pixel(Vector2(battle.field.exit) + Vector2(0.5, 0.5))
	var health := float(battle.health) / float(battle.data.balance.base_health)
	var core := PINK.lerp(MINT, health)
	glow_at(start, 31.0, Color(PINK, 0.48))
	glow_at(goal, 31.0, Color(core, 0.55))
	draw_arc(start, 19, elapsed, elapsed + 5.0, 32, PINK, 2.0, true)
	draw_arc(start, 14, -elapsed, -elapsed + 4.2, 32, Color("#ff92b0"), 1.5, true)
	draw_set_transform(goal, PI / 4.0)
	draw_rect(Rect2(-10, -10, 20, 20), Color("#122534"))
	draw_rect(Rect2(-10, -10, 20, 20), core, false, 2)
	draw_rect(Rect2(-5, -5, 10, 10), Color(core, health))
	draw_set_transform(Vector2.ZERO)
	draw_arc(goal, 19, -PI * 0.5, -PI * 0.5 + maxf(0.01, TAU * health), 40, core, 2.0, true)

func _update_flares() -> void:
	var ring_count := 0
	var spark_count := 0
	for flare in _flares:
		spark_count += _spark_count(flare.kind)
		if flare.kind != &"fire":
			ring_count += 1
	_effect_glows.begin(_flares.size())
	_rings.begin(ring_count)
	_sparks.begin(spark_count)
	var ring := 0
	var spark := 0
	for i in _flares.size():
		var flare := _flares[i]
		var t := flare.age / flare.duration
		var alpha := (1.0 - t) * (0.52 if _preferences.fx_dim else 1.0)
		var tint := Color(flare.color, alpha)
		var at := flare.point
		if flare.kind == &"fire":
			var length := 23.0 - t * 12.0
			_effect_glows.item(i, at, Vector2.RIGHT * 30.0, tint)
			_sparks.item(spark, at + flare.direction * length * 0.5, flare.direction * length, Color(Color.WHITE, alpha), (5.0 * alpha + 1.0) / length)
			spark += 1
			continue
		var radius := 9.0 + t * 23.0
		if flare.kind in [&"kill", &"base"]:
			radius *= 1.65
		elif flare.kind == &"collapse":
			radius *= 5.5
		_effect_glows.item(i, at, Vector2.RIGHT * radius * 1.35, tint)
		_rings.item(ring, at, Vector2.RIGHT * radius, tint)
		ring += 1
		var count := _spark_count(flare.kind)
		var length := 3.0 + alpha * 8.0
		for j in count:
			var direction := Vector2.from_angle(TAU * j / count + at.x * 0.09)
			var distance := radius * (0.65 + float(j % 3) * 0.16) + length * 0.5
			_sparks.item(spark, at + direction * distance, direction * length, tint, 2.0 / length)
			spark += 1
	_effect_glows.finish()
	_rings.finish()
	_sparks.finish()

func _spark_count(kind: StringName) -> int:
	if kind == &"fire":
		return 1
	var count := 4
	match kind:
		&"kill", &"base":
			count = 8
		&"collapse":
			count = 24
	return roundi(count * _preferences.fx_particles * (0.5 + 0.25 * _preferences.fx_quality))

func glow_at(at: Vector2, radius: float, color: Color) -> void:
	draw_texture_rect(_glow, centered(at, radius), false, color)

func centered(at: Vector2, radius: float) -> Rect2:
	return Rect2(at - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
