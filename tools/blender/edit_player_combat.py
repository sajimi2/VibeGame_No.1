"""按已保存玩家源定向编辑剑术/格挡/翻滚动作；不重建模型，不改其他角色。"""
import bpy, math, json
from pathlib import Path
from mathutils import Vector, Matrix
ROOT=Path(__file__).resolve().parents[2]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/characters/blender/player_rig.blend'),load_ui=False,use_scripts=False)
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
for track in rig.animation_data.nla_tracks: track.mute=True
rest={b.name:b.matrix_local.copy() for b in rig.data.bones}

def matrix_at(name,position,rotation):
    rig.pose.bones[name].matrix=Matrix.Translation(Vector(position)) @ rotation.to_4x4() @ rest[name].to_3x3().to_4x4()
    bpy.context.view_layer.update()

def segment(name,start,end):
    q=Vector((0,0,-1)).rotation_difference(Vector(end)-Vector(start))
    matrix_at(name,start,q.to_matrix())

def limb(upper,lower,hand,target,pole,l1,l2):
    """两节定长 IK 仅在制作期计算；运行时仍播放烘焙图集。"""
    start=rig.pose.bones[upper].head.copy(); target=Vector(target)
    line=target-start; distance=min(line.length,l1+l2-.008)
    axis=line.normalized(); target=start+axis*distance
    toward=Vector(pole)-start; side=(toward-axis*toward.dot(axis)).normalized()
    along=(l1*l1-l2*l2+distance*distance)/(2*distance)
    elbow=start+axis*along+side*math.sqrt(max(0,l1*l1-along*along))
    segment(upper,start,elbow);segment(lower,elbow,target)
    matrix_at(hand,target,Vector((0,0,-1)).rotation_difference(target-elbow).to_matrix())

def keyed(frame):
    for bone in rig.pose.bones:
        bone.rotation_mode='QUATERNION'
        bone.keyframe_insert('location',frame=frame,group=bone.name)
        bone.keyframe_insert('rotation_quaternion',frame=frame,group=bone.name)
        bone.keyframe_insert('scale',frame=frame,group=bone.name)

def reset():
    for b in rig.pose.bones: b.matrix_basis=Matrix.Identity(4)
    bpy.context.view_layer.update()

def new_action(name):
    # 只替换本次明确修改的动作；旧源整体备份位于 work/pre_courtyard_combat。
    old=bpy.data.actions.get(name)
    if old: bpy.data.actions.remove(old)
    action=bpy.data.actions.new(name);action.use_fake_user=True
    rig.animation_data.action=action
    return action

def sword_pose(hand,pitch,yaw,twist,crouch=0):
    reset()
    matrix_at('Pelvis',(0,-crouch*.6,.855-crouch),Matrix.Rotation(math.radians(twist*.35),3,'Z'))
    matrix_at('Spine',(0,-crouch*.6,.855-crouch),Matrix.Rotation(math.radians(twist),3,'Z') @ Matrix.Rotation(math.radians(6+crouch*80),3,'X'))
    # 前后错步与屈膝承重；脚底固定，骨盆转动不再拖着直腿一起扭。
    limb('ThighL','ShinL','FootL',(-.18,-.17,.075),(-.20,-.65,.45),.43,.41)
    limb('ThighR','ShinR','FootR',(.18,.14,.075),(.22,-.40,.45),.43,.41)
    head=rig.pose.bones['Head'].head.copy()
    matrix_at('Head',head,Matrix.Rotation(math.radians(twist*.2),3,'Z'))
    d=Vector((math.sin(math.radians(yaw))*math.cos(math.radians(pitch)),-math.cos(math.radians(yaw))*math.cos(math.radians(pitch)),math.sin(math.radians(pitch))))
    right=Vector(hand);left=right-d*.13
    limb('UpperArmR','ForearmR','HandR',right,(.60,-.06,.99),.29,.27)
    limb('UpperArmL','ForearmL','HandL',left,(-.55,-.12,1.02),.29,.27)
    # 两手自身朝向也沿握柄排列，手掌不会继续保持旧的前送姿态。
    for name in ['HandR','HandL']:
        matrix_at(name,rig.pose.bones[name].head.copy(),Vector((0,0,-1)).rotation_difference(d).to_matrix())

ready=((.10,-.27,1.12),48,-15,-12,0)
horizontal=[(0,*ready),(26,(.30,-.04,1.22),8,105,45,.04),(34,(.30,-.06,1.23),5,95,42,.04),(44,(.12,-.43,1.22),0,15,5,.06),(55,(-.26,-.19,1.12),-8,-85,-42,.06),(72,(-.23,-.17,1.04),-22,-95,-32,.04),(96,*ready)]
overhead=[(0,*ready),(22,(.16,-.22,1.48),70,5,-12,.02),(36,(.07,-.06,1.76),145,0,0,.02),(43,(.07,-.17,1.70),110,0,0,.03),(53,(.06,-.45,1.19),5,0,0,.08),(64,(.04,-.35,.91),-48,0,0,.09),(76,(.04,-.29,.96),-38,0,0,.06),(96,*ready)]
for name,frames in [('sword_ready',[(0,*ready)]),('sword_slash',horizontal),('sword_overhead',overhead),('weapon_guard',[(0,(.02,-.32,1.40),72,65,-12,.04)])]:
    action=new_action(name)
    for frame,hand,pitch,yaw,twist,crouch in frames:
        sword_pose(hand,pitch,yaw,twist,crouch);keyed(frame)
    for fc in action.fcurves:
        for k in fc.keyframe_points:k.interpolation='LINEAR'

# 翻滚以蜷身姿态绕横轴完整滚动；位移交给 move_and_slide，动画无根运动。
action=new_action('roll')
for frame in range(0,97,4):
    t=frame/96
    if t<.15:
        blend=t/.15
    elif t>.82:
        blend=(1-t)/.18
    else: blend=1
    reset()
    spine_rot=Matrix.Rotation(math.radians(60*blend),3,'X')
    matrix_at('Pelvis',(0,0,.91-.27*blend),Matrix.Identity(3))
    matrix_at('Spine',(0,0,.91-.27*blend),spine_rot)
    for side,sign in [('L',-1),('R',1)]:
        limb('Thigh'+side,'Shin'+side,'Foot'+side,(sign*.15,.08*blend,.08+.20*blend),(sign*.18,-1,.45),.43,.41)
        limb('UpperArm'+side,'Forearm'+side,'Hand'+side,(sign*.19,-.34,.80),(sign*.50,-.12,.88),.29,.27)
    snapshots={b.name:b.matrix.copy() for b in rig.pose.bones}
    angle=2*math.pi*max(0,min(1,(t-.1)/.8))
    pivot=Vector((0,-.12,.75))
    rotate=Matrix.Translation(pivot) @ Matrix.Rotation(angle,4,'X') @ Matrix.Translation(-pivot)
    for b in rig.pose.bones:
        b.matrix=rotate @ snapshots[b.name]
        bpy.context.view_layer.update()
    keyed(frame)
for fc in action.fcurves:
    for k in fc.keyframe_points:k.interpolation='LINEAR'
rig.animation_data.action=bpy.data.actions['sword_ready']
bpy.context.scene.frame_set(0)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'assets/characters/blender/player_rig.blend'))
print('EDITED_PLAYER_ACTIONS sword_ready sword_slash sword_overhead weapon_guard roll')
