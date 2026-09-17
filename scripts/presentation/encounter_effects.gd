extends Node3D
## 集中创建程序音效、受击数字与短时效果，并管理临时节点的释放。
var streams: Dictionary = {}

## 预先合成并缓存各类音效，触发时直接复用音频资源。
func _ready() -> void:
	for kind in ["step","swing","bow","hit","alert","death"]: streams[kind] = make_sound(kind)

## 把简短波形与噪声合成为 16 位 PCM 数据；固定种子使同类音效可复现。
func make_sound(kind: String) -> AudioStreamWAV:
	var rate := 22050
	var duration := 0.10 if kind == "step" else 0.32 if kind in ["alert","death"] else 0.17
	var data := PackedByteArray()
	data.resize(int(rate*duration)*2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 76+kind.hash()
	for i in data.size()/2:
		var t := float(i)/rate
		var fade := pow(1-t/duration,2)
		var value := 0.0
		match kind:
			"step": value = (sin(t*TAU*110)*0.3+rng.randf_range(-0.25,0.25))*fade
			"swing": value = rng.randf_range(-0.5,0.5)*sin(t/duration*PI)*fade
			"bow": value = sin(t*TAU*(650-1200*t))*fade*0.4
			"hit": value = (rng.randf_range(-0.6,0.6)+sin(t*TAU*85)*0.4)*fade
			"alert": value = sin(t*TAU*(540 if t<0.16 else 730))*fade*0.35
			"death": value = sin(t*TAU*(180-300*t))*fade*0.5
		data.encode_s16(i*2,int(clampf(value,-1,1)*26000))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	return stream

## 在世界位置播放空间音效，播放结束后自动释放临时播放器。
func sound(kind: String, where: Vector3) -> void:
	if not streams.has(kind): return
	var audio := AudioStreamPlayer3D.new()
	audio.stream = streams[kind]
	audio.volume_db = -22 if kind=="step" else -12
	audio.max_distance = 24
	add_child(audio)
	audio.global_position = where
	audio.finished.connect(audio.queue_free)
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
	sound("step",where)
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
