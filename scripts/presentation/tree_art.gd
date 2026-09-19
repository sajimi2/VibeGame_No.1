extends RefCounted
## 仅负责当前场景使用的像素树纹理，与角色美术无关。
static var cache: Dictionary = {}

## 程序生成像素树纹理，根部位置用于对齐地面。
static func tree() -> Texture2D:
	if cache.has("tree"): return cache.tree
	var image := Image.create(48, 64, false, Image.FORMAT_RGBA8)
	# 绘制分叉树干与外扩树根，最后一行不透明像素固定在 y=61。
	for y in range(26,62):
		var width := 3 if y < 56 else 3 + (y-56)/2
		for x in range(23-width,26+width):
			image.set_pixel(x,y,Color("65533c") if x < 25 else Color("3b3830"))
	for i in range(14):
		image.fill_rect(Rect2i(12+i,29+i,3,2),Color("514332"))
		image.fill_rect(Rect2i(25+i,40-i,3,2),Color("514332"))
	var lobes := [Vector3(29,31,15),Vector3(13,30,11),Vector3(35,22,10),Vector3(21,20,16),Vector3(14,15,10),Vector3(29,10,9)]
	for lobe in lobes:
		for y in range(1,47):
			for x in range(1,47):
				var d := Vector2((x-lobe.x)/lobe.z,(y-lobe.y)/(lobe.z*0.78))
				var edge := 0.94 + 0.06*sin(atan2(d.y,d.x)*9)
				if d.length_squared() > edge: continue
				var light := (d + Vector2(0.28,0.35)).length()
				var col := Color("354d3b") if light > 1.05 else Color("496447") if light > 0.65 else Color("648050")
				if d.length_squared() > 0.8 and d.y > 0: col = Color("354d3b")
				if light < 0.7 and (x/3+y/2)%5 == 0: col = Color("7b945e")
				image.set_pixel(x,y,col)
	cache.tree = ImageTexture.create_from_image(image)
	return cache.tree
