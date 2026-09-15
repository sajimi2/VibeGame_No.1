@abstract
class_name CombatantPort
extends Node2D
## Implement as a child component of a CharacterBody2D actor.
## Sole owner of HP/stamina and final hit resolution. UI observes signals.
signal health_changed(current: float, maximum: float)
signal stamina_changed(current: float, maximum: float)
signal died(source_id: int)

## Synchronous, exactly-once death transition; returns IGNORED if already dead,
## invalid, friendly, or a repeated (source_id, attack_id) for this target.
## Damage never heals. Handle dodge/block/armor here, not in hitbox or HUD.
@abstract
func receive_hit(event: DamageEvent) -> HitResult

## Atomic: <= 0 or insufficient stamina returns false, changing nothing.
@abstract
func try_spend_stamina(amount: float) -> bool

@abstract
func is_alive() -> bool

## Read-only snapshot: health, max_health, stamina, max_stamina (float),
## alive (bool). Return a fresh dictionary, not internal mutable state.
@abstract
func get_snapshot() -> Dictionary
