# 61 — Voxel art authoring guide

How to build a model in the Hearthblock style. The look is defined in
[64 — Hearthblock art direction](64_hearthblock_art_direction.md). Renderer, pipeline
and acceptance rules are in [63 — Technical art standard](63_shared_art_standard.md).
Dwarf appearance pools and runtime tinting are in
[41b](../40_economy_colony/41b_dwarf_appearance_glb.md).

Every production model is built on the 1:16 grid: one cell is 1/16 of a world block on
each axis (0.0625 Godot units).

## Where things live

| Path | What it holds |
| --- | --- |
| `tools/hearthblock/art/proposal.mjs` | The approved proposal models, verbatim, and the shared `Vox` cell vocabulary and palette |
| `tools/hearthblock/art/tier1.mjs` | Tier 1 · Axe-Hewn furniture, hearth, kits and flag |
| `tools/hearthblock/art/dwarves.mjs` | Every dwarf part: heads, eyes, body, mittens and cuffs, boots, hair, beards, brows, scars, work tools |
| `tools/hearthblock/art/wildlife.mjs` | Rabbit, deer, wolf and ducks |
| `tools/hearthblock/art/export.mjs`, `write_data.py` | Export the `.mjs` models to `tools/art_data/voxel_hearthblock.json` |
| `tools/voxel_assets/hearthblock.py` | Replays those operations for the Python builders |
| `tools/voxel_assets/build.py` | Stages, checks and installs a family |
| `tools/voxel_assets/<family>.py` | Family builders: `trees`, `plants`, `rocks`, `crops`, `dwarves`, `presentation`, `wildlife`, `furniture`, `items` (+ `hearthblock_goods`), `construction` |
| `tools/voxel_glb.py`, `tools/voxel_shadow.py` | Greedy mesher with opt-in baked occlusion, GLB writer, shadow proxies |
| `tools/art_data/voxel_*.json` | Family profiles and palettes; installed manifests in `tools/art_data/voxel_manifests/` |
| `tools/art_data/studies/hearthblock_furniture_tiers.json` | Tier 1 and Tier 2 furniture study layouts (never delete) |

Art data sits under `tools/` (not `data/`) because no game script reads it; the export preset excludes `tools/*`,
so it does not ship.

## Cell vocabulary

Models are lists of cell operations on integer coordinates, Y up:
- `box(x0,x1, y0,y1, z0,z1, role)` fills a block of cells;
- `cut(..., n, role)` makes a notched box whose vertical edges are clipped by `n`
  cells (`cutX` and `cutZ` clip the edges that run along X or Z);
- `paint` recolours existing cells only;
- `ring` draws growth rings on a cut end;
- `air` (a box with no role) carves cells away;
- `mirror_x` builds one side and mirrors it.

Python builders use the same ideas (`notched`, `paint` and `carve` in
`hearthblock_goods.py`, `square_clump` in `plants.py`, square crowns and `square_pine`
in `trees.py`).

Roles are semantic names (`wood`, `bark`, `grain`, `rope`, `hay`, `stone`, `iron`,
`tunic`, `skin` and so on), not colours. The palette maps them to colours:
- Wood roles map to the existing source palettes, so `CraftMaterials` recolours them
  for pine, oak, juniper and apple.
- Skin, hair and eye roles are tinted per dwarf.
- The tunic and cuffs are recoloured to the dwarf's clothing colour.
- Everything else is a fixed colour.

Keep wood swatches for wood only, or hay and stone would recolour with the wood.

## Workflow

1. **Edit the source.** Edit a `.mjs` file under `tools/hearthblock/art/`, then run
   `py -3 tools/hearthblock/art/write_data.py` (it needs Node). Or edit a Python
   builder in `tools/voxel_assets/`.
2. **Stage.** Run `py -3 tools/voxel_assets/build.py FAMILY`. `--only <path substring>`
   stages a quick preview, but a partial family can't be installed.
3. **Review the gallery.** Run `tools/voxel_assets/Gallery.gd` with `--family=FAMILY`
   and `--output=res://tmp/<label>/`, then look at the captures. It writes
   `gallery.json` with the exact hashes it reviewed. The family galleries
   (`FurnitureGallery`, `DwarfGallery`, `WildlifeGallery`, `TreeGallery`, `PlantGallery`,
   `ItemGallery`) show contact sheets.
4. **Install.** Run `build.py FAMILY --install --review <gallery.json>`, then import with
   `tools/voxel_assets/Import.ps1`.
5. **Verify.** Run `build.py FAMILY --check` (byte-identical regeneration) and the
   Python tests (`py -3 -m unittest` in `tools/voxel_assets`). Then run the family's
   Godot art and gameplay tests from `scripts/tests/`: `DwarfArtTest`,
   `WildlifeArtTest`, `ItemArtTest`, `FurnitureArtTest`, `FireArtTest`,
   `GemDropArtTest`, `GroundStoneArtTest`, `SurfaceVegetationArtTest` and
   `VoxelPipelineTest`.
6. **Check in the game.** Run the game and look at the model in the main world, which
   always uses Hearthblock lighting.
7. **Re-render the menu pictures** that show the model with
   `tools/FurnitureCatalogThumbnails.gd`, `tools/InventoryCatalogThumbnails.gd` or
   `tools/GenerateFloorIcons.gd`.

Run Godot with `APPDATA` and `LOCALAPPDATA` pointed at a scratch folder so the player's
profile and saves are never touched. The project starts borderless fullscreen, so a
windowed capture must switch the window to `WINDOWED` first.

## File conventions

```
res://assets/models/
  animals/        wildlife, grouped by species
  characters/
    dwarves/      modular appearance parts and work tools
  flora/
    trees/  bushes/  flowers/  reeds/  crops/
  rocks/
    boulders/  scree/
  construction/   floors and the materials crate
  furniture/      furniture, packed forms and flame animation libraries
  items/          loose goods, crates and inventory tools
  presentation/   eyelids and meal servings
```

Flora files are named `{species}_{stage}[_{season}][_{variant}].glb`, with stage and
season strings exactly as the registry uses them. The registry builds the path by
concatenation. Examples:
- `oak_mature.glb` (summer, variant 1);
- `oak_mature_autumn_2.glb` (autumn, variant 2);
- `pine_mature_winter.glb` (evergreens have no summer suffix).

Furniture, workshops and world objects are named `{id}.glb`. Paths hold only the leaf
name; the registry adds the `base:flora:`, `base:furniture:` or `base:workshop:`
namespace.

All variants of one species, stage and season share:
- the trunk base position;
- the logical trunk footprint and occupancy height;
- the stage's visual height.

They may differ in crown silhouette, branch layout, a small lean (at most ±5°) and
detail placement. `clearance_height` is trunk occupancy, not visual height. Canopy
overhang never enlarges ground occupancy.

## Checklist

- [ ] Built from boxes, notched boxes and steps; no round geometry.
- [ ] Reads at colony zoom: a clear silhouette, lit tops and dark undersides.
- [ ] One or two deliberate marks; no per-cell noise.
- [ ] Roles, not colours: wood recolours in all four woods; tints and clothing still work.
- [ ] Every state is present: growth, season, picked, packed, fill level, appearance.
- [ ] Gameplay contracts kept: footprint, clearance, seat and sleep heights, grips,
      ground contact (see [64](64_hearthblock_art_direction.md)).
- [ ] Shadow proxy present. Baked occlusion is used where it doesn't multiply triangles.
- [ ] Gallery reviewed, `--check` byte-identical, family tests passing.
- [ ] Seen in the game under Hearthblock lighting; menu pictures re-rendered.

## Material rule

Furniture is woodwork (owner, 2026-07-11): beds, chairs, benches, tables and shelves,
anything dwarves use rather than work at, are wood, warm against the stone. Stone and
iron are for industrial anchors (anvil, trade counter, workshop bodies) and monuments.
Within a tier, Tier 1 pieces stay axe-hewn (split, notched, lashed, no iron); joinery,
planks and blankets wait for Tier 2.
