extends RefCounted
## 战术 v1 存档的读写边界，只处理 JSON，不依赖场景或界面。

## 读取并解析 v1 字典；文件缺失或格式不符时返回空字典，由调用方决定后续处理。
static func read_snapshot(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary and data.get("version", 0) == 1:
		return data
	return {}

## 覆盖写入 JSON 快照并返回文件错误码，让调用方决定如何提示保存失败。
static func write_snapshot(path: String, data: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	return file.get_error()
