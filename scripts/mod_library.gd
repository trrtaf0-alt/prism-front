class_name ModLibrary
extends RefCounted

const MAX_INSTALLED := 24
const MAX_ADDED_PER_KIND := 256
const KEYS := ["towers", "nodes", "enemies"]
const CONTENT_NAMES := {"towers": "타워", "nodes": "연구", "enemies": "적"}

var packages: Dictionary = {}
var requested: Dictionary = {}
var problems: Dictionary = {}
var applied: Dictionary = {}
var data: BattleData
var storage_error := ""
var _directory: String
var _base: BattleData

func _init(directory: String = "user://mods", base: BattleData = null) -> void:
	_directory = directory
	_base = base if base != null else BattleData.new()
	data = _base
	reload()

func reload() -> void:
	packages.clear()
	requested.clear()
	storage_error = ""
	var dir := DirAccess.open(_directory)
	if dir == null:
		resolve()
		return
	var config := ConfigFile.new()
	var loaded := config.load(_path(".enabled.cfg"))
	if loaded != OK and loaded != ERR_FILE_NOT_FOUND:
		storage_error = "저장된 모드 설정을 읽을 수 없습니다."
	for filename in dir.get_files():
		var id := filename.trim_suffix(".json")
		if not filename.ends_with(".json") or not ModPackage.valid_id(id):
			continue
		var source := FileAccess.open(_path(filename), FileAccess.READ)
		var package: Variant = null
		if source != null and source.get_length() <= 4 * ModPackage.MAX_MEMBER:
			package = JSON.parse_string(source.get_as_text())
		if not package is Dictionary or not ModPackage.validate(package).is_empty() or package.manifest.id != id:
			package = {"manifest": {"id": id, "name": id, "author": "", "version": "", "description": "설치 파일을 읽을 수 없습니다."}, "invalid": true}
		packages[id] = package
		if config.get_value("mods", id, false) == true:
			requested[id] = true
	resolve()

func install(path: String) -> String:
	if packages.size() >= MAX_INSTALLED:
		return "모드는 최대 %d개까지 설치할 수 있습니다." % MAX_INSTALLED
	if not path.begins_with("content://") and path.get_extension().to_lower() != "zip":
		return "ZIP 파일을 선택하세요."
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null:
		return "선택한 파일을 읽을 수 없습니다."
	var bytes := source.get_buffer(ModPackage.MAX_ARCHIVE + 1)
	source.close()
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory)) != OK:
		return "모드 저장 공간을 만들 수 없습니다."
	var staging := _path(".import.zip")
	var result := ModPackage.import_zip(bytes, staging)
	if FileAccess.file_exists(staging):
		DirAccess.remove_absolute(staging)
	if result.has("error"):
		return result.error
	var package: Dictionary = result.package
	var id: String = package.manifest.id
	if packages.has(id):
		return "같은 ID의 모드가 이미 설치되어 있습니다 · " + id
	if not _write(_path(id + ".json"), JSON.stringify(package)):
		return "설치 파일을 저장할 수 없습니다."
	packages[id] = package
	resolve()
	return ""

func set_enabled(id: String, enabled: bool) -> String:
	if not packages.has(id) or packages[id].get("invalid", false):
		return "설치 파일이 손상되었습니다."
	var next := requested.duplicate()
	if enabled:
		next[id] = true
	else:
		next.erase(id)
	return _apply_settings(next)

func set_all(enabled: bool) -> String:
	var next := {}
	if enabled:
		for id in packages:
			if not packages[id].get("invalid", false):
				next[id] = true
	return _apply_settings(next)

func remove(id: String) -> String:
	if not packages.has(id) or not ModPackage.valid_id(id):
		return "설치된 모드를 찾을 수 없습니다."
	var next := requested.duplicate()
	next.erase(id)
	if next != requested and not _save_settings(next):
		return "모드 설정을 저장할 수 없습니다."
	if DirAccess.remove_absolute(_path(id + ".json")) != OK:
		_save_settings(requested)
		return "설치 파일을 삭제할 수 없습니다."
	packages.erase(id)
	requested = next
	resolve()
	return ""

func resolve() -> void:
	data = _base
	applied.clear()
	problems.clear()
	var appended := {"towers": [], "nodes": [], "enemies": []}
	var pending := requested.keys()
	pending.sort()
	for id in packages:
		if packages[id].get("invalid", false):
			problems[id] = "설치 파일이 손상되었습니다."
	while not pending.is_empty():
		var progress := false
		for id: String in pending.duplicate():
			var manifest: Dictionary = packages[id].manifest
			var waiting := false
			var blocked := str(problems.get(id, ""))
			for dependency: String in manifest.get("requires", []):
				if not requested.has(dependency) or problems.has(dependency):
					blocked = "필요한 모드가 설치·활성화되지 않았거나 적용할 수 없습니다 · " + dependency
					break
				waiting = waiting or not applied.has(dependency)
			if waiting and blocked.is_empty():
				continue
			pending.erase(id)
			progress = true
			if blocked.is_empty():
				blocked = _include(id, appended)
			if not blocked.is_empty():
				problems[id] = blocked
		if not progress:
			for id in pending:
				problems[id] = "모드 의존성이 순환합니다 · " + ", ".join(PackedStringArray(packages[id].manifest.get("requires", [])))
			break

func _include(id: String, appended: Dictionary) -> String:
	var package: Dictionary = packages[id]
	var candidate := appended.duplicate(true)
	var existing := {"towers": data.towers.definitions, "nodes": data.research.nodes, "enemies": data.mobs.definitions}
	for key in KEYS:
		for row in package.get(key, []):
			if existing[key].has(row.id):
				return "%s ID 충돌 · %s" % [CONTENT_NAMES[key], row.id]
			candidate[key].append(row)
		if candidate[key].size() > MAX_ADDED_PER_KIND:
			return "활성 모드의 %s 추가 한도를 초과했습니다." % CONTENT_NAMES[key]
	var preview := BattleData.new(candidate)
	for error in [preview.towers.error, preview.mobs.error, preview.research.error]:
		if not error.is_empty():
			return error
	if not _bounded_research(preview.research, candidate.nodes):
		return "연구 선행 경로가 너무 복잡합니다."
	data = preview
	for key in KEYS:
		appended[key] = candidate[key]
	applied[id] = true
	return ""

func _bounded_research(graph: ResearchGraph, rows: Array) -> bool:
	var added := {}
	for row in rows:
		added[row.id] = true
	var costs := {}
	var depth := {}
	for id in graph.ordered:
		if not added.has(id):
			continue
		var longest := 0
		for parent in graph.parents[id]:
			longest = maxi(longest, int(depth.get(parent, 0)))
		depth[id] = longest + 1
		costs[id] = _plan_bound(graph.nodes[id].requirements, costs, _base.research)
		if depth[id] > 24 or costs[id] > 128:
			return false
	return true

func _plan_bound(expression: Variant, costs: Dictionary, original: ResearchGraph) -> int:
	if expression == null:
		return 1
	if expression is String:
		if not costs.has(expression):
			costs[expression] = original._plans(expression, {}, {}).size()
		return costs[expression]
	var union: bool = expression.has("any")
	var count := 0 if union else 1
	for term in expression.get("any" if union else "all"):
		var bound := _plan_bound(term, costs, original)
		count = mini(129, count + bound if union else count * bound)
	return count

func _apply_settings(next: Dictionary) -> String:
	if next == requested:
		return ""
	if not _save_settings(next):
		return "모드 설정을 저장할 수 없습니다."
	requested = next
	resolve()
	return ""

func _save_settings(next: Dictionary) -> bool:
	var config := ConfigFile.new()
	for id in next:
		config.set_value("mods", id, true)
	return _write(_path(".enabled.cfg"), config.encode_to_text())

func _write(path: String, contents: String) -> bool:
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	var saved := file.store_string(contents)
	file.close()
	if saved and DirAccess.rename_absolute(temp, path) == OK:
		return true
	DirAccess.remove_absolute(temp)
	return false

func _path(filename: String) -> String:
	return _directory.path_join(filename)
