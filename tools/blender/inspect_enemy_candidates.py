"""用独立 Blender 进程重新打开候选文件，验证交付模型可读且没有提前进入绑定或动画阶段。"""
import argparse
import json
import math
import sys
from pathlib import Path

import bpy


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--folder', required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    folder = Path(args.folder).resolve()
    report = json.loads((folder/'model_report.json').read_text(encoding='utf-8'))
    results = []
    for name in ['goblin','skeleton','slime','golem','enemy_lineup']:
        path = folder/(name+'.blend')
        assert path.exists() and path.stat().st_size > 10000, str(path)
        bpy.ops.wm.open_mainfile(filepath=str(path), load_ui=True)
        scene = bpy.context.scene
        collections = [c for c in scene.collection.children if c.name.startswith('MODEL_')]
        expected = list(report['models']) if name=='enemy_lineup' else [name]
        assert sorted(c.name for c in collections)==sorted('MODEL_'+a.upper() for a in expected)
        assert scene.camera is not None
        assert not any(o.type=='ARMATURE' for o in scene.objects)
        assert not any(o.animation_data and o.animation_data.action for o in scene.objects)
        assert not any(image.source=='FILE' and not image.packed_file for image in bpy.data.images)
        assert all(obj.users>0 for obj in bpy.data.objects), 'Unlinked model data remains in '+name
        for asset in expected:
            col = bpy.data.collections['MODEL_'+asset.upper()]
            meshes = [o for o in col.objects if o.type=='MESH']
            assert not col.hide_render and not col.hide_viewport
            assert len(meshes)==report['models'][asset]['mesh_objects']
            for obj in meshes:
                assert len(obj.data.vertices)>0 and len(obj.data.materials)>0
                assert all(math.isfinite(v) for vertex in obj.data.vertices for v in vertex.co)
        results.append({'file':path.name,'visible_models':expected,'bytes':path.stat().st_size,'reopened':True})
        print('REOPEN_OK',path.name,flush=True)
    (folder/'validation.json').write_text(json.dumps({'blender_version':bpy.app.version_string,'files':results,'no_rig_or_animation':True,'no_external_texture_dependencies':True},indent=2),encoding='utf-8')
    print('MODEL_VALIDATION: 5 files reopened, 0 failures',flush=True)


if __name__=='__main__':
    main()
