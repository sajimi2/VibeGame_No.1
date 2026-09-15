extends Node
const ActorArt = preload("res://scripts/ui/pixel_actor.gd")
const WorldArt = preload("res://scripts/ui/pixel_world.gd")
var camera: Camera2D
var shake_time := 0.0
var level: Node2D
var audio_source: SfxPlayer
var settings: PanelContainer
var audio_open := false
static var shake_enabled := true

func setup(root: Node2D, player: PlayerController, encounters: EncounterManager, audio: SfxPlayer) -> void:
	level = root
	audio_source = audio
	process_mode = Node.PROCESS_MODE_ALWAYS
	var floor := WorldArt.new()
	level.add_child(floor)
	floor.setup(level)
	for child in level.get_children():
		if child is Node2D and (String(child.name) in ["QuestGiver", "WeaponRack"] or String(child.name).begins_with("Exit")):
			var prop := preload("res://scripts/ui/pixel_prop.gd").new()
			child.add_child(prop)
			prop.setup(child)
	_attach(player)
	camera = player.get_node_or_null("FollowCamera") as Camera2D
	if encounters != null:
		encounters.enemy_spawned.connect(func(body: Node, _id: StringName): _attach(body))
		for body in encounters.all_enemy_nodes(): _attach(body)
	if audio != null:
		audio.process_mode = Node.PROCESS_MODE_ALWAYS
		audio.start_region(String(root.level_id))
	_build_settings()
	_style_hud()

func _attach(body: Node2D) -> void:
	if body.has_node("PixelArt"): return
	var art := ActorArt.new()
	art.name = "PixelArt"
	body.add_child(art)
	art.setup(body, audio_source, _shake)

func _shake() -> void:
	if shake_enabled: shake_time = 0.16

func set_shake_enabled(value: bool) -> void:
	shake_enabled = value
	if not value:
		shake_time = 0
		if camera != null: camera.offset = Vector2.ZERO

func _process(delta: float) -> void:
	if camera == null: return
	shake_time = maxf(0, shake_time - delta)
	var amount := shake_time / 0.16
	camera.offset = Vector2(sin(shake_time * 160), cos(shake_time * 140)) * 2 * amount if shake_enabled else Vector2.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		audio_open = not audio_open
		settings.visible = audio_open
		level._set_inventory_open(false)
		get_tree().paused = audio_open
		get_viewport().set_input_as_handled()
	elif audio_open:
		get_viewport().set_input_as_handled()

func _build_settings() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 20
	add_child(canvas)
	settings = PanelContainer.new()
	settings.position = Vector2(208, 65)
	settings.custom_minimum_size = Vector2(230, 220)
	canvas.add_child(settings)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("202a2c")
	style.border_color = Color("baa875")
	style.set_border_width_all(2)
	style.set_content_margin_all(12)
	settings.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	settings.add_child(box)
	var title := Label.new()
	title.text = "声音与画面 · Esc 返回"
	title.add_theme_font_size_override("font_size", 13)
	box.add_child(title)
	for i in 3:
		var label := Label.new()
		label.text = ["总音量", "音乐", "音效与环境声"][i]
		label.add_theme_font_size_override("font_size", 11)
		box.add_child(label)
		var slider := HSlider.new()
		slider.max_value = 1.0
		slider.step = 0.01
		slider.value = SfxPlayer.volumes[i]
		slider.value_changed.connect(func(value: float): audio_source.set_volume(i, value))
		box.add_child(slider)
	var shake := CheckButton.new()
	shake.text = "受击轻微震屏"
	shake.button_pressed = shake_enabled
	shake.add_theme_font_size_override("font_size", 11)
	shake.toggled.connect(set_shake_enabled)
	box.add_child(shake)
	settings.hide()

func _style_hud() -> void:
	var hud := level.get_node_or_null("HintLayer")
	if hud == null: return
	var plate := ColorRect.new()
	plate.position = Vector2(8, 8)
	plate.size = Vector2(252, 118)
	plate.color = Color(0.07, 0.10, 0.11, 0.86)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.z_index = -1
	hud.add_child(plate)
	var locations := {"BuildLabel": Vector2(14, 11), "HealthLabel": Vector2(14, 31), "StaminaLabel": Vector2(14, 44), "EnemyName": Vector2(14, 59), "QuestStatus": Vector2(14, 109)}
	for name in locations:
		var label := hud.get_node_or_null(name) as Label
		if label != null:
			label.position = locations[name]
			label.add_theme_font_size_override("font_size", 10 if name != "BuildLabel" else 12)
	var build := hud.get_node_or_null("BuildLabel") as Label
	if build != null: build.text = {"village": "渡鸦村 · 安全区", "forest": "幽林古道", "outpost_lower": "旧哨站 · 下层", "outpost_upper": "旧哨站 · 首领大厅"}.get(String(level.level_id), "哨站")
	var positions := {"HealthBar": Vector2(40, 32), "StaminaBar": Vector2(40, 45), "EnemyBar": Vector2(14, 77)}
	for name in positions:
		var bar := hud.get_node_or_null(name) as Control
		if bar != null:
			bar.position = positions[name]
			bar.size = Vector2(140, 7)
	var weapon := hud.get("_weapon_status_label") as Label
	if weapon != null:
		weapon.position = Vector2(14, 91)
		weapon.add_theme_font_size_override("font_size", 9)
	var growth := hud.get_node_or_null("LevelUpPanel") as Control
	if growth != null:
		growth.position = Vector2(440, 12)
		growth.scale = Vector2(0.85, 0.85)
	var notice := hud.get("_notice_label") as Label
	if notice != null: notice.position = Vector2(14, 310)
	for pair in [["HealthBar", "a94f4b"], ["StaminaBar", "6c9767"], ["EnemyBar", "af8054"]]:
		var bar := hud.get_node_or_null(pair[0]) as ProgressBar
		if bar == null: continue
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color("20272c")
		bg.border_color = Color("7a7964")
		bg.set_border_width_all(1)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(pair[1])
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fill)
		bar.show_percentage = false
	var hint := hud.get_node_or_null("ControlsLabel") as Label
	if hint != null:
		hint.text = "WASD 移动 | 左键/Q 攻击 | 空格 闪避 | 右键 格挡 | E 交互 | I 背包 | Esc 设置 | F5/F9 存读档"
		hint.add_theme_font_size_override("font_size", 9)
