extends RefCounted
## Original pixel silhouettes: eight headings and two gait frames.
static var cache: Dictionary = {}

static func texture(direction: int, step: int, crouch: bool, outline: bool = false) -> Texture2D:
	var key := "%s/%s/%s/%s" % [direction, step, crouch, outline]
	if cache.has(key): return cache[key]
	var image := Image.create(24, 32, false, Image.FORMAT_RGBA8)
	var back := direction in [3, 4, 5]
	var side := direction in [2, 6]
	var shift := 3 if crouch else 0
	var dark := Color("252c32")
	var coat := Color("548589") if not back else Color("43666f")
	var left := 8 if side else 6
	var width := 8 if side else 12
	image.fill_rect(Rect2i(left, 11 + shift, width, 12 - shift), dark)
	image.fill_rect(Rect2i(left + 1, 12 + shift, width - 2, 9 - shift), coat)
	image.fill_rect(Rect2i(8, 3 + shift, 9, 10), dark)
	image.fill_rect(Rect2i(9, 4 + shift, 7, 4), Color("795d42"))
	image.fill_rect(Rect2i(9, 8 + shift, 7, 4), Color("ceac84") if not back else Color("604d3e"))
	if not back:
		var eye_x := 14 if direction in [1, 2] else 9 if direction in [6, 7] else 11
		image.fill_rect(Rect2i(eye_x, 9 + shift, 2, 1), dark)
	if direction in [1, 7]:
		image.fill_rect(Rect2i(9 if direction == 1 else 15, 5 + shift, 2, 7), Color("604d3e"))
	image.fill_rect(Rect2i(left + 1, 20, width - 2, 2), Color("9d8451"))
	var leg_length := 5 if crouch else 7
	for leg in 2:
		var x := 8 + leg * 6
		var y := 22 + (step if leg == 0 else -step)
		image.fill_rect(Rect2i(x, y, 3, leg_length), Color("38454b"))
		image.fill_rect(Rect2i(x - 1, y + leg_length - 1, 4, 2), dark)
	image.fill_rect(Rect2i(left - 2, 14 + shift, 3, 6 - shift), Color("ceac84"))
	image.fill_rect(Rect2i(left + width - 1, 14 + shift, 3, 6 - shift), Color("ceac84"))
	if back:
		var pack_x := 7 if direction == 3 else 11 if direction == 5 else 9
		image.fill_rect(Rect2i(pack_x, 14 + shift, 6, 5), Color("725f43"))
	if outline:
		var border := Image.create(24, 32, false, Image.FORMAT_RGBA8)
		for y in range(1, 31):
			for x in range(1, 23):
				if image.get_pixel(x, y).a > 0: continue
				if image.get_pixel(x - 1, y).a > 0 or image.get_pixel(x + 1, y).a > 0 or image.get_pixel(x, y - 1).a > 0 or image.get_pixel(x, y + 1).a > 0:
					border.set_pixel(x, y, Color("ffe3a0"))
		image = border
	var result := ImageTexture.create_from_image(image)
	cache[key] = result
	return result

static func tree() -> Texture2D:
	if cache.has("tree"): return cache.tree
	var image := Image.create(48, 64, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(20, 29, 9, 33), Color("443d30"))
	image.fill_rect(Rect2i(22, 34, 3, 26), Color("87714b"))
	for y in range(3, 47):
		for x in range(3, 45):
			if pow((x - 24.0) / 21, 2) + pow((y - 25.0) / 23, 2) < 1:
				var shade := ((x * 73856093) ^ (y * 19349663)) % 17
				image.set_pixel(x, y, Color("687948") if shade < 3 else Color("425c3c") if x < 27 else Color("344938"))
	cache.tree = ImageTexture.create_from_image(image)
	return cache.tree
