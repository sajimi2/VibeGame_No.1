"""重开制作源，按骨架类别验证动作、权重与真实顶点运动；不改源文件。"""
import hashlib
import json
import math
import sys
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
from export_characters import SOURCES
CLIPS = {'player': 'heavy_swing', 'archer': 'bow_draw', 'guard': 'shield_slash', 'skeleton': 'shield_slash', 'goblin':'attack','golem':'attack','slime':'attack'}


def posed_hand(obj, frame):
    """通过依赖图读取蒙皮后的实体顶点，避免只检查动作名字。"""
    bpy.context.scene.frame_set(frame)
    obj = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    return [obj.matrix_world @ v.co for v in obj.data.vertices]


def validate(asset):
    path = SOURCES[asset]
    before = hashlib.sha256(path.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(path), load_ui=False, use_scripts=False)
    rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH' and o.get('art_part') in ('upper', 'lower', 'full')]
    creature = asset in ('goblin','golem','slime')
    assert len(rig.data.bones) == (3 if asset=='slime' else 16 if asset=='goblin' else 15) and meshes
    for name in (('Root','Gel','Crown') if asset=='slime' else ('Pelvis', 'Spine', 'Head', 'HandL', 'HandR', 'FootL', 'FootR')):
        assert name in rig.data.bones, name
    for clip in (('idle','walk','attack','hurt','death_fall') if creature else (CLIPS[asset], 'walk_00', 'run_06', 'jump_00', 'hurt', 'death_fall')):
        assert clip in bpy.data.actions, clip
    for obj in meshes:
        assert any(m.type == 'ARMATURE' and m.object == rig for m in obj.modifiers), obj.name
        assert len(obj.data.materials) > 0, obj.name
        for vertex in obj.data.vertices:
            assert abs(sum(g.weight for g in vertex.groups)-1) < 1e-6, obj.name
            assert all(math.isfinite(v) for v in vertex.co), obj.name
        assert all(g.name in rig.data.bones for g in obj.vertex_groups), obj.name
    rig.animation_data.action = bpy.data.actions[CLIPS[asset]]
    hand = next(o for o in meshes if o.name==('Slime_Body' if asset=='slime' else 'Fist_1' if asset=='golem' else 'Spear_Wood')) if creature else next(o for o in meshes if o.get('bound_bone') == 'HandR')
    a, b = posed_hand(hand, 0), posed_hand(hand, 48)
    delta = max((x-y).length for x, y in zip(a, b))
    assert delta > .03
    assert hashlib.sha256(path.read_bytes()).hexdigest() == before
    return {'bones': len(rig.data.bones), 'clips': len(bpy.data.actions), 'meshes': len(meshes),
            'actual_hand_motion_m': delta, 'source_sha256': before}


report = {asset: validate(asset) for asset in SOURCES}
output = ROOT / 'work/checks/blender_characters.json'
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print('BLENDER_CHARACTERS_VALIDATED', json.dumps(report))
