class_name SupportView
extends Node2D

const COLORS := [Color.TRANSPARENT, Color("#56dac9"), Color("#76b9ff"), Color("#bd90f8"), Color("#ff985a"), Color("#ac80fb"), Color("#ffdaa0")]
const AQUA := Color("#69f1da")
const Kind := TowerSupport.Kind
const ATLAS := preload("res://assets/support_atlas.png")

var battle
var view
var preferences
var _visible_field := Rect2()
var _glyphs: SpriteBatch

func setup(owner_view, active_battle, profile) -> void:
	view = owner_view
	battle = active_battle
	preferences = profile
	var fx_material := ShaderMaterial.new()
	fx_material.shader = TowerArt.SHADER
	_glyphs = SpriteBatch.new(ATLAS, 1.0, fx_material)
	add_child(_glyphs)
	_visible_field = Rect2(view.ORIGIN, Vector2(battle.field.size) * view.CELL).grow(35.0)

func _draw() -> void:
	var quality: int = preferences.fx_quality
	var dim := 0.57 if preferences.fx_dim else 1.0
	var time: float = view.elapsed
	var selected = battle.occupied.get(view.selected)
	var quantum_links := PackedVector2Array()
	var particles := roundi(64.0 * float(preferences.fx_particles)) if quality >= 3 else 0
	var used := 0
	_glyphs.begin(battle.towers.size() * 8 + particles)
	for tower in battle.towers:
		var at: Vector2 = view.pixel(tower.position)
		if not _visible_field.has_point(at):
			continue
		var kind: int = tower.definition.support
		if kind != Kind.NONE:
			var followers: Array = battle.support.followers(tower)
			var active := not followers.is_empty()
			_glyphs.item(used, at + Vector2(0, -31), Vector2.RIGHT * 19, _paint(kind - 1, 0.95 if active else 0.38))
			used += 1
			if quality >= 1 and active:
				_source(at, kind, time, quality, dim, followers)
			continue
		var count: int = tower.buffs.size()
		if count == 0:
			continue
		var slot := 0
		var choose := posmod(floori(time * 7.0) + tower.cell.x + tower.cell.y, count)
		var strength := float(tower.recoil) / 0.12
		for buff in range(1, Kind.COMMAND + 1):
			if not tower.buffs.has(buff):
				continue
			var direction := (slot - (count - 1) * 0.5) * 0.28 - PI * 0.5
			var mark: Vector2 = at + Vector2.from_angle(direction) * (22.0 + 2.5 * tower.definition.stage)
			_glyphs.item(used, mark, Vector2.RIGHT * 14.0, _paint(buff - 1, 0.94))
			used += 1
			var synced: bool = buff == Kind.COMMAND and battle.support.synchronized
			if quality >= 1 and (slot == choose or synced):
				var alpha := (0.40 if quality >= 2 else 0.21) + strength * 0.46 + (0.27 if synced else 0.0)
				var facing: float = tower.angle
				if buff == Kind.COMMAND:
					facing = _command_spin(time, 0.9, 3.7)
				elif buff == Kind.RESONANCE or buff == Kind.QUANTUM:
					facing = time * (-2.0 if buff == Kind.QUANTUM else 1.0)
				if strength > 0.0 or quality >= 2 and buff >= Kind.RESONANCE:
					_glyphs.item(used, at, Vector2.from_angle(facing) * (70.0 + strength * 8.0), _paint(7 + buff, alpha * dim))
					used += 1
			var source = tower.buffs[buff]
			if (selected == source and quality >= 1) or (buff == Kind.QUANTUM and quality >= 2):
				var start: Vector2 = view.pixel(source.position)
				if selected == source:
					draw_line(start, at, Color(COLORS[buff], 0.5), 1.15, true)
				else:
					quantum_links.append(start)
					quantum_links.append(at)
				if particles > 0:
					particles -= 1
					var dot := start.lerp(at, fposmod(time * 0.76 + slot * 0.13, 1.0))
					_glyphs.item(used, dot, Vector2.RIGHT * 8.0, _paint(Kind.QUANTUM - 1, 0.80))
					used += 1
			if selected == source:
				draw_arc(at, 26.0, 0.0, TAU, 28, Color(COLORS[buff], 0.8), 1.8, true)
			slot += 1
	_glyphs.finish(used)
	if not quantum_links.is_empty():
		draw_multiline(quantum_links, Color(COLORS[Kind.QUANTUM], 0.19), 1.15, true)

static func _paint(frame: int, alpha: float) -> Color:
	return Color(TowerArt.batch_color(frame), clampf(alpha, 0.0, 1.0))
func _source(at: Vector2, kind: int, time: float, quality: int, dim: float, followers: Array) -> void:
	var color := Color(COLORS[kind], 0.56 * dim)
	var phase := fposmod(time * 0.62, 1.0)
	match kind:
		Kind.TACTICAL:
			var tip := at + Vector2.from_angle(time * 0.38) * 23.0
			draw_circle(tip, 2.7, Color(color, (0.32 + 0.60 * phase) * dim), true, -1.0, true)
			draw_arc(at, 26.0 + 22.0 * phase, 0, TAU, 32, Color(color, (1.0 - phase) * 0.45 * dim), 1.4, true)
		Kind.AIM:
			var sweep := Vector2.from_angle(-time * 0.65)
			draw_line(at, at + sweep * 42.0, color, 1.6, true)
			draw_arc(at, 36.0, sweep.angle() - 0.7, sweep.angle(), 12, color, 2.2, true)
			for i in 4:
				var mark := Vector2.from_angle(i * PI * 0.5) * 36.0
				draw_line(at + mark * 0.9, at + mark * 1.1, color, 1.4, true)
		Kind.RESONANCE:
			var activity := 0.0
			for i in mini(8, followers.size()):
				activity = maxf(activity, followers[i].recoil / 0.12)
			color.a += 0.3 * activity * dim
			draw_arc(at, 30.0, time, time + TAU * 0.62, 24, color, 2.0, true)
			draw_arc(at, 35.0 + phase * 9.0, -time, -time + TAU * 0.4, 16, color, 1.2, true)
		Kind.OVERDRIVE:
			var dir := Vector2.from_angle(time * 2.0)
			var side := dir.orthogonal()
			draw_polyline(PackedVector2Array([at + dir * 18.0, at + dir * 29.0 - side * 6.0, at + dir * 28.0, at + dir * 40.0 + side * 7.0]), color, 2.3, true)
			draw_arc(at, 30.0 + phase * 12.0, time, time + 2.4, 18, color, 2.0, true)
		Kind.QUANTUM:
			draw_arc(at, 39.0, time * 0.9, time * 0.9 + 2.7, 20, color, 1.9, true)
			draw_arc(at, 43.0, -time, -time + 2.3, 18, Color(AQUA, 0.48 * dim), 1.9, true)
		Kind.COMMAND:
			var synced: bool = battle.support.synchronized
			var phase_advance := _command_spin(time, 0.66, 2.4)
			for i in (3 if quality >= 2 else 1):
				var rotation := phase_advance * (-1.0 if i % 2 == 0 else 1.0)
				draw_arc(at, 39.0 + i * 6.5, rotation, rotation + 4.3, 26, Color(color, (0.8 if synced else 0.44) * dim), 2.6, true)
			if synced:
				draw_circle(at, 6.0, Color("#fff3bc"), true, -1.0, true)

func _command_spin(time: float, idle: float, active: float) -> float:
	var clock: float = battle.support.command_time
	var cycles := floori(clock / TowerSupport.SYNC_PERIOD)
	var synced_seconds := 0.0
	if cycles > 0:
		synced_seconds = (cycles - 1) * TowerSupport.SYNC_DURATION + minf(fposmod(clock, TowerSupport.SYNC_PERIOD), TowerSupport.SYNC_DURATION)
	return time * idle + synced_seconds * (active - idle)
