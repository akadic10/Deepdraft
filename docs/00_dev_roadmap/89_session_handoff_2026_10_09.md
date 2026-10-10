# 89 — Session handoff: 2026-10-09

Historical handoff, superseded by [103 — Evening handoff](103_session_handoff_2026_10_09_evening.md).
This record originally superseded [65 — Previous handoff](65_session_handoff_2026_10_07.md).
This session progressed from seeded world generation through caves, ore fields,
surface details, plant relocation and growth, worker assignment, and crafted
ladders. The approved implementation passes are complete. The most recent player
confirmation is: “this is working now and I was finally able to make a staircase
with mining.” This confirms the repaired ladder access and mined-staircase workflow
in play; it does not close unrelated older mining reports.

This wrap-up changes documentation only. No next feature has been selected.

## Completed work and current rules

| Area | Current behavior | Detailed record |
|---|---|---|
| World layout | Seeded geography replaces fixed compass regions. Every accepted world retains substantial mountains and at least a 32×32 summit at Y115. Cliffs and shores, including underwater edges, are rough. No prepared settlement plateau or tree exclusion; players choose and clear their site. | [66 — Layout](66_seeded_world_layout.md), [67 — Diagnostics](67_world_generation_diagnostics.md) |
| Caves | Connected dry underground chambers provide existing exposed resources and occasional soil. Normal mining discovers them; ordinary slicing conceals undiscovered caves. DEV Cave explorer locates/previews them without discovery or excavation. | [68 — Caves](68_caves_and_discovery.md) |
| Resources | Smaller independent metal fields and broader coal replace the shared ore field; tin/gem precedence corrections are included. Resource placement remains depth-based. | [69 — Audit](69_resource_distribution_review.md), [70 — Prototypes](70_ore_vein_prototypes.md), [71 — Integration](71_independent_ore_fields.md) |
| Surface details | Boulders, gatherable scree, seasonal berry shrubs, flowers and lakeside reeds are live. Clear stones covers boulders/scree; Harvest plants and Clear plants handle the relevant vegetation. Cleared details remain removed. | [72 — Plan](72_surface_details_plan.md), milestones 73–77, [78 — Combined review](78_surface_detail_review.md) |
| Plant lifecycle | Clearing each berry shrub yields one cutting at 100%, configured in JSON. Cuttings can be planted and grown. Mature shrubs and flowers support Move, Uproot, storage and replanting with exact identity/season/crop state preserved. Moving grants no berries or cutting. | [79 — Shrub relocation](79_shrub_transplanting.md), [80 — Cutting growth](80_shrub_cutting_growth.md), [85 — Habitats and flowers](85_plant_habitats_spacing_flowers.md) |
| Habitat and space | Wild berry shrubs grow on grass/dirt/soil below Y44, never bare mountain rock. Players may cultivate suitable soil at any elevation. Shrubs, flowers, cuttings and queued planting destinations reserve nonoverlapping 3×3 areas while remaining walkable. | [85 — Habitats and flowers](85_plant_habitats_spacing_flowers.md) |
| Plant work | Eligible nearby idle dwarves compete for reachable surface work. An available uprooter continues a Move through collection/replanting. Mature planting starts its animation immediately and takes 1.25 seconds. Junipers now have an autumn berry harvest from standing mature/ancient trees. | [81 — Selection](81_surface_worker_selection.md), [82 — Handoff](82_shrub_move_handoff.md), [83 — Animation](83_shrub_planting_animation.md), [84 — Juniper](84_juniper_berry_harvesting.md) |
| Placement and hauling | Owned packed furniture remains available while reserved for storage or carried. Confirmed placement can supersede storage hauling, preserving the item and continuing with its carrier where supported. Plants and ladder sections share this availability path. | [87 — Placement priority](87_placement_over_storage_hauling.md) |
| Ladders and mining | Workers craft sections at a crude workbench and install from below. Each section is exactly four blocks: 8/12-block ledges need 2/3 sections, with no extra top cap. Uneven ledges round up. Installed sections provide real climbing/hauling access and can be recovered. Mining now finds reachable work positions above ladders without DEV Walk. | [86 — Ladders](86_rudimentary_ladders.md), [88 — Reachability](88_ladder_task_reachability.md) |

The practical access loop is raw timber → crude workbench → ladder sections →
temporary access → mine a permanent staircase. The player confirmed reaching the
staircase stage. Section recovery is implemented and automated-tested; this last
player message did not separately report dismantling after the staircase.

## Outstanding and deferred work

1. **Optional ladder planning improvement:** allow a valid blueprint before all
   sections exist, install what is available, and wait for the rest. Distinguish
   material shortages from invalid geometry in the preview. This was proposed,
   not implemented. Placement still requires the full quoted section count;
   required/available/missing counts and stationary-hover stock refresh are fixed.
2. **Required future honey connection:** consume the planted, living, seasonally
   blooming flower records already exposed by the detail manager. Packed/stored
   plants do not count. Hive radius, forage weights, production and pollination
   remain design work. See [85](85_plant_habitats_spacing_flowers.md) and
   [42 — Flower forage](../40_economy_colony/42_farming_brewing.md#required-future-connection-wildflower-forage).
3. **Cave playtesting and content:** the player deferred further manual discovery,
   access and multi-seed shape checks. Existing automated/native checks remain
   valid evidence; deferred manual checks are not marked passed. Pools, fungi,
   ruins, hazards, deeper networks and progressive discovery remain proposals
   recorded in [68](68_caves_and_discovery.md).
4. **Resource and economy tuning:** review practical access costs, abundance and
   temporary testing drop values when the economy is ready. Horizontal resource
   bias remains deferred; the current rule is depth-based placement. See [71](71_independent_ore_fields.md).
5. **Season-transition performance:** the surface-detail queue optimization is
   complete, but broader tree/material/world rebuild spikes remain. Profile them
   before expanding population or promising smooth transitions; current density
   was retained after the initial review. See [78](78_surface_detail_review.md).
6. **Older defects:** [Issue 001](00_open_issues.md) remains open pending its original
   mining-face reproduction. The new resumable searches address its old probe-cap
   hypothesis but do not prove that report resolved. Issue 002, dwarf overlap with
   unmined terrain, remains parked; its lighting symptom was fixed separately.

Dedicated stair/ramp construction tools, other access materials, farming/food
processing, brewing and reed uses remain later gameplay milestones. A staircase
carved through ordinary mining is already possible; do not confuse it with an
unimplemented dedicated stairs tool.

## Verification and evidence

Milestone documents 66–88 record their respective automated tests, native
captures and player feedback. These are checks from each implementation pass,
not a claim that every suite was rerun after the last edit.

The final ladder-height correction passed:

- `LadderTest`, headless and native: crafting, installation, four-block mesh and
  preview heights, uneven landings, clearance, partial work, loaded climbing,
  interruption, removal/recovery and reuse.
- `LadderMiningTest`: automatic mining across two offset tall ladders, bounded
  resumable searches and invalidation/missing-route cases.
- `MiningLedgeAccessTest`, native: the reported seed's real 8-block ladder and
  32-block mining zone complete without DEV Walk.
- `SaveManagerRoundTripTest`: normal save, autosave and backup recovery.

Logs: `tmp/ladder_sections_review/`. Native captures:
`tmp/ladder_review/loaded_climb.png` and
`tmp/ladder_mining_live/seeded_mining.png`.
Tests used isolated APPDATA/LOCALAPPDATA profiles. The final named runs passed
without script errors; existing fixture sky warnings remain. The player then
confirmed the ladder correction and successful staircase excavation.

This documentation-only wrap-up checks links and whitespace; no gameplay suite
is rerun for prose changes.

## Next-session entry

Read this handoff and the milestone/system documents for the chosen work.
Preserve JSON ownership, physical item conservation on interruption, deterministic
generation, three-block navigation clearance, bedrock and cave concealment rules.
Use isolated test profiles and do not stop the player's running editor/game.

The shared workspace contains the session's implementation, assets, data and
documentation as uncommitted changes, including new files. No commit, reset or
cleanup was requested for this wrap-up. Choose the next milestone with the player;
do not automatically treat deferred proposals as authorized implementation.
