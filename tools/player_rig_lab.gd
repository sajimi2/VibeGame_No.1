extends Node3D
## 三维角色离线图集样板：复用战场的移动与攻击，显式禁用真实进度和遭遇。
const Baked = preload("res://scripts/presentation/baked_human.gd")
var battlefield: Node3D
var presenter: Node3D
var caption: Label
var previous_testing: bool
var source_rig: Node3D
var source_visible := false

func _ready() -> void:
	previous_testing=ProjectSettings.get_setting("tactical/testing",false)
	ProjectSettings.set_setting("tactical/testing",true)
	battlefield=preload("res://scenes/battlefield.tscn").instantiate()
	battlefield.encounter_enabled=false
	battlefield.results_enabled=false
	add_child(battlefield)
	battlefield.camera.size=8
	presenter=battlefield.player.baked_visual
	var loaded: bool=not presenter.manifest.is_empty()
	battlefield.combat.apply_weapon(load("res://data/weapons/cleaver.tres"))
	var layer := CanvasLayer.new()
	add_child(layer)
	caption=Label.new()
	caption.position=Vector2(24,204)
	caption.add_theme_font_size_override("font_size",17)
	caption.add_theme_color_override("font_shadow_color",Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x",2)
	caption.add_theme_constant_override("shadow_offset_y",2)
	layer.add_child(caption)
	if not loaded: caption.text="图集未生成：请先运行 tools/bake_player_rig.gd，再导入资源。"

func _process(_delta: float) -> void:
	if not is_instance_valid(presenter) or presenter.manifest.is_empty(): return
	var status := "离线像素图集" if presenter.active else "原版对照" if not presenter.enabled else "美术数据缺失，回退原版"
	caption.text="玩家三维转像素样板 · %s\n1 轻装奔跑 / 2 重刀攻击 · Tab 原版对照 · M 显示三维源模型\nWASD 移动 · Shift 疾跑（轻装）· 鼠标转向/左键攻击\n新外观已覆盖全部现有动作；十二朝向与移动攻击\n%s" % [status,"右侧为三维美术源预览；正式玩家只播放已保存图集" if source_visible else "F5 同样使用新角色；本试验场不保存进度"]
	if source_visible:
		var player: Node3D=battlefield.player
		source_rig.apply_state({"action":player.visual_action,"action_frame":player.visual_action_frame,"step":player.art_step,"move":posmod(player.movement_direction-player.direction_index,12),"run":player.sprinting,"crouch":roundi(player.crouch_blend*6),"jump":player.jump_frame})
		source_rig.global_position=player.global_position+battlefield.camera.global_basis.x*2.1
		source_rig.rotation.y=battlefield.camera.rotation.y+player.direction_index*PI/6

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.physical_keycode:
		KEY_1: battlefield.combat.apply_weapon(load("res://data/weapons/knife.tres"))
		KEY_2: battlefield.combat.apply_weapon(load("res://data/weapons/cleaver.tres"))
		KEY_TAB: presenter.enabled=not presenter.enabled
		KEY_M:
			source_visible=not source_visible
			if source_visible and not is_instance_valid(source_rig):
				source_rig=preload("res://assets/characters/player_rig.tscn").instantiate()
				add_child(source_rig)
			if is_instance_valid(source_rig): source_rig.visible=source_visible
		_: return
	get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	ProjectSettings.set_setting("tactical/testing",previous_testing)
