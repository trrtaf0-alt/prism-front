class_name FieldView
extends Node2D

const CELL := 48.0
const ORIGIN := Vector2(48, 147)
const MINT := Color("#50f6ed")
const PINK := Color("#ff467d")
const GOLD := Color("#ffc879")
const GRID := Color("#1b2a3a")
const MAX_EFFECTS := 160
const DRONE_TEXTURE := preload("res://assets/drone.png")
const TURRET_BASE := preload("res://assets/turret_base.png")
const TURRET_HEAD := preload("res://assets/turret_head.png")
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
var _preferences
var frozen := false
var elapsed := 0.0
var _flares: Array[Flare] = []
var _available: Array[Flare] = []
var _glow: ImageTexture
var _turret_color: Color
var _drone_color: Color
var _bases: SpriteBatch
var _heads: SpriteBatch
var _drones: SpriteBatch
var _bolts: SpriteBatch
var _overlay: Node2D
var _sparks: SpriteBatch
var _rings: SpriteBatch
var _effect_glows: SpriteBatch
var _health_back: SpriteBatch
var _health_front: SpriteBatch
var _marks: SpriteBatch

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
	_bases = SpriteBatch.new(TURRET_BASE, 48.0, material_mask)
	_heads = SpriteBatch.new(TURRET_HEAD, 48.0, material_mask)
	_drones = SpriteBatch.new(DRONE_TEXTURE, 48.0, material_mask)
	_bolts = SpriteBatch.new(BOLT_TEXTURE, 55.0, material_mask)
	for batch: SpriteBatch in [_bases, _heads, _drones, _bolts]:
		add_child(batch)
	_overlay = Node2D.new()
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)
	var white := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	_effect_glows = SpriteBatch.new(_glow, 2.0, null)
	_rings = SpriteBatch.new(SHOCKWAVE, 2.0, null)
	var dot := ImageTexture.create_from_image(white)
	_sparks = SpriteBatch.new(dot, 1.0, null)
	_health_back = SpriteBatch.new(dot, 1.0, null)
	_health_front = SpriteBatch.new(dot, 1.0, null)
	_marks = SpriteBatch.new(dot, 1.0, null)
	for batch: SpriteBatch in [_health_back, _health_front, _marks, _effect_glows, _rings, _sparks]:
		add_child(batch)
	advanced_fx.setup(_glow, _preferences, get_tree().root.get_node("Sound"))
	add_child(advanced_fx)
	battle.attack_visual.connect(advanced_fx.capture)
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
	canvas.draw_rect(Rect2(ORIGIN - Vector2(9, 9), extent + Vector2(18, 18)), Color("#101b29"))
	for y in map.size.y:
		for x in map.size.x:
			var at := ORIGIN + Vector2(x, y) * CELL
			var tile := map.tile_at(Vector2i(x, y))
			var color := Color("#101c29") if (x + y) % 2 == 0 else Color("#111e2b")
			if tile == "#":
				color = Color("#161e2a")
			elif tile != ".":
				color = Color("#172b37")
			canvas.draw_rect(Rect2(at + Vector2.ONE, Vector2.ONE * (CELL - 1)), color)
			if tile == "#":
				var plate := Rect2(at + Vector2(6, 6), Vector2(36, 36))
				canvas.draw_rect(plate, Color("#26313f"))
				canvas.draw_rect(plate, Color("#364354"), false, 1.0)
				canvas.draw_line(at + Vector2(11, 34), at + Vector2(34, 11), Color("#495868"), 1.4, true)
				canvas.draw_line(at + Vector2(23, 35), at + Vector2(35, 23), Color("#3c4a5c"), 1.4, true)
			elif tile == ".":
				canvas.draw_rect(Rect2(at + Vector2(23, 23), Vector2(2, 2)), GRID.lightened(0.10))
	var track := PackedVector2Array()
	for point in map.path:
		track.append(pixel(point))
	canvas.draw_polyline(track, Color("#203e4a"), 4.0, true)
	canvas.draw_polyline(track, Color("#315465"), 1.0, true)
	for i in range(1, map.path.size() - 1):
		var at := track[i]
		var direction := (track[i + 1] - at).normalized()
		var side := direction.orthogonal()
		canvas.draw_polyline(PackedVector2Array([at - direction * 4 + side * 5, at + direction * 2, at - direction * 4 - side * 5]), Color("#437782"), 1.6, true)
	canvas.draw_rect(Rect2(ORIGIN, extent), Color("#34485c"), false, 1.0)

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

func _update_batches() -> void:
	_bases.begin(battle.towers.size())
	_heads.begin(battle.towers.size())
	for i in battle.towers.size():
		var tower := battle.towers[i]
		var at := pixel(tower.position)
		var aim := Vector2.from_angle(tower.angle)
		var pulse := 0.9 + sin(elapsed * 3.0) * 0.1
		var tint: Color = tower.definition.tint
		var scale := 1.0 + float(tower.definition.stage) * 0.085
		_bases.item(i, at, Vector2.RIGHT * scale, Color(tint, pulse))
		_heads.item(i, at - aim * (tower.recoil * 34.0), aim * scale, tint)
	_bases.finish()
	_heads.finish()
	var count := battle.enemies.size()
	_drones.begin(count)
	_health_back.begin(count)
	_health_front.begin(count)
	_marks.begin(count)
	var damaged := 0
	var marked := 0
	for i in count:
		var drone := battle.enemies[i]
		var color := drone.tint.lerp(Color.WHITE, 0.64 if not _preferences.fx_dim else 0.27) if drone.flash > 0.0 else drone.tint
		if drone.status.stun_left > 0.0:
			color = color.lerp(Color("#8fc9ff"), 0.65)
		var at := pixel(drone.position)
		_drones.item(i, at, battle.field.heading_at(drone.progress), color)
		if drone.health < drone.maximum_health:
			var width := maxf(1.0, 18.0 * drone.health / float(drone.maximum_health))
			_health_back.item(damaged, at + Vector2(0, -13), Vector2(18, 0), Color("#3a1b34"), 2.0 / 18.0)
			_health_front.item(damaged, at + Vector2(-9.0 + width * 0.5, -13), Vector2(width, 0), Color("#ffa4bd"), 2.0 / width)
			damaged += 1
		if drone.status.mark_stacks > 0:
			var width := 3.0 + 2.0 * drone.status.mark_stacks
			_marks.item(marked, at + Vector2(13 + width * 0.5, -13), Vector2(width, 0), Color("#ddb3ff"), 3.0 / width)
			marked += 1
	_drones.finish()
	_health_back.finish(damaged)
	_health_front.finish(damaged)
	_marks.finish(marked)
	_bolts.begin(battle.bolts.size())
	for i in battle.bolts.size():
		var bolt := battle.bolts[i]
		_bolts.item(i, pixel(bolt.position), bolt.direction * (0.68 if bolt.fragment else 1.0), bolt.definition.tint)
	_bolts.finish()

func _draw() -> void:
	var map := battle.field
	_draw_portals()
	var focus := selected if map.contains(selected) else (hovered if building and battle.can_install(hovered, build_id) else Vector2i(-1, -1))
	if map.contains(focus):
		var at := pixel(Vector2(focus) + Vector2(0.5, 0.5))
		var def: Dictionary = battle.occupied[focus].definition if battle.occupied.has(focus) else battle.data.towers.lookup(build_id)
		var tint: Color = def.tint
		if def.global:
			var area := Rect2(ORIGIN, Vector2(battle.field.size) * CELL).grow(-2.0)
			draw_rect(area, Color(tint, 0.075))
			draw_rect(area, Color(tint, 0.78), false, 2.3)
		else:
			var radius := float(def.range) * CELL
			draw_circle(at, radius, Color(tint, 0.075), true, -1.0, true)
			draw_arc(at, radius, 0, TAU, 96, Color(tint, 0.6), 1.6, true)
	if map.contains(hovered) and not battle.lost:
		var at := pixel(Vector2(hovered))
		var color := MINT if not building or battle.can_install(hovered, build_id) else PINK
		var tile := Rect2(at + Vector2(2, 2), Vector2(44, 44))
		draw_rect(tile, Color(color, 0.12))
		draw_rect(tile, Color(color, 0.76), false, 1.5)
	if battle.occupied.has(selected):
		draw_arc(pixel(battle.occupied[selected].position), 21.0, 0, TAU, 32, battle.occupied[selected].definition.tint, 2.0, true)

func _draw_overlay() -> void:
	for tower in battle.towers:
		if tower.definition.stage >= 3 and tower.recoil > 0.0:
			var tint: Color = Color(tower.definition.tint, tower.recoil * 5.0)
			_overlay.draw_arc(pixel(tower.position), 18.0 + 8.0 * (1.0 - tower.recoil / 0.12), elapsed * 2.0, elapsed * 2.0 + 4.9, 22, tint, 2.3)

func _draw_portals() -> void:
	var start := pixel(Vector2(battle.field.start) + Vector2(0.5, 0.5))
	var goal := pixel(Vector2(battle.field.exit) + Vector2(0.5, 0.5))
	var health := float(battle.health) / float(battle.data.balance.base_health)
	var core := PINK.lerp(MINT, health)
	glow_at(start, 31.0, Color(PINK, 0.8))
	glow_at(goal, 31.0, Color(core, 0.9))
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
