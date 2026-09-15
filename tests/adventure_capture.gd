extends Node
## Visual capture for review: opens the village, accepts the contract, and saves one rendered frame
## so the level's presentation can be judged. Also walks to the forest and back to prove the flow in
## a real window.
##
## Run with a real window:
##   godot --path <project> --windowed res://tests/adventure_capture.tscn
## Writes work/t06_village_frame.png and work/t06_forest_frame.png.

const VILLAGE := "res://scenes/level_village.tscn"

var _frames := 0
var _village: Node

func _ready() -> void:
	GameSession.start_new_run(3)
	_village = (load(VILLAGE) as PackedScene).instantiate()
	## The capture scene is not the main scene, so the level must become the tree's current scene
	## itself. The root is busy during _ready, hence the deferred add.
	get_tree().root.add_child.call_deferred(_village)
	set_physics_process(false)
	_boot()

func _boot() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = _village
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	_frames += 1
	match _frames:
		20:
			## Accept the contract the way a player would, then report the HUD state.
			var giver := _village.get_node("QuestGiver") as QuestGiver
			print("CAPTURE village: quest prompt='%s' accepted=%s" % [giver.prompt_text(), giver.interact()])
			print("CAPTURE session: stage=%s" % GameSession.current.stage_label())
		30:
			await _save("res://work/t06_village_frame.png")
		40:
			var flow := _village as LevelFlow
			print("CAPTURE leaving for the forest -> %s" % flow.go_to_level(&"forest"))
		70:
			var forest := get_tree().current_scene
			print("CAPTURE forest loaded: %s" % (forest.name if forest else "null"))
			await _save("res://work/t06_forest_frame.png")
			get_tree().quit(0)

func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	print("CAPTURE saved=%s error=%d" % [path, error])
