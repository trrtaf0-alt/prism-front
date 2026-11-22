extends SceneTree

var _workspace: String
var _checks := 0
var _failures := 0
var _base := BattleData.new()
var _files := PackedStringArray()

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)

func _run() -> void:
	_workspace = "user://mod-qa-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_workspace)
	var installed := _workspace.path_join("installed")
	var library := ModLibrary.new(installed, _base)
	var main_zip := _fixture("fixture", {
		"towers.json": {"towers": [_tower("qa_beam", "qa_beam_design")]},
		"research.json": {"nodes": [_node("qa_beam_design", "survey", "qa_beam")]},
		"enemies.json": {"enemies": [{
			"id": "qa_drone", "name": "검증 드론", "color": "#ff8866", "health": 12,
			"speed": 1.0, "reward": 3, "reward_rp": 1, "first_wave": 1, "weight": 100000,
		}]},
	})
	var addon := _fixture("addon", {"research.json": {"nodes": [_node("qa_connector", "qa_beam_design")]}}, ["fixture"])
	var clashing := _fixture("collision", {"towers.json": {"towers": [_tower("tower_01", "duplicate_unlock")]}})
	var peer_collision := _fixture("peer", {"enemies.json": {"enemies": [{
		"id": "qa_drone", "name": "중복 드론", "color": "#ff8866", "health": 12, "speed": 1,
		"reward": 3, "reward_rp": 1,
	}]}}, ["fixture"])
	var invalid := _fixture("malformed", {"enemies.json": {"enemies": [{"id": "qa_bad", "color": "#ff9988", "health": "bad"}]}})
	var traversal := _fixture("traversal", {"../unexpected.gd": "extends Node\n"})
	var oversized := _fixture("oversized", {"research.json": " ".repeat(ModPackage.MAX_MEMBER + 1)})
	var broken := _fixture("broken", {"research.json": {"nodes": [_node("qa_missing", "does_not_exist")]}})
	var cycle_a := _fixture("cycle-a", {"research.json": {"nodes": [_node("qa_cycle_a", "survey")]}}, ["cycle-b"])
	var cycle_b := _fixture("cycle-b", {"research.json": {"nodes": [_node("qa_cycle_b", "survey")]}}, ["cycle-a"])
	_check(library.data == _base and library.packages.is_empty(), "fresh library uses unchanged base data")
	_check(library.install(main_zip).is_empty() and library.packages.has("fixture") and library.data == _base, "ZIP installs disabled by default")
	_check(FileAccess.file_exists(installed.path_join("fixture.json")) and FileAccess.file_exists(main_zip), "install copies data into private storage without modifying the source ZIP")
	_check(not library.install(main_zip).is_empty(), "duplicate mod ID cannot overwrite installed data")
	_check(not library.install(invalid).is_empty() and not library.install(traversal).is_empty(), "malformed data and unexpected paths are rejected")
	_check(not library.install(oversized).is_empty(), "oversized compressed member is rejected before reading")
	for path in [addon, clashing, peer_collision, broken, cycle_a, cycle_b]:
		_check(library.install(path).is_empty(), "ZIP metadata is installed even if its dependencies are unresolved")
	_check(library.set_enabled("addon", true).is_empty() and library.problems.get("addon", "").contains("fixture"), "missing or disabled dependency blocks actual activation")
	_check(library.set_enabled("fixture", true).is_empty() and library.applied.has("addon"), "dependency becomes active before dependent content")
	_check(library.data.towers.definitions.has("qa_beam") and library.data.research.nodes.has("qa_connector") \
		and library.data.mobs.definitions.has("qa_drone"), "tower, research and enemy use the base registries")
	var active := library.data
	_check(library.set_all(true).is_empty() and library.applied.size() == 2 and library.problems.get("collision", "").contains("tower_01"), "ID conflict is reported and valid mods remain enabled")
	_check(library.problems.get("peer", "").contains("qa_drone"), "two installed mods with the same ID report a conflict")
	_check(library.problems.get("broken", "").contains("선행") and library.problems.get("cycle-a", "").contains("순환"), "invalid graph and cyclic dependencies stay isolated")
	var reloaded := ModLibrary.new(installed, _base)
	_check(reloaded.packages.size() == 7 and reloaded.applied.size() == 2 and reloaded.requested.size() == 7, "ZIP installs and requested activation persist on reload")
	_check(reloaded.set_enabled("fixture", false).is_empty() and reloaded.data == _base and reloaded.problems.has("addon"), "disabling one mod withdraws dependent content")
	_check(reloaded.set_all(false).is_empty() and reloaded.data == _base and reloaded.packages.size() == 7, "disable all restores base and preserves installed packages")
	_check(active.towers.definitions.has("qa_beam"), "an existing gameplay snapshot stays untouched")
	_check(reloaded.remove("fixture").is_empty() and not FileAccess.file_exists(installed.path_join("fixture.json")) \
		and FileAccess.file_exists(installed.path_join("addon.json")) and FileAccess.file_exists(main_zip), "delete only removes the selected installed package")

	var ui = (load("res://scenes/Front.tscn") as PackedScene).instantiate()
	root.add_child(ui)
	var menu_data: BattleData = ui.data
	ui.mod_library = reloaded
	ui.show_mods()
	var manager: ModScreen = ui.mod_screen
	if OS.has_feature("windows") and not root.get_node("Profile").mobile_mode:
		root.files_dropped.emit(PackedStringArray([main_zip]))
	else:
		manager._files_selected(true, PackedStringArray([main_zip]), 0)
	_check(manager._title.text == "검증 fixture" and not manager._switch.button_pressed, "manager automatically displays import result")
	manager._switch.button_pressed = true
	_check(manager._detail.text.contains("활성화됨") and ui.data == menu_data, "switch updates next-run content and reports active state")
	if "--visual" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		var suffix := "-mobile" if root.get_node("Profile").mobile_mode else ""
		_check(root.get_texture().get_image().save_png("res://reports/mod-manager%s.png" % suffix) == OK, "manager screenshot saved")
	ui.start_game(&"easy", {}, 50, 9)
	var sim: Battle = ui.battle
	_check(sim.research.purchase("survey") and sim.research.purchase("qa_beam_design") and sim.install(Vector2i(2, 2), "qa_beam"), "next run unlocks and places installed mod tower")
	_check(sim.start_wave() and sim.preview_wave().has("qa_drone"), "mod enemy participates in normal wave selection")
	var target := sim.spawn(2.0, sim.data.mobs.lookup("qa_drone"))
	var was := target.health
	sim.tick(1.0 / 60.0)
	_check(target.health < was or not sim.enemies.has(target), "modded tower uses existing real attack logic")
	ui.show_menu()
	ui.show_mods()
	manager = ui.mod_screen
	for i in manager._list.item_count:
		if manager._list.get_item_metadata(i) == "fixture":
			manager._select_row(i)
			break
	manager._confirm_delete()
	_check(manager.cancel() and reloaded.packages.has("fixture"), "delete confirmation can be canceled")
	manager._confirm_delete()
	manager._delete_confirmed("fixture")
	_check(not reloaded.packages.has("fixture") and not reloaded.requested.has("fixture"), "confirmed deletion clears installed content and saved activation")
	ui.start_game()
	_check(not ui.battle.data.towers.definitions.has("qa_beam") and ui.battle.data.towers.ids.size() == 44, "new run after deletion loads all base towers")
	sim = null
	ui.queue_free()
	await process_frame
	await process_frame

	for id in reloaded.packages.keys():
		reloaded.remove(id)
	DirAccess.remove_absolute(installed.path_join(".enabled.cfg"))
	DirAccess.remove_absolute(installed)
	for path in _files:
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(_workspace)
	print("Mod checks: %d, failures: %d" % [_checks, _failures])
	quit(int(_failures > 0))

func _fixture(id: String, contents: Dictionary, dependencies: Array = []) -> String:
	var path := _workspace.path_join(id + ".zip")
	var zip := ZIPPacker.new()
	if zip.open(path) != OK:
		return ""
	contents["mod.json"] = {"format": 1, "id": id, "name": "검증 " + id, "author": "QA",
		"version": "1.0", "description": "모드 관리 통합 테스트 파일입니다.", "requires": dependencies}
	for filename in contents:
		zip.start_file(filename)
		var text: String = contents[filename] if contents[filename] is String else JSON.stringify(contents[filename])
		zip.write_file(text.to_utf8_buffer())
		zip.close_file()
	zip.close()
	_files.append(path)
	return path

func _tower(id: String, research_id: String) -> Dictionary:
	return {"id": id, "name": "검증 광선", "description": "테스트용 광선입니다.", "stage": 1, "research_id": research_id,
		"damage": 20, "interval": 0.5, "range": 8, "cost": 10, "attack": "beam", "color": "#ffaa77"}

func _node(id: String, parent: String, tower: String = "") -> Dictionary:
	var node := {"id": id, "name": id, "cost_rp": 2, "stage": 1, "lane": 0, "position": [860, 1430], "requirements": parent}
	if not tower.is_empty():
		node.unlock = {"type": "tower", "id": tower}
	return node
