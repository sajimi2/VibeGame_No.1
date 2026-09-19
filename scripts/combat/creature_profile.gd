extends Resource
## 三种新敌人的战斗参数；演员读取资源，不把物种数值散落在地图或 UI。
@export var art_id := "goblin"
@export var title := "哥布林"
@export_enum("thrust","slam","charge") var attack_kind := "thrust"
@export var health := 55
@export var height := 1.3
@export var radius := .25
@export var speed := 3.5
@export var damage := 18
@export var trigger_range := 1.85
@export var reach := 1.85
@export var windup := .65
@export var active_time := .18
@export var recovery := .7
@export var rest_time := .45
@export var attack_speed := 2.0
@export var knockback_scale := 1.0
