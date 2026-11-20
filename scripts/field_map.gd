class_name FieldMap
extends RefCounted

const REQUIRED_SIZE := Vector2i(30, 18)

var size: Vector2i
var title: String
var sample: bool
var tiles := PackedStringArray()
var path := PackedVector2Array()
var start: Vector2i
var exit: Vector2i

func load_map(data: Dictionary) -> String:
	size = read_cell(data.get("size"))
	if size != REQUIRED_SIZE:
		return "맵 크기는 30 × 18이어야 합니다."
	var rows: Variant = data.get("tiles")
	if not rows is Array or rows.size() != size.y:
		return "타일 행의 개수가 올바르지 않습니다."
	tiles.clear()
	path.clear()
	var track_cells := 0
	for row: Variant in rows:
		if not row is String or row.length() != size.x:
			return "타일 행의 길이가 올바르지 않습니다."
		for tile: String in row:
			if tile not in [".", "#", "=", "S", "E"]:
				return "알 수 없는 타일 기호입니다."
			if tile in ["=", "S", "E"]:
				track_cells += 1
		tiles.append(row)
	start = read_cell(data.get("spawn"))
	exit = read_cell(data.get("exit"))
	var coords: Variant = data.get("path")
	if not coords is Array or coords.size() < 2:
		return "경로에는 두 칸 이상 필요합니다."
	if tile_at(start) != "S" or tile_at(exit) != "E":
		return "생성 지점 또는 출구가 올바르지 않습니다."
	var seen := {}
	var previous := start
	for i in coords.size():
		var cell := read_cell(coords[i])
		if not contains(cell):
			return "경로 %d번 좌표가 격자 밖입니다." % (i + 1)
		if seen.has(cell):
			return "경로 %d번 좌표가 중복됩니다." % (i + 1)
		var step := cell - previous
		if i > 0 and absi(step.x) + absi(step.y) != 1:
			return "경로 %d번 좌표가 이전 칸에 연결되지 않습니다." % (i + 1)
		var expected := "="
		if i == 0:
			expected = "S"
		elif i == coords.size() - 1:
			expected = "E"
		if tile_at(cell) != expected:
			return "경로 %d번 좌표와 타일 유형이 일치하지 않습니다." % (i + 1)
		seen[cell] = true
		previous = cell
		path.append(Vector2(cell) + Vector2(0.5, 0.5))
	if read_cell(coords[0]) != start or previous != exit or seen.size() != track_cells:
		return "경로와 생성 지점, 출구 또는 경로 타일이 일치하지 않습니다."
	title = str(data.get("name", "전장"))
	sample = data.get("sample", false) == true
	return ""

static func read_cell(raw: Variant) -> Vector2i:
	if raw is Array and raw.size() == 2:
		if (raw[0] is float or raw[0] is int) and (raw[1] is float or raw[1] is int):
			var cell := Vector2(raw[0], raw[1])
			if cell.is_finite() and absf(cell.x) < 10000 and absf(cell.y) < 10000 and cell.floor() == cell:
				return Vector2i(cell)
	return Vector2i(-1, -1)

func contains(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y

func tile_at(cell: Vector2i) -> String:
	return tiles[cell.y][cell.x] if contains(cell) else ""

func length() -> float:
	return float(path.size() - 1)

func position_at(progress: float) -> Vector2:
	var distance := clampf(progress, 0, length())
	var segment := mini(floori(distance), path.size() - 2)
	return path[segment].lerp(path[segment + 1], distance - segment)

func heading_at(progress: float) -> Vector2:
	var segment := clampi(floori(progress), 0, path.size() - 2)
	return path[segment + 1] - path[segment]
