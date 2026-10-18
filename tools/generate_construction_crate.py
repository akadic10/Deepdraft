"""Automatic construction packaging, reusing the production open-crate shell."""
from pathlib import Path
from generate_items_faceted import crate_shell
from generate_wildlife_faceted import validate
from voxel_glb import write_glb

root = Path(__file__).resolve().parents[1]
mesh = crate_shell()
validate("materials_crate", mesh)
write_glb(root / "assets/models/construction/materials_crate.glb",
          "materials_crate", mesh.arrays())
