@abstract
class_name InventoryPort
extends Node
signal inventory_changed
signal equipment_changed(slot: StringName, instance_id: String)

## False on invalid/duplicate ID or full bag, with no mutation.
## Inventory owns a deep copy on success; caller keeps no mutable authority.
@abstract
func try_add(item: ItemInstance) -> bool

## Legal slots: weapon, head, body, accessory. Atomic swap with old equipment
## returning into the incoming item's bag position, including when bag is full.
## Reject invalid slot/type or non-owned item without changes.
@abstract
func try_equip(instance_id: String, slot: StringName) -> bool

## Deep snapshot: bag (Array[Dictionary]), equipment (Dictionary slot -> item
## Dictionary or null). Item schema: instance_id, definition_id (String),
## rarity (int), modifiers (Dictionary). Never return live Resource references.
@abstract
func get_snapshot() -> Dictionary
