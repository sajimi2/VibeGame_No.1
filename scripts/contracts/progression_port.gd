@abstract
class_name ProgressionPort
extends Node
## Which stat a level-up point may be spent on. DESIGN v0.1 offers exactly these two.
enum Attribute { MAX_HEALTH, MAX_STAMINA }

signal experience_changed(level: int, xp_in_level: int, xp_to_next: int)
signal leveled_up(new_level: int)
signal points_changed(unspent_points: int)
## Emitted after a point is successfully spent, so the owning actor can recompute its stats.
signal attribute_increased(attribute: Attribute, amount: float)

## Nonpositive amount is ignored. Process every crossed threshold in order,
## preserve excess XP, emit leveled_up once per level then experience_changed.
## Enemy death grants XP once from encounter logic, never from the HUD.
@abstract
func grant_experience(amount: int) -> void

## Fresh snapshot: level, xp_in_level, xp_to_next, unspent_points (all int).
## Implementations may add read-only keys (e.g. base attribute bonuses); extra keys are additive.
@abstract
func get_snapshot() -> Dictionary

## Spends one unspent point on `attribute`. Atomic: with no points available, at the level cap, or
## on an unknown attribute it returns false and changes NOTHING. Spending a point never heals:
## raising a maximum raises the ceiling only, and the current value is left where it is.
@abstract
func spend_point(attribute: Attribute) -> bool
