extends SceneTree
var failures := 0
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("%s %s" % ["PASS" if value else "FAIL", label])

func frames(count: int) -> void:
	for i in count: await physics_frame

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/stage3_%s.png" % name)

func run() -> void:
	await frames(2)
	for region in ["village", "forest", "outpost_lower", "outpost_upper"]:
		GameSession.start_new_run()
		var level := load("res://scenes/level_%s.tscn" % region).instantiate() as LevelFlow
		root.add_child(level)
		current_scene = level
		var player := level.get_node("Player") as PlayerController
		player.position = Vector2(340, 270) if region == "village" else Vector2(430, 290)
		if region == "outpost_upper": player.position = Vector2(530, 270)
		var camera := player.get_node("FollowCamera") as Camera2D
		camera.reset_smoothing()
		await frames(12)
		var presentation := level.get_node("Presentation")
		check(player.has_node("PixelArt"), region + " installs player art")
		check(not player.get_node("Visual/Body").visible, region + " replaces diamond")
		var audio_source := level.get_node_or_null(level.sfx_path) as SfxPlayer
		check(audio_source != null and audio_source._music.playing, region + " music plays")
		check(audio_source != null and audio_source._ambient.playing, region + " ambience plays")
		check(audio_source._music.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "music loops")
		await capture(region)
		if region == "forest":
			var manager := level.get_node("Encounters") as EncounterManager
			check(manager.total_alive_enemies() > 0, "actual encounter generated")
			for enemy in manager.all_enemy_nodes():
				check(enemy.has_node("PixelArt"), "spawned enemy has presentation")
			var event := DamageEvent.new()
			event.source_id = 30001
			event.attack_id = 1
			event.team_id = 2
			event.raw_damage = 10
			event.origin = player.global_position + Vector2(20, 0)
			player.get_node("ActorCombatant").receive_hit(event)
			check(player.get_node("PixelArt").effect_time > 0, "damage event creates visible feedback")
			check(presentation.shake_time > 0, "player damage starts bounded shake")
			await capture("hit")
			presentation.set_shake_enabled(false)
			await frames(2)
			check(camera.offset == Vector2.ZERO, "shake disable restores camera")
			var e := InputEventKey.new()
			e.physical_keycode = KEY_ESCAPE
			e.pressed = true
			Input.parse_input_event(e)
			await frames(2)
			check(paused and presentation.settings.visible, "Escape opens settings and pauses world")
			check(audio_source.can_process(), "audio stays active while adjusting volume")
			var bag_key := InputEventKey.new()
			bag_key.physical_keycode = KEY_I
			bag_key.pressed = true
			Input.parse_input_event(bag_key)
			await frames(2)
			check(paused and presentation.settings.visible, "inventory key cannot unpause settings")
			bag_key = InputEventKey.new()
			bag_key.physical_keycode = KEY_I
			Input.parse_input_event(bag_key)
			await capture("settings")
			e = InputEventKey.new()
			e.physical_keycode = KEY_ESCAPE
			Input.parse_input_event(e)
			await frames(2)
			e = InputEventKey.new()
			e.physical_keycode = KEY_ESCAPE
			e.pressed = true
			Input.parse_input_event(e)
			await frames(2)
			check(not paused, "Escape closes settings and resumes")
			audio_source.set_volume(1, 0)
			check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "music mute works")
			audio_source.set_volume(1, 0.35)
		level.queue_free()
		await frames(3)
	print("STAGE3_PRESENTATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
