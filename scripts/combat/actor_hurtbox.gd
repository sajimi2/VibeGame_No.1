class_name ActorHurtbox
extends Area2D
## Marker + shape holder for "this body can be hit". The shape is what the attacker's physics
## query reports; no damage logic lives here. Monitoring is off because nothing needs to react to
## overlap: attacks query the space, they are not pushed events.

func _ready() -> void:
	## An actor can be spawned while an Area2D signal is being emitted (an encounter reacts to a
	## death, or a level transition instantiates the next scene), where these setters are blocked.
	monitoring = false
	set_deferred("monitorable", true)
