extends SceneTree
## 局部对照的发布工具：读取已保存原稿，生成真实小尺寸运行图；绝不覆盖原图和正式目录。
const OUT="res://assets/environment/painted/density_trial/"
const PPM=37.5
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var records:={}
	var baked:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment/painted/courtyard/baked.json"))
	var wall:Image=Image.load_from_file("res://assets/environment/painted/courtyard/source/wall.png")
	var c:Array=baked.wall.crop
	records.wall=publish(wall.get_region(Rect2i(c[0],c[1],c[2],c[3])),Vector2i(147,77),"wall")
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment/painted/woodpath/unified/catalog.json"))
	var vertical:Image=Image.load_from_file(catalog.wall_z.texture)
	c=catalog.wall_z.region
	var target:=Vector2i(98,roundi(98.0*c[3]/c[2]))
	records.wall_z=publish(vertical.get_region(Rect2i(c[0],c[1],c[2],c[3])),target,"wall_z")
	var chest:Image=Image.load_from_file("res://assets/environment/painted/woodpath/source/chest_motion.png")
	# 原图2103宽不能整除4；边界分别取整，不把四帧当525.75像素切片。
	for i in 4:
		var left:=roundi(chest.get_width()*i/4.0)
		var right:=roundi(chest.get_width()*(i+1)/4.0)
		records["chest_%d"%i]=publish(chest.get_region(Rect2i(left,0,right-left,chest.get_height())),Vector2i(53,75),"chest_%d"%i)
	FileAccess.open(OUT+"manifest.json",FileAccess.WRITE).store_string(JSON.stringify({"pixels_per_view_meter":PPM,"assets":records},"\t"))
	print("DENSITY_PUBLISH: ",records.size()," textures; originals preserved")
	quit()

func publish(source:Image, target:Vector2i, id:String) -> Dictionary:
	var original:=source.get_size()
	# 宝箱原稿已有硬描边，面积混合会把一像素扣环融成灰边；先取硬边样本用于对照。
	# 墙的完整绘画原稿先滤掉细碎纹理；两类最终都只含目标数量的真实像素。
	source.resize(target.x,target.y,Image.INTERPOLATE_NEAREST if id.begins_with("chest") else Image.INTERPOLATE_LANCZOS)
	for y in target.y:
		for x in target.x:
			var color:=source.get_pixel(x,y)
			color.a=1.0 if color.a>=.5 else 0.0
			source.set_pixel(x,y,color)
	source.save_png(OUT+id+".png")
	return {"source_region_size":[original.x,original.y],"size":[target.x,target.y],"view_size":[target.x/PPM,target.y/PPM]}
