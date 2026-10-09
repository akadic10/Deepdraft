# 79 — Move and uproot mature shrubs

Status: **implemented 2026-10-08.** The user chose mature-plant relocation before
growing new plants from recovered cuttings, following the Stonehearth comparison.

## Player controls

Select a blueberry, elderberry or wild-strawberry bush in Object explorer:

- **Harvest:** collect its available seasonal fruit and keep the bush.
- **Move:** choose a destination with the normal placement preview; a worker
  uproots the exact bush, carries it there and replants it mature. Nothing is
  uprooted until the destination is confirmed. Escape cancels the preview.
- **Uproot:** lift the whole bush as a portable item for storage or later use.
  Replant it through **Place → Plants**. Enable **Show all designs** to see species
  with no available whole shrubs. Cuttings do not count as whole shrubs.
- **Clear plant:** permanently remove it for the existing guaranteed cutting.

Both Move and Uproot preserve the plant's crop cycle. A picked bush stays picked
for that season, and a ripe bush retains its unharvested crop. Neither action
grants fruit or a cutting. Normal calendar seasons still govern future crops;
storage does not freeze the calendar or grant an extra harvest.

Uprooting takes **3 seconds** and replanting takes **1.25 seconds**, configured per
species in its existing JSON `wild.transplant` section. Replanting animates from
arrival through completion, with no additional set-down delay; see
[83 — Shrub planting animation](83_shrub_planting_animation.md).
Carrying uses the existing worker
pipeline. A packed shrub is one unstackable heavy item, occupies the full
4-point carrying budget and one storage slot, and uses **Seeds & cuttings** filters.
Root-wrapped seasonal art distinguishes it from both cuttings and planted bushes.

## Destinations and cancellation

Player placement checks a flat, dry, clear 3×3 envelope around the plant's single
support tile, with at least three blocks of headroom and open sky above its center.
Blueberries accept rock, dirt or grass; elderberries and strawberries accept dirt
or grass. These ground kinds are in JSON. Bedrock Y0, water, occupied ground,
other nearby details, conflicting placement plans and unsupported sites are rejected.
World-generation habitat noise, mountain height bands and wild spacing do not
restrict player placement. Mature shrubs remain nonblocking and have no colliders.

Cancelling a Move before lifting leaves the original bush and its partial uproot
work. Cancelling after lifting leaves the intact packed shrub available for storage
or later placement. Interrupting a worker drops carried goods at their feet and
keeps unfinished planting work on the destination plan. A Move's exact plant stays
reserved for that plan, so ordinary hauling or another planting request cannot
take it after an interruption. Cancelling the plan releases that reservation.
If the destination becomes unsuitable, the worker releases the intact shrub;
no item is consumed at an invalid site.

## Ownership and save contract

**Worker continuation follow-up:** [82 — Shrub Move handoff](82_shrub_move_handoff.md)
keeps an available uprooter at the pickup on the carrying/replanting stage, with
nearby replacement selection after sleep, interruption or higher-priority work.
This preference is transient; plant identity and partial work remain persistent.

`SurfaceDetailRegistry` alone reads transplant definitions and supplies a small
adapter to the shared Place catalog/controller. `SurfaceDetailManager` retains
the original generated identity and generated origin while saving the current
origin/yaw, packed state, crop cycle and independent action progress. Uprooting
marks the original location removed before creating the physical item. Replanting
reactivates the same identity at the new location; reload cannot resurrect its
original bush or duplicate its fruit.

Whole-plant goods use `base:resources:plant:*_bush` item keys and an `instance_id`
pointing to that saved plant. Loose items, carried goods, ground stockpiles,
visible shelves and opaque containers preserve this optional identity field.
Container counts remain aggregate inventory, with identified slot entries saved
alongside them. Ordinary stackable goods keep their existing behavior.

`UPROOT_SHRUB` is an appended priority-50 adjacent hand-work task. Destination
plans use `ShrubPlantingComponent`, a small specialization of the shared
`FurnitureGhostComponent` fetch/carry contract, at existing `FETCH_BUILD` priority
45. Plan saves add `plant_work` and optional `plant_id`; leases, routes and claims
remain transient. Claims are rebuilt before loose/carried items restore. Saving
does not release workers; loading safely restores in-flight cargo at their feet.
Planted shrubs return to the detail owner, not installed-furniture storage.

## Seasonal art

`tools/generate_uprooted_shrubs.py` reuses the authored shrub voxels and adds a
wrapped root ball on the same baked 0.125 grid. Sixteen packed GLBs cover twelve
seasonal models and four picked variants at
`assets/models/flora/bushes/{species}/{species}_packed_{season}[_picked].glb`.
Loose, carried and shelf-displayed shrubs update with the season; opaque storage
resolves the current variant when withdrawn. Shelf refitting uses its original
anchor so repeated seasonal changes cannot drift or overflow the display slot.
Place previews use the current mature seasonal model; the actual replanted bush
uses its preserved crop state. Catalog thumbnails show each species in summer.

## Verification and manual check

`ShrubTransplantTest` passes in the native renderer with actual inspector Move
and Place → Plants tile clicks. The worker tests cover harvest-before-Move,
partial uproot cancellation/reissue, exact physical carrying, interruption and
claim protection, persistent planting work, original-location removal, ripe/picked
preservation, stockpile/chest hauling and restoration, storage removal, invalidated
destinations, seasonal shelf refitting and fresh-owner restore.

`SaveManagerRoundTripTest` passes manual save, autosave and corrupt-primary backup
recovery with moved plants, packed shrubs in both storage forms, loose packed
items, unfinished Move/planting orders and partial uprooting. Its in-flight save
case includes an identified carried shrub and verifies identity/crop preservation.
The complete saved owner sections match after reload; terrain fingerprints remain
unchanged. `ShrubPilotTest`, `ProduceCrateTest`, `StorageFilterTest`,
`FurniturePlaceTest` and `ColonyInventoryTest` also pass.

Native UI captures (`transplanted.png`, `place_plants.png`) and the seasonal packed
art contact sheet (`packed_art.png`) were visually inspected. Evidence is under
`tmp/transplant_review/`. Native execution:

```powershell
$env:APPDATA = 'P:\Deepdraft\tmp\transplant_review\appdata\native'
$env:LOCALAPPDATA = 'P:\Deepdraft\tmp\transplant_review\localappdata\native'
& 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --path P:\Deepdraft --script res://scripts/tests/ShrubTransplantTest.gd -- --capture
```

For a quick playtest, use **Menu → Development → DEV: Next blueberry**, select
**Move**, and click nearby open ground. Watch the bush move without leaving a
duplicate. Then **Uproot** it, allow storage hauling, and use **Place → Plants** to
replant it. Harvesting a ripe bush before either action should leave the replanted
bush picked. Cancel a move while the worker carries it to check intact recovery.

Growing new shrubs from cuttings subsequently shipped in
[80 — Shrub cutting growth](80_shrub_cutting_growth.md). Farm plots, food processing
and the required wildflower/honey connection remain later work. This milestone changes neither
world-generation density nor wild plant locations.
