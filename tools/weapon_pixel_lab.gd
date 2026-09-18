extends Node3D
## 独立美术试验场：复用真实战场和玩家动作，实验开关不写存档或正式工程设置。
const PixelWeapon = preload("res://scripts/presentation/pixel_weapon.gd")
var battlefield: Node3D
var adapter: Node3D
var caption: Label
var pixel_enabled := true
var model_id := "sword"
var previous_testing: bool

func _ready() -> void:
	previous_testing = ProjectSettings.get_setting("tactical/testing",false)
	ProjectSettings.set_setting("tactical/testing",true)
	battlefield = preload("res://scenes/battlefield.tscn").instantiate()
	battlefield.encounter_enabled = false
	battlefield.results_enabled = false
	add_child(battlefield)
	battlefield.camera.size = 9
	var layer := CanvasLayer.new()
	add_child(layer)
	caption = Label.new()
	caption.position = Vector2(24,205)
	caption.add_theme_font_size_override("font_size",18)
	caption.add_theme_color_override("font_shadow_color",Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x",2)
	caption.add_theme_constant_override("shadow_offset_y",2)
	layer.add_child(caption)
	equip("sword")

## 换装仍走正式战斗入口；适配器只在这里绑定新模型，主线无需知道实验存在。
func equip(id: String) -> void:
	if is_instance_valid(adapter):
		adapter.set_enabled(false)
		adapter.free()
	model_id = id
	battlefield.combat.apply_weapon(load("res://data/weapons/%s.tres" % id))
	adapter = PixelWeapon.attach(battlefield.combat.weapon,battlefield.camera,battlefield.lighting.sun)
	adapter.set_enabled(pixel_enabled)
	update_caption()

func update_caption(note := "") -> void:
	caption.text = "武器像素对照 · %s · %s\n1 宝剑 / 2 大砍刀 / 3 匕首 · Tab 原版对照 · V 导出当前像素帧\n鼠标转向与攻击 · WASD 移动 · C 下蹲 · 空格跳跃\n%s" % ["平面像素" if pixel_enabled else "三维原版",{"sword":"宝剑","cleaver":"大砍刀","knife":"匕首"}[model_id],note]

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.physical_keycode:
		KEY_1: equip("sword")
		KEY_2: equip("cleaver")
		KEY_3: equip("knife")
		KEY_TAB:
			pixel_enabled = not pixel_enabled
			adapter.set_enabled(pixel_enabled)
			update_caption()
		KEY_V: export_frame()
		_: return
	get_viewport().set_input_as_handled()

## 导出的是生成图，不会自动写入正式手绘覆盖目录；保留透明底和对应深度。
func export_frame() -> void:
	# 原版对照时也烘焙当前姿态，避免导出上次切换前的陈旧帧。
	adapter.set_enabled(true)
	adapter.sync(1.0)
	adapter.set_enabled(pixel_enabled)
	var frame: Dictionary = adapter.capture_frame()
	if frame.is_empty(): return
	var folder := "res://work/weapon_pixels"
	DirAccess.make_dir_recursive_absolute(folder)
	var path := "%s/%s_%d" % [folder,model_id,Time.get_ticks_msec()]
	var err: int = frame.image.save_png(path+".png")
	var depth_err: int = frame.depth.save_png(path+"_depth.png")
	update_caption("已导出至 work/weapon_pixels" if err==OK and depth_err==OK else "导出失败，请查看目录权限")

func _exit_tree() -> void:
	ProjectSettings.set_setting("tactical/testing",previous_testing)
