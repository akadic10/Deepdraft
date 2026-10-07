"""Approved dining geometry and isolated seated-dwarf review export. Does not install assets."""
import json
import shutil
from pathlib import Path

from voxel_glb import Voxels, write_glb
from generate_tavern_redesign import OAK, IRON, box, export_mesh, sha

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'tmp/seating_study'


def table(width, depth=2):
    """1.75-block top; depth variants retain clearance at the occupied edges."""
    v = Voxels()
    half = width * 4
    half_depth = depth * 4
    support = half_depth - 2
    for x0 in (-half + 2, half - 5):
        box(v, x0, x0+3, 0, 2, -support, support, OAK[2])
        box(v, x0, x0+3, 0, 1, -support, support, IRON[1])
        box(v, x0, x0+3, 2, 11, -2, 2, OAK[3])
        box(v, x0, x0+3, 10, 12, -support, support, OAK[2])
        for y, reach in [(6, 2), (7, 3), (8, 4), (9, 5)]:
            box(v, x0, x0+3, y, y+1, -reach, reach, OAK[3])
    box(v, -half+1, half-1, 3, 5, -1, 1, OAK[2])
    for x in range(-half, half):
        for z in range(-half_depth, half_depth):
            if abs(x+.5) == half-.5 and abs(z+.5) == half_depth-.5:
                continue
            v.cells[x, 12, z] = OAK[2]
            color = OAK[5 if (z+half_depth)//4 % 2 == 0 else 4]
            if z % 4 == 0: color = OAK[3]
            if z in (-half_depth, half_depth-1) or x in (-half, half-1): color = OAK[5]
            v.cells[x, 13, z] = color
    for x in (-half+1, half-2):
        for z in (-half_depth+1, half_depth-2):
            box(v, x, x+1, 13, 14, z-1, z+2, IRON[1])
            v.cells[x, 13, z] = IRON[2]
    for z in range(-half_depth+2, half_depth, 4):
        for x in range(-half+3, half-3):
            if (x+half+z) % 13 < 3:
                v.cells[x, 13, z] = OAK[4]
    return v


def chair():
    """2x2 footprint, .875 seat and 1.375 low back, clear of long rear hair."""
    v = Voxels()
    for x0 in (-8, 6):
        for z0 in (-8, 6):
            box(v, x0, x0+2, 0, 6, z0, z0+2, OAK[3])
            box(v, x0, x0+2, 0, 1, z0, z0+2, IRON[1])
        box(v, x0, x0+2, 6, 11, -8, -6, OAK[3])
        box(v, x0, x0+2, 3, 4, -6, 6, OAK[2])
    box(v, -8, 8, 5, 7, -8, 8, OAK[4])
    for z in range(-8, 8):
        for x in range(-8, 8):
            v.cells[x, 6, z] = OAK[5] if z % 4 else OAK[3]
    # Broad, low back supports the torso below the flowing hair.
    box(v, -8, 8, 7, 11, -8, -7, OAK[3])
    box(v, -7, 7, 10, 11, -8, -6, OAK[5])
    for x in (-8, 7):
        box(v, x, x+1, 7, 10, 5, 7, OAK[3])
        box(v, x, x+1, 9, 11, -7, 7, OAK[4])
        box(v, x, x+1, 10, 11, -6, 6, OAK[5])
        v.cells[x, 9, 6] = IRON[1]
    return v


def connected_count(voxels):
    remaining = set(voxels.cells)
    count = 0
    while remaining:
        pending = [remaining.pop()]
        count += 1
        while pending:
            x, y, z = pending.pop()
            for q in [(x-1,y,z), (x+1,y,z), (x,y-1,z), (x,y+1,z), (x,y,z-1), (x,y,z+1)]:
                if q in remaining:
                    remaining.remove(q)
                    pending.append(q)
    return count


def generate():
    for folder in ['models', 'reference', 'dwarves', 'renders']:
        (OUT / folder).mkdir(parents=True, exist_ok=True)
    report = {'status': 'preview_only', 'models': {}, 'source_hashes': {}}
    for name, voxels, size in [('personal_table', table(2), [2,1.75,2]),
                               ('communal_table', table(8), [8,1.75,2]),
                               ('communal_table_8x3', table(8,3), [8,1.75,3]),
                               ('communal_table_8x4', table(8,4), [8,1.75,4]),
                               ('wide_chair', chair(), [2,1.375,2])]:
        mesh = export_mesh(voxels)
        path = OUT / 'models' / (name + '.glb')
        write_glb(path, name, mesh, export_scale=.125)
        low = [min(p[a] for p in mesh[0])*.125 for a in range(3)]
        high = [max(p[a] for p in mesh[0])*.125 for a in range(3)]
        assert [high[a]-low[a] for a in range(3)] == size
        assert connected_count(voxels) == 1
        report['models'][name] = {'bounds': [low, high], 'voxels': len(voxels), 'sha256': sha(path)}
    for source in (ROOT / 'assets/dwarves').rglob('*.glb'):
        if source.parent.name not in ['body', 'hair', 'beards', 'eyebrows']:
            continue
        relative = source.relative_to(ROOT / 'assets/dwarves')
        target = OUT / 'dwarves' / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        report['source_hashes'][str(source.relative_to(ROOT))] = sha(source)
    for name in ['wooden_chair', 'wooden_table']:
        filename = 'wooden_chair_legacy' if name == 'wooden_chair' else name
        source = ROOT / 'assets/models/furniture' / (filename+'.glb')
        shutil.copyfile(source, OUT / 'reference' / (name+'.glb'))
        report['source_hashes'][str(source.relative_to(ROOT))] = sha(source)
    for name in ['TreeRedesignPreview.gd', 'SeatingStudy.gd']:
        shutil.copyfile(ROOT / 'tools' / name, OUT / name)
    (OUT / 'project.godot').write_text('''config_version=5
[application]
config/name="Deepdraft seated dining study"
run/main_scene="res://review.tscn"
[display]
window/size/viewport_width=1600
window/size/viewport_height=1000
window/size/window_width_override=1280
window/size/window_height_override=800
[rendering]
renderer/rendering_method="forward_plus"
rendering_device/driver.windows="d3d12"
anti_aliasing/quality/msaa_3d=2
''', encoding='utf-8')
    (OUT / 'review.tscn').write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://SeatingStudy.gd" id="1"]
[node name="SeatingStudy" type="Node3D"]
script = ExtResource("1")
''', encoding='utf-8')
    (OUT / '.gitignore').write_text('.godot/\n*.import\n*.uid\n', encoding='utf-8')
    (OUT / 'validation.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print('SEATING_STUDY_EXPORTED: personal 2x2, communal 8x2/8x3/8x4, chair 2x2; original assets copied unchanged')


if __name__ == '__main__':
    generate()
