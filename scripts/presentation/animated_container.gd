@tool
extends Node3D
## 箱子只播放开合，不拥有库存。始终相同脚点和碰撞，暂停界面时动画仍完成。
var sprite: Sprite3D
var frame := 0
var target := 0
var elapsed := 0.0
@export_storage var frames: Array[AtlasTexture]=[]
var opened := false

func _ready() -> void:
	if has_node("Illustration"):
		sprite=get_node("Illustration")
		set_notify_transform(true)
		process_mode=Node.PROCESS_MODE_ALWAYS
		return
	if Engine.is_editor_hint(): return
	process_mode=Node.PROCESS_MODE_ALWAYS
	var texture: Texture2D=load("res://assets/environment/painted/woodpath/source/chest_motion.png")
	# 原稿四格共享底部基线，不随盖子高度重算裁切，避免开箱跳动。
	for i in 4:
		var atlas:=AtlasTexture.new()
		atlas.atlas=texture
		atlas.region=Rect2(i*texture.get_width()/4.0,0,texture.get_width()/4.0,texture.get_height())
		frames.append(atlas)
	sprite=Sprite3D.new()
	sprite.name="Illustration"
	sprite.texture=frames[0]
	sprite.pixel_size=1.4/(texture.get_width()/4.0)
	sprite.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded=false
	sprite.alpha_cut=SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.basis=Basis.from_euler(Vector3(deg_to_rad(-35),deg_to_rad(25),0))
	sprite.position=sprite.basis*Vector3(0,(float(texture.get_height())*.40)*sprite.pixel_size,0)
	add_child(sprite)
	var body:=StaticBody3D.new()
	body.collision_layer=1|8
	var shape:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(1.0,.62,.65)
	shape.shape=box
	shape.position.y=.31
	body.add_child(shape)
	add_child(body)
	var shadow:=preload("res://scripts/presentation/illustration_shadow.gd").new()
	shadow.name="PaintedShadow"
	add_child(shadow)
	set_notify_transform(true)
	shadow.setup("chest",1,Vector3(1.1,.8,.7))

## 开箱只切换纹理；脚点、碰撞和交互根节点不会随帧变化。
func _notification(what: int) -> void:
	if what==NOTIFICATION_TRANSFORM_CHANGED and is_inside_tree():
		var shadow=get_node_or_null("PaintedShadow")
		if shadow!=null: shadow.sync_transform()

func set_open(value: bool) -> void:
	opened=value
	target=3 if value else 0

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or sprite==null: return
	elapsed+=delta
	if frame!=target and elapsed>.075:
		elapsed=0
		frame+=1 if target>frame else -1
		sprite.texture=frames[frame]
