class_name ItemInstance
extends Resource
## Unique per drop; definition_id resolves immutable catalog data.
## Never mutate shared catalog resources when rolling an item.
@export var instance_id: String = ""
@export var definition_id: StringName = &""
@export var rarity: int = 0
## Snapshot-compatible modifier keys: attack, armor, max_health, max_stamina, move_speed.
## Values are additive floats. Valid ranges belong to the item catalog.
@export var modifiers: Dictionary = {}
