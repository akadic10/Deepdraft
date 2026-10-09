"""Export berry-free juniper variants without changing their silhouette or trunk."""
from pathlib import Path

from generate_forest_redesign import build_model, mesh_model
from generate_juniper_redesign import BERRIES, LEAVES
from voxel_glb import write_glb


def main():
    destination = Path(__file__).resolve().parents[1] / 'assets/models/flora/trees/juniper'
    for stage in ('mature', 'ancient'):
        for season in ('summer', 'winter'):
            for variant in (1, 2):
                vox = build_model('juniper', stage, season, variant)
                berry_cells = [p for p, color in vox.cells.items() if color in BERRIES]
                assert berry_cells, (stage, season, variant)
                for x, y, z in berry_cells:
                    vox.cells[x, y, z] = LEAVES[abs(x * 31 + y * 17 + z * 13) % len(LEAVES)]
                name = f'juniper_{stage}' + ('_winter' if season == 'winter' else '') + ('_2' if variant == 2 else '') + '_picked'
                write_glb(destination / (name + '.glb'), name, mesh_model(vox, 'juniper', stage))
                print(name, len(berry_cells), 'berry voxels replaced; geometry preserved')


if __name__ == '__main__':
    main()
