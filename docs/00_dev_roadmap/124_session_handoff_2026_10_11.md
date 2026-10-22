# 124 — Session handoff: starter colony, 2026-10-11

Current starting point, superseding [112 — Water and wildlife](112_session_handoff_2026_10_10.md).
The initial documentation wrap-up followed the storage Contents cleanup. A final
saved-game ladder report then exposed scheduling starvation; that fix and its
new verification are included below.

The subsequent [jobs/dwarves architecture review](125_jobs_and_dwarves_architecture_review.md)
led to the four implemented steps in [126 — Shared lifecycle and recovery](126_job_lifecycle_and_recovery.md):
order/attempt diagnostics, furniture and ladder planning/recovery, shared family
execution/fairness, and a combined fault-test gate. Temporal informed the lifecycle;
the game keeps its existing local source ownership and snapshot model.

## Where we stopped

The starter colony now has log bridges, material-bearing furniture, rudimentary
beds and hearths, assigned bedrooms, sleep comfort and bedroom privacy. Crafting
uses a category browser. Furniture placement follows the set-down animation,
and storage Contents groups quantities by item/material without permission buttons.
Storage, ladder dispatch and the shared job lifecycle are implemented. Next is
player verification after restarting, especially mixed construction/hauling/mining.
Use **Dwarf development → DEV: Job inspector** to inspect waiting orders and
retry orders that need attention.

Restart Play to load the latest scripts. A checkout picking up today's new
`CraftMaterials` autoload/global classes should first use **Project → Reload
Current Project**. Current-version save/load is verified. Older development saves
do not require compatibility work or migrations, by user decision. Use fresh
worlds to judge the new resource progression across the full map.

Implementation and generated assets remain in the shared working tree. This
wrap-up does not commit, discard or reorganize them. Player saves were not
rewritten by the investigation fixtures; reproductions used isolated copies.

## Completed work and decisions

| Area | Current result | Detail |
|---|---|---|
| Stability and assignment | Active walks revalidate changed routes. An unreachable first dwarf no longer blocks a furniture order from other eligible workers. Duck flight queries safely skip freed trees, and felling uses the tree's original scatter-column ownership. | [32 — Navigation](../30_simulation_systems/32_navigation_3d.md), [31 — Tasks](../30_simulation_systems/31_task_system.md), [45 — Wildlife](../40_economy_colony/45_wildlife.md) |
| Shared jobs and recovery | Stable saved order identity, fresh attempt generations, fenced commits, meaningful progress supervision, safe retry/attention, two-leg fetch planning, retained fair searches and a live development inspector. Physical source state stays authoritative. | [126 — Lifecycle/recovery](126_job_lifecycle_and_recovery.md) |
| Ladder extension dispatch | Unfinished mining searches yield across job types while preserving search progress. The saved colony finishes its existing partial ladder from stored sections; access-dependent mining can then proceed. | [88 — Ladder reachability](88_ladder_task_reachability.md) |
| Log bridges | Two blocks wide, clear water spans of 1–5 blocks, equal-height/equal-distance landings. Bank-face and riverbed aiming auto-aligns the preview. Workers can install from either bank, including the saved opposite-bank order. | [113 — Bridges](113_log_bridges.md) |
| Movement recovery | Mining beneath another dwarf settles the unsupported actor and releases stale work/cargo safely. Bogorn's bridge-corner fall was reproduced and fixed by checking shortcuts from actual actor positions. Already submerged actors still need recovery. | [115 — Footing](115_dwarf_support_recovery.md), [32 — Navigation](../30_simulation_systems/32_navigation_3d.md) |
| Crafting menu | Compact recipe icons under category headings, search, Recipes/Orders tabs and one selected-recipe card. Actions remain usable on compact screens. | [114 — Crafting browser](114_crafting_browser.md) |
| Packed furniture | Shared furniture packaging fills an 8×8×8-voxel crate, one world block. Existing shelf/carry presentation remains supported. | [116 — Crates](116_full_furniture_crates.md) |
| Starter log furniture | Log bench, simpler log torch, single-leaf log doors at two/three blocks wide and a double-leaf door at four. Door-side lighting follows the correct room side. Campfire/torches have spatial fire sounds. | [117 — Furniture/audio](117_log_furniture_and_fire_audio.md), [24 — Rendering](../20_player_interface/24_world_rendering.md) |
| Materials and appeal | Pine/oak/juniper/applewood identity, names and wood palettes survive crafting through installation and recovery. Appeal combines design and material; copper/gold profiles prepare future recipes without adding them now. | [118 — Materials](118_crafted_materials_and_appeal.md) |
| Walking and ground sleep | Normal speed is 3.4 blocks/second, with a renewed gait. Dwarves seek walls/trees, sit or recline, breathe, close their eyes and snore quietly. The old sleeping emoji is removed. | [119 — Rest](119_dwarf_walking_and_ground_rest.md) |
| Log beds and readability | A four-log, matching-wood bed uses rough timber and loose hay/leaves. Real bed access, exclusive sleepers, ground fallback and interrupted rest are supported. A faint occlusion silhouette improves readability without changing collision. | [120 — Beds](120_log_beds_and_bedrooms.md) |
| Personal rooms | Bed assignments persist; one assigned bed in a qualifying room makes a personal bedroom, multiple beds make a barracks. Three qualifying sleep hours plus completed rest grants +10 happiness for 24 game hours. | [121 — Ownership](121_personal_bedrooms.md) |
| Lighting and ambience | Campfire/torch light energy is doubled; torches then gained longer range/gentler falloff for small furnished rooms. Waterfalls are 10 dB quieter so work, fire and dwarf sounds remain audible. | [120](120_log_beds_and_bedrooms.md), [121](121_personal_bedrooms.md), [108 — Water sound](108_water_ambience.md) |
| Privacy and warmth | Visitors leave bedrooms before idling; work access remains legal. Rock starts from a sheltered 10°C baseline. Cold/chilly/hot sleep earns negative thoughts. A Worker-crafted hearth supplies practical starter-room heat. | [122 — Comfort/progression](122_bedroom_comfort_and_mining_progression.md) |
| Rudimentary hearth | Low irregular fieldstones, exposed logs/coals and stepped flames replace the polished hearth. Two logs plus four rough stones, 18-second craft, 2×2 footprint and 2400 heat. No iron fittings or fuel upkeep. | [122](122_bedroom_comfort_and_mining_progression.md) |
| Mining progression | Immutable cover from the natural exterior gates resources, including cliff entrances. Coal/copper appear earlier; tin/iron need more cover; valuable gems/metals require substantial cover and descent. Existing inventory is preserved. | [122 — Progression](122_bedroom_comfort_and_mining_progression.md) |
| Placement timing | All 25 ordinary furniture designs install during one 0.65-second set-down immediately on arrival, facing the actual placement contact. Bridges/ladders/plants retain animated work appropriate to their task. | [123 — Placement timing](123_furniture_placement_timing.md) |
| Storage Contents | Alphabetical totals by item and material, including full produce quantities. Physical slot capacity remains separate. Allow/Disallow applies only outside storage; stored goods are available stock, while filters control acceptance/relocation. | [59 — Storage](59_storage_filters.md), [110 — Permissions](110_item_permissions_and_water_stones.md) |

## Contracts to preserve

- Keep one physical owner for each item/quantity/material/instance. Cancelling
  work releases claims and returns intact cargo. Grouped Contents is only a view;
  it does not merge crates, slots or material variants in the world.
- Loose/carried goods and placed water stones retain permissions. Stored goods
  clear the permission flag on deposit/restoration and have no permission action.
  Acceptance filters are separate: rejected stored goods wait for a destination.
- Ordinary placement commits only at the end of the set-down, after final site
  validation. Do not restore the removed generic two-second build wait.
- Bridges provide support only when complete. Either bank may serve the builder;
  closing decks retain occupied support until dwarves can leave safely.
- Priority starts each fresh scheduler pass; an exhausted bucket yields to the
  next type rather than restarting at mining forever. Retain per-type suspended
  frontiers and invalidate them with their normal terrain/policy/route owners.
- Dwarf navigation still requires three blocks of clearance. Visual size,
  sleeping poses and the occlusion silhouette do not relax this rule. Physical
  support is distinct from a navigable exit; settling does not rescue a trapped pit.
- Bedrooms require enclosure, a door, a complete bed and an inside light.
  Assignment controls ownership; a transient sleeper claim controls current use.
  Privacy filters leisure/rest routes, not legitimate work access.
- Sleep thoughts use actual sleeping time, honor pause/speed and persist.
  Thermal discomfort can outweigh the personal-bedroom bonus. Object appeal
  does not yet contribute to room quality or happiness.
- Resource cover uses the original natural exterior, not excavated terrain.
  Mining cannot make deposits appear by changing cover. Preserve bedrock,
  deterministic generation and concealed-resource rendering.

## Verification at handoff

Milestone docs record their own full scope and capture paths. Earlier failed
diagnostics may remain beside final passing runs; do not infer current status
from the first log in a review directory.

- Shared job lifecycle: all **23** fixtures pass in
  `tmp/job_reliability_gate_final/results.json`, including the full current-save
  round trip. Targeted verification of the final route/diagnostic changes is in
  `tmp/job_reliability_verification/`. The mixed world completes seven interrupted
  work families in **222.1 simulated seconds**, with **2,221** ownership checks,
  actual leisure/sleep and a water obstruction. Its observed worst scheduler
  wake is **1.614 ms** against the cooperative 1 ms budget; this is a fixture
  measurement, not a large-colony performance guarantee. The rendered inspector
  capture is `tmp/job_reliability_20261011/job_inspector.png`.
  Source progress and cargo remain authoritative; runtime receipts and the saved
  diagnostic journal do not add crash durability beyond normal game saves.
  All six final targeted fixtures pass, including `SavedLadderJobTest` with explicit
  kit-count/material checks. The original quicksave SHA-256 remains
  `BA79BCD8DCA5ECA3222BA7D6700B77AC18DD349C2F661C4B0004F2732B1D91DF`.
- Final ladder follow-up: the copied quicksave advances 4 → 8 → 12 blocks,
  consumes the two stored pine sections and retains all three paid materials.
  `LadderSchedulingTest` fails before the fix and passes afterward, including
  automatic mining after construction. Ten surrounding ladder, task-selection,
  handoff and save/backup suites pass; see [88](88_ladder_task_reachability.md).
  The crafting-selection fixture now supplies the hearth's four required stones.
  Evidence is in `tmp/ladder_extension_20261011/`; the original quicksave's
  SHA-256 still matches the untouched reproduction input.
- Final storage pass: `ItemPermissionTest` (native), `StorageFilterTest`,
  `CraftingPermissionTest`, `ProduceCrateTest` and `SaveManagerRoundTripTest` pass.
  The Contents fixture checks mixed wood variants, separate produce crates,
  live withdrawal totals, capacity, relocation notes, outside-only actions and
  ground/chest/shelf restoration. Captures at 960×540 and 2560×1440 are in
  `tmp/storage_contents_20261011/`; ten changed scripts have clean LSP diagnostics.
- Latest full save/autosave/backup output is
  `tmp/material_furniture_20261011/SaveManagerRoundTripTest.out`:
  `SAVE_VALIDATION_CASES_OK (169 malformed snapshots)` and
  `SAVE_MANAGER_ROUND_TRIP_OK`. Its intentional damaged-save cases emit expected
  recovery warnings. The player's save directory is not used.
- Placement: 37 actual placements cover all 25 ordinary designs and rotated
  furniture/wall mounts, timing, pause/2×, contact, cargo, cancellation and support
  loss. Headless/native checks and surrounding task-family regressions pass;
  evidence is in `tmp/furniture_placement_animation_20261011/`.
- Hearth: native model/room renders and live animation, collision, heat,
  crafting and save checks are in `tmp/rudimentary_hearth_20261011/`.
  Bedroom/privacy and resource evidence is in `tmp/colony_balance_review_20261011/`:
  eight fresh layouts, 898,961 solid sample cells and the copied player excavation.
  Sparse samples are not whole-world totals or guaranteed local yields.
- The earlier milestone passes cover bridge mouse input/delivery/corners,
  material identity, bed ownership, rest, lighting, audio and crafting UI. See
  113–122 for the corresponding tests and native captures. Broad diagnostic
  counts there apply to those runs, not a new full-project audit today.
- Two test-fixture repairs keep validation meaningful: save checks wait for
  wildlife initialization, and the crate snapshot-only dwarf initializes its
  mood component. Missing-Environment warnings belong to lightweight fixtures.

## Next-session playtest

Reload the final quicksave and watch the unfinished cliff ladder: the remaining
two stored pine sections should be collected and installed automatically. The
isolated reproduction completes the existing route without replacing its order.

1. Restart with the current scripts. Open a stocked zone/container: repeated
   items should appear once with summed quantities; inspect a loose item to
   check Allow/Disallow remains there. Change a filter and watch relocation.
2. Place a bench and wall torch: the worker should lower and install immediately
   on arrival. Build a bridge aimed from the opposite bank; installation should
   use the reachable colony bank and traversal should stay on the deck.
3. Assign beds in sealed, lit rooms. Check personal-bedroom/barracks labels,
   visitor exits, sleep poses and thoughts. Add a hearth and inspect actual
   temperature rather than assuming brightness means warmth.
4. In a fresh world, compare shallow excavation with deeper mining. Review local
   resource frequency across more than one seed before further balancing.
5. Save/load during ordinary activity and confirm furniture, ownership, material
   variants and sleep thoughts continue. Keep audio balance under observation.

## Remaining work and boundaries

**2026-10-12 update:** [Issues 001 and 002](00_open_issues.md) are **CLOSED — presumed
resolved** by Alen's decision. Issue 001 follows the major scheduler/lifecycle
changes; neither original cause was confirmed. Neither is active investigation
work. Reopen only if the player reports the behavior again.

Appeal-driven room scores/moods, craftsmanship quality, pricing and precious-metal
crafting remain future work. Copper/gold profiles are foundations, not craftable
brazier variants. Fuel/ignition upkeep, fall injuries and drowning/rescue behavior
are not implemented. Longer/sloping bridges and dry-chasm construction remain outside
the starter crossing scope.

The earlier handoff's specialist workshop/equipment progression, physical brewery
water jobs, broader flood mechanics and duck breeding/eggs remain deferred. No new
production milestone or automatic follow-up was requested at session end.
