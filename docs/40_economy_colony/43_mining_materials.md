# 43 — Mining & Materials

## Overview

Mining is the primary expansion mechanic. Dwarves remove solid blocks, depositing raw materials into nearby stockpiles. The geological composition of the mountain is procedurally generated and affects resource yield, structural stability, and collapse risk.

## Geological Spectrum

| Block Key | Category | Hardness | Yield | Notes |
|---|---|---|---|---|
| `base:terrain:rock:rock01`-`rock06` | Mountain rock | 3 | Stone TBD | Authored mountain shelves |
| `base:terrain:rock:rock07`-`rock10` | Body rock | 3 | Stone TBD | Valley/foothill body bands |
| `base:terrain:rock:rock11` | Foundation rock | 3 | Stone TBD | Stable band above bedrock |
| `base:terrain:ore:iron`       | Ore        | 4 | 2× Iron Ore           | Common ore |
| `base:terrain:ore:copper`     | Ore        | 3 | 2× Copper Ore         | Shallow, early-game |
| `base:terrain:ore:gold`       | Ore        | 5 | 1× Gold Ore           | Deep, rare |
| `base:terrain:gem:ruby`       | Gem        | 5 | 1× Ruby               | Very rare, high trade value |
| `base:terrain:soil:cave`      | Soil       | 1 | 1× Soil               | Farmable (see `42_farming_brewing.md`) |
| `base:terrain:bedrock`        | Bedrock    | ∞ | None                  | **Unmovable — Y=0..3 protocol** |

**Hardness** determines mining time: `mine_time = base_time × hardness / dwarf_mining_skill`.

`base_time = 2.0` seconds at skill 1 on hardness 1.

## Mining Tools

The player designates mining regions using two tools. Both tools create a **mining zone entity** that persists in the world until the work is complete. Dwarves path to the zone's adjacent cells and mine blocks one at a time from the zone's destination region.

> **Verified against Stonehearth source:** `stonehearth_client.js` wires `mineBasic` → `designate_mining_zone('cube')` and `mineCustom` → `designate_mining_zone('custom_block')`. Constants: `XZ_CELL_SIZE = 4`, `Y_CELL_SIZE = 5`, `MAX_WORKERS = 4` per zone. The cell alignment uses floor/ceil snapping to always expand to a full cell boundary.

---

### Tool 1 — Dig (Large, Grid-Snapped)

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

### Tool 2 — Precision Dig (Variable, 1-Block Minimum)

A single-block tool for surgical work: finishing a room corner, punching a doorway, clearing one specific block. Starts at 1×1×1 and is resized interactively before confirming.

| Control | Effect |
|---|---|
| Shift + MouseWheel up/down | Expand/shrink horizontal extent (X and Z), 1–8 blocks |
| Alt + MouseWheel up/down | Expand/shrink vertical extent (Y), 1–8 blocks |
| Right-click | Cancel |

The selection is anchored at the clicked face normal — the region grows away from the face the player pointed at. There is no grid snapping. The region is always exactly the size shown.

This tool is intentionally slower to use than the Dig tool. A 1×1×1 precision dig is for fine work; players who want to carve a room should use the Dig tool.

---

### Mining Zone Entity

Both tools produce the same kind of mining zone entity in the world. Key properties:

- **Region**: the designated block volume to be mined, stored as a `Region3i`.
- **Destination**: the subset of the region that dwarves can currently reach and mine (updated each time terrain changes within the zone).
- **Max workers**: **4 dwarves** may work the same zone simultaneously. Additional dwarves are rerouted to other tasks.
- **Enabled/disabled**: the player can pause a zone without deleting it. The zone persists until all blocks in it are mined or it is manually deleted.
- **Render**: the zone boundary is drawn as a coloured region outline overlay — it is not part of the terrain mesh.

When a dwarf mines the last block in a zone, the zone entity is automatically destroyed.

---

### Worker Assignment Flow

```
1. Player designates zone → MiningZoneComponent created, region set
2. TaskSystem sees open zone → posts MINE tasks up to MAX_WORKERS (4)
3. Each dwarf: path to zone adjacent cell → mine one block → loop
4. On each block mined: WorldGrid removes block, drops item entity, emits chunk_changed
5. MiningZoneComponent.update_destination() recalculates reachable blocks
6. When zone.region is empty: zone entity destroyed, tasks cancelled
```

---

## World Design Intent (North Star)

> Migrated from the original `00_dev_roadmap/01_world_gen_plan.md`. These are the enduring
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

Plains/settlement areas vary only 0–2 blocks locally; foothills step in **8-block shelves**;
mountains step in **12-block shelves**. If a later idea fights this rule, this rule wins.

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
domain: lower plains / settlement use `grass_01`–`grass_04`; valley / highland / foothill use
`grass_05`–`grass_08`. Within a domain, a calm base grass fills the interior and lighter
variants trace patch edges and terrace lips — region-aware outlining, never per-block noise.

### Core world composition (authored macro layout)

The map uses an authored macro layout before local noise:

| Region | Footprint | Height | Character |
|---|---|---|---|
| **Northwest mountain** | NW mass | Y44–115 (12-block shelves) | The main dig-in face and visual anchor; broad stepped shelves, strong exposed stone, sparse sheltered pockets on low ledges. |
| **Central valley corridor** | mid-map | Y20–27, plain ~Y27 | One dominant settlement plain (≥80×80 mostly-flat, 0–2 block variation); grass/dirt/rock/road-ready soil mix. |
| **Foothill band** | valley↔mountain | Y20–43 (8-block terraces at Y20/28/36) | Stepped, not noisy; mixed grass/dirt/rock. Where readable shelves matter most. |
| **Southwest lake basin** | SW, south edge | ground ~Y20–27; lake floor Y11, water Y12–18 | Macro-cell lake touching the south map edge; dirt/mud/stone banks, never grass at the waterline. |
| **Southeast highland** | SE | Y20–43 | A smaller, calmer forest plateau; broad shelves for later forest scatter. |
| **World-edge wilderness** | outer 20–30 blocks | rises/roughens | Denser near the boundary; block identity must never depend on fog or camera distance. |

> **Design reference (Stonehearth).** The original plan reviewed `services/server/world_generation/`
> and `data/biome/*_generation_data.json`. The lessons Deepdraft kept: large readable landforms
> over noisy detail; broad flat terraces for legible settlement choice; elevation changes as
> strong terrace drops (~8 blocks foothill, ~12 mountain) rather than slopes; soil strata
> alternating in 2-block bands for readable side walls; grass edges deliberately lighter than
> interiors; water biased toward flat ground; props placed as scatter entities after terrain.
> Deepdraft uses tuned equivalents of Stonehearth's step sizes but shares no assets or data.

---

## World Generation Pipeline

### Overview

The world is generated once at new-game time, driven entirely by `world_seed`. All phases are fully deterministic — the same seed always produces the same mountain silhouette, valley shape, and lake position.

Generation runs in **two stages on a background thread**:

**Stage A — 2D map passes (run once when `generate(seed)` is called):**

1. Build the noise instances
2. Compute terrain domain map (2D - classifies every column as mountain, valley, or lowland; then macro coherence cleanup)
3. Compute surface heightmap (2D - macro-cell terraces, plateau smoothing, mountain/lowland transitions, shelf step limits)
4. Carve both lake bodies into the heightmap (macro-cell lowland lake + single-cell mountain tarn)
5. Apply final shelf edge detail, then build the cap-grass band maps and generation metrics
6. Mark `_maps_ready = true`

**Stage B — on-demand column streaming:**

After the maps are ready, blocks are **not** filled all at once. The worker enters `_process_requested_columns()` and fills 3D blocks only for the 16×16 XZ chunk columns the renderer asks for, via `request_chunk_column(cx, cz)` as the camera moves. Each phase reads data produced by prior phases.

> **Public API (`WorldGenerator` autoload).** `generate(seed)`, `is_generating()`, `request_chunk_column(cx, cz)`, `get_streaming_stats()`, `get_generation_metrics()`, plus surface queries `get_surface_y()`, `get_visible_surface_y()`, `get_visible_surface_block_id()`, `get_column_top_y()`, `get_generated_block_id()`, `get_column_debug_info()`.
>
> **Signals.** `chunk_generated(cx, cy, cz)` and `world_complete()` both fire deferred from the worker thread — connect with `CONNECT_DEFERRED`. There is no `maps_ready` *signal*; the renderer polls `get_streaming_stats()` / `is_generating()` instead.

> **Agent note:** Use separate `FastNoiseLite` instances per logical layer, each with its own seed offset. Never reuse or reconfigure a single instance across passes - it is error-prone and makes the code unreadable.

Macro domain cleanup happens before height assignment. A 32x32 lowland macro cell now needs a real lowland majority; isolated non-anchor lowland cells with no cardinal lowland neighbor are promoted to valley. This prevents single lowland plates from appearing in the middle of foothill shelves while preserving the authored southwest basin and settlement/plain anchors.

The final edge-detail pass is intentionally narrow. It applies only to foothill shelves 1-3 and mountain shelves 1-6, after lake carving and shelf cleanup. It pushes shallow blocky ledges into exactly one lower cardinal neighbor direction, skips lowland/settlement/water columns, and keeps the pushed height inside the source shelf band so existing dirt/grass and rock strata remain valid.

---

### Terrain Domains

Three terrain domains drive surface character across the map:

| Domain | `domain_n` range | Surface Y range | Character |
|---|---|---|---|
| **Mountain** | > 0.60 | 44 – 115 | Jagged ridge shelves. The dwarves' homeland; primary dig-in faces. |
| **Valley / Foothills** | 0.35 – 0.60 | 20 – 43 | Wide flat basin, farmland, trade road corridor, and stepped foothill shelves. |
| **Lowland** | < 0.35 | 12 – 19 | Lowest ground. Lake basin, river mouth, open wilderness floor. |

Transitions between domains are **blended** — a column near the mountain/valley border lerps between the two height targets, producing natural slopes rather than hard cliff edges. There are no abrupt vertical walls between biomes.

---

### World Seed

`world_seed` is a signed 32-bit integer stored in the save file header at new-game time. All 6 noise instances derive from it via fixed offsets (`+1` ore, `+2` cave, `+3` soil, `+4` domain, `+5` mountain, `+6` valley). Two games with the same seed always produce identical worlds.

```gdscript
func _new_game_setup(player_seed: int = 0) -> void:
    world_seed = player_seed if player_seed != 0 else randi()
    # Write world_seed to save file header before generation begins.
    # It must be read back and restored exactly on every subsequent load.
```

Passing `0` generates a random seed via `randi()`. Any non-zero value reproduces a specific world. Display the seed in the New Game UI and in the pause menu so players can share worlds.

---

### Noise Instance Configuration

There are **six** noise instances — one per logical layer. There is **no `noise_stone`** layer: rock identity is chosen by authored altitude bands (see *Authored Rock Selection* below), not by noise.

```gdscript
# WorldGenerator.gd  (called once when generate() starts, before any chunk work)

func _build_noise_instances() -> void:

    # Layer 1 — Ore vein mask
    # Medium frequency, fewer octaves → thin vein shapes.
    noise_ore = FastNoiseLite.new()
    noise_ore.noise_type        = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
    noise_ore.seed              = world_seed + 1
    noise_ore.frequency         = 0.02
    noise_ore.fractal_octaves   = 2

    # Layer 2 — Cave void mask
    # Medium-low frequency, more octaves → organic cave networks.
    noise_cave = FastNoiseLite.new()
    noise_cave.noise_type       = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
    noise_cave.seed             = world_seed + 2
    noise_cave.frequency        = 0.015
    noise_cave.fractal_octaves  = 4

    # Layer 3 — Soil patch mask (also drives surface dirt fraction via a 2D query)
    # Higher frequency, smooth → small irregular farmable soil pockets.
    noise_soil = FastNoiseLite.new()
    noise_soil.noise_type       = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
    noise_soil.seed             = world_seed + 3
    noise_soil.frequency        = 0.03
    noise_soil.fractal_octaves  = 2

    # Layer 4 — Terrain domain map
    # Very low frequency, large scale → broad mountain / valley / lowland zones.
    noise_domain = FastNoiseLite.new()
    noise_domain.noise_type      = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
    noise_domain.seed            = world_seed + 4
    noise_domain.frequency       = 0.0015
    noise_domain.fractal_octaves = 2

    # Layer 5 — Mountain ridge detail
    # Ridge noise (absolute value of simplex, inverted) → sharp peaks and narrow spines.
    noise_mountain = FastNoiseLite.new()
    noise_mountain.noise_type      = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
    noise_mountain.seed            = world_seed + 5
    noise_mountain.frequency       = 0.006
    noise_mountain.fractal_octaves = 5

    # Layer 6 — Valley / lowland floor detail
    # Low amplitude, gentle rolls → subtle variation in otherwise flat ground.
    noise_valley = FastNoiseLite.new()
    noise_valley.noise_type      = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
    noise_valley.seed            = world_seed + 6
    noise_valley.frequency       = 0.012
    noise_valley.fractal_octaves = 2
```

---

### Phase 1 — Domain Map (2D)

Classify every column as mountain, valley, or lowland before computing any heights. Store both the integer domain and the raw float value; the float is needed for smooth blending at borders.

```gdscript
const DOMAIN_MOUNTAIN := 2
const DOMAIN_VALLEY   := 1
const DOMAIN_LOWLAND  := 0

# domain_map:   flat Array[int],   indexed [x * WORLD_SIZE_Z + z]
# domain_n_map: flat Array[float], stores raw noise value for blend math

func _compute_domain_map() -> void:
    for x in range(WORLD_SIZE_X):
        for z in range(WORLD_SIZE_Z):
            var n := (noise_domain.get_noise_2d(x, z) + 1.0) * 0.5    # remap to [0, 1]
            domain_n_map[x * WORLD_SIZE_Z + z] = n
            if   n > 0.60: domain_map[x * WORLD_SIZE_Z + z] = DOMAIN_MOUNTAIN
            elif n > 0.35: domain_map[x * WORLD_SIZE_Z + z] = DOMAIN_VALLEY
            else:          domain_map[x * WORLD_SIZE_Z + z] = DOMAIN_LOWLAND
```

---

### Phase 2 — Surface Heightmap (2D)

Each column's surface elevation is computed from its domain, with smooth blending in border transition bands:

```gdscript
const MOUNTAIN_MIN := 44;  const MOUNTAIN_MAX := 115
const VALLEY_MIN   := 20;  const VALLEY_MAX   := 27
const LOWLAND_MIN  := 12;  const LOWLAND_MAX  := 15

func _compute_heightmap() -> void:
    for x in range(WORLD_SIZE_X):
        for z in range(WORLD_SIZE_Z):
            var idx := x * WORLD_SIZE_Z + z
            var n   := domain_n_map[idx]
            var height_f: float

            if n > 0.60:
                # Mountain zone — ridge noise: abs(simplex) inverted gives sharp peaks.
                var ridge := 1.0 - abs(noise_mountain.get_noise_2d(x, z))
                height_f  = lerp(float(MOUNTAIN_MIN), float(MOUNTAIN_MAX), ridge)
                # Blend into valley in the 0.60–0.70 transition band.
                if n < 0.70:
                    var t := (n - 0.60) / 0.10    # 0 at border, 1 deep in mountains
                    height_f = lerp(_valley_height(x, z), height_f, t)

            elif n > 0.35:
                # Valley zone — gentle detail, stays flat.
                height_f = _valley_height(x, z)
                # Blend into lowland in the 0.35–0.45 transition band.
                if n < 0.45:
                    var t := (n - 0.35) / 0.10
                    height_f = lerp(_lowland_height(x, z), height_f, t)

            else:
                # Lowland zone.
                height_f = _lowland_height(x, z)

            heightmap[idx] = int(height_f)

func _valley_height(x: int, z: int) -> float:
    # Low amplitude — valley floors stay close to flat.
    var detail := (noise_valley.get_noise_2d(x, z) + 1.0) * 0.5
    return lerp(float(VALLEY_MIN), float(VALLEY_MAX), detail * 0.4)

func _lowland_height(x: int, z: int) -> float:
    # Offset z by 1000 so lowland detail doesn't mirror the valley pattern.
    var detail := (noise_valley.get_noise_2d(x, z + 1000) + 1.0) * 0.5
    return lerp(float(LOWLAND_MIN), float(LOWLAND_MAX), detail * 0.3)
```

---

### Phase 3 — Lake Bodies (Lowland Lake + Mountain Tarn)

Two lake bodies are carved in this phase. Both are built from whole **32×32 macro cells**, not circular bowls — this keeps them in the same macro language as the rest of terrain generation. `_carve_lakes()` carves the lowland lake, runs the macro shelf step limiter, then writes the single-cell mountain tarn as a final macro carve. Column sets (`lake_columns`, `tarn_columns`) are stored for water placement during column fill.

**Lowland lake** (`_southern_lowland_lake_macro_cell`, `_lake_macro_cell_is_eligible`, `_apply_lowland_lake_macro_cell`):
- Selected from eligible lowland macro cells, then expanded to at least `LAKE_MIN_MACRO_CELLS` (12) cells via `_expand_lake_to_minimum_macro_cells`.
- Forced into the lowland band: **floor Y11**, water fills **Y12–Y18** (`LAKE_WATERLINE = 18`, `LAKE_FLOOR_Y = 11`).
- At least one full 32×32 cell is guaranteed to touch the **south map edge** so the body reads as continuing past the playable slab.

**Mountain tarn** (`_mountain_tarn_anchor`, `_apply_mountain_tarn_macro_cell`):
- Placed as exactly **one 32×32 macro cell** on mountain shelf 1.
- Hard placement invariant: the tarn cell must have a complete **3×3 macro footprint** around it. The center cell is water on mountain shelf 1; all eight surrounding 32×32 macro cells must already be mountain shelf 1 or mountain shelf 2. If no valid 3×3 footprint exists, skip the tarn rather than carving a broken edge lake.
- Fixed geometry: **floor Y47**, water fills **Y48–Y54** (`TARN_FLOOR_Y = 47`, `TARN_WATERLINE = 54`). The waterline is a constant, not derived.
- It has no surround restore, no plateau ring, and no second cap pass. The tarn is intentionally simple and rectangular so it cannot fight the shelf-step cleanup.

`TARN_RADIUS` / `LAKE_RADIUS` survive only as metrics labels — the macro-cell passes no longer use circular carving.

> **Design note:** The tarn (water Y48–54) sits well above the lowland lake (`LAKE_WATERLINE` Y18). If a player digs a channel connecting the two bodies, water flows downhill under the (future) CA rules, producing emergent river-like behaviour. No river simulation is needed.

---

---

### Phase 5 — Underground Fill (3D, per chunk)

For each block position `(x, y, z)`. The underground logic is unchanged from the original design; only the water-column handling above the surface is new.

```gdscript
func generate_block(x: int, y: int, z: int) -> StringName:
    var col       := Vector2i(x, z)
    var surface_y := heightmap[x * WORLD_SIZE_Z + z]

    # --- Absolute boundaries ---
    if y <= 3:
        return &"base:terrain:bedrock"

    # --- Above surface ---
    if y > surface_y:
        # Lake columns fill from their carved floor up to their waterline.
        if lake_columns.has(col) and y <= LAKE_WATERLINE:
            return &"base:terrain:water:source"
        if tarn_columns.has(col) and y <= tarn_waterline:
            return &"base:terrain:water:source"
        return &"base:terrain:void"

    # --- Foundation band ---
    if y <= 11:
        return &"base:terrain:rock:rock11"   # Y4–11 hardcoded foundation

    # --- Surface skin ---
    if y == surface_y:
        return _pick_surface_block(x, z, col)

    # --- Underground volume ---
    var n_cave  := (noise_cave.get_noise_3dv(Vector3(x, y, z))  + 1.0) * 0.5
    var n_ore   := (noise_ore.get_noise_3dv(Vector3(x, y, z))   + 1.0) * 0.5
    var n_soil  := (noise_soil.get_noise_3dv(Vector3(x, y, z))  + 1.0) * 0.5
    # No stone-type noise — rock identity comes from authored altitude bands.

    # Cave void — no caves within 5 blocks of surface.
    if n_cave > 0.65 and y < surface_y - 5:
        return &"base:terrain:void"

    var ore := _pick_ore(y, n_ore)
    if ore != &"":
        return ore

    if n_soil > 0.68 and y >= 20 and y <= 60:
        return &"base:terrain:soil:cave"

    # Authored rock: mountain shelves above Y44, altitude body bands below.
    return _altitude_rock_body_id(y) if y < 44 else _mountain_shelf_block_id(y)
```

### Ore Selection

Resource replacement is concealed on untouched exposed walls. `_apply_resource_veins()` keeps
the authored rock unchanged for natural terrace/mountain side walls and for the outer
world-edge perimeter band, so the outside slab face cannot reveal metals or gems before the
player mines inward.

Ore selection reads `noise_threshold` and `depth_bias.max_y` directly from `block_resources.json` so adding a new ore never requires changing this function — only the data file.

```gdscript
# Ores are evaluated in ascending rarity order; first match wins.
# The order here must match the depth/rarity ladder in block_resources.json.
const ORE_LADDER := [
    &"base:terrain:ore:tin",
    &"base:terrain:ore:copper",
    &"base:terrain:ore:coal",
    &"base:terrain:ore:iron",
    &"base:terrain:ore:silver",
    &"base:terrain:ore:gold",
    &"base:terrain:gem:jade",
    &"base:terrain:gem:amethyst",
    &"base:terrain:gem:ruby",
    &"base:terrain:gem:sapphire",
    &"base:terrain:gem:emerald",
    &"base:terrain:gem:diamond",
]

func _pick_ore(x: int, y: int, z: int, n_ore: float) -> StringName:
    for block_key in ORE_LADDER:
        var res := BlockResources.get(block_key)   # loaded from block_resources.json
        if res == null:
            continue
        if y < res.depth_bias.max_y and n_ore > res.noise_threshold:
            return block_key
    return &""
```

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

The topmost solid block in each column gets a grass or dirt variant chosen deterministically from `(x, z)`. Lake and tarn bank columns get dirt unconditionally — the ground is wet. Water columns at or below their waterline skip this pass entirely; their topmost visible block is water.

There are **8 active grass variants** (`grass_01`–`grass_08`) and **4 dirt variants** (`dirt_01`–`dirt_04`). Grass is chosen by domain, not a flat hash: lowland/settlement uses `grass_01`–`grass_04` and valley/highland/foothill uses `grass_05`–`grass_08`, with the lighter variant in each set used along patch edges and terrace lips (resolved via the cap-grass band maps). The real `_pick_surface_block(x, z, col)` delegates to `_grass_variant()` / `_dirt_variant()` / `_lowland_cap_grass_band_variant_index()` / `_foothill_cap_grass_band_variant_index()`; the simplified shape is:

```gdscript
func _pick_surface_block(x: int, z: int, col: Vector2i) -> int:
    # Bank columns adjacent to water get forced dirt.
    if lake_columns.has(col) or tarn_columns.has(col):
        return _dirt_ids[0]   # dirt_01

    var n_dirt := (noise_soil.get_noise_2d(x, z) + 1.0) * 0.5
    if n_dirt > 0.70:
        return _dirt_ids[_dirt_variant(x, z)]            # 1 of 4 dirt variants
    return _grass_ids[_grass_variant(x, z)]              # 1 of 8 grass variants, domain + edge aware
```

> **Agent note:** Do not use `randi()` or `randf()` for variant selection. Random calls are non-deterministic across chunk reloads and will cause visible seams when a chunk unloads and reloads with different variants. Deterministic hashing / region maps always return the same value for the same column.

---

### Generation Order Summary

```
STAGE A — 2D map passes (once, when generate() is called):
1.  Build the 6 noise instances                          (no stone noise)
2.  Compute domain map + macro coherence cleanup         (2D — mountain / valley / lowland)
3.  Compute surface heightmap from domain                (2D — macro terraces, plateau smoothing,
                                                          mountain/lowland transitions, shelf step limits)
4.  Carve lake bodies into heightmap (macro-cell):
      a. Lowland lake  (macro cells, floor Y11, water Y12–18, touches south edge; store lake_columns)
      b. Mountain tarn (one macro cell on shelf 1, floor Y47, water Y48–54; store tarn_columns)
5.  Apply edge detail, build cap-grass band maps + generation metrics, mark _maps_ready

STAGE B — on-demand column fill (per requested 16×16 column, for each block):
      a. Bedrock at Y=0..3, rock11 foundation at Y4..11
      b. Water source above surface_y in lake_columns (≤ LAKE_WATERLINE 18) or tarn_columns (≤ TARN_WATERLINE 54)
      c. Void above surface_y (all other columns)
      d. Surface skin at surface_y                       (grass / dirt / bank variants, domain + edge aware)
      e. Cave void carving                               (skip within 5 blocks of surface)
      f. Ore vein check                                  (depth_bias + noise_threshold from data)
      g. Soil patch check                                (Y:20–60 band)
      h. Authored rock fill                              (altitude body bands + mountain shelves)
```

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
