"""Blender 4.2 候选敌人建模工具：只生成可编辑模型与检查图，不制作骨骼、动画或游戏资源。

运行：blender --background --factory-startup --python <本文件> -- --out <新目录>
默认拒绝覆盖 .blend，人工修改后请直接维护源文件，不反复运行模板覆盖。
"""
import argparse
import json
import math
import random
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector

TAU = math.tau
MODEL = None
PARTS = []
M = {}


def material(name, hex_color, rough=.7, metal=0, emission=0):
    """使用独立材质色块塑形；没有外部贴图依赖，便于之后统一烘焙配色。"""
    srgb = tuple(int(hex_color[i:i+2], 16) / 255 for i in (0, 2, 4))
    color = tuple(c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in srgb)
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Roughness'].default_value = rough
    shader.inputs['Metallic'].default_value = metal
    if emission:
        shader.inputs['Emission Color'].default_value = (*color, 1)
        shader.inputs['Emission Strength'].default_value = emission
    M[name] = mat
    return mat


def palette():
    for args in [
        ('skin', '737853'), ('skin_light', '929475'), ('ear', '635441'),
        ('cloth', '803f30'), ('cloth_light', '9e5139'), ('cloth_dark', '592f29'),
        ('pants', '443c30'), ('leather', '302b23'), ('wrap', '9c967c'),
        ('hair', '302e26'), ('eye', 'a7792c', .45), ('pupil', '131711'),
        ('wood', '644b30'), ('wood_light', '927047'), ('iron', '555e5a', .45, .6),
        ('edge', '9b9d87', .4, .5), ('rust', '78513b', .8, .25),
        ('bone', 'bcb494'), ('bone_light', 'd3cbb1'), ('bone_shadow', '837b62'),
        ('cavity', '232a25'), ('rag', '40545b'), ('rag_light', '596b6e'),
        ('gel', '347d5c', .24), ('gel_light', '61a579', .25),
        ('gel_dark', '235941', .32), ('gel_eye', 'd5c887', .32),
        ('stone', '636c62'), ('stone_light', '858b76'), ('stone_dark', '414b47'),
        ('stone_edge', 'a0a18b'), ('moss', '516345'), ('joint', '2b3734'),
        ('amber', 'bd8742', .6, 0, .4), ('stage', '202c32'),
    ]:
        material(*args)
    shader = M['gel'].node_tree.nodes.get('Principled BSDF')
    shader.inputs['Coat Weight'].default_value = .35
    shader.inputs['Coat Roughness'].default_value = .23


def keep(obj, name, mat):
    obj.name = name
    for col in list(obj.users_collection):
        col.objects.unlink(obj)
    MODEL.objects.link(obj)
    if mat and hasattr(obj.data, 'materials'):
        obj.data.materials.append(M[mat] if isinstance(mat, str) else mat)
    PARTS.append(obj)
    return obj


def mesh(name, verts, faces, mat):
    data = bpy.data.meshes.new(name + '_Mesh')
    data.from_pydata(verts, [], faces)
    data.update()
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(data)
    bm.free()
    return keep(bpy.data.objects.new(name, data), name, mat)


def apply(obj, modifier):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def uv(name, pos, scale, mat, segments=12, rings=8, smooth=False):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=pos)
    obj = keep(bpy.context.object, name, mat)
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for face in obj.data.polygons:
        face.use_smooth = smooth
    return obj


def box(name, pos, scale, mat, bevel=.015, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos, rotation=rotation)
    obj = keep(bpy.context.object, name, mat)
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new('Edge_shape', 'BEVEL')
        mod.width = bevel
        mod.segments = 1
        apply(obj, mod)
    return obj


def tube(name, points, radii, mat, sides=8, smooth=False):
    """沿折线建立有体积的封闭管面；骨骼、肋骨与武器不使用无厚度平面。"""
    pts = [Vector(p) for p in points]
    if isinstance(radii, (int, float)):
        radii = [radii] * len(pts)
    verts, faces = [], []
    for i, p in enumerate(pts):
        axis = pts[min(i+1, len(pts)-1)] - pts[max(i-1, 0)]
        q = Vector((0, 0, 1)).rotation_difference(axis.normalized())
        radius = radii[i]
        rx, ry = radius if isinstance(radius, tuple) else (radius, radius)
        for j in range(sides):
            a = TAU*j/sides
            verts.append(p + q @ Vector((rx*math.cos(a), ry*math.sin(a), 0)))
    for i in range(len(pts)-1):
        for j in range(sides):
            faces.append((i*sides+j, i*sides+(j+1)%sides,
                          (i+1)*sides+(j+1)%sides, (i+1)*sides+j))
    faces.extend([tuple(reversed(range(sides))), tuple((len(pts)-1)*sides+j for j in range(sides))])
    obj = mesh(name, verts, faces, mat)
    for f in obj.data.polygons:
        f.use_smooth = smooth
    return obj


def loft(name, rings, mat, sides=12, phase=0):
    """截面直接控制腰、胸、颅骨比例；参数是 z、中心 y、半宽和半深。"""
    verts, faces = [], []
    for z, cy, rx, ry in rings:
        for j in range(sides):
            a = TAU*j/sides+phase
            verts.append((rx*math.cos(a), cy+ry*math.sin(a), z))
    for i in range(len(rings)-1):
        for j in range(sides):
            faces.append((i*sides+j, i*sides+(j+1)%sides,
                          (i+1)*sides+(j+1)%sides, (i+1)*sides+j))
    faces.extend([tuple(reversed(range(sides))), tuple((len(rings)-1)*sides+j for j in range(sides))])
    return mesh(name, verts, faces, mat)


def segment(name, a, b, radius_a, radius_b, mat, sides=10):
    return tube(name, [a, b], [radius_a, radius_b], mat, sides)


def cut(target, cutter):
    """眼眶使用真实凹洞；辅助切割网格完成后移除，文件中只留模型。"""
    mod = target.modifiers.new('Carved_socket', 'BOOLEAN')
    mod.operation = 'DIFFERENCE'
    mod.solver = 'EXACT'
    mod.object = cutter
    apply(target, mod)
    PARTS.remove(cutter)
    bpy.data.objects.remove(cutter, do_unlink=True)


def union_skin(objects):
    """皮肤体块融合为连续网格，减少肩肘处拼球；这里只塑形，绑定与重拓扑留到角色入选后。"""
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    others = [item for item in PARTS if item not in objects]
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = objects[0]
    PARTS[:] = others + [obj]
    mod = obj.modifiers.new('Skin_union', 'REMESH')
    mod.mode = 'VOXEL'
    mod.voxel_size = .008
    apply(obj, mod)
    mod = obj.modifiers.new('Surface_relax', 'SMOOTH')
    mod.factor = .8
    mod.iterations = 5
    apply(obj, mod)
    mod = obj.modifiers.new('Planar_reduction', 'DECIMATE')
    mod.ratio = .22
    apply(obj, mod)
    return obj


def leaf(name, points, mat, inset=None):
    center = sum((Vector(p) for p in points), Vector())/len(points)
    front = center + Vector((0, -.016, 0))
    back = center + Vector((0, .016, 0))
    verts = list(points)+[front, back]
    n = len(points)
    faces = []
    for i in range(n):
        faces.extend([(i, (i+1)%n, n), ((i+1)%n, i, n+1)])
    obj = mesh(name, verts, faces, mat)
    if inset:
        obj.data.materials.append(M[inset])
        for f in obj.data.polygons:
            if f.index%2 == 0:
                f.material_index = 1
    return obj


def spear(base=(.36, -.025, .025), tip=(.28, -.07, 1.42)):
    a, end = Vector(base), Vector(tip)
    axis = (end-a).normalized()
    neck = end-axis*.18
    segment('Spear_Wood', a, neck, .013, .011, 'wood')
    q = Vector((0, 0, 1)).rotation_difference(axis)
    points = [(-.046, 0, .065), (-.015, 0, 0), (.015, 0, 0), (.046, 0, .065), (0, 0, .18)]
    blade = leaf('Spear_IronHead', points, 'iron')
    blade.rotation_mode = 'QUATERNION'
    blade.rotation_quaternion = q
    blade.location = neck
    for i in range(5):
        p = neck-axis*(.015+i*.014)
        segment('Spear_Binding_%02d'%i, p-axis*.005, p+axis*.005, .017, .017, 'wrap')


def goblin_model():
    """哥布林沿用确认稿；连续皮肤、短衣和正常屈膝结构，装备独立保留。"""
    skin = [loft('Body_Skin',[(.66,0,.087,.056),(.72,.015,.085,.051),(.87,.012,.12,.06),(.945,.018,.14,.052),(.985,.02,.075,.04)],'skin')]
    for side in [-1, 1]:
        tag = 'L' if side < 0 else 'R'
        shoulder = (side*.157,.016,.94)
        elbow = (side*.237,0,.77)
        wrist = (side*.294,-.061,.61)
        skin.append(tube('Arm_'+tag,[shoulder,(side*.195,.008,.87),elbow,(side*.27,-.034,.68),wrist],[.046,.042,.031,.034,.024],'skin'))
        skin.append(uv('Shoulder_'+tag,shoulder,(.05,.049,.057),'skin'))
        skin.append(uv('Palm_'+tag,(side*.30,-.074,.581),(.034,.027,.043),'skin'))
        for finger in range(3):
            x = side*(.279+finger*.019)
            skin.append(tube('Finger_'+tag+str(finger),[(x,-.09,.565),(x,-.103,.538),(x,-.091,.527)],[.011,.01,.008],'skin',6))
        skin.append(segment('Thumb_'+tag,(side*.273,-.079,.599),(side*.263,-.103,.562),.014,.01,'skin',6))
        hip = (side*.083,.02,.64)
        knee = (side*.114,-.035,.39)
        ankle = (side*.14,.02,.12)
        skin.append(tube('Leg_'+tag,[hip,(side*.1,-.005,.52),knee,(side*.132,.009,.26),ankle],[.066,.06,.043,.044,.028],'skin'))
        skin.append(uv('Foot_'+tag,(side*.144,-.064,.057),(.058,.108,.048),'skin'))
        skin.append(uv('Ankle_'+tag,(side*.14,.015,.102),(.033,.037,.05),'skin'))
        for toe in range(3):
            skin.append(uv('Toe_'+tag+str(toe),(side*(.115+toe*.025),-.153+toe*.009,.038),(.018,.029,.022),'skin',8,6))
    union_skin(skin)
    segment('Neck',(0,.025,.953),(0,.022,1.055),.043,.04,'skin')
    head = loft('Head',[(1.008,-.038,.048,.05),(1.038,-.018,.073,.068),(1.10,.008,.1,.09),(1.185,.018,.1,.083),(1.238,.021,.079,.065),(1.261,.022,.031,.03)],'skin',16)
    for side in [-1, 1]:
        leaf('Ear_'+str(side),[(side*.077,.012,1.16),(side*.244,.025,1.225),(side*.174,-.004,1.125),(side*.09,-.006,1.109)],'skin','ear')
        cut(head,uv('EyeCut',(side*.047,-.077,1.166),(.033,.033,.026),'skin',16,12))
        uv('Eye_'+str(side),(side*.047,-.078,1.162),(.024,.018,.016),'eye',12,8)
        uv('Pupil_'+str(side),(side*.047,-.095,1.162),(.008,.004,.011),'pupil',8,6)
        tube('Brow_'+str(side),[(side*.016,-.094,1.18),(side*.052,-.09,1.199),(side*.084,-.061,1.188)],[.016,.019,.014],'skin',6)
        leaf('Cheek_'+str(side),[(side*.032,-.079,1.124),(side*.079,-.062,1.143),(side*.089,-.061,1.113),(side*.054,-.074,1.084)],'skin')
    loft('Nose',[(1.083,-.14,.008,.014),(1.103,-.14,.024,.028),(1.148,-.094,.016,.025),(1.194,-.074,.009,.014)],'skin',8)
    tube('Mouth',[(-.039,-.075,1.055),(0,-.089,1.049),(.039,-.075,1.055)],.004,'pupil',6)
    for i in range(7):
        y = -.023+i*.014
        leaf('Hair_%02d'%i,[(-.018,y,1.247),(0,y+.003,1.284-(i%3)*.005),(.018,y,1.247),(0,y+.018,1.25)],'hair')
    loft('Tunic',[(.668,.018,.124,.087),(.731,.018,.114,.079),(.80,.016,.123,.079),(.917,.015,.159,.086),(.97,.021,.124,.056),(.998,.02,.044,.035)],'cloth',12)
    leaf('Collar_V',[(-.043,-.038,.99),(0,-.084,.895),(.043,-.038,.99),(0,-.056,.978)],'skin')
    loft('Trouser_Hips',[(.58,.018,.103,.079),(.64,.018,.122,.083),(.714,.018,.108,.077)],'pants',12)
    for side in [-1, 1]:
        leaf('Tunic_Hem_'+str(side),[(side*.008,-.082,.704),(side*.12,-.048,.694),(side*.133,-.055,.62),(side*.035,-.086,.639)],'cloth')
        tube('Trousers_'+str(side),[(side*.082,.018,.643),(side*.102,-.012,.514),(side*.115,-.031,.367)],[.075,.069,.055],'pants',10)
        for i in range(3):
            segment('AnkleWrap_%d_%d'%(side,i),(side*.14,.018,.11+i*.022),(side*.14,.017,.127+i*.022),.032,.034,'wrap',10)
        segment('WristWrap_'+str(side),(side*.286,-.05,.638),(side*.295,-.063,.607),.029,.027,'wrap',8)
    loft('Belt',[(.719,.018,.118,.084),(.752,.018,.119,.085)],'leather',12)
    box('Buckle',(0,-.071,.736),(.037,.014,.03),'iron',.004)
    box('Pouch',(-.142,-.025,.69),(.065,.065,.094),'leather',.012)
    box('Pouch_Flap',(-.144,-.063,.724),(.061,.01,.031),'wood',.007)
    spear()


def bone_segment(name, a, b, radius):
    a, b = Vector(a), Vector(b)
    axis = b-a
    return tube(name,[a,a+axis*.13,a+axis*.35,a+axis*.73,a+axis*.9,b],
                [radius*1.35,radius,radius*.70,radius*.75,radius*1.23,radius*.95],'bone',8)


def skeleton_model():
    """真实镂空胸腔与眼眶保证骷髅轮廓；骨头、下颌、装备独立，便于后续刚性绑定。"""
    for i in range(9):
        box('Vertebra_%02d'%i,(0,.058,.87+i*.061),(.062,.075,.043),'bone_shadow',.012)
    for side in [-1, 1]:
        leaf('Pelvis_'+str(side),[(side*.03,0,.924),(side*.151,.02,.958),(side*.169,-.019,.851),(side*.085,-.056,.803),(side*.026,-.018,.828)],'bone')
        bone_segment('Clavicle_'+str(side),(side*.015,-.045,1.393),(side*.205,.017,1.405),.023)
        uv('ShoulderJoint_'+str(side),(side*.211,.017,1.394),(.045,.039,.05),'bone',10,8)
        for i in range(5):
            z, width = 1.34-i*.065, .195-i*.012
            points = []
            for j in range(11):
                a = math.pi*j/10
                points.append((side*(.023+width*math.sin(a)),.074*math.cos(a)-.052*math.sin(a),z-.047*math.sin(a)))
            tube('Rib_%d_%d'%(side,i),points,.015+i*.0005,'bone',6)
        bone_segment('Humerus_'+str(side),(side*.215,.015,1.382),(side*.276,-.013,1.117),.031)
        uv('Elbow_'+str(side),(side*.28,-.018,1.102),(.036,.035,.039),'bone',10,6)
        for offset in [-.015,.015]:
            bone_segment('Forearm_%d_%s'%(side,offset),(side*(.281+offset),-.014,1.10),(side*(.335+offset*.7),-.052,.889),.017)
        box('Palm_'+str(side),(side*.34,-.056,.845),(.068,.04,.075),'bone',.01)
        for finger in range(3):
            x = side*(.315+finger*.021)
            tube('Finger_%d_%d'%(side,finger),[(x,-.065,.829),(x,-.079,.785),(x,-.06,.776)],[.011,.01,.009],'bone',6)
        bone_segment('Femur_'+str(side),(side*.095,.004,.84),(side*.12,-.013,.50),.036)
        uv('Patella_'+str(side),(side*.12,-.04,.475),(.034,.024,.038),'bone_light',10,8)
        bone_segment('Tibia_'+str(side),(side*.12,0,.472),(side*.14,.018,.122),.026)
        bone_segment('Fibula_'+str(side),(side*.147,.008,.465),(side*.166,.02,.13),.015)
        box('Heel_'+str(side),(side*.144,.018,.075),(.078,.075,.087),'bone',.018)
        for toe in range(3):
            x = side*(.119+toe*.025)
            tube('Foot_%d_%d'%(side,toe),[(x,.001,.08),(x,-.09,.041),(x,-.15+toe*.013,.028)],[.018,.015,.012],'bone',6)
    segment('Sternum',(0,-.055,1.34),(0,-.063,1.075),.024,.021,'bone_light',6)
    bone_segment('Neck',(0,.031,1.386),(0,.018,1.477),.033)
    skull = loft('Skull',[(1.46,-.029,.066,.06),(1.52,-.005,.106,.096),(1.60,.014,.131,.102),(1.69,.028,.12,.093),(1.735,.031,.068,.052)],'bone',16)
    for side in [-1, 1]:
        cut(skull,uv('SocketCut',(side*.059,-.087,1.61),(.046,.065,.043),'cavity',16,12))
        uv('SocketDark',(side*.057,-.026,1.605),(.034,.012,.031),'cavity',12,8)
        tube('OrbitalBrow_'+str(side),[(side*.016,-.092,1.648),(side*.064,-.092,1.659),(side*.105,-.064,1.64)],[.015,.02,.016],'bone_light',6)
        leaf('Cheekbone_'+str(side),[(side*.069,-.088,1.567),(side*.115,-.053,1.564),(side*.098,-.074,1.535),(side*.068,-.09,1.525)],'bone')
    nose = mesh('NoseCut',[(-.023,-.18,1.535),(.023,-.18,1.535),(0,-.18,1.58),(-.023,.02,1.535),(.023,.02,1.535),(0,.02,1.58)],[(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)],'cavity')
    cut(skull,nose)
    tube('Skull_Fracture',[(.018,-.055,1.728),(.032,-.073,1.70),(.015,-.076,1.68)],.003,'bone_shadow',5)
    tube('Jaw',[(-.087,-.01,1.515),(-.082,-.067,1.445),(0,-.084,1.425),(.082,-.067,1.445),(.087,-.01,1.515)],[.019,.021,.025,.021,.019],'bone',8)
    for i in range(6):
        x = (i-2.5)*.018
        box('UpperTooth_%d'%i,(x,-.086,1.482),(.015,.023,.026),'bone_light',.003)
        box('LowerTooth_%d'%i,(x,-.088,1.454),(.015,.021,.023),'bone',.003)
    loft('WaistStrap',[(.835,.012,.15,.072),(.87,.012,.15,.072)],'leather',12)
    for x,z in [(-.09,.72),(0,.67),(.09,.73)]:
        leaf('TatteredTabard',[(x-.042,-.073,.845),(x+.048,-.073,.845),(x+.036,-.084,z+.03),(x-.03,-.08,z)],'rag')
    box('Old_Pauldron',(-.218,.008,1.407),(.21,.17,.10),'rust',.035,rotation=(0,-.2,-.1))
    box('Pauldron_Ridge',(-.214,-.083,1.42),(.17,.018,.035),'iron',.007)
    x = .355
    segment('Sword_Grip',(x,-.07,.73),(x,-.07,.87),.022,.02,'leather')
    box('Sword_Guard',(x,-.07,.731),(.19,.035,.035),'iron',.009)
    blade = leaf('Sword_Blade',[(x-.045,-.07,.715),(x+.045,-.07,.715),(x+.031,-.07,.27),(x,-.07,.19),(x-.031,-.07,.27)],'iron')
    blade.data.materials.append(M['edge'])
    for f in blade.data.polygons:
        if f.index%3 == 0: f.material_index=1
    uv('Sword_Pommel',(x,-.07,.887),(.028,.022,.027),'rust',8,6)
    center = Vector((-.355,-.12,.94))
    uv('Shield_Wood',center,(.185,.043,.205),'wood',12,6)
    for i in range(12):
        a,b = TAU*i/12,TAU*(i+1)/12
        if i == 2: continue
        tube('Shield_Rim_%d'%i,[center+Vector((.18*math.cos(a),-.023,.2*math.sin(a))),center+Vector((.18*math.cos(b),-.023,.2*math.sin(b)))],.012,'iron',6)
    uv('Shield_Boss',center+Vector((0,-.046,0)),(.051,.026,.057),'iron',10,6)


def slime_model():
    """低矮胶团采用不透明胶质材质；避免依赖折射才能成立的造型妨碍后续深度烘焙。"""
    rings = [(.026,.35),(.055,.45),(.14,.50),(.26,.47),(.40,.39),(.52,.30),(.62,.19),(.69,.075),(.71,.008)]
    verts,faces = [],[]
    sides = 24
    for z,radius in rings:
        for j in range(sides):
            a = TAU*j/sides
            ripple = 1+.065*math.cos(5*a+.2)*(1-z/.8)
            x = radius*math.cos(a)*ripple-.07*(z/.71)**2
            y = radius*math.sin(a)*.79*ripple+.045*(z/.71)**2
            verts.append((x,y,z))
    for i in range(len(rings)-1):
        for j in range(sides):
            faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    faces.extend([tuple(reversed(range(sides))),tuple((len(rings)-1)*sides+j for j in range(sides))])
    obj = mesh('Slime_Body',verts,faces,'gel')
    for f in obj.data.polygons: f.use_smooth=True
    mod = obj.modifiers.new('Soft_surface','SUBSURF')
    mod.levels=1
    mod.render_levels=1
    apply(obj,mod)
    for side in [-1, 1]:
        eye = uv('Eye_'+str(side),(side*.142,-.332,.337),(.06,.021,.039),'gel_eye',12,8)
        eye.rotation_euler.y = side*-.15
        uv('Pupil_'+str(side),(side*.146,-.352,.336),(.014,.009,.028),'pupil',10,8)
        tube('Gel_Brow_'+str(side),[(side*.07,-.331,.375),(side*.14,-.334,.389),(side*.205,-.309,.373)],[.018,.022,.014],'gel_dark',8,True)
    for i,(x,y,z,s) in enumerate([(-.18,-.18,.57,.038),(.16,.07,.57,.031),(.35,-.03,.32,.03),(-.36,.01,.3,.025),(.08,-.25,.50,.019)]):
        uv('Gel_Bubble_%d'%i,(x,y,z),(s,s,s*.65),'gel_light',10,8,True)


def rock(name, pos, dimensions, seed, mat='stone', bevel=.07, rotation=(0,0,0)):
    """石块用轻微不规则的削角网格和分面颜色，不堆叠高面数噪声。"""
    obj = box(name,pos,dimensions,mat,bevel,rotation)
    rng = random.Random(seed)
    for v in obj.data.vertices:
        v.co += Vector((rng.uniform(-.023,.023),rng.uniform(-.02,.02),rng.uniform(-.014,.014)))
    obj.data.materials.append(M['stone_light'])
    obj.data.materials.append(M['stone_dark'])
    if mat == 'stone':
        for f in obj.data.polygons:
            f.material_index = 1 if f.normal.z>.4 else 2 if f.normal.z<-.4 else 0
        if name=='Head' or name.startswith('Shoulder_'):
            obj.data.materials.append(M['moss'])
            for f in obj.data.polygons:
                if f.normal.z>.5 and rng.random()<.7: f.material_index=3
    return obj


def golem_model():
    """宽肩石头人的石缝来自真实部件间隙；各石段独立，入选后可做刚性绑定。"""
    rock('Pelvis',(0,.025,.83),(.63,.39,.34),1,bevel=.09)
    rock('Core_Shadow',(0,.035,1.29),(.65,.39,.64),2,'joint',.11)
    rock('Chest_Left',(-.20,-.10,1.45),(.42,.36,.44),3,bevel=.075,rotation=(.03,-.14,-.045))
    rock('Chest_Right',(.21,-.095,1.46),(.40,.36,.43),4,bevel=.07,rotation=(-.025,.14,.05))
    rock('Belly',(0,-.09,1.115),(.52,.34,.29),5,bevel=.06)
    rock('Back',(0,.23,1.36),(.62,.19,.54),6,bevel=.06)
    rock('Neck',(0,.025,1.73),(.25,.27,.17),7,'stone_dark',.04)
    rock('Head',(0,.005,1.92),(.43,.36,.34),8,bevel=.07)
    rock('Brow',(0,-.17,1.97),(.46,.13,.115),9,bevel=.028)
    rock('Jaw',(0,-.145,1.804),(.31,.15,.13),10,bevel=.026)
    for side in [-1, 1]:
        rock('Eye_Socket_'+str(side),(side*.094,-.196,1.91),(.099,.025,.049),21+side,'joint',.008)
        box('Eye_Amber_'+str(side),(side*.095,-.212,1.911),(.063,.016,.024),'amber',.003)
        uv('ShoulderCore_'+str(side),(side*.48,.03,1.51),(.16,.15,.18),'joint',10,8)
        rock('Shoulder_'+str(side),(side*.51,.025,1.58),(.40,.43,.36),30+side,bevel=.085,rotation=(0,side*.17,side*.03))
        rock('UpperArm_'+str(side),(side*.62,.015,1.29),(.30,.33,.32),40+side,bevel=.075,rotation=(0,side*-.18,0))
        uv('ElbowJoint_'+str(side),(side*.68,-.005,1.10),(.13,.13,.12),'joint',10,8)
        rock('Forearm_'+str(side),(side*.7,-.065,.94),(.33,.39,.38),50+side,bevel=.075,rotation=(.08,side*.10,0))
        rock('Fist_'+str(side),(side*.73,-.13,.70),(.36,.37,.25),60+side,bevel=.055)
        for knuckle in range(3):
            rock('Knuckle_%d_%d'%(side,knuckle),(side*(.63+knuckle*.1),-.292,.72),(.088,.09,.14),70+knuckle,'stone_light',.025)
        rock('Thigh_'+str(side),(side*.22,.025,.67),(.30,.32,.36),80+side,bevel=.06)
        uv('KneeJoint_'+str(side),(side*.235,-.005,.46),(.115,.12,.1),'joint',10,8)
        rock('Shin_'+str(side),(side*.25,-.015,.30),(.29,.29,.32),90+side,bevel=.055)
        rock('Foot_'+str(side),(side*.26,-.12,.10),(.36,.49,.20),100+side,bevel=.05)
    leaf('Core_Amber',[(-.034,-.268,1.48),(0,-.271,1.535),(.041,-.27,1.449),(.008,-.274,1.36)],'amber')
    tube('Head_Fracture',[(.045,-.18,2.06),(.018,-.191,2.025),(.056,-.19,1.997)],.007,'joint',5)


def aim(obj, target):
    obj.rotation_euler = (Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()


def stage():
    """独立摄影集合不属于角色资产；统一背景光照，比较造型而非不同渲染风格。"""
    collection = bpy.data.collections.new('STUDIO__not_part_of_model')
    bpy.context.scene.collection.children.link(collection)
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.002))
    floor = bpy.context.object
    for col in list(floor.users_collection): col.objects.unlink(floor)
    collection.objects.link(floor)
    floor.name = 'Studio_Ground'
    floor.data.materials.append(M['stage'])
    for name,pos,energy,size,color in [
        ('Key',(-3,-4,6),500,4,(1,.88,.72)),
        ('Fill',(4,-1,3),220,3,(.72,.86,1)),
        ('Rim',(0,4,5),650,3,(.85,1,.92))]:
        data = bpy.data.lights.new(name,'AREA')
        data.energy, data.size, data.color = energy,size,color
        data.shape = 'DISK'
        obj = bpy.data.objects.new(name,data)
        collection.objects.link(obj)
        obj.location = pos
        aim(obj,(0,0,.8))
    camera_data = bpy.data.cameras.new('Review_Camera')
    camera = bpy.data.objects.new('Review_Camera',camera_data)
    collection.objects.link(camera)
    camera_data.type = 'ORTHO'
    scene = bpy.context.scene
    scene.camera = camera
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.cycles.device = 'CPU'
    scene.render.threads_mode = 'FIXED'
    scene.render.threads = 8
    scene.world.use_nodes = True
    scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.13,.18,.21,1)
    scene.world.node_tree.nodes['Background'].inputs[1].default_value = .3
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'
    scene.view_settings.exposure = 0
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.resolution_percentage = 100
    scene.unit_settings.system = 'METRIC'
    return camera,collection


def set_camera(camera, target, scale, angle=26, elevation=18):
    angle, elevation = math.radians(angle), math.radians(elevation)
    camera.location = Vector(target)+Vector((math.sin(angle)*math.cos(elevation),-math.cos(angle)*math.cos(elevation),math.sin(elevation)))*8
    aim(camera,target)
    camera.data.ortho_scale = scale


def render(path, camera, target, scale, angle=26, elevation=18, size=(800,900)):
    set_camera(camera,target,scale,angle,elevation)
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def tidy_workspace(camera, target, scale):
    """打开文件即见全身和材质色；隐藏灯光辅助线，保留普通视口旋转与网格编辑。"""
    bpy.ops.object.select_all(action='DESELECT')
    for area in bpy.context.screen.areas if bpy.context.screen else []:
        if area.type == 'VIEW_3D':
            space = area.spaces.active
            space.shading.type = 'MATERIAL'
            space.overlay.show_extras = False
            space.region_3d.view_distance = scale*1.6
            space.region_3d.view_location = target
            space.region_3d.view_rotation = camera.rotation_euler.to_quaternion()
            space.region_3d.view_perspective = 'ORTHO'


def inspect_model(collection):
    """检查非空几何、实际尺寸与开放边；这里只报告模型，不把摄影地面计入面数。"""
    low = Vector((1e9,1e9,1e9))
    high = Vector((-1e9,-1e9,-1e9))
    triangles = vertices = meshes = open_edges = 0
    for obj in collection.objects:
        if obj.type != 'MESH': continue
        assert obj.data.vertices, 'Empty mesh: '+obj.name
        meshes += 1
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)
        vertices += len(obj.data.vertices)
        for corner in obj.bound_box:
            p = obj.matrix_world@Vector(corner)
            for i in range(3):
                low[i] = min(low[i],p[i]); high[i] = max(high[i],p[i])
        bm = bmesh.new(); bm.from_mesh(obj.data)
        open_edges += sum(1 for e in bm.edges if e.is_boundary)
        bm.free()
    assert meshes > 0 and triangles > 0
    assert not any(o.type=='ARMATURE' for o in collection.objects)
    return {'mesh_objects':meshes,'vertices':vertices,'triangles':triangles,'boundary_edges':open_edges,
            'bounds_min':list(low),'bounds_max':list(high),'dimensions_m':list(high-low),'rigged':False,'animated':False}


def clean_saved_files(output, names):
    """重开新生成文件后清理未关联数据，避免独立模型夹带其余候选的孤立网格。"""
    for name in names:
        path = Path(output)/(name+'.blend')
        bpy.ops.wm.open_mainfile(filepath=str(path),load_ui=True)
        bpy.ops.outliner.orphans_purge(do_recursive=True)
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True)
        print('MODEL_CLEANED',path.name,len(bpy.data.objects),flush=True)


def main():
    global MODEL, PARTS
    parser = argparse.ArgumentParser()
    parser.add_argument('--out',required=True)
    parser.add_argument('--only',choices=['goblin','skeleton','slime','golem'])
    parser.add_argument('--skip-render',action='store_true')
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    output = Path(args.out).resolve()
    output.mkdir(parents=True,exist_ok=True)
    names = ['goblin','skeleton','slime','golem'] if not args.only else [args.only]
    if any((output/(name+'.blend')).exists() for name in names):
        raise RuntimeError('Refusing to overwrite authored models. Choose a new output directory.')
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    palette()
    models, metadata = {}, {}
    builders = {'goblin':goblin_model,'skeleton':skeleton_model,'slime':slime_model,'golem':golem_model}
    for name in names:
        MODEL = bpy.data.collections.new('MODEL_'+name.upper())
        bpy.context.scene.collection.children.link(MODEL)
        PARTS = []
        builders[name]()
        bpy.context.view_layer.update()
        # 所有模型最低点落在同一地面；不同角色的自然身高保留，装备随同整体平移。
        bottom = min((obj.matrix_world@Vector(corner)).z for obj in PARTS for corner in obj.bound_box)
        for obj in PARTS: obj.location.z -= bottom
        bpy.context.view_layer.update()
        for obj in PARTS:
            obj['asset_role'] = 'model'
            obj['candidate'] = name
        MODEL['status'] = 'Model review only; no rig, animation or Godot integration'
        metadata[name] = inspect_model(MODEL)
        models[name] = MODEL
        print('MODEL_BUILT',name,json.dumps(metadata[name]),flush=True)
    camera, studio = stage()
    for name,col in models.items():
        for other in models.values():
            other.hide_render = other!=col
            other.hide_viewport = other!=col
        height = metadata[name]['bounds_max'][2]
        center = Vector((0,0,height*.5))
        scale = max(height*1.22,metadata[name]['dimensions_m'][0]*1.25)
        if not args.skip_render:
            render(output/(name+'_front.png'),camera,center,scale,0,10)
            render(output/(name+'_back.png'),camera,center,scale,155,15)
            render(output/(name+'_preview.png'),camera,center,scale,28,18)
        # 保存时只将当前角色和摄影集合留在场景中，独立文件不会夹带其余三个模型。
        excluded = [other for other in models.values() if other!=col]
        for other in excluded: bpy.context.scene.collection.children.unlink(other)
        set_camera(camera,center,scale)
        tidy_workspace(camera,center,scale)
        bpy.ops.wm.save_as_mainfile(filepath=str(output/(name+'.blend')),compress=True)
        for other in excluded: bpy.context.scene.collection.children.link(other)
    if not args.only:
        positions = {'goblin':-2.2,'skeleton':-.8,'slime':.65,'golem':2.3}
        for name,col in models.items():
            col.hide_render = False
            col.hide_viewport = False
            for obj in col.objects: obj.location.x += positions[name]
        center = Vector((.05,0,1.0))
        if not args.skip_render:
            render(output/'lineup.png',camera,center,7.1,12,14,(1600,800))
        set_camera(camera,center,7.1,12,14)
        tidy_workspace(camera,center,7.1)
        bpy.ops.wm.save_as_mainfile(filepath=str(output/'enemy_lineup.blend'),compress=True)
    (output/'model_report.json').write_text(json.dumps({'blender_version':bpy.app.version_string,'stage':'model_review_only','models':metadata},ensure_ascii=False,indent=2),encoding='utf-8')
    clean_saved_files(output,names+(['enemy_lineup'] if not args.only else []))
    print('MODEL_REVIEW_COMPLETE',str(output),flush=True)


if __name__ == '__main__':
    main()

