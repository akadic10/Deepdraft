# 160 — Faceted fire

**2026-10-13:** The player reported the remaining cube-shaped flames on the
converted campfire and torches. The furniture migration had preserved both
their static flame meshes and the old animation libraries. This batch replaces
both presentations across all six existing fire sources.

| Source | Static named flame | Animated frames |
|---|---|---:|
| Campfire | `campfire_flame` | 8 |
| Hearth | `hearth_flame` | 10 |
| Brazier | `brazier_flame` | 8 |
| Smelter | `smelter_flame` | 8 |
| Wall torch | `torch_flame` | 8 |
| Log torch | `torch_flame` | Shares the wall-torch clip |

The flames use closed, curved, tapered tongues with pale golden cores, amber
edges and continuous vertex-color gradients. Their roots stay fixed while the
upper silhouettes sway and change height through the existing flipbook timing.
Static catalogue/placement flames are generated from the exact first frame.
The imported runtime uses one opaque flame surface and one visible frame per
source; no textures, particles, extra lights or save fields are added.

The shared lighting owner now defaults flames to unshaded emission so their
far sides do not turn dark behind brackets or logs. Definitions can still
explicitly override this render choice. Existing point-light strengths, ranges,
shadows, heat, sound, frame durations, phase offsets and visibility gates remain
unchanged. All six furniture definitions are byte-identical.

Eleven GLBs change: six furniture files containing static flames and five
animation libraries containing **42 distinct frames**. Their six non-flame
bodies retain identical positions, normals, colors and indices. All other
**370 models** remain byte-identical. The six catalogue thumbnails are refreshed.
Import settings are unchanged and imported source hashes are current.

Author with `tools/generate_fire_faceted.py` and `data/art/fire_effects.json`.
The command builds all eleven exports together; `--check` reproduces them in a
temporary directory and checks closed geometry, rooted frames, distinct poses
and each source's existing clearance envelope. The furniture generator calls
the same static-frame builder. The unused raw voxel mesh dump
`data/art/furniture_flames.json` is removed after verification in the external
recovery archive. Retired voxel export commands remain guarded.

Each visible flame has **350 triangles**. Across all stored animation frames,
the total changes from 13,680 to 14,700 triangles; this is storage inventory,
not simultaneously rendered geometry or an FPS measurement. Draw surfaces,
clip count and frame timing are unchanged. Exact before/after export costs and
revisions are in the inventory and `data/art/asset_revisions.json`; the original
conversion reports remain historical evidence.

Verification covers nine distinct fixtures:

- `FireFacetedArtTest`: all imported frames, static/first-frame agreement,
  non-cube normals, opaque surfaces, real timing, fixed roots, self-lit material
  and hide/reveal animation gates. Root comparison allows 0.00005 world units
  for Godot's per-frame AABB compression; source roots must match exactly.
- `FurnitureFacetedArtTest`, `CraftMaterialTest`, `CampfirePlacementTest`,
  `CampfireStoolTest`, `ProfessionCraftingTest`, `WallMountHeightTest` and
  `FireAudioTest`: existing palette, placement, worker, seating, restoration,
  wall-clearance and audio behavior.
- Native `BedroomLightingTest`: the generated underground room remains sealed
  from outside daylight and responds correctly to the installed log torch.

Native review captures cover all six sources from front/back, in day/night,
and every animated frame through the live animation owner. Review scene:
`res://tools/fire_art/review.tscn`, launched with the existing
`tools/furniture_art/RunReview.ps1` and an isolated profile. Full fire/furniture
reproduction and both historical art audits pass.

Evidence: [inventory](concepts/160_faceted_fire/inventory.json),
[validation](concepts/160_faceted_fire/validation.json),
[campfire daylight](concepts/160_faceted_fire/campfire_day.png),
[torch at night](concepts/160_faceted_fire/wall_torch_night.png), and
[campfire frame sheet](concepts/160_faceted_fire/campfire_frames.png).

Restart Play to reload the cached meshes, clips and catalogue textures. Existing
installed lights use the new art automatically; no rebuilding or new world is needed.
