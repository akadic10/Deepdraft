# 109 — Loose wet and dry stones

Implemented 2026-10-10. The user requested both natural water stones match the
loose ore shape while keeping water behavior exactly as it is.

**Lifecycle follow-up:** [110 — Permissions and movable stones](110_item_permissions_and_water_stones.md)
supersedes the presentation-only/fixed-feature behavior below. The ore artwork
and initial hydrology remain; stones now have persistent identities, default
Disallow and deliberate Pack/Move/Place work.

## Appearance and placement

`tools/generate_water_stones.py` imports the existing authored ore template,
including the 304-voxel silhouette, body shading and mineral fleck layout. Both
new GLBs have the exact same topology and 1×1×1 world-block size as copper ore.
Only the fleck palette differs: turquoise wet stone and muted gray dry stone.
The generator does not rewrite existing ore assets.

The wet stone rests on an existing dry ledge beside the cave's back pool. The dry
stone rests on the lakebed at the existing intake. They replace the embedded wet
wall patches and the earlier dry terrain cube; neither decorative arch returns.
All supporting rock, bed heights, cave air, roof and channel geometry stay intact.

`WaterStones`, owned by `WaterRenderer`, creates the two configured world models.
They use normal underground lighting, exposed-cave visibility and slicing. The
object inspector identifies visible stones. Fully submerged stones are concealed
by opaque water and cannot be selected through it; a drawdown exposes the model.
Removing supporting terrain settles a model onto solid ground below, consistently
on restoration. There are no inventory entries, haul actions or added colliders.

## Water contract

Both remain fixed natural source/outlet features. Model positions are presentation
metadata, separate from source/drain positions. The spring still supplies up to
2 blocks³/s to the same pool space at the same maximum discharge level. The drain
still removes up to 8 blocks³/s at the same intake, retaining lake surface Y19.
The models do not displace water or alter navigation. This artwork pass retained
layout version 4, with no migration, new save owner or water rebalance. The later
spring-outlet correction in [106](106_spring_caves_and_water_edges.md) uses version 5.

## Verification

- Before/after serialized water snapshots match exactly, both initially and
  after 100 simulation steps (`loose_baseline.log`).
- `DryStoneTest`: three seeds, supported lakebed positions, open intake, retained
  volume and exact water continuation after JSON save/load (`loose_dry.log`).
- `SpringCaveTest --geometry-only`: eight seeds, cave air/roof, ledge support,
  exposed source, connected water route and dry access (`loose_cave.log`).
- `WorldTerrainStartupTest`: all 1,024 tiles after startup, local refresh,
  slicing, actual scene save/reload, leaving slice and full invalidation
  (`loose_terrain.log`).
- Native `LooseWaterStonesPreview.gd`: exact imported ore vertex/normal/index
  arrays, grounding, lighting, submerged and slice visibility, inspection,
  support removal and restoration without duplicates (`loose_native.log`).

Logs and the isolated preview script live in `tmp/water_review/`. The preview
never saves its test-only drawdown or support edit. Captures in `loose_stones/`:
`ore_wet_dry.png` compares copper ore, wet stone and dry stone; `lake_submerged.png`
and `dry_lakebed_exposed.png` verify lake placement. `wet_cave_daylight.png` shows
normal cave darkness through a slice; `wet_cave_lit.png` uses a temporary ordinary
local light to inspect the same model and its shadows. No light is added to the
generated cave by this change. Restart Play to instantiate the new world models.
