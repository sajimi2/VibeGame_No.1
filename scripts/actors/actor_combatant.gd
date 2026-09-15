class_name ActorCombatant
extends CombatantPort
## Concrete CombatantPort: sole owner of health and stamina, and the only place a hit is
## resolved. Hitboxes and the HUD never decide damage; they hand a DamageEvent here and read the
## HitResult or the signals.

signal hurt(damage: float, origin: Vector2)
signal blocked(origin: Vector2)
signal dodged
signal knockback_applied(impulse: Vector2)
signal stamina_regen_changed(regenerating: bool)

## Guards only cover this half-angle around the actor's facing direction (DESIGN: 120 degrees).
const GUARD_HALF_ANGLE_DEGREES := 60.0

@export var tuning: ActorTuning
## ActorCommandPort component; receives STAGGER / DEAD and answers whether the guard is up.
@export var command_port_path: NodePath
## Optional equipment source. When set, equipped modifiers are added on top of the base tuning
## values. Stats are always recomputed from base + equipment, never accumulated onto a previous
## result, so repeated equip/unequip cycles cannot drift.
@export var inventory_path: NodePath
## Optional progression source. Adds the level-up attribute bonuses to the ceilings.
@export var progression_path: NodePath

const STAT_ATTACK := &"attack"
const STAT_ARMOR := &"armor"
const STAT_MAX_HEALTH := &"max_health"
const STAT_MAX_STAMINA := &"max_stamina"
const STAT_MOVE_SPEED := &"move_speed"

var _health: float = 100.0
var _stamina: float = 100.0
var _regen_delay_remaining := 0.0
var _regenerating := false
var _command_port: ActorCommandPort
var _inventory: ActorInventory
var _progression: ActorProgression
## Equipment-derived additive bonuses, refreshed by refresh_equipment().
var _equipment_modifiers: Dictionary = {}
## Per-target hit deduplication: one (source_id, attack_id) may only land once. Cleared by
## reset_vitals() so a retry can be hit again.
var _seen_attacks: Dictionary = {}

func _ready() -> void:
	_command_port = get_node_or_null(command_port_path) as ActorCommandPort
	_inventory = get_node_or_null(inventory_path) as ActorInventory
	_progression = get_node_or_null(progression_path) as ActorProgression
	if tuning != null:
		_health = tuning.max_health
		_stamina = tuning.max_stamina
	else:
		push_error("ActorCombatant: tuning resource is required")
	## A command port is optional: a static target has no actions and simply never staggers.
	if _command_port == null and not command_port_path.is_empty():
		push_error("ActorCombatant: command_port_path does not point at an ActorCommandPort")
	## Equipment changes must re-derive stats; the signal is the only trigger, so a swap from the
	## UI, a reward, or a future save load all take the same path.
	if _inventory != null:
		_inventory.equipment_changed.connect(_on_equipment_changed)
	## Levelling raises ceilings; the same refresh path re-clamps instead of healing.
	if _progression != null:
		_progression.attribute_increased.connect(_on_attribute_increased)
	refresh_equipment()
	health_changed.emit(_health, max_health())
	stamina_changed.emit(_stamina, max_stamina())

func _on_equipment_changed(_slot: StringName, _instance_id: String) -> void:
	refresh_equipment()

func _on_attribute_increased(_attribute: int, _amount: float) -> void:
	refresh_equipment()

## Recomputes equipment bonuses from scratch and clamps current values to the new ceilings.
## DESIGN: raising a maximum never heals, and lowering one clamps the current value.
func refresh_equipment() -> void:
	if _inventory == null:
		_equipment_modifiers = {}
		_clamp_to_ceilings()
		return
	_equipment_modifiers = _inventory.equipped_modifiers()
	_clamp_to_ceilings()
	health_changed.emit(_health, max_health())
	stamina_changed.emit(_stamina, max_stamina())

func equipment_modifier(key: StringName) -> float:
	return float(_equipment_modifiers.get(key, 0.0))

## Weapon damage bonus added to every attack this actor makes.
func attack_bonus() -> float:
	return equipment_modifier(STAT_ATTACK)

## Behaviour of the equipped weapon, or null when unarmed or when this actor has no inventory
## (every enemy). ActorActionPort asks for this on each attack so a weapon swap takes effect on the
## next swing without the port caching anything.
func equipped_weapon_profile() -> WeaponProfile:
	if _inventory == null:
		return null
	return _inventory.equipped_weapon_profile()

func _clamp_to_ceilings() -> void:
	_health = minf(_health, max_health())
	_stamina = minf(_stamina, max_stamina())

func receive_hit(event: DamageEvent) -> HitResult:
	var result := HitResult.new()
	if event == null or not is_alive():
		return result
	if not _is_hostile(event):
		return result
	if event.raw_damage <= 0.0 and event.stamina_damage <= 0.0:
		return result

	## Dodge is resolved before block: a dodge outranks holding the shield.
	if _is_dodging():
		result.outcome = HitResult.Outcome.DODGED
		dodged.emit()
		return result

	var guard_held := _is_blocking()
	var from_front := _is_from_front(event.origin)
	var guard_broken := false
	if guard_held and from_front and event.stamina_damage > 0.0:
		if try_spend_stamina(event.stamina_damage):
			result.outcome = HitResult.Outcome.BLOCKED
			blocked.emit(event.origin)
		else:
			## Guard break: stamina is already zero, this hit lands for full damage.
			guard_broken = true
	elif guard_held and from_front:
		result.outcome = HitResult.Outcome.BLOCKED
		blocked.emit(event.origin)

	if result.outcome == HitResult.Outcome.BLOCKED:
		if event.knockback.length() > 0.0:
			knockback_applied.emit(event.knockback)
		return result

	var applied := physical_damage(event.raw_damage)
	_health = maxf(0.0, _health - applied)
	result.outcome = HitResult.Outcome.GUARD_BROKEN if guard_broken else HitResult.Outcome.DAMAGED
	result.damage_applied = applied
	health_changed.emit(_health, max_health())
	if event.knockback.length() > 0.0:
		knockback_applied.emit(event.knockback)
	hurt.emit(applied, event.origin)

	if _health <= 0.0:
		result.killed = true
		_die()
	elif _command_port != null:
		if guard_broken:
			_command_port.apply_stagger(tuning.guard_break_stagger_seconds)
		elif event.stagger_seconds > 0.0:
			_command_port.apply_stagger(event.stagger_seconds)
	return result

## DESIGN: raw damage must be non-negative and physical damage is max(1, raw - armor),
## applied only when raw damage is positive.
func physical_damage(raw_damage: float) -> float:
	if raw_damage <= 0.0:
		return 0.0
	var armor := (tuning.armor if tuning != null else 0.0) + equipment_modifier(STAT_ARMOR)
	return maxf(1.0, raw_damage - armor)

## Atomic: <= 0 or insufficient stamina returns false, changing nothing.
func try_spend_stamina(amount: float) -> bool:
	if amount <= 0.0:
		return false
	if _stamina < amount:
		return false
	_stamina -= amount
	_regen_delay_remaining = tuning.stamina_regen_delay if tuning != null else 0.0
	_set_regenerating(false)
	stamina_changed.emit(_stamina, max_stamina())
	return true

func is_alive() -> bool:
	return _health > 0.0

func get_snapshot() -> Dictionary:
	return {
		"health": _health,
		"max_health": max_health(),
		"stamina": _stamina,
		"max_stamina": max_stamina(),
		"alive": is_alive(),
	}

## Base tuning value plus equipped bonuses plus level-up bonuses. Always recomputed, never
## accumulated.
func max_health() -> float:
	var base := tuning.max_health if tuning != null else 0.0
	var level_bonus := _progression.bonus_max_health() if _progression != null else 0.0
	return maxf(1.0, base + equipment_modifier(STAT_MAX_HEALTH) + level_bonus)

func max_stamina() -> float:
	var base := tuning.max_stamina if tuning != null else 0.0
	var level_bonus := _progression.bonus_max_stamina() if _progression != null else 0.0
	return maxf(0.0, base + equipment_modifier(STAT_MAX_STAMINA) + level_bonus)

func get_health() -> float:
	return _health

func get_stamina() -> float:
	return _stamina

## Sets current values, clamped to the current ceilings. Used when arriving in a level so a
## transition carries the player's state without being able to exceed the maximums.
func set_vitals(health: float, stamina: float) -> void:
	_health = clampf(health, 0.0, max_health())
	_stamina = clampf(stamina, 0.0, max_stamina())
	health_changed.emit(_health, max_health())
	stamina_changed.emit(_stamina, max_stamina())

## Extra hit sources for this target: an attack id may only ever land once per attack.
func has_seen(source_id: int, attack_id: int) -> bool:
	return _seen_attacks.has(_attack_key(source_id, attack_id))

func mark_seen(source_id: int, attack_id: int) -> void:
	_seen_attacks[_attack_key(source_id, attack_id)] = true

## Restores the actor to full for a retry. Clears hit deduplication: after a reset the scene
## restarts, so old attack ids must not suppress new hits.
func reset_vitals() -> void:
	_seen_attacks.clear()
	_regen_delay_remaining = 0.0
	_set_regenerating(false)
	_health = max_health()
	_stamina = max_stamina()
	health_changed.emit(_health, max_health())
	stamina_changed.emit(_stamina, max_stamina())

func _physics_process(delta: float) -> void:
	_update_stamina(delta)

func _update_stamina(delta: float) -> void:
	if tuning == null or not is_alive():
		_set_regenerating(false)
		return
	if _regen_delay_remaining > 0.0:
		_regen_delay_remaining = maxf(0.0, _regen_delay_remaining - delta)
		_set_regenerating(false)
		return
	if _command_port != null and not ActionRules.stamina_regenerates(_command_port.get_state()):
		_set_regenerating(false)
		return
	if _stamina >= max_stamina():
		_set_regenerating(false)
		return
	_set_regenerating(true)
	_stamina = minf(max_stamina(), _stamina + tuning.stamina_regen_per_second * delta)
	stamina_changed.emit(_stamina, max_stamina())

func _set_regenerating(value: bool) -> void:
	if _regenerating == value:
		return
	_regenerating = value
	stamina_regen_changed.emit(value)

func _is_hostile(event: DamageEvent) -> bool:
	if tuning == null:
		return true
	return event.team_id != tuning.team_id

## Deduplication key. A single int key keeps the per-target record cheap.
func _attack_key(source_id: int, attack_id: int) -> int:
	return hash(Vector2i(source_id, attack_id))

func _is_blocking() -> bool:
	return _command_port != null and _command_port.get_state() == ActorCommandPort.State.BLOCK

func _is_dodging() -> bool:
	if _command_port == null or tuning == null:
		return false
	var state := _command_port.get_state()
	if state != ActorCommandPort.State.DODGE:
		return false
	return ActionRules.is_invulnerable(state, _command_port.get_state_elapsed(), tuning.dodge_invuln_start, tuning.dodge_invuln_end)

## DESIGN: the shield covers the front 120 degrees; attacks from behind land normally.
func _is_from_front(origin: Vector2) -> bool:
	var to_attacker := origin - global_position
	if to_attacker.length() <= ActorMovement.MIN_AXIS_LENGTH:
		return true
	var facing := Vector2.RIGHT
	if _command_port != null:
		facing = _command_port.get_facing()
	return absf(rad_to_deg(facing.angle_to(to_attacker))) <= GUARD_HALF_ANGLE_DEGREES

func _die() -> void:
	if _command_port != null:
		_command_port.apply_death()
	_set_regenerating(false)
	died.emit(get_instance_id())
