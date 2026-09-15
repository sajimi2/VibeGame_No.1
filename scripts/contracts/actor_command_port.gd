@abstract
class_name ActorCommandPort
extends Node
## Player input and AI send intentions to this actor-local component.
## No game logic may poll Input outside the player input adapter.
enum Action { LIGHT_ATTACK, HEAVY_ATTACK, DODGE, DASH }
enum State { IDLE, MOVE, WINDUP, ACTIVE, RECOVERY, DODGE, BLOCK, STAGGER, DEAD }
signal state_changed(previous: State, current: State)

## Called each physics tick. Normalize movement if length > 1.
## Zero aim preserves the last non-zero facing direction.
@abstract
func set_intent(move_axis: Vector2, aim_direction: Vector2, block_held: bool) -> void

## Returns true only if a legal action starts AND its cost is paid once.
## Rejection changes neither state nor stamina. No input buffering in v0.1.
@abstract
func request_action(action: Action) -> bool

@abstract
func get_state() -> State

## World-space expected velocity for this physics step, in logical pixels per second, for the
## owning body to hand to move_and_slide(). Pure read: must not spend stamina, advance timers or
## emit signals. The body owns the real collided velocity afterwards. DEAD returns zero.
@abstract
func get_velocity() -> Vector2

## World-space unit vector the actor currently faces. Downstream code (hitboxes, block arcs,
## T02) reads facing from here, never from a visual node. Defaults to RIGHT; zero aim in
## set_intent preserves the previous facing.
@abstract
func get_facing() -> Vector2

## Seconds accumulated in the current state by physics delta. Pure read. The body needs it to
## move during DODGE, the combatant to test its invulnerability window, and the HUD to show a
## charge. Zero for states that do not accumulate time.
@abstract
func get_state_elapsed() -> float

## Id of the attack currently being performed, incremented once per accepted attack. Together
## with the attacker's instance id it forms the per-target deduplication key, so a target can
## only be hit once per swing. Zero while no attack is running.
@abstract
func get_attack_id() -> int
