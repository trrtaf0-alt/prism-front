class_name TowerArt
extends RefCounted

const ATLAS := preload("res://assets/tower_atlas.png")
const SHADER := preload("res://assets/tower_atlas.gdshader")
const FRAME_SIDE := 128
const FRAMES_PER_ROW := 8
const FRAME_ENCODING := 127
const SIZE := 1.54

static var _textures: Dictionary = {}

static func first_frame(id: String) -> int:
	var suffix := id.trim_prefix("tower_")
	if suffix == id or not suffix.is_valid_int():
		return 0
	var number := suffix.to_int()
	return (number - 1) * 2 if number >= 1 and number <= 36 else 0

static func batch_color(frame: int) -> Color:
	return Color(float(frame) / FRAME_ENCODING, 1.0, 1.0)

static func icon(frame: int) -> AtlasTexture:
	if not _textures.has(frame):
		var art := AtlasTexture.new()
		art.atlas = ATLAS
		art.region = Rect2(
			(frame % FRAMES_PER_ROW) * FRAME_SIDE,
			floori(float(frame) / FRAMES_PER_ROW) * FRAME_SIDE,
			FRAME_SIDE, FRAME_SIDE,
		)
		art.filter_clip = true
		_textures[frame] = art
	return _textures[frame]

static func size_for_stage(stage: int) -> float:
	return SIZE * (1.0 + 0.075 * stage)

static func rotation_offset(id: String, elapsed: float) -> float:
	match id:
		"tower_14", "tower_20", "tower_27", "tower_28", "tower_32", "tower_35":
			return elapsed * -0.65
		"tower_21", "tower_34":
			return elapsed * 2.0
		"tower_22", "tower_24", "tower_29", "tower_30", "tower_31", "tower_33", "tower_36":
			return elapsed * 0.38
	return 0.0
