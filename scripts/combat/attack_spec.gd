class_name AttackSpec
extends Resource
## One attack's numbers. WINDUP deals no damage, ACTIVE is the only damage window, RECOVERY
## commits the attacker. All times are seconds accumulated from physics delta, never frames.

@export var damage: float = 18.0
@export var stamina_cost: float = 16.0
@export var windup_seconds: float = 0.16
@export var active_seconds: float = 0.10
@export var recovery_seconds: float = 0.28
## Reach measured from the body centre to the far edge of the damage box, in logical pixels.
@export var range_pixels: float = 26.0
## Half-height of the damage box.
@export var half_height_pixels: float = 10.0
## Extra center offset so the box sits in front of the body rather than on it.
@export var forward_offset_pixels: float = 8.0
## Stamina damage this attack inflicts when it is blocked.
@export var stamina_damage: float = 16.0
@export var stagger_seconds: float = 0.18
@export var knockback_pixels: float = 26.0

@export_group("Motion")
## How the attacker may steer while this attack is committed. STATIONARY is the default and keeps
## every existing enemy attack planted; the player's weapons opt in explicitly.
enum MoveMode {
	## No steering at all: the attack owns the body until RECOVERY ends.
	STATIONARY,
	## The attacker keeps its full locomotion speed through WINDUP/ACTIVE/RECOVERY.
	FULL_SPEED,
	## Locomotion is kept but multiplied by move_speed_scale (a heavy weapon's committed walk).
	SCALED,
}

@export var move_mode: MoveMode = MoveMode.STATIONARY
## Fraction of the actor's locomotion speed available while SCALED. Ignored by the other modes.
@export var move_speed_scale: float = 1.0
## Forward travel along the locked attack direction, applied only while the damage window (ACTIVE)
## is open. This is what makes a heavy swing read as stepping into the blow instead of a slide.
@export var strike_advance_pixels: float = 0.0
## When > 0 the attacker keeps moving along its locked attack direction during WINDUP/ACTIVE/
## RECOVERY, covering about this many pixels in total. This is what makes a beast's lunge read as
## a lunge instead of a stationary swing; the speed is derived so the distance is the tuning knob.
@export var charge_distance_pixels: float = 0.0

@export_group("Projectile")
## When true the attack spawns a projectile instead of using the melee damage box.
@export var spawns_projectile: bool = false
## Scene instantiated for the projectile; must expose setup(direction, team_id, spec, source_id).
@export var projectile_scene: PackedScene
@export var projectile_speed_pixels: float = 210.0
## Maximum flight distance before the projectile expires on its own.
@export var projectile_max_range_pixels: float = 260.0
