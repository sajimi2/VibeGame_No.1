class_name SaveService
extends RefCounted
## Reads and writes the single save file. It owns the schema, the validation and the safe write.
##
## TASKS.md T07 rules implemented here:
##   - schema v1, saved under user://;
##   - the file holds progression, equipment instances and quest state;
##   - active projectiles, live instance ids and in-combat state are NOT persisted;
##   - a corrupt or unknown-version file produces recoverable feedback and never overwrites itself;
##   - writes go to a temporary file first and only then replace the real one.
##
## The service does not know about scenes: it converts a dictionary to and from disk, and the level
## flow decides what goes in and where the player ends up (the village safe point).

const SCHEMA_VERSION := 1
const DEFAULT_PATH := "user://outpost_save.json"

## Keys of the root document, all required except the ones noted.
const REQUIRED_KEYS: Array[String] = ["schema_version", "session", "progression", "inventory", "vitals"]

enum LoadStatus { OK, NO_SAVE, CORRUPT, UNSUPPORTED_VERSION }

var _path := DEFAULT_PATH

func _init(path := DEFAULT_PATH) -> void:
	_path = path

func get_path() -> String:
	return _path

func has_save() -> bool:
	return FileAccess.file_exists(_path)

## Removes the save file; used by tests and by a future "new game" flow.
func delete_save() -> bool:
	if not has_save():
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(_path)) == OK

# --- writing -------------------------------------------------------------------------------

## Writes a save document. Returns an empty string on success, or a human-readable error.
func save(document: Dictionary) -> String:
	var payload := document.duplicate(true)
	payload["schema_version"] = SCHEMA_VERSION
	var text := JSON.stringify(payload, "  ")
	## Temp file first: a crash or a full disk leaves the previous save intact.
	var temp_path := _path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return "无法写入临时存档（错误 %d）" % FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	var absolute_temp := ProjectSettings.globalize_path(temp_path)
	var absolute_target := ProjectSettings.globalize_path(_path)
	var directory := DirAccess.open(ProjectSettings.globalize_path(_path).get_base_dir())
	if directory == null:
		return "无法打开存档目录"
	## rename() replaces an existing target on the platforms this project targets.
	var error := directory.rename(absolute_temp, absolute_target)
	if error != OK:
		DirAccess.remove_absolute(absolute_temp)
		return "替换存档失败（错误 %d）" % error
	return ""

# --- reading -------------------------------------------------------------------------------

## Reads the save. On any failure the file is left exactly as it was, and the returned message
## tells the player what happened.
func load_document() -> Dictionary:
	var result := {"status": LoadStatus.NO_SAVE, "message": "没有存档", "data": {}}
	if not has_save():
		return result
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		result["status"] = LoadStatus.CORRUPT
		result["message"] = "无法读取存档（错误 %d）" % FileAccess.get_open_error()
		return result
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		result["status"] = LoadStatus.CORRUPT
		result["message"] = "存档内容已损坏，原文件保持不动"
		return result
	var document := parsed as Dictionary
	var version := int(document.get("schema_version", -1))
	if version != SCHEMA_VERSION:
		result["status"] = LoadStatus.UNSUPPORTED_VERSION
		result["message"] = "存档版本 %d 不受支持（当前 %d），原文件保持不动" % [version, SCHEMA_VERSION]
		return result
	var missing := _missing_keys(document)
	if not missing.is_empty():
		result["status"] = LoadStatus.CORRUPT
		result["message"] = "存档缺少字段：%s，原文件保持不动" % ", ".join(missing)
		return result
	result["status"] = LoadStatus.OK
	result["message"] = ""
	result["data"] = document
	return result

func _missing_keys(document: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	for key in REQUIRED_KEYS:
		if not document.has(key):
			missing.append(key)
	return missing

# --- building a document -------------------------------------------------------------------

## Collects the persistable state. Deliberately excludes anything transient: no projectiles, no
## in-combat flags, no live instance ids of actors.
static func build_document(
	session: GameSession,
	progression: ActorProgression,
	inventory: ActorInventory,
	combatant: ActorCombatant) -> Dictionary:
	var vitals := {
		"health": combatant.get_health() if combatant != null else 0.0,
		"stamina": combatant.get_stamina() if combatant != null else 0.0,
	}
	return {
		"schema_version": SCHEMA_VERSION,
		"session": session.snapshot() if session != null else {},
		"progression": progression.get_snapshot() if progression != null else {},
		"inventory": inventory.get_snapshot() if inventory != null else {},
		"vitals": vitals,
	}
