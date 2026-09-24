extends AudioStreamPlayer
## 小院临时配乐。独立音乐总线支持背包调音，暂停整理时继续播放。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index("Music") < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count-1,"Music")
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"),linear_to_db(.4))
	bus = &"Music"
	var audio := load("res://assets/audio/sunlit_woodpath.mp3") as AudioStreamMP3
	stream = audio.duplicate()
	stream.loop = true
	volume_db = -40
	play()
	create_tween().tween_property(self,"volume_db",-5.0,2.0)
