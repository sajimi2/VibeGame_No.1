class_name ActorProgression
extends ProgressionPort
## Concrete ProgressionPort: level, experience and the level-up points earned along the way.
##
## DESIGN v0.1 rules implemented here:
##   - level cap 5;
##   - reaching level L+1 costs 50 * L experience;
##   - each level grants one unspent point, spendable on +5 max health or +5 max stamina;
##   - raising a maximum is not a heal (the actor clamps, never refills);
##   - at the cap, experience is zeroed and the next requirement is zero, and later experience is
##     ignored rather than looping.
##
## This node owns progression state only. Applying the attribute bonus to the actor is the
## actor's job, driven by the attribute_increased signal, so there is one place that owns stats.

const MAX_LEVEL := 5
const POINTS_PER_LEVEL := 1
const ATTRIBUTE_BONUS := 5.0
## Experience needed to go from level L to L+1.
const XP_PER_LEVEL_FACTOR := 50

var _level := 1
var _xp_in_level := 0
var _unspent_points := 0
var _bonus_max_health := 0.0
var _bonus_max_stamina := 0.0

func _ready() -> void:
	experience_changed.emit(_level, _xp_in_level, xp_to_next())
	points_changed.emit(_unspent_points)

# --- ProgressionPort -----------------------------------------------------------------------

func grant_experience(amount: int) -> void:
	if amount <= 0:
		return
	if is_at_cap():
		## At the cap experience is ignored; it neither accumulates nor loops.
		return
	_xp_in_level += amount
	## Every crossed threshold is processed in order, and excess experience is preserved.
	while not is_at_cap() and _xp_in_level >= xp_to_next():
		var required := xp_to_next()
		_xp_in_level -= required
		_level += 1
		_unspent_points += POINTS_PER_LEVEL
		leveled_up.emit(_level)
		points_changed.emit(_unspent_points)
	if is_at_cap():
		## DESIGN: at the cap experience is zeroed and the next requirement becomes zero.
		_xp_in_level = 0
	experience_changed.emit(_level, _xp_in_level, xp_to_next())

func get_snapshot() -> Dictionary:
	return {
		"level": _level,
		"xp_in_level": _xp_in_level,
		"xp_to_next": xp_to_next(),
		"unspent_points": _unspent_points,
		"bonus_max_health": _bonus_max_health,
		"bonus_max_stamina": _bonus_max_stamina,
	}

func spend_point(attribute: Attribute) -> bool:
	if _unspent_points <= 0:
		return false
	if attribute != Attribute.MAX_HEALTH and attribute != Attribute.MAX_STAMINA:
		return false
	## Commit: every rejection was handled above.
	_unspent_points -= 1
	if attribute == Attribute.MAX_HEALTH:
		_bonus_max_health += ATTRIBUTE_BONUS
	else:
		_bonus_max_stamina += ATTRIBUTE_BONUS
	points_changed.emit(_unspent_points)
	attribute_increased.emit(attribute, ATTRIBUTE_BONUS)
	experience_changed.emit(_level, _xp_in_level, xp_to_next())
	return true

# --- queries -------------------------------------------------------------------------------

func get_level() -> int:
	return _level

func get_xp_in_level() -> int:
	return _xp_in_level

func get_unspent_points() -> int:
	return _unspent_points

func is_at_cap() -> bool:
	return _level >= MAX_LEVEL

## Experience needed for the next level; zero once the cap is reached.
func xp_to_next() -> int:
	if is_at_cap():
		return 0
	return XP_PER_LEVEL_FACTOR * _level

func bonus_max_health() -> float:
	return _bonus_max_health

func bonus_max_stamina() -> float:
	return _bonus_max_stamina

## Retry: progression is part of the run, so a retry starts over.
func reset_for_retry() -> void:
	_level = 1
	_xp_in_level = 0
	_unspent_points = 0
	_bonus_max_health = 0.0
	_bonus_max_stamina = 0.0
	experience_changed.emit(_level, _xp_in_level, xp_to_next())
	points_changed.emit(_unspent_points)

## Restores a snapshot taken by get_snapshot(), e.g. when carrying state between levels. Unknown
## or missing keys fall back to the starting values rather than corrupting the run.
func restore_from_snapshot(snapshot: Dictionary) -> void:
	_level = clampi(int(snapshot.get("level", 1)), 1, MAX_LEVEL)
	_xp_in_level = maxi(0, int(snapshot.get("xp_in_level", 0)))
	_unspent_points = maxi(0, int(snapshot.get("unspent_points", 0)))
	_bonus_max_health = maxf(0.0, float(snapshot.get("bonus_max_health", 0.0)))
	_bonus_max_stamina = maxf(0.0, float(snapshot.get("bonus_max_stamina", 0.0)))
	if is_at_cap():
		_xp_in_level = 0
	experience_changed.emit(_level, _xp_in_level, xp_to_next())
	points_changed.emit(_unspent_points)
