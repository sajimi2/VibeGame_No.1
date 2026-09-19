extends SceneTree
## 初次建模/动画种子工具：输出可独立编辑的源场景和标准骨骼动画；日常烘焙绝不调用它。
## 已存在的资产默认拒绝覆盖，只有明确传 --replace-authored 才重新制作模板。
const Rig = preload("res://scripts/art/humanoid_rig.gd")
const Spec = preload("res://scripts/art/baked_human_spec.gd")
const Actions = preload("res://scripts/combat/action_library.gd")
var names: Array[String]=["Pelvis","Spine","Head"]
var parents: Array[int]=[-1,0,1]
var rests: Array[Vector3]=[Vector3(0,0.91,0),Vector3.ZERO,Vector3(0,0.65,0)]
var parts: Array[String]=["lower","upper","upper"]

func _initialize() -> void: run.call_deferred()
func run() -> void:
	if FileAccess.file_exists(Spec.LIBRARY) and "--replace-authored" not in OS.get_cmdline_user_args():
		push_error("源动画已存在；普通改动请编辑 AnimationPlayer 后仅运行烘焙器。")
		quit(1)
		return
	for side in [-1,1]:
		var suffix: String="L" if side<0 else "R"
		var first:=names.size()
		names.append_array(["Thigh"+suffix,"Shin"+suffix,"Foot"+suffix,"UpperArm"+suffix,"Forearm"+suffix,"Hand"+suffix])
		parents.append_array([0,first,first+1,1,first+3,first+4])
		rests.append_array([Vector3(side*0.105,0,0),Vector3(0,-0.43,0),Vector3(0,-0.41,0),Vector3(side*0.215,0.405,0),Vector3(0,-0.29,0),Vector3(0,-0.27,0)])
		parts.append_array(["lower","lower","lower","upper","upper","upper"])
	var library:=AnimationLibrary.new()
	var ids: Array[String]=[]
	for asset in Spec.ACTIONS:
		for id in Spec.ACTIONS[asset]:
			if id not in ids: ids.append(id)
	ids.append("crouch")
	for gait in ["walk","run","crouch_walk","jump"]:
		for move in 12: ids.append(gait+"_%02d"%move)
	for id in ids: library.add_animation(id,_animation(id))
	var reset:=Animation.new()
	reset.length=0.001
	for i in names.size():
		_track(reset,i,0,Transform3D(Basis.IDENTITY,rests[i]),true)
	library.add_animation("RESET",reset)
	assert(ResourceSaver.save(library,Spec.LIBRARY)==OK)
	library=load(Spec.LIBRARY)
	for asset in ["player","guard","archer"]:
		var model:=_model(asset,library)
		root.add_child(model)
		model.sample(Spec.ready(asset),0)
		_owners(model,model)
		var packed:=PackedScene.new()
		assert(packed.pack(model)==OK)
		assert(ResourceSaver.save(packed,"res://assets/characters/"+asset+"_rig.tscn")==OK)
		model.free()
	print("AUTHORED_RIGS: 3 models, ",ids.size()," editable skeletal clips")
	quit()

func _owners(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner=owner_node
		_owners(child,owner_node)

## 固定骨長的两段 IK 只用于初稿；解算结果保存为普通旋转关键帧，烘焙不再执行 IK。
func _joint(start: Vector3, target: Vector3, a: float, b: float, pole: Vector3) -> Array[Vector3]:
	var axis: Vector3=(target-start).normalized()
	var distance:=clampf(start.distance_to(target),absf(a-b)+0.005,a+b-0.002)
	var along:=(a*a-b*b+distance*distance)/(2*distance)
	var bend:=(pole-axis*pole.dot(axis)).normalized()
	if bend.length()<0.1: bend=Vector3.FORWARD
	var elbow:=start+axis*along+bend*sqrt(maxf(0,a*a-along*along))
	return [elbow,start+axis*distance]

func _axis(start: Vector3, end: Vector3) -> Basis:
	var y:=(start-end).normalized()
	var x:=Vector3.RIGHT-y*y.dot(Vector3.RIGHT)
	if x.length()<0.1: x=Vector3.FORWARD-y*y.dot(Vector3.FORWARD)
	x=x.normalized()
	return Basis(x,y,x.cross(y).normalized()).orthonormalized()

## 以米和固定骨长塑形；跑步的前倾分布在骨盆/胸椎，后退减小前倾，不能单独平移胸口。
func _pose(id: String, t: float) -> Array[Transform3D]:
	var root_at:=Vector3(0,0.91,0)
	var root_rotation:=Basis.IDENTITY
	var spine_rotation:=Basis.IDENTITY
	var feet: Array[Vector3]=[Vector3(-0.12,0.075,0.015),Vector3(0.12,0.075,0.015)]
	var hands: Array[Vector3]=[Vector3(-0.20,1.05,0.18),Vector3(0.20,1.10,0.23)]
	var gait: String=id.get_slice("_",0)
	if id.begins_with("crouch_walk"): gait="crouch_walk"
	var moving:=gait in ["walk","run","crouch_walk"]
	var move:=int(id.get_slice("_",2 if gait=="crouch_walk" else 1)) if moving or gait=="jump" else 0
	var travel:=Vector3.BACK.rotated(Vector3.UP,move*PI/6)
	var bend:=t if id=="crouch" else 1.0 if gait=="crouch_walk" else 0.0
	var cycle:=t*TAU
	if bend>0:
		root_at=Vector3(0,lerpf(0.91,0.47,bend),-0.065*bend)
		spine_rotation=Basis(Vector3.RIGHT,deg_to_rad(14*bend))
	if moving:
		var running:=gait=="run"
		var backwards:=maxf(0,-travel.z)
		var stride:=(0.32 if running else 0.23)*(1-0.3*backwards)*(0.5 if bend>0 else 1.0)
		root_at.y+=(0.028 if running else 0.012)*cos(cycle*2)
		if running:
			root_at+=travel*0.025
			root_rotation=Basis(Vector3.UP.cross(travel).normalized(),deg_to_rad(3.5*(1-0.6*backwards)))
			spine_rotation=Basis(Vector3.UP.cross(travel).normalized(),deg_to_rad(2.0*(1-0.7*backwards)))
		for index in 2:
			var phase:=cycle+(PI if index==0 else 0.0)
			feet[index]+=travel*cos(phase)*stride
			feet[index].y+=maxf(0,sin(phase))*(0.24 if running else 0.095)*(0.35 if bend>0 else 1.0)
			var side: int=-1 if index==0 else 1
			hands[index]=Vector3(side*0.23,1.14+(0.03 if running else 0)*cos(phase),0.10-sin(phase)*(0.14 if running else 0.055))
	if bend>0:
		for index in 2:
			feet[index].x*=1.35
			feet[index].z+=0.05
			hands[index].y-=0.40*bend
	if gait=="jump":
		var index:=clampi(roundi(t*4),0,4)
		root_at.y-=[0.14,0.02,0.025,0.0,0.21][index]
		for side_index in 2:
			feet[side_index].y+=[0.0,0.22 if side_index==0 else 0.13,0.14,0.045,0.0][index]
			feet[side_index]+=travel*(0.08 if side_index==0 else -0.06) if index in [1,2] else Vector3.ZERO
			hands[side_index].y+=0.05 if index in [0,1,2] else 0
		spine_rotation=Basis(Vector3.RIGHT,deg_to_rad(5 if index in [0,4] else 1))
	var profile:=Actions.get_action(id) if id in Spec.LABELS and id not in ["bow_draw","bow_ready","hurt","death_fall"] else null
	if profile!=null:
		var action: Dictionary=profile.sample(t)
		root_at+=action.hip*0.025
		spine_rotation=Basis.from_euler(Vector3(clampf(action.chest.z*0.04,-0.14,0.18),action.twist*0.65,-action.chest.x*0.015))
		hands[1]=Vector3(0,1.315,0)+action.hand*0.04
		hands[0]=Vector3(0,1.315,0)+action.support*0.04
		for index in 2: feet[index].z+=(1 if index==1 else -1)*action.stance*0.032
		# 双手使用同一实际刀柄，第二只手沿刀柄后移，避免掌心各自漂浮。
		if id.begins_with("sword"):
			hands[0]=hands[1]+Basis(Vector3.UP,PI)*Basis.from_euler(action.blade)*Vector3(0,0,0.10)
	if id in ["bow_ready","bow_draw"]:
		var draw:=t if id=="bow_draw" else 0.0
		hands[0]=Vector3(-0.09,1.26,0.39)
		hands[1]=Vector3(0.07,1.27,lerpf(0.30,-0.08,draw))
		spine_rotation=Basis(Vector3.UP,deg_to_rad(-12*draw))
	if id=="hurt":
		var amount:=sin(t*PI)
		spine_rotation=Basis(Vector3.RIGHT,-0.14*amount)
		root_at.y-=0.06*amount
		hands[0]=Vector3(-0.20,1.12,0.22)
		hands[1]=Vector3(0.23,1.08,0.25)
	# 先弯膝失去支撑，再整身后倒。保存的是实际三维姿态，运行时不用旋转一张立人纸片。
	var fall:=smoothstep(0.12,0.92,t) if id=="death_fall" else 0.0
	if id=="death_fall":
		root_at.y-=0.20*sin(t*PI)
		hands=[Vector3(-0.28,0.99,0.12),Vector3(0.29,1.02,0.05)]
		spine_rotation=Basis(Vector3.RIGHT,-0.1*sin(t*PI))
	var globals: Array[Transform3D]=[Transform3D(root_rotation,root_at),Transform3D(root_rotation*spine_rotation,root_at)]
	globals.append(globals[1]*Transform3D((root_rotation*spine_rotation).inverse(),rests[2]))
	for side_index in 2:
		var side: int=-1 if side_index==0 else 1
		var hip:=globals[0]*Vector3(side*0.105,0,0)
		var leg:=_joint(hip,feet[side_index],0.43,0.41,Vector3.BACK)
		globals.append(Transform3D(_axis(hip,leg[0]),hip))
		globals.append(Transform3D(_axis(leg[0],leg[1]),leg[0]))
		globals.append(Transform3D(Basis.IDENTITY,leg[1]))
		var shoulder:=globals[1]*Vector3(side*0.215,0.405,0)
		# 奔跑主要在前后方向摆臂，肘部贴近躯干；战斗戒备才保留适度侧张。
		var pole:=Vector3(side*.18,-1,-.45) if moving or gait=="jump" or id=="crouch" else Vector3(side*.75,-.65,-.2)
		var arm:=_joint(shoulder,hands[side_index],0.29,0.27,pole)
		globals.append(Transform3D(_axis(shoulder,arm[0]),shoulder))
		globals.append(Transform3D(_axis(arm[0],arm[1]),arm[0]))
		globals.append(Transform3D(Basis.IDENTITY,arm[1]))
	if fall>0:
		var rotate:=Basis(Vector3.RIGHT,-fall*PI*0.5)
		var minimum:=100.0
		for bone in globals: minimum=minf(minimum,(rotate*bone.origin).y)
		for i in globals.size():
			globals[i]=Transform3D(rotate*globals[i].basis,rotate*globals[i].origin+Vector3(0,(0.13-minimum)*fall,0))
	var poses: Array[Transform3D]=[]
	for i in names.size(): poses.append(globals[parents[i]].affine_inverse()*globals[i] if parents[i]>=0 else globals[i])
	return poses

func _animation(id: String) -> Animation:
	var result:=Animation.new()
	result.resource_name=id
	result.length=1.0
	var looping:=id.begins_with("walk_") or id.begins_with("run_") or id.begins_with("crouch_walk_")
	if looping: result.loop_mode=Animation.LOOP_LINEAR
	var count:=9 if looping else 5 if id.begins_with("jump_") else 7 if id=="crouch" else Spec.phases(id)
	for sample_index in count:
		var t:=float(sample_index)/maxi(1,count-1)
		var poses:=_pose(id,t)
		for i in names.size(): _track(result,i,t,poses[i],sample_index==0)
	return result

## 所有片段都有完整旋转轨道，只有骨盆可平移；其余关节位置由源骨架 rest 决定。
func _track(animation: Animation, bone: int, t: float, pose: Transform3D, first: bool) -> void:
	var path:=NodePath("Skeleton3D:"+names[bone])
	if first:
		if bone==0:
			var position:=animation.add_track(Animation.TYPE_POSITION_3D)
			animation.track_set_path(position,path)
		var rotation:=animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(rotation,path)
	if bone==0: animation.position_track_insert_key(0,t,pose.origin)
	animation.rotation_track_insert_key(bone+1,t,pose.basis.orthonormalized().get_rotation_quaternion())

func _model(asset: String, library: AnimationLibrary) -> MeshInstance3D:
	var model:=Rig.new()
	model.name=asset.capitalize()+"Rig"
	var skeleton:=Skeleton3D.new()
	skeleton.name="Skeleton3D"
	model.add_child(skeleton)
	for i in names.size():
		skeleton.add_bone(names[i])
		if parents[i]>=0: skeleton.set_bone_parent(i,parents[i])
		skeleton.set_bone_rest(i,Transform3D(Basis.IDENTITY,rests[i]))
		skeleton.set_bone_pose_position(i,rests[i])
		skeleton.set_bone_meta(i,"part",parts[i])
		var attachment:=BoneAttachment3D.new()
		attachment.name=names[i]
		attachment.bone_name=names[i]
		skeleton.add_child(attachment)
	var animator:=AnimationPlayer.new()
	animator.name="AnimationPlayer"
	animator.add_animation_library("",library)
	model.add_child(animator)
	var coat: Color={"player":Color("476c77"),"guard":Color("6e5041"),"archer":Color("687345")}[asset]
	var skin:=Color("c49d76")
	var dark:=Color("343d40")
	var leather:=Color("514030")
	var steel:=Color("8c9694")
	_piece(skeleton,"Pelvis","Breeches",_ellipsoid(Vector3(0.16,0.11,0.12)),dark,Vector3(0,-0.025,0))
	_piece(skeleton,"Spine","Coat",_rings([[0,.145,.10],[.10,.138,.10],[.32,.205,.125],[.43,.17,.11]]),coat)
	_piece(skeleton,"Spine","Belt",_box(Vector3(.30,.05,.235)),leather,Vector3(0,.035,.008))
	_piece(skeleton,"Spine","Buckle",_box(Vector3(.052,.038,.03)),Color("baa168"),Vector3(0,.035,.135))
	_piece(skeleton,"Spine","Collar",_ellipsoid(Vector3(.10,.035,.08)),coat.lightened(.25),Vector3(0,.445,0))
	_piece(skeleton,"Spine","Fastening",_box(Vector3(.028,.26,.015)),leather,Vector3(0,.27,.128))
	for index in 3: _piece(skeleton,"Spine","Button%d"%index,_box(Vector3(.025,.024,.02)),Color("b6a47b"),Vector3(.027,.20+index*.075,.14))
	_piece(skeleton,"Head","Neck",_ellipsoid(Vector3(.055,.075,.055)),skin.darkened(.1),Vector3(0,-.15,0))
	_piece(skeleton,"Head","Face",_ellipsoid(Vector3(.103,.135,.094)),skin)
	_piece(skeleton,"Head","Jaw",_ellipsoid(Vector3(.078,.068,.083)),skin.darkened(.06),Vector3(0,-.065,.013))
	_piece(skeleton,"Head","Hair",_ellipsoid(Vector3(.108,.077,.104)),Color("493f33"),Vector3(0,.085,-.015))
	_piece(skeleton,"Head","Nose",_box(Vector3(.034,.043,.04)),skin.lightened(.12),Vector3(0,-.005,.10))
	for side in [-1,1]:
		var suffix: String="L" if side<0 else "R"
		_piece(skeleton,"Head","Eye"+suffix,_box(Vector3(.025,.016,.014)),Color("30332b"),Vector3(side*.039,.026,.09))
		_piece(skeleton,"Head","Ear"+suffix,_ellipsoid(Vector3(.023,.034,.025)),skin,Vector3(side*.102,-.012,-.004))
		_piece(skeleton,"Thigh"+suffix,"Trouser",_rings([[0,.086,.096],[-.18,.077,.086],[-.43,.061,.066]]),dark)
		_piece(skeleton,"Shin"+suffix,"Calf",_rings([[.025,.064,.066],[-.15,.071,.075],[-.41,.044,.046]]),dark.lightened(.08))
		_piece(skeleton,"Shin"+suffix,"BootCuff",_rings([[-.19,.067,.071],[-.39,.048,.054]]),leather)
		_piece(skeleton,"Foot"+suffix,"Boot",_ellipsoid(Vector3(.066,.070,.135)),leather,Vector3(0,-.012,.045))
		_piece(skeleton,"Foot"+suffix,"Sole",_box(Vector3(.12,.028,.23)),dark.darkened(.3),Vector3(0,-.060,.04))
		_piece(skeleton,"UpperArm"+suffix,"Sleeve",_rings([[.025,.086,.089],[-.10,.081,.079],[-.29,.058,.06]]),coat)
		_piece(skeleton,"Forearm"+suffix,"Arm",_rings([[.02,.058,.058],[-.13,.050,.051],[-.27,.038,.042]]),skin.darkened(.04))
		_piece(skeleton,"Forearm"+suffix,"Bracer",_rings([[-.10,.055,.056],[-.24,.043,.049]]),leather)
		_piece(skeleton,"Hand"+suffix,"Palm",_ellipsoid(Vector3(.044,.061,.04)),skin)
	if asset=="guard":
		_piece(skeleton,"Head","Helmet",_ellipsoid(Vector3(.121,.098,.116)),steel,Vector3(0,.071,-.01))
		_piece(skeleton,"Head","Brow",_box(Vector3(.245,.038,.235)),steel.darkened(.18),Vector3(0,.025,.005))
		_piece(skeleton,"Spine","Breastplate",_rings([[.13,.16,.122],[.35,.208,.145],[.42,.17,.115]]),steel.darkened(.20))
		for side in [-1,1]:
			var suffix: String="L" if side<0 else "R"
			_piece(skeleton,"UpperArm"+suffix,"Pauldron",_ellipsoid(Vector3(.112,.093,.116)),steel,Vector3(0,-.012,0))
			_piece(skeleton,"Head","Cheek"+suffix,_box(Vector3(.024,.11,.09)),steel.darkened(.1),Vector3(side*.104,-.05,-.002))
			_piece(skeleton,"Thigh"+suffix,"Tasset",_box(Vector3(.13,.18,.028)),steel.darkened(.2),Vector3(0,-.11,.093))
			_piece(skeleton,"Shin"+suffix,"Knee",_ellipsoid(Vector3(.066,.067,.034)),steel,Vector3(0,0,.059))
	if asset=="archer":
		_piece(skeleton,"Head","Hood",_ellipsoid(Vector3(.13,.115,.124)),coat.darkened(.1),Vector3(0,.067,-.045))
		_piece(skeleton,"Spine","ShoulderCape",_rings([[.32,.227,.144],[.43,.155,.116]]),coat.lightened(.12))
		var strap:=_piece(skeleton,"Spine","CrossStrap",_box(Vector3(.045,.40,.028)),leather,Vector3(0,.25,.147))
		strap.rotation.z=-.43
		var quiver:=_piece(skeleton,"Spine","Quiver",_rings([[0,.067,.065],[.40,.080,.075]]),leather,Vector3(.14,.13,-.185))
		quiver.rotation.z=-.2
		for index in 3:
			_piece(skeleton,"Spine","Arrow%d"%index,_box(Vector3(.014,.24,.014)),Color("b3a375"),Vector3(.12+index*.032,.53,-.19))
			_piece(skeleton,"Spine","Fletching%d"%index,_box(Vector3(.035,.075,.025)),Color("c6bea0"),Vector3(.12+index*.032,.61,-.19))
	else:
		_piece(skeleton,"Pelvis","Pouch",_ellipsoid(Vector3(.07,.085,.055)),leather,Vector3(-.165,-.07,-.015))
	return model

func _piece(skeleton: Skeleton3D, bone: String, id: String, mesh: Mesh, color: Color, at:=Vector3.ZERO) -> MeshInstance3D:
	var item:=MeshInstance3D.new()
	item.name=id
	item.mesh=mesh
	item.position=at
	var material:=StandardMaterial3D.new()
	material.albedo_color=color
	material.roughness=.9
	item.material_override=material
	skeleton.get_node(bone).add_child(item)
	return item
func _box(size: Vector3) -> BoxMesh:
	var box:=BoxMesh.new()
	box.size=size
	return box
func _ellipsoid(radius: Vector3) -> ArrayMesh:
	var sphere:=SphereMesh.new()
	sphere.radius=1
	sphere.height=2
	sphere.radial_segments=12
	sphere.rings=6
	var surface:=SurfaceTool.new()
	surface.create_from(sphere,0)
	var arrays:=surface.commit_to_arrays()
	var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	for i in points.size(): points[i]*=radius
	arrays[Mesh.ARRAY_VERTEX]=points
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
func _rings(rings: Array) -> ArrayMesh:
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertices: Array[Vector3]=[]
	for ring in rings:
		for index in 10:
			var angle:=TAU*index/10
			vertices.append(Vector3(cos(angle)*ring[1],ring[0],sin(angle)*ring[2]))
	for row in rings.size()-1:
		for index in 10:
			var a:=row*10+index
			var b:=row*10+(index+1)%10
			for vertex in ([a,b,b+10,a,b+10,a+10] if float(rings[1][0])>float(rings[0][0]) else [a,b+10,b,a,a+10,b+10]): surface.add_vertex(vertices[vertex])
	for row in [0,rings.size()-1]:
		for index in range(1,9):
			for vertex in [row*10,row*10+index,row*10+index+1]: surface.add_vertex(vertices[vertex])
	surface.generate_normals()
	return surface.commit()
