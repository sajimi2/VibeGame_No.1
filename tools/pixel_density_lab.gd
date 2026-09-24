extends Node
## 对照入口只改当前驿站一角的表现；复用正式场景/交互，隔离存档，不改玩家和碰撞。
const PPM=37.5
const OUT="res://assets/environment/painted/density_trial/"
var scene:Node3D
var ready_for_test:=false
var calibrated:=false
var zoom_index:=0
var walls:Array=[]
var ground:ShaderMaterial
var chest:Node3D
var original_frames:Array=[]
var trial_frames:Array[AtlasTexture]=[]
var old_chest_pixel:float
var old_chest_position:Vector3
var notice:Label

func _ready() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	scene=load("res://scenes/courtyard_combat.tscn").instantiate()
	add_child(scene)
	while not scene.ready_to_test or not is_instance_valid(scene.objective) or scene.objective.state==null: await get_tree().process_frame
	for enemy in get_tree().get_nodes_in_group("tactical_enemies"):
		enemy.ai_enabled=false
		enemy.hide()
	scene.player.position=Vector3(65,.03,-6)
	for prop in scene.region.props:
		if prop.asset_id in ["wall","wall_z"] and prop.position.x>64 and prop.position.z>-7:
			walls.append({"prop":prop,"texture":prop.art_material.get_shader_parameter("illustration"),"logical":prop.art_material.get_shader_parameter("logical_size"),"size":prop.art.mesh.size,"position":prop.art.position})
	for node in scene.find_children("*","MeshInstance3D",true,false):
		if node.material_override is ShaderMaterial and node.material_override.shader==preload("res://scripts/presentation/courtyard_ground.gdshader"):
			ground=node.material_override
			break
	ground.set_shader_parameter("density_right",scene.camera.global_basis.x)
	ground.set_shader_parameter("density_up",scene.camera.global_basis.y)
	chest=scene.objective.containers.chest
	original_frames=chest.frames.duplicate()
	old_chest_pixel=chest.sprite.pixel_size
	old_chest_position=chest.sprite.position
	for i in 4:
		var atlas:=AtlasTexture.new()
		atlas.atlas=load(OUT+"chest_%d.png"%i)
		atlas.region=Rect2(0,0,53,75)
		trial_frames.append(atlas)
	var layer:=CanvasLayer.new()
	layer.layer=92
	add_child(layer)
	notice=Label.new()
	notice.theme=preload("res://scripts/ui/pixel_style.gd").theme()
	notice.position=Vector2(18,170)
	notice.add_theme_color_override("font_outline_color",Color.BLACK)
	notice.add_theme_constant_override("outline_size",5)
	notice.mouse_filter=Control.MOUSE_FILTER_IGNORE
	layer.add_child(notice)
	ready_for_test=true
	set_calibrated(true)

## 只交换表现资源，墙和箱的脚点/碰撞及交互状态保留；切回恢复原对象。
func set_calibrated(value:bool) -> void:
	calibrated=value
	for item in walls:
		var prop:Node3D=item.prop
		var texture:Texture2D=load(OUT+prop.asset_id+".png") if value else item.texture
		prop.art_material.set_shader_parameter("illustration",texture)
		prop.art_material.set_shader_parameter("logical_size",Vector2.ZERO if value else item.logical)
		var size:Vector2=texture.get_size()/PPM if value else item.size
		prop.art.mesh.size=size
		var anchor:=Vector2(prop.spec.anchor[0],prop.spec.anchor[1])
		prop.art.position=prop.art.basis*Vector3((.5-anchor.x)*size.x,(anchor.y-.5)*size.y,0) if value else item.position
	chest.frames.assign(trial_frames if value else original_frames)
	chest.sprite.pixel_size=1.0/PPM if value else old_chest_pixel
	chest.sprite.position=chest.sprite.basis*Vector3(0,75*.4/PPM,0) if value else old_chest_position
	chest.sprite.texture=chest.frames[chest.frame]
	ground.set_shader_parameter("density_trial",value)
	update_notice()

## 清晰档位仅作用于实验入口，沿用现有阻尼；通过投影实测比例，避免假设Camera3D尺寸轴。
func choose_zoom(index:int) -> void:
	zoom_index=index
	if index==0:
		scene.camera_size_target=scene.DEFAULT_CAMERA_SIZE
	else:
		var origin:Vector3=scene.player.position
		var pixels:float=scene.camera.unproject_position(origin+scene.camera.global_basis.x).distance_to(scene.camera.unproject_position(origin))
		scene.camera_size_target=scene.camera.size*pixels/(PPM*(2.0 if index==1 else 3.0))
	update_notice()

func update_notice() -> void:
	notice.text="局部像素对照 · "+("校准37.5 px/m" if calibrated else "原版")+" · "+["原视野","每像素2点","每像素3点"][zoom_index]+"\nF6 切原版/校准 · F7 切视野 · E 开箱 · 不写入正式进度"

func _input(event:InputEvent) -> void:
	if not ready_for_test: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_F6:
			set_calibrated(not calibrated)
			get_viewport().set_input_as_handled()
		elif event.physical_keycode==KEY_F7:
			choose_zoom((zoom_index+1)%3)
			get_viewport().set_input_as_handled()
