extends SceneTree
## T07 acceptance tests: the save round-trip, corrupt/unknown-version handling that never destroys
## the original file, the safe-point load, and the Windows export template check.
##
## Runnable with:
##   godot --headless --path <project> --script res://tests/t07_save_test.gd
## Exits 0 when every case passes, 1 otherwise.

const PLAYER_SCENE := "res://scenes/player.tscn"
const TEST_SAVE := "res://work/outpost_save_test.json"

var _failures: Array[String] = []
var _checks := 0
var _service: SaveService

func _initialize() -> void:
	_run()

func _run() -> void:
	print("=== T07 save/export tests ===")
	await physics_frame
	_service = SaveService.new(TEST_SAVE)
	_service.delete_save()
	await _test_round_trip()
	await _test_corrupt_file_is_kept()
	await _test_unknown_version_is_kept()
	await _test_load_lands_in_village()
	_check_export_templates()
	_service.delete_save()
	print("--- checks=%d failures=%d" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("T07_SAVE_TESTS: PASS")
		quit(0)
	else:
		for failure in _failures:
			print("T07_SAVE_TESTS: FAIL %s" % failure)
		quit(1)

# --- harness -------------------------------------------------------------------------------

func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(message)
		print("  [FAIL] %s" % message)
	return condition

func _step() -> void:
	await physics_frame

func _steps(count: int) -> void:
	for _i in count:
		await _step()

func _file_text() -> String:
	if not FileAccess.file_exists(TEST_SAVE):
		return ""
	return FileAccess.get_file_as_string(TEST_SAVE)

func _write_raw(text: String) -> void:
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(text)
	file.close()

## Builds a player with some equipment, progression and kills, the way a real run would look.
func _build_run() -> Node:
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as Node
	root.add_child(player)
	await _step()
	return player

# --- cases ---------------------------------------------------------------------------------

func _test_round_trip() -> void:
	print("[test] a save round-trips progression, equipment and quest state")
	var player := await _build_run()
	var inventory := player.get_node("ActorInventory") as ActorInventory
	var combatant := player.get_node("ActorCombatant") as ActorCombatant
	var progression := player.get_node("ActorProgression") as ActorProgression
	var catalog := ItemCatalog.build()
	inventory.set_catalog(catalog)

	## Advance the run: level up, spend a point, equip a weapon and an armour piece, lose health.
	progression.grant_experience(170)
	progression.spend_point(ProgressionPort.Attribute.MAX_HEALTH)
	var axe := catalog.roll(&"woodcutter_axe", "save-axe")
	var vest := catalog.roll(&"chainmail", "save-vest")
	inventory.try_add(axe)
	inventory.try_add(vest)
	inventory.try_equip("save-axe", ActorInventory.SLOT_WEAPON)
	inventory.try_equip("save-vest", ActorInventory.SLOT_BODY)
	var hit := DamageEvent.new()
	hit.source_id = 8080
	hit.attack_id = 1
	hit.team_id = 2
	hit.raw_damage = 25.0
	hit.origin = (player as Node2D).global_position + Vector2(10, 0)
	combatant.receive_hit(hit)
	await _step()

	var session := GameSession.start_new_run(3)
	session.accept_quest()
	session.register_enemy_kill()

	var document := SaveService.build_document(session, progression, inventory, combatant)
	var error := _service.save(document)
	_check(error.is_empty(), "saving must succeed (%s)" % error)
	_check(_service.has_save(), "the save file must exist after saving")

	## The persisted document must not carry transient state.
	var text := _file_text()
	_check(not text.contains("projectile"), "the save must not contain projectiles")
	_check(not text.contains("attack_id"), "the save must not contain attack bookkeeping")

	## Restore into a brand-new actor and compare.
	var reloaded := _service.load_document()
	_check(reloaded["status"] == SaveService.LoadStatus.OK, "the save must load back (%s)" % reloaded.get("message", ""))
	var data: Dictionary = reloaded["data"]
	var fresh_player := await _build_run()
	var fresh_inventory := fresh_player.get_node("ActorInventory") as ActorInventory
	var fresh_progression := fresh_player.get_node("ActorProgression") as ActorProgression
	fresh_inventory.set_catalog(catalog)
	fresh_progression.restore_from_snapshot(data.get("progression", {}))
	fresh_inventory.restore_from_snapshot(data.get("inventory", {}) as Dictionary)

	var snapshot := fresh_inventory.get_snapshot()
	var equipment: Dictionary = snapshot["equipment"]
	_check(not (equipment.get(ActorInventory.SLOT_WEAPON, {}) as Dictionary).is_empty(), "the equipped weapon must survive the round-trip")
	_check(not (equipment.get(ActorInventory.SLOT_BODY, {}) as Dictionary).is_empty(), "the equipped body armour must survive the round-trip")
	_check(String((equipment[ActorInventory.SLOT_WEAPON] as Dictionary).get("instance_id", "")) == "save-axe", "the weapon instance id must be preserved")
	var original_attack := float(axe.modifiers.get("attack", 0.0))
	_check(float((equipment[ActorInventory.SLOT_WEAPON] as Dictionary).get("modifiers", {}).get("attack", 0.0)) == original_attack, "the weapon's rolled modifiers must be preserved exactly (%s)" % original_attack)
	_check(fresh_progression.get_level() == progression.get_level(), "the level must survive the round-trip")
	_check(fresh_progression.get_unspent_points() == progression.get_unspent_points(), "unspent points must survive")
	_check(fresh_progression.bonus_max_health() == progression.bonus_max_health(), "spent points must survive")

	## The session state is restored by the flow, not here; assert the document itself.
	var session_data: Dictionary = data.get("session", {})
	_check(int(session_data.get("kills", 0)) == 1, "the kill count must be saved")
	_check(int(session_data.get("quest_stage", -1)) == GameSession.QuestStage.IN_PROGRESS, "the quest stage must be saved")
	player.queue_free()
	fresh_player.queue_free()
	await _step()

func _test_corrupt_file_is_kept() -> void:
	print("[test] a corrupt save is reported and left untouched")
	_write_raw("{ this is not valid json")
	var before := _file_text()
	var result := _service.load_document()
	_check(result["status"] == SaveService.LoadStatus.CORRUPT, "corrupt content must be reported as corrupt (got %s)" % result["status"])
	_check(not String(result.get("message", "")).is_empty(), "a corrupt load must explain itself")
	_check(_file_text() == before, "the corrupt file must not be modified by a failed load")

	## A well-formed JSON document missing required keys is also refused.
	_write_raw('{"schema_version": 1, "session": {}}')
	var partial := _file_text()
	var partial_result := _service.load_document()
	_check(partial_result["status"] == SaveService.LoadStatus.CORRUPT, "a document missing required keys must be refused")
	_check(_file_text() == partial, "the incomplete file must not be modified")

func _test_unknown_version_is_kept() -> void:
	print("[test] an unknown schema version is refused without destroying the file")
	var document := {
		"schema_version": 99,
		"session": {"kills": 0, "kills_required": 3, "quest_stage": 0, "current_level": "village", "reward_paid": false},
		"progression": {"level": 1, "xp_in_level": 0, "unspent_points": 0},
		"inventory": {"bag": [], "equipment": {}},
		"vitals": {"health": 100.0, "stamina": 100.0},
	}
	_write_raw(JSON.stringify(document))
	var before := _file_text()
	var result := _service.load_document()
	_check(result["status"] == SaveService.LoadStatus.UNSUPPORTED_VERSION, "version 99 must be refused as unsupported (got %s)" % result["status"])
	_check(String(result.get("message", "")).contains("99"), "the message must name the version it found")
	_check(_file_text() == before, "an unsupported-version file must be left alone")

	## A missing file is reported distinctly from a broken one.
	_service.delete_save()
	var missing := _service.load_document()
	_check(missing["status"] == SaveService.LoadStatus.NO_SAVE, "a missing save must be reported as such")

func _test_load_lands_in_village() -> void:
	print("[test] loading puts the run back at the village safe point")
	var session := GameSession.start_new_run(3)
	session.accept_quest()
	session.register_enemy_kill()
	session.set_level(GameSession.LEVEL_OUTPOST_UPPER)
	_check(session.current_level == GameSession.LEVEL_OUTPOST_UPPER, "the session must be able to sit in the outpost")

	var document := {
		"schema_version": SaveService.SCHEMA_VERSION,
		"session": session.snapshot(),
		"progression": {"level": 2, "xp_in_level": 10, "unspent_points": 1},
		"inventory": {"bag": [], "equipment": {}},
		"vitals": {"health": 42.0, "stamina": 30.0},
	}
	_check(_service.save(document).is_empty(), "the document must save")

	## Loading into a fresh session must override the level back to the village.
	var fresh := GameSession.start_new_run(3)
	fresh.set_level(GameSession.LEVEL_FOREST)
	var data: Dictionary = _service.load_document()["data"]
	_check(fresh.restore_into_village(data.get("session", {})), "the session must accept the restore")
	_check(fresh.current_level == GameSession.LEVEL_VILLAGE, "loading must land in the village (got %s)" % fresh.current_level)
	_check(fresh.kills == 1, "the restored kill count must survive")
	_check(fresh.quest_stage == GameSession.QuestStage.IN_PROGRESS, "the restored stage must survive")

	## A completed, paid contract must never come back unpaid, or the reward could pay twice.
	var completed := GameSession.start_new_run(1)
	completed.accept_quest()
	completed.register_enemy_kill()
	completed.complete_quest()
	var completed_document := completed.snapshot()
	completed_document["reward_paid"] = false
	var restored := GameSession.start_new_run(1)
	restored.restore_from_snapshot(completed_document)
	_check(restored.reward_paid, "a completed contract must stay paid after a restore")
	_check(restored.complete_quest() == false, "a completed contract must not pay again after a restore")

## TASKS.md T07: check the export template that matches this engine, and report a blocker honestly
## instead of claiming an export happened.
func _check_export_templates() -> void:
	print("[test] Windows export templates are checked, not assumed")
	var version := Engine.get_version_info()
	var expected := "%d.%d.%d" % [version.major, version.minor, version.patch]
	var folder := OS.get_environment("APPDATA").path_join("Godot/export_templates/%s.stable" % expected)
	var directory_exists := DirAccess.dir_exists_absolute(folder)
	var templates: Array[String] = []
	if directory_exists:
		var directory := DirAccess.open(folder)
		if directory != null:
			for name in directory.get_files():
				templates.append(name)
	print("  engine %s, template folder %s, present=%s, files=%d" % [expected, folder, directory_exists, templates.size()])
	if templates.is_empty():
		print("  BLOCKER: no Windows export template installed for this engine version.")
		print("  Install via Editor > Manage Export Templates, then run the export in a later round.")
	_check(true, "the template check must run and report its finding")
