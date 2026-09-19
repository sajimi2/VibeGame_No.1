extends SceneTree
## 开发期批量出图：只读取保存的模型/动画，按资产生成颜色、深度和双手锚点。
const Gpu=preload("res://scripts/presentation/pixel_frame_gpu.gd")
const Spec=preload("res://scripts/art/baked_human_spec.gd")
var backend: Node
var rig: Node3D
var manifest: Dictionary
var color: Image
var depth: Image
var page:=0
var cursor:=Vector2i.ZERO
var row_height:=0
var count:=0
var output_folder: String
var staging_folder: String
var duplicates: Dictionary={}
var frame_size:=Spec.CELL

func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("角色烘焙需要实际 GPU，请勿传 --headless")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var assets: Array=Spec.ACTIONS.keys()
	for arg in OS.get_cmdline_user_args():
		if arg in Spec.ACTIONS: assets=[arg]; break
	for asset in assets:
		if not await bake(asset):
			quit(1)
			return
	backend.queue_free()
	await process_frame
	quit()

func bake(asset: String) -> bool:
	if is_instance_valid(backend): backend.free()
	frame_size=Spec.cell(asset)
	backend=Gpu.new()
	backend.frame_size=frame_size
	backend.pixel_size=Spec.pixel(asset)
	root.add_child(backend)
	await process_frame
	output_folder=Spec.folder(asset)
	DirAccess.make_dir_recursive_absolute(output_folder)
	staging_folder="res://work/character_bake/"+asset
	DirAccess.make_dir_recursive_absolute(staging_folder)
	rig=load(Spec.source_scene(asset)).instantiate()
	root.add_child(rig)
	await process_frame
	manifest={"version":2,"asset":asset,"cell":frame_size,"pixel_size":Spec.pixel(asset),"pitch":Spec.PITCH,"entries":{},"pages":[],"source_scene":Spec.source_scene(asset),"animation_library":Spec.source_model(asset)}
	manifest.parts=Spec.parts(asset)
	page=0
	count=0
	duplicates.clear()
	_new_page()
	var started:=Time.get_ticks_msec()
	for job in Spec.jobs(asset):
		for move in job.moves:
			for phase in job.frames:
				var anchors: Dictionary=rig.sample_job(job,move,phase)
				var center: Vector3=anchors.pelvis if job.part=="upper" else Spec.CENTER
				backend.set_triangles(rig.geometry(job.part,center))
				for direction in 12:
					if not _capture(job.part,job.id,direction,move,phase,anchors,center):
						rig.free()
						return false
			await process_frame
		print("BAKED ",asset," ",job.part,"/",job.id," frames=",count)
	_save_page()
	manifest.frame_count=count
	# 所有帧验证完才发布；空帧/裁边不会把旧有效清单覆盖为半成品。
	for id in manifest.pages:
		for suffix in [".png","_depth.png"]:
			if DirAccess.copy_absolute(staging_folder+"/"+str(id)+suffix,output_folder+"/"+str(id)+suffix)!=OK:
				push_error("无法发布烘焙图页："+str(id)+suffix)
				rig.free()
				return false
	var file:=FileAccess.open(output_folder+"/atlas.pending.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest))
	file.close()
	assert(DirAccess.rename_absolute(output_folder+"/atlas.pending.json",output_folder+"/atlas.json")==OK)
	print("HUMAN_BAKE: ",asset," ",count," frames, ",page+1," pages, ",(Time.get_ticks_msec()-started)/1000.0," seconds")
	rig.free()
	return true

func _new_page() -> void:
	color=Image.create(1024,1024,false,Image.FORMAT_RGBA8)
	depth=Image.create(1024,1024,false,Image.FORMAT_RGBA8)
	cursor=Vector2i.ZERO
	row_height=0
func _save_page() -> void:
	var id:="page_%02d"%page
	assert(color.save_png(staging_folder+"/"+id+".png")==OK)
	assert(depth.save_png(staging_folder+"/"+id+"_depth.png")==OK)
	manifest.pages.append(id)

## GPU 读回仅存在于此工具；颜色相同但深度不同的帧不合并，防止背向遮挡失真。
func _capture(part: String, action: String, direction: int, move: int, phase: int, anchors: Dictionary, center: Vector3) -> bool:
	var view:=Basis(Vector3.RIGHT,deg_to_rad(Spec.PITCH)).inverse()*Basis(Vector3.UP,direction*PI/6)
	backend.draw(view,Vector3(-.35,.75,.56).normalized())
	backend.color_mesh.force_update_transform()
	backend.depth_mesh.force_update_transform()
	RenderingServer.force_draw(false)
	var packed: Image=backend.viewport.get_texture().get_image()
	var frame:=packed.get_region(Rect2i(0,0,frame_size,frame_size))
	var area:=frame.get_used_rect()
	if not area.has_area() or area.position.x<=0 or area.position.y<=0 or area.end.x>=frame_size or area.end.y>=frame_size:
		frame.save_png(staging_folder+"/rejected_frame.png")
		print("REJECTED_FRAME ",action," direction=",direction," phase=",phase," bounds=",area)
		push_error("出图为空或超出采样框："+action+"；原有效图集保留。")
		return false
	var trim:=area.grow(1)
	var signature:=str(hash(packed.get_data()))
	var metadata: Dictionary
	if duplicates.has(signature):
		metadata=duplicates[signature].duplicate()
	else:
		if cursor.x+trim.size.x>1024:
			cursor=Vector2i(0,cursor.y+row_height)
			row_height=0
		if cursor.y+trim.size.y>1024:
			_save_page()
			page+=1
			_new_page()
		color.blit_rect(packed,trim,cursor)
		depth.blit_rect(packed,Rect2i(trim.position+Vector2i(frame_size,0),trim.size),cursor)
		metadata={"page":page,"rect":[cursor.x,cursor.y,trim.size.x,trim.size.y],"trim":[trim.position.x,trim.position.y,trim.size.x,trim.size.y]}
		duplicates[signature]=metadata.duplicate()
		cursor.x+=trim.size.x
		row_height=maxi(row_height,trim.size.y)
	for id in ["pelvis","grip","support"]:
		var point: Vector3=anchors[id]-center if part=="upper" else anchors[id]
		metadata[id]=[point.x,point.y,point.z]
	manifest.entries[Spec.key(part,action,direction,move,phase)]=metadata
	count+=1
	return true
