import sys
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / 'tools'))
from generate_log_furniture import door_parts, write_door

out = Path(__file__).resolve().parent
(out / 'framed_reference').mkdir(exist_ok=True)
for width in (2, 3, 4):
    name = 'door' if width == 2 else f'log_door_{width}'
    target = root / 'assets/models/furniture' / f'{name}.glb'
    reference = out / 'framed_reference' / target.name
    if not reference.exists(): shutil.copyfile(target, reference)
    parts = door_parts(width)
    assert len(parts) == (2 if width == 4 else 1)
    assert all(name.startswith('leaf_') for name, _ in parts)
    cells = set().union(*(set(part.cells) for _, part in parts))
    assert all(-width*4 <= x < width*4 and 0 <= y < 31 and -3 <= z < 3 for x,y,z in cells)
    assert min(x for x,y,z in cells) == -width*4
    assert max(x for x,y,z in cells) == width*4-1
    write_door(target, width, out)
    print(f'{name}: {len(parts)} leaves, no frame, {len(cells)} voxels')
