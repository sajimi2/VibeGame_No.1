extends CharacterBody3D
## 独立NPC只播放十二朝向呼吸待机；仍复用颜色/深度播放，不增加战斗动画。
var camera: Camera3D
var hp := 100
var visual: Node3D
var tint := Color.WHITE
var asset_id := "steward"
var clock := 0.0
func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	visual = preload("res://scripts/presentation/baked_human.gd").new()
	add_child(visual)
	visual.setup(self,asset_id)
	visual.tint = tint
func _process(delta: float) -> void:
	clock+=delta
	visual.apply_frame({"direction":0,"step":-1,"action":"town_idle","action_frame":int(clock*3)%12})
