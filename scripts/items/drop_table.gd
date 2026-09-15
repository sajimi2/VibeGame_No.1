class_name DropTable
extends Resource
## What an enemy drops. Rolls come from the ItemCatalog's RNG, so a fixed seed reproduces the
## same loot - which is what makes the drop path testable.

## Always dropped (v0.1: one entry, the enemy's own item).
@export var guaranteed_definition_ids: Array[StringName] = []
## Chance that one extra item from this list also drops.
@export var bonus_chance: float = 0.25
@export var bonus_definition_ids: Array[StringName] = []

func is_empty() -> bool:
	return guaranteed_definition_ids.is_empty() and bonus_definition_ids.is_empty()
