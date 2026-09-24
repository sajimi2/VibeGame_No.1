extends RefCounted
## v1/v2 存档边界：版本迁移由库存处理；替换前保留备份，临时文件写完后才提交。

## 读取并解析 v1/v2 字典；文件缺失或格式不符时返回空字典，由调用方决定后续处理。
static func read_snapshot(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary and int(data.get("version", 0)) in [1,2]:
		return data
	return {}

## 备份并替换 JSON 快照，返回文件错误码，让调用方决定如何提示保存失败。
static func write_snapshot(path: String, data: Dictionary) -> Error:
	# 不覆盖无法识别的旧文件；让调用方显示保存失败，便于人工恢复。
	if FileAccess.file_exists(path) and read_snapshot(path).is_empty(): return ERR_FILE_CORRUPT
	if FileAccess.file_exists(path):
		var previous := read_snapshot(path)
		var backup := path + (".v1.bak" if int(previous.get("version",1)) == 1 else ".bak")
		if not FileAccess.file_exists(backup) or int(previous.get("version",1)) == 2:
			var copied := DirAccess.copy_absolute(path,backup)
			if copied != OK: return copied
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return error
	return DirAccess.rename_absolute(path + ".tmp",path)
