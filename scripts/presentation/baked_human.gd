extends Node3D
## 运行时只查离线图集与握点；没有骨架、SubViewport、Image 创建或图像读回。
const Spec = preload("res://scripts/art/baked_human_spec.gd")
const ShaderFile = preload("res://scripts/presentation/baked_human.gdshader")
const Store = preload("res://scripts/art/atlas_store.gd")
static var shared: Dictionary = {}
var asset_id := "player"
var current_frame: Dictionary = {}
var last_support := Vector3.ZERO
var opacity := 1.0
var tint := Color.WHITE
var ground_basis := Basis.IDENTITY
var ground_origin := Vector3.ZERO
var grounded_death := false
var actor: CharacterBody3D
var manifest: Dictionary = {}
var pages: Array[Texture2D] = []
var depths: Array[Texture2D] = []
var layers: Dictionary = {}
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
	pages=shared[asset].pages
	depths=shared[asset].depths
	for part in ["upper","lower"]:
		var body := _card(false)
		var outline := _card(true)
		var shadow := Sprite3D.new()
		shadow.pixel_size=Spec.PIXEL
		shadow.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
		shadow.alpha_cut=SpriteBase3D.ALPHA_CUT_DISCARD
		shadow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		add_child(shadow)
		layers[part]={"body":body,"outline":outline,"shadow":shadow,"key":""}
	actor.art_provider=apply_frame
	return true

func _card(outline: bool) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size=Vector2.ONE
	item.mesh=quad
	item.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	# 遮挡轮廓使用独立 shader 变体，正文仍保留真实深度测试。
	if outline:
		var shader := Shader.new()
		shader.code=ShaderFile.code.replace("render_mode unshaded, cull_disabled;","render_mode unshaded, cull_disabled, depth_test_disabled;")
		material.shader=shader
		material.set_shader_parameter("outline_only",true)
		material.render_priority=10
	else: material.shader=ShaderFile
	item.material_override=material
	add_child(item)
	return item

## 选帧、握点与阴影同帧刷新；缺失资产显式回退，完整当前招式均应由离线图覆盖。
func apply_frame(state: Dictionary) -> bool:
	# 已有二维人工稿保持精确帧覆盖优先，未覆盖状态仍使用新图集。
	var legacy:=Store.lookup(asset_id,preload("res://scripts/art/frame_spec.gd").key(state))
	var selected := Spec.select(state,asset_id) if enabled and actor.camera!=null and legacy.is_empty() else {}
	active=not selected.is_empty() and manifest.entries.has(selected.upper) and manifest.entries.has(selected.lower) and absf(rad_to_deg(actor.camera.rotation.x)-Spec.PITCH)<0.1
	visible=active
	actor.sprite.visible=not active
	actor.world_shadow.visible=not active
	if not active: return false
	actor.outline.hide()
	if store_revision!=Store.revision:
		store_revision=Store.revision
		for layer in layers.values(): layer.key=""
	last_keys=selected
	var lower: Dictionary=manifest.entries[selected.lower]
	var pelvis := _vector(lower.pelvis)
	var yaw := Basis(Vector3.UP,actor.camera.rotation.y+int(state.direction)*PI/6)
	for part in ["lower","upper"]:
		var layer: Dictionary=layers[part]
		var entry: Dictionary=manifest.entries[selected[part]]
		var pivot: Vector3=pelvis if part=="upper" else Spec.CENTER
		var origin: Vector3=ground_origin if grounded_death else actor.global_position
		var world := origin+ground_basis*yaw*pivot
		var trim: Array=entry.trim
		var dimensions := Vector2(trim[2],trim[3])
		layer.size=dimensions*Spec.PIXEL
		var shift := Vector2(float(trim[0])+dimensions.x*0.5-32,32-float(trim[1])-dimensions.y*0.5)
		# 改变裁片尺寸只缩放单位四边形，不逐帧重建 QuadMesh 并上传网格。
		var basis: Basis=ground_basis*actor.camera.global_basis*Basis.from_scale(Vector3(layer.size.x,layer.size.y,1))
		layer.body.global_transform=Transform3D(basis,world+ground_basis*actor.camera.global_basis*Vector3(shift.x,shift.y,0)*Spec.PIXEL)
		layer.outline.global_transform=layer.body.global_transform
		layer.outline.visible=actor.occluded and actor.hp>0
		layer.shadow.global_transform=Transform3D(Basis(Vector3.UP,actor.camera.rotation.y).scaled(Vector3(1,1/cos(deg_to_rad(Spec.PITCH)),1)),world)
		layer.shadow.offset=shift
		layer.shadow.visible=actor.hp>0
		for item in [layer.body,layer.outline]:
			item.material_override.set_shader_parameter("tint",tint)
			item.material_override.set_shader_parameter("opacity",opacity)
			item.material_override.set_shader_parameter("depth_axis",actor.camera.global_basis.inverse()*ground_basis*actor.camera.global_basis.z)
		if layer.key!=selected[part]:
			layer.key=selected[part]
			frame_changes+=1
			var at := Vector2(entry.rect[0],entry.rect[1])
			var rect := Vector4(at.x/1024,at.y/1024,dimensions.x/1024,dimensions.y/1024)
			for item in [layer.body,layer.outline]:
				item.material_override.set_shader_parameter("color_atlas",pages[int(entry.page)])
				item.material_override.set_shader_parameter("depth_atlas",depths[int(entry.page)])
				item.material_override.set_shader_parameter("frame_rect",rect)
				item.material_override.set_shader_parameter("depth_rect",rect)
				item.material_override.set_shader_parameter("frame_pixels",dimensions)
			var texture := AtlasTexture.new()
			texture.atlas=pages[int(entry.page)]
			texture.region=Rect2(at,dimensions)
			layer.shadow.texture=texture
			# 人工补色只替换颜色，深度仍来自同一源模型；来源校验禁止画出没有深度的新轮廓。
			var override:=Store.lookup(asset_id+"_baked",selected[part])
			if not override.is_empty():
				var region:=Rect2(Vector2(entry.trim[0],entry.trim[1]),dimensions)
				var uv:=Vector4(region.position.x/64,region.position.y/64,dimensions.x/64,dimensions.y/64)
				var edited: Texture2D=override.texture
				# AtlasTexture 在 shader uniform 中不自动裁片；显式还原到原图 UV。
				if edited is AtlasTexture:
					uv=Vector4((edited.region.position.x+region.position.x)/edited.atlas.get_width(),(edited.region.position.y+region.position.y)/edited.atlas.get_height(),dimensions.x/edited.atlas.get_width(),dimensions.y/edited.atlas.get_height())
					edited=edited.atlas
				for item in [layer.body,layer.outline]:
					item.material_override.set_shader_parameter("color_atlas",edited)
					item.material_override.set_shader_parameter("frame_rect",uv)
				var shadow_texture:=AtlasTexture.new()
				shadow_texture.atlas=override.texture
				shadow_texture.region=region
				layer.shadow.texture=shadow_texture
	# 轮廓读取两层的联合覆盖；相邻纸片的枢轴差转换为同一像素网格偏移。
	for part in ["lower","upper"]:
		var layer: Dictionary=layers[part]
		var other: Dictionary=layers["upper" if part=="lower" else "lower"]
		var material: ShaderMaterial=layer.outline.material_override
		material.set_shader_parameter("other_atlas",other.body.material_override.get_shader_parameter("color_atlas"))
		material.set_shader_parameter("other_rect",other.body.material_override.get_shader_parameter("frame_rect"))
		var delta: Vector3=actor.camera.global_basis.inverse()*(layer.body.global_position-other.body.global_position)
		var scale: Vector2=layer.size/other.size
		material.set_shader_parameter("other_scale",scale)
		material.set_shader_parameter("other_shift",Vector2.ONE*0.5-scale*0.5+Vector2(delta.x,-delta.y)/other.size)
	var upper: Dictionary=manifest.entries[selected.upper]
	var bow: bool=selected.upper.contains("/bow_")
	last_grip=actor.global_position+yaw*(pelvis+_vector(upper.support if bow else upper.grip))
	last_support=actor.global_position+yaw*(pelvis+_vector(upper.support))
	var override:=Store.lookup(asset_id+"_baked",selected.upper)
	if not override.is_empty() and override.anchors.has("grip"):
		var hand:=_vector(upper.support if bow else upper.grip)
		var projected:=Basis(Vector3.RIGHT,deg_to_rad(Spec.PITCH)).inverse()*Basis(Vector3.UP,int(state.direction)*PI/6)*hand
		var original:=Vector2(32+projected.x/Spec.PIXEL,32-projected.y/Spec.PIXEL)
		var edited:=Vector2(override.anchors.grip[0],override.anchors.grip[1])
		last_grip+=actor.camera.global_basis*Vector3(edited.x-original.x,original.y-edited.y,0)*Spec.PIXEL
	current_frame=_legacy_anchor(last_grip)
	var support:=_legacy_anchor(last_support)
	current_frame.support=support.grip
	current_frame.support_depth=support.depth
	actor.grip_pixel=current_frame.grip
	actor.grip_depth=current_frame.depth
	return true

## 保持战斗的世界握点接口不变；源骨架手心是唯一位置来源。
func _legacy_anchor(point: Vector3) -> Dictionary:
	var view: Vector3=actor.camera.global_basis.inverse()*(point-actor.global_position)
	var baseline: Vector3=Vector3.UP*(view.y/actor.camera.global_basis.y.y)
	return {"grip":Vector2(16+view.x/Spec.PIXEL,48-view.y/Spec.PIXEL),"depth":view.z-(actor.camera.global_basis.inverse()*baseline).z}

static func _vector(values: Array) -> Vector3:
	return Vector3(values[0],values[1],values[2])

func _exit_tree() -> void:
	if is_instance_valid(actor):
		actor.art_provider=Callable()
		if is_instance_valid(actor.sprite): actor.sprite.show()
		if is_instance_valid(actor.world_shadow): actor.world_shadow.show()
