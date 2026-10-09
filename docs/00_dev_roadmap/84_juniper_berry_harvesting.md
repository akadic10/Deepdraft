# 84 — Harvest berries from standing junipers

Implemented 2026-10-09 after the player noticed juniper's Fruit field displayed
N/A despite berries appearing among its felling drops, and approved perennial
harvesting similar to berry shrubs.

## Player behavior

- Mature juniper: **2 berries** each autumn. Ancient juniper: **4 berries** each
  autumn. Saplings are too young. Picking takes **three seconds** at normal speed.
- Select **Harvest berries** in Object explorer, or use **Orders → Harvest
  plants** to click or drag over ripe junipers and shrubs together.
- Picking preserves the tree, its trunk collision and navigation occupancy.
  Berry accents disappear, and Fruit changes to **Picked this season**. The
  berries return next autumn; missed crops do not accumulate or auto-designate.
- Felling yields the existing logs and possible seeds. It no longer grants
  berries, preventing an extra crop after picking.
- Cancel harvest through the inspector, Cancel orders or Undo. Interrupted or
  cancelled work resumes for the same crop. New year's crop starts fresh picking
  work; felling progress is independent and never transferred to harvesting.

These are initial gameplay values. Each juniper stage's JSON `fruit_harvest`
defines `harvest_season`, `work_seconds`, `yield_item` and `yield_count`.
Apple harvest definitions and autumn visuals remain as before; playable apple
picking, automatic orders and brewing are separate future work.

## Ownership and visuals

`SurfaceFloraSpawner` remains the sole tree definition/state owner. One active
tree source can either fell or harvest; an active action must be cancelled before
switching. `HARVEST_TREE` is appended to the existing task enum at priority 50,
using the shared adjacent-work source, bounded nearby-worker comparison and
hand-gathering pose. There is no new global class or autoload.

The changed-tree save record retains action, independent work and the harvested
year/season. Completion stamps the crop before drops, retires the work source,
and places one berry crate on the worker's accessible side of the solid trunk.
Cancellation, save/load, streaming and stale completion calls cannot repeat the
crop. Leaving autumn cancels pending/active picking; work on the next crop resets.

`tools/generate_juniper_picked.py` derives eight GLBs from the authored trees:
mature/ancient, two shape variants and baseline/winter. Only berry colors become
needle colors; tree geometry and color encoding are preserved. The canonical
model resolver selects berry-free art outside autumn or after picking. Harvest
replaces only the visual child, keeping the same collision body and occupancy.
Clock restoration refreshes crop state even when only the year changes.

## Verification

`JuniperHarvestTest` passes headless and in the native renderer, covering:

1. Mature/ancient yields, sapling and season gating, authored durations and
   exclusion of other species without a live picking definition.
2. Nearby worker selection, hand work, pause/speed, interruption, cancellation,
   separate felling progress and restoration of a pending partial harvest.
3. One crop per season, stale callbacks, picked art, unchanged body/occupancy,
   accessible crate placement, streaming/reload and next-year crop renewal.
4. Inspector actions, Harvest plants click/rectangle, mixed shrub/tree receipts,
   View order, Undo and Cancel orders.
5. Felling after harvesting, with normal timber and no extra berry drops.

Native picking/picked captures were visually reviewed. ObjectExplorerTest,
TreeFellingTest, ShrubPilotTest, OrdersShelfTest and SurfaceWorkSelectionTest pass.
SaveManagerRoundTripTest passes manual save/load, autosave and backup recovery,
including picked and partial juniper records. Evidence is under
`tmp/juniper_harvest_review/`.

## Quick manual check

Restart Play. Open **Menu → Clock & weather** and use **+1 Season** to reach autumn. Select
a mature juniper and choose **Harvest berries**, or mark it through Harvest
plants. Expect two berries and a standing tree with **Picked this season**;
ancient trees yield four. Advance through the seasons to verify next autumn's
crop. Save/reload after picking to confirm the crop stays picked.
