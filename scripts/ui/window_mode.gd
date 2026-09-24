extends Node
## 只管理游戏窗口与快捷键；挂在 Window 下跨关卡保留，暂停时也能恢复窗口。
var saved_size := Vector2i(1280,720)
var saved_position := Vector2i.ZERO
var saved_mode := Window.MODE_WINDOWED
var saved_screen := 0
var switching := false
var embedded_hint: Label
var hint_timer: Timer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var window := get_window()
	saved_screen = window.current_screen
	if window.mode in [Window.MODE_WINDOWED,Window.MODE_MAXIMIZED]:
		saved_size = window.size
		saved_position = window.position
		saved_mode = window.mode
	else:
		var usable := DisplayServer.screen_get_usable_rect(saved_screen)
		saved_position = usable.position+(usable.size-saved_size)/2

## 先于界面处理专用组合键；长按产生的重复事件不反复切换，普通 Enter 不受影响。
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.physical_keycode == KEY_F11 or (event.alt_pressed and event.physical_keycode in [KEY_ENTER,KEY_KP_ENTER]):
		get_viewport().set_input_as_handled()
		toggle()

## 原生编辑器嵌入须查询 Engine；Window.is_embedded() 只覆盖 Godot 内部子窗口。
func is_editor_embedded() -> bool:
	return Engine.is_embedded_in_editor() or get_window().is_embedded()

## 引擎限制不能静默吞键；非模态提示不会抢走战斗输入或改变背包暂停状态。
func show_embedded_hint() -> void:
	if not is_instance_valid(embedded_hint):
		var layer := CanvasLayer.new()
		layer.layer = 100
		add_child(layer)
		embedded_hint = Label.new()
		embedded_hint.position = Vector2(20,120)
		embedded_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		embedded_hint.text = "Godot 内嵌预览不支持全屏；关闭编辑器的嵌入游戏功能后重新运行。\n也可双击工程内的 play.bat，直接全屏进入林路探索。"
		embedded_hint.add_theme_font_size_override("font_size",16)
		embedded_hint.add_theme_color_override("font_color",Color("ffe2a0"))
		embedded_hint.add_theme_color_override("font_outline_color",Color("17232a"))
		embedded_hint.add_theme_constant_override("outline_size",5)
		layer.add_child(embedded_hint)
		hint_timer = Timer.new()
		hint_timer.one_shot = true
		hint_timer.timeout.connect(embedded_hint.hide)
		add_child(hint_timer)
	embedded_hint.show()
	hint_timer.start(7)

## 只改变窗口模式，不改画布、相机、图集或存档；退出全屏恢复进入前的窗口状态。
func toggle() -> void:
	if switching or DisplayServer.get_name()=="headless": return
	var window := get_window()
	if is_editor_embedded():
		show_embedded_hint()
		return
	switching = true
	if window.mode in [Window.MODE_FULLSCREEN,Window.MODE_EXCLUSIVE_FULLSCREEN]:
		window.mode = Window.MODE_WINDOWED
		# 原生窗口模式异步生效，等一帧再恢复位置，避免被系统的全屏退出过程覆盖。
		await get_tree().process_frame
		window.current_screen = clampi(saved_screen,0,DisplayServer.get_screen_count()-1)
		window.size = saved_size
		window.position = saved_position
		window.mode = saved_mode
	else:
		saved_size = window.size
		saved_position = window.position
		saved_mode = Window.MODE_MAXIMIZED if window.mode==Window.MODE_MAXIMIZED else Window.MODE_WINDOWED
		saved_screen = window.current_screen
		# Windows 的普通全屏可能保留一像素边缘；游戏全屏使用显示器完整尺寸。
		window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
	await get_tree().process_frame
	switching = false
