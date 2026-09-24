extends RefCounted
## 小尺寸九宫格边框由整数像素绘制；统一行囊、对话和快捷栏，不缩放文字内容。
static var cache: Dictionary={}
static func theme() -> Theme:
	if cache.has("theme"): return cache.theme
	var result:=Theme.new()
	# 正文使用清晰的系统CJK字体；像素质感归边框/材质，避免12px字形被非整数倍率拉坏。
	var font:=SystemFont.new()
	font.font_names=PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei","Noto Sans CJK SC","sans-serif"])
	font.font_weight=500
	result.default_font=font
	result.default_font_size=16
	# 滑块也使用方形像素柄，避免系统默认的圆形控件混入像素界面。
	var handle:=Image.create(12,16,false,Image.FORMAT_RGBA8)
	handle.fill(Color("88795d"))
	handle.fill_rect(Rect2i(2,2,8,12),Color("d6bc84"))
	handle.fill_rect(Rect2i(4,4,2,8),Color("eedab0"))
	var icon:=ImageTexture.create_from_image(handle)
	for state in ["grabber","grabber_highlight","grabber_disabled"]: result.set_icon(state,"HSlider",icon)
	var track:=StyleBoxFlat.new()
	track.bg_color=Color("10171c")
	track.content_margin_top=3
	track.content_margin_bottom=3
	result.set_stylebox("slider","HSlider",track)
	var fill:=track.duplicate() as StyleBoxFlat
	fill.bg_color=Color("8e805e")
	result.set_stylebox("grabber_area","HSlider",fill)
	result.set_stylebox("grabber_area_highlight","HSlider",fill)
	cache.theme=result
	return result
static func box(selected:=false, hover:=false) -> StyleBoxTexture:
	var key:=str(selected)+str(hover)
	if cache.has(key): return cache[key]
	var image:=Image.create(16,16,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var edge:=Color("d2b576") if selected else Color("72716b")
	var light:=Color("eed69c") if selected else Color("969184")
	var inside:=Color("353e42") if hover else Color("282f35") if selected else Color("1f242c")
	for y in 16:
		for x in 16:
			if (x<2 or x>13) and (y<2 or y>13): continue
			var color:=inside
			if x==0 or x==15 or y==0 or y==15: color=Color("101219")
			elif x==1 or y==1: color=light
			elif x==14 or y==14: color=edge.darkened(.3)
			elif x==2 or y==2 or x==13 or y==13: color=edge
			image.set_pixel(x,y,color)
	var style:=StyleBoxTexture.new()
	style.texture=ImageTexture.create_from_image(image)
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		style.set_texture_margin(side,5)
		style.set_content_margin(side,8)
	style.axis_stretch_horizontal=StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.axis_stretch_vertical=StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	cache[key]=style
	return style
