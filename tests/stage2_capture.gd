extends Node
## Real-window visual capture for v0.2 阶段 2: the starting knife in hand, the village weapon rack,
## the claimed cleaver with the HUD weapon line, and a cleaver heavy strike mid-damage-window.
## It also measures the strike step and both weapons' attack-walk speed in the same real window, so
## the numbers can be read off one run instead of trusting the headless suite alone.
##
## Run with a real window:
##   godot --path <project> --windowed res://tests/stage2_capture.tscn
## Writes work/v02_stage2_knife.png, _cleaver.png and _strike.png.

const VILLAGE := "res://scenes/level_village.tscn"
const DUMMY := "res://scenes/training_dummy.tscn"
const KNIFE_INSTANCE := "starter-knife"
const CLEAVER_INSTANCE := "village-cleaver"

var _frames := 0
var _level: LevelFlow
var _player: PlayerController
var _port: ActorActionPort
var _inventory: ActorInventory
var _rack: WeaponRack
var _strike_speed := 0.0
var _strike_saved := false
var _walk_probe := ""
var _walk_start_frame := -1
var _walk_speeds: Dictionary = {}

func _ready() -> void:
	## Runs after the player's own step (priority 0), so the state and the velocity read here come
	## from the same completed physics step.
	process_physics_priority = 100
	GameSession.start_new_run(3)
	_level = (load(VILLAGE) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_level)
	set_physics_process(false)
	_boot()

func _boot() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = _level
	_player = _level.get_node("Player") as PlayerController
	_port = _player.get_node("ActorActionPort") as ActorActionPort
	_inventory = _player.get_node("ActorInventory") as ActorInventory
	_rack = _level.get_node("WeaponRack") as WeaponRack
	## Deterministic facing for the capture: the device is not used, so the strike goes east.
	_player.test_intent_override = true
	_player.test_intent_move = Vector2.ZERO
	_player.test_intent_aim = Vector2.RIGHT
	_player.global_position = _rack.global_position + Vector2(20, 0)
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	_frames += 1
	match _frames:
		20:
			print("CAPTURE knife: %s" % _level.equipped_weapon_label())
			print("CAPTURE rack prompt='%s' in_range=%s" % [_rack.prompt_text(), _rack.is_player_inside()])
		30:
			await _save("res://work/v02_stage2_knife.png")
		40:
			print("CAPTURE claim=%s" % _rack.claim())
			print("CAPTURE after claim: %s" % _level.equipped_weapon_label())
		50:
			await _save("res://work/v02_stage2_cleaver.png")
		60:
			var dummy := (load(DUMMY) as PackedScene).instantiate()
			_level.add_child(dummy)
			dummy.global_position = _player.global_position + Vector2(26, 0)
			print("CAPTURE starting a standing heavy cleaver swing with a dummy at +26px")
			_port.request_action(ActorCommandPort.Action.HEAVY_ATTACK)
		190:
			## Walk probes: hold the move axis and read the attack's own locomotion for each weapon.
			_player.test_intent_move = Vector2.RIGHT
			_inventory.try_equip(KNIFE_INSTANCE, ActorInventory.SLOT_WEAPON)
			_walk_probe = "knife"
			_walk_start_frame = _frames
			_port.request_action(ActorCommandPort.Action.LIGHT_ATTACK)
		260:
			_inventory.try_equip(CLEAVER_INSTANCE, ActorInventory.SLOT_WEAPON)
			_walk_probe = "cleaver"
			_walk_start_frame = _frames
			_port.request_action(ActorCommandPort.Action.LIGHT_ATTACK)
		350:
			print("CAPTURE measured standing strike step=%.1f px/s" % _strike_speed)
			print("CAPTURE attack walk: knife=%.1f px/s cleaver=%.1f px/s (both attacking, move held)" % [
				float(_walk_speeds.get("knife", -1.0)), float(_walk_speeds.get("cleaver", -1.0))])
			get_tree().quit(0)
	if _frames > 60 and _frames < 190:
		var state := _port.get_state()
		if state == ActorCommandPort.State.ACTIVE:
			_strike_speed = _player.velocity.length()
			if not _strike_saved:
				_strike_saved = true
				await _save("res://work/v02_stage2_strike.png")
	if not _walk_probe.is_empty() and _frames > _walk_start_frame and _port.get_state() == ActorCommandPort.State.WINDUP:
		_walk_speeds[_walk_probe] = maxf(float(_walk_speeds.get(_walk_probe, 0.0)), _player.velocity.length())

func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	print("CAPTURE saved=%s error=%d" % [path, error])
