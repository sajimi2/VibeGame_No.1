class_name DamageEvent
extends RefCounted
## A single candidate hit. No target mutation occurs in this value object.
## (source_id, attack_id) identifies a swing for per-target deduplication.
## source_id is the attacker's live instance ID; never persist it in save data.
var source_id: int = 0
var attack_id: int = 0
var team_id: int = 0
var raw_damage: float = 0.0
var stamina_damage: float = 0.0
var stagger_seconds: float = 0.0
var knockback: Vector2 = Vector2.ZERO
var origin: Vector2 = Vector2.ZERO
