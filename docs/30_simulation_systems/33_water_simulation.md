# 33 — Water Simulation

## Design Constraints (Non-Negotiable)

These constraints were locked in after deliberate design discussion and must not be revisited without a strong gameplay reason:

- **Gravity-only flow.** Water flows down first, then sideways. It never flows uphill. No pressure simulation.
- **Finite water.** Nothing creates new water. The river and lake placed by worldgen are the total supply for the entire game.
- **No rain, no external water events.** The only water that exists is what worldgen placed.
- **No pressurized pipe networks.** Dwarves can dig channels and ditches; water fills them naturally from the bottom up. That is the full extent of water interaction.
- **No flood events.** Water does not threaten the colony as a disaster mechanic. Dwarves directing water is a construction tool, not a hazard.

> **Precedent:** Oxygen Not Included (Klei Entertainment) ships a near-identical mass-per-cell gravity-driven CA on the CPU. ONI's late-game performance problems come specifically from their pressure simulation and large-scale pipe networks — neither of which exist in DwarfVoxel. The dirty-flag optimisation below addresses ONI's main weakness directly.

---

## Worldgen Water Sources

Two permanent lake bodies are carved and filled during world generation (see `43_mining_materials.md` — Phases 3–4):

**Lowland Lake** — Built from whole 32×32 macro cells in the lowland band (not a circular bowl), with at least one full cell touching the south map edge. Floor sits at Y 11; water fills **Y 12 through Y 18** (`LAKE_WATERLINE = 18`). Every block in `lake_columns` at or below the waterline is a water source block (`mass = 1.0` once the CA is implemented). This is the largest water body on the map and the primary source for irrigation and brewing.

**Mountain Tarn** — A single 32×32 macro-cell body placed on **mountain shelf 1** at a naturally higher elevation. It requires a full 3×3 macro footprint: the water cell in the center, surrounded on all eight sides by mountain shelf 1 or mountain shelf 2 cells. Fixed geometry: floor Y 47, water fills **Y 48 through Y 54** (`TARN_WATERLINE = 54`). It has no surrounding restore pass or plateau ring; invalid placements are skipped rather than repaired. Because the tarn sits well above the lowland lake, a dwarf who digs a channel between them will cause water to flow downhill under the CA rules — producing functional river-like behaviour emergently, without a simulated river.

Source blocks are permanent — they are never consumed by flow and will sustain any channel a dwarf connects to them. Neither body grows, overflows, or changes unless a dwarf digs into it.

> **Implementation status:** Worldgen already places the water **source blocks** for both bodies (see `43_mining_materials.md` Phase 3). The CA tick loop, mass model, and dirty-flag frontier described below are **not yet implemented** — this section is the design spec for that work.

---

## Fluid Mass Model

Each water-containing block stores a `float32` mass value alongside its block ID in `WorldData`:

| Value | Meaning |
|---|---|
| `0.0` | No water — block is air |
| `0.0 – 1.0` | Partial fill — shallow water, flows freely |
| `1.0` | Full block — stable when all neighbours are also full |

Mass never exceeds `1.0`. There is no overpressure, no upward forcing, no pressure value.

---

## Dirty-Flag Architecture

**The simulation never runs on the full world grid.** Only blocks on the *active frontier* — those adjacent to a non-full, non-solid neighbour — are ever simulated. The interior of the lake and river costs zero CPU every tick.

Every block has a boolean `is_active` flag in `WorldData`. The rules for flag management:

- A water block is **activated** when any of its six neighbours changes (terrain removed, water mass changes, block placed).
- A water block is **deactivated** (goes idle) when its mass delta over the last tick is below `SETTLE_THRESHOLD = 0.005` and all four lateral neighbours are at equal mass.
- When a dwarf removes a terrain block adjacent to a water body, all water blocks touching the new air space are immediately activated.

This means a fully settled river or lake has zero active cells and zero simulation cost. The CA only wakes up at the water/air boundary when terrain changes.

---

## CA Tick Rules

The simulation runs at a fixed **10 Hz tick rate** (every 0.1 s) on a background `WorkerThreadPool` thread, independent of render frame rate. Rules execute in strict order per active cell.

### Rule 1 — Gravity (Downward Flow)

Always resolved first, before any lateral spread:

```gdscript
var below := Vector3i(x, y - 1, z)
if WorldData.is_air_or_water(below) and WorldData.get_mass(below) < 1.0:
    var room     := 1.0 - WorldData.get_mass(below)
    var transfer := min(WorldData.get_mass(pos), room)
    WorldData.add_mass(below, transfer)
    WorldData.sub_mass(pos,   transfer)
    activate(below)
```

If the full cell mass moved downward, skip Rules 2 and 3 for this tick.

### Rule 2 — Lateral Spread (Sideways Only If Below Is Full)

Only runs if the block directly below is solid or already full:

```gdscript
var neighbours := [pos + Vector3i(1,0,0), pos + Vector3i(-1,0,0),
                   pos + Vector3i(0,0,1), pos + Vector3i(0,0,-1)]
for nb in neighbours:
    if not WorldData.is_air_or_water(nb):
        continue
    var diff := WorldData.get_mass(pos) - WorldData.get_mass(nb)
    if diff > 0.0:
        var transfer := diff * 0.25   # distribute evenly across up to 4 neighbours
        WorldData.sub_mass(pos, transfer)
        WorldData.add_mass(nb,  transfer)
        activate(nb)
```

### Rule 3 — Settling Check

After Rules 1 and 2, check whether this cell can go idle:

```gdscript
const SETTLE_THRESHOLD := 0.005

if abs(WorldData.get_mass(pos) - prev_mass) < SETTLE_THRESHOLD:
    var all_equal := true
    for nb in lateral_neighbours:
        if abs(WorldData.get_mass(pos) - WorldData.get_mass(nb)) > SETTLE_THRESHOLD:
            all_equal = false
            break
    if all_equal:
        WorldData.set_active(pos, false)   # cell goes idle; wakes on next neighbour change
```

---

## Cascade Behaviour

When water flows from a source block to an open-air column with no floor, the gravity rule handles it naturally — mass drops one block per tick, building up in the pool at the bottom until it stabilises. No separate waterfall system is needed. Each newly filled block in the cascade is activated by Rule 1 and propagates the frontier downward automatically.

---

## Rendering

Blocks with `mass > 0.0` use `water_material.tres`:

- **Top surface:** Animated UV scroll (`uv_offset.y += TIME × FLOW_SPEED`) indicating surface movement.
- **Cascade columns:** Faster vertical UV scroll on blocks whose downward neighbour also contains water mass.
- **Depth tint:** Colour lerps from `SHALLOW_COLOR` → `DEEP_COLOR` as mass approaches `1.0`.

| Shader Uniform | Default | Effect |
|---|---|---|
| `FLOW_SPEED` | 0.4 | UV scroll speed for surface ripple |
| `CASCADE_SPEED` | 1.8 | UV scroll speed for falling columns |
| `SHALLOW_COLOR` | `#56B8E2` | Water colour at mass ≈ 0.1 |
| `DEEP_COLOR` | `#2D849C` | Water colour at mass = 1.0 |

Colour values are taken directly from Stonehearth's water colour map as a validated reference palette.

> **Agent note:** Do not use individual `MeshInstance3D` nodes per water block. Water blocks are rendered as part of the chunk `ArrayMesh` pipeline, the same as terrain. The water shader is applied at the chunk material level for blocks whose ID resolves to `kind = "water"`.

---

*Prev: [32_navigation_3d.md](./32_navigation_3d.md) | Next: [34_temperature.md](./34_temperature.md)*
