extends SceneTree
## 显式离线整理共享崖壁母版；不覆盖来源，不在游戏运行时缩图。
func _initialize() -> void:
	var image:=Image.load_from_file("res://assets/environment/painted/terraces/source/cliff_master.png")
	if image==null:
		push_error("断崖母版缺失")
		quit(1)
		return
	image.resize(224,112,Image.INTERPOLATE_NEAREST)
	image.save_png("res://assets/environment/painted/terraces/textures/cliff.png")
	print("TERRACE_ART_BAKED: 224 x 112, source preserved")
	quit()
