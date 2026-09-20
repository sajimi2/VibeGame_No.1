extends SceneTree
## 原创像素环境纹理的离线制作源。仅显式运行时重建 PNG/材质，游戏不生成纹理。
const COLORS={"grass":"536449","path":"8a795b","soil":"645743","masonry":"858773","plaster":"a19d7a","planks":"88714e","timber":"594936","wood":"88714e","roof":"665c54","cloth":"856044","iron":"4d5755"}
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/environment/textures")
	DirAccess.make_dir_recursive_absolute("res://assets/environment/materials")
	for id in COLORS: build(id)
	print("ENVIRONMENT_TEXTURES: ",COLORS.size()," palettes saved")
	quit()
func hash_at(x: int,y: int) -> int: return posmod(x*374761+y*668265+137631,104729)
func build(id: String) -> void:
	var base:=Color(COLORS[id])
	var image:=Image.create(128,128,false,Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			# 连续低频地色被量化成少量阶，避免独立方格明暗组成棋盘。
			var field:=sin(x*TAU/128.0+sin(y*TAU/64.0)*.6)+cos(y*TAU/128.0-x*TAU/64.0)*.45
			var tone: float=.035 if field>.8 else -.035 if field<-.8 else .012 if field>.2 else -.012
			var color:=base.lightened(tone) if tone>0 else base.darkened(-tone)
			if id in ["grass","path","soil"]:
				# 草簇和卵石形成稀疏连续短笔触；不使用全屏白点噪声。
				var tile:=hash_at(x/8,y/8)
				var px:=posmod(x,8); var py:=posmod(y,8)
				if id=="grass" and tile%5==0:
					if (px==3 and py in [3,4,5]) or (px==2 and py==2) or (px==5 and py in [3,4]): color=base.lightened(.12)
					elif py==6 and px in [2,3,4]: color=base.darkened(.14)
				elif id!="grass" and tile%6==0 and px in [3,4,5] and py in [3,4]: color=base.lightened(.12) if py==3 else base.darkened(.16)
			elif id in ["masonry","plaster"]:
				var row:=y/8; var bx:=posmod(x+(row%2)*8,16)
				if id=="masonry":
					color=base.darkened(float(hash_at((x+(row%2)*8)/16,row)%5)*.035)
					if y%8==0 or bx==0: color=base.darkened(.28)
					elif y%8==1 or bx==1: color=base.lightened(.1)
				elif hash_at(x/16,y/16)%5==0 and x%16 in [7,8] and y%16<5: color=base.darkened(.12)
			elif id in ["wood","planks","timber"]:
				var plank:=x/8
				color=base.darkened(float(hash_at(plank,0)%5)*.025)
				if x%8==0: color=base.darkened(.32)
				elif x%8==1: color=base.lightened(.08)
				elif (x+int(sin(y*.22+plank)*1.4))%7==0 and y%21<14: color=base.darkened(.13)
				if y%32==0: color=base.darkened(.22)
			elif id=="roof":
				var row:=x/7; var tile:=posmod(y+(row%2)*5,10)
				color=base.lightened(float(hash_at(row,y/10)%5)*.024)
				if x%7==0 or tile==0: color=base.darkened(.27)
				elif x%7==1: color=base.lightened(.13)
				elif tile==9: color=base.darkened(.12)
			image.set_pixel(x,y,color)
	var texture_path:="res://assets/environment/textures/"+id+".png"
	image.save_png(texture_path)
	# 文本材质引用独立 PNG，首次生成后由正常 Godot 导入即可使用。
	var text:='[gd_resource type="ShaderMaterial" load_steps=3 format=3]\n\n[ext_resource type="Shader" path="res://scripts/presentation/environment_surface.gdshader" id="1"]\n[ext_resource type="Texture2D" path="'+texture_path+'" id="2"]\n\n[resource]\nshader = ExtResource("1")\nshader_parameter/surface_texture = ExtResource("2")\nshader_parameter/texels_per_meter = 25.0\nshader_parameter/soft_edges = '+('true' if id=="path" else 'false')+'\n'
	FileAccess.open("res://assets/environment/materials/"+id+".tres",FileAccess.WRITE).store_string(text)
