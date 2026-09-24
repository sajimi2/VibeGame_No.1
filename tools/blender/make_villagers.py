"""从保存的玩家骨架派生两位非战斗NPC，仅首次建源；不覆盖玩家或已保存NPC。"""
import bpy, math
from pathlib import Path
from mathutils import Matrix
ROOT=Path(__file__).resolve().parents[2]

def material(name,color):
    m=bpy.data.materials.new(name)
    m.diffuse_color=(*color,1)
    m.use_nodes=True
    m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(*color,1)
    return m

def accessory(rig,name,center,size,color,bone='Spine',cone=False):
    if cone:
        bpy.ops.mesh.primitive_cone_add(vertices=10,radius1=1,radius2=.55,depth=2,location=center)
    else:
        bpy.ops.mesh.primitive_cube_add(size=2,location=center)
    obj=bpy.context.object
    obj.name=name
    obj.scale=tuple(v/2 for v in size)
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    obj.data.materials.append(material(name,color))
    group=obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))),1,'REPLACE')
    modifier=obj.modifiers.new('NPCSavedSkin','ARMATURE')
    modifier.object=rig
    obj.parent=rig
    obj['art_part']='lower' if bone=='Pelvis' else 'upper'

for asset in ['steward','healer']:
    source=ROOT/f'assets/characters/blender/{asset}_rig.blend'
    if source.exists():
        bpy.ops.wm.open_mainfile(filepath=str(source),load_ui=False,use_scripts=False)
        rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    else:
        bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/characters/blender/player_rig.blend'),load_ui=False,use_scripts=False)
        rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
        for track in rig.animation_data.nla_tracks: track.mute=True
        # 取已有自然步态的站立关键帧，去掉武器前举姿势，再保存独立呼吸动作。
        rig.animation_data.action=bpy.data.actions.get('walk_00')
        bpy.context.scene.frame_set(1)
        bpy.context.view_layer.update()
        poses={b.name:b.matrix_basis.copy() for b in rig.pose.bones}
        rig.animation_data_clear()
        for old in list(bpy.data.actions): bpy.data.actions.remove(old)
        for o in list(bpy.context.scene.objects):
            if o.type!='MESH': continue
            if not o.get('art_part'):
                bpy.data.objects.remove(o,do_unlink=True)
                continue
            if any(n in o.name for n in ['Coat','Sleeve','Collar']):
                color=(.32,.14,.11) if asset=='steward' else (.20,.31,.23)
                o.data.materials.clear();o.data.materials.append(material(asset+'_cloth',color))
            if 'Hair' in o.name:
                o.data.materials.clear();o.data.materials.append(material(asset+'_hair',(.37,.35,.30) if asset=='steward' else (.20,.12,.075)))
            if asset=='steward' and 'Coat' in o.name:
                for v in o.data.vertices: v.co.x*=1.18
        if asset=='steward':
            accessory(rig,'Head_Cap',(0,0,1.68),(.40,.38,.16),(.32,.15,.11),'Head',True)
            accessory(rig,'Head_Beard',(0,-.13,1.40),(.20,.12,.20),(.47,.43,.34),'Head',True)
            accessory(rig,'Spine_Ledger',(.24,-.05,1.0),(.12,.24,.27),(.32,.23,.11))
            accessory(rig,'Spine_Cape',(0,.15,1.18),(.52,.10,.52),(.25,.12,.10))
        else:
            accessory(rig,'Head_Kerchief',(0,.02,1.65),(.35,.36,.15),(.73,.70,.53),'Head',True)
            accessory(rig,'Spine_Apron',(0,-.15,1.05),(.33,.06,.30),(.70,.66,.48))
            accessory(rig,'Pelvis_Skirt',(0,0,.65),(.50,.33,.43),(.19,.29,.22),'Pelvis',True)
            accessory(rig,'Spine_HerbSatchel',(.25,.05,1.03),(.18,.22,.30),(.40,.30,.16))
        action=bpy.data.actions.new('town_idle');action.use_fake_user=True
        rig.animation_data_create();rig.animation_data.action=action
        for frame in [1,25,49,73,97]:
            for b in rig.pose.bones:
                b.matrix_basis=poses[b.name].copy()
                b.rotation_mode='QUATERNION'
                if b.name=='Spine': b.location.z+=math.sin((frame-1)/96*math.tau)*.009
                b.keyframe_insert('location',frame=frame)
                b.keyframe_insert('rotation_quaternion',frame=frame)
                b.keyframe_insert('scale',frame=frame)
        bpy.context.scene.render.fps=24
        bpy.context.scene.frame_start=1;bpy.context.scene.frame_end=97
        bpy.context.scene.frame_set(1)
        bpy.ops.wm.save_as_mainfile(filepath=str(source))
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    for o in bpy.context.scene.objects:
        if o.type=='MESH' and o.get('art_part'): o.select_set(True)
    bpy.context.view_layer.objects.active=rig
    bpy.ops.export_scene.gltf(filepath=str(ROOT/f'assets/characters/{asset}_source.glb'),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=True,export_frame_range=False,export_skins=True,export_extras=True,export_yup=True,export_cameras=False,export_lights=False)
    print('NPC_SAVED_EXPORTED',asset)
