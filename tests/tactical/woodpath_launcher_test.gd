extends "res://tests/startup_smoke.gd"
## 用实际BAT调用；继承启动测试的进度隔离，只额外检查独立窗口默认全屏。
func run() -> void:
	await process_frame
	check(DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN,DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN],"BAT launches a fullscreen game window")
	await super.run()
