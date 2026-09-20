extends "res://tests/tactical/environment_motion_test.gd"
## 绘画场景滚屏测试共用的取帧方法；位移对齐与冻结复用环境测试，不装配任何退役样板。
func screen() -> Image:
	for i in 3: await process_frame
	RenderingServer.force_draw(false)
	var frame: Image=root.get_texture().get_image()
	frame.convert(Image.FORMAT_RGB8)
	return frame
