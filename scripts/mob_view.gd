class_name MobView
extends Node2D

const TEXTURES: Array[Texture2D] = [
	preload("res://assets/drone.png"), preload("res://assets/mobs/dart.png"),
	preload("res://assets/mobs/hex.png"), preload("res://assets/mobs/swarm.png"),
	preload("res://assets/mobs/cell.png"), preload("res://assets/mobs/split.png"),
	preload("res://assets/mobs/ring.png"), preload("res://assets/mobs/guardian.png"),
	preload("res://assets/mobs/relay.png"), preload("res://assets/mobs/tank.png"),
	preload("res://assets/mobs/calamity.png"), preload("res://assets/mobs/boss.png"),
]
const SHIELD_RING := preload("res://assets/shockwave.png")
const SHIELD_TINT := Color("#66d9ff")
const HP_TRACK := Color("#321a28")
const HP_FILL := Color("#ff9ab5")
const MARK_TINT := Color("#ddb3ff")
const SHOCK_TINT := Color("#8fc9ff")

var bodies: Array[SpriteBatch] = []
var rings: SpriteBatch
var health_back: SpriteBatch
var health_front: SpriteBatch
var shield_bar: SpriteBatch
var marks: SpriteBatch
var _counts := PackedInt32Array()
var _used := PackedInt32Array()
var _last_time := -1.0
var _last_count := -1

var _cell: float

func setup(material_mask: ShaderMaterial, cell: float) -> void:
	_cell = cell
	for texture in TEXTURES:
		var body := SpriteBatch.new(texture, _cell, material_mask)
		bodies.append(body)
		add_child(body)
	var white := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	var dot := ImageTexture.create_from_image(white)
	rings = SpriteBatch.new(SHIELD_RING, 2.0, null)
	health_back = SpriteBatch.new(dot, 1.0, null)
	health_front = SpriteBatch.new(dot, 1.0, null)
	shield_bar = SpriteBatch.new(dot, 1.0, null)
	marks = SpriteBatch.new(dot, 1.0, null)
	for batch: SpriteBatch in [rings, health_back, health_front, shield_bar, marks]:
		add_child(batch)
	_counts.resize(bodies.size())
	_used.resize(bodies.size())

func submit(battle: Battle, origin: Vector2, dim: bool) -> void:
	var total := battle.enemies.size()
	if _last_time == battle.elapsed and _last_count == total:
		return
	_last_time = battle.elapsed
	_last_count = total
	_counts.fill(0)
	_used.fill(0)
	var shielded := 0
	var injured := 0
	var marked := 0
	for drone in battle.enemies:
		_counts[drone.shape] += 1
		shielded += int(drone.shield_hp > 0)
		injured += int(drone.health < drone.maximum_health)
		marked += int(drone.status.mark_stacks > 0)
	for i in bodies.size():
		bodies[i].begin(_counts[i])
	rings.begin(shielded)
	shield_bar.begin(shielded)
	health_back.begin(injured)
	health_front.begin(injured)
	marks.begin(marked)
	shielded = 0
	injured = 0
	marked = 0
	var path := battle.field.path
	var last := path.size() - 2
	for drone in battle.enemies:
		var color := drone.tint
		if drone.flash > 0.0:
			color = color.lerp(Color.WHITE, 0.25 if dim else 0.53)
		if drone.status.stun_left > 0.0:
			color = color.lerp(SHOCK_TINT, 0.58)
		var at := origin + drone.position * _cell
		var segment := mini(floori(drone.progress), last)
		var heading := path[segment + 1] - path[segment]
		if drone.shape == 5:
			var age := battle.elapsed - drone.mob.spawn_at
			if age < 0.40 and int(drone.definition.get("generation", 0)) > 0:
				at += Vector2.from_angle((drone.serial % 4) * PI * 0.5) * sin(age / 0.4 * PI) * 17.0
		if drone.hidden:
			color.a = 0.34
		bodies[drone.shape].item(_used[drone.shape], at, heading * drone.scale, color)
		_used[drone.shape] += 1
		var half_width := 9.0 * maxf(0.72, drone.scale)
		var y := -13.0 * drone.scale
		if drone.shield_hp > 0:
			var ratio := float(drone.shield_hp) / float(drone.shield_max)
			var shield_color := Color(SHIELD_TINT, 0.16 if drone.hidden else 0.55 + ratio * 0.4)
			var bar := maxf(1.0, half_width * 2.0 * ratio)
			rings.item(shielded, at, Vector2.RIGHT * (22.0 * drone.scale), shield_color)
			shield_bar.item(shielded, at + Vector2(-half_width + bar * 0.5, y - 4.0), Vector2(bar, 0), shield_color, 2.0 / bar)
			shielded += 1
		if drone.health < drone.maximum_health:
			var full := half_width * 2.0
			var width := maxf(1.0, full * drone.health / float(drone.maximum_health))
			health_back.item(injured, at + Vector2(0, y), Vector2(full, 0), HP_TRACK, 2.0 / full)
			health_front.item(injured, at + Vector2(-half_width + width * 0.5, y), Vector2(width, 0), Color(HP_FILL, color.a), 2.0 / width)
			injured += 1
		if drone.status.mark_stacks > 0:
			var width := 3.0 + 2.0 * drone.status.mark_stacks
			marks.item(marked, at + Vector2(half_width + width * 0.5 + 4, y), Vector2(width, 0), MARK_TINT, 3.0 / width)
			marked += 1
	for batch in bodies:
		batch.finish()
	for batch: SpriteBatch in [rings, shield_bar, health_back, health_front, marks]:
		batch.finish()
