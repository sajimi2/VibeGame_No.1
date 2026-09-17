extends RefCounted
## I/O boundary for tactical_progress_v1.json. No scene or UI references.
static func read_snapshot(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary and data.get("version", 0) == 1:
		return data
	return {}

static func write_snapshot(path: String, data: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	return file.get_error()
