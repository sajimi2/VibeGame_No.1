extends Resource
## 一次通过校验的图集及其精确帧键/握点；PNG 字节随资源打包，发布版无需访问 work 目录。
@export var asset_id := ""
@export var png_bytes := PackedByteArray()
@export var cell_size := Vector2i(96,96)
@export var columns := 12
@export var cells: Array[Dictionary] = []
var texture: ImageTexture

func get_texture() -> ImageTexture:
	if texture == null:
		var image := Image.new()
		if image.load_png_from_buffer(png_bytes) != OK: return null
		texture = ImageTexture.create_from_image(image)
	return texture
