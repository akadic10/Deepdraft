# 14 - Flora Distribution Plan (mixed forest)

Status: **implemented 2026-06-06 (Phases 1–4), pending in-engine verification.** Defines where the
four tree species belong and the system that places them. Builds on `13_flora_scatter_pine.md`
(the pine spawner) and implements `12_worldgen_second_milestone.md` §2 (*Scatter maps for flora*).

**Assets are done.** All four species exist as chunky 1:1 GLBs (`tools/generate_{pine,apple,oak,
juniper}_glbs.py`; see `61_voxel_art_guide.md`). This plan is about **placement**, not art.

> **Implemented (2026-06-06).** `WorldGenerator.get_moisture()` + `noise_moisture` (Phase 1);
> `SurfaceFloraSpawner` generalised to a multi-species registry with the unified per-cell selector
> (Phase 2); `placement` blocks added to oak/apple/juniper (Phase 3); apple grove mask (Phase 4).
> The placement logic was validated by a Python simulation of the selector (per-zone mix +
> determinism); it has **not** been run in Godot yet. **One deviation from §6 below:** the scatter
> cell size is a single **global** spawner export (`scatter_cell_size`, default 14), not a
> per-species field — one shared grid holds one tree per cell. Per-species `base_density` (+
> moisture/grove) set the mix within a cell. Pine's existing `spawn_chance` serves as its
> `base_density` fallback. Juniper floor lowered to Y12 so dry low ground isn't bare.

---

## 1. Decisions (recorded with the user, 2026-06-06)

| Question | Decision |
|---|---|
| What drives placement? | **Ecology + a moisture map** — elevation/domain bands *plus* a new seed-derived moisture channel. |
| Settlement plain & valley/road forested? | **Fully forested** — trees spawn everywhere suitable, including the lowland plain; the player clears land to build. |
| Apple trees | **Wild groves + plantable** — ancient/mature apples spawn wild in sheltered low ground; players can also plant saplings. |
| Edge forest belt | **No** — normal rules run to the border; no special border band. |

---

## 2. Worldgen inputs (the bands flora reads)

From `WorldGenerator.gd` (verified 2026-06-06). Flora reads these at runtime via public getters —
it never bakes into chunk data (props are placed entities, `12_world_grid.md`).

| Zone | Surface Y | Domain | Notes |
|---|---|---|---|
| Lowland shelf / settlement plain | 12–19 | lowland (0) | Buildable home; lowland lake at waterline **Y18** |
| Valley corridor | 20–27 | valley (1) | Future trade road (`12_worldgen_second_milestone.md` §1) |
| Foothill shelves | 20–43 | valley (1) | The main mixing zone |
| Lower mountain | 44–75 | mountain (2) | Mountain tarn at waterline **Y54** |
| Treeline | 75–90 | mountain (2) | Pine falloff band |
| High peaks | 90–115 | mountain (2) | Bare rock (future snow caps) |

Getters available: `get_surface_y`, `get_domain`, `get_visible_surface_y` (waterline),
`is_column_pending`. **New getter needed:** `get_moisture(wx, wz) -> float` (§3).

Hard exclusions everywhere: water columns (`exclude_water`), off-world/edge setback, slopes
steeper than a species tolerates (`max_surface_slope`), cliff lips (`edge_dropoff_max`).

---

## 3. The moisture model (new)

A single seed-derived noise channel, `noise_moisture` (FastNoiseLite, low frequency ~0.004),
giving each column a value `m ∈ [0,1]`. Deterministic from `world_seed` (Hard Rule 8) — no
`randf()`. Exposed as `WorldGenerator.get_moisture(wx, wz)`.

Two adjustments layered on the raw noise:

- **Water proximity boost:** columns within ~N blocks of the lowland lake, the tarn, or the
  valley floor read wetter (`+`). Keeps oak/apple hugging water and low ground.
- **Elevation drying:** higher columns trend drier (`−` scaled by surface Y above the foothill
  base). Pushes juniper and bare rock up high, broadleaf down low.

Buckets used by the niche table: **dry** `m < 0.40`, **mid** `0.40–0.65`, **wet** `m ≥ 0.65`.

> Optional later refinement (out of scope for v1): an **aspect** term (slope facing) so shaded
> north faces read wetter. Spec it only if the moisture noise alone looks too blobby.

---

## 4. Species niches

Each species is suitable where its elevation band, domain, and moisture preference all hold.
Overlap is intentional — the foothills are a true mix. "Pattern" is how the unified selector (§5)
weights it.

| Species | Surface Y | Domains | Moisture | Pattern / density | Footprint (sap/mat/anc) | Role |
|---|---|---|---|---|---|---|
| **Oak** | 12–43 | lowland, valley, foothill | mid–**wet** | Even, **dominant broadleaf** of low/wet ground | 1 / 3 / 5 | Hardwood; oak staves for barrels |
| **Apple** | 12–30 | lowland, valley (+low foothill) | **wet**, low slope | **Clumped groves** (grove mask), low overall | 1 / 3 / 5 | Wild fruit + player-plantable orchards |
| **Pine** | 20–90 | foothill, mountain | any (dry-tolerant); falloff 75–90 | **High on slopes**, the elevation tree | 1 / 2 / 3 | Construction lumber (already shipped) |
| **Juniper** | 16–95 | lowland (rocky), foothill, mountain | **dry** | Sparse, scattered; extends *above* pine treeline | 1 / 1 / 2 | Berries (future gin); hardy pioneer |

Reading the world by zone after this:

- **Lowland / valley (12–27):** oak-dominant broadleaf woodland, apple groves in the wettest
  pockets, juniper on dry rocky patches. Settlement plain is wooded — player clears it.
- **Foothills (20–43):** the blend — oak in wet folds, pine climbing the drier/steeper slopes,
  juniper on exposed rock.
- **Mountain (44–90):** pine forest thinning to the treeline; juniper on dry bands and a little
  above the pines.
- **Peaks (90+):** bare (juniper may freckle to ~95, then nothing).

---

## 5. Unified placement architecture

Today `SurfaceFloraSpawner` scatters **one** species (pine), each cell independently. With four
species that would let big canopies overlap and double-book cells. Replace the per-species scatter
with **one shared cell grid and a per-cell species selector**:

For each scatter cell (`scatter_cell_size`, ~6–8 blocks, one tree max):

1. **Hash** `(seed, cell_x, cell_z)` → deterministic stream (no `randf()`).
2. Pick the cell's **jittered column**; read `surface_y`, `domain`, `moisture`, slope, water.
3. Compute each species' **suitability score** `s_i ≥ 0` (0 if any of its band/domain/moisture/
   slope/water gates fail; otherwise a weight that peaks in the centre of its niche and tapers
   to the edges, ×its base density and ×any grove mask for apple).
4. **Select:** with probability `Σ s_i` (capped) place a tree; choose the species by hashed
   weighted pick over `{s_i}`. Otherwise leave the cell open (forest gaps).
5. Pick **stage** (species `stage_weights`; respect `world_gen_only` — e.g. apple/oak ancient are
   world-gen only) and **model variant** (the canonical resolver, `42_farming_brewing.md`).

This gives natural transitions (suitability blends across the moisture/elevation gradient), no
overlapping canopies (one tree per cell), and full determinism (same seed → same forest, no save
data) — exactly how terrain identity is reproduced.

Reuse from the pine system unchanged: whole-map streaming (nearest-first, drained over frames),
`_instance_tree` (already generic — reads `models`, footprint, `clearance_height`), the shared
unlit-vertex-colour material, Layer-2 tree collision (the camera-springarm gotcha, `13` §7).

---

## 6. Data schema

Standardise a `placement` block on every tree JSON (pine already has one). Add it to
`oak_tree.json`, `apple_tree.json`, `juniper_tree.json`:

```
"placement": {
  "domains": ["lowland","valley","foothill"],   // whitelist
  "exclude_water": true,
  "min_surface_y": 12, "max_surface_y": 43,
  "moisture_min": 0.45, "moisture_max": 1.0,    // niche band (new)
  "base_density": 0.5,                            // selector weight
  "scatter_cell_size": 7,
  "max_surface_slope": 1, "edge_margin": 2, "edge_dropoff_max": 3,
  "footprint": { "sapling": 1, "mature": 3, "ancient": 5 },
  "stage_weights": { "sapling": 0.15, "mature": 0.55, "ancient": 0.30 },
  "grove": { "enabled": true, "frequency": 0.02, "threshold": 0.6 }  // apple only
}
```

**Footprint-key cleanup:** apple/oak currently carry `footprint_tiles` per stage; pine uses
`placement.footprint`. Move everything to `placement.footprint` (per stage) and have the spawner
read only that. Juniper gains footprints 1/1/2. (Pine keeps its falloff fields
`full_density_max_y`/`falloff_max_y`.)

---

## 7. Spawner changes (`SurfaceFloraSpawner`)

- Load **all** `data/entities/flora/*_tree.json` into a species registry (placement + stages),
  instead of the single hard-coded pine path. Each system still owns its data (registry pattern).
- Add the **unified per-cell selector** (§5) over the existing chunk-column streaming.
- Add `WorldGenerator.get_moisture()` + the `noise_moisture` channel and a debug overlay readout.
- Keep `voxels_per_block = 1` (all trees are 1:1 now).
- Parity check: with only pine enabled, the new selector must reproduce today's pine forest.

---

## 8. Apple groves + plantable

- **Wild groves:** apple suitability is gated by a low-frequency **grove mask**
  (`hash/noise(seed, cell)` thresholded) so wild apples cluster into orchards instead of even
  scatter. Outside groves, apple weight ≈ 0.
- **Plantable:** the sapling→mature→ancient chain already exists in `apple_tree.json`. Player
  planting belongs to the farming/task system (out of scope here); this plan only needs to not
  conflict with it — wild placement and planted placement share the same models and growth data.

---

## 9. Tuning dials (all JSON, no code)

`scatter_cell_size` (bigger = sparser), `base_density` per species (mix balance),
`moisture_min/max` (niche width), `min/max_surface_y` (band), apple `grove.frequency/threshold`
(orchard size/rarity), pine `full_density_max_y`/`falloff_max_y` (treeline). Overall canopy
coverage is the product of cell size and the summed densities — tune against in-engine screenshots.

---

## 10. Dependencies & interactions

- **Trade road (not yet built, `12` §1):** the valley corridor is forested under this plan, but
  when the road ships its mask must **exclude flora** from the road strip. Flagged dependency.
- **Slice view:** trees still don't obey the slice plane (`13` §9). A denser mixed forest makes
  this more visible — revisit slice culling of props.
- **Performance:** more trees, but the 1:1 models are tiny (KB) and whole-map streaming drains
  over frames; `enable_collision` can stay off until agents exist. Rely on import LODs.
- **Determinism (Hard Rule 8):** moisture noise and all selection hashes derive from `world_seed`.

---

## 11. Phasing

1. **Moisture channel** — `noise_moisture` + `get_moisture()` in `WorldGenerator`, deterministic,
   with a debug overlay. No flora changes yet.
2. **Multi-species spawner** — generalise `SurfaceFloraSpawner` to the registry + unified
   selector; migrate pine into it; verify pine parity.
3. **Niches live** — add `placement` blocks to oak/apple/juniper, tune the mix per §4, verify the
   mixed forest by zone.
4. **Apple groves** — add the grove mask; confirm clustered wild apples.
5. **Later** — aspect term, water-bank reeds, boulders/scree, snow line (separate plans).

---

## 12. Verification

- **Determinism:** same seed → identical forest across two launches.
- **Zones:** sample columns per band confirm the §4 mix (oak low/wet, pine slopes, juniper dry,
  apple in groves); none in water; nothing above ~Y95.
- **No overlaps:** one tree per cell; canopies may touch but trunks never share a column.
- **Plain forested:** settlement plain shows trees (player-clearable), per the decision.
- **Performance:** node count + fps while panning a forested region; no node leaks.
- **Visual:** fixed-seed screenshots per zone for review.

---

## 12a. Known issues / follow-ups

- **Oak vs apple read too similar in-engine (logged 2026-06-06).** Both are broad chunky green
  deciduous canopies on brown trunks, so at overview zoom (and outside autumn/spring) they're hard
  to tell apart. Not fixing yet — just recorded. When addressed, candidate differentiators:
  diverge the summer canopy colour (e.g. oak a darker/bluer green, apple a lighter/warmer green),
  push the silhouette difference further (oak bigger + more irregular multi-lobe vs apple a tidier
  rounder dome), redden the apple trunk vs a greyer oak trunk, and/or let a few apples show fruit
  even outside the fruiting overlay. Lives in the generators (`generate_oak_glbs.py`,
  `generate_apple_glbs.py`) + `61_voxel_art_guide.md`.

---

## 13. Out of scope

Growth over time, planting/felling/harvest tasks, the trade-road mask itself, water-bank reeds,
boulders/scree, snow-line terrain, and the aspect/slope-facing moisture refinement. Each is its
own later plan.

---

*Prev: [13_flora_scatter_pine.md](./13_flora_scatter_pine.md)*
