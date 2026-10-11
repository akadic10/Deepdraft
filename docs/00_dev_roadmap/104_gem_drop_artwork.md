# 104 — Finished gem drop artwork

Implemented 2026-10-10.

## Decision and visible result

The user requested the missing gem artwork and explicitly rejected a future
Jeweller function: gems should already be shiny and pretty when they drop.
Jade, Amethyst, Ruby, Sapphire, Emerald and Diamond now have real imported
models and transparent inventory icons. Their displayed names omit "Raw".
There is no cutting, polishing, Jeweller profession or workshop on the roadmap.
This supersedes the deferred Jeweller proposal in the crafting document.

The user rejected the initial angled polygon faces as inconsistent with the
project's voxel approach. All six models and icons were rebuilt with true cube
geometry on the existing item grid; the shiny, finished-drop decision remains.

## Art and integration

`tools/generate_gem_glbs.py` deterministically writes six GLBs under
`assets/models/items/gem/`. The shared `Voxels` container and exposed-face mesher
build a stepped jewel from 100 unit cubes. Five layers widen from a grounded
base into broad shoulders, then narrow to a flat crown. Shoulder corners omit
whole cubes. Each asset has 304 triangles and a 6×5×6-voxel envelope
(0.75×0.625×0.75 blocks), within one block at every yaw. Eight voxels per block
and baked scale 0.125 match the other items; import/root scale remains 1.
All faces are axis-aligned cube faces. There are no sloped polygon facets,
bevels, textures, smooth normals or colliders.

Linear vertex-colour palettes distinguish mint jade, violet amethyst, crimson
ruby, royal-blue sapphire, vivid emerald and icy diamond. Bright stepped bands
and small square glints give a finished gem appearance at RTS and inventory
sizes while retaining the project's voxel geometry.

ItemDropManager still owns the resource definitions and the common visual path.
The optional `surface` dictionary supplies `roughness` and `specular` values
for a cached material per item type. Standard materials cover isolated catalog
views. In the world, UndergroundLighting adds opt-in direct-light highlights
using the same daylight-access gate as its diffuse light. Ordinary materials
retain zero gloss; gems add no lights, particles, transparency, emission or
per-item processing. The shared faint underground readability floor still applies.

The same artwork survives spawning, dwarf pickup, stockpile deposit, shelf
fitting and save restoration. InventoryCatalogThumbnails now obtains the item
visual from its registry so the six generated icons retain the surface finish.

The `_raw` item keys and filenames remain stable identifiers only. Mining drop
chances and counts, trade values, stockpile filters, stack limits and carry costs
are unchanged. No recipes or additional resource stages were introduced.

## Verification

All checks passed in Godot 4.7.2; native captures used the project's D3D12
Forward+ renderer. Test profiles were isolated from player saves.

- `GemDropArtTest.gd`: six actual mining drop definitions resolve to imported
  ArrayMeshes and inventory icons; palettes differ; real pickup/deposit,
  slot bounds, slice visibility and JSON save restoration preserve goods.
- `GemDropArtTest.gd -- --capture`: rendered daylight, sealed darkness and
  torchlight; removing gloss changes real image pixels, while toggling the sun
  in sealed air produces exactly zero image difference. Actual dwarf carry
  posing uses actor exposure; a real shelf container restores six visible slots.
- Existing native `UndergroundLightingTest.gd`: all assertions pass, including
  entrance falloff, door boundaries, stacked floors, torches and restored fields.
  Only its capture destination was redirected for this run.
- Existing headless `ColonyInventoryTest`, `LooseItemSupportTest` and
  `SaveManagerRoundTripTest`: pass, including full scene and backup recovery.
- Six transparent thumbnails generated successfully; native art, icons and
  the dwarf/shelf scale capture were visually reviewed.

The voxel revision reran `GemDropArtTest` with native captures and regenerated
all six thumbnails. New geometry assertions check imported normals are axial
and positions align to the 1/8-block grid, allowing only Godot's small mesh
compression error; the generator checks its uncompressed grid exactly. The
native pass also rechecks lighting, carrying, shelf fitting and save restoration.
The broader inventory/lighting/save regressions above were run for the unchanged
runtime integration in the initial pass.

Review files:

- `tmp/gem_drop_review/gems.png` — all six palettes with real item materials.
- `tmp/gem_drop_review/game_scale.png` — dwarf carrying a ruby, stocked shelf,
  and loose drops at their gameplay sizes.
- `tmp/gem_drop_review/sealed_dark.png` and `torchlight.png` — lighting checks.
- `tmp/gem_drop_review/checks.json` — native assertions and pixel measurements.
- `tmp/gem_drop_review/underground_lighting_review/checks.json` — shared lighting regression.

Rebuild the models with `python tools/generate_gem_glbs.py`, then let Godot
import them. Run the thumbnail tool with `--only=` and the six comma-separated
gem keys to regenerate just these icons. Run the art test headless for its
contracts, or natively with `-- --capture` to reproduce the review images.
