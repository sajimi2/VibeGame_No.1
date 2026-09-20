extends Node3D
## 运行时只查离线图集与握点；没有骨架、SubViewport、Image 创建或图像读回。
const Spec = preload("res://scripts/art/baked_human_spec.gd")
const ShaderFile = preload("res://scripts/presentation/baked_human.gdshader")
const Store = preload("res://scripts/art/atlas_store.gd")
static var shared: Dictionary = {}
var asset_id := "player"
var last_support := Vector3.ZERO
var opacity := 1.0
var tint := Color.WHITE
var ground_basis := Basis.IDENTITY
var ground_origin := Vector3.ZERO
var grounded_death := false
var actor: CharacterBody3D
var manifest: Dictionary = {}
var frame_size := Spec.CELL
var pixel_size := Spec.pixel("player")
var pages: Array[Texture2D] = []
var depths: Array[Texture2D] = []
var layers: Dictionary = {}
var parts: Array = ["upper","lower"]
var enabled := true
var active := false
var last_keys := {}
var frame_changes := 0
var store_revision := -1
var last_grip := Vector3.ZERO

## 玩家/敌人共用一个播放模块；同类实例共享已导入图页与元数据，不重复解析。
func setup(player: CharacterBody3D, asset := "player") -> bool:
	actor=player
	asset_id=asset
	var folder:=Spec.folder(asset)
	var path:=folder+"/atlas.json"
	if not FileAccess.file_exists(path): return false
	if not shared.has(asset):
		var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
		if int(data.get("version",0))!=2: return false
		var colors: Array[Texture2D]=[]
		var depth_pages: Array[Texture2D]=[]
		for page in data.pages:
			colors.append(load(folder+"/"+str(page)+".png"))
			depth_pages.append(load(folder+"/"+str(page)+"_depth.png"))
		shared[asset]={"manifest":data,"pages":colors,"depths":depth_pages}
	manifest=shared[asset].manifest
	parts=manifest.get("parts",["upper","lower"])
	frame_size=int(manifest.cell)
	pixel_size=float(manifest.pixel_size)
	pages=shared[asset].pages
	depths=shared[asset].depths
	for part in parts:
		var body := _card(false)
		var occlusion := _card(true)
		var shadow := Sprite3D.new()
		shadow.pixel_size=pixel_size
		shadow.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
		shadow.alpha_cut=SpriteBase3D.ALPHA_CUT_DISCARD
		shadow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		add_child(shadow)
		layers[part]={"body":body,"occlusion":occlusion,"shadow":shadow,"key":""}
	return true

func _card(occlusion: bool) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size=Vector2.ONE
	item.mesh=quad
	item.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	# 灰色遮挡层在正文之前绘制；共享深度解码，但不写场景深度、不改变正文遮挡。
	if occlusion:
		var shader := Shader.new()
		shader.code="#define OCCLUSION_PASS\n"+ShaderFile.code
		material.shader=shader
		material.render_priority=-1
	else: material.shader=ShaderFile
	item.material_override=material
	add_child(item)
	return item

## 选帧、世界握点与阴影同帧刷新；人物只有这一条播放路径，缺失资产由验证阻止发布。
func apply_frame(state: Dictionary) -> bool:
	var selected := Spec.select(state,asset_id) if enabled and actor.camera!=null else {}
	active=not selected.is_empty() and parts.all(func(part):return selected.has(part) and manifest.entries.has(selected[part])) and absf(rad_to_deg(actor.camera.rotation.x)-Spec.PITCH)<0.1
	visible=active
	if not active: return false
	if store_revision!=Store.revision:
		store_revision=Store.revision
		for layer in layers.values(): layer.key=""
	last_keys=selected
	var pelvis := Vector3.ZERO if parts==["full"] else _vector(manifest.entries[selected.lower].pelvis)
	var yaw := Basis(Vector3.UP,actor.camera.rotation.y+int(state.direction)*PI/6)
	for part in parts:
		var layer: Dictionary=layers[part]
		var entry: Dictionary=manifest.entries[selected[part]]
		var pivot: Vector3=pelvis if part=="upper" else Spec.CENTER
		var origin: Vector3=ground_origin if grounded_death else actor.global_position
		var world := origin+ground_basis*yaw*pivot
		var trim: Array=entry.trim
		var dimensions := Vector2(trim[2],trim[3])
		layer.size=dimensions*pixel_size
		var shift := Vector2(float(trim[0])+dimensions.x*0.5-frame_size*0.5,frame_size*0.5-float(trim[1])-dimensions.y*0.5)
		# 改变裁片尺寸只缩放单位四边形，不逐帧重建 QuadMesh 并上传网格。
		var basis: Basis=ground_basis*actor.camera.global_basis*Basis.from_scale(Vector3(layer.size.x,layer.size.y,1))
		layer.body.global_transform=Transform3D(basis,world+ground_basis*actor.camera.global_basis*Vector3(shift.x,shift.y,0)*pixel_size)
		layer.occlusion.global_transform=layer.body.global_transform
		layer.occlusion.visible=actor.hp>0
		layer.shadow.global_transform=Transform3D(Basis(Vector3.UP,actor.camera.rotation.y).scaled(Vector3(1,1/cos(deg_to_rad(Spec.PITCH)),1)),world)
		layer.shadow.offset=shift
		layer.shadow.visible=actor.hp>0
		for item in [layer.body,layer.occlusion]:
			item.material_override.set_shader_parameter("tint",tint)
			item.material_override.set_shader_parameter("opacity",opacity)
			item.material_override.set_shader_parameter("depth_axis",actor.camera.global_basis.inverse()*ground_basis*actor.camera.global_basis.z)
		if layer.key!=selected[part]:
			layer.key=selected[part]
			frame_changes+=1
			var at := Vector2(entry.rect[0],entry.rect[1])
			var rect := Vector4(at.x/1024,at.y/1024,dimensions.x/1024,dimensions.y/1024)
			for item in [layer.body,layer.occlusion]:
				item.material_override.set_shader_parameter("color_atlas",pages[int(entry.page)])
				item.material_override.set_shader_parameter("depth_atlas",depths[int(entry.page)])
				item.material_override.set_shader_parameter("frame_rect",rect)
				item.material_override.set_shader_parameter("depth_rect",rect)
			var texture := AtlasTexture.new()
			texture.atlas=pages[int(entry.page)]
			texture.region=Rect2(at,dimensions)
			layer.shadow.texture=texture
			# 人工补色只替换颜色，深度仍来自同一源模型；来源校验禁止画出没有深度的新轮廓。
			var override:=Store.lookup(asset_id+"_baked",selected[part],Vector2i.ONE*frame_size)
			if not override.is_empty():
				var region:=Rect2(Vector2(entry.trim[0],entry.trim[1]),dimensions)
				var uv:=Vector4(region.position.x/frame_size,region.position.y/frame_size,dimensions.x/frame_size,dimensions.y/frame_size)
				var edited: Texture2D=override.texture
				# AtlasTexture 在 shader uniform 中不自动裁片；显式还原到原图 UV。
				if edited is AtlasTexture:
					uv=Vector4((edited.region.position.x+region.position.x)/edited.atlas.get_width(),(edited.region.position.y+region.position.y)/edited.atlas.get_height(),dimensions.x/edited.atlas.get_width(),dimensions.y/edited.atlas.get_height())
					edited=edited.atlas
				for item in [layer.body,layer.occlusion]:
					item.material_override.set_shader_parameter("color_atlas",edited)
					item.material_override.set_shader_parameter("frame_rect",uv)
				var shadow_texture:=AtlasTexture.new()
				shadow_texture.atlas=override.texture
				shadow_texture.region=region
				layer.shadow.texture=shadow_texture
	# 整身图集与分层角色共用逐像素提示，不再计算两层边缘的联合轮廓。
	if parts==["full"]: return true
	var upper: Dictionary=manifest.entries[selected.upper]
	var bow: bool=selected.upper.contains("/bow_")
	last_grip=actor.global_position+yaw*(pelvis+_vector(upper.support if bow else upper.grip))
	last_support=actor.global_position+yaw*(pelvis+_vector(upper.support))
	var override:=Store.lookup(asset_id+"_baked",selected.upper,Vector2i.ONE*frame_size)
	if not override.is_empty() and override.anchors.has("grip"):
		var hand:=_vector(upper.support if bow else upper.grip)
		var projected:=Basis(Vector3.RIGHT,deg_to_rad(Spec.PITCH)).inverse()*Basis(Vector3.UP,int(state.direction)*PI/6)*hand
		var original:=Vector2(frame_size*0.5+projected.x/pixel_size,frame_size*0.5-projected.y/pixel_size)
		var edited:=Vector2(override.anchors.grip[0],override.anchors.grip[1])
		last_grip+=actor.camera.global_basis*Vector3(edited.x-original.x,original.y-edited.y,0)*pixel_size
	return true

## 提示层只按存活/显示状态启用；真正被挡的像素交给 GPU，不受单条中心射线限制。
func refresh_occlusion_visibility() -> void:
	for layer in layers.values(): layer.occlusion.visible = active and actor.hp>0

static func _vector(values: Array) -> Vector3:
	return Vector3(values[0],values[1],values[2])
