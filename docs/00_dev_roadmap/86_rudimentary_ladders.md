# 86 — Rudimentary ladders

Implemented 2026-10-09 after approval of all six ladder steps.

## Player workflow

1. Use **Craft → Crude workbench** to make the first bench from one raw log;
   place it through the existing Place menu.
2. At that bench, any Worker can craft **Ladder section**. One raw log produces
   one section in six seconds. The existing timber selector accepts other log
   species. No promotion, planks, metal or rope is required.
3. Choose **Place → Access → Rough wooden ladder**. Aim at a cliff face, its
   upper edge, or the floor beside its base. Wall hits choose the facing;
   **R** rotates ground/edge placement. **Esc** leaves the tool.
4. The preview shows the complete route and its cost before placement. Each
   section installs exactly four blocks: 4/8/12 blocks cost 1/2/3 sections.
   Uneven ledges round up to a complete section (a five-block ledge uses an
   eight-block ladder). Preview, installation, navigation and recovery use
   that same height. There is no extra two-block piece above the last section.
5. Workers physically collect and carry each section. They build from the
   bottom and climb finished sections to extend the route. Installation takes
   two seconds per section. Ordinary traversal to the upper landing becomes
   possible only when enough sections have actually been installed.
6. Select the ladder to pause/resume construction or **Dismantle and recover
   sections**. Dismantling takes 1.5 seconds per section, proceeding downward.
   Recovered sections become physical loose items, available for storage/reuse.

Pausing an extension retains its paid supports, partial work and reserved
column; resuming waits for available sections. Cancelling a wholly unbuilt
plan releases its item claims. Dismantling can also be cancelled. Partial
construction and removal progress, section counts and route identity are saved.

## Placement and movement

- This version serves continuous terrain cliff faces with a clear lower floor
  and an accessible upper landing. One-block steps retain normal auto-step.
- The entire climbing column needs three air blocks of body clearance. Water,
  occupied clearance, overlapping ladders/furniture/plans, plant spacing and
  storage zones reject placement with an explanation. Raise slicing to show
  the upper landing before placing a new route.
- Selection outlines match the visible planned/installed height. The reserved
  climbing column separately retains three blocks of headroom, including above
  a rounded-up final section. A paused route shows only its installed sections.
- Placement currently requires all sections for the quoted route. Shortage
  hints show required, available and missing counts; stock changes refresh
  the hover preview without needing to move the pointer. Planning a route
  before all sections exist remains a proposed follow-up.
- Rungs are explicit graph supports in `NavGrid`; no terrain blocks are added,
  and `is_walkable()` still requires a real solid floor. `is_navigable()` also
  accepts registered, clear rungs. Vertical edges follow installed rungs;
  cardinal exits lead to actual floors. Flat path smoothing never cuts across
  unsupported air. Route changes invalidate cached paths and wake blocked work.
- Dwarves face the wall and alternate hands/feet while climbing at 45% of
  walking speed. Existing heavy-carry slowdown still applies. Cargo is displayed
  against the back so both hands can use the ladder. Haulers use the same route.
- An interrupted or tired worker leaves the ladder before becoming available
  or sleeping. Restored actors saved on a rung likewise descend safely before
  taking fresh work; saved cargo uses the existing physical drop/settling path.
- Dismantling closes the route to new through traffic, keeps escape and
  maintenance paths, and waits for other occupants before removing a section.
  Terrain support damage closes the route and recovers only installed sections
  after evacuation. A removed lower support lets an occupant settle down the
  clear column to surviving ground; this never adds unpaid navigation rungs.

## Art and ownership

`tools/generate_crude_ladder.py` exports one four-block section and a compact
bundle of rails/rungs for carrying. Split wooden rails, evenly spaced chunky
rungs, wooden pegs and axe scars use eight voxels per block with baked 0.125
scale. Full sections end at their quoted height, with no appended handhold
cap. Installed meshes use vertex colours and existing underground lighting.

`data/furniture/crude_ladder.json` owns module height, installed models,
installation/removal durations and climbing speed. FurniturePlacementController
remains the sole furniture-definition loader. CraftingManager owns its recipe;
ItemDropManager owns the packed item definition. Place has an Access category
and a rendered model thumbnail. The Craft recipe list now scrolls so the extra
recipe does not force its window over the dock at 960×540.

The scene-owned `LadderSystem` is a child of FurniturePlacementController.
`LadderBuildComponent` and `LadderRemovalComponent` reuse existing fetch/carry
and uninstall tasks. No new global class or autoload was added. The `ladders`
save section restores after furniture and before loose items/dwarves, using
namespaced definition keys and real installed heights.

## Verification

- `LadderTest`: actual raw timber → bench → sections → Place → installation,
  12-block extension from below, unfinished-route reachability, stock cost and
  cancellation, clearance rejection, partial restoration, interrupted loaded
  climbing, pause, real stone delivery into elevated storage, reverse routing,
  occupied-route dismantling, section reuse, sleep evacuation and support loss.
- Four-block-section regression coverage checks 4/8/12-block mesh and preview
  bounds, actual exits on 5/9-block uneven ledges, clearance above rounded
  sections, no unpaid rungs, and selection bounds on partial/finished ladders.
- Native D3D12 execution of that test: `tmp/ladder_review/loaded_climb.png` shows
  a loaded worker on the wooden route. Native and headless logs are in the
  same review folder.
- The section-height revision was also checked in the native reported-seed
  mining fixture (8-block ladder) and full save/backup round trips. Logs are
  in `tmp/ladder_sections_review`; native mining capture remains
  `tmp/ladder_mining_live/seeded_mining.png`.
- `SaveManagerRoundTripTest`: includes two natural cliff sites, one partially
  built and one queued for dismantling, both with partial work. Full owner
  snapshots survive autosave, normal loading and backup recovery.
- Related regression suites: WorkerCraftingTest, HaulingAnimationTest,
  ShrubPlantingAnimationTest, PlantHabitatTransplantTest, FurniturePlaceTest and
  ColonyInventoryTest. Godot import/parse and `git diff --check` are also checked.

**Player acceptance, 2026-10-09:** after the four-block section/top-cap correction,
the player confirmed the ladders work and successfully made a staircase through
mining. This validates temporary ladder access leading to permanent excavated
access. It does not imply a dedicated staircase construction tool was added.

Dedicated stair/ramp construction tools, alternative ladder materials and
scaffolding remain future work. Ladders are always player-designated; dwarves
do not create free routes. See [89 — Session handoff](89_session_handoff_2026_10_09.md)
for the outstanding proposals and deferred work.
