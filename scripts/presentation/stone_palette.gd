@tool
extends RefCounted
## 断墙与巨石共用的像素材质；输入石材类型，输出缓存的有限色阶纹理与材质。
static var materials: Dictionary = {}

## 用连续色块、缺口和短裂纹组织石面；没有随机单像素噪声或三角面随机着色。
static func material(rock: bool) -> ShaderMaterial:
	if materials.has(rock): return materials[rock]
	var image := Image.create(64, 64, false, Image.FORMAT_RGB8)
	var palette := [Color("555e59"), Color("6b746b"), Color("828979"), Color("9a9d87"), Color("b0af94")]
	for y in 64:
		for x in 64:
			var field := sin(x * 0.17 + sin(y * 0.12) * 2.0) + cos(y * 0.23 - x * 0.07)
			var shade := 3 if field > 1.2 else 2 if field > -0.7 else 1
			var color: Color = palette[shade]
			# 不规则台阶形裂纹，亮边只沿裂纹一侧出现，避免棋盘或满屏勾线。
			var seam := posmod(y + int(x / 5) - int(3 * sin(x * 0.13)), 29)
			if seam == 0 and x % 31 < 19: color = palette[0]
			elif seam == 1 and x % 31 < 17: color = palette[3]
			if not rock:
				var chip := posmod(x + int(y / 4) * 7, 37)
				if chip < 2 and y % 23 < 6: color = palette[1]
			elif field > 1.6 and y % 9 < 3: color = Color("88906b")
			image.set_pixel(x, y, color)
	var result := ShaderMaterial.new()
	result.shader = preload("res://scripts/presentation/pixel_stone.gdshader")
	result.set_shader_parameter("stone_texture", ImageTexture.create_from_image(image))
	result.set_shader_parameter("rock", rock)
	materials[rock] = result
	return result
