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

**Current follow-up (2026-10-08):** the four-species mixed forest is already live.
[72 — Surface details plan](72_surface_details_plan.md) now provides the numbered
plan for boulders, scree, shrubs, flowers and lakeside reeds. The older asset
availability wording below must not be read as confirming bush models: the new
inventory found their definitions, but none of their 12 referenced model files.

> **Partly implemented (2026-06-06): pine.** `SurfaceFloraSpawner` now scatters pine across the
> foothill + mountain bands (elevation-gated, seed-deterministic, whole-map, streamed) — the
> first placed-entity system. Design and conventions (the canonical model-variant resolver, the
> spawn-time scale rule, the shared vertex-colour material, edge setback) live in
> `docs/00_dev_roadmap/13_flora_scatter_pine.md` and are meant to be reused by every later
> species/prop. **Oak, apple, and juniper 1:1 assets are now done too** (`61_voxel_art_guide.md`);
> their *placement* across the world — a moisture-driven mixed forest — is specced in
> [`14_flora_distribution_plan.md`](./14_flora_distribution_plan.md). **Still backlog:** boulders,
> scree, flowers/shrubs, road-side detail, and lake-bank reeds.

Worldgen itself does not bake flora into the chunk data (props are placed entities, not terrain
— see below); the spawner reads worldgen's domain/height maps at runtime. Tree/bush assets
already exist under `assets/models/flora/`. Remaining work is mostly extending the pine spawner
to the species/props listed above (each gets its own `placement` data block) plus any worldgen
hints they need (e.g. the border foliage belt mask).

Placement rules (already normative elsewhere — pointers, not duplicates):

- Props are **placed entities**, never terrain blocks (`12_world_grid.md` §Placed World
  Entities).
- Plant visual overhangs add no collision (Hard Rule 5, `42_farming_brewing.md`).
- Large props need local flatness checks.
- Determinism: scatter maps derive from `world_seed` (Hard Rule 8).

## 3. <span style="color:#d29922;">Open design questions</span>

- **Macro composition — resolved 2026-10-07:** seeded geography replaces fixed
  compass positions. Every seed retains substantial mountains and an intact
  32×32 Y115 summit. See [66](66_seeded_world_layout.md).
- **Snow / cold high-altitude stone:** should a future pass add snow caps or cold stone
  variants above some Y? (Weather snow exists, `data/weather/snow.json`; terrain snow
  does not. Touches the seasonal surface-palette system.)
- **Starting area — removed 2026-10-07:** the player chooses a site and clears
  trees. There is no reserved starting plateau, flora exclusion or candidate
  diagnostic to promote. See [66](66_seeded_world_layout.md).

## 4. <span style="color:#d29922;">Resource calibration (from retired doc 02)</span>

Verified against `WorldGenerator._apply_resource_veins()` 2026-06-05. Source of truth for
bands/thresholds is `data/terrain/block_resources.json`; algorithm and design goals are
normative in `43_mining_materials.md` §Resource Distribution. Resolved on retirement:
foundation gems confirmed (rock11 overwritable, diamond from Y4); surface dirt caps need no
extra protection (the replaceable set is rock01–11 only — grass, dirt, and soil are
structurally immune).

1. <span style="color:#3fb950;">**Coal shadowing — FIXED 2026-08-07 (doc 22 close-out
   pass):**</span> first-match-wins on the shared `noise_ore` channel meant coal
   (threshold 0.72, listed last) was captured by iron 0.70 / copper 0.66 / tin 0.66
   everywhere their bands overlap — coal effectively spawned only at **Y12–19** despite
   its declared Y12–90 window. Fixed data-only: coal's threshold lowered to **0.62**
   (below every earlier metal) in `data/terrain/block_resources.json`.
   This restored coal reachability. The later independent-field integration in
   [71](71_independent_ore_fields.md) replaces shared-metal cutoff ordering.
   In-engine density and economy tuning remain open.
2. **Spatial confinement — keep depth-based placement for now (2026-10-08):**
   the user accepted retaining settlement freedom and deferring horizontal
   mountain bias while moving on to [surface details](72_surface_details_plan.md).
3. **Vein shape — independent fields live 2026-10-08:** the
   [audit](69_resource_distribution_review.md) and
   [prototypes](70_ore_vein_prototypes.md) led to smaller independent metal patches
   with broad coal. [71](71_independent_ore_fields.md) records integration and
   sixteen-seed measurements. Final excavation/economy balance remains open;
   independent noise does not impose a hard maximum deposit size.
4. **Tin shadowing — fixed 2026-10-07:** copper/tin both used 0.66 on the shared
   channel, making tin unreachable at Y55–88. Tin was corrected to **0.64**,
   between copper and coal, before independent fields replaced this shared rule.
   Depths, priority and drops stay unchanged. Actual block samples and
   remaining balance limitations are recorded in
   [67 — World generation diagnostics](67_world_generation_diagnostics.md).
5. **Emerald shadowing — fixed 2026-10-08:** diamond/emerald both used 0.90,
   blocking emerald at Y5–12. Diamond now uses **0.91**, leaving emerald the
   interval `(0.90, 0.91]`. Exact Y4–22 censuses across eight seeds confirm all
   four deep gem types remain present. See [69](69_resource_distribution_review.md).

## 5. <span style="color:#d29922;">Repeatable terrain review captures</span>

Screenshots / repeatable debug captures for terrain review (fixed seeds + camera
bookmarks). Process tooling, not a feature — adopt opportunistically.

---

*Prev: [11_slice_xray_plan.md](./11_slice_xray_plan.md)*
