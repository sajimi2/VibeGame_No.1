class_name LevelFlow
extends Node2D
## The shared shell of every level: it owns the player, the encounters, the HUD, the retry loop and
## the transitions to other levels. Levels differ by the data they are given (which encounters,
## where the exits lead, whether the village refills) rather than by duplicating this logic.
##
## Retry stays in the current level. Leaving through an exit carries the player's vitals to the
## next level through the session, so walking between areas does not heal you - except in the
## village, which is the explicit safe point (DESIGN: 首次死亡返回村庄、状态补满).

const LEVEL_SCENES := {
	&"village": "res://scenes/level_village.tscn",
	&"forest": "res://scenes/level_forest.tscn",
	&"outpost_lower": "res://scenes/level_outpost_lower.tscn",
	&"outpost_upper": "res://scenes/level_outpost_upper.tscn",
}

const RESTART_ACTION := &"restart"
const INVENTORY_ACTION := &"inventory"
const SAVE_ACTION := &"save_game"
const LOAD_ACTION := &"load_game"

@export var level_id: StringName = &"village"
## The village is the safe point: entering it refills health and stamina.
@export var refills_on_entry := false
@export var player_path: NodePath
@export var encounter_manager_path: NodePath
@export var hud_path: NodePath
@export var inventory_panel_path: NodePath
@export var quest_panel_path: NodePath
## Optional quest giver; only the village has one.
@export var quest_giver_path: NodePath
## Optional shared audio source for the level's cues.
@export var sfx_path: NodePath

## Optional smoke check: when enabled, the level saves and reloads itself shortly after starting
## and records the outcome in user://save_smoke.log. Off by default; it exists so an exported build
## can prove its save path works without a human at the keyboard (T07 verification).
@export var run_save_smoke_check := false

var _player: PlayerController
var _encounters: EncounterManager
var _hud: CombatHud
var _inventory_panel: Control
var _quest_panel: Control
var _quest_giver: QuestGiver
var _sfx: SfxPlayer
var _session: GameSession
var _awaiting_retry := false

func _ready() -> void:
	## Must keep receiving input while a menu pauses the tree, or the inventory could never close.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for child in get_children():
		child.process_mode = Node.PROCESS_MODE_ALWAYS if child is CanvasLayer else Node.PROCESS_MODE_PAUSABLE
	_player = get_node_or_null(player_path) as PlayerController
	_encounters = get_node_or_null(encounter_manager_path) as EncounterManager
	_hud = get_node_or_null(hud_path) as CombatHud
	_inventory_panel = get_node_or_null(inventory_panel_path) as Control
	_quest_panel = get_node_or_null(quest_panel_path) as Control
	_quest_giver = get_node_or_null(quest_giver_path) as QuestGiver
	_sfx = get_node_or_null(sfx_path) as SfxPlayer
	_session = GameSession.current
	if _session == null:
		## Starting the game directly in a level (tests, editor F5) still needs a session.
		_session = GameSession.start_new_run()
	_session.set_level(level_id)
	_enter_level()
	_set_inventory_open(false)
	_connect_signals()
	_refresh_hud()
	## Hand the player to the quest giver explicitly, so proximity does not depend on physics
	## signals or on group membership being set up in the right order.
	if _quest_giver != null and _player != null:
		_quest_giver.bind_session(_session)
		_quest_giver.set_player(_player)
	if run_save_smoke_check:
		## Deferred so the level is fully inside the tree before the round-trip runs.
		_run_save_smoke_check.call_deferred()

## Writes the outcome of a save/load round to user://save_smoke.log, which is what an exported
## build can show without a console. Only runs when explicitly enabled.
func _run_save_smoke_check() -> void:
	var service := SaveService.new()
	service.delete_save()
	var combatant := _find_combatant(_player)
	var before := combatant.get_health() if combatant != null else -1.0
	var save_error := save_now()
	var saved_exists := service.has_save()
	var load_status := load_now()
	var after_player := _find_combatant(_player)
	var after := after_player.get_health() if after_player != null else -1.0
	var lines := [
		"exported save path: %s" % ProjectSettings.globalize_path(service.get_path()),
		"save_now ok=%s message='%s'" % [save_error.is_empty(), save_error],
		"file exists after save: %s" % saved_exists,
		"load status: %d" % load_status,
		"health before=%.1f after reload=%.1f" % [before, after],
		"loaded in level: %s" % level_id,
	]
	var file := FileAccess.open("user://save_smoke.log", FileAccess.WRITE)
	if file == null:
		push_error("save smoke check: cannot write the log (%d)" % FileAccess.get_open_error())
		return
	for line in lines:
		file.store_line(line)
	file.close()
	print("[smoke] wrote user://save_smoke.log")

## Applies the rules for arriving in this level.
func _enter_level() -> void:
	if _player == null:
		return
	_apply_pending_vitals()
	if refills_on_entry:
		_restore_full()
	_session.pending_vitals = {}
	if _hud != null:
		_hud.set_status("")

func _restore_full() -> void:
	var combatant := _find_combatant(_player)
	if combatant == null:
		return
	combatant.reset_vitals()

func _apply_pending_vitals() -> void:
	var combatant := _find_combatant(_player)
	if combatant == null:
		return
	var vitals: Dictionary = _session.pending_vitals
	if vitals.is_empty():
		combatant.reset_vitals()
		return
	if _inventory() != null and vitals.has("inventory"):
		_inventory().restore_from_snapshot(vitals["inventory"])
	if _progressions() != null:
		_progressions().restore_from_snapshot(vitals.get("progression", {}))
	combatant.refresh_equipment()
	var health := float(vitals.get("health", combatant.max_health()))
	var stamina := float(vitals.get("stamina", combatant.max_stamina()))
	combatant.reset_vitals()
	combatant.set_vitals(health, stamina)

func _connect_signals() -> void:
	var combatant := _find_combatant(_player)
	if combatant != null:
		combatant.died.connect(_on_player_died)
	## The player's swing gets a cue; enemies' hit/block/death cues come from their own feedback node.
	var port := _player.get_node_or_null("ActorActionPort") if _player != null else null
	if port is ActorActionPort and _sfx != null:
		(port as ActorActionPort).attack_started.connect(_on_player_attack_started)
	if _encounters != null:
		_encounters.enemy_spawned.connect(_on_enemy_spawned)
		_encounters.encounter_defeated.connect(_on_encounter_defeated)
		_encounters.encounter_disengaged.connect(_on_encounter_disengaged)
	if _session != null:
		_session.quest_stage_changed.connect(_on_quest_stage_changed)
		_session.completed_once.connect(_on_quest_completed)
	if _inventory_panel is InventoryPanel:
		(_inventory_panel as InventoryPanel).item_dropped.connect(_on_item_dropped)
		(_inventory_panel as InventoryPanel).notice.connect(_show_notice)
	if _progressions() != null:
		_progressions().leveled_up.connect(_on_level_up)
	var loot := get_node_or_null("Loot") as LootSpawner
	if loot != null:
		loot.notice.connect(_show_notice)
		loot.item_collected.connect(_on_item_collected)

func _show_notice(message: String) -> void:
	if _hud != null:
		_hud.show_notice(message)
	if message.begins_with("已装备") and _sfx != null:
		_sfx.play(SfxPlayer.Cue.PICKUP)

func _on_item_collected(_item: ItemInstance) -> void:
	if _sfx != null:
		_sfx.play(SfxPlayer.Cue.PICKUP)

func _on_level_up(_level: int) -> void:
	_show_notice("升级！可在成长面板分配属性点")
	if _sfx != null:
		_sfx.play(SfxPlayer.Cue.LEVEL_UP)

func _on_quest_completed() -> void:
	if is_queued_for_deletion():
		return
	if _progressions() != null:
		_progressions().grant_experience(50)
	_show_notice("契约完成：获得 50 经验")
	if _sfx != null:
		_sfx.play(SfxPlayer.Cue.LEVEL_UP)

func _on_item_dropped(item: ItemInstance) -> void:
	var pickup := load("res://scenes/item_pickup.tscn").instantiate() as ItemPickup
	add_child(pickup)
	pickup.global_position = _player.global_position
	pickup.setup(item, _inventory())
	pickup.wait_until_player_leaves(_player)
	pickup.collected.connect(_on_item_collected)
	pickup.collected.connect(func(collected: ItemInstance): _show_notice("获得：" + ItemCatalog.build().definition(collected.definition_id).display_name))
	pickup.rejected.connect(func(_item: ItemInstance): _show_notice("背包已满，物品留在地面"))

## Every enemy death counts toward the contract while the quest is active. Death is once-only by
## contract, so a kill cannot be counted twice.
func _on_enemy_spawned(enemy: Node, _id: StringName) -> void:
	var combatant := _find_combatant(enemy)
	if combatant == null:
		return
	combatant.died.connect(_on_enemy_died)

func _on_enemy_died(_source_id: int) -> void:
	if _session == null or not _session.is_quest_active():
		return
	_session.register_enemy_kill()
	_refresh_hud()

func _on_player_died(_source_id: int) -> void:
	_awaiting_retry = true

## A swing cue on commit, so the wind-up is audible as well as visible.
func _on_player_attack_started(_spec: AttackSpec) -> void:
	if _sfx != null:
		_sfx.play(SfxPlayer.Cue.SWING)

func _on_quest_stage_changed(_stage: GameSession.QuestStage) -> void:
	_refresh_hud()

func _on_encounter_defeated(_id: StringName) -> void:
	if _encounters == null or _encounters.total_alive_enemies() > 0:
		return
	if _hud != null:
		_hud.set_status("区域已清空")

func _on_encounter_disengaged(_id: StringName) -> void:
	if _encounters == null or _encounters.total_alive_enemies() > 0:
		return
	if _hud != null and not _awaiting_retry:
		_hud.set_status("已脱离战斗")

func _refresh_hud() -> void:
	if _hud == null or _session == null:
		return
	_hud.set_quest_status("契约：%s%s" % [
		_session.stage_label(),
		"" if _session.is_quest_completed() else "（%d/%d）" % [_session.kills, _session.kills_required],
	])
	if _quest_giver != null:
		_quest_giver.refresh_prompt()

# --- input ---------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed(RESTART_ACTION):
		restart()
		return
	if event.is_action_pressed(INVENTORY_ACTION):
		_set_inventory_open(not is_inventory_open())
		return
	if event.is_action_pressed(SAVE_ACTION):
		notify_save_result(save_now())
		return
	if event.is_action_pressed(LOAD_ACTION):
		var result := load_now()
		if result != SaveService.LoadStatus.OK:
			notify_save_result(result)
		return

# --- persistence ---------------------------------------------------------------------------

## Writes the run to disk. Returns an empty string on success or a message to show the player.
func save_now(path := SaveService.DEFAULT_PATH) -> String:
	if _session == null:
		return "无法存档：没有进行中的游戏"
	var document := SaveService.build_document(_session, _progressions(), _inventory(), _find_combatant(_player))
	var service := SaveService.new(path)
	var result := service.save(document)
	## Also logged to stdout so the exported build's log records it (T07 verification).
	print("[save] path=%s ok=%s message='%s'" % [service.get_path(), result.is_empty(), result])
	return result

## Loads the save and returns a SaveService.LoadStatus. On success the whole run is replaced and
## the player is placed at the village safe point (TASKS.md T07).
func load_now(path := SaveService.DEFAULT_PATH) -> SaveService.LoadStatus:
	var service := SaveService.new(path)
	var result := service.load_document()
	var status: SaveService.LoadStatus = result["status"]
	notify_save_result(status, String(result.get("message", "")))
	if status != SaveService.LoadStatus.OK:
		return status
	var data: Dictionary = result["data"]
	## Run state first, then the actor's own state, then the level swap.
	var restored := GameSession.current
	if restored == null:
		restored = GameSession.start_new_run()
	restored.restore_into_village(data.get("session", {}) as Dictionary)
	var progression := _progressions()
	if progression != null:
		progression.restore_from_snapshot((data.get("progression", {}) as Dictionary))
		## The combatant reads progression bonuses, so refresh its ceilings before vitals.
		var combatant := _find_combatant(_player)
		if combatant != null:
			combatant.refresh_equipment()
	var inventory := _inventory()
	if inventory != null:
		inventory.restore_from_snapshot(data.get("inventory", {}) as Dictionary)
	var vitals: Dictionary = data.get("vitals", {})
	if _player != null and not vitals.is_empty():
		var target := _find_combatant(_player)
		if target != null:
			target.set_vitals(float(vitals.get("health", target.max_health())), float(vitals.get("stamina", target.max_stamina())))
	go_to_level(GameSession.LEVEL_VILLAGE)
	return status

## Shows the outcome of a save/load attempt in the status line, so a corrupt file is visible
## rather than silent. Also printed to stdout, which is what the exported build's log captures.
func notify_save_result(status_or_error: Variant, message := "") -> void:
	if status_or_error is String:
		var text: String = status_or_error
		print("[save] %s" % ("ok" if text.is_empty() else text))
		if _hud != null:
			_hud.set_status("已保存" if text.is_empty() else text)
		return
	var status := status_or_error as SaveService.LoadStatus
	var described := message if not message.is_empty() else _describe_status(status)
	print("[load] status=%d %s" % [status, described])
	if _hud != null:
		match status:
			SaveService.LoadStatus.OK:
				_hud.set_status("已读取存档")
			SaveService.LoadStatus.NO_SAVE:
				_hud.set_status("没有找到存档")
			_:
				_hud.set_status(described)

func _describe_status(status: SaveService.LoadStatus) -> String:
	match status:
		SaveService.LoadStatus.OK: return "已读取存档"
		SaveService.LoadStatus.NO_SAVE: return "没有找到存档"
		SaveService.LoadStatus.UNSUPPORTED_VERSION: return "存档版本不受支持，原文件未改动"
		_: return "存档无法读取，原文件未改动"

func _inventory() -> ActorInventory:
	if _player == null:
		return null
	for child in _player.get_children():
		if child is ActorInventory:
			return child as ActorInventory
	return null

func is_inventory_open() -> bool:
	return _inventory_panel != null and _inventory_panel.visible

func _set_inventory_open(open: bool) -> void:
	if _inventory_panel == null:
		return
	_inventory_panel.visible = open
	get_tree().paused = open

## Retry: player back to the level's safe point and every encounter re-armed. Progression and
## equipment survive (they are the run's rewards); the level's enemies do not.
func restart() -> void:
	_awaiting_retry = false
	if _player != null:
		_player.reset_for_retry()
		if refills_on_entry:
			_restore_full()
	if _encounters != null:
		_encounters.reset_all()
	if _hud != null:
		_hud.clear_death_state()
	_refresh_hud()

func is_awaiting_retry() -> bool:
	return _awaiting_retry

# --- transitions ---------------------------------------------------------------------------

## Leaves this level for another, carrying the player's current state with them.
##
## The swap is done by hand rather than with SceneTree.change_scene_to_file(): a level can ask for
## the next one while it is itself being freed or replaced, and an explicit free-then-add keeps the
## order deterministic (and testable) instead of leaving the tree briefly empty.
func go_to_level(destination: StringName) -> bool:
	if not LEVEL_SCENES.has(destination):
		push_error("LevelFlow: unknown level '%s'" % destination)
		return false
	if _session == null:
		return false
	var packed := load(LEVEL_SCENES[destination]) as PackedScene
	if packed == null:
		push_error("LevelFlow: could not load '%s'" % LEVEL_SCENES[destination])
		return false
	_session.pending_vitals = _capture_vitals()
	_session.set_level(destination)
	var tree := get_tree()
	if tree == null:
		return false
	var next := packed.instantiate()
	if next == null:
		return false
	var previous := tree.get_current_scene()
	tree.root.add_child(next)
	tree.set_current_scene(next)
	if previous != null and previous != self:
		previous.queue_free()
	queue_free()
	return true

func _capture_vitals() -> Dictionary:
	var combatant := _find_combatant(_player)
	if combatant == null:
		return {}
	var vitals := {
		"health": combatant.get_health(),
		"stamina": combatant.get_stamina(),
	}
	var progression := _progressions()
	if progression != null:
		vitals["progression"] = progression.get_snapshot()
	if _inventory() != null:
		vitals["inventory"] = _inventory().get_snapshot()
	return vitals

func _find_combatant(actor: Node) -> ActorCombatant:
	if actor == null:
		return null
	for child in actor.get_children():
		if child is ActorCombatant:
			return child as ActorCombatant
	return null

func _progressions() -> ActorProgression:
	if _player == null:
		return null
	for child in _player.get_children():
		if child is ActorProgression:
			return child as ActorProgression
	return null

func session() -> GameSession:
	return _session
