# 13 - Flora Scatter: Pine (First Pass)

Status: **in progress** — first surface-flora placement system. Created 2026-06-06.
Implements the pine slice of `12_worldgen_second_milestone.md` §2 (*Scatter maps for flora
and boulders*), scoped to **pine only**, structured to extend to oak / juniper / apple.

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

`61_voxel_art_guide.md` states 1 block = 0.5 Godot units (export scale 0.0625). **The live
renderer does not follow this** — `ChunkMesher`/`WorldRenderer` emit one block as a **1.0-unit**
cube (quads at `ox+1`, chunk nodes at `cx*16`), and the camera centres at x=512 for the
1024-block world. So in the running game **1 block = 1 Godot unit**.

The pine GLBs are authored in MagicaVoxel-voxel units with `.import` `root_scale = 1.0` (and
`.import` files must never be hand-edited — File Ownership Rules). The spawner therefore applies
the scale itself, as a single tunable:

```
instance_scale = godot_units_per_block / voxels_per_block      # 1.0 / 8.0 = 0.125
```

At 0.125 a mature pine's 16-voxel trunk box reads as 2 blocks wide — matching the 2×2
footprint. **This 0.125 is the number most likely to need an in-engine nudge**; it is one
exported field (`voxels_per_block`) on the spawner, "one number in one place".

Tree origin: trunk base sits on the **top face** of the surface block. `get_surface_y` returns
the index of the topmost solid block; its top face is at world `y = surface_y + 1`, so the
instance is placed there.

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
2. **Scale** — a mature pine is ~2 blocks wide / ~8 tall. If it's 8× too big, set
   `voxels_per_block` higher (the GLBs are at voxel scale); if too small, lower it.
3. **Elevation** — pines blanket foothills and lower mountain, thin out approaching the
   peaks, vanish above ~Y90, and **none** appear on the lowland/settlement plain or in water.
4. **Determinism** — same seed → identical forest across two launches.
5. **Streaming** — pines appear/disappear with the camera radius without leaking nodes
   (watch node count while panning).
6. **Material** — needles render in their baked green, unlit and flat (not pink/untextured,
   not lit-and-shaded).
7. **Slice/overview** — confirm pines behave acceptably in the slice view (they are scene
   objects, not terrain; they do not obey the slice plane yet — note if culling is wanted).

---

## 9. Out of scope (future passes)

- Other species (oak valley groves, juniper, apple orchards) — reuse this spawner's resolver,
  scale, material, and streaming; add their own `placement` blocks.
- Growth over time (sapling → mature → ancient via `WorldClock`), planting tasks, felling/
  harvest tasks — those belong to the task/agent systems.
- Pines obeying the slice plane (hide trees above the cut), boulders/scree, lake-bank reeds.
- Snow caps / cold high-altitude stone (open question in doc 12 §3) pairs naturally with the
  treeline defined here.
