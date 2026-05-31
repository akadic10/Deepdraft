# 02 - Resource Distribution Plan (Ore, Gem, Cave Soil)

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = keep</span> |
> <span style="color:#d29922;">Yellow = review / move to a more specific plan</span> |
> <span style="color:#f85149;">Red = safe to delete or archive once you are comfortable</span>

## Document Review - 2026-05-31

This plan has mostly been implemented. `WorldGenerator.gd` now has `noise_gem`, `_apply_resource_veins()`, rarest-first resource windows, perimeter suppression, natural exposed-wall suppression, and data-driven `min_y` / `max_y` windows loaded from `data/terrain/block_resources.json`.

Use this document as a review and calibration note, not as the source of truth. The actual source of truth for resource windows is now `data/terrain/block_resources.json`, and the implementation details live in `scripts/systems/WorldGenerator.gd`.

---
## <span style="color:#3fb950;">KEEP - Design Goals</span>

These are still useful guardrails for future tuning.

- <span style="color:#3fb950;"><strong>KEEP:</strong></span> **Depth identity / progression.** Digging deeper yields better rewards.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> **Both dig routes pay off.** Mining into the mountain face yields common industrial metals; tunneling down from valley / lowland floors is the express route to precious metals and gems.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> **Deterministic and seed-stable.** Use noise + position, never unseeded random calls, so streamed chunks reload identically.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> **Cheap.** Resources layer onto rock blocks only; noise is sampled lazily.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> **Bedrock is inviolate.** Nothing overwrites `Y0-3`.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> **Surface stays intact.** The override never replaces the visible surface skin.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> **Natural cliff faces stay readable.** Resource overlays do not paint untouched exposed terrain walls.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> **World-edge perimeter stays concealed.** Metals and gems should not be revealed on the outside slab.

## <span style="color:#3fb950;">KEEP - Vertical Context</span>

This is still useful explanatory context for why the resource bands exist.

| World layer | Y range | What lives there |
|---|---|---|
| Bedrock | 0-3 | Nothing; immovable |
| Foundation `rock11` | 4-11 | Deepest gems: diamond, emerald |
| Lowland band / deep body | 12-19 | Deep gems + gold tail |
| Valley / foothill body | 20-43 | Iron core, silver, mid gems |
| Lower mountain | 44-72 | Iron, copper, coal |
| Upper mountain | 72-115 | Coal, tin, copper |

## <span style="color:#d29922;">REVIEW / MOVE - Resource Bands</span>

<span style="color:#d29922;"><strong>REVIEW / MOVE:</strong></span> These values are implemented in `data/terrain/block_resources.json`. Keep this table only if you want a human-readable tuning summary; otherwise delete it and rely on the JSON.

### <span style="color:#d29922;">REVIEW / MOVE - Metals</span>

| Resource | Band (Y) | Threshold | Role |
|---|---|---|---|
| Coal | 12-90 | 0.72 | Smelting fuel; broad availability |
| Tin | 55-95 | 0.66 | Upper mountain; bronze pair with copper |
| Copper | 45-88 | 0.66 | Upper-mid mountain; early metal |
| Iron | 20-72 | 0.70 | Economic backbone |
| Silver | 16-52 | 0.80 | Precious, mid-deep |
| Gold | 8-36 | 0.84 | Precious, deep |

### <span style="color:#d29922;">REVIEW / MOVE - Gems</span>

| Resource | Band (Y) | Threshold | Role |
|---|---|---|---|
| Jade | 28-58 | 0.80 | Most common gem; mid-depth |
| Amethyst | 20-48 | 0.82 | Mid gem |
| Ruby | 6-22 | 0.88 | Deep gem |
| Sapphire | 6-22 | 0.89 | Deep gem |
| Emerald | 5-16 | 0.90 | Near-bedrock |
| Diamond | 4-12 | 0.90 | Rarest; foundation band just above bedrock |

### <span style="color:#d29922;">REVIEW / MOVE - Cave Soil</span>

| Resource | Band (Y) | Threshold | Role |
|---|---|---|---|
| `soil:cave` | 18-60 | 0.66 | Farmable plump-helmet pockets; utility resource |

<span style="color:#d29922;"><strong>REVIEW:</strong></span> The threshold notes are still useful for calibration, but should eventually live near generation metrics or tuning docs rather than in an implementation plan.

---
## <span style="color:#3fb950;">KEEP - Selection Method</span>

This section describes the current intended algorithm and is worth keeping unless it is fully folded into `43_mining_materials.md`.

For each eligible sub-surface rock block:

1. <span style="color:#3fb950;"><strong>KEEP:</strong></span> Reject bedrock and any block at or above the visible surface.
2. <span style="color:#3fb950;"><strong>KEEP:</strong></span> Reject non-replaceable blocks.
3. <span style="color:#3fb950;"><strong>KEEP:</strong></span> Reject world-edge perimeter columns.
4. <span style="color:#3fb950;"><strong>KEEP:</strong></span> Reject natural exposed wall blocks so untouched cliffs keep their authored strata.
5. <span style="color:#3fb950;"><strong>KEEP:</strong></span> Evaluate gems first, rarest to most common, using `noise_gem`.
6. <span style="color:#3fb950;"><strong>KEEP:</strong></span> Evaluate metals next, rarest to most common, using `noise_ore`.
7. <span style="color:#3fb950;"><strong>KEEP:</strong></span> Evaluate cave soil last, using `noise_soil`.
8. <span style="color:#3fb950;"><strong>KEEP:</strong></span> Otherwise keep the authored rock.

---
## <span style="color:#d29922;">REVIEW - Remaining Decisions</span>

These are the only parts that still need human design judgment or tuning.

1. <span style="color:#d29922;"><strong>REVIEW:</strong></span> **Spatial confinement vs pure depth.** Should gold and gems get horizontal bias under the NW mountain mass, or is pure depth enough?
2. <span style="color:#d29922;"><strong>REVIEW:</strong></span> **Vein size.** Is `noise_ore` frequency `0.02` too sheet-like, or should metal veins become tighter and more followable?
3. <span style="color:#3fb950;"><strong>KEEP / CONFIRMED:</strong></span> **Foundation gems.** Gems may overwrite `rock11` in `Y4-11`; this is implemented and fits the deep payoff.
4. <span style="color:#d29922;"><strong>REVIEW:</strong></span> **Coal availability.** Coal spans `Y12-90`; confirm this stays broad enough for smelting.
5. <span style="color:#d29922;"><strong>REVIEW:</strong></span> **Surface dirt cap.** Grass is protected. Decide whether visible `surface:dirt_*` cap blocks should also always be protected from ore/cave-soil replacement.

---

*Prev: [01_world_gen_plan.md](./01_world_gen_plan.md)*
