"""从人工维护的 Blender 源导出角色 GLB，不生成或覆盖源模型/动作。"""
import argparse
import sys
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[2]
SOURCES = {name: ROOT / f'assets/characters/blender/{name}_rig.blend'
           for name in ('player', 'guard', 'archer', 'skeleton', 'goblin', 'golem', 'slime')}


def export_character(asset):
    """每次重开已保存的源，显式选择身体/骨架，保持独立武器与隐藏参考不进入身体图集。"""
    bpy.ops.wm.open_mainfile(filepath=str(SOURCES[asset]), load_ui=False, use_scripts=False)
    rig = next(obj for obj in bpy.context.scene.objects if obj.type == 'ARMATURE')
    meshes = [obj for obj in bpy.context.scene.objects
              if obj.type == 'MESH' and obj.get('art_part') in ('upper', 'lower', 'full')]
    if not meshes or not bpy.data.actions:
        raise RuntimeError(f'{asset} 缺少身体网格或动作，停止导出')
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    for mesh in meshes:
        mesh.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.context.scene.render.fps = 96
    # 输出先落临时文件，导出完成才替换 GLB；不保存或改写 blend。
    output = ROOT / f'assets/characters/{asset}_source.glb'
    temporary = ROOT / f'work/character_export/{asset}_source.glb'
    temporary.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(temporary), export_format='GLB', use_selection=True,
        export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=True,
        export_frame_range=False, export_skins=True, export_all_influences=False,
        export_extras=True, export_yup=True, export_cameras=False, export_lights=False)
    temporary.replace(output)
    print('EXPORTED_CHARACTER', asset, len(meshes), len(bpy.data.actions))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('assets', nargs='*', metavar='character')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    if any(asset not in SOURCES for asset in args.assets):
        parser.error('角色必须是 ' + '、'.join(SOURCES))
    for asset in args.assets or list(SOURCES):
        export_character(asset)
