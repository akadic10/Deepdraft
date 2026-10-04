#!/usr/bin/env python3
"""Generate the approved Deepdraft dwarf roster (41 modular GLBs).

Run: python tools/generate_dwarf_glb.py [--out DIR] [--check]
Default output: assets/dwarves. All 800 current appearance combinations are
validated before writing. --check validates the source without writing GLBs.

8 voxels = 1 block. X/Z cell centres are integers; character meshes receive a
half-cell centering shift before the baked 0.125 export scale. All parts share
one origin; left/right hands and feet still mirror at runtime with scale.x=-1.
Keep Godot import Root Scale at 1.0. See docs/00_dev_roadmap/25_dwarf_visual_redesign.md.

The common voxel helpers remain re-exported here for existing tree, item and
furniture generators; their corner-based frame and output are unchanged.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
from voxel_glb import Voxels, mesh_from_voxels, write_glb
from dwarf_roster import (AGES, HAIR_MALE, HAIR_FEMALE, BEARDS, BROWS_MALE,
                         BROWS_FEMALE, SCARS, build_head, build_body, build_hand,
                         build_foot, build_eyes, build_hair, build_beard,
                         build_brows, build_scar, manifest, part_mesh, validate)

EXPORT_SCALE = 0.125


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--out', type=Path, default=Path(__file__).resolve().parents[1]/'assets/dwarves')
    ap.add_argument('--check', action='store_true')
    args = ap.parse_args()
    parts = {f'{folder}/{name}': builder() for folder,name,builder in manifest()}
    report = validate(parts)
    print(json.dumps(report))
    if args.check:
        return
    hashes = {}
    for key,v in parts.items():
        path = args.out / (key+'.glb')
        write_glb(path,path.stem,part_mesh(v,key.startswith('scars/')),EXPORT_SCALE)
        hashes[key] = hashlib.sha256(path.read_bytes()).hexdigest()
    # Keep generated QA reports outside the live import tree.
    report_path = Path(__file__).resolve().parents[1]/'tmp/dwarf_roster/geometry_report.json'
    report_path.parent.mkdir(parents=True,exist_ok=True)
    report_path.write_text(json.dumps({**report,'sha256':hashes},indent=2)+'\n')
    print(f'Wrote {len(parts)} GLBs to {args.out.resolve()}. Root Scale remains 1.0.')


if __name__ == '__main__':
    main()
