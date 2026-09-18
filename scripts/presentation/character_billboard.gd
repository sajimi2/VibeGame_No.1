extends RefCounted
## 人物纸片只绕竖轴朝向镜头；保留屏幕尺寸，同时让深度与脚下位置一致。

## 相机俯角只用于补偿投影高度，不能让人物上半身向墙内倾斜。
static func align(item: Sprite3D, camera: Camera3D) -> void:
	item.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	item.scale = Vector3(1, height_scale(camera), 1)

static func height_scale(camera: Camera3D) -> float:
	return 1.0 / maxf(0.3, camera.global_basis.y.y) if is_instance_valid(camera) else 1.0

## 复制当前人物的透明剪影来投影；只显示影子，不再用胶囊代替头、手和双腿。
static func shadow(parent: Node3D) -> Sprite3D:
	var item := Sprite3D.new()
	item.name = "CharacterWorldShadow"
	item.pixel_size = 0.04
	item.offset = Vector2(0, 24)
	item.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	item.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	parent.add_child(item)
	return item

## 阴影与人物使用同一帧及同一朝向；太阳光负责把剪影投到实际地形上。
static func sync_shadow(shadow_sprite: Sprite3D, body: Sprite3D) -> void:
	shadow_sprite.texture = body.texture
	shadow_sprite.billboard = body.billboard
	shadow_sprite.transform = body.transform
