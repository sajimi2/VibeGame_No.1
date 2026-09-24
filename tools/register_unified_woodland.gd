extends SceneTree
## 只登记生成原稿的主体区域、世界尺寸与28px/m逻辑网格；不改写原始图片。
func _initialize() -> void:
	var folder:="res://assets/environment/painted/woodpath/unified/"
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment/painted/woodpath/catalog.json"))
	var sizes:={"tree_a":4.8,"tree_b":3.6,"tree_c":4.4,"wall_z":2.6,"litter":1.6}
	for id in sizes:
		var source_id:String="wall_z_v4" if id=="wall_z" else id
		var image:=Image.load_from_file(folder+"source/"+source_id+".png")
		if image==null: continue
		var rect:=image.get_used_rect()
		var spec:Dictionary=catalog.wall_z.duplicate(true) if id=="wall_z" else catalog.oak_calm.duplicate(true)
		spec.texture=folder+"source/"+source_id+".png"
		spec.region=[rect.position.x,rect.position.y,rect.size.x,rect.size.y]
		spec.aspect=float(rect.size.y)/rect.size.x
		spec.width=sizes[id]
		spec.pixels_per_meter=preload("res://scripts/presentation/pixel_standard.gd").ENVIRONMENT_PIXELS_PER_METER
		if id.begins_with("tree"):
			spec.anchor=[.5,.97]
			spec.radius=.36 if id=="tree_b" else .42
			spec.shadow_profile="oak"
		elif id=="litter":
			spec={"texture":spec.texture,"region":spec.region,"aspect":spec.aspect,"width":1.6,"anchor":[.5,.65],"shape":"none","depth_box":[1.6,.1,1]}
		catalog[id]=spec
		print(id," logical=",Vector2(sizes[id]*28,sizes[id]*28*spec.aspect).round())
	var file:=FileAccess.open(folder+"catalog.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(catalog,"\t"))
	quit()
