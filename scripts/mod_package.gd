class_name ModPackage
extends RefCounted

const MAX_ARCHIVE := 4_194_304
const MAX_DATA_V1 := 1_048_576
const MAX_INSTALLED_FILE := 6_291_456
const MAX_MEDIA_BYTES := 3_145_728
const MAX_ASSETS := 32
const MAX_ASSET_BYTES := 2_097_152
const MAX_MEMBER := 262_144
const MAX_ROWS := 96
const MEMBERS := {"mod.json": "", "towers.json": "towers", "research.json": "nodes", "enemies.json": "enemies",
	"campaign.json": "campaign", "tower_overrides.json": "tower_overrides", "assets.json": "bindings"}
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
		return {"error": "ZIP 안의 파일 이름, 크기 또는 형식을 확인하세요."}
	var output := FileAccess.open(staging, FileAccess.WRITE)
	if output == null or not output.store_buffer(bytes):
		return {"error": "임시 파일을 저장할 수 없습니다."}
	output.close()
	var zip := ZIPReader.new()
	if zip.open(staging) != OK:
		return {"error": "ZIP 파일을 열 수 없습니다."}
	var package := {}
	var files := {}
	for filename: String in entries:
		var data := zip.read_file(filename)
		if data.size() != entries[filename]:
			zip.close()
			return {"error": "손상된 ZIP 항목 · " + filename}
		if not MEMBERS.has(filename):
			files[filename] = Marshalls.raw_to_base64(data)
			continue
		var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
		if not parsed is Dictionary:
			zip.close()
			return {"error": "손상되었거나 올바르지 않은 JSON · " + filename}
		if filename == "mod.json":
			package.manifest = parsed
		else:
			var key: String = MEMBERS[filename]
			package[key] = parsed.get(key) if key in ["towers", "nodes", "enemies"] else parsed
	zip.close()
	if not files.is_empty():
		package.files = files
	if package.get("manifest", {}).get("format") == 1 and bytes.size() > MAX_DATA_V1:
		return {"error": "형식 1 모드의 ZIP은 1 MiB까지 지원합니다."}
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
	if count < 1 or count > MEMBERS.size() + MAX_ASSETS + 1 or bytes.decode_u16(end + 8) != count or offset + bytes.decode_u32(end + 12) != end:
		return {}
	var entries := {}
	var at := offset
	var media_bytes := 0
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
		if next > end or flags & 1 or method not in [0, 8] or size > MAX_ASSET_BYTES or local + 30 > offset:
			return {}
		var filename := bytes.slice(at + 46, at + 46 + name_size).get_string_from_ascii()
		if entries.has(filename) or bytes.decode_u32(local) != 0x04034b50:
			return {}
		if filename == "assets/":
			if size != 0:
				return {}
		elif MEMBERS.has(filename):
			if size == 0 or size > MAX_MEMBER:
				return {}
		elif _asset_path(filename):
			media_bytes += size
			if size == 0 or media_bytes > MAX_MEDIA_BYTES:
				return {}
		else:
			return {}
		var local_name := bytes.decode_u16(local + 26)
		var payload := local + 30 + local_name + bytes.decode_u16(local + 28)
		if payload + compressed > offset or bytes.decode_u16(local + 8) != method \
				or bytes.slice(local + 30, local + 30 + local_name) != filename.to_ascii_buffer():
			return {}
		entries[filename] = size
		at = next
	var directory := int(entries.erase("assets/"))
	if count - directory > MEMBERS.size() + MAX_ASSETS:
		return {}
	return entries if at == end and entries.has("mod.json") else {}

static func validate(package: Dictionary) -> String:
	var manifest: Variant = package.get("manifest")
	if not manifest is Dictionary or (manifest.get("format") != 1 and manifest.get("format") != 2):
		return "mod.json의 format은 1 또는 2여야 합니다."
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
	var expanded: bool = manifest.format == 2
	for key in ["campaign", "tower_overrides", "bindings", "files"]:
		if package.has(key) and (not expanded or not package[key] is Dictionary):
			return "해당 데이터에는 모드 형식 2가 필요합니다 · " + key
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
			var ok := _tower(row) if key == "towers" else (_enemy(row, expanded) if key == "enemies" else _research(row))
			if not ok:
				return "데이터 속성을 확인하세요 · " + row.id
	var campaign: Dictionary = package.get("campaign", {})
	var overrides: Dictionary = package.get("tower_overrides", {})
	if not _campaign(campaign):
		return "campaign.json의 맵 또는 웨이브 설정을 확인하세요."
	if not _tower_overrides(overrides):
		return "tower_overrides.json의 타워 ID 또는 수정 가능 속성을 확인하세요."
	var media_error := _media_structure(package)
	if not media_error.is_empty():
		return media_error
	return "" if total > 0 or not campaign.is_empty() or not overrides.is_empty() \
		or package.has("bindings") else "추가할 콘텐츠가 없습니다."

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

static func _enemy(row: Dictionary, expanded: bool) -> bool:
	if not _fields(row, ENEMY_FIELDS.merged(EnemyRegistry.DEFAULTS)) or not _color(row.get("color")) or not _plain(row.get("name")):
		return false
	var phases: Array = row.get("phases", [])
	if int(row.get("first_wave", 1)) not in range(1, 101 if expanded else 51):
		return false
	if (row.get("boss", false) or not phases.is_empty()) and (not expanded or not row.get("boss", false)):
		return false
	if phases.size() > 8:
		return false
	for phase in phases:
		if not phase is Dictionary or not _fields(phase, {"threshold": 0.0, "shield": 0, "speed_multiplier": 0.0, "regen": {}, "boost": {}}):
			return false
		if float(phase.get("speed_multiplier", 1)) > 10.0 or not _ability(phase, "regen") or not _ability(phase, "boost"):
			return false
	if row.get("boss", false) and (float(row.get("weight", 0)) != 0.0 or row.get("child", false)):
		return false
	var last_wave := 0
	for anchor in row.get("intro_hp", []):
		if not anchor is Array or anchor.size() != 2 or not _number(anchor[0]) or not _number(anchor[1]) \
				or float(anchor[0]) != int(anchor[0]) or int(anchor[0]) <= last_wave or int(anchor[0]) > 50 \
				or float(anchor[1]) <= 0.0 or float(anchor[1]) > 100.0:
			return false
		last_wave = int(anchor[0])
	for key in ABILITIES:
		if not _ability(row, key):
			return false
	return float(row.get("scale", 1.0)) <= 8.0 and int(row.get("brood", {}).get("limit", 0)) <= 100 \
		and float(row.get("speed", 0)) >= 0.01 and float(row.get("speed", 0)) <= 50.0

static func _ability(row: Dictionary, key: String) -> bool:
	var settings: Dictionary = row.get(key, {})
	return _fields(settings, ABILITIES[key]) and (not settings.has("interval") or float(settings.interval) >= 0.02)

static func _campaign(campaign: Dictionary) -> bool:
	if not _fields(campaign, {"final_wave": 0, "boss_id": "", "map": {}, "waves": []}):
		return false
	if int(campaign.get("final_wave", 50)) not in range(1, 101) or not valid_id(campaign.get("boss_id", "boss")):
		return false
	if campaign.has("map") and (not _plain(campaign.map.get("name", "전장")) or FieldMap.new().load_map(campaign.map) != ""):
		return false
	var seen := {}
	var waves: Array = campaign.get("waves", [])
	if waves.size() > 100:
		return false
	for row in waves:
		if not row is Dictionary or not _fields(row, {"wave": 0, "count": 0, "interval": 0.0, "reward": 0, "spawns": []}):
			return false
		var wave := int(row.get("wave", 0))
		if wave not in range(1, 101) or seen.has(wave):
			return false
		seen[wave] = true
		if int(row.get("count", 1)) not in range(1, 2001) or float(row.get("interval", 0.5)) < 0.02 \
				or float(row.get("interval", 0.5)) > 60.0 or int(row.get("reward", 0)) < 0:
			return false
		var groups: Array = row.get("spawns", [])
		if groups.size() > 128:
			return false
		for group in groups:
			if not group is Dictionary or not _fields(group, {"enemy": "", "count": 0, "interval": 0.0}) \
					or not valid_id(group.get("enemy", "")) or int(group.get("count", 0)) not in range(1, 2001) \
					or float(group.get("interval", 0.5)) < 0.02 or float(group.get("interval", 0.5)) > 60.0:
				return false
	return true

static func _tower_overrides(overrides: Dictionary) -> bool:
	if overrides.size() > MAX_ROWS:
		return false
	for id: String in overrides:
		var patch: Variant = overrides[id]
		if not valid_id(id) or not patch is Dictionary or patch.is_empty() or not _fields(patch, {
			"name": "", "description": "", "color": "", "damage": 0.0, "interval": 0.0,
			"range": 0.0, "cost": 0, "refund_ratio": 0.0, "production": 0, "projectile_speed": 0.0,
		}):
			return false
		if (patch.has("name") and not _plain(patch.name)) or (patch.has("description") and not _plain(patch.description)) \
				or (patch.has("color") and not _color(patch.color)):
			return false
		if float(patch.get("interval", 1.0)) < 0.02 or float(patch.get("range", 0)) > 100 \
				or float(patch.get("projectile_speed", 12)) <= 0 or int(patch.get("production", 0)) < 0 \
				or float(patch.get("refund_ratio", 1)) < 0 or float(patch.get("refund_ratio", 1)) > 1:
			return false
	return true

static func _asset_path(path: String) -> bool:
	if not path.begins_with("assets/"):
		return false
	var basename := path.trim_prefix("assets/")
	return basename.get_extension() in ["png", "wav", "ogg"] and valid_id(basename.get_basename())

static func _media_structure(package: Dictionary) -> String:
	var bindings: Dictionary = package.get("bindings", {})
	var files: Dictionary = package.get("files", {})
	if not package.has("bindings") and files.is_empty():
		return ""
	if not _fields(bindings, {"towers": {}, "enemies": {}, "audio": {}}) or files.is_empty() or files.size() > MAX_ASSETS:
		return "assets.json과 assets/ 파일을 확인하세요."
	var referenced := {}
	for kind: String in bindings:
		for id: String in bindings[kind]:
			var path: Variant = bindings[kind][id]
			if not valid_id(id) or not path is String or not _asset_path(path) or not files.has(path):
				return "리소스 연결을 확인하세요 · " + id
			if (path.get_extension() == "png") != (kind != "audio"):
				return "리소스 파일 형식이 맞지 않습니다 · " + path
			if kind == "audio" and not id in ["patrol", "boss", "wave", "clear", "install", "sell", "hit", "kill", "base", "charge", "heavy"]:
				return "지원하지 않는 음향 슬롯 · " + id
			referenced[path] = true
	var length := 0
	for path: String in files:
		var bytes: Variant = files[path]
		if not referenced.has(path) or not bytes is String or bytes.length() > ceili(MAX_ASSET_BYTES / 3.0) * 4:
			return "리소스 파일 크기 또는 사용처를 확인하세요 · " + path
		length += bytes.length()
	if length > ceili(MAX_MEDIA_BYTES / 3.0) * 4 + 4 * MAX_ASSETS:
		return "리소스 합계는 3 MiB까지 지원합니다."
	return ""

static func decode_media(package: Dictionary) -> Dictionary:
	var loaded := {}
	var media := {}
	var files: Dictionary = package.get("files", {})
	var bindings: Dictionary = package.get("bindings", {})
	for kind: String in bindings:
		media[kind] = {}
		for id: String in bindings[kind]:
			var path: String = bindings[kind][id]
			var music := kind == "audio" and id in ["patrol", "boss"]
			var key := path + ("#music" if music else "")
			if not loaded.has(key):
				var bytes := Marshalls.base64_to_raw(files[path])
				var resource := _read_media(path.get_extension(), bytes, music)
				if resource == null:
					return {"error": "리소스를 읽을 수 없습니다 · " + path}
				loaded[key] = resource
			media[kind][id] = loaded[key]
	return {"media": media}

static func _read_media(ext: String, bytes: PackedByteArray, music: bool) -> Resource:
	if ext == "png":
		if bytes.size() < 33 or bytes.slice(0, 8).hex_encode() != "89504e470d0a1a0a" \
				or bytes.slice(8, 16).hex_encode() != "0000000d49484452":
			return null
		for offset in [16, 20]:
			var dimension := (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3]
			if dimension < 1 or dimension > 512:
				return null
		var image := Image.new()
		if image.load_png_from_buffer(bytes) != OK:
			return null
		image.generate_mipmaps()
		return ImageTexture.create_from_image(image)
	var stream: AudioStream
	if ext == "ogg" and bytes.size() > 32 and bytes.slice(0, 4).get_string_from_ascii() == "OggS":
		var ogg := AudioStreamOggVorbis.load_from_buffer(bytes)
		if ogg != null:
			ogg.loop = music
			stream = ogg
	elif ext == "wav" and bytes.size() > 44 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" \
			and bytes.slice(8, 12).get_string_from_ascii() == "WAVE":
		var options := {"edit/loop_mode": 2} if music else {}
		stream = AudioStreamWAV.load_from_buffer(bytes, options)
	if stream == null or stream.get_length() <= 0.0 or stream.get_length() > (300.0 if music else 8.0):
		return null
	return stream

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
