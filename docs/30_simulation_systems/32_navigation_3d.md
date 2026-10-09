# 32 — 3D Navigation

## Overview

Dwarves navigate using a **custom 3D A\* (A-Star) grid** tailored to the block world. Godot's built-in NavigationServer is not used — the voxel structure requires custom walkability rules that a navmesh cannot easily express.

## Grid Parameters

| Parameter | Value |
|---|---|
| Block / node size | One terrain block |
| Grid dimensions | Mirrors world grid: 1024 × 128 × 1024 nodes |
| Graph scope | Lazy queries across loaded terrain and deterministic generated terrain |
| Heuristic | Octile X/Z distance + 0.9 × vertical distance |

> **Agent note:** The navigation graph is built lazily per-chunk and cached. Rebuild a chunk's nav nodes only when `WorldData` emits `chunk_changed` for that chunk.

## Walkability Rules

**2026-10-04 mining commit timing:** WorldData's `chunk_dirtied` subscription is
deferred for thread safety. After a main-thread mining void write,
`MiningDesignationController` also calls `NavGrid.refresh_mined_block(block)` to
invalidate that chunk and the chunk below (clearance dependency) immediately.
This lets the worker snap to the new floor and choose its next block in the same
frame without stale floor/path caches. Rebuilds remain lazy; the general deferred
invalidation path is unchanged.

A navigation node at `(x, y, z)` is **walkable** if and only if:

1. The block at `(x, y, z)` is **solid** (the floor to stand on).
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

Placed entities (trees, workshops, boulders, furniture — see `12_world_grid.md`) are **not** stored in the terrain grid. The A* walkability check must therefore query two sources:

```gdscript
func _is_air(pos: Vector3i) -> bool:
    var block_is_air = WorldGrid.get_block(pos) == "deepdraft:air"
    var entity_clear = not PlacedEntityRegistry.occupies(pos)
    return block_is_air and entity_clear
```

All existing walkability rules (the 3-air-layer clearance envelope above every floor node) apply equally to entity-occupied cells. A tree trunk at `(x, y+1, z)` fails the same clearance check as a solid stone block at that position.

**PlacedEntityRegistry.occupies(pos)** returns true if any registered entity's `footprint` contains that grid coordinate. The footprint is registered on spawn and unregistered on death (see `12_world_grid.md`). The nav grid chunk that contains the affected cells must be rebuilt when a placed entity spawns or dies — emit `chunk_changed` for each chunk whose cells are in the entity's footprint.

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
H cost (heuristic) = octile(XZ) + 0.9 × |dy|     (admissible with diagonals)
```

> **Diagonal movement ENABLED (Alen, 2026-06-10 — supersedes the original
> "disabled" rule).** Cardinal-only A* produced L-shaped routes that read wrong in
> play. Rules: diagonals are **flat only** (vertical ±1 steps remain cardinal) and
> **never cut corners** — both cardinal in-between cells must be walkable, so agents
> cannot clip past tree trunks or wall corners. Implemented in `NavGrid._astar()`.

## Path Reuse and Caching

- Completed paths are cached keyed by `(start_block, goal_block)` with a TTL of `5.0` seconds.
- On `chunk_changed`, all cached paths whose nodes overlap the changed chunk are immediately invalidated.
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

---

*Prev: [31_task_system.md](./31_task_system.md) | Next: [33_water_simulation.md](./33_water_simulation.md)*
