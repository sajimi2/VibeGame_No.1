class_name ActorTuning
extends Resource
## Every combat/locomotion number for one actor kind, in one place. Values are the DESIGN.md
## starting points and are explicitly tunable defaults, not final design. Actors never read
## constants from UI, AI or animation callbacks; they read this resource.

@export_group("Locomotion")
@export var move_speed: float = 90.0
@export var dodge_speed: float = 240.0
@export var dodge_seconds: float = 0.32
## Invulnerability window measured from dodge start: [start, end).
@export var dodge_invuln_start: float = 0.08
@export var dodge_invuln_end: float = 0.22

@export_group("Vitals")
@export var max_health: float = 100.0
@export var max_stamina: float = 100.0
@export var stamina_regen_per_second: float = 24.0
## Stamina stays untouched for this long after a spend, then regenerates.
@export var stamina_regen_delay: float = 0.6
@export var armor: float = 0.0
@export var team_id: int = 1

@export_group("Reactions")
@export var hit_stagger_seconds: float = 0.18
## While holding block, stamina does not regenerate.
@export var guard_break_stagger_seconds: float = 0.6
@export var knockback_damping: float = 12.0

@export_group("Actions")
@export var light_attack: AttackSpec
@export var heavy_attack: AttackSpec
## Optional extra attack used by Action.DASH (a beast's lunge). Null for actors without one.
@export var dash_attack: AttackSpec
## Dodge costs its own stamina (DESIGN: 25).
@export var dodge_stamina_cost: float = 25.0
