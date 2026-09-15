class_name ItemDefinition
extends Resource
## Immutable catalog entry. Never mutated at runtime: a rolled ItemInstance carries its own
## copy of the modifiers, so random rolls can never write back into the shared definition.

## Bag/equipment categories. "weapon" is required for a weapon slot, and so on.
enum Category { WEAPON, HEAD, BODY, ACCESSORY }

@export var id: StringName = &""
@export var display_name: String = ""
@export var category: Category = Category.ACCESSORY
## Additive modifiers applied while equipped. Allowed keys: attack, armor,
## max_health, max_stamina, move_speed. Ranges are this resource's own definition.
@export var base_modifiers: Dictionary = {}
## A quality roll picks one modifier from here and adds a small amount of it.
@export var bonus_pool: Array[StringName] = []
## Optional behaviour for Category.WEAPON entries: the attack specs the wielder swaps in while this
## item is equipped. Null means the weapon only contributes its modifiers and the wielder keeps the
## fallback moves (enemies, and any weapon not yet given its own profile).
@export var weapon_profile: WeaponProfile
