class_name ItemPickup
extends Area2D
## A dropped item lying on the ground. Walking over it moves the item into the bag; if the bag is
## full the pickup simply stays there (TASKS.md: a failed pickup leaves the drop in the world).
##
## The pickup owns its ItemInstance until it is accepted, then hands over a copy and frees itself.

signal collected(item: ItemInstance)
signal rejected(item: ItemInstance)

const BOB_SPEED := 2.0
const BOB_HEIGHT := 1.5

var item: ItemInstance
var _inventory: ActorInventory
var _visual: Node2D
var _registering := false
var _must_leave: PlayerController
var _rejected_until := 0

func _ready() -> void:
	monitoring = true
	monitorable = true
	## Detect the player body (layer 2) so walking over the drop picks it up.
	collision_mask = 2
	body_entered.connect(_on_body_entered)
	_visual = get_node_or_null("Visual") as Node2D

func setup(instance: ItemInstance, inventory: ActorInventory) -> void:
	item = instance
	_inventory = inventory
	var label := Label.new()
	label.position = Vector2(-36, -25)
	label.add_theme_font_size_override("font_size", 9)
	var definition := ItemCatalog.build().definition(item.definition_id)
	var body := get_node_or_null("Visual/Body") as Polygon2D
	if body != null and definition != null:
		body.color = Color("e4bd62") if item.rarity == 1 else Color("c8d5d1")
		match definition.category:
			ItemDefinition.Category.WEAPON:
				body.polygon = PackedVector2Array([Vector2(-2, -10), Vector2(2, -10), Vector2(2, 2), Vector2(5, 2), Vector2(5, 4), Vector2(1, 4), Vector2(1, 9), Vector2(-1, 9), Vector2(-1, 4), Vector2(-5, 4), Vector2(-5, 2), Vector2(-2, 2)])
			ItemDefinition.Category.HEAD:
				body.polygon = PackedVector2Array([Vector2(-7, 5), Vector2(-7, -3), Vector2(-3, -7), Vector2(3, -7), Vector2(7, -3), Vector2(7, 5), Vector2(3, 5), Vector2(3, 0), Vector2(-3, 0), Vector2(-3, 5)])
			ItemDefinition.Category.BODY:
				body.polygon = PackedVector2Array([Vector2(-3, -6), Vector2(-8, -3), Vector2(-6, 1), Vector2(-4, 0), Vector2(-4, 7), Vector2(4, 7), Vector2(4, 0), Vector2(6, 1), Vector2(8, -3), Vector2(3, -6)])
			_:
				body.polygon = PackedVector2Array([Vector2(0, -7), Vector2(6, 0), Vector2(0, 7), Vector2(-6, 0)])
	var glow := get_node_or_null("Visual/Glow") as Line2D
	if glow != null:
		glow.visible = false
	label.text = ("优质 " if item.rarity == 1 else "") + (definition.display_name if definition != null else "装备")
	add_child(label)

func wait_until_player_leaves(player: PlayerController) -> void:
	_must_leave = player

func _physics_process(_delta: float) -> void:
	if is_instance_valid(_must_leave):
		if global_position.distance_to(_must_leave.global_position) <= 24.0:
			return
		_must_leave = null
	# Retry overlap after a full bag frees up, also covering drops born beneath the player.
	for body in get_overlapping_bodies():
		_on_body_entered(body)

func _process(_delta: float) -> void:
	## Placeholder readability: a small bob so drops are noticeable on the floor.
	if _visual != null:
		_visual.position.y = sin(Time.get_ticks_msec() / 1000.0 * BOB_SPEED * PI) * BOB_HEIGHT

func _on_body_entered(body: Node2D) -> void:
	if _registering or item == null:
		return
	if is_instance_valid(_must_leave) or Time.get_ticks_msec() < _rejected_until:
		return
	if not (body is PlayerController):
		return
	if _inventory == null:
		return
	## Never steal the instance if the bag refuses it: the drop must survive a full bag.
	if not _inventory.try_add(item):
		_rejected_until = Time.get_ticks_msec() + 2000
		rejected.emit(item)
		return
	_registering = true
	collected.emit(item)
	queue_free()
