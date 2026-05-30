# 32 — 3D Navigation

## Overview

Dwarves navigate using a **custom 3D A\* (A-Star) grid** tailored to the block world. Godot's built-in NavigationServer is not used — the voxel structure requires custom walkability rules that a navmesh cannot easily express.

## Grid Parameters

| Parameter | Value |
|---|---|
| Block / node size | 0.5 m |
| Grid dimensions | Mirrors world grid: 512 × 128 × 512 nodes |
| Graph scope | Only chunks within active range are populated |
| Heuristic | 3D Manhattan distance (scaled by 0.5 m) |

> **Agent note:** The navigation graph is built lazily per-chunk and cached. Rebuild a chunk's nav nodes only when `WorldData` emits `chunk_changed` for that chunk.

## Walkability Rules

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

### Ladders / Ramps (Future)

Multi-level vertical traversal will be implemented via designated block types (`"dwarf:ladder"`, `"dwarf:ramp_stone"`). These nodes have special connection rules that allow `y` changes of more than 1 per step. Details TBD in a future update to this document.

## A\* Cost Function

```
G cost (move)     = 1.0  (cardinal)
                  = 1.414 (diagonal, if enabled — currently disabled)
                  = 1.2  (step up +1 block)
                  = 0.9  (step down -1 block — slightly preferred)
H cost (heuristic) = Manhattan3D(current, goal) × 0.5
```

Diagonal movement is currently **disabled** to keep pathfinding aligned with the block face grid.

## Path Reuse and Caching

- Completed paths are cached keyed by `(start_block, goal_block)` with a TTL of `5.0` seconds.
- On `chunk_changed`, all cached paths whose nodes overlap the changed chunk are immediately invalidated.
- The Task System's reachability probe uses a **maximum 200-node A\* expansion** for speed; if no path is found within that budget the task is flagged BLOCKED.

---

*Prev: [31_task_system.md](./31_task_system.md) | Next: [33_water_simulation.md](./33_water_simulation.md)*
