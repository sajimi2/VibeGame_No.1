class_name GameSession
extends RefCounted
## The run's persistent state: which level we are in, the quest's stage, how many of the target
## enemies have died, and whether the completion reward has already been paid.
##
## Deliberately NOT an Autoload singleton (ARCHITECTURE: the first version does not need one).
## A single instance is created by the level flow and handed to each level through `current`,
## so scenes stay self-contained and tests can construct their own session.

## Quest stages. TASKS.md T06: 未接 / 进行中 / 可交付 / 已完成.
enum QuestStage { NOT_STARTED, IN_PROGRESS, DELIVERABLE, COMPLETED }

signal quest_stage_changed(stage: QuestStage)
signal kills_changed(kills: int, required: int)
signal level_changed(level_id: StringName)
signal completed_once

const LEVEL_VILLAGE := &"village"
const LEVEL_FOREST := &"forest"
const LEVEL_OUTPOST_LOWER := &"outpost_lower"
const LEVEL_OUTPOST_UPPER := &"outpost_upper"

## The instance the running levels share. Set by the level flow when a run begins.
static var current: GameSession = null

## Enemies that must fall for the contract to become deliverable.
var kills_required := 3
var kills := 0
var quest_stage: QuestStage = QuestStage.NOT_STARTED
var current_level: StringName = LEVEL_VILLAGE
## True once the completion reward has been paid; a second hand-in must not pay again.
var reward_paid := false
## Player state handed from one level to the next. Written by the level being left, read by the
## level being entered; the village ignores it because the village always refills (DESIGN).
var pending_vitals: Dictionary = {}

static func start_new_run(kills_required_for_contract := 3) -> GameSession:
	var session := GameSession.new()
	session.kills_required = kills_required_for_contract
	current = session
	return session

# --- quest ---------------------------------------------------------------------------------

func accept_quest() -> bool:
	## Only a quest that has not been taken can be accepted.
	if quest_stage != QuestStage.NOT_STARTED:
		return false
	_set_stage(QuestStage.IN_PROGRESS)
	return true

## Records one enemy death against the contract. Returns true when it made the quest deliverable.
func register_enemy_kill() -> bool:
	if quest_stage != QuestStage.IN_PROGRESS:
		return false
	kills += 1
	kills_changed.emit(kills, kills_required)
	if kills >= kills_required:
		_set_stage(QuestStage.DELIVERABLE)
		return true
	return false

## Hands the contract in. Returns true only for the FIRST successful hand-in, so the reward can
## never be paid twice even if the player talks to the quest giver again.
func complete_quest() -> bool:
	if quest_stage != QuestStage.DELIVERABLE:
		return false
	_set_stage(QuestStage.COMPLETED)
	if reward_paid:
		return false
	reward_paid = true
	completed_once.emit()
	return true

func is_quest_active() -> bool:
	return quest_stage == QuestStage.IN_PROGRESS

func is_quest_deliverable() -> bool:
	return quest_stage == QuestStage.DELIVERABLE

func is_quest_completed() -> bool:
	return quest_stage == QuestStage.COMPLETED

func stage_label() -> String:
	match quest_stage:
		QuestStage.NOT_STARTED: return "未接"
		QuestStage.IN_PROGRESS: return "进行中"
		QuestStage.DELIVERABLE: return "可交付"
		_: return "已完成"

# --- levels --------------------------------------------------------------------------------

func set_level(level_id: StringName) -> void:
	if current_level == level_id:
		return
	current_level = level_id
	level_changed.emit(level_id)

func snapshot() -> Dictionary:
	return {
		"kills": kills,
		"kills_required": kills_required,
		"quest_stage": int(quest_stage),
		"current_level": String(current_level),
		"reward_paid": reward_paid,
	}

## Restores run state from a snapshot (see snapshot()). Validation of the file's schema version is
## the caller's job; this only refuses values that make no sense for the current rules.
func restore_from_snapshot(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	kills_required = maxi(1, int(data.get("kills_required", kills_required)))
	kills = maxi(0, int(data.get("kills", 0)))
	quest_stage = clampi(int(data.get("quest_stage", 0)), 0, GameSession.QuestStage.COMPLETED) as QuestStage
	current_level = StringName(String(data.get("current_level", LEVEL_VILLAGE)))
	reward_paid = bool(data.get("reward_paid", false))
	## A completed contract cannot be un-paid; a paid flag without completion would re-pay.
	if quest_stage == QuestStage.COMPLETED:
		reward_paid = true
	kills_changed.emit(kills, kills_required)
	quest_stage_changed.emit(quest_stage)
	level_changed.emit(current_level)
	return true

## The run starts at the village, so loading always drops the player at a safe point
## (TASKS.md T07: 加载至村庄安全点).
func restore_into_village(data: Dictionary) -> bool:
	var restored := restore_from_snapshot(data)
	if not restored:
		return false
	current_level = LEVEL_VILLAGE
	level_changed.emit(current_level)
	return true

func _set_stage(stage: QuestStage) -> void:
	if quest_stage == stage:
		return
	quest_stage = stage
	quest_stage_changed.emit(stage)
