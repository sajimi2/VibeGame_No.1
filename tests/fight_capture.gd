extends Node
## Visual capture for review. Drives the player into the mixed encounter (two archers + a beast),
## lets the fight develop until an arrow is in the air or the player takes a hit, then saves one
## rendered frame and prints the state. This is the "does it actually look and play right" check
## that a headless assertion cannot make.
##
## Run with a real window:
##   godot --path <project> --windowed res://tests/fight_capture.tscn
## Writes work/t03_encounter_frame.png.

const MAX_FRAMES := 2400
const OUTPUT_PATH := "res://work/t03_encounter_frame.png"

var _arena: Node
var _encounters: EncounterManager
var _frames := 0

func _ready() -> void:
	_arena = (load("res://scenes/arena.tscn") as PackedScene).instantiate()
	add_child(_arena)
	_encounters = _arena.get_node("Encounters") as EncounterManager
	## Walk the player to the outpost encounter so archers, a beast and arrows are all on screen.
	_player().global_position = _encounters.activity_center(&"outpost") + Vector2(-90, 60)

func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames < MAX_FRAMES and not _should_capture():
		return
	_capture()

func _should_capture() -> bool:
	var player_combatant := _player().get_node("ActorCombatant") as ActorCombatant
	if player_combatant.get_health() < player_combatant.max_health():
		return true
	return _projectile_count() > 0

func _player() -> Node2D:
	return _arena.get_node("Player") as Node2D

func _projectile_count() -> int:
	var count := 0
	for node in _descendants(_arena):
		if node is CombatProjectile:
			count += 1
	return count

func _descendants(scope: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in scope.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found

func _capture() -> void:
	set_physics_process(false)
	var player := _player()
	var player_combatant := player.get_node("ActorCombatant") as ActorCombatant
	print("CAPTURE frame=%d player_hp=%.1f/%.1f arrows_in_flight=%d alive_enemies=%d" % [
		_frames, player_combatant.get_health(), player_combatant.max_health(),
		_projectile_count(), _encounters.total_alive_enemies()])
	for enemy in _encounters.all_enemy_nodes():
		var combatant := enemy.get_node_or_null("ActorCombatant") as ActorCombatant
		var port := enemy.get_node_or_null("ActorActionPort") as ActorCommandPort
		print("CAPTURE enemy=%s pos=%s hp=%.1f state=%d" % [
			enemy.name, enemy.global_position,
			combatant.get_health() if combatant else -1.0,
			port.get_state() if port else -1])
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(OUTPUT_PATH)
	print("CAPTURE saved=%s error=%d" % [OUTPUT_PATH, error])
	get_tree().quit(0 if error == OK else 1)
