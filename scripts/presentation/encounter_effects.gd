extends Node3D
## 集中播放采样音效、受击数字与短时效果，并管理临时节点的释放。
var streams: Dictionary = {}

var observer: Node3D
var previous_clip: Dictionary={}
var last_play: Dictionary={}
var rng:=RandomNumberGenerator.new()
var voice_count:=0
var played_events: Dictionary={}

## 预载采样并建立音效总线，运行时不再生成波形或读取文件。
func _ready() -> void:
	rng.randomize()
	add_to_group("encounter_sound")
	if AudioServer.get_bus_index("SFX")<0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count-1,"SFX")
	for kind in preload("res://scripts/presentation/sound_library.gd").CLIPS:
		streams[kind]=[]
		for file in preload("res://scripts/presentation/sound_library.gd").CLIPS[kind]:
			streams[kind].append(load("res://assets/audio/sfx/"+file))

## 音量以玩家而非高空正交相机为基准；限制并发与同帧重复，轮换同类采样。
func sound(kind: String, where: Vector3) -> void:
	if kind=="step" and absf(where.x)<2.4 and where.z>-2.6 and where.z<2.8: kind="step_wood"
	if not streams.has(kind) or voice_count>=14: return
	var now:=Time.get_ticks_msec()
	if now-int(last_play.get(kind,-1000))<45: return
	var distance: float=observer.global_position.distance_to(where) if is_instance_valid(observer) else 0.0
	if distance>24: return
	last_play[kind]=now
	var choices: Array=streams[kind]
	var index:=rng.randi_range(0,choices.size()-1)
	if choices.size()>1 and index==previous_clip.get(kind,-1): index=(index+1)%choices.size()
	previous_clip[kind]=index
	var audio:=AudioStreamPlayer.new()
	audio.stream=choices[index]
	audio.bus=&"SFX"
	audio.process_mode=Node.PROCESS_MODE_ALWAYS
	audio.volume_db=(-13.0 if kind.begins_with("step") else -7.0)-minf(distance,22)*.8
	audio.pitch_scale=rng.randf_range(.95,1.05)
	add_child(audio)
	voice_count+=1
	played_events[kind]=int(played_events.get(kind,0))+1
	audio.finished.connect(func(): voice_count-=1; audio.queue_free())
	audio.play()

## 显示伤害数字、音效和火花；Tween 完成后释放临时节点。
func impact(where: Vector3, amount: int, killed: bool = false) -> void:
	sound("death" if killed else "hit",where)
	var number := Label3D.new()
	number.text = str(amount)
	number.font_size = 30
	number.pixel_size = 0.013
	number.modulate = Color("ffe0a0")
	number.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(number)
	number.global_position = where
	var tween := create_tween()
	tween.tween_property(number,"position",number.position+Vector3.UP*0.55,0.5)
	tween.parallel().tween_property(number,"modulate:a",0.0,0.5)
	tween.tween_callback(number.queue_free)
	for i in 6:
		var spark := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE*0.055
		spark.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color("efc277")
		spark.material_override = mat
		add_child(spark)
		spark.global_position = where
		var movement := Vector3(cos(i*TAU/6),0.35,sin(i*TAU/6))*0.35
		var motion := create_tween()
		motion.tween_property(spark,"position",spark.position+movement,0.18)
		motion.parallel().tween_property(spark,"scale",Vector3.ZERO,0.18)
		motion.tween_callback(spark.queue_free)

## 生成落地尘土和脚步声，各粒子随补间动画结束释放。
func landing(where: Vector3) -> void:
	sound("land",where)
	for i in 6:
		var dust := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size=Vector3(0.09,0.045,0.09)
		dust.mesh=mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color=Color("a99a75")
		dust.material_override=mat
		add_child(dust)
		dust.global_position=where+Vector3.UP*0.04
		var tween := create_tween()
		tween.tween_property(dust,"position",dust.position+Vector3(cos(i*TAU/6),0.12,sin(i*TAU/6))*0.5,0.22)
		tween.parallel().tween_property(dust,"scale",Vector3.ZERO,0.22)
		tween.tween_callback(dust.queue_free)
