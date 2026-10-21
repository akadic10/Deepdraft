# Rudimentary fences, gates and board games

**Recreation revision:** [249 — Solo games and partner search](249_solo_games_and_partner_search.md)
supersedes the two-player-only rules below. One stool supports solo play for +4
happiness, while shared games give +8. Occupied tables recruit within 48 routed
blocks. The historical release and original validation remain below.

**Fence revision:** [201 — Grid-corner fences](201_grid_corner_fences.md)
replaces the 2×1 panel below with individual corner posts and automatic rails.
Gates now span two grid edges with shared end posts. Ground animals respect the
new rails; gate locking and animal permissions remain outside this feature.

**Visual/layout revision:** [200 — Game on a log](200_game_on_a_log.md) replaces
the fitted 3×2 table below with a 3×3 rough log game and closer separate stools.
The original release description and evidence below are historical; crafting
costs and recreation rules still apply.

2026-10-16. User-approved additions to the Rudimentary workbench: log fence,
matching log gate, and a two-player board-game table with separately placed log
stools. This is gameplay work; the construction redesign and parked performance
and water work remain separate.

## Player use

Craft these with a Worker at the crude workbench:

| Design | Cost | Work | Footprint |
| --- | --- | --- | --- |
| Log fence | 1 timber | 10 seconds | 2 × 1 |
| Log gate | 1 timber | 10 seconds | 2 × 1 |
| Board-game table | 2 timber + 1 rough stone | 18 seconds | 3 × 2 |

All use the existing packed-item, hauling, placement, Move, uninstall and wood
material systems. Place fences and gates from Access, and the table from the new
Recreation category. R rotates. The gate swings open near dwarves and uses the
existing passable-door navigation convention. Neither fences nor gates seal a
room. Locking, permissions and animal containment are not part of this addition.

Craft two existing log stools (one timber each). Place them on the table's two
opposite snap guides. The table plus stools occupies a 3 × 6 rectangle, with
clearance around it for broad dwarf heads and reachable access ground. Stools
remain independent objects. Stool positions associated with a game table are
reserved for games; removing the table makes them ordinary seats again. The
table inspector reports stool count and game status.

## Recreation rules

- Two eligible dwarves walk to opposite stools. A table with fewer than two
  installed stools does not start recruiting.
- Idle dwarves may play; a working dwarf may take a break when below baseline
  happiness. Carried cargo, explicit movement, food, sleep, profession-tool
  collection and access recovery keep priority.
- Search is local (24-block route), one candidate and a bounded 500-microsecond
  route slice per scene frame. A candidate gets at most three simulation seconds.
- Travel and partner waiting share a 30-second limit. Once both are seated, a
  game lasts 20 simulation seconds. Pause and speed follow the world clock.
- Completion awards each dwarf **+8 happiness for 12 game hours**. Repeated
  awards refresh one thought; they never stack. An active thought does not block
  another game after the six-hour cooldown (fixed in [203](203_dining_rest_and_game_partners.md)); interrupted
  or unpaired attempts retry after half a game hour.
- Food, sleep, movement, job/profession changes, invalid routes or support,
  furniture removal, dwarf removal and scene teardown release both players and
  claims. Partial games earn no happiness. Work returns through the existing
  cheap release protocol; durable source progress and real materials retain
  their existing owners.

The board and stone counters are part of the furniture. Dwarves alternate short
detached-hand reaches; there is no separate counter inventory or playable board
game UI. Logical feet remain on a legal adjacent floor while visual parts sit on
the stool, matching the existing dining and idle-seat convention.

## Ownership and save compatibility

`FurniturePlacementController` owns a preloaded `BoardGameRecreation` coordinator.
An active game is shared by its two `DwarfAgent` participants. `TaskManager`
excludes participants from assignment and reconciliation until their break ends.
No autoload or global `class_name` was added.

`DwarfMood` saves optional `recreation_memory_hours` and
`recreation_retry_hours`; `SaveSnapshotValidator` accepts them. Older saves
default both to zero. Mid-game saves retain safe floor positions and completed
thoughts, while transient games, routes and seat claims restart from ordinary
availability after load. Furniture uses existing namespaced keys and save owners.

Definitions live in `data/furniture/`, recipes in
`data/workshops/worker_crafting.json`, and balance values in
`data/tasks/task_config.json`. The normal owning registries load them. New art is
reproducible via `tools/generate_rudimentary_furniture.py`; `--check` verifies
geometry and byte-identical output. All wood vertices use the established oak
source palette, preserving runtime timber recolouring; stone counters retain
their own colours. Gate animation reuses named leaf hinges.

## Validation and delivery

The final results pass 15 distinct integration fixtures: RudimentaryRecreation,
WorkerCrafting, WorkerCraftingWood, FurnitureFacetedArt, FurnitureAssignment,
FurnitureMove, FurniturePlace, DwarfIdleBehavior, DwarfFood, DwarfDining,
DwarfInspector, DwarfSupport, JobLifecycle, JobPlanning and SaveManagerRoundTrip.
The expanded recreation fixture covers actual material consumption and delivery,
all rotations, fence/gate navigation and opening, stool association/clearance,
two-player completion, third-player contention, pause/speed, timeout, furniture
and terrain changes, food/sleep, movement/profession changes, safe cargo,
resumption of released work, inspector labels, scene teardown, and JSON mood
restore. Old saves restore missing recreation timers as zero.

Native capture verifies both seated dwarves and alternating hands, the table,
fence and gate. Three actual-model menu thumbnails were generated and inspected.
The geometry generator's byte-reproduction check and the native palette/import
fixture pass, including all four wood appearances. No hand edits to import
metadata were made.

During development the art check caught a 0.01-block table ground offset, which
was corrected. Save fixture expectations now include nonzero recreation timers;
malformed timer cases are rejected. The existing inspector fixture needed its
terrain material cache initialized before camera/audio probes, matching other
isolated fixtures. The recreation fixture was corrected to wait for terrain
invalidation and to use the void-returning item restoration API correctly.
These diagnostics are test/art corrections, not deferred runtime failures.

The actual exported PCK passes 19 native checks: all three definitions, recipes,
models and thumbnails load; the scene owns recreation; a private squad spawns;
and completed happiness and cooldown persist through an actual package save and
reload without restoring stale game claims. `SmokeRudimentary.gd` runs with the
editor executable's `--main-pack` option, because release EXEs ignore `--script`.
Its initial fresh-world assumption was corrected: ordinary dwarf arrival waits
for the player to place a settlement flag, so this isolated test creates its
squad through the existing development entry point. The original player profile
is not used by either package test.

The release export includes all runtime JSON and excludes development content.
The actual release EXE also starts cleanly in its own fresh profile, completes
all 1,024 overview tiles in 8.58 seconds, and exits with code 0 using
`--quit-after 1200`. Final package, native feature and EXE logs contain no engine
or script errors; expected startup and intentional save-recovery warnings remain.
The generated Windows builds and ZIP were subsequently removed from the project
at the user's request. Windows playtests must only be created or updated when
explicitly asked.
Restart Play in the editor; a project reload is unnecessary.

Durable evidence: [validation summary](concepts/rudimentary_recreation_20261016/summary.json),
[native game view](concepts/rudimentary_recreation_20261016/game.png),
[package save/reload](concepts/rudimentary_recreation_20261016/package_result.json).
The evidence directory also retains final compressed fixture logs and release
startup logs. Run the recreation fixture with `-- --capture` for the native view;
the fixture is included in `tools/run_job_reliability.ps1`'s default batch.

## Fullscreen follow-up

At the player's request, `project.godot` now starts in borderless fullscreen
(`window/size/mode=3`). Stretch remains disabled, so rendering follows the native
display size. The existing 2560×1440 dimensions are only a windowed fallback.
Native source and exported-PCK probes both confirm a 7680×2160 window, viewport
and render texture on this display. The fullscreen image was visually reviewed
with the dock, clock and layer controls correctly anchored. Fixed-size native
capture fixtures can use Godot's `--windowed` command-line override.

Restart Play to use fullscreen. Source and package probes used isolated player
profiles. The unsolicited Windows export was removed at the user's request;
future exports require an explicit request. Before removal, the release EXE
started and exited cleanly (code 0), completing all 1,024
overview tiles in 9.92 seconds with no engine or script errors. See the
[fullscreen package measurements](concepts/rudimentary_recreation_20261016/fullscreen_result.json).
