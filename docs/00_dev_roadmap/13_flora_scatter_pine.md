# 13 - Flora Scatter: Pine (First Pass)

Status: **shipped 2026-06-06; placement generalized by `14_flora_distribution_plan.md`.** This was
the first surface-flora placement system (pine only). Doc 14 then generalized `SurfaceFloraSpawner`
into a multi-species moisture + niche selector, so the **placement strategy here is superseded** (§2).
**13 remains the conventions reference** — the scale rule (§5/§5.1), material (§6), collision + the
camera Layer-2 gotcha (§7), and determinism (§3) — which all flora inherit and 14 does not repeat.
Implements the pine slice of `12_worldgen_second_milestone.md` §2.

This is the first system in the project that spawns **placed entities** (GLB world objects)
into the live scene. Until now the world was terrain-only. The pine spawner therefore also
establishes the conventions every later flora/prop spawner inherits: the canonical model
variant resolver, the spawn-time scale rule, the unlit vertex-colour material, and the
camera-radius streaming lifecycle.

---

## 1. Goal

Place pine trees in the world **by elevation**: dense on the foothill shelves and lower
mountain slopes, thinning to a bare-rock treeline near the peaks, and **never on the lowland
shelf or settlement plain**. Pine is the "elevation tree" and the early-game construction
lumber supply.

Decision recorded with the user (2026-06-06):

| Question | Decision |
|---|---|
| Mountain density profile | Full density on foothills + lower mountain (to ~Y75), linear falloff Y75–90, hard cutoff ~Y90 (bare rock above). |
| Footprint | Mature **2×2**, Ancient **3×3** (sapling 1×1 / clutter). |
| Scope | Pine-only, extensible. |

---

## 2. Elevation strategy

> **Superseded for placement by `14_flora_distribution_plan.md` §5.** The pine-only elevation bands
> and single `spawn_chance` below were the first pass; placement is now a unified multi-species
> per-cell selector driven by elevation **and** a moisture channel. Pine's `spawn_chance` survives as
> its `base_density` fallback, and the bands here still describe pine's niche — but the live selection
> logic lives in 14. The scale/material/collision/determinism sections (§3, §5–§7) remain current.

Bands come straight from `WorldGenerator.gd` surface-elevation constants and the domain
classification. Pine reads the **terrain surface Y** (`get_surface_y`, the solid top — not the
waterline) and the **domain** of each column.

| Terrain band | Surface Y | Domain | Pine density |
|---|---|---|---|
| Lowland shelf / settlement plain | 12–19 | lowland (0) | **none** |
| Valley corridor (future trade road) | 20–27 | valley/foothill (1) | sparse — corridor itself left clear |
| Foothill shelves | 20–43 | valley/foothill (1) | **full** |
| Lower mountain | 44–75 | mountain (2) | **full** |
| Treeline falloff | 75–90 | mountain (2) | linear ramp full → 0 |
| High peaks | 90–115 | mountain (2) | **none** (bare rock; future snow caps) |

All thresholds live in `data/entities/flora/pine_tree.json` → `placement`, not in code:

```
domains            : ["foothill", "mountain"]   # whitelist; "lowland" excluded
min_surface_y      : 20      # below this = lowland; reject
full_density_max_y : 75      # full density up to here
falloff_max_y      : 90      # density reaches zero here; reject at/above
scatter_cell_size  : 5       # blocks per scatter cell (≤1 tree/cell)
spawn_chance       : 0.40    # P(full-density cell has a pine), pre-falloff
max_surface_slope  : 1       # reject footprint if column surface Y spread > this
edge_margin        : 2       # ring (blocks) around footprint checked for drops; 0 disables
edge_dropoff_max   : 3       # reject if a ring column is off-world or drops > this below trunk
footprint          : sapling 1, mature 2, ancient 3
stage_weights      : sapling 0.15, mature 0.60, ancient 0.25
```

`scatter_cell_size` (bigger = sparser) and `spawn_chance` (lower = sparser) are the density
dial; `edge_margin` / `edge_dropoff_max` set how far trees are kept back from cliff lips and
the world border so their wider canopies don't overhang a drop. All are JSON edits — no code
change.

---

## 3. Determinism (Hard Rule 8)

Every placement decision is a pure function of `WorldGenerator.world_seed` and the column XZ.
No `randi()`/`randf()`. The world is divided into `scatter_cell_size`-block cells; each cell
holds at most one candidate pine. For a cell the spawner hashes `(seed, cell_x, cell_z)` to
derive, in order:

1. **presence** — compare a hashed `[0,1)` value against `spawn_chance × falloff_factor`.
2. **jittered position** — the block within the cell where the trunk sits.
3. **stage** — weighted pick over `stage_weights`.
4. **model variant** — `resolve_tree_model_for_season` (the canonical resolver, §5).

The same seed reproduces the same forest every load, with no save data, matching how terrain
identity is reproduced.

---

## 4. Architecture — `SurfaceFloraSpawner`

`scripts/systems/SurfaceFloraSpawner.gd` (`class_name SurfaceFloraSpawner`, extends `Node3D`),
added to `scenes/main/debug_world.tscn` as a sibling of the `Renderer`, positioned at the
origin so child tree positions are world coordinates.

Responsibilities (it **owns** its data loading, the same pattern `VisitorManager` uses for the
merchant catalog — no separate registry autoload):

- Load `data/entities/flora/pine_tree.json` (extensible to the whole flora dir).
- Host the canonical `static func resolve_tree_model[_for_season]` (the design contract in
  `42_farming_brewing.md` mandates **exactly one** resolution point — it lives here).
- Arm once `WorldGenerator` reports `maps_ready` (height + domain maps built); the spawner
  polls this in `_process` rather than relying on signal ordering with the renderer that
  kicks off the threaded generation.
- **Coverage — whole map by default** (`cover_whole_map = true`). The world is an RTS
  *overview*: terrain renders edge-to-edge, so flora must too, or trees appear to "follow" the
  camera. In whole-map mode every chunk-column is queued once (nearest-camera-first) and
  drained over several frames by `spawn_budget_per_frame`; nothing is ever despawned. Tracked
  in `_loaded_columns: Dictionary[Vector2i → Array[Node3D]]`.
  - A `cover_whole_map = false` fallback keeps the original **camera-radius streaming**
    (`view_radius_chunks`, spawn on enter / free on leave) for a future close/first-person
    camera where only nearby trees need to exist.
- Per spawned tree: instance the GLB, apply the spawn-time scale (§5) and the unlit
  vertex-colour material (§6), and add a `StaticBody3D` + `BoxShape3D` for mature/ancient
  (none for saplings — Hard Rule 5 / clutter; collision can also be globally disabled via
  `enable_collision` while the world has no agents and thousands of trees exist).
- Re-resolve models on `WorldClock.season_changed` (pine only flips summer ⇄ winter).

The spawner needs the column's domain. A small public getter `get_domain(wx, wz) -> int` was
added to `WorldGenerator` (alongside the existing `get_surface_y` etc.); it returns the
`DOMAIN_*` constant or `-1` before maps are ready.

---

## 5. Scale (important — project scale is inconsistent on paper)

The live renderer draws **1 block = 1 Godot unit** — `ChunkMesher`/`WorldRenderer` emit one
block as a 1.0-unit cube (quads at `ox+1`, chunk nodes at `cx*16`), camera centred at x=512 for
the 1024-block world. (An earlier `61_voxel_art_guide.md` "universal" rule said 1 block = 0.5
units / export scale 0.0625; that was wrong for the live world and has been corrected — see doc
61's per-class scale table.)

**Trees are authored 1:1 — 1 voxel = 1 block** (`tools/generate_pine_glbs.py`,
`VOX_PER_BLOCK = 1`), the Stonehearth tree convention (their trees render at scale 1.0, one model
voxel per terrain block). `.import` `root_scale = 1.0` (never hand-edit `.import`); the spawner
applies the scale:

```
instance_scale = godot_units_per_block / voxels_per_block      # 1.0 / 1.0 = 1.0
```

At scale 1.0 each model voxel is one terrain block, so the GLB's voxel height *is* its block
height — ancient 27 / mature 20 / sapling 8. The spawner's `voxels_per_block` **must equal** the
generator's `VOX_PER_BLOCK` (both 1); kept in sync by hand. This is the deliberate
trees-coarser-than-people split Stonehearth uses (their trees 1/block, characters 10/block; ours
trees 1/block, characters/items 8/block) — it also makes the trees tiny on disk (~2 MB for all 12
pines vs ~28 MB at 3/block). Characters/items keep 8 voxels/block via their own import scale.

Tree origin: trunk base sits on the **top face** of the surface block. `get_surface_y` returns
the index of the topmost solid block; its top face is at world `y = surface_y + 1`, so the
instance is placed there.

---

## 5.1 Size baseline & targets (Stonehearth-matched)

The pines currently read as too small in-engine — even an ancient. To set a defensible
target we measured the reference game in `P:\stonehearth` (a Stonehearth mod tree: same
genre, same stylised voxel look) and compared its pines to its people.

**How Stonehearth scales models.** Per its own modding guide
(`docs/modding_guide/.../item_scale`), the default render scale is **0.1** (1 model voxel =
0.1 terrain block), and **trees and boulders override to `scale: 1`** (1 voxel = 1 full
terrain block). Hearthlings stay at 0.1 — the guide notes "their face is 13 voxels wide…
they barely occupy more than one terrain block of width," which matches the `.qb` files
exactly. Measuring the actual Qubicle voxels and applying each entity's real scale:

| Stonehearth model | Voxels (H × W) | Scale | World size (H × W, blocks) | × hearthling height |
|---|---|---|---|---|
| Hearthling (male) | 32 × 13 | 0.1 | 3.2 × 1.3 | 1.0× |
| Sapling pine | 12 × 7 | 0.7 | 8.4 × 4.9 | 2.6× |
| Medium pine | 20 × 9 | 1.0 | 20 × 9 | 6.3× |
| Large pine | ~27–30 × 15 | 1.0 | ~27 × 15 | ~8.4× |

**The anchor that makes this transferable:** a Stonehearth hearthling (~3.2 blocks tall) is
essentially identical to the Deepdraft dwarf (3.3 blocks visual, `41_dwarf_agents.md`). The
people are the same size, so Stonehearth's tree-to-person ratios map straight onto our
dwarf — and the wide canopy is purely visual (its gameplay collision footprint is only
~5×5), which is consistent with Hard Rule 5 (plant overhangs carry no collision).

**Adopted Deepdraft pine targets (Stonehearth-matched):**

| Stage | Target height | Target canopy width | × dwarf (3.3 blk) | Delivered (2026-06-06) |
|---|---|---|---|---|
| sapling | **~8 blocks** | ~5 blocks | ~2.4× | 8.0 × ~5.5 ✓ |
| mature (≈ SH medium) | **~20 blocks** | ~9 blocks | ~6× | 20.0 × ~9 ✓ |
| ancient (≈ SH large) | **~27 blocks** | ~15 blocks | ~8× | 27.0 × ~16 ✓ |

> Note: Stonehearth has only three stages and its "sapling" is still a sizeable ~8-block
> young tree, not a knee-high seedling. We adopt that here for visual parity; if a true
> seedling stage is wanted later it should deviate below this ratio deliberately.

**Delivered.** `tools/generate_pine_glbs.py` (new, 2026-06-06) authors all 12 pine GLBs as a
simple Stonehearth-style **stepped conifer** (bare reddish trunk, a stack of flat needle whorls
narrowing to a point with 1-block gaps the trunk peeks through, two-tone greens, snow-frosted
winter variants) at the sizes above. It supersedes the old pines (produced by a script not in the
repo, ~3× short). Key conventions baked in: **authored 1:1, 1 voxel = 1 block** (`VOX_PER_BLOCK = 1`,
paired with the spawner's `voxels_per_block = 1.0`, scale 1.0 — see §5 and doc 61); centred on the
trunk at X=Z=0 with the base at Y=0 (matches `_instance_tree`'s origin); trunk width tracks the
1 / 2 / 3-block footprints, canopy is visual overhang only. The whole set is ~2.3 MB (ancient
~340 KB, ~3.8k tris) — the 1:1 grid keeps trees cheap. Collision stays small — footprint XZ ×
`clearance_height` Y (`pine_tree.json`: sapling 6 / mature 16 / ancient 22). Density is JSON-only
(`scatter_cell_size` 16, `spawn_chance` 0.33).

Source: Stonehearth modding guide, *Changing the item scale*
(`P:\stonehearth\docs\modding_guide\modding_guide\basic\adding_items\item_scale\index.html`);
model dimensions read from the `.qb` files under `P:\stonehearth\entities\`.

---

## 6. Material

Imported GLBs carry per-vertex colour (`COLOR_0`) and no texture. The spawner assigns a
`material_override` to every `MeshInstance3D` in the instance that **matches the terrain
material** (`WorldRenderer._create_material()`):

```
StandardMaterial3D:
  vertex_color_use_as_albedo = true
  cull_mode    = CULL_DISABLED          # double-sided
  shading_mode = SHADING_MODE_PER_PIXEL # lit
```

This is a deliberate departure from `61_voxel_art_guide.md`, which specs world objects as
`unshaded, cull_back`. That spec predates the lit, double-sided terrain material and produced
two artifacts on the canopy: **double-siding** (`CULL_DISABLED`) stops the thin/sparse leaf
shell from showing see-through "missing" back faces, and **lighting** (`PER_PIXEL`) makes the
voxel facets read as 3D under the sun instead of a flat green blob — so trees now match the
ground. The art guide should be reconciled to this. Tradeoff: `CULL_DISABLED` ~doubles canopy
triangles, but terrain already runs this way; revisit only if it costs too much at scale.

World assets use no runtime `tint` uniform (their colours are baked).

---

## 7. Collision

Per `42_farming_brewing.md`, trees are the only surface entities with real collision.

- **Sapling** — none (clutter).
- **Mature / Ancient** — `StaticBody3D` + `BoxShape3D`, XZ = footprint (2 or 3 blocks),
  height = the stage's `clearance_height` blocks, resting on the ground. Dwarves (not yet in
  the world) will path around it. Can be globally disabled via `enable_collision`.

> **Layer gotcha (do not put trees on Layer 1).** The RTS camera's `SpringArm3D` forces
> `collision_mask = 1` and collides against **terrain only** to avoid clipping (`Camera.gd`,
> comment: "Do not collide with dwarves or items"). Tree colliders therefore live on **Layer
> 2** (`tree_collision_layer`). On Layer 1 the spring arm treats every tree as terrain and, on
> a quick pan, snaps the camera down onto a tree at the surface — the y≈79 "zoom" glitch.

---

## 8. In-engine verification checklist

This system could not be run in the authoring environment. Open the project in Godot and
confirm:

1. **Parse/load** — no GDScript or scene errors on launch; `SurfaceFloraSpawner` prints its
   loaded-pine count after `grass_bands_ready`.
2. **Scale** — confirm the §5.1 targets in-engine (ancient 27 / mature 20 / sapling 8 blocks
   tall; canopy 15 / 9 / 5 wide) against a 3.3-block dwarf. Trees are authored 1:1, so the
   spawner's `voxels_per_block` must read **1.0** and each model voxel is exactly one terrain
   block. If everything is uniformly off, that one field is the dial.
3. **Elevation** — pines blanket foothills and lower mountain, thin out approaching the
   peaks, vanish above ~Y90, and **none** appear on the lowland/settlement plain or in water.
4. **Determinism** — same seed → identical forest across two launches.
5. **Streaming** — pines appear/disappear with the camera radius without leaking nodes
   (watch node count while panning).
6. **Material** — needles render in their baked green, unlit and flat (not pink/untextured,
   not lit-and-shaded).
7. **Slice/overview** — pines now obey the slice plane: `SurfaceFloraSpawner` hides trees whose
   base is above the cut (shipped 2026-06-07; coarse per-instance toggle, `11_slice_xray_plan.md`
   Phase 5). Confirm trees above the active cut disappear and reappear as it is raised/lowered.

---

## 9. Out of scope (future passes)

- Other species (oak valley groves, juniper, apple orchards) — reuse this spawner's resolver,
  scale, material, and streaming; add their own `placement` blocks.
- Growth over time (sapling → mature → ancient via `WorldClock`), planting tasks, felling/
  harvest tasks — those belong to the task/agent systems.
- ~~Pines obeying the slice plane (hide trees above the cut)~~ — **done 2026-06-07** (coarse
  base-Y cull, `11_slice_xray_plan.md` Phase 5; a per-prop clip-plane is the optional clean
  follow-up). Still future: boulders/scree, lake-bank reeds.
- Snow caps / cold high-altitude stone (open question in doc 12 §3) pairs naturally with the
  treeline defined here.
