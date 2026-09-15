extends Node2D
## Presentation only: samples the action port, never changes combat or movement.
const Pixels = preload("res://assets/pixel/pixel_assets.gd")
var actor: Node2D
var port: ActorCommandPort
var combatant: ActorCombatant
var kind := "player"
var clock := 0.0
var flash := 0.0
var effect_time := 0.0
var effect_text := ""
var blocked := false
var last_position := Vector2.ZERO
var moving := false
var foot_timer := 0.0
var audio_source: SfxPlayer
var shake_callback: Callable

func setup(body: Node2D, audio: SfxPlayer, shake: Callable) -> void:
	actor = body
	port = body.get_node_or_null("ActorActionPort") as ActorCommandPort
	combatant = body.get_node_or_null("ActorCombatant") as ActorCombatant
	audio_source = audio
	shake_callback = shake
	if body is ArcherController: kind = "archer"
	elif body is BeastController: kind = "wolf"
	elif body is BanditController: kind = "boss" if String(body.name).to_lower().contains("boss") else "bandit"
	elif not body is PlayerController: kind = "dummy"
	for path in ["Visual/Body", "Visual/FacingArrow", "Visual/Blade", "Visual/Claw"]:
		var old := body.get_node_or_null(path) as CanvasItem
		if old != null: old.hide()
	if combatant != null:
		combatant.hurt.connect(_hurt)
		combatant.blocked.connect(_blocked)
		combatant.died.connect(_died)
	if port is ActorActionPort:
		(port as ActorActionPort).attack_started.connect(_attack)
	last_position = actor.global_position
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 2

func _attack(spec: AttackSpec) -> void:
	if is_instance_valid(audio_source) and kind != "player":
		audio_source.play(SfxPlayer.Cue.ARROW if spec.spawns_projectile else SfxPlayer.Cue.SWING)

func _hurt(damage: float, _origin: Vector2) -> void:
	flash = 0.12
	effect_time = 0.55
	effect_text = str(roundi(damage))
	blocked = false
	if is_instance_valid(audio_source): audio_source.play(SfxPlayer.Cue.HIT)
	if kind == "player" and shake_callback.is_valid(): shake_callback.call()

func _blocked(_origin: Vector2) -> void:
	flash = 0.06
	effect_time = 0.4
	effect_text = "格挡"
	blocked = true
	if is_instance_valid(audio_source): audio_source.play(SfxPlayer.Cue.BLOCK)

func _died(_source: int) -> void:
	if is_instance_valid(audio_source): audio_source.play(SfxPlayer.Cue.DEATH)

func _process(delta: float) -> void:
	clock += delta
	flash = maxf(0, flash - delta)
	effect_time = maxf(0, effect_time - delta)
	moving = actor.global_position.distance_squared_to(last_position) > 0.01
	last_position = actor.global_position
	foot_timer -= delta
	if kind == "player" and moving and foot_timer <= 0 and combatant.is_alive():
		foot_timer = 0.27
		if is_instance_valid(audio_source): audio_source.play(SfxPlayer.Cue.FOOTSTEP)
	queue_redraw()

func _draw() -> void:
	if actor == null: return
	var alive := combatant == null or combatant.is_alive()
	var tint := Color.WHITE if alive else Color("615b55")
	draw_rect(Rect2(-9, 4, 18, 4), Color(0.04, 0.06, 0.05, 0.5))
	if kind == "dummy":
		draw_rect(Rect2(-3, -13, 6, 20), Color("64492e"))
		draw_rect(Rect2(-12, -9, 24, 5), Color("9a7c45"))
		draw_circle(Vector2(0, -15), 6, Color("b59458") if alive else tint)
	else:
		var bob := roundf(sin(clock * 16)) if moving and alive else 0.0
		var lean := 0.0
		if port != null and port.get_state() == ActorCommandPort.State.WINDUP: lean = -1.0
		if port != null and port.get_state() == ActorCommandPort.State.ACTIVE: lean = 2.0
		if not alive:
			draw_set_transform(Vector2(0, 4), PI * 0.5, Vector2.ONE)
		var step := roundf(sin(clock * 16) * 2) if moving and alive else 0.0
		draw_rect(Rect2(-5, -2 + step, 4, 7), Color("332e2b"))
		draw_rect(Rect2(2, -2 - step, 4, 7), Color("433b31"))
		var size := Vector2(22, 25) if kind == "boss" else Vector2(18, 20)
		draw_texture_rect(Pixels.actor(kind), Rect2(Vector2(-size.x / 2 + lean, -21 + bob), size), false, tint)
		if flash > 0: draw_rect(Rect2(-6, -17, 12, 13), Color(1, 0.93, 0.76, 0.6))
		draw_set_transform(Vector2.ZERO)
	if alive and port != null and kind != "wolf": _weapon()
	if effect_time > 0:
		var color := Color("a3e5ef") if blocked else Color("ffe0a4")
		color.a = minf(1, effect_time * 4)
		var progress := 1 - effect_time / 0.55
		for i in 6:
			var at := Vector2.RIGHT.rotated(i * TAU / 6) * (4 + progress * 14)
			draw_rect(Rect2(at + Vector2(0, -8), Vector2(2, 2)), color)
		draw_string(ThemeDB.fallback_font, Vector2(-8, -26 - progress * 12), effect_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)

func _weapon() -> void:
	var facing := port.get_facing()
	var state := port.get_state()
	var spec: AttackSpec = port.get_active_attack()
	var cleaver := false
	if combatant != null:
		var profile := combatant.equipped_weapon_profile()
		cleaver = profile != null and profile.light_attack.strike_advance_pixels > 0
		if kind == "player" and profile == null:
			draw_rect(Rect2(facing * 9 + Vector2(-2, -7), Vector2(4, 4)), Color("d4ad83"))
			return
	var attacking := state == ActorCommandPort.State.WINDUP or state == ActorCommandPort.State.ACTIVE or state == ActorCommandPort.State.RECOVERY
	var angle := facing.angle()
	var extension := 0.0
	if attacking and spec != null:
		if cleaver:
			if state == ActorCommandPort.State.WINDUP: angle -= 0.8
			elif state == ActorCommandPort.State.ACTIVE: angle += lerpf(-0.8, 0.8, clampf(port.get_state_elapsed() / spec.active_seconds, 0, 1))
		else:
			extension = 6.0 if state == ActorCommandPort.State.ACTIVE else -2.0
	if state == ActorCommandPort.State.ACTIVE:
		draw_arc(Vector2.ZERO, minf(32, spec.range_pixels), facing.angle() - 0.65, facing.angle() + 0.65, 12, Color(1, 0.86, 0.53, 0.7), 2)
	if state == ActorCommandPort.State.BLOCK:
		draw_arc(Vector2.ZERO, 13, angle - 0.8, angle + 0.8, 8, Color("9ccfd0"), 3)
	draw_set_transform(Vector2(0, -5), angle)
	if kind == "archer":
		draw_arc(Vector2(9, 0), 7, -1.2, 1.2, 8, Color("b99b65"), 2)
		draw_line(Vector2(11, -6), Vector2(11, 6), Color("dfcf9e"), 1)
	else:
		var length := 17 if cleaver or kind == "boss" else 9
		draw_rect(Rect2(6 + extension, -2, 5, 4), Color("84673d"))
		draw_rect(Rect2(11 + extension, -3 if cleaver else -1, length, 5 if cleaver else 2), Color("bbc7c4"))
		draw_line(Vector2(11 + extension, -3), Vector2(11 + extension + length, -3), Color("eff0cc"), 1)
	draw_set_transform(Vector2.ZERO)
