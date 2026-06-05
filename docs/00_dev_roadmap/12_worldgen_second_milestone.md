# 12 - Worldgen Second Milestone (Backlog)

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = keep</span> |
> <span style="color:#d29922;">Yellow = decision needed before building</span> |
> <span style="color:#f85149;">Red = explicitly out of scope for this pass</span>

Status: backlog, created 2026-06-05 from the live remainders of `01_world_gen_plan.md` and
`02_resource_distribution_plan.md` (both retired — their first milestones shipped; permanent
rules live in `43_mining_materials.md` *World Design Intent / World Generation Pipeline /
Resource Distribution* and `24_world_rendering.md` *Terrain Render Modes / Debug Overlay &
Block Inspector*; resource bands/thresholds live in `data/terrain/block_resources.json`).

Nothing here is in progress. Each item becomes its own focused plan (or a phase in one)
when work begins.

---

## 1. <span style="color:#d29922;">Trade road / path mask through the valley</span>

Not implemented — `WorldGenerator.gd` has no road logic; the valley corridor is only
"road-ready" terrain today. The trade road is core to the design: the Dig → Brew → Trade
loop sells along it (`11_overview.md`), the valley domain reserves a corridor for it
(`12_world_grid.md`, `43_mining_materials.md`), and all visitors enter on it
(`51_visitors.md`). Likely shape: a deterministic mask over valley columns connecting a
map edge to the settlement plain, surfaced as packed dirt; un-minable threshold per the
design pillar.

Open question, decide with implementation:

- Should the road be visible immediately at worldgen as packed dirt, or appear only once
  caravans start using it?

## 2. <span style="color:#3fb950;">Scatter maps for flora and boulders</span>

Worldgen does not spawn flora yet (tree/bush assets already exist under
`assets/models/flora/`). Worldgen should eventually produce placement maps that make
spawning easy: dense edge forest (the border foliage belt, `24_world_rendering.md`),
valley trees, mountain pines/junipers, boulders, scree, flowers/shrubs, road-side
detail, and lake-bank reeds.

Placement rules (already normative elsewhere — pointers, not duplicates):

- Props are **placed entities**, never terrain blocks (`12_world_grid.md` §Placed World
  Entities).
- Plant visual overhangs add no collision (Hard Rule 5, `42_farming_brewing.md`).
- Large props need local flatness checks.
- Determinism: scatter maps derive from `world_seed` (Hard Rule 8).

## 3. <span style="color:#d29922;">Open design questions</span>

- **Macro composition rotation:** should the mountain always be northwest, or should
  future seeds rotate/mirror the macro layout? (Today: fixed NW per the North Star table
  in `43_mining_materials.md`.)
- **Snow / cold high-altitude stone:** should a future pass add snow caps or cold stone
  variants above some Y? (Weather snow exists, `data/weather/snow.json`; terrain snow
  does not. Touches the seasonal surface-palette system.)
- **Settlement candidates:** worldgen already computes 20×20-flat settlement-candidate
  metrics (debug overlay shows the count). Promote to a real UI hint at embark, or keep
  debug-only?

## 4. <span style="color:#d29922;">Resource calibration (from retired doc 02)</span>

Verified against `WorldGenerator._apply_resource_veins()` 2026-06-05. Source of truth for
bands/thresholds is `data/terrain/block_resources.json`; algorithm and design goals are
normative in `43_mining_materials.md` §Resource Distribution. Resolved on retirement:
foundation gems confirmed (rock11 overwritable, diamond from Y4); surface dirt caps need no
extra protection (the replaceable set is rock01–11 only — grass, dirt, and soil are
structurally immune).

1. <span style="color:#f85149;">**Coal shadowing (bug-grade):**</span> first-match-wins on
   the shared `noise_ore` channel means coal (threshold 0.72, listed last) is captured by
   iron 0.70 / copper 0.66 / tin 0.66 everywhere their bands overlap — coal effectively
   spawns only at **Y12–19** despite its declared Y12–90 window, defeating its "smelting
   fuel, broad availability" role. Fix candidates: evaluate coal before iron/copper/tin,
   give coal its own noise offset, or re-band it. Verify densities in-engine after.
2. <span style="color:#d29922;">**Spatial confinement vs pure depth:**</span> should gold
   and gems get horizontal bias under the NW mountain mass, or is pure depth enough?
3. <span style="color:#d29922;">**Vein size:**</span> is `noise_ore` frequency `0.02` too
   sheet-like, or should metal veins become tighter and more followable?

## 5. <span style="color:#d29922;">Repeatable terrain review captures</span>

Screenshots / repeatable debug captures for terrain review (fixed seeds + camera
bookmarks). Process tooling, not a feature — adopt opportunistically.

---

*Prev: [11_slice_xray_plan.md](./11_slice_xray_plan.md)*
