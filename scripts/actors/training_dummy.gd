class_name TrainingDummy
extends CharacterBody2D
## A stationary target for reading the ACTIVE window and damage: no AI, no state machine, never
## attacks. It exists so hit feedback can be judged without an enemy chasing the player.

const HIT_FLASH_SECONDS := 0.15
const HIT_TINT := Color.WHITE
const BASE_TINT := Color(0.55, 0.5, 0.36)

@export var combatant_path: NodePath

var _combatant: ActorCombatant
var _body_visual: Polygon2D
var _flash_timer := 0.0

func _ready() -> void:
	_combatant = get_node_or_null(combatant_path) as ActorCombatant
	_body_visual = get_node_or_null("Visual/Body") as Polygon2D
	if _combatant != null:
		_combatant.hurt.connect(_on_hurt)
		_combatant.health_changed.connect(_on_health_changed)

func _physics_process(delta: float) -> void:
	velocity = Vector2.ZERO
	if _flash_timer <= 0.0:
		return
	_flash_timer = maxf(0.0, _flash_timer - delta)
	if _body_visual == null:
		return
	_body_visual.color = HIT_TINT if _flash_timer > 0.0 else BASE_TINT

func _on_hurt(_damage: float, _origin: Vector2) -> void:
	_flash_timer = HIT_FLASH_SECONDS

## When destroyed the dummy dims instead of vanishing, so the kill is visible.
func _on_health_changed(current: float, _maximum: float) -> void:
	if current <= 0.0 and _body_visual != null:
		_body_visual.color = Color(0.3, 0.28, 0.24)
