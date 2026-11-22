class_name ModPackage
extends RefCounted

const MAX_ARCHIVE := 1_048_576
const MAX_MEMBER := 262_144
const MAX_ROWS := 96
const MEMBERS := {"mod.json": "", "towers.json": "towers", "research.json": "nodes", "enemies.json": "enemies"}
const TOWER_FIELDS := {
	"id": "", "name": "", "description": "", "color": "", "attack": "", "damage": 0,
	"interval": 0.0, "range": 0.0, "cost": 0, "refund": 0, "refund_ratio": 0.0, "detect_cloak": false,
}
const ENEMY_FIELDS := {
	"id": "", "name": "", "color": "", "health": 0, "speed": 0.0, "reward": 0,
	"reward_rp": 0, "intro_cap": 0, "intro_hp": [], "base_damage_mode": "",
}
const ABILITIES := {
	"regen": {"interval": 0.0, "amount": 0},
	"cloak": {"cycle": 0.0, "hidden": 0.0},
	"acceleration": {"rate": 0.0, "max_speed": 0.0},
	"guardian": {"interval": 0.0, "shield_hp": 0, "range": 0.0, "targets": 0, "rearm": 0.0,
		"stackable": false, "persist_after_caster_death": true},
	"boost": {"interval": 0.0, "range": 0.0, "targets": 0, "bonus": 0.0, "duration": 0.0},
	"brood": {"interval": 0.0, "limit": 0, "child": ""},
}

static func valid_id(id: String) -> bool:
	if id.is_empty() or id.length() > 64:
		return false
	for i in id.length():
		var c := id.unicode_at(i)
		if not (c >= 97 and c <= 122 or c >= 48 and c <= 57 or c in [45, 46, 95]):
			return false
	return id.unicode_at(0) not in [45, 46, 95] and not id.contains("..")

static func import_zip(bytes: PackedByteArray, staging: String) -> Dictionary:
	var entries := _entries(bytes)
	if entries.is_empty():
		return {"error": "ZIP 루트에 mod.json과 지원되는 JSON 데이터만 넣어 주세요. 파일 크기와 ZIP 형식도 확인하세요."}
	var output := FileAccess.open(staging, FileAccess.WRITE)
	if output == null or not output.store_buffer(bytes):
		return {"error": "임시 파일을 저장할 수 없습니다."}
	output.close()
	var zip := ZIPReader.new()
	if zip.open(staging) != OK:
		return {"error": "ZIP 파일을 열 수 없습니다."}
	var package := {}
	for filename in entries:
		var data := zip.read_file(filename)
		var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
		if data.size() != entries[filename] or not parsed is Dictionary:
			zip.close()
			return {"error": "손상되었거나 올바르지 않은 JSON · " + filename}
		if filename == "mod.json":
			package.manifest = parsed
		else:
			var key: String = MEMBERS[filename]
			package[key] = parsed.get(key)
	zip.close()
	var error := validate(package)
	return {"package": package} if error.is_empty() else {"error": error}

static func _entries(bytes: PackedByteArray) -> Dictionary:
	# Inspect declared sizes before ZIPReader allocates or decompresses an entry.
	var length := bytes.size()
	if length < 22 or length > MAX_ARCHIVE:
		return {}
	var end := length - 22
	while end >= maxi(0, length - 65_557):
		if bytes.decode_u32(end) == 0x06054b50 and end + 22 + bytes.decode_u16(end + 20) == length:
			break
		end -= 1
	if end < maxi(0, length - 65_557) or bytes.decode_u32(end + 4) != 0:
		return {}
	var count := bytes.decode_u16(end + 10)
	var offset := bytes.decode_u32(end + 16)
	if count < 1 or count > MEMBERS.size() or bytes.decode_u16(end + 8) != count or offset + bytes.decode_u32(end + 12) != end:
		return {}
	var entries := {}
	var at := offset
	for i in count:
		if at + 46 > end or bytes.decode_u32(at) != 0x02014b50:
			return {}
		var flags := bytes.decode_u16(at + 8)
		var method := bytes.decode_u16(at + 10)
		var compressed := bytes.decode_u32(at + 20)
		var size := bytes.decode_u32(at + 24)
		var name_size := bytes.decode_u16(at + 28)
		var next := at + 46 + name_size + bytes.decode_u16(at + 30) + bytes.decode_u16(at + 32)
		var local := bytes.decode_u32(at + 42)
		if next > end or flags & 1 or method not in [0, 8] or size == 0 or size > MAX_MEMBER or local + 30 > offset:
			return {}
		var filename := bytes.slice(at + 46, at + 46 + name_size).get_string_from_ascii()
		if not MEMBERS.has(filename) or entries.has(filename) or bytes.decode_u32(local) != 0x04034b50:
			return {}
		var local_name := bytes.decode_u16(local + 26)
		var payload := local + 30 + local_name + bytes.decode_u16(local + 28)
		if payload + compressed > offset or bytes.decode_u16(local + 8) != method \
				or bytes.slice(local + 30, local + 30 + local_name) != filename.to_ascii_buffer():
			return {}
		entries[filename] = size
		at = next
	return entries if at == end and entries.has("mod.json") else {}

static func validate(package: Dictionary) -> String:
	var manifest: Variant = package.get("manifest")
	if not manifest is Dictionary or manifest.get("format") != 1:
		return "mod.json의 format은 1이어야 합니다."
	for key in ["id", "name", "author", "version", "description"]:
		var value: Variant = manifest.get(key)
		if not value is String or value.strip_edges().is_empty() or value.length() > (800 if key == "description" else 100):
			return "모드 정보 필드를 확인하세요 · " + key
	if not valid_id(manifest.id):
		return "모드 ID는 소문자, 숫자, 점, 밑줄, 하이픈을 사용할 수 있습니다."
	var dependencies: Variant = manifest.get("requires", [])
	if not dependencies is Array or dependencies.size() > 12:
		return "requires 의존성 목록을 확인하세요."
	var seen := {}
	for entry in dependencies:
		if not entry is String or not valid_id(entry) or entry == manifest.id or seen.has(entry):
			return "유효하지 않은 모드 의존성 · " + str(entry)
		seen[entry] = true
	var total := 0
	for key in ["towers", "nodes", "enemies"]:
		var rows: Variant = package.get(key, [])
		if not rows is Array or rows.size() > MAX_ROWS:
			return "데이터 목록 형식 또는 개수를 확인하세요 · " + key
		total += rows.size()
		seen.clear()
		for row in rows:
			if not row is Dictionary or not row.get("id") is String or not valid_id(row.id) or seen.has(row.id):
				return "잘못되었거나 중복된 콘텐츠 ID · " + key
			seen[row.id] = true
			var ok := _tower(row) if key == "towers" else (_enemy(row) if key == "enemies" else _research(row))
			if not ok:
				return "데이터 속성을 확인하세요 · " + row.id
	return "" if total > 0 else "추가할 콘텐츠가 없습니다."

static func _tower(row: Dictionary) -> bool:
	if not _fields(row, TOWER_FIELDS.merged(TowerRegistry.DEFAULTS)):
		return false
	if not _plain(row.get("name")) or not _plain(row.get("description")) or not _color(row.get("color")):
		return false
	var interval := float(row.get("interval", 0))
	return interval >= 0.02 and float(row.get("projectile_speed", 12)) > 0.0 \
		and int(row.get("stage", 0)) in range(6) and float(row.get("range", 0)) <= 100.0 \
		and int(row.get("shots", 1)) in range(1, 65) and int(row.get("split", 0)) in range(65) \
		and float(row.get("refund_ratio", 0.75)) >= 0 and float(row.get("refund_ratio", 0.75)) <= 1 \
		and int(row.get("refund", 0)) >= 0 and int(row.get("refund", 0)) <= int(row.get("cost", 0)) \
		and float(row.get("ramp", 0)) >= 0 and float(row.get("duration", 0)) >= 0 \
		and (row.get("attack") != "chain" or float(row.get("jump_radius", 0)) > 0.0) \
		and (row.get("attack") != "singularity" or float(row.get("tick", 0)) >= 0.02)

static func _enemy(row: Dictionary) -> bool:
	if not _fields(row, ENEMY_FIELDS.merged(EnemyRegistry.DEFAULTS)) or not _color(row.get("color")) or not _plain(row.get("name")):
		return false
	if bool(row.get("boss", false)) or not row.get("phases", []).is_empty() or int(row.get("first_wave", 1)) not in range(1, 51):
		return false
	var last_wave := 0
	for anchor in row.get("intro_hp", []):
		if not anchor is Array or anchor.size() != 2 or not _number(anchor[0]) or not _number(anchor[1]) \
				or float(anchor[0]) != int(anchor[0]) or int(anchor[0]) <= last_wave or int(anchor[0]) > 50 \
				or float(anchor[1]) <= 0.0 or float(anchor[1]) > 100.0:
			return false
		last_wave = int(anchor[0])
	for key in ABILITIES:
		var settings: Dictionary = row.get(key, {})
		if not _fields(settings, ABILITIES[key]):
			return false
		if not settings.is_empty() and settings.has("interval") and float(settings.interval) < 0.02:
			return false
	return float(row.get("scale", 1.0)) <= 8.0 and int(row.get("brood", {}).get("limit", 0)) <= 100 \
		and float(row.get("speed", 0)) >= 0.01 and float(row.get("speed", 0)) <= 50.0

static func _research(row: Dictionary) -> bool:
	if not _fields(row, {"id": "", "name": "", "description": "", "cost_rp": 0, "stage": 0, "lane": 0, "position": [], "unlock": {}}, ["requirements"]):
		return false
	var point: Array = row.get("position", [])
	var unlock: Dictionary = row.get("unlock", {})
	return row.get("name") is String and point.size() == 2 and _number(point[0]) and _number(point[1]) \
		and float(point[0]) >= 0 and float(point[0]) <= 25_000 and float(point[1]) >= 0 and float(point[1]) <= 8_000 \
		and _requirement(row.get("requirements"), 0, true) \
		and (not row.has("unlock") or (unlock.get("type") == "tower" and unlock.get("id") is String and valid_id(unlock.id)))

static func _requirement(value: Variant, depth: int, root: bool = false) -> bool:
	if value == null:
		return root
	if value is String:
		return valid_id(value)
	if depth >= 5 or not value is Dictionary or value.size() != 1:
		return false
	var terms: Variant = value.get("all", value.get("any"))
	if not terms is Array or terms.is_empty() or terms.size() > 8:
		return false
	for term in terms:
		if not _requirement(term, depth + 1):
			return false
	return true

static func _fields(row: Dictionary, fields: Dictionary, exceptions: Array = []) -> bool:
	for key in row:
		if key in exceptions:
			continue
		if not fields.has(key):
			return false
		var value: Variant = row[key]
		var sample: Variant = fields[key]
		if sample is int or sample is float:
			if not _number(value) or (sample is int and float(value) != float(int(value))):
				return false
		elif typeof(value) != typeof(sample) or value is String and value.length() > 800:
			return false
	return true

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) <= 100_000_000.0

static func _color(value: Variant) -> bool:
	return value is String and Color.html_is_valid(value)

static func _plain(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty() and not value.contains("[") and not value.contains("]")
