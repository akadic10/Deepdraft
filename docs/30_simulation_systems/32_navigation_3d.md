# 32 — 3D Navigation

**Wall-light access (2026-10-12):** Both torches install and uninstall from a
reachable walkable floor beneath/beside the bracket, up to five blocks below
its cell. Normal three-block clearance and a clear reach to the mount are
required. The planner searches all candidate floors; the worker checks actual
reach again at commit. Rungs are not work floors and access ladders are not
created automatically. See [129](../00_dev_roadmap/129_wall_mount_heights.md).

**Bedroom leisure privacy (2026-10-11):** Normal work navigation still passes
through rooms and doors. Bed searches may supply a per-search floor filter to
avoid other colonists' bedrooms and take a public detour. These routes bypass
the shared work-path cache; sleep string pulling honors the same privacy rule.
Idle/ground-rest visitor exits use bounded checked segments. See milestone 122.

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
The 2026-10-12 flooring follow-up also recovers feet embedded in a one-block
raised floor when the standing space above is clear. Idle dwarves with no flat
stroll can take an adjacent one-block step up out of a shallow excavation.
Both use the existing clearance rules; no pathfinding rules were relaxed.
See [115 — Dwarf support recovery](../00_dev_roadmap/115_dwarf_support_recovery.md).

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
cells separately from terrain. Normal walking, hauling and flat smoothing use
these supports with the same three-block clearance and diagonal corner rules.
Closing decks retain physical support but reject new entry, including shortcuts;
occupants may exit to land. Structural changes invalidate cached/progressing
searches and active routes through the shared route revision. Loose goods use
the same deck support for resting and restoring. No water or terrain volume is
modified. See [113 — Log bridges](../00_dev_roadmap/113_log_bridges.md).

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
failure fixed in [174](../00_dev_roadmap/174_mining_furniture_access.md).

For loose goods, explicit route goals are the usable pickup stand cells, not
the item's potentially unwalkable support cell. Validate those actual goals
with live occupancy. Adjacent pickup reach can extend to a support two blocks
above the stand floor; it does not increase step height or reduce three-block
clearance. See [173](../00_dev_roadmap/173_ledge_pickup_and_safe_exports.md).

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
See [86 — Rudimentary ladders](../00_dev_roadmap/86_rudimentary_ladders.md) for
costs, placement constraints, physical construction/recovery and verification.

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
  marking work blocked. The forward limit matches ordinary walking (**6000**),
  with up to 64 extra nodes for a quick sealed-destination check. Relevant
  chunk/occupancy edits and ladder changes invalidate searches; unrelated
  terrain changes preserve progress. See [milestone 88](../00_dev_roadmap/88_ladder_task_reachability.md).
- Mining searches all valid working positions together, requiring an exact
  reached stand. An isolated cliff shelf cannot reject the whole zone. All
  alternatives share the same search bound, and the chosen worker receives
  the proven block, stand and cached route.

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
