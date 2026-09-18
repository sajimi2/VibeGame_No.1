extends RefCounted
## 32×48 像素人物使用共享关节姿态，保留十二朝向、八相位步态及按需纹理缓存。
const Pose = preload("res://scripts/presentation/character_pose.gd")
const Spec = preload("res://scripts/art/frame_spec.gd")
const Store = preload("res://scripts/art/atlas_store.gd")
static var cache: Dictionary = {}

## 居中采样像素线段，用于有厚度的四肢；裁剪只保护画布，不缩放角色。
static func stroke(image: Image, start: Vector2, finish: Vector2, color: Color, width: int = 2) -> void:
	var length := maxi(1, ceili(start.distance_to(finish) * 2))
	for i in length + 1:
		var point := start.lerp(finish, float(i) / length) - Vector2.ONE * floorf(width / 2.0)
		var rect := Rect2i(roundi(point.x), roundi(point.y), width, width).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		if rect.has_area(): image.fill_rect(rect, color)

## 以整数像素填充多边形，保留明确的肩、腰、下摆轮廓。
static func polygon(image: Image, points: PackedVector2Array, color: Color) -> void:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points: bounds = bounds.expand(point)
	for y in range(maxi(0, floori(bounds.position.y)), mini(image.get_height(), ceili(bounds.end.y) + 1)):
		for x in range(maxi(0, floori(bounds.position.x)), mini(image.get_width(), ceili(bounds.end.x) + 1)):
			if Geometry2D.is_point_in_polygon(Vector2(x, y), points): image.set_pixel(x, y, color)

## 上臂与前臂分开着色，肘部保持弯曲；手心像素就是武器握点。
static func draw_arm(image: Image, data: Dictionary, side: int, coat: Color, skin: Color) -> void:
	var p: Dictionary = data.pixels
	var shoulder: Vector2 = p["shoulder%d" % side]
	var elbow: Vector2 = p["elbow%d" % side]
	var hand: Vector2 = p["hand%d" % side]
	stroke(image, shoulder, elbow, Color("29333a"), 4)
	stroke(image, shoulder, elbow, coat, 2)
	stroke(image, elbow, hand, Color("423f38"), 3)
	stroke(image, elbow, elbow.lerp(hand, 0.6), Color("887257"), 2)
	stroke(image, hand, hand, skin, 2)

## 按关节画成年人的长腿、收腰躯干与较小头部；前后手臂依据朝向分层遮挡。
static func texture(direction: int, step: int, crouch: bool, outline: bool = false, move_direction: int = -1, pose: int = 0, enemy: bool = false, arm_phase: int = -1, weight: int = 0, draw_phase: int = -1, crouch_frame: int = -1, running: bool = false, jump_frame: int = -1, asset_id: String = "") -> Texture2D:
	var id := asset_id if not asset_id.is_empty() else "guard" if enemy else "player"
	var state := Spec.character(direction,step,crouch,move_direction,pose,arm_phase,weight,draw_phase,crouch_frame,running,jump_frame)
	var imported := Store.lookup(id,Spec.key(state))
	if not imported.is_empty(): return outline_texture(imported.texture) if outline else imported.texture
	var key := str([direction, step, crouch, outline, move_direction, pose, enemy, arm_phase, weight, draw_phase, crouch_frame, running, jump_frame])
	if cache.has(key): return cache[key]
	var data := Pose.build(direction, step, crouch, move_direction, pose, arm_phase, weight, draw_phase, crouch_frame, running, jump_frame)
	var p: Dictionary = data.pixels
	var angle: float = data.angle
	var back := cos(angle) < -0.25
	var image := Image.create(32, 48, false, Image.FORMAT_RGBA8)
	var ink := Color("29333a")
	var coat := Color("536f76") if not enemy else Color("79534a")
	var light := Color("80918b") if not enemy else Color("a7846b")
	var skin := Color("c6a17c")
	var far_side: int = data.far_side
	for side in [far_side, -far_side]:
		var hip: Vector2 = p["hip%d" % side]
		var knee: Vector2 = p["knee%d" % side]
		var foot: Vector2 = p["foot%d" % side]
		var toe: Vector2 = p["toe%d" % side]
		var trouser := Color("65706b") if side != far_side else Color("424f50")
		stroke(image, hip, knee, ink, 5)
		stroke(image, hip, knee, trouser, 3)
		stroke(image, knee, foot, ink, 4)
		stroke(image, knee, foot, trouser.darkened(0.13), 2)
		stroke(image, foot + Vector2(0, -2), toe, Color("343932"), 3)
		stroke(image, foot, toe, Color("6d6651"), 1)
	draw_arm(image, data, far_side, coat.darkened(0.15), skin.darkened(0.1))
	var joints: Dictionary = data.joints
	var chest: Vector3 = joints.chest
	var pelvis: Vector3 = joints.pelvis
	var body := PackedVector2Array([
		Pose.project(chest + Vector3(-4.8, 0, 0), angle), Pose.project(chest + Vector3(4.8, 0, 0), angle),
		Pose.project(pelvis + Vector3(3.4, 0, 0), angle), Pose.project(pelvis + Vector3(-3.4, 0, 0), angle)])
	# 侧身仍需躯干厚度，不能把人物画成一条线。
	var breadth := maxi(5, roundi(10 * absf(cos(angle)) + 5 * absf(sin(angle))))
	body[0].x = p.chest.x - breadth * 0.5
	body[1].x = p.chest.x + breadth * 0.5
	body[2].x = p.pelvis.x + breadth * 0.34
	body[3].x = p.pelvis.x - breadth * 0.34
	polygon(image, body, coat)
	stroke(image, body[0], body[3], ink, 1)
	stroke(image, body[1], body[2], ink, 1)
	stroke(image, body[0] + Vector2(1, 1), body[1] - Vector2(1, -1), light, 2)
	stroke(image, body[3], body[2], Color("564839"), 3)
	if back:
		stroke(image, p.chest + Vector2(-2, 3), p.pelvis + Vector2(-1, -3), Color("807458"), 2)
	else:
		stroke(image, p.chest + Vector2(-2, 2), p.pelvis + Vector2(1, -2), Color("9a8967"), 1)
		stroke(image, p.pelvis, p.pelvis, Color("bca16b"), 2)
	stroke(image, p.chest + Vector2(0, -1), p.neck, skin.darkened(0.15), 3)
	# 七像素高的头部取代原先十四像素的方头，保留侧脸、耳部和后脑差异。
	var center: Vector2 = p.head
	var head_width := 3.2 if absf(sin(angle)) < 0.8 else 2.6
	for y in range(-4, 4):
		for x in range(-4, 5):
			if pow(x / head_width, 2) + pow(y / 4.0, 2) > 1.05: continue
			var at := Vector2i(center) + Vector2i(x, y)
			if not Rect2i(0, 0, 32, 48).has_point(at): continue
			var color := skin if not back else Color("534a3b")
			if y <= -1: color = Color("777e75") if enemy else Color("615341")
			if y <= -3: color = Color("a0a597") if enemy else Color("857253")
			if x == -3 or y == 3: color = color.darkened(0.2)
			image.set_pixelv(at, color)
	if not back:
		var nose := center + Vector2(roundi(sin(angle) * 3), 1)
		stroke(image, nose, nose + Vector2(signf(sin(angle)), 0), skin.lightened(0.08), 1)
		stroke(image, nose + Vector2(-signf(sin(angle)), -1), nose + Vector2(-signf(sin(angle)), -1), ink, 1)
	else:
		stroke(image, center + Vector2(signf(sin(angle)) * 2, 1), center + Vector2(signf(sin(angle)) * 2, 2), skin.darkened(0.1), 1)
	draw_arm(image, data, -far_side, coat.lightened(0.03), skin)
	if outline:
		var border := Image.create(32, 48, false, Image.FORMAT_RGBA8)
		for y in range(1, 47):
			for x in range(1, 31):
				if image.get_pixel(x, y).a > 0: continue
				for neighbor in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
					if image.get_pixelv(Vector2i(x, y) + neighbor).a > 0:
						border.set_pixel(x, y, Color("ffe3a0"))
						break
		image = border
	var result := ImageTexture.create_from_image(image)
	cache[key] = result
	return result

## 纹理与握点一起解析，回导后手绘外观、持械位置、遮挡轮廓和阴影使用同一帧。
static func frame(asset_id: String, state: Dictionary, enemy: bool = false) -> Dictionary:
	var tex := texture(state.direction,state.step,state.crouch>0,false,state.move,state.pose,enemy,state.arm,state.weight,state.draw,state.crouch,state.run,state.jump,asset_id)
	var grip: Vector2 = Pose.build(state.direction,state.step,state.crouch>0,state.move,state.pose,state.arm,state.weight,state.draw,state.crouch,state.run,state.jump).grip
	var imported := Store.lookup(asset_id,Spec.key(state))
	var anchor = imported.get("anchors",{}).get("grip")
	if anchor is Array: grip = Vector2(anchor[0],anchor[1])
	return {"texture":tex,"grip":grip}

## 轮廓由当前透明像素重建，不能继续引用程序旧轮廓，否则手绘形体会穿帮。
static func outline_texture(texture_value: Texture2D) -> Texture2D:
	var key := "outline:"+str(texture_value.get_instance_id())
	if cache.has(key): return cache[key]
	var image := texture_value.get_image()
	var border := Image.create(image.get_width(),image.get_height(),false,Image.FORMAT_RGBA8)
	for y in range(1,image.get_height()-1):
		for x in range(1,image.get_width()-1):
			if image.get_pixel(x,y).a > 0: continue
			for neighbor in [Vector2i(-1,0),Vector2i(1,0),Vector2i(0,-1),Vector2i(0,1)]:
				if image.get_pixelv(Vector2i(x,y)+neighbor).a > 0:
					border.set_pixel(x,y,Color("ffe3a0"))
					break
	cache[key] = ImageTexture.create_from_image(border)
	return cache[key]


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
