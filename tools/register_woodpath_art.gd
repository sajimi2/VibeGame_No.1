extends SceneTree
## 保存原稿不改像素；登记 alpha 包围盒，运行时 AtlasTexture 直接取原图区域。
func _initialize() -> void:
	var folder:="res://assets/environment/painted/woodpath/"
	var specs:={
		"oak_calm":{"width":4.8,"anchor":[.5,.97],"shape":"cylinder","radius":.42,"height":2.1,"depth_box":[3.8,4.8,3.0],"depth_mode":1},
		"oak_young":{"width":3.2,"anchor":[.5,.97],"shape":"cylinder","radius":.30,"height":2.0,"depth_box":[2.6,4.2,2.4],"depth_mode":1},
		"wall_z":{"width":2.6,"anchor":[.5,.72],"shape":"box","size":[.6,1.05,4.0],"depth_box":[.65,1.45,4.0]},
		"waystation_ruin":{"width":8.0,"anchor":[.5,.75],"shape":"box","size":[5.0,2.4,3.0],"depth_box":[5.0,3.0,3.0]}}
	for id in specs:
		var image:=Image.load_from_file(folder+"source/"+id+".png")
		var rect:=image.get_used_rect()
		specs[id].texture=folder+"source/"+id+".png"
		specs[id].region=[rect.position.x,rect.position.y,rect.size.x,rect.size.y]
		specs[id].aspect=float(rect.size.y)/rect.size.x
		print(id," ",image.get_size()," region=",rect," alpha=",image.detect_alpha())
	specs.waystation_ruin.collision_parts=[{"at":[0,1.1,-1.6],"size":[5.4,2.2,.4]},{"at":[-2.5,1,0],"size":[.4,2,3.2]},{"at":[2.5,1,0],"size":[.4,2,3.2]},{"at":[-1.7,.8,1.6],"size":[1.6,1.6,.4]},{"at":[1.7,.8,1.6],"size":[1.6,1.6,.4]}]
	var file:=FileAccess.open(folder+"catalog.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(specs,"\t"))
	quit()
