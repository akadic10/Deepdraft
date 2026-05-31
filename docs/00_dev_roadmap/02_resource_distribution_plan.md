# 02 — Resource Distribution Plan (Ore, Gem, Cave Soil)

This is a planning document. It proposes *at what elevations* ore, gem, and cave-soil
blocks should be injected into the generated world, and the method for doing so.
Implementation should follow review.

## Current State (why nothing spawns)

`WorldGenerator._generate_block_id()` decides each column's blocks from the **authored
strata** first:

- bedrock `Y0–3` → foundation `rock11` `Y4–11`
- lowland body/shelf `Y12–19`, foothill body + shelf `Y12–43`, mountain body + shelf `Y12–115`

Because every column is a lowland / foothill / mountain shelf column, one of those branches
**returns rock before** the underground ore / gem / cave-soil noise checks (the `n_ore`,
`n_soil` blocks lower in the function) are ever reached. Those checks are effectively dead
code today — hence no `:ore:`, `:gem:`, or `soil:cave` blocks appear.

Two existing data issues to fix while we are here:

1. **`ORE_LADDER` ordering is wrong.** `_pick_ore()` evaluates ascending rarity, first match
   wins, but thresholds also ascend. Tin (`threshold 0.68`, `max_y 95`) matches first across
   almost the whole map and masks every rarer ore. As written, only tin could ever appear.
2. **`depth_bias` is `max_y` only** — a ceiling with no floor. Every resource can appear
   anywhere below its cap, so nothing has a depth identity. We add a `min_y` floor.

## Design Goals

- **Depth identity / progression.** Digging deeper yields better rewards. This matches the
  existing "deeper = rarer" note in `block_resources.json` and the colony's natural arc.
- **Both dig routes pay off.** Mining *into* the mountain face (`Y44–115`) yields the common
  industrial metals; tunnelling *down* from the valley/lowland floor (`Y12–43 → Y4`) is the
  express route to precious metals and the gem tier near bedrock.
- **Deterministic & seed-stable.** No `randi()` — noise + position only, so streamed chunks
  reload identically.
- **Cheap.** Resources are layered onto rock blocks only; noise is sampled lazily.
- **Bedrock is inviolate.** Nothing ever overwrites `Y0–3`.
- **Surface stays intact.** The override never replaces the surface skin — **grass caps in
  particular** — only the rock/soil-body blocks beneath it. Ore, gems, or cave soil poking out
  of the grass surface would read as a generation bug.
- **Natural cliff faces stay readable.** Resource overlays do not replace rock on naturally
  exposed mountain or terrace side walls. Veins should become visible through player digging,
  not paint the untouched world overview with high-contrast patches.
- **World-edge perimeter stays concealed.** Resource overlays do not replace rock in the
  outer perimeter band of the map. The outside slab walls should show host strata only, so
  metals and gems are not revealed before the player mines inward.

## Vertical Context

The solid world runs `Y0–115`. Every column shares the deep foundation (`Y4–19`); only
mountain footprints add the tall `Y44–115` rock mass. That geometry drives the bands:

| World layer | Y range | What lives there |
|---|---|---|
| Bedrock | 0–3 | nothing (immovable) |
| Foundation `rock11` | 4–11 | **deepest gems** (diamond, emerald) |
| Lowland band / deep body | 12–19 | deep gems + gold tail |
| Valley / foothill body | 20–43 | iron core, silver, mid gems |
| Lower mountain | 44–72 | iron, copper, coal |
| Upper mountain | 72–115 | coal, tin, copper (shallow tier) |

## Proposed Elevation Bands

Each resource gets an elevation **window** `[min_y, max_y]` and a noise **threshold** (higher =
rarer). Bands overlap deliberately so tier transitions blend rather than hard-cut.

### Metals — sampled from `noise_ore` (larger, sheet-like veins, freq ≈ 0.02)

| Resource | Band (Y) | Threshold | Role |
|---|---|---|---|
| Coal     | 12–90 | 0.72 | Smelting fuel — common, but below the combined metal ore supply |
| Tin      | 55–95 | 0.66 | Upper mountain; bronze pair with copper |
| Copper   | 45–88 | 0.66 | Upper-mid mountain; early metal |
| Iron     | 20–72 | 0.70 | **Economic backbone** — broad mid band, lower mountain + valley-down |
| Silver   | 16–52 | 0.80 | Precious, mid-deep |
| Gold     | 8–36  | 0.84 | Precious, deep |

### Gems — sampled from a new `noise_gem` (small, clustered pockets, freq ≈ 0.06)

| Resource | Band (Y) | Threshold | Role |
|---|---|---|---|
| Jade     | 28–58 | 0.80 | Most common gem; mid-depth |
| Amethyst | 20–48 | 0.82 | Mid gem |
| Ruby     | 6–22  | 0.88 | Deep gem |
| Sapphire | 6–22  | 0.89 | Deep gem |
| Emerald  | 5–16  | 0.90 | Near-bedrock |
| Diamond  | 4–12  | 0.90 | Rarest, sits in the foundation band just above bedrock |

### Cave soil — sampled from `noise_soil`

| Resource | Band (Y) | Threshold | Role |
|---|---|---|---|
| `soil:cave` | 18–60 | 0.66 | Farmable pockets (plump helmet). Not depth-valuable; a utility resource exposed when mined. Sits in the habitable mid-depth where the colony lives. |

> **Threshold intuition.** A single simplex value remapped to `[0,1]` clears `0.62` over
> roughly a quarter of space, `0.70` ~15%, `0.80` ~7%, `0.88` ~2–3%, `0.94` <1%. So coal is
> plentiful, iron solid, gold scarce, and diamond a rare treat. Treat these as **starting
> values** and calibrate against the existing block-spawn-count metrics report.

## Selection Method (fixes the ladder bug)

Layer resources onto the authored rock as a vein/pocket overlay. The override runs **only on
sub-surface rock body blocks** (`y < surf_y`, so the surface cap is excluded by construction)
and it **never** replaces a `surface:grass_*` block. For a qualifying block at `(x, y, z)`:

Before sampling any resource noise, reject natural exposed wall blocks: if a cardinal neighbour
column's surface is lower than `y`, the block is part of a visible cliff/terrace face and remains
its authored rock. This preserves the macro terrain read and keeps resources as rewards revealed
by mining.

1. **Gems first** (rarer, more valuable). Sample `n_gem = remap(noise_gem)`. Walk the gem list
   **rarest → most common** (diamond, emerald, sapphire, ruby, amethyst, jade). First whose
   window contains `y` **and** `n_gem > threshold` wins.
2. **Else metals.** Sample `n_ore = remap(noise_ore)`. Walk the metal list **rarest → most
   common** (gold, silver, iron, copper, tin, coal). First match wins.
3. **Else cave soil.** If `18 ≤ y ≤ 60`, sample `n_soil`; if `> 0.66`, place `soil:cave`.
4. **Else** keep the authored rock.

Evaluating **rarest-first** is what removes the first-match-wins masking bug — a block that
qualifies as both diamond and (say) tin becomes the diamond. Using a **separate `noise_gem`**
field lets gems cluster into small pockets independent of the broader metal veins.

## Code Integration

- **Pipeline position:** resource distribution is **not** a terrain-shaping phase. It runs only
  after the generator has built its noise instances, applied the 32×32 macro domain layout,
  computed the heightmap, carved lake/tarn bodies, and built the surface band masks. In the
  current demand-streamed generator, that means resources are evaluated during Phase 5 chunk
  column filling, after `_maps_ready = true`.
- **Where:** wrap the authored-rock returns in `_generate_block_id()`. Compute the rock id into
  a local `rock_id`, then `return _apply_resource_veins(x, y, z, surf_y, rock_id)`. The helper
  returns a resource id or the original `rock_id`. This is logically a **post-strata inline
  overlay**: the macro terrain and authored strata decide the base block first; ore, gems, and
  cave soil decorate eligible subsurface rock afterward. It stays inline so streamed columns pay
  the cost once with no second full-world traversal.
- **Order dependency:** do not call `_apply_resource_veins()` before the 32×32 macro terrain
  layout exists. The resource pass assumes `heightmap`, `domain_map`, water masks, and surface
  band maps are final for the column being filled.
- **Surface guard:** invoke `_resource_override` only from the rock-body return paths, never
  from `_pick_surface_block`. Gate on `y < surf_y` and assert the candidate is not a
  `surface:grass_*` variant, so the grass cap is never overwritten — ore/gems/cave soil only
  appear once a dwarf digs below the surface skin.
- **Perimeter guard:** before sampling gem, metal, or cave-soil windows, return the authored
  rock unchanged when `x/z` is inside the world-edge suppression band. This is separate from
  the natural exposed-wall guard because boundary columns have no out-of-bounds neighbor to
  compare against.
- **Foundation gems:** allow the override to run inside `Y4–11` (so diamond/emerald can sit in
  the `rock11` foundation) but **never** at `Y0–3`.
- **Data-driven:** add `min_y` to each resource's `depth_bias` in `block_resources.json`
  alongside the existing `max_y` and `noise_threshold`, plus the gem-vs-metal noise channel.
  Cache the windows in `_cache_block_ids()` so the worker thread never touches `BlockRegistry`.
- **Noise:** add a `noise_gem` instance (seed offset `+7`, freq ≈ 0.06, 3 octaves). Keep
  `noise_ore` for metals. Replace/repair `ORE_LADDER` + `_pick_ore` with the rarest-first,
  windowed evaluation above (or delete them in favour of the data-driven path).
- **Determinism:** position + noise only; no `randi()`/`randf()`.

## Open Decisions (your call)

1. **Spatial confinement vs pure depth.** The bands above are pure depth, which already makes
   the mountain the de-facto source of shallow metals and the valley-down route the path to
   gems. Do you also want a *horizontal* bias (e.g. gold/gems concentrated under the NW mountain
   mass) using `mountain_influence`? Cheap to add as a strength multiplier on the threshold.
2. **Vein size.** `noise_ore` at freq 0.02 gives large sheets. If you want tighter, more
   "followable" veins, raise it to ~0.04 (or give metals their own `noise_metal`).
3. **Foundation gems.** Confirm gems may overwrite `rock11` (`Y4–11`). Recommended yes — it is
   the deepest minable band and the thematic "deep draft" payoff.
4. **Coal availability.** Coal is the only smelting fuel. Band `Y12–95` keeps it findable both
   in the mountain and when digging down. Confirm that breadth is acceptable.
5. **Surface dirt cap.** Grass is protected. The visible cliff/cap dirt (`surface:dirt_*`) sits
   just under the grass and forms the readable side-wall strata. Should the override also leave
   that dirt cap alone (recommended — extend the guard to `surface:dirt_*`), or may ore/cave
   soil replace dirt in the body bands?

---

*Prev: [01_world_gen_plan.md](./01_world_gen_plan.md)*
