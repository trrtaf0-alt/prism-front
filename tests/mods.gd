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
	await _expanded(ui, reloaded, installed)
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

func _expanded(ui: Control, library: ModLibrary, installed: String) -> void:
	var map := BattleData.read_json("res://data/sample_map.json")
	map.name = "역방향 실험장"
	var original_spawn: Array = map.spawn
	map.spawn = map.exit
	map.exit = original_spawn
	map.path.reverse()
	for row in map.tiles.size():
		map.tiles[row] = map.tiles[row].replace("S", "s").replace("E", "S").replace("s", "E")
	var sprite := Image.create_empty(24, 24, false, Image.FORMAT_RGBA8)
	sprite.fill(Color("#52ffbb"))
	var sample := AudioStreamWAV.new()
	sample.mix_rate = 8000
	var silence := PackedByteArray()
	silence.resize(800)
	sample.data = silence
	var wav_path := _workspace.path_join("test.wav")
	_check(sample.save_to_wav(wav_path) == OK, "create genuine WAV fixture")
	_files.append(wav_path)
	var example := _fixture("expanded", {
		"enemies.json": {"enemies": [{
			"id": "qa_boss", "name": "테스트 보스", "boss": true, "shape": "boss", "color": "#50efff",
			"health": 400, "speed": 0.2, "reward": 50, "reward_rp": 5, "armor": 0,
			"phases": [{"threshold": 0.5, "speed_multiplier": 1.5, "shield": 12}],
		}]},
		"campaign.json": {"map": map, "final_wave": 2, "boss_id": "qa_boss", "waves": [
			{"wave": 1, "count": 2, "interval": 0.15, "reward": 17, "spawns": [
				{"enemy": "normal", "count": 1}, {"enemy": "swift", "count": 1, "interval": 0.75},
			]},
			{"wave": 2, "count": 2, "interval": 0.1, "spawns": [{"enemy": "normal", "count": 1}]},
		]},
		"tower_overrides.json": {"tower_01": {"damage": 3, "cost": 12}},
		"assets.json": {"towers": {"tower_01": "assets/sprite.png"}, "enemies": {"qa_boss": "assets/sprite.png"},
			"audio": {"patrol": "assets/patrol.ogg", "wave": "assets/test.wav"}},
		"assets/sprite.png": sprite.save_png_to_buffer(),
		"assets/patrol.ogg": FileAccess.get_file_as_bytes("res://assets/music/neon_watch.ogg"),
		"assets/test.wav": FileAccess.get_file_as_bytes(wav_path),
	}, [], 2)
	var installation := library.install(example)
	_check(installation.is_empty() and library.data == _base, "format 2 ZIP with nested media installs disabled: " + installation)
	_check(library.set_enabled("expanded", true).is_empty() and library.applied.has("expanded"),
		"format 2 activation: " + str(library.problems))
	if not library.applied.has("expanded"):
		return
	var checker := ModLibrary.new(installed, _base)
	_check(checker.applied.has("expanded") and checker.data.tower_sprite("tower_01") != null, "expanded ZIP and media bindings survive reload")
	ui.start_game()
	var sim: Battle = ui.battle
	var audio := root.get_node("Sound")
	_check(sim.field.title == "역방향 실험장" and sim.field.start == Vector2i(29, 9), "new game loads full custom path")
	_check(sim.tower_definition("tower_01").damage == 3 and sim.tower_definition("tower_01").cost == 12, "base tower patch reaches combat")
	_check(sim.tower_definition("tower_01").refund == 12, "base refund follows patched cost")
	_check(audio._music[&"patrol"].stream == sim.data.audio("patrol") and audio._voices[&"wave"].stream == sim.data.audio("wave"), "music and effect override the existing players")
	_check(sim.data.audio("patrol") is AudioStreamOggVorbis and sim.data.audio("patrol").loop \
		and sim.data.audio("wave") is AudioStreamWAV, "Ogg music loops and WAV effects use the installed file")
	_check(ui.field._custom_towers.has("tower_01") and ui.field._mobs._custom_shapes.has("qa_boss"), "tower and enemy textures have live render batches")
	_check(sim.preview_wave() == {"normal": 1, "swift": 1} and sim.start_wave() and sim.enemies[0].definition.id == "normal", "scripted composition is previewed and spawns in order")
	sim._dispatch(0.5)
	_check(sim.enemies.size() == 1, "next group delay overrides the wave interval")
	sim._dispatch(0.25)
	_check(sim.enemies.size() == 2 and sim.enemies[1].definition.id == "swift", "next group spawns on schedule")
	for unit: Battle.Drone in sim.enemies:
		sim._apply_damage(unit, 1_000_000, Vector2.ZERO)
	sim._remove_drones()
	sim.tick(0.0)
	_check(not sim.active and sim.data.wave_reward(1) == 17 and sim.preview_wave().has("qa_boss"), "custom reward and boss preview use campaign data")
	_check(sim.start_wave() and sim.bosses.size() == 1 and sim.bosses[0].maximum_health == 400, "replacement boss spawns once with mod HP")
	if sim.bosses.is_empty():
		return
	var boss: Battle.Drone = sim.bosses[0]
	sim._apply_damage(boss, 201, Vector2.ZERO)
	sim.tick(0.0)
	_check(boss.mob.phase == 1 and boss.shield_hp == 12, "custom health threshold invokes real phase logic")
	ui.field._update_batches()
	if "--visual" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		_check(ui.field._mobs.bodies[ui.field._mobs._custom_shapes.qa_boss].multimesh.visible_instance_count == 1, "custom boss renderer submits one body")
	sim._apply_damage(boss, 1_000_000, Vector2.ZERO)
	sim._remove_drones()
	sim.tick(0.1)
	_check(sim.active and not sim.won and sim.enemies.size() == 1, "boss death waits for scheduled survivors")
	for unit: Battle.Drone in sim.enemies:
		sim._apply_damage(unit, 1_000_000, Vector2.ZERO)
	sim._remove_drones()
	sim.tick(0.0)
	_check(sim.won and not sim.start_wave() and ui.modal_kind == "victory", "campaign clears at wave two and blocks wave three")
	var conflict := _fixture("second-campaign", {"campaign.json": {"final_wave": 3}}, ["expanded"], 2)
	var broken := _fixture("bad-roster", {"campaign.json": {"waves": [{"wave": 1, "count": 2,
		"spawns": [{"enemy": "unknown", "count": 2}]}]}}, [], 2)
	_check(library.install(conflict).is_empty() and library.set_enabled("second-campaign", true).is_empty() \
		and library.problems.has("second-campaign"), "second campaign cannot silently overwrite an active one")
	_check(library.set_all(false).is_empty() and library.install(broken).is_empty() \
		and library.set_enabled("bad-roster", true).is_empty() and library.problems.get("bad-roster", "").contains("unknown")
		and library.data == _base, "invalid roster is isolated without changing normal game")
	ui.show_menu()
	ui.start_game()
	_check(sim.won and ui.battle.data.final_wave == 50 and ui.battle.tower_definition("tower_01").damage == 1 \
		and audio._music[&"patrol"].stream == audio._default_music[&"patrol"], "new game restores vanilla without mutating prior run")

func _fixture(id: String, contents: Dictionary, dependencies: Array = [], format: int = 1) -> String:
	var path := _workspace.path_join(id + ".zip")
	var zip := ZIPPacker.new()
	if zip.open(path) != OK:
		return ""
	contents["mod.json"] = {"format": format, "id": id, "name": "검증 " + id, "author": "QA",
		"version": "1.0", "description": "모드 관리 통합 테스트 파일입니다.", "requires": dependencies}
	for filename in contents:
		zip.start_file(filename)
		var item: Variant = contents[filename]
		var bytes: PackedByteArray = item if item is PackedByteArray else str(item if item is String else JSON.stringify(item)).to_utf8_buffer()
		zip.write_file(bytes)
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
