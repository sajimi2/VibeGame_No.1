class_name EncounterGroup
extends Resource
## One fixed encounter: which enemies stand where, and the area the player must be inside for the
## encounter to be "engaged". Leaving the area disengages and clears the fight, which is what
## stops enemies from chasing the player across the whole level.

@export var id: StringName = &"encounter"
@export var enemy_scenes: Array[PackedScene] = []
## Spawn offsets from the encounter centre, one per entry in enemy_scenes.
@export var spawn_offsets: Array[Vector2] = []
## The encounter engages while the player is within this distance of the centre.
@export var activity_radius: float = 190.0
@export var display_name: String = ""
