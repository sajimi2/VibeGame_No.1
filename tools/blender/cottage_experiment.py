"""小屋实验：只在 --init 时创建初始简模；默认从已保存的 .blend 导出，不覆盖人工修改。"""
import math
import sys
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[2]
ASSET = ROOT / 'assets/environment/painted/cottage/structure'
SOURCE = ASSET / 'source/cottage.blend'


def point(v):
    return (v[0], -v[2], v[1])


def box(name, center, size, tilt=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=point(center))
    obj = bpy.context.object
    obj.name = name
    obj.scale = (size[0], size[2], size[1])
    obj.rotation_euler.y = -tilt
    return obj


def initialize():
    if SOURCE.exists():
        raise RuntimeError('源文件已存在，禁止初始化覆盖；日常运行不加 --init。')
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    # 五米宽、六米深；门洞净宽 1.5m、高 2.2m，室内与地面齐平。
    box('WallBack', (0, 1.4, -2.825), (5, 2.8, .35))
    box('WallWest', (-2.325, 1.4, 0), (.35, 2.8, 5.3))
    box('WallEast', (2.325, 1.4, 0), (.35, 2.8, 5.3))
    box('WallFrontLeft', (-1.625, 1.4, 2.825), (1.75, 2.8, .35))
    box('WallFrontRight', (1.625, 1.4, 2.825), (1.75, 2.8, .35))
    box('WallLintel', (0, 2.5, 2.825), (1.5, .6, .35))
    box('SupportFloor', (0, -.06, 0), (5, .12, 6))
    box('Crate', (-1.35, .45, -.95), (.9, .9, .9))
    slope = math.atan2(1.3, 2.5)
    for side in (-1, 1):
        box('RoofWest' if side < 0 else 'RoofEast', (side*1.45, 4.1-1.45*.52, 0),
            (math.hypot(2.9, 2.9*.52), .12, 6.7), -side*slope)
    # 山墙也只是三角棱柱，补齐轮廓即可，不制作砖瓦或木纹几何。
    for name, z in [('GableFront', 2.825), ('GableBack', -2.825)]:
        vertices = [point((x,y,z+dz)) for dz in (-.175,.175)
                    for x,y in [(-2.5,2.8),(2.5,2.8),(0,4.1)]]
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(vertices, [], [(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)])
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
    SOURCE.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))


if '--init' in sys.argv:
    initialize()
else:
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE), load_ui=False, use_scripts=False)
# 临时导出成功后替换 GLB；不会保存或重建源 .blend。
temporary = ROOT / 'work/cottage_export.glb'
temporary.parent.mkdir(exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(temporary), export_format='GLB', export_yup=True,
                          export_animations=False, export_cameras=False, export_lights=False)
temporary.replace(ASSET / 'cottage_shell.glb')
print('COTTAGE_EXPORTED', SOURCE)
