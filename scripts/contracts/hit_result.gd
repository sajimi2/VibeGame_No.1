class_name HitResult
extends RefCounted
enum Outcome { IGNORED, DAMAGED, BLOCKED, GUARD_BROKEN, DODGED }
var outcome: Outcome = Outcome.IGNORED
var damage_applied: float = 0.0
var killed: bool = false
