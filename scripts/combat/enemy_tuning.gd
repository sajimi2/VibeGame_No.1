extends Resource
## 关卡提供只读难度参数；默认值保持旧战场，演员不修改共享资源。
@export var guard_health := 60
@export var archer_health := 40
@export var damage_scale := 1.0
@export var windup_scale := 1.0
@export var recovery_scale := 1.0
@export var cooldown_scale := 1.0
@export var chase_speed := 2.75
## 零代表原有不限追击范围；正数限制离岗距离，避免串起整张地图的敌人。
@export var leash_distance := 0.0
