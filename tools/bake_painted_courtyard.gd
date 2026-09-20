extends SceneTree
## 将各尺寸原稿裁到实际 alpha 内容，再按统一屏幕密度生成运行图；只在制作时运行。
const FOLDER="res://assets/environment/painted/courtyard/"
func _initialize() -> void:
	var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FOLDER+"catalog.json"))
	var output: Dictionary={}
	DirAccess.make_dir_recursive_absolute(FOLDER+"textures")
	for id in catalog.assets:
		var spec: Dictionary=catalog.assets[id]
		var source:=Image.load_from_file(FOLDER+"source/"+id+".png")
		if source==null: quit(1); return
		var source_size:=source.get_size()
		var bounds:=Rect2i(Vector2i.ZERO,source_size)
		if not spec.get("tile",false):
			# 弱透明的边缘光晕不算物件轮廓，避免空白边距把小桶缩成针尖。
			var minimum:=source_size
			var maximum:=Vector2i.ZERO
			for y in source_size.y:
				for x in source_size.x:
					if source.get_pixel(x,y).a>.5:
						minimum=minimum.min(Vector2i(x,y))
						maximum=maximum.max(Vector2i(x,y))
			bounds=Rect2i(minimum,maximum-minimum+Vector2i.ONE)
			if not bounds.has_area(): push_error("无有效 alpha 轮廓："+id); quit(1); return
		var image:=source.get_region(bounds)
		var width: int=int(spec.get("pixels",round(float(spec.get("width",1))*float(catalog.pixels_per_view_meter))))
		var height:=maxi(1,roundi(width*float(bounds.size.y)/bounds.size.x))
		image.resize(width,height,Image.INTERPOLATE_LANCZOS)
		image.save_png(FOLDER+"textures/"+id+".png")
		output[id]={"source_size":[source_size.x,source_size.y],"crop":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y],"size":[width,height],"aspect":float(height)/width}
	FileAccess.open(FOLDER+"baked.json",FileAccess.WRITE).store_string(JSON.stringify(output,"\t"))
	print("COURTYARD_BAKE: ",output.size()," assets, source preserved")
	quit()
