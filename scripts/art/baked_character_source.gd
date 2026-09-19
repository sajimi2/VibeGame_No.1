extends "res://scripts/art/atlas_source.gd"
## 烘焙来源适配器：同一清单供游戏和工作台使用；拼图仅在工具中执行，不进入实时角色。
const Spec=preload("res://scripts/art/baked_human_spec.gd")
const Frame=preload("res://scripts/art/frame_spec.gd")
const Store=preload("res://scripts/art/atlas_store.gd")
@export var rig_id: String="player":
	set(value):
		rig_id=value
		cell_size=Vector2i.ONE*Spec.cell(value)
var manifest: Dictionary={}
var colors: Array[Image]=[]
var depths: Array[Image]=[]

func _init() -> void: cell_size=Vector2i.ONE*Spec.CELL

func animations() -> Array:
	var result: Array=[{"id":"idle","label":"站立","frames":1},{"id":"walk","label":"行走","frames":8},{"id":"run","label":"疾跑","frames":8},{"id":"crouch","label":"蹲起","frames":7},{"id":"crouch_walk","label":"蹲行","frames":8},{"id":"jump","label":"跳跃","frames":5}]
	for action in Spec.ACTIONS[rig_id]:
		if Spec.phases(action)>1: result.append({"id":action,"label":Spec.LABELS[action],"frames":Spec.phases(action)})
	return result

func options() -> Array:
	var ready_ids: Array=[]
	var titles: Array=[]
	for action in Spec.ACTIONS[rig_id]:
		if Spec.phases(action)==1:
			ready_ids.append(action)
			titles.append(Spec.LABELS[action])
	var directions: Array=[]
	for index in 12: directions.append("同向" if index==0 else "后退" if index==6 else "%d°"%(index*30))
	return [{"id":"part","label":"显示层","labels":["完整合成（查看/导出）","上身（补色回导）","下身（补色回导）"],"values":["full","upper","lower"],"default":"full"},
		{"id":"ready","label":"持械","labels":titles,"values":ready_ids,"default":Spec.ready(rig_id)},
		{"id":"move","label":"移动方向","labels":directions,"values":range(12),"default":0},
		{"id":"gait","label":"攻击步态","labels":["静止","步0","步1","步2","步3","步4","步5","步6","步7"],"values":[-1,0,1,2,3,4,5,6,7],"default":-1}]

func _load() -> void:
	if not manifest.is_empty(): return
	var folder:=Spec.folder(rig_id)
	manifest=JSON.parse_string(FileAccess.get_file_as_string(folder+"/atlas.json"))
	cell_size=Vector2i.ONE*int(manifest.cell)
	for page in manifest.pages:
		colors.append(load(folder+"/"+str(page)+".png").get_image())
		depths.append(load(folder+"/"+str(page)+"_depth.png").get_image())

## 图集与实体预览共用状态组装，保证后退、蹲跳和移动攻击取到同一动作组合。
func preview_state(animation: String, direction: int, phase: int, settings: Dictionary) -> Dictionary:
	var moving: bool=animation in ["walk","run","crouch_walk"]
	var bend:=phase if animation=="crouch" else 6 if animation=="crouch_walk" else 0
	var state:=Frame.character(direction,phase if moving else int(settings.get("gait",-1)),bend>0,(direction+int(settings.get("move",0)))%12,0,-1,0,-1,bend,animation=="run",phase if animation=="jump" else -1)
	state=Frame.with_action(state,animation if animation in Spec.ACTIONS[rig_id] else str(settings.get("ready",Spec.ready(rig_id))),phase)
	if animation=="bow_draw": state.draw=phase
	state.asset=rig_id
	return state

func model_preview(animation: String, direction: int, phase: int, settings: Dictionary) -> Dictionary:
	_load()
	return {"scene":manifest.source_scene,"state":preview_state(animation,direction,phase,settings),"part":settings.get("part","full")}

## 原尺寸分层图可补色回导；合成图按逐像素深度合并，不能用前后固定贴图顺序冒充遮挡。
func sample(animation: String, direction: int, phase: int, settings: Dictionary) -> Dictionary:
	_load()
	var state:=preview_state(animation,direction,phase,settings)
	var selection:=Spec.select(state,rig_id)
	var part: String=settings.get("part","full")
	if part!="full":
		var key: String=selection[part]
		var document_key:=key+"@"+animation+"/"+str(phase)
		var frame:=layer_image(key)
		var entry: Dictionary=manifest.entries[key]
		var point: Vector3=_vector(entry.support if selection.upper.contains("/bow_") else entry.grip)
		var projected:=_project(point,direction)
		var anchors: Dictionary={"grip":[projected.x,projected.y]} if part=="upper" else {}
		var override:=Store.lookup(asset_id,key,cell_size)
		if not override.is_empty(): return {"key":document_key,"binding":key,"texture":override.texture,"anchors":override.anchors}
		return {"key":document_key,"binding":key,"texture":ImageTexture.create_from_image(frame),"anchors":anchors}
	var image:=Image.create(cell_size.x,cell_size.y,false,Image.FORMAT_RGBA8)
	var buffer:=PackedFloat32Array()
	buffer.resize(cell_size.x*cell_size.y)
	buffer.fill(-100)
	var pelvis:=_vector(manifest.entries[selection.lower].pelvis)
	var center:=pelvis if animation=="death_fall" else Spec.CENTER
	var camera:=Basis(Vector3.RIGHT,deg_to_rad(Spec.PITCH)).inverse()
	var yaw:=Basis(Vector3.UP,direction*PI/6)
	for layer in ["lower","upper"]:
		var key: String=selection[layer]
		var entry: Dictionary=manifest.entries[key]
		var pivot: Vector3=pelvis if layer=="upper" else Spec.CENTER
		var delta:=camera*yaw*(pivot-center)
		var offset:=Vector2i(roundi(delta.x/float(manifest.pixel_size)),roundi(-delta.y/float(manifest.pixel_size)))
		var frame:=layer_image(key)
		var override:=Store.lookup(asset_id,key,cell_size)
		if not override.is_empty(): frame=override.texture.get_image()
		var depth:=layer_image(key,true)
		for y in cell_size.y:
			for x in cell_size.x:
				var color:=frame.get_pixel(x,y)
				if color.a<.5: continue
				var at:=Vector2i(x,y)+offset
				if not Rect2i(Vector2i.ZERO,cell_size).has_point(at): continue
				var encoded:=depth.get_pixel(x,y)
				var z:=(encoded.r*65280+encoded.g*255)/65535*6-3+delta.z
				if z<=buffer[at.y*cell_size.x+at.x]: continue
				buffer[at.y*cell_size.x+at.x]=z
				image.set_pixelv(at,color)
	return {"key":"full|"+selection.lower+"|"+selection.upper+"@"+animation+"/"+str(phase),"texture":ImageTexture.create_from_image(image),"anchors":{}}

func layer_image(key: String, is_depth:=false) -> Image:
	_load()
	var entry: Dictionary=manifest.entries[key]
	var image:=Image.create(cell_size.x,cell_size.y,false,Image.FORMAT_RGBA8)
	var rect:=Rect2i(entry.rect[0],entry.rect[1],entry.rect[2],entry.rect[3])
	image.blit_rect(depths[int(entry.page)] if is_depth else colors[int(entry.page)],rect,Vector2i(entry.trim[0],entry.trim[1]))
	return image

## 手绘补色保留源表面深度；轮廓/体积应改源模型后重烘焙，不能给新增像素捏造深度。
func validate_edit(document: RefCounted) -> String:
	if document.settings.get("part","full")=="full": return "完整合成图用于查看/导出。回导补色请选择上身或下身；形体与遮挡请修改 3D 源模型后重新烘焙。"
	for index in document.cells.size():
		var cell: Dictionary=document.cells[index]
		var original:=layer_image(cell.get("binding",cell.key))
		var at:=Vector2i(index%12,index/12)*cell_size
		for y in cell_size.y:
			for x in cell_size.x:
				if document.image.get_pixelv(at+Vector2i(x,y)).a>=.5 and original.get_pixel(x,y).a<.5:
					return "第 %d 帧增加了源模型轮廓外的像素，缺少对应深度。补色可回导；改变形体请修改源模型后重烘焙。"%index
	return ""

func _project(point: Vector3, direction: int) -> Vector2:
	var p:=Basis(Vector3.RIGHT,deg_to_rad(Spec.PITCH)).inverse()*Basis(Vector3.UP,direction*PI/6)*point
	return Vector2(cell_size.x*0.5+p.x/float(manifest.pixel_size),cell_size.y*0.5-p.y/float(manifest.pixel_size))
static func _vector(values: Array) -> Vector3: return Vector3(values[0],values[1],values[2])
