# 32 — 3D Navigation

**Grid-edge fences (2026-10-17, 201):** fence posts and rails are thin barriers in
`PlacedEntityRegistry` (`register_barrier`), kept apart from cell occupancy. These do
not make either adjacent floor tile unwalkable. A* transitions, flat route smoothing
and live dwarf movement sweep a standing body against the barriers
(`barrier_blocks_segment`), including diagonal post corners.
Ground-animal clearance and hops use the same barriers. Gate openings remain
passable under the existing door convention. Creation/removal emits the normal
occupancy invalidation signal; plans have no physical barrier. Terrain cells
remain owned by WorldData, and three-block dwarf clearance is unchanged.

**Wall-light access (2026-10-12, 129):** wall lights (the log torch) install and
uninstall from a reachable walkable floor below the bracket or beside it, never
behind the wall, up to five blocks below its cell (`furniture.wall_reach_up_blocks`
in `task_config.json`; `WallFurnitureMount.work_stands`). Normal three-block
clearance and a clear reach to the mount are required. The planner searches all
candidate floors; the worker checks actual reach again at commit, and losing access
releases the work while keeping the carried item. Rungs are not work floors and
access ladders are not created automatically.

**Bedroom leisure privacy (2026-10-11, 122):** Normal work navigation still passes
through rooms and doors. Bed searches may supply a per-search floor filter to
avoid other colonists' bedrooms and take a public detour. These routes bypass
the shared work-path cache; sleep string pulling honors the same privacy rule.
Idle/ground-rest visitor exits use bounded checked segments (`DwarfPrivacy.leave`):
at most 64 floor cells a tick and 4,096 an attempt, a two-second wait after a failed
attempt, a fresh search after any navigation change, and never a teleport. Privacy
adds no permanent navigation obstacle. Who may use which room is in doc 41.

## Overview

Dwarves navigate using a **custom 3D A\* (A-Star) grid** tailored to the block world. Godot's built-in NavigationServer is not used — the voxel structure requires custom walkability rules that a navmesh cannot easily express.

## Grid Parameters

| Parameter | Value |
|---|---|
| Block / node size | One terrain block |
| Grid dimensions | Mirrors world grid: 1024 × 128 × 1024 nodes |
| Graph scope | Lazy queries across loaded terrain and deterministic generated terrain |
| Heuristic | Maximum of slope-adjusted octile and vertical lower bounds; see cost function below |

> **Agent note:** Walkability is cached lazily per chunk. Terrain `chunk_dirtied`, placed-entity `occupancy_changed`, and live water-level changes invalidate affected chunks and their clearance dependencies. Ladder changes invalidate route caches.

## Walkability Rules

**2026-10-04 mining commit timing:** WorldData's `chunk_dirtied` subscription is
deferred for thread safety. After a main-thread mining void write,
`MiningDesignationController` also calls `NavGrid.refresh_mined_block(block)` to
invalidate that chunk and the chunk below (clearance dependency) immediately.
This lets the worker snap to the new floor and choose its next block in the same
frame without stale floor/path caches. Rebuilds remain lazy; the general deferred
invalidation path is unchanged.

**2026-10-11 support recovery:** DwarfAgent also checks footing before every
unpaused tick, including idle/sleeping actors whose floor another dwarf mined.
It settles onto the first physical solid/deck below and releases stale work and
routes before pathfinding resumes. Physical support is distinct from walkability:
water or blocked headroom must never make a dwarf fall through a solid floor.
Existing rung traversal and ordinary step interpolation remain supported.
Feet embedded in a one-block raised floor (a block built where a dwarf stands, for
instance) recover onto it when the standing space above is clear (2026-10-12). Idle dwarves with no flat
stroll can take an adjacent one-block step up out of a shallow excavation.
Both use the existing clearance rules; no pathfinding rules were relaxed
(doc 115; `DwarfMovement.snap_to_floor` and `lift_from_raised_floor`).

**2026-10-11 bridge-corner movement correction:** the saved colony at seed
471286621 placed Bogorn and Ralrek at floor `(807,41,814)`, just outside a deck
at Y=43. Replaying walks from Bogorn's earlier autosave position reproduced the
same fall. String-pulling approved a line from the current cell centre while the
actor was already near its edge; the actual segment crossed unsupported water.
The support handler then correctly settled the actor onto the submerged riverbed,
where navigation could not find an exit.

`NavGrid.line_walkable_flat_from()` accepts the actual world position. Dwarf
shortcut selection, active-segment validation and leisure walks use it; static
cell-to-cell queries retain `line_walkable_flat()`. Returning to the centre of
the same walkable cell is allowed, so a task interrupt near an edge can safely
recentre instead of repeatedly failing the corner margin. Step/climb rules,
physical support and the existing clearance margin are unchanged.

`BridgeCornerWalkingTest` covers four orientations, both directions, four frame
steps, interruption at the failing fractional position and leisure rejection.
The copied player world completes all 27 reachable test crossings without falls
(four reproduced falls before the correction). NavigationRegressionTest,
DwarfSupportTest, DwarfIdleBehaviorTest, LogBridgeTest, LadderTest and
HaulingAnimationTest also cover surrounding movement. Investigation copies and
traces live in `tmp/bogorn_bridge_20261011/`; player saves are not rewritten by
this movement fix, and already submerged actors still need recovery.

A navigation node at `(x, y, z)` is **walkable** if and only if:

1. The block at `(x, y, z)` is **solid**, or a completed log bridge registers a
   deck support there (the floor to stand on).
2. The block at `(x, y+1, z)` is **air** (dwarf's feet level is clear).
3. The block at `(x, y+2, z)` is **air** (dwarf's mid-body).
4. The block at `(x, y+3, z)` is **air** (dwarf's head).

This constitutes the **3 empty air layers** clearance envelope above every floor cell.

### Clearance Envelope Summary

```
y+3  [ AIR ]   ← head clearance
y+2  [ AIR ]   ← mid-body clearance
y+1  [ AIR ]   ← feet clearance
y    [SOLID]   ← floor node
```

## Entity Obstacles

**Log bridge supports (2026-10-11):** BridgeSystem registers completed deck
cells separately from terrain; a plan never supports anyone. Normal walking, hauling and flat smoothing use
these supports with the same three-block clearance and diagonal corner rules.
Each deck cell also registers a `PlacedEntityRegistry` box, so nothing below can
stand with its body through the deck.
Closing decks retain physical support but reject new entry, including shortcuts;
occupants, idle and sleeping ones too, drop their cargo on the deck and walk to the
nearest landing. Structural changes invalidate cached/progressing
searches and active routes through the shared route revision. Loose goods use
the same deck support for resting and restoring. No water or terrain volume is
modified (doc 113).

A bridge is two blocks wide, with a clear span of 1–5 blocks
(`data/furniture/log_bridge.json` → `bridge`) and one solid landing row at each end.
Both lanes must meet the opposite bank at the same distance and height, so
diagonal, sloping and uneven crossings are rejected. Each gap column needs water
below it when the bridge is placed, and the deck and both landings need three clear
blocks above them (`BridgeSystem.describe`). A worker installs the whole deck from
whichever landing is nearer, so no route across the water is needed. Dismantling
can be cancelled, which reopens the deck without making a kit. When terrain,
water or occupancy later breaks these rules (a gap that dries out excepted), an
unbuilt plan is cancelled; a finished deck closes like a dismantled one, keeps its
support while anyone is on it, then drops its kit at a walkable landing. This is the
starter crossing only: longer spans, sloping landings, piers, stone bridges and
crossings over dry chasms are outside it.

Placed entities (trees, workshops, boulders, furniture — see `12_world_grid.md`) are **not** stored in the terrain grid. The A* walkability check must therefore query two sources:

```gdscript
func _is_air(pos: Vector3i) -> bool:
    var block_is_air = WorldGrid.get_block(pos) == "deepdraft:air"
    var entity_clear = not PlacedEntityRegistry.occupies(pos)
    return block_is_air and entity_clear
```

All existing walkability rules (the 3-air-layer clearance envelope above every floor node) apply equally to entity-occupied cells. A tree trunk at `(x, y+1, z)` fails the same clearance check as a solid stone block at that position.

**PlacedEntityRegistry.occupies(pos)** returns true if any registered entity's occupancy box contains that grid coordinate. Boxes are registered on placement and unregistered on removal (see `12_world_grid.md`). Its `occupancy_changed` signal invalidates the affected nav chunks, extending downward by the three-block clearance height; walkability is recomputed lazily.

Mining maintains a separate cache of workable blocks. Its controller also
listens to occupancy changes, invalidates nearby zone destinations and refreshes
pending lease targets after the footprint updates settle. NavGrid invalidation
alone does not refresh that work cache. This distinction caused the moved-bed
failure fixed in doc 174 (`MiningZoneWork.on_occupancy_changed`).

For loose goods, explicit route goals are the usable pickup stand cells, not
the item's potentially unwalkable support cell: a work probe with explicit stands
(`NavGrid.advance_reachability`, `exact_goals`) validates the stands, while ordinary
walking still needs a navigable destination. Validate those actual goals
with live occupancy. Adjacent pickup reach can extend to a support two blocks
above the stand floor, from a cardinal neighbour only, when the item's space and
the space over the lip are clear in live terrain and placed occupancy
(`StorageComponent.ground_access_cells`, `ledge_reach_clear`); it does not increase
step height or reduce three-block clearance. Haul and fetch contact recheck that
reach before the goods change hands; a blocked reach releases the claim and leaves
the goods where they lie (doc 173).

> **Design note (verified against Stonehearth):** Stonehearth's engine handles this via a `navgrid` system that unifies terrain blocks and entity `region_collision_shape` components into a single walkability query. Our `PlacedEntityRegistry.occupies()` call is the functional equivalent — the nav grid sees one coherent obstacle space, the two data sources just live in separate registries.

---

## Vertical Path Mechanics

### Step-Assist (Upward)

Dwarves can step up a **maximum of 1 block** (0.5 m) without a jump animation:

- The neighbour node at `(x±1 or z±1, y+1)` is considered a valid lateral-plus-up connection if:
  - The destination block at `y+1` is solid.
  - Air clearance at `y+2`, `y+3`, `y+4` is met.
- Step-assist is **not** a jump — no arc, no jump physics. The agent's Y position is smoothly interpolated upward over the horizontal step duration.
- Maximum auto-step height: **0.5 m** (exactly one block). Anything taller requires stairs, ramps, or a ladder structure.

### Step-Down (Downward)

Dwarves step down up to 1 block without special animation, symmetrical to step-up.

### Ladders (live 2026-10-09); stairs and ramps deferred

Player-built wooden ladders register explicit rung supports and vertical edges
in NavGrid. They are scene-owned structures, not terrain block types.
`is_walkable()` retains solid-floor rules; `is_navigable()` additionally accepts
clear installed rungs. Only completed height is registered, so builders extend
tall routes from below without granting early access to the top. Vertical
movement costs reflect the slower climbing speed; ordinary floor smoothing
cannot skip over air. Hauling uses these same paths.

Closing routes allow occupants to leave and workers to dismantle from the top,
while rejecting new through traffic. Interruptions/sleep return an actor to a
floor first. Route changes invalidate path caches and re-arm blocked tasks.

**Sections and cost.** A Worker makes one section from one raw log in six seconds
at a crude workbench (`data/workshops/worker_crafting.json`). Each section installs
exactly four blocks (`data/furniture/crude_ladder.json` → `ladder`, which also holds
the install/removal times and the 0.45 climbing speed), so 4/8/12-block ledges take
1/2/3 sections. An uneven ledge rounds up to whole sections (a five-block ledge gets
an eight-block ladder) with nothing added above the last one; preview,
installation, navigation and recovery all use that height. Placement waits until
every section of the quoted route is in stock.

**Placement.** Ladders are always placed by the player; dwarves never make their own
access. A ladder climbs a continuous terrain cliff from a walkable floor at
its base to a walkable landing; a one-block rise uses step-assist instead. The whole
climbing column, including the part above a rounded-up final section, needs three
air blocks of body clearance and stays reserved while the route exists. Water,
occupied clearance, other ladders, bridges and their plans, furniture and queued
placements, plants or stones within their 3×3 spacing, and storage zones reject
placement with a reason (`LadderSystem.describe`); the upper landing must be inside
the slice.

**Building and recovery.** Workers carry each section to the route, build from the
bottom and climb the finished sections to add the next (two seconds each). Pausing
keeps the paid sections, partial work and the reserved column, and shows only the
installed sections; cancelling a route
with nothing built releases its claim. Dismantling works down from the top at 1.5
seconds per section, waits for climbers to leave, drops each section as a loose item
and can be cancelled. Terrain damage closes a route, waits for its occupants, then
drops only the installed sections. If a lower support is mined away, an occupant
settles down the clear column to the surviving ground; this never registers unpaid
rungs. The `ladders` save section keeps each route's height, installed height,
mode, section materials and partial work (roadmap 86).

## A\* Cost Function

```
G cost (move)     = 1.0   (cardinal)
                  = 1.414 (flat diagonal)
                  = 1.2   (step up +1 block)
                  = 0.9   (step down -1 block — slightly preferred)
For ordinary ladders (climbing cost >= 1.2) or no ladders:
horizontal bound  = octile(XZ) + 0.2 × ascent - 0.1 × descent
vertical bound    = 1.2 × ascent + 0.9 × descent
H cost (heuristic) = max(horizontal bound, vertical bound)
```

A cardinal step can make horizontal and vertical progress for one cost, so
adding full horizontal and vertical costs would overestimate. The horizontal
bound instead adds only the uphill surcharge or subtracts the downhill discount;
the vertical bound handles height differences larger than horizontal distance.
Ladder edges cost `1 / max(0.1, climb_speed_multiplier)`. Faster installed ladders
lower the vertical bound and cap the slope adjustment. If climbing plus a
downhill step becomes cheaper than a flat step, the horizontal cardinal bound
also drops to that combined cost. Both bounds are consistent, as is their maximum,
so closed A* nodes need not be reopened. Multiple-goal and adjacent-goal searches
minimise each bound over an enclosing box of acceptable endpoints: the horizontal
bound uses the lowest goal for its descent discount, while the vertical bound
uses the nearest goal height.

> **Diagonal movement ENABLED (Alen, 2026-06-10 — supersedes the original
> "disabled" rule).** Cardinal-only A* produced L-shaped routes that read wrong in
> play. Rules: diagonals are **flat only** (vertical ±1 steps remain cardinal) and
> **never cut corners** — both cardinal in-between cells must be walkable, so agents
> cannot clip past tree trunks or wall corners. Implemented in `NavGrid._astar()`.

## Path Reuse and Caching

- Completed paths are cached keyed by `(start_block, goal_block)` with a TTL of `5.0` seconds.
- Terrain, occupancy and water changes invalidate cached routes touching affected chunks, including diagonal corner and head-clearance dependencies.
- Active dwarf walks also revalidate their current segment when navigation or
  the target waypoint changes. Flat shortcuts check every sampled floor along
  the segment; steps and ladders retain exact waypoints. A blocked segment
  replans to the same destination, or reports failure through the normal task
  cleanup. Failure clears the old walk before callbacks run, preserving any
  replacement route assigned by a callback. Unrelated changes do not start a
  fresh A* search when the current segment remains clear.
- Task reachability uses **resumable A\* searches**. The configured
  `scheduler.probe_node_cap` (**1200**) limits one slice; the scheduler's time
  budget can yield earlier. An unfinished search resumes next wake without
  marking work blocked: a tall ladder's slower climbing cost makes A* explore wide
  lower ground before it commits to the climb, so a spent slice proves nothing.
  The forward limit matches ordinary walking (**6000**),
  with up to 64 extra nodes for a quick reverse check that rejects a sealed
  destination pocket. That check is skipped while any ladder or bridge is closing,
  because a closing route is one-way (`NavGrid._new_approach_probe`). Reaching the
  forward limit means reachability unknown (`ProbeResult.BUDGET_EXHAUSTED`), not a proven
  missing route; how scheduler searches widen the allowance before backing off is in
  doc 31 ("Search fairness"). A search records
  every chunk it examines, rejected neighbours and clearance cells included, so
  relevant chunk/occupancy edits (even one that opens an approach it rejected) and
  ladder changes invalidate it; unrelated terrain changes preserve progress
  (milestone 88).
- Mining searches all valid working positions together, requiring an exact
  reached stand. An isolated cliff shelf cannot reject the whole zone. All
  alternatives share the same search bound, and the chosen worker receives
  the proven block, stand and cached route. That hint is transient: the zone
  revalidates the block before reserving it, release and cancellation discard it,
  and terrain changes invalidate the proof.

**2026-10-11 regression coverage:** `NavigationRegressionTest.gd` covers obstacles
placed after smoothing, changed terrain, rising water, a blocked later step,
unreachable destinations, replacement routes from failure callbacks, unrelated
edits, and diagonal corner dependencies across chunk boundaries.
It also compares A* costs against zero-heuristic searches on seeded terraces in
both directions and on ordinary/faster ladders. This coverage did not establish
the cause of the original mining-face visual-overlap report in
[issue 002](../00_dev_roadmap/00_open_issues.md). Alen provisionally closed that
report on 2026-10-12; reopen only if the player reports it again.

---

*Prev: [31_task_system.md](./31_task_system.md) | Next: [33_water_simulation.md](./33_water_simulation.md)*
