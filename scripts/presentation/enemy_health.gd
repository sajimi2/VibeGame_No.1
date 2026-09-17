extends Sprite3D
var displayed := -1
func _ready() -> void:
	pixel_size=0.023
	position.y=1.92
	billboard=BaseMaterial3D.BILLBOARD_ENABLED
	texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	no_depth_test=true
	render_priority=11
func set_health(value: int, maximum: int) -> void:
	visible=value>0
	var amount := clampi(roundi(float(value)/maximum*42),0,42)
	if amount==displayed: return
	displayed=amount
	var image := Image.create(48,7,false,Image.FORMAT_RGBA8)
	image.fill(Color("1d272b"))
	image.fill_rect(Rect2i(1,1,46,5),Color("c4b68c"))
	image.fill_rect(Rect2i(3,2,42,3),Color("453332"))
	if amount>0:
		image.fill_rect(Rect2i(3,2,amount,3),Color("af5146"))
		image.fill_rect(Rect2i(3,2,amount,1),Color("e58664"))
	texture=ImageTexture.create_from_image(image)
