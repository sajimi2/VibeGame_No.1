class_name ActorHitFeedback
extends Node
## Shared placeholder feedback for actors that are hit: flashes the body white, and on death dims
## it. Every actor used it or nothing: only the player had feedback, so hits on enemies looked
## like they did nothing.
##
## This is presentation only - it reads the CombatantPort signals and never changes health.

const HIT_FLASH_SECONDS := 0.14
const DEAD_TINT := Color(0.28, 0.26, 0.24)

@export var combatant_path: NodePath
@export var body_visual_path: NodePath
## Optional audio source. When present, landing/blocking/dying play a cue.
@export var sfx_path: NodePath

var _combatant: ActorCombatant
var _body: Polygon2D
var _sfx: SfxPlayer
var _base_color := Color.WHITE
var _flash_timer := 0.0
var _dead := false

func _ready() -> void:
	_combatant = get_node_or_null(combatant_path) as ActorCombatant
	_body = get_node_or_null(body_visual_path) as Polygon2D
	_sfx = get_node_or_null(sfx_path) as SfxPlayer
	if _body != null:
		_base_color = _body.color
	if _combatant == null:
		push_error("ActorHitFeedback: combatant_path must point at an ActorCombatant")
		return
	_combatant.hurt.connect(_on_hurt)
	_combatant.blocked.connect(_on_blocked)
	_combatant.died.connect(_on_died)

func _process(delta: float) -> void:
	if _body == null or _flash_timer <= 0.0:
		return
	_flash_timer = maxf(0.0, _flash_timer - delta)
	if _flash_timer > 0.0:
		_body.color = Color.WHITE
	elif _dead:
		_body.color = DEAD_TINT
	else:
		_body.color = _base_color

func _on_hurt(_damage: float, _origin: Vector2) -> void:
	_flash_timer = HIT_FLASH_SECONDS
	if _sfx != null:
		_sfx.play(SfxPlayer.Cue.HIT)

func _on_blocked(_origin: Vector2) -> void:
	_flash_timer = HIT_FLASH_SECONDS * 0.5
	if _sfx != null:
		_sfx.play(SfxPlayer.Cue.BLOCK)

func _on_died(_source_id: int) -> void:
	_dead = true
	_flash_timer = HIT_FLASH_SECONDS
	if _sfx != null:
		_sfx.play(SfxPlayer.Cue.DEATH)
