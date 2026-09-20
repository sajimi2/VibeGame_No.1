extends SceneTree
## 运行时只加载目标像素尺寸，保留生图原稿供改画；滤波只在离线缩图时执行。
func _initialize() -> void:
	var path: String="res://assets/environment/experiments/painted_cottage/"
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path+"registration.json"))
	var size:=int(config.runtime_canvas)
	var originals: Dictionary={}
	for part in ["walls","roof"]:
		var image:=Image.load_from_file(path+"source/"+part+".png")
		if image==null: quit(1); return
		# 请求尺寸不等于实际输出尺寸；换源须明确确认大小，不能静默沿用旧配准。
		if image.get_size()!=Vector2i.ONE*int(config.source_canvas):
			push_error("插画原稿尺寸与 registration.json 不符："+part)
			quit(1)
			return
		originals[part]=image
	for part in originals:
		var image: Image=originals[part]
		image.resize(size,size,Image.INTERPOLATE_LANCZOS)
		image.save_png(path+part+".png")
	# 内景来自独立生成稿，按其真实尺寸读取，归一化配准不依赖请求像素数。
	var interior:=Image.load_from_file(path+"source/interior.png")
	if interior==null: quit(1); return
	interior.resize(size,size,Image.INTERPOLATE_LANCZOS)
	interior.save_png(path+"interior.png")
	print("PAINTED_COTTAGE: exterior, roof and interior baked at %d square; source preserved"%size)
	quit()
