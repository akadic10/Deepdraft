# 85 — Plant habitats, spacing and flower relocation

Implemented 2026-10-09, following approval of all seven proposed steps.

## 1. Wild berry habitat

Blueberry, elderberry and wild strawberry now generate at Y4–43, below the
mountain boundary Y44, with roots on grass/dirt/soil. Bare rock is excluded.
Species retain their moisture, patch and tree-spacing rules. Blueberries now
use lowland/foothill ground rather than their former Y36–115 range.

Opening lowlands with the former blueberry density produced about three times
as many bushes. Both blueberry density values were reduced from 0.48 to 0.16;
the final eight-seed sample has 250–340 blueberry bushes, comparable to the
previous sample's 180–337. Terrain, water, trees, boulders and scree are unchanged.

## 2. Cultivation at any height

The altitude limit belongs to wild generation. Players may move mature bushes
or plant cuttings at any elevation, including mountain gardens, on suitable
root soil with level dry ground, clearance and open sky. Flowers use these same
player placement rules. Their existing wild height band remains Y4–70.

## 3. Exclusive planting space

Bushes and flower clumps retain one root/support cell, their current visual
scale, and no navigation collision. Each reserves a 3×3 planting area. Areas
may touch but not overlap: straight-row centers are at least three blocks
apart; two-block diagonal offsets are rejected too. Separate terrain levels
do not collide merely because their X/Z coordinates match.

## 4. All placement paths

The same area geometry applies to deterministic generation, moved or stored
plants, and cuttings from the moment they are planted. Queued destinations also
reserve the whole area immediately. Cancellation releases it; save restoration
reconstructs it from the saved plan. A completing plan ignores only its own
reservation. The cursor and queued ghost show the 3×3 outline; invalid spacing
shows a red outline and an explanation. Dwarves can walk through these areas.

## 5. Move and store flowers

Flower inspectors offer **Move**, **Uproot**, and permanent clearing. Uprooting
takes 1.5 seconds and replanting takes 1.25 seconds, including the immediate
planting animation. **Place → Plants** has cream, heather and gold flower entries
with matching thumbnails. Each uses its own unstackable packed item, one heavy
carry load and one Seeds & cuttings storage slot. Twelve new GLBs preserve the
authored stems/petals over a wrapped root mat in all seasons.

The existing shared uproot/fetch/plant sources retain exact identity, shape,
partial work and same-worker Move continuation. Cancellation/interruption leaves
the physical plant intact. Moving gives no resources; clearing still gives none.
No new global class or autoload was introduced. The internal UPROOT_SHRUB task
and ShrubPlantingComponent now also support flowers, with plant-aware UI labels.

## 6. Future honey connection

`surface_details.json` declares flower bloom seasons: spring and summer.
`SurfaceDetailManager.flower_blooming(id)` and `flowering_clumps(center, radius)`
expose only living, planted blooming clumps at their current locations. Packed,
stored and cleared flowers do not qualify. Moving/reloading never resets bloom;
winter flowers stay dormant. The future hive system must consume these logical
records rather than visible meshes. Hive radius, forage weight, production rates,
pollination and honey gameplay remain deferred decisions.

## 7. Verification and review

- `PlantHabitatTransplantTest`: all bush/flower pairings and diagonals, touching
  areas, young/pending/restored cutting reservations, mountain cultivation,
  separate levels, exact flower variant, same worker, cancellation, interrupted
  carry, seasonal art, container round-trip and replanting, forage and clearing.
- `SurfaceDetailLayoutTest`: eight seeds, every wild berry below Y44 on suitable
  ground, no intersecting bush/flower planting areas, deterministic reversed
  candidate order, fresh-owner restore, unchanged terrain/tree/stone fingerprints.
- Full `SaveManagerRoundTripTest`: manual saves, autosave and backup recovery;
  flower variants in loose, ground-storage, container, pending Move and partial
  uproot states, plus in-flight identity conservation.
- Shrub transplant, cutting growth, same-worker handoff and planting animation
  regressions pass. Seasonal packed art and valid/invalid placement previews were
  rendered and visually reviewed using the native D3D12 renderer.
- Flower/reed clearing, Orders shelf, juniper harvesting, Furniture Place and
  colony inventory regressions pass. All six new thumbnails import successfully;
  the final editor import and changed-file whitespace check report no errors.

Final abundance across seeds 0, 1, 2, 7, 42, 1234, 65535 and 20261007:

| Plant | Minimum | Maximum |
|---|---:|---:|
| Blueberry | 250 | 340 |
| Elderberry | 289 | 390 |
| Wild strawberry | 430 | 532 |
| Flowers | 769 | 936 |

Evidence: `tmp/plant_habitat_review/`, including the layout JSON, test logs,
`packed_seasonal_art.png`, `planting_spacing.png`, and
`planting_spacing_blocked.png`. Generate a fresh world to review the new wild
habitats. **DEV: Next flowers** locates clumps; **Clock & weather** can advance
seasons. Try moving two plants two blocks apart, then three; pack a flower into
storage and replant its matching entry from Place → Plants.
