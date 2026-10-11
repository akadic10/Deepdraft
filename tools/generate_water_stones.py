"""Wet/dry source stones use the exact authored ore-drop silhouette and flecks.

Only the fleck palette differs. Existing ore assets are never rewritten.
These are world features, not inventory goods; eight voxels per block, Y0 base.
"""
from pathlib import Path
from generate_ore_glbs import build_rock_template, build_ore, _c, EXPORT_SCALE
from voxel_glb import mesh_from_voxels, write_glb

ROOT = Path(__file__).resolve().parents[1]
PALETTES = {"wet_stone": (0x69B6AF, 0x398F8A), "dry_stone": (0xC2CDD0, 0x87989E)}

if __name__ == "__main__":
    template = build_rock_template()
    for name, (main, shadow) in PALETTES.items():
        voxels = build_ore(template, _c(main), _c(shadow))
        assert set(voxels.cells) == template[0]
        mesh = mesh_from_voxels(voxels)
        assert all(sum(abs(v) for v in n) == 1 for n in mesh[1])
        write_glb(ROOT / "assets/models/world/water" / f"{name}.glb", name, mesh, EXPORT_SCALE)
        print(f"{name}: {len(voxels)} voxels, exact ore shape, 1 x 1 x 1 block")
