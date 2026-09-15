class_name RecordingCommandPort
extends ActorCommandPort
## Test double: records what the input adapter submits and when, so submit ordering is observable
## without depending on whether the real port accepts a given action. Lives in tests/ and is never
## referenced by a scene.

var received_actions: Array[int] = []
var intent_count := 0
var last_move_axis := Vector2.ZERO

func set_intent(move_axis: Vector2, _aim_direction: Vector2, _block_held: bool) -> void:
	intent_count += 1
	last_move_axis = move_axis

func request_action(action: Action) -> bool:
	received_actions.append(action)
	return false

func get_state() -> State:
	return State.MOVE if last_move_axis != Vector2.ZERO else State.IDLE

func get_velocity() -> Vector2:
	return last_move_axis * 90.0

func get_facing() -> Vector2:
	return Vector2.RIGHT

func get_state_elapsed() -> float:
	return 0.0

func get_attack_id() -> int:
	return 0
