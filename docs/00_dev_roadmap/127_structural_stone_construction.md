# 127 — Structural stone construction

Implemented scope, 2026-10-12. Mining and building are separate player actions.
There are no wall coverings and no combined Replace wall command. Additional
wall types and thin partitions are deferred; the first structural block completes
this phase. Wood and stone floors are the next design discussion. Rugs, pelts and
fitted carpets form a separate, later category. None of these floors or coverings
is implemented by this milestone.
This supersedes the unbuilt implementation proposal in milestone 23.

## First implementation

1. Add **Construction → Stone block** to the main dock. Click or drag a footprint,
   with adjustable height, to order full 1×1×1 blocks in cleared air. Preview the
   actual visible cells and stone cost. Allow cancelling unfinished plans.
2. Each completed block consumes **one rough stone**, physically fetched from
   loose goods or storage by a worker. Use the existing planned pickup/delivery,
   interruption, progress supervision and commit guards. One active worker per
   construction area keeps task count proportional to player orders.
3. Use the world's existing plain stone geometry and natural rock shade at the
   target height. No new masonry texture or ore/gem creation. Construction owns
   a separate record of placed blocks, while WorldData holds their real solidity.
4. Completed blocks block movement, support walking and enclose rooms. Plans do
   none of these. Validate air, support, occupants, items and other structures at
   designation and commit. Unsupported planned cells wait for an adjoining solid
   block before delivery starts. Never build into bedrock or displace water.
5. Remove completed blocks with the normal mining tool. Recover one rough stone
   from a constructed block; natural rock keeps its existing loot rules.
6. Save completed block keys, unfinished areas and partial work. Restore terrain
   before furniture and workers; rebuild transient routes and item claims.

## Controls and implementation

- **Construction → Stone block** starts the tool. Click a solid face to build in
  the adjoining air, or drag a rectangle. Alt + wheel sets height (1–8 blocks);
  the footprint is limited to 16×16. The active slice clips both preview and order.
- Ctrl + click a blue plan cancels its entire unfinished area; completed blocks
  remain. Escape finishes the tool. Remove completed blocks through normal mining.
- Click blue cells to inspect their pending area, including while the construction
  tool is active. The shared Object explorer highlights the visible area and shows
  live remaining blocks, stone needed, worker, work status and current block progress.
  **Cancel construction** uses the existing cancellation path, preserving completed
  terrain and unconsumed materials. Picking tests individual planned cells and
  respects foreground objects, terrain and slices. Completion/removal or hiding
  the entire area closes the inspector; inspection does not alter work or saves.
- `BlockRegistry` loads `data/construction/blocks.json`. `ConstructionController`
  owns plan cells and built provenance; `ConstructionWork` reuses the shared
  FETCH_BUILD planner/executor with one lease per area and retained per-cell work.
  It consumes one allowed rough stone after physical delivery and two seconds of
  work at normal speed. Stored goods use the existing withdrawal path.
- The renderer shares the provenance dictionary for face exclusion. Construction
  uses the existing stone colors, terrain lighting material and sliced cube faces.
  Artificial top caps with solid terrain hidden above share the natural overview's
  slice dimming; exposed tops and vertical faces keep their normal color.
  Excavation history remains intact. WorldData receives actual solid blocks after
  materializing their original chunks. Mining these blocks refunds one stone.
- Save section `construction` restores at priority 15, after mining and water and
  before furniture/workers. It holds built cell/key pairs, pending area IDs/cells,
  partial work and the next ID. Claims, routes and assignments rebuild. Carried
  stone follows the existing dwarf cargo restoration contract. Current development
  saves require the new section; older saves have no migration.

## Validation

`ConstructionTest` exercises real worker fetching, unit consumption, multiple
blocks, missing/disallowed supplies, storage withdrawal, cancellation, late
occupancy, retained progress, mining rebuilt cells, navigation and room sealing.
`ConstructionInputTest` uses actual mouse/key events for the dock, drag, single
click, height, slice clipping, side picking, cancellation and Escape. Native
captures cover the menu, plans, stone geometry and controls at 1280×720 and 960×540.
`SaveManagerRoundTripTest` includes built/backfilled stone, an outstanding mining
order on a rebuilt cell and partial construction across real scene replacement,
manual/autosave and backup recovery. Both new tests join the 25-fixture job gate.

Logs and native captures: `tmp/construction_20261012/`.

Verified 2026-10-12: all 25 shared job fixtures have passing results, plus
`OrdersShelfTest`; `verified_results.json` records the latest run for each fixture.
Native menu/control checks pass. A generated seed-1234 mountain review confirms
a 16-block backfilled wall uses the live terrain lighting material and rock palette;
capture `native/world.png` shows that initial result. It did not catch the missing
slice-cap dimming subsequently reported by the player.

**Slice-cap shading fix, 2026-10-12:** constructed tops exposed by hiding solid
terrain above now share the renderer's natural cut-face dimming. Native comparison
of a restored column directly adjoining natural rock reproduces the bright patch
before the fix, then measures identical vertex colors and sampled rendered pixels
at levels 47 and 46 and after returning to 47. Mining away the roof and showing the
full world retain ordinary exposed-top color. Construction and construction-input
regressions pass. Review script, before/after captures and logs:
`tmp/construction_slice_20261012/`. Restart Play/load a current save to apply the
rendering change to existing blocks; rebuilding them is unnecessary.

**Pending-plan inspection, 2026-10-12:** construction/input and Object explorer
regressions pass. Real mouse tests cover active/inactive tool selection, UI input,
terrain occlusion, cancellation, sparse plans, slice hiding and observational
refresh. Real-worker tests cover live block counts, carrier/work progress and
cancellation with carried stone intact. Native layouts pass at 960×540 and
1280×720. Logs: `tmp/construction_inspector_20261012/`; captures:
`tmp/construction_20261012/native/construction_inspector*.png`.

## Deferred wall types

Keep the owner and work-source contracts generic enough to add other full blocks
with their own material requirements. Wood and other materials require separate
design decisions. No floor-finishing or decorative layer is introduced here.

The player confirmed on 2026-10-12 that the existing framework is enough for now.
Material-specific walls (logs/wood and other stone choices) and 1/8-block geometry
can wait. Wall finishes are excluded, including panelling and facing. Any future
thin wall must occupy cleared space rather than cover retained natural terrain.

## Floor design decision

Approved and implemented as a development preview in
[128 — Permanent floors](128_permanent_floor_preview.md), 2026-10-12: mine one
supporting layer and build full plank/stone floor blocks back to the original
walking height. The art uses eight detail voxels per block axis. Normal floor
work awaits Carpenter/Stonemason; blue plans expose DEV Build for testing.
Complete room coverage gives +5 flooring appeal. Production recipes and costs
remain undecided. Rugs, pelts and fitted carpets are a separate future category.
