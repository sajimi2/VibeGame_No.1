extends RefCounted
## Original 16px pixel patterns. Editable source, no external asset dependencies.
static var cache: Dictionary = {}

const HUMAN := [
"................", ".....oooooo.....", "....ohhhhhho....", "...ohhhHHhhho...",
"...ohhsssssho...", "....ossessso....", "....ossssso.....", ".....ooooo......",
"...oocccccoo....", "..occlccclcco...", ".osocclllccoso..", ".osoocccccooso..",
"..o.occccc.o....", "....occccc......", "....obbbbbo.....", "....occccc......",
".....ooooo......", "................"]
const WOLF := [
"................", "..oo......oo....", "..oho....oho....", "..ohhoooohho....",
"...ohhHHhho.....", "..ohhehhehho....", ".ohhhhhhhhhho...", ".ohHhhhhhhHho...",
"..ohHHhhHHho....", "...ohssssho.....", "....osssso......", ".....oooo.......",
"....ohhhho......", "...ohhhhhho.....", "...ohhhhhho.....", "....oooooo......",
"................", "................"]

static func actor(kind: String) -> Texture2D:
	if cache.has(kind):
		return cache[kind]
	var colors := {"o": Color("20242a"), "h": Color("5d4936"), "H": Color("8d7047"), "s": Color("d4ad83"), "e": Color("25272a"), "c": Color("537d81"), "l": Color("87b5ae"), "b": Color("654c33")}
	if kind == "bandit":
		colors["c"] = Color("934f48")
		colors["l"] = Color("c17b5f")
	elif kind == "archer":
		colors["c"] = Color("667347")
		colors["l"] = Color("a3ac72")
	elif kind == "boss":
		colors["c"] = Color("574665")
		colors["l"] = Color("b6a16e")
		colors["h"] = Color("687b87")
	elif kind == "wolf":
		colors["h"] = Color("7e7d6d")
		colors["H"] = Color("b2b5a0")
		colors["e"] = Color("dbaa57")
	var pattern: Array = WOLF if kind == "wolf" else HUMAN
	var image := Image.create(16, 18, false, Image.FORMAT_RGBA8)
	for y in 18:
		for x in 16:
			var key: String = pattern[y][x]
			if colors.has(key):
				image.set_pixel(x, y, colors[key])
	var texture := ImageTexture.create_from_image(image)
	cache[kind] = texture
	return texture
