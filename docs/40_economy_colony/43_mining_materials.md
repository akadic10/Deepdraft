# 43 — Mining & Materials

## Overview

Mining is the primary expansion mechanic. Dwarves remove solid blocks, depositing raw materials into nearby stockpiles. The geological composition of the mountain is procedurally generated and affects resource yield, structural stability, and collapse risk.

**Gem drops (2026-10-10):** Jade, Amethyst, Ruby, Sapphire, Emerald and Diamond
drop as finished, gleaming valuables. No Jeweller, cutting or polishing stage is
planned. The six shared voxel models and inventory thumbnails use distinct
palettes and light-dependent highlights, including under local torches. Gems
obey normal underground darkness, slice visibility, carrying and storage rules.
Existing `_raw` item keys, drop chances, values and counts remain unchanged;
the displayed names omit "Raw". See [104](../00_dev_roadmap/104_gem_drop_artwork.md).

## Geological Spectrum

Wet and dry stones are loose ore-shaped world models, without terrain block IDs
or mining yields. Surrounding rock remains editable; their source/drain behavior
stays fixed. See [109](../00_dev_roadmap/109_loose_water_stones.md).

| Block Key | Category | Hardness | Yield | Notes |
|---|---|---|---|---|
| `base:terrain:rock:rock01`-`rock06` | Mountain rock | 3 | 1× Rough Stone (5%) | Authored mountain shelves |
| `base:terrain:rock:rock07`-`rock10` | Body rock | 3 | 1× Rough Stone (5%) | Valley/foothill body bands |
| `base:terrain:rock:rock11` | Foundation rock | 3 | 1× Rough Stone (5%) | Stable band above bedrock |
| `base:terrain:ore:iron`       | Ore        | 4 | 2× Iron Ore (10%)     | Common ore |
| `base:terrain:ore:copper`     | Ore        | 3 | 2× Copper Ore (10%)   | Shallow, early-game |
| `base:terrain:ore:gold`       | Ore        | 5 | 1× Gold Ore (10%)     | Deep, rare |
| `base:terrain:gem:ruby`       | Gem        | 5 | 1× Ruby               | Very rare, high trade value |
| `base:terrain:soil:cave`      | Soil       | 1 | 1× Soil (5%)          | Farmable (see `42_farming_brewing.md`) |
| `base:terrain:bedrock`        | Bedrock    | ∞ | None                  | **Unmovable — Y=0..3 protocol** |

**Hardness** determines mining time: `mine_time = base_time × hardness / dwarf_mining_skill`.

`base_time = 2.0` seconds at skill 1 on hardness 1.

> **Rough Stone (added 2026-06-10, retuned 2026-08-06 twice):** all 11 rock bands drop
> `base:resources:stone:rough_stone` at 5% chance (tunable — `data/terrain/block_resources.json`;
> was 50% at launch, cut to 25% on 2026-06-10, then 12% then 5% both on 2026-08-06 — the last cut
> was explicitly for testing convenience, less stockpile clutter while iterating, not a final
> economy number). Its purpose is **void fill**: the player will use stocked rough stone to wall
> up and backfill unwanted openings via a future BUILD designation (mechanic not yet designed —
> the item and drop exist now so mining execution, `16_first_dwarf_milestone.md` Phase 4, yields
> it from day one). May need to come back up once backfill is actually playtestable.
>
> **Soil (retuned 2026-08-06 twice):** every soil/dirt/grass block (surface grass/dirt variants and
> `soil:cave`/`soil:light`/`soil:dark`) dropped its soil item at a guaranteed 100% until 2026-08-06,
> cut to 30%, then to 5% later the same day (same testing-convenience reasoning as stone, now
> matching it) — tunable in the same file.
>
> **Ore (retuned 2026-08-14):** all six ores (copper, tin, iron, silver, coal, gold) cut from a
> guaranteed 100% to **10%** — Alen: drop volume was flooding manual playtests (chests filling
> with silver/iron faster than they could be placed). Same testing-convenience class as the
> stone/soil cuts above, explicitly not a balance number; revisit in the economy pass. Gem
> chances remain untouched (0.65–0.90).

## Mining animation and feedback — implemented and accepted 2026-10-04

Dwarves show an implicit pickaxe held by both floating hands, with recovery,
wind-up, strike and contact hold. The point reaches the target voxel face across
the existing vertical reach, including underfoot mining. No tool inventory,
crafting or durability requirement is introduced. Work honors WorldClock
pause/speed and retains the authored hardness/durability totals.

Contact triggers a procedural stone strike or softer soil impact and six small
outward chips. Grass/dirt use the soil sound family; rock, ores and gems use stone.
The struck face's chip color follows the renderer's concealment rule: authored
strata until the facing neighbour is mined open, then the exposed material.
Effects never reveal hidden neighbouring resources or sliced-out targets.

A successful block-removal commit produces one brief material-colored dust puff.
Restore, DEV edits and generic terrain writes produce no mining feedback. Drops
remain immediately available. The shared `WorkFeedback` service supplies camera
focus/zoom attenuation, stereo panning, bounded simultaneous sounds/effects,
pause/speed handling and scene cleanup. It adds no saved simulation state.

Implementation, tuning, generators, test coverage and native previews:
[doc 48 §6](../00_dev_roadmap/48_object_explorer_and_tree_felling.md#6-mining-tool-sound-and-effects).

## Pickaxe upgrades — planned (2026-10-09)

Agreed with the player after the first Miner promotion. This is future equipment
work, not current mining behavior; see
[41 — Equipment progression](41_dwarf_agents.md#agreed-equipment-progression--planned-2026-10-09).

| Tool | Planned benefit |
|---|---|
| Default pickaxe | Current single-block mining; immediately available, including on Miner promotion |
| Iron pickaxe | Modest chance to remove **2 voxels total** when completing a block; first crafted upgrade |
| Steel or another advanced metal | More frequent double breaks, with an occasional **3-voxel total** break |

Exact probabilities, recipes and advanced-metal choice require later balancing.
The equipment effect supplements the existing Miner experience speed bonus.

- Roll once per normally completed block, never once per animation strike.
  Bonus removals cannot trigger further bonus rolls.
- Extra blocks must be adjacent, still designated in the same mining zone,
  reachable by the miner and eligible for normal mining. Never enlarge the
  player's designation or take another dwarf's reserved block. A one-block
  designation still removes exactly one block.
- Recheck eligibility after each removal, including bedrock protections, current
  reach and footing beneath dwarves or ladders. Skip extras that would remove
  that footing; use a smaller result when fewer eligible blocks remain.
- Every removed voxel uses normal world updates, resource-drop rules and Miner
  experience. This speeds excavation; it does not multiply a single voxel's loot.
- Preserve mining progress, task cleanup and save/load behavior, including when
  a bonus block completes the zone.

Implement this with the physical equipment and specialist crafting systems.
Tool durability and repairs are outside the first version.

## Mining Tools

The player designates mining regions using two tools. Both tools create a **mining zone entity** that persists in the world until the work is complete. Dwarves path to the zone's adjacent cells and mine blocks one at a time from the zone's destination region.

> **Verified against Stonehearth source:** `stonehearth_client.js` wires `mineBasic` → `designate_mining_zone('cube')` and `mineCustom` → `designate_mining_zone('custom_block')`. Constants: `XZ_CELL_SIZE = 4`, `Y_CELL_SIZE = 5`, `MAX_WORKERS = 4` per zone. The cell alignment uses floor/ceil snapping to always expand to a full cell boundary.

---

### Tool 1 — Dig (Large, Grid-Snapped) — NOT YET IMPLEMENTED

> Deferred. Only Tool 2 (Precision Dig) is built today; this section is the design spec for
> when the large snapped tool lands.

The primary mining tool. The player clicks and drags on any terrain face; the selection **snaps outward** to the nearest 4×4×4 cell boundary. The result always covers a complete cell — you can never designate a partial cell.

**Cell size for Deepdraft:**

| Axis | Cell size | Physical size | Rationale |
|---|---|---|---|
| X, Z | 4 blocks | 2 m × 2 m | Two dwarves can pass side-by-side |
| Y | 4 blocks | 2 m | Floor (1) + 3-block clearance envelope = minimum passable corridor |

**Alignment rule** (mirrors Stonehearth's `get_aligned_cube`):

```gdscript
func get_aligned_region(selection: AABB) -> AABB:
    const XZ := 4
    const Y  := 4
    var aligned_min := Vector3i(
        floori(selection.position.x / XZ) * XZ,
        floori(selection.position.y / Y)  * Y,
        floori(selection.position.z / XZ) * XZ
    )
    var aligned_max := Vector3i(
        ceili(selection.end.x / XZ) * XZ,
        ceili(selection.end.y / Y)  * Y,
        ceili(selection.end.z / XZ) * XZ
    )
    return AABB(aligned_min, aligned_max - aligned_min)
```

A single click (no drag) always produces a **4×4×4 zone**. Dragging expands the selection by full cell increments only.

**Dig direction:**
- Click on a **horizontal face** (top of terrain) → zone extends downward from the surface. This is the primary cave-entry flow.
- Click on a **vertical face** (side of a wall) → zone extends inward from the face. Used for expanding rooms horizontally.

---

### Tool 2 — Precision Dig (Variable, 1-Block Minimum) — SHIPPED (designation + real execution)

> **Real mining execution live since 2026-06-10 (doc 16 Phases 4–5):** confirmed zones are now
> work sources — dwarves take zone leases, walk over, and mine blocks into `WorldData` for real
> (see §Worker Assignment Flow below). The "visual cut only" model described further down
> remains true **for the designation phase**; execution then writes void through
> `WorldData.set_block` with the bedrock re-guard.

> Migrated from the original `00_dev_roadmap/03_mining_plan.md` (retired 2026-06-05). The
> follow-up Stonehearth parity-polish pass shipped 2026-06-06 (see *Shipped UX polish* below);
> its tracking doc `05_mining_tech_debt.md` was retired the same day (git history retains the
> worklog). Implemented in `scripts/systems/MiningDesignationController.gd`. Tuning lives in
> `data/terrain/mining_config.json` (defaults 1×1, max 8×8, max drag 40) — the controller's
> inline values are fallbacks only; JSON wins.

**Shipped UX polish (2026-06-06 Stonehearth parity pass — all verified in-engine):**

- *Drag height locking* — mid-drag the moving end locks to the anchor block's top plane, so the
  selection footprint stays flat across slopes/terraces (`_raycast_anchor_plane`).
- *X/Z rulers + depth label* — flat dimension bars (main line + end caps + outward arrowheads) on
  the selection top, plus a corner depth number, showing the true footprint extents
  (`_build_ruler_mesh`); modelled on SH `services/client/selection/ruler_widget.lua`.
- *Instant modifier recolor* — Ctrl press/release flips the designate↔remove colour immediately,
  even with a stationary cursor.
- *Mining-mode hint callout* — a control-summary panel (`_build_hint_window`) shown while the
  tool is active. Custom cursor assets remain deferred.
- *Dropped — per-cell validity tinting:* SH keeps the marquee rectangular and just designates the
  terrain-intersected subset (filtered by `_filter_mineable_blocks`); a per-cell display would
  diverge from SH (`call_handlers/mining_call_handler.lua` only swaps the whole cursor to
  `invalid_hover`). Only the existing whole-selection "empty confirms to nothing" is kept.

> **Known perf caveat — active-tool per-frame cost (migrated from retired
> `05_mining_tech_debt.md`, 2026-06-06):** while the tool is active (HOVER or DRAGGING),
> `_process` runs `_rebuild_terrain_grid()` + `_update_hover_preview()` every frame. Moving the
> camera (WASD) keeps the mouse fixed on screen but scrolls the world under it, so the hovered
> block changes every frame → `_update_hover_preview` never early-returns and each frame re-runs
> `_raycast_voxel` (a DDA march up to `camera.far` = 1024, worst when pointing past terrain at
> the sky), rebuilds the hover preview mesh, and rebuilds the floor grid → choppy camera movement
> with the tool on (confirmed pre-existing, not from the 2026-06-06 drag-lock change). Mitigations
> cheapest-first: (1) cap the voxel march distance / early-out when the ray leaves the world's
> vertical band; (2) throttle the hover raycast + grid rebuild to ~30 Hz; (3) skip the rebuild on
> camera-only frames when the hovered block is unchanged. Acceptance: WASD pan stays smooth with
> the tool active while preview/grid still track the cursor when the mouse moves. (Minor related:
> holding Ctrl over empty space force-runs the empty-clear branch each frame — negligible.)

A single-block tool for surgical work: finishing a room corner, punching a doorway, clearing one specific block. Starts at 1×1×1 and is resized interactively before confirming. Dock `Mine` requests `mine_precision` via `DockUI.tool_requested`; the tool stays active after each confirm for repeated designations.

| Control | Effect |
|---|---|
| Left click + drag | Designate the mining region (mouse-up confirms) |
| Shift + MouseWheel up/down | Expand/shrink horizontal extent (X and Z), 1–8 blocks |
| Alt + MouseWheel up/down | Expand/shrink vertical extent (Y), 1–8 blocks |
| Ctrl held while confirming | Subtract existing mining zones under the selected region |
| Escape | Cancel / exit mining mode (ESC-only — right-mouse is reserved for camera orbit, `21_camera.md` tool input contract) |

The selection is anchored at the clicked face normal — the region grows away from the face the player pointed at. There is no grid snapping. The region is always exactly the size shown.

**Region math** (`_build_precision_region()` / `_map_precision_axis()`):

```text
if normal.y != 0:                       # clicked a top/bottom face
    min_y = anchor.y + 1 - size_vertical
    max_y = anchor.y + 1
else:                                   # clicked a side face
    min_y = anchor.y - floor(size_vertical / 2)
    max_y = anchor.y + floor(size_vertical / 2 + 0.5)
```

Invariants: the origin block is always included; horizontal extents round up to a multiple of
the current horizontal size; the region grows away from the clicked face when there is a
horizontal face normal; axes without a normal component are centered by half the horizontal
size; max drag length is enforced by trimming one horizontal-size step.

**Selection filters:** out-of-bounds, transparent blocks, water, and `y <= 3` (Bedrock
Protocol) are never selected; a preview with no valid mineable blocks confirms to nothing.
Designation is clipped to the visible volume (WYSIWYG — confirm designates exactly what the
preview shows; `11_slice_xray_plan.md` Phase 3).

**Zone selection:** clicking a confirmed zone opens a compact `Mining Zone` window with
`Remove`, `X`, and the DEV mine button below.

**Visual terrain cut model (interim, until worker mining):** confirmed zones visually cut
terrain through renderer state only — `WorldData` is never mutated by designation. The
controller pushes localized deltas (`add_visual_cut_blocks` / `remove_visual_cut_blocks`);
`ChunkMesher` skips cut blocks and the overview recomputes visible surfaces after subtracting
them. Designations render concealed everywhere (strata-only ghost — a plan reveals nothing;
see the unified exposure principle, `24_world_rendering.md`).

This tool is intentionally slower to use than the Dig tool. A 1×1×1 precision dig is for fine work; players who want to carve a room should use the Dig tool.

---

### DEV Instant Mine (testing tool, added 2026-06-05; re-based 2026-06-10)

Not gameplay: the Mining Zone window's **DEV Mine (no drops)** button executes the selected
zone immediately — no dwarves, no drops. Since real mining execution landed (doc 16 step 6),
its semantics are **the same pipeline minus the dwarf**:

- The zone's blocks become **mined**: leases are cancelled and the work source unregistered,
  zone bookkeeping is erased, the renderer's visual cuts are KEPT (in overview mode the cut
  set is the authoritative record of removal — the generated heightmap would resurrect the
  rock otherwise), chunks are **materialised from the generator** before the void write, and
  `WorldData` gets void written everywhere (the old "only where a chunk exists" carve-out —
  and the nav blind spot it caused — is gone). The renderer's `add_mined_blocks()` moves the
  blocks into the mined set (exact-colour reveal per the unified exposure principle), and the
  X0 `InteriorTracker` records the interior columns.
- Mined blocks are transparent to the designation raycast (the freshly exposed rock
  behind/beneath is designatable — iterative digging works), excluded from new designations,
  and stepped past by the terrain grid's effective-top walk.
- No undo; a new run regenerates the world. Differences from real mining: instant, no
  drops, no dwarf labour.
- Lateral digs surfaced the overview's cavity-invisibility property and unblocked its fix —
  see `11_slice_xray_plan.md` Phase SO-2b (mined/designation set split, side-band punching,
  cavity shell).

---

### Mining Zone Entity

Both tools produce the same kind of mining zone entity in the world. Key properties:

- **Region**: the designated block volume to be mined, stored as a `Region3i`.
- **Destination**: the subset of the region that dwarves can currently reach and mine (updated each time terrain changes within the zone).
- **Max workers**: **4 dwarves** may work the same zone simultaneously. Additional dwarves are rerouted to other tasks.
- **Enabled/disabled**: the player can pause a zone without deleting it. The zone persists until all blocks in it are mined or it is manually deleted.
- **Render**: the zone boundary is drawn as a coloured region outline overlay — it is not part of the terrain mesh.

When a dwarf mines the last block in a zone, the zone entity is automatically destroyed.

> **Block-state split — LANDED 2026-06-10 (doc 16 step 5; Phase 4 acceptance run banked
> 2026-07-06 — milestone closed):**
> the mined/designation set split shipped with slice Phase SO-2b; the remaining split —
> **completed**, **destination**, and **reserved** blocks — now lives in
> `scripts/components/MiningZoneComponent.gd` (the zone's work source). Destination is derived
> lazily (in region, not completed, not reserved, ≥1 walkable stand cell); full reachability
> is proven by the dwarf at pull time (3 path failures release the lease with backoff).

> **Adjacency decision (Alen, 2026-06-05): adjacent zones are NOT merged — a deliberate
> departure from Stonehearth.** Performance reasoning, against the per-zone overlay
> architecture (per-zone overlay split, shipped 2026-06-05): merging makes every confirm
> beside an existing zone rebuild the whole merged zone (unbounded growth — the exact
> whole-rebuild pathology the per-zone split removed), widens zone Y-ranges until the
> slice-step clip-state skip never applies, and pays an adjacency/union scan per confirm
> for zero rendering benefit. Gameplay side-effect, accepted: each zone keeps its own
> MAX_WORKERS=4 cap rather than a merged zone sharing one cap. Known cosmetic remainder
> (was `05_mining_tech_debt.md` #7, retired 2026-06-06): adjacent zones draw a doubled outline
> at the shared seam — if it bothers in play, the fix is presentational (suppress outline faces
> against any-zone neighbours via `_zone_by_block`), never data merging.

---

### Worker Assignment Flow — IMPLEMENTED (doc 16 §2.7, live since 2026-06-10)

```
1. Player designates zone → MiningZoneComponent created (work source), region set
2. Component posts min(MAX_WORKERS (4), unreserved remaining) MINE leases to TaskManager
3. Dwarf holding a lease: pull → reserve → path to stand cell → swing timer → commit, loop
   - reach-aware pull: blocks workable from the dwarf's CURRENT cell rank first (2026-06-26)
   - vertical reach envelope: a dwarf beside a face works blocks up to reach_up_blocks (5)
     above / reach_down_blocks (1) below their stand floor (mining_config.json execution.*)
   - swing = base × hardness ÷ durability per swing; partial swings discarded on interrupt
4. On each block mined: bedrock re-guard (y > 3), chunk materialised from the generator before
   the first write, WorldData.set_block → void, renderer add_mined_blocks (exact-colour
   exposure), drops spawn via ItemDropManager per block_resources.json, InteriorTracker X0
   bookkeeping, nav cells invalidated
5. Destination recompute is lazy and local (blocks completing / chunk_dirtied in zone bounds);
   stalled zones re-target + re-arm leases when nearby terrain opens
6. When the zone empties: leases complete, zone entity destroyed
```

Interruption at any step releases the lease cleanly (doc 16 §2.8) — the reserved block returns to the destination set, zone progress is never lost.

---

## World Design Intent (North Star)

> Migrated from the original `00_dev_roadmap/01_world_gen_plan.md` (retired 2026-06-05; live
> remainder in `00_dev_roadmap/12_worldgen_second_milestone.md`). These are the enduring
> design rules the generated world must read as; the pipeline below is how they are produced.

Deepdraft borrows **Stonehearth's clarity**, not its systems or assets. The world should read
first as calm flat plates separated by strong blocky cuts, then as detailed wilderness once
edge detail, water, materials, and scatter are layered on top. Deepdraft's hard difference:
terrain is a true voxel simulation — world *data* decides block identity (mineable, pathable,
inspectable), and the renderer may simplify exposed faces but must never paint a heightmap that
disagrees with the generated blocks.

### Terrain rule (highest priority)

The Stonehearth plateau pattern comes before any visual detail:

1. Build a low-resolution macro height map.
2. Expand each macro value into large flat terrain plates.
3. Quantize the expanded heights into readable bands.

Plains vary only 0–2 blocks locally; foothills step in **8-block shelves**;
mountains step in **12-block shelves**. If a later idea fights this rule, this rule wins.

Lowland is not allowed to appear as an embedded island inside foothills. Lowland macro cells
must connect to the true lowland basin or a map-edge lowland mass; disconnected lowland cells
are promoted to valley/foothill before heightmap expansion. Settlement location is
chosen by the player; generation does not raise or flatten a dedicated starting area.

### Surface strata rule

Plains use a real earth body under the grass cap, never grass directly on stone:

- 1 block grass cap,
- 4–8 blocks of dirt / light soil / dark soil beneath it (broad horizontal bands for readable
  cliff faces),
- stone only below the soil body, or where slope / mountain influence / bank / exposed-rock
  rules override it.

The mountain is rock-heavy; the plains are earth-heavy.

### Grass palette rule

Grass colour is **domain language, not random speckle**. The eight active variants split by
domain: lower plains use `grass_01`–`grass_04`; valley / highland / foothill use
`grass_05`–`grass_08`. Within a domain, a calm base grass fills the interior and lighter
variants trace patch edges and terrace lips — region-aware outlining, never per-block noise.

### Core world composition (seeded macro layout)

The approved seeded layout is live as of 2026-10-07. There are no fixed compass
regions or central valley. Ridges, secondary hills, foothills and water positions
vary by seed. The increased lowland share was accepted for future development.

| Region | Guarantee / shape | Elevation |
|---|---|---|
| Mountain region | At least 128 connected dry macro cells containing a summit | Shelf tops Y55/67/79/91/103/115 |
| Summit | At least one intact 32×32 plateau; larger allowed | Y115 |
| Foothills | Shelves around seeded landforms | Tops Y27/35/43 |
| Lowland | At least 205 cells' worth of connected dry columns after detail; no embedded lowland islands | Y19 |
| Lowland lake | One connected 12–32-cell body, inland or at any map edge | Floor Y11, water Y12–18 |
| Mountain tarn | Optional single-cell body, full Y55/Y67 surround | Floor Y47, water Y48–54 |

The player chooses where to place the flag and which trees to clear. Terrain and
flora have no reserved start footprint. The camera uses its configured initial
position, with the existing terrain-clearance behavior.
Profile, implementation, checks and visual evidence: [doc 66](../00_dev_roadmap/66_seeded_world_layout.md).

> **Design reference (Stonehearth).** The original plan reviewed `services/server/world_generation/`
> and `data/biome/*_generation_data.json`. The lessons Deepdraft kept: large readable landforms
> over noisy detail; broad flat terraces for legible settlement choice; elevation changes as
> strong terrace drops (~8 blocks foothill, ~12 mountain) rather than slopes; soil strata
> alternating in 2-block bands for readable side walls; grass edges deliberately lighter than
> interiors; water biased toward flat ground; props placed as scatter entities after terrain.
> Deepdraft uses tuned equivalents of Stonehearth's step sizes but shares no assets or data.

---

## World Generation Pipeline

The world is generated from its seed and the active
`data/world_gen/macro_layout_v1.json` profile. This is the only live geography
path. The developer confirmed there are no existing saves to support, so no
legacy generator or migration layer is retained.

### Stage A — Geography and column maps

1. `WorldGenerator` loads and validates the profile on the main thread, caches
   block IDs, then starts its background worker.
2. `WorldLayout` constructs seeded ridges, surrounding shelves and water
   footprints. Independent `WorldLayoutValidator` checks the
   complete candidate. Eight bounded attempts are followed by one of 32
   exhaustively checked fallback variants.
3. Expand macro heights and each water body's waterline into authoritative
   column arrays. Domains follow final heights: lowland ≤Y19, foothill Y20–43,
   mountain Y44+. `domain_n_map` is a height-derived terrain gradient, not the
   old compass-influenced domain noise. `DOMAIN_VALLEY` remains the API name for
   foothills; it no longer implies a central corridor.
4. Add seeded ledges to every natural cliff and shore, including summit edges,
   foothill rims and transitions into lowlands. Preserve summit interiors.
   Shore detail fills narrow strips with rock, creating
   irregular dry lips and submerged ledges; rebuild water membership/bank masks.
5. Validate **every finished column** before exposing maps. Confirm no erosion,
   no height above Y115, exact protected interiors, all six shelf areas,
   consistent domains/waterlines, and no excessive dry shelf steps (including
   diagonals). Check connected dry lowland area and water containment. Detail
   remains within three-column boundary strips; wide lowland/water cores retain
   the accepted macro connectivity. Macro validation budgets the lost flat area.
6. Build dry connected caves from `data/world_gen/caves_v1.json`, using the final
   detailed heights and water maps for shell/containment checks. Cache immutable
   air spans and optional soil-floor patches; surface heights and shores are not
   changed. See [68 — Caves and discovery](../00_dev_roadmap/68_caves_and_discovery.md).
7. Publish `_maps_ready`. Build grass
   bands, visible tile ranges and metrics afterward; `grass_bands_ready` refreshes
   already rendered surfaces when those variant maps finish.

### Water bodies

The main lake and optional tarn each store their macro-cell footprint, floor and
waterline. Expansion produces `waterline_map` (`-1` on dry land). Visible surface
queries, streamed-column vertical bounds, overview tile ranges and generated
water blocks all use this map. Existing `lake_columns` and `tarn_columns` sets
remain available to flora, flag placement and other consumers.

Main lake floor Y11 / waterline Y18 and tarn floor Y47 / waterline Y54 remain the
current profile values. Main lakes can be inland or meet any edge; tarns require
a full 3×3 mountain-shelf surround. These maps describe initial water occupancy;
live volumes belong to `WaterManager` ([doc 33](../30_simulation_systems/33_water_simulation.md)).

**River generation — live 2026-10-10:** after macro validation and edge detail,
`RiverLayout` chooses a downhill connection from an upper rock-face spring to the
main lake. It preserves Y115 summit columns, cuts authoritative channels, adds
quiet pools and starts shallow river reaches with a hydraulic gradient. Caves
are placed afterwards, respecting the resulting water buffers. A natural lake
fissure drains only excess above its fixed threshold. Stored water is finite;
mining/solid edits can divert it or cause flooding. `waterline_map` is immutable
seed data, not a live water-level query. Terrain meshes draw actual beds;
`WaterRenderer` supplies changing surfaces and cascades. See roadmap 105.

### Seed and noise

`generate(0)` chooses a seed once; a supplied nonzero seed is deterministic.
Geography uses independent seeded RNG streams for landforms and each
water choice. Save/load regenerates the base maps from the stored seed, then
reapplies edits. Five independent `FastNoiseLite` instances provide the existing
resource/surface/ecology fields; old mountain/valley shaping noise and the unused
cave-noise fallback were removed. `CaveLayout` owns separate deterministic RNG
and roughness streams for the new chamber geometry.

| Noise | Seed offset | Frequency | Octaves |
|---|---:|---:|---:|
| Ore | +1 | 0.02 | 2 |
| Soil | +3 | 0.03 | 2 |
| Surface regions (`noise_domain`) | +4 | 0.0015 | 2 |
| Gems | +7 | 0.06 | 3 |
| Moisture | +8 | 0.004 | 2 |

### Stage B — On-demand block columns

After the maps are ready, the worker fills only requested 16×16 chunk columns.
`get_generated_block_id()` also provides the same deterministic terrain without
materializing a chunk. Before mining first writes to an unmaterialized chunk,
the mining controller fills its original blocks from that getter.

Block evaluation keeps the existing bedrock Y0–3, foundation Y4–11, earth and
rock shelf bands, and resource replacement rules. Above the floor, a column's
own waterline decides water versus air. The six mountain shelves expose the
authored `rock06` through `rock01` materials. Cave air is checked before authored
strata in the real block getter. Concealed slice/overview queries omit both cave
air and floor-soil patches and return authored strata. Revealed cave faces use
the actual remaining material, including existing ore/gem veins. Optional cave
soil replaces floor rock only after gem/metal checks, so it does not erase veins.

**Review follow-up (2026-10-07):** surface diagnostics now count actual generated
blocks, and tin's threshold is corrected below copper's. See
[67 — World generation diagnostics](../00_dev_roadmap/67_world_generation_diagnostics.md).
The former unreachable cave fallback is replaced by the explicit cave pass in
[68](../00_dev_roadmap/68_caves_and_discovery.md). Integration tests check real
blocks, all six mountain materials, cave connectivity and mining discovery.

### Cave discovery

Mining a block adjacent to generated cave air reveals that whole connected cave
system. `InteriorTracker` publishes its air to rendering and lighting; this
does not create mined-block deltas for pre-existing air. Save/load reconstructs
discovery from the actual saved mining edits. The normal mining picker treats
hidden cave air as concealed strata, then removes now-empty designations after
discovery. A discovered cave provides walkable space and exposed mining leads;
it remains dark away from real entrances and installed lights. It does not yet
contain water, crops, creatures or loot.

### Resource Distribution (Ore, Gem, Cave Soil)

> Migrated from the original `00_dev_roadmap/02_resource_distribution_plan.md` (retired
> 2026-06-05; live calibration items in `00_dev_roadmap/12_worldgen_second_milestone.md`).
> Verified against `WorldGenerator._apply_resource_veins()` on retirement day.

**Source of truth for all bands, thresholds, and channels is
`data/terrain/block_resources.json`** (`depth_bias.min_y` / `max_y`, `noise_threshold`,
`noise_channel`, and ore `noise_field.seed_offset` / `frequency` / `octaves`).
Retuning existing resources requires only data changes; adding a resource also
requires registering its priority key. `WorldGenerator` copies the settings on
the main thread before building seeded noise on the generation thread; the
rarest-first evaluation order is fixed in `METAL_RESOURCE_KEYS` / `GEM_RESOURCE_KEYS` /
`SOIL_RESOURCE_KEYS`.

**Design goals (enduring guardrails for tuning):**

- **Depth identity / progression** — digging deeper yields better rewards.
- **Both dig routes pay off** — mining into the mountain face yields common industrial
  metals; tunneling down from valley/lowland floors is the express route to precious metals
  and gems.
- **Deterministic and seed-stable** — noise + position only, never unseeded random calls
  (Hard Rule 8).
- **Cheap** — resources layer onto rock blocks only; noise is sampled lazily.
- **Bedrock is inviolate** — nothing overwrites `Y0–3`.
- **Surface stays intact** — the override never replaces the visible surface skin; the
  replaceable set is `rock01`–`rock11` only, so grass, dirt caps, and soil bands are
  structurally protected.
- **Natural cliff faces stay readable** — resource overlays do not paint untouched exposed
  terrain walls.
- **World-edge perimeter stays concealed** — an 8-column suppression band keeps metals and
  gems off the outside slab.

> **Slice concealment (HARD rule, 2026-06-04):** the slice view never reveals undiscovered
> resources either — cut floors render authored strata only (the renderer uses the strata
> lookup, not the full generated block, for plane-cut tops). Veins, gems, and caves become
> visible exclusively through mining. See `24_world_rendering.md` §Slice concealment rule.

**Selection method** — `_apply_resource_veins(x, y, z, surf_y, rock_id)`, for each
sub-surface rock block:

1. Reject bedrock (`y <= 3`) and any block at or above the visible surface (`y >= surf_y`).
2. Reject non-replaceable blocks (only `rock01`–`rock11` are replaceable).
3. Reject world-edge perimeter columns (8-wide band).
4. Reject natural exposed wall blocks (any cardinal neighbour column with a lower surface),
   so untouched cliffs keep their authored strata.
5. Evaluate **gems** first, rarest to most common, on `noise_gem`.
6. Evaluate **metals** next, rarest to most common, each on its own seeded field.
   Skip fields outside their depth window; stop at the first qualifying metal.
7. Evaluate an added cave-floor soil patch, then **cave soil** on `noise_soil`.
8. Otherwise keep the authored rock.

**Independent metals (2026-10-08):** gold, silver, iron, copper and tin now use
separate fields at frequencies 0.055–0.070, producing smaller, distinct patches.
Coal keeps a broad 0.020 field. Each field uses simplex-smooth noise, two octaves
and a distinct fixed offset added to the world seed. Settings and cutoffs live in
the ore entries in `block_resources.json`; generation never fits them per seed.
First-match priority resolves spatial overlaps. Cutoffs need not descend between
independent fields, so copper no longer takes an entire interval from tin.
Depth windows, gems, priority, terrain and temporary drops remain unchanged.
See [71 — Independent ore fields](../00_dev_roadmap/71_independent_ore_fields.md)
for calibration, held-out measurements and integration checks. Connected bodies
can still contain thousands of blocks; there is no hard deposit-size cap.

**Shared gem/soil semantics:** each of these categories still uses a shared field
and the first window matching `(y in band, noise > threshold)` wins. Overlapping
entries on the same field therefore need strictly descending cutoffs to avoid
shadowing. Historical metal shadowing corrections (coal .62 and tin .64) are
recorded in docs 12/67; those were shared-field rules, not the current metal cutoffs.

**Gem correction (2026-10-08):** diamond and emerald both used 0.90, so diamond
captured every emerald candidate in their shared Y5–12 range. Diamond now uses
**0.91**, giving emerald `(0.90, 0.91]` there and reserving `>0.91` for diamond.
The gem thresholds now strictly descend: diamond .91, emerald .90, sapphire .89,
ruby .88, amethyst .82, jade .80. This intentionally reduces diamond abundance;
emerald's own threshold, all depth bands, priority order and drop rates are
unchanged. At Y4, removed diamond candidates become ordinary foundation rock.
See [69 — Resource distribution review](../00_dev_roadmap/69_resource_distribution_review.md)
for exact deep-gem counts and the original resource audit.

### Authored Rock Selection

Rock identity is chosen entirely by authored height shelves — there is no stone-type noise. Body rock comes from `_altitude_rock_body_id(y)`, mountain shelves from `_mountain_shelf_block_id(y)`, and Y4–11 is the hardcoded `rock11` foundation:

```gdscript
func _altitude_rock_body_id(y: int) -> StringName:
    if y >= 12 and y <= 19:
        return &"base:terrain:rock:rock10"
    if y >= 20 and y <= 27:
        return &"base:terrain:rock:rock09"
    if y >= 28 and y <= 35:
        return &"base:terrain:rock:rock08"
    if y >= 36 and y <= 43:
        return &"base:terrain:rock:rock07"
    return &"base:terrain:rock:rock10"

func _mountain_shelf_block_id(y: int) -> StringName:
    if y >= 44 and y <= 55:
        return &"base:terrain:rock:rock06"
    if y >= 56 and y <= 67:
        return &"base:terrain:rock:rock05"
    if y >= 68 and y <= 79:
        return &"base:terrain:rock:rock04"
    if y >= 80 and y <= 91:
        return &"base:terrain:rock:rock03"
    if y >= 92 and y <= 103:
        return &"base:terrain:rock:rock02"
    return &"base:terrain:rock:rock01"
```

### Phase 5b — Surface Skin

Authored strata decide the actual blocks before the legacy surface fallback.
Lowland and foothill shelf caps use grass; their lower earth bands and irregular
cut ledges expose dirt. Mountain shelves expose their authored rock. Dry banks
follow these same bands; they are not forced to dirt merely by water adjacency.
In wet columns the top visible block is water above the solid bed.

There are **8 active grass variants** (`grass_01`–`grass_08`) and **4 dirt
variants** (`dirt_01`–`dirt_04`). Lowlands use `grass_01`–`grass_04`; foothills
use `grass_05`–`grass_08`, with cap-band maps choosing the lighter edge variants.
`_pick_surface_block()` remains a fallback and must not be used to describe or
measure current authored surface coverage.

`_compute_surface_metrics()` evaluates `_generate_block_id()` at
`max(heightmap, waterline_map)` for every column, then counts material categories
globally and within each domain. The diagnostic is **top surface coverage**:
one visible block per column, including water, not cliff-face area or underground
material volume. It describes the generated world before player edits.

> **Agent note:** Do not use `randi()` or `randf()` for variant selection. Random calls are non-deterministic across chunk reloads and will cause visible seams when a chunk unloads and reloads with different variants. Deterministic hashing / region maps always return the same value for the same column.

---

### Generation Order Summary

Seed/profile → validated macro layout → height/domain/water column maps →
protected edge detail → final column validation → dry caves → maps ready → grass bands and
visible tile ranges → requested block columns. See Stage A/B above for the
actual ordering; the former noise-shaped compass layout has been removed.

## Collapse Safety Constraints

### Support Model

Each solid block has a **support score** derived from its load-bearing neighbours. A block becomes at risk of collapse when it is undermined beyond safe limits.

```
support_score = (solid_neighbours_below + solid_neighbours_lateral × 0.5)
collapse_threshold = 1.5
```

If `support_score < collapse_threshold` after a mining action, the block is flagged as **unstable**.

### Collapse Resolution

1. Unstable blocks wait `COLLAPSE_DELAY = 3.0` seconds (simulates crack propagation).
2. If not shored up (future: support pillar mechanic), the block falls:
   - Block is destroyed, dropping a `Rubble` item.
   - Cascade check: all neighbours above the fallen block are re-evaluated.
   - Falling blocks deal damage to any dwarf agent in the target cell.
3. Large cascades (> 20 blocks) emit `WorldData.collapse_event(epicenter: Vector3i, block_count: int)`, triggering a CRITICAL toast.

### Mining Safety Checks

Before issuing any `MINE` task, `TaskManager` must run a pre-flight safety check:

```gdscript
func is_safe_to_mine(pos: Vector3i) -> bool:
    if pos.y <= 3: return false                      # bedrock protocol
    var score := compute_support_score(pos)
    return score >= collapse_threshold               # or warn if borderline
```

If the check returns `false`, the task is not queued and the player receives a WARN toast: *"Mining here risks a collapse."*

---

*Prev: [42_farming_brewing.md](./42_farming_brewing.md) | Next: [51_visitors.md](../50_world_events/51_visitors.md)*
