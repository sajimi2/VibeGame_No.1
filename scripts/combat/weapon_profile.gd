class_name WeaponProfile
extends Resource
## What a weapon *does*, as opposed to what it is worth: the two attack specs it swaps in when it
## is equipped, plus the one-line movement description the HUD shows.
##
## Weapon behaviour lives here rather than in ActorTuning because the player owns several weapons
## and switches between them at runtime; ActorActionPort resolves the equipped weapon's profile on
## every attack request and falls back to the tuning's own specs when the weapon slot is empty
## (fists) or when the actor has no inventory at all (every enemy).

## The light attack this weapon replaces the tuning's light attack with. Null keeps the fallback.
@export var light_attack: AttackSpec
## The heavy attack this weapon replaces the tuning's heavy attack with. Null keeps the fallback.
@export var heavy_attack: AttackSpec
## Short movement summary for the HUD, e.g. "出招可全速移动".
@export var description: String = ""

## Resolves which spec an action should use: the weapon's own spec when it defines one, otherwise
## the actor's fallback spec. Keeping this here means the action port never has to know how many
## weapons exist or in what order they are registered.
func spec_for(is_heavy: bool, fallback: AttackSpec) -> AttackSpec:
	var candidate := heavy_attack if is_heavy else light_attack
	return candidate if candidate != null else fallback
