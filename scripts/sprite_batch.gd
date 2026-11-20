class_name SpriteBatch
extends MultiMeshInstance2D

# 2D transform rows are padded to four floats. The final four values are RGBA.
const STRIDE := 12
var _buffer := PackedFloat32Array()
var _count := 0

func _init(sprite: Texture2D, side: float, sprite_material: Material, shape: Mesh = null) -> void:
	texture = sprite
	material = sprite_material
	if shape == null:
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * side
		shape = quad
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.mesh = shape
	multimesh.custom_aabb = AABB(Vector3.ZERO, Vector3(1920, 1080, 1))

func begin(count: int) -> void:
	_count = count
	if count > multimesh.instance_count:
		var capacity := 16
		while capacity < count:
			capacity *= 2
		multimesh.instance_count = capacity
		_buffer.resize(capacity * STRIDE)

func item(index: int, at: Vector2, heading: Vector2, tint: Color, vertical_scale: float = 1.0) -> void:
	var i := index * STRIDE
	_buffer[i] = heading.x
	_buffer[i + 1] = -heading.y * vertical_scale
	_buffer[i + 3] = at.x
	_buffer[i + 4] = heading.y
	_buffer[i + 5] = heading.x * vertical_scale
	_buffer[i + 7] = at.y
	_buffer[i + 8] = tint.r
	_buffer[i + 9] = tint.g
	_buffer[i + 10] = tint.b
	_buffer[i + 11] = tint.a

func finish(used: int = -1) -> void:
	var visible_count := _count if used < 0 else used
	multimesh.visible_instance_count = visible_count
	if visible_count > 0:
		multimesh.buffer = _buffer
