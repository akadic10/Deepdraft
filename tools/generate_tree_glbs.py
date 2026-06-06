#!/usr/bin/env python3
"""
DEPRECATED — retired 2026-06-06.

This produced oak GLBs at the old 8-voxels/block fine style. Trees are now
authored 1:1 (1 voxel = 1 block, scale 1.0; see docs/60_asset_creation/
61_voxel_art_guide.md). Use the per-species 1:1 generators instead:

    generate_pine_glbs.py
    generate_apple_glbs.py
    generate_oak_glbs.py
    generate_juniper_glbs.py
"""

import sys

if __name__ == "__main__":
    sys.exit("generate_tree_glbs.py is retired — use generate_oak_glbs.py "
             "(and the other per-species 1:1 generators).")
