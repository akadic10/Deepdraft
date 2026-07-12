# 61 — Voxel Art Authoring Guide (World Assets)

> **Scope:** Trees, bushes, cave flora, farm crops, furniture, workshop props, decorative/world objects.
> For dwarf body parts, see [`41b_dwarf_appearance_glb.md`](../40_economy_colony/41b_dwarf_appearance_glb.md).

---

## 1. Visual Identity

Deepdraft is flat-shaded, chunky, and readable at RTS zoom. Every asset must serve those three goals before anything else.

**The four aesthetic pillars:**

| Pillar | What it means in practice |
|---|---|
| **Dwarven weight** | Forms are squat, broad, and heavy. Thin spindly geometry reads as elven or human — not here. A dwarf table is thick-legged; a dwarf barrel is stout; a dwarf tree has a trunk as wide as it is tall. |
| **Stone and iron first** | The dominant materials of the WORLD are grey granite, dark iron, and amber torch-light — halls, industry, and monuments are stone and iron. **Furniture is woodwork (Alen, 2026-07-11):** beds, chairs, benches, tables, shelves — anything dwarves use rather than work — is wood, warm against the stone. Wood is plentiful on the surface (the map is forested); it is the natural furniture material, not a luxury. Stone/iron furniture is reserved for industrial anchors (anvil, trade counter, workshop bodies) and monuments (rune shelf, standing stones). |
| **Mushroom magic** | The underground is alive with bioluminescence. Cave flora glows — not neon, but a soft, cold blue-violet that contrasts sharply with the warm stone environment. This is the game's primary visual signature. |
| **Weather and age** | Everything in this world has been underground too long or outside too long. Stone is darkened at corners. Wood is grain-streaked. Iron is dull and pitted. Achieve this through colour gradient within a voxel mesh — a lighter highlight layer on top surfaces, a darker shadow layer on underside and recesses. Never flat fill an entire material with a single colour. |

---

## 2. Toolchain

**Canonical tool: MagicaVoxel 0.99.7.1+**

The full pipeline is:

```
MagicaVoxel (.vox) → Export as GLB → Import into Godot 4.x
```

Export settings in MagicaVoxel:
- **Format:** GLB
- **Scale:** see Section 3
- **Merge objects:** OFF (world assets are single-mesh, so this has no effect — but keep it off for cleanliness)
- **Normals:** Flat (never smooth — smooth normals destroy the voxel aesthetic)
- **Texture bake:** OFF — all colour lives in vertex colour, not a texture atlas

In Godot, imported GLBs use the **project-wide vertex-colour material** — the same one the
terrain renderer applies (`WorldRenderer._create_material()`), so world objects and the ground
shade consistently:

```gdscript
# World object material (vertex colour as albedo, lit, double-sided)
var mat := StandardMaterial3D.new()
mat.vertex_color_use_as_albedo = true
mat.roughness    = 1.0
mat.metallic     = 0.0
mat.cull_mode    = BaseMaterial3D.CULL_DISABLED          # double-sided
mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL # lit by the sun
```

> **History (2026-06-06):** this guide previously specified an `unshaded, cull_back` shader.
> That predated the lit, double-sided terrain material and caused two artifacts on voxel
> foliage: single-sided culling (`cull_back`) made the thin/sparse canopy shell show
> see-through "missing" faces, and `unshaded` flattened the voxel facets into a colour blob.
> Matching the terrain material (`CULL_DISABLED` + `SHADING_MODE_PER_PIXEL`) fixes both. First
> applied to pine in `SurfaceFloraSpawner` — see `docs/00_dev_roadmap/13_flora_scatter_pine.md`
> §6. Tradeoff: `CULL_DISABLED` ~doubles a mesh's drawn triangles; terrain already runs this
> way, so revisit only if it costs too much at scale.

The **highlight/shadow gradient still matters** (top surfaces lighter, recesses darker, baked
into vertex colour) — lighting enhances that read, it does not replace it. Never flat-fill a
material with a single colour.

World assets (unlike dwarf parts) do **not** use a runtime `tint` uniform. Their colours are baked at authoring time. If a future system needs runtime recolouring (e.g. banner dye), it will use a separate shader with a tint uniform identical to the dwarf shader in `41b`.

---

## 3. Scale Reference

**The anchor: in the live game 1 block = 1.0 Godot unit.** (The renderer emits one block as a
1.0-unit cube; the old "1 block = 0.5 units / root scale 0.0625" rule in this section was wrong
for the running world and is corrected below.)

**Resolution is per asset-class — two classes, mirroring Stonehearth:**

| Asset class | Voxels per block | Render scale | How scale is applied |
|---|---|---|---|
| Characters & items (dwarves `41b`, drops, props) | **8 / block** | **0.125** (1.0 ÷ 8) | GLB import Root Scale = 0.125 |
| Trees & large flora | **1 / block (1:1)** | **1.0** | runtime, via `SurfaceFloraSpawner.voxels_per_block = 1` |

Generated dwarf GLBs are the exception to the import-setting column: `tools/generate_dwarf_glb.py` authors in the 8-voxels-per-block frame, then bakes the `0.125` scale into exported vertex positions. Those generated files should keep Godot import Root Scale = 1.0.

So a character voxel is 1/8 block (fine, for facial detail); a tree voxel is a full 1×1×1 block
(chunky, simple — the "Voxel Trees" / Stonehearth look). This is deliberate: Stonehearth does the
same split (characters at 10 vox/block scale 0.1; **trees at scale 1.0, ~1 voxel per block**).

| Game concept | Class | MV voxels | Godot units |
|---|---|---|---|
| Dwarf height, visual (3.3 blocks) | character (8/blk) | ~26 | 3.3 |
| Ancient pine (27 blocks tall) | tree (1/blk) | 27 | 27 |
| Mature pine (20 blocks) | tree (1/blk) | 20 | 20 |

> **Practical check:** a 1×1×1 block of stone is a 1.0-unit cube in Godot. A dwarf (~26 voxels,
> imported at 0.125) stands ~3.3 units. A pine leaf-cube (1 voxel, scale 1.0) is exactly one
> terrain block. Trees are NOT imported at the character root scale — their `.import` keeps
> root_scale 1.0 and the spawner applies scale 1.0 at runtime.

### Comparison with Stonehearth

Stonehearth uses two resolutions too: characters/items at **10 QB voxels per block** (`"scale": 0.1`),
and **trees at `"scale": 1.0` — roughly one voxel per terrain block** (10× chunkier than their
people). Deepdraft mirrors this: characters at 8 vox/block, trees at 1 vox/block.

| | Stonehearth | Deepdraft |
|---|---|---|
| Character voxels per block | 10 | **8** |
| Tree voxels per block | ~1 (scale 1.0) | **1 (scale 1.0)** |
| Character height (voxels) | 44 visual / 35 collision | ~26 visual / 24 logical |
| Character scale value | 0.1 wu/vox | **0.125 Godot/vox** |
| Seasonal tree variants | 3 random per season | up to 3 (oak/pine), 2 (juniper) |

Stonehearth ships **3 randomly selected variants per season per tree stage**. Deepdraft uses the same approach: season keys in a tree stage's `models` block accept either a string (single model, backward-compatible) or an array of strings (one picked at spawn time via world-position hash). See `42_farming_brewing.md § Model Variant Resolution` for the GDScript pattern. The table above is now updated — variants are fully specced, not parked.

### Tree Variant Naming Convention

Base model (variant 1) keeps the existing name. Additional variants append `_2`, `_3`:

```
oak_mature.glb              ← variant 1 (summer)
oak_mature_2.glb            ← variant 2 (summer)
oak_mature_3.glb            ← variant 3 (summer)
oak_mature_autumn.glb       ← variant 1 (autumn)
oak_mature_autumn_2.glb     ← variant 2 (autumn)
oak_mature_winter.glb       ← single (winter)
```

Evergreens with no season suffix on their summer baseline:

```
pine_mature.glb             ← variant 1 (summer)
pine_mature_2.glb           ← variant 2 (summer)
pine_mature_3.glb           ← variant 3 (summer)
pine_mature_winter.glb      ← variant 1 (winter)
pine_mature_winter_2.glb    ← variant 2 (winter)
```

### What Variants Differ In

All variants for a given species/stage/season **must share**:
- Trunk base XZ position (the origin point collision and harvest targeting uses)
- Full XZ canopy footprint (collision box is identical across variants)
- Overall height (`clearance_height` applies to all variants equally)

Variants **may differ in**:
- Canopy silhouette and branch layout
- Degree of lean (max ±5° from vertical — more looks wrong at RTS zoom)
- Density and clustering of leaf voxels
- Bark texture variation implied by colour spot patterns on the trunk

---

## 4. Master Colour Palette

All world assets draw from this palette. Using consistent colours across assets is what makes the game world feel cohesive. **Do not introduce colours outside these ranges without a design justification.**

### Stone & Earth

| Name | Hex | Use |
|---|---|---|
| `stone_highlight` | `#C4BEB4` | Top-face, lit voxels of stone |
| `stone_mid` | `#9B9088` | Primary stone body |
| `stone_shadow` | `#6B6260` | Underside, recesses, cracks |
| `stone_dark` | `#3F3938` | Deep shadow, ancient stone |
| `cave_soil_wet` | `#3D2B1F` | Damp cave soil farm blocks |
| `cave_soil_dry` | `#5C3E2C` | Dry cave soil |
| `surface_dirt` | `#7A5C3A` | Surface dirt terrain |
| `surface_dirt_shadow` | `#4E3A20` | Shaded faces on surface dirt |

### Wood

| Name | Hex | Use |
|---|---|---|
| `wood_oak_light` | `#A67C52` | Highlighted oak grain |
| `wood_oak_mid` | `#7A5230` | Primary oak body |
| `wood_oak_dark` | `#4E3018` | Oak shadow, dark grain streaks |
| `wood_pine_light` | `#B08050` | Pine sapwood highlight |
| `wood_pine_mid` | `#7A5230` | Pine heartwood (same dark as oak) |
| `wood_bark_grey` | `#6E6258` | Aged, bleached bark on ancient trees |
| `wood_plank` | `#8C6840` | Sawn plank furniture surfaces |
| `wood_plank_dark` | `#5A3E20` | Plank shadow / grooves |

### Foliage

| Name | Hex | Use |
|---|---|---|
| `leaf_summer` | `#4A7A2C` | Full summer leaf canopy |
| `leaf_summer_shadow` | `#2E5218` | Underside / deep canopy |
| `leaf_spring` | `#6AA040` | Fresh spring growth |
| `leaf_autumn_gold` | `#C88820` | Gold autumn leaf |
| `leaf_autumn_rust` | `#A04818` | Rust/red autumn leaf |
| `leaf_winter_bare` | `#5C4830` | Bare winter branch tips |
| `needle_dark` | `#2A4A1A` | Pine / juniper needle clumps |
| `needle_highlight` | `#3A6228` | Pine needle highlights |

### Metal & Mineral

| Name | Hex | Use |
|---|---|---|
| `iron_dull` | `#6A6868` | Raw iron, pickaxes, brackets |
| `iron_highlight` | `#9A9898` | Polished iron face |
| `iron_dark` | `#3A3838` | Iron shadow / pitting |
| `copper_body` | `#B05828` | Copper fittings, brewery pipes |
| `copper_patina` | `#4A7858` | Aged copper patina |
| `coal_body` | `#2A2828` | Coal ore or charcoal deposits |
| `gold_bright` | `#D4A020` | Gold ingot highlight |
| `gold_mid` | `#A87810` | Gold body |

### Fungal & Bioluminescent (Cave Flora)

| Name | Hex | Use |
|---|---|---|
| `mushroom_cap_purple` | `#6A3A78` | Plump helmet cap |
| `mushroom_cap_deep` | `#3E1E4A` | Plump helmet cap shadow |
| `mushroom_stalk` | `#C8B8A8` | Pale mushroom stalk |
| `mushroom_gill` | `#E8D8C8` | Gill underside |
| `glow_blue` | `#3A78C8` | Bioluminescent spore clusters |
| `glow_blue_bright` | `#78B8F0` | Brightest glow accent |
| `glow_violet` | `#7840A0` | Rare bioluminescent cave moss |
| `mycelium_web` | `#C8C0B0` | Mycelium threads on cave soil |

### Organic / Craft

| Name | Hex | Use |
|---|---|---|
| `cloth_undyed` | `#C8B888` | Raw pig-tail cloth, sacking |
| `rope_natural` | `#A09060` | Rope, lashing on beehives |
| `leather_brown` | `#6A3A18` | Leather belts, chair seats |
| `ceramic_grey` | `#9898A8` | Crocks, jugs in the brewery |
| `wax_amber` | `#C89040` | Beehive wax, candle stubs |
| `honey_gold` | `#E0A030` | Honeycomb, honey jars |

### Torch & Warmth

| Name | Hex | Use |
|---|---|---|
| `flame_core` | `#FFDD44` | Torch flame bright core |
| `flame_mid` | `#FF8820` | Main flame body |
| `flame_tip` | `#CC4400` | Flame tip / ember |
| `torch_handle` | `#4A3018` | Torch stick |
| `torch_bracket` | `#5A5858` | Iron wall bracket |
| `ember_glow` | `#882200` | Forge / smelter ember bed |

---

## 5. Asset Specifications

### 5.1 Surface Trees

Path convention: `res://assets/models/flora/trees/{species}/{species}_{stage}_{season}.glb`

Seasons with defined variants: `spring`, `summer`, `autumn`, `winter`. Summer is the canonical base and the fallback if a season key is missing.

Collision rule (from `42_farming_brewing.md`): trees are the **only** surface entities with `CollisionShape3D`. The XZ extents of the collision box must match the trunk footprint (1/2/3 blocks); the wider canopy is visual overhang only.

> **Tree resolution moved to 1:1 (2026-06-06).** All trees are now authored at **1 voxel = 1
> block, scale 1.0** (§3), one generator per species: `tools/generate_pine_glbs.py`,
> `generate_apple_glbs.py`, `generate_oak_glbs.py`, `generate_juniper_glbs.py`. The old
> `generate_tree_glbs.py` (8 vox/block oak) is retired. Box dimensions below are in voxels =
> blocks.

#### Oak (`base:flora:oak_tree`) — converted to 1:1

Oak is **1:1, scale 1.0** (§3), generated by `tools/generate_oak_glbs.py`. The largest broadleaf:
a big **irregular multi-lobe** canopy (gnarled, ancient-feeling) on a dark grey-brown flared
trunk. No fruit/blossom. Box dimensions in voxels = blocks.

| Stage | Box (voxels = blocks) | Trunk footprint | Notes |
|---|---|---|---|
| Sapling | ~6×6×7 | 1 | Small lumpy blob on a thin trunk |
| Mature | ~13×13×17 | 3 | Broad spreading canopy, flared trunk |
| Ancient | ~23×23×25 | 5 | Massive irregular canopy, heavy root-flared trunk |

Seasons (per-voxel in the generator): spring fresh light green, summer two-tone green, autumn
gold/rust, winter bare gnarled branches (no leaves). Variants: summer ×3, autumn ×2, spring/winter ×1.

#### Pine (`base:flora:pine_tree`) — converted to 1:1

Pine is **1:1 — 1 voxel = 1 block, scale 1.0** (§3), generated by `tools/generate_pine_glbs.py`.
Box dimensions in voxels therefore *equal* block dimensions. It's a simple Stonehearth-style
stepped conifer: bare reddish trunk, a stack of flat needle whorls narrowing to a point with
1-block gaps the trunk peeks through, pointed apex.

| Stage | Box (voxels = blocks) | Trunk footprint | Whorls | Notes |
|---|---|---|---|---|
| Sapling | 5×5×8 | 1 | 3 | Small stepped cone (clutter, no collision) |
| Mature | 9×9×20 | 2 | 6 | Stepped cone; trunk visible between whorls |
| Ancient | 15×15×27 | 3 | 8 | Tall stepped cone, pointed apex |

Two-tone greens (`PINE_TOP`/`MID`/`DARK`); reddish trunk; engine lighting (PER_PIXEL) does the
face shading. Winter variants frost upward-facing needle voxels with snow; summer needle colour
otherwise constant year-round. Up to 3 summer + 2 winter variants per mature/ancient stage. Whole
set ≈ 2.3 MB. Sizing rationale and Stonehearth measurements: `13_flora_scatter_pine.md` §5.1.

#### Juniper (`base:flora:juniper_tree`) — converted to 1:1

Juniper is **1:1, scale 1.0** (§3), generated by `tools/generate_juniper_glbs.py`. A narrow
**columnar** evergreen: a tall, dense, dark blue-green column with a rounded top, dotted with
dusty blue-grey berries. Much narrower than oak/apple. Evergreen — only summer + snow-dusted
winter. Box dimensions in voxels = blocks.

| Stage | Box (voxels = blocks) | Trunk footprint | Notes |
|---|---|---|---|
| Sapling | ~5×5×5 | 1 | Small dark blob |
| Mature | ~7×7×12 | 1 | Dense column, berries on the surface |
| Ancient | ~9×9×16 | 2 | Broader column, more berries |

Berry voxels: dusty blue-grey (`#556488`), placed as distinct 1-voxel dots on the surface so a
dwarf harvest task reads visually. Variants: summer ×2, winter ×1 (matches `juniper_tree.json`).

#### Apple (`base:flora:apple_tree`) — converted to 1:1

Apple is **1:1 — 1 voxel = 1 block, scale 1.0** (§3), generated by `tools/generate_apple_glbs.py`.
Chunky deciduous orchard tree: a lower, wider, slightly asymmetric canopy of big cubes with a
bobbly (protruding-cube) surface, a red-brown crooked/flared trunk, and warmer/yellower leaves
than oak. It must read as a fruit tree, not a small oak. Box dimensions in voxels equal block
dimensions.

| Stage | Box (voxels = blocks) | Trunk footprint | Notes |
|---|---|---|---|
| Sapling | ~8×7×~7 | 1 (clutter) | Low orchard blob on a thin trunk |
| Mature | ~13×12×~12 | 3 | Low wide canopy, crooked/flared trunk |
| Ancient | ~20×15×~18 | 5 | Broad orchard canopy, root-flared trunk |

Seasonal handling (per-voxel, all in the generator):
- Spring: lighter `SPR_TOP`/`SPR_MID` greens with white/pink blossom flecks on the upper surface.
- Summer: two-tone `LEAF_TOP`/`MID`/`DARK` greens (shared with pine).
- Autumn: gold (`AU_GOLD`) + rust (`AU_RUST`) mix.
- Autumn-fruiting: autumn canopy plus obvious red apple clusters on the lower/outer surface — a **separate
  model key** (`apple_{stage}_autumn_fruiting.glb`) used only during the `fruit_harvest` FRUITING
  state, additional to the seasonal set.
- Winter: no leaves — bare red-brown branch structure fanning from the trunk.

Variants: summer ×3, autumn ×2, spring/winter/fruiting ×1 (matches `apple_tree.json`). Whole set
≈ 2.9 MB.

---

### 5.2 Surface Shrubs & Bushes

These are farm crops (1×1 footprint, no collision) or world-gen scatter objects. Rules from `42_farming_brewing.md` Single-Tile Asset Overflow Rule apply: **no CollisionShape3D on any shrub**.

Path: `res://assets/models/flora/bushes/{species}/{species}_{stage}.glb`

For bushes that have seasonal variants, append `_{season}`.

#### Blueberry Bush (`base:flora:blueberry_bush`)

All at **8 MV voxels per block, scale 0.0625**.

| Stage | MV Box | Notes |
|---|---|---|
| Sapling | 8×8×6 MV | Low mound of leaves, no berries (~0.75 blocks tall) |
| Mature | 16×16×12 MV | Rounded bush; dense blue-tinted `#3A5878` berries visible in clusters |
| Autumn | 16×16×12 MV | Leaves go `leaf_autumn_rust`; berries remain |
| Winter | 12×12×8 MV | Bare twigs, no berries |

#### Elderberry Bush (`base:flora:elderberry_bush`)

All at **8 MV voxels per block, scale 0.0625**.

| Stage | MV Box | Notes |
|---|---|---|
| Sapling | 8×8×8 MV | Upright stem with sparse leaves (~1×1 block) |
| Mature | 20×20×20 MV | Arching stems ~2.5 blocks across; creamy-white flat flower clusters (`#E8E4D8`) in spring/summer; dark purple berry clusters (`#2A1838`) in autumn |
| Winter | 16×16×12 MV | Bare arching stems |

#### Wild Strawberry Bush (`base:flora:wild_strawberry_bush`)

At **8 MV voxels per block, scale 0.0625**.

| Stage | MV Box | Notes |
|---|---|---|
| Ground cover | 16×16×6 MV | Flat, creeping (~2×2 blocks XZ, ~0.75 blocks tall); small trilobed leaf voxels; tiny red fruit dots (`#C02818`) when fruiting |

This is always ground-hugging — never taller than 6 MV voxels (1.5 game blocks). The visual overflow is exclusively horizontal.

---

### 5.3 Farm Crops

Path: `res://assets/models/flora/crops/{crop_id}/{crop_id}_{stage}.glb`

Rules: 1×1 footprint, no collision, visual overflow allowed horizontally. Model must never exceed the `clearance_height` from the JSON definition (measured in game blocks).

#### Plump Helmet Mushroom (`base:flora:plump_helmet`)

The visual signature of Deepdraft's underground. Must look appetising and fantastical simultaneously.

At **8 MV voxels per block, scale 0.0625**.

| Stage | MV Box | Palette | Notes |
|---|---|---|---|
| Sprouting | 8×8×8 MV | Stalk: `mushroom_stalk` · Cap: `mushroom_cap_deep` | Tiny dome barely poking out of soil (~1 block). Visible spore ring at base. |
| Mature | 16×16×16 MV | Stalk: `mushroom_stalk` + `mushroom_gill` · Cap: `mushroom_cap_purple` + `mushroom_cap_deep` | Full helmet shape: wide flat-bottomed cap, short stout stalk (~2 blocks). Cap highlight row on top edge. Gill voxels visible on underside. **Add 2–3 `glow_blue` voxels in gill shadow area** — colour accent, not a light source. |

#### Hops Plant (`base:flora:hops_plant`) — Annual

At **8 MV voxels per block, scale 0.0625**.

| Stage | MV Box | Notes |
|---|---|---|
| Seedling | 6×6×8 MV | Small leafy stem, no bine training (~0.75 block XZ, ~1 block tall) |
| Climbing | 12×12×24 MV | Bine wraps upward around a stake (~1.5 blocks XZ, ~3 blocks tall). Side shoots visible. |
| Mature | 16×16×28 MV | Hanging hop cones (`#8A9860` — yellow-green) visible in clusters on upper bine (~2 blocks XZ, ~3.5 blocks tall). |

Stake: a 2×2 MV dark wood post running the full height. The climbing bine spirals around it using `leaf_summer` / `leaf_summer_shadow`.

#### Grape Vine (`base:flora:grape_vine`)

At **8 MV voxels per block, scale 0.0625**.

| Stage | MV Box | Notes |
|---|---|---|
| Cutting | 8×8×8 MV | Low leafy mound, a few early tendrils (~1×1 block) |
| Fruiting | 24×24×16 MV | Wide spreading, low-growing vine on a trellis frame (~3×3 blocks XZ, ~2 blocks tall). Fruit clusters: deep purple `#4A1860` grapes as 2-voxel blobs. Autumn variant: leaves go gold. Dormant (winter): bare trellis only. |

Trellis frame: 2 upright posts + 2 horizontal rails in `wood_plank_dark`.

#### Pig Tail Plant (`base:flora:pig_tail_plant`)

At **8 MV voxels per block, scale 0.0625**.

| Stage | MV Box | Notes |
|---|---|---|
| Seeded | 4×4×4 MV | Barely visible soil disturbance (~0.5 block) |
| Sprouting | 8×8×12 MV | Spiky upright blue-grey leaves (`#7A8898`) (~1 block XZ, ~1.5 blocks tall) |
| Mature | 12×12×20 MV | Dense clump of strap-like leaves (~1.5 blocks XZ, ~2.5 blocks tall); fibrous look achieved by mixing `#7A8898` with `#9AACB8` highlight |

---

### 5.4 Furniture

Path: `res://assets/models/furniture/{furniture_id}.glb`

All furniture is single-file, no seasonal variants. Colours are baked in.

**Aesthetic rule:** dwarven furniture is built to last centuries underground. Hewn, not joinery-crafted. Comfort is implied by worn surfaces, not cushioning.

**Collision region schema:** every furniture JSON carries a `collision_regions` array. Coordinates are in game blocks (0.5 m each), local to the piece. Origin `(0, 0, 0)` = bottom-front-left corner of the footprint. Y is up. The furniture placement system reads these at runtime to create `CollisionShape3D` nodes — the agent never writes collision into `.tscn` files. See `data/furniture/trade_counter.json` for the canonical example.

**Rule: collision height = visual height.** If the backrest of a chair is visually 2 blocks tall, the collision region is 2 blocks tall. Do not collapse everything to a 1-block flat slab.

---

#### Trade Counter (`base:furniture:trade_counter`) — Existing

Footprint: **2×1**. Collision: `[{min:[0,0,0], max:[2,2,1]}]` — full footprint, 2 blocks tall (counter surface sits at dwarf chest height).

Heavy stone slab on two squat legs. Iron band across the top edge. Shallow recess on the shopkeeper's side (1-voxel indent). `stone_mid` body, `stone_highlight` top, `iron_dull` bands.

---

#### Barrel (`base:furniture:barrel`)

Footprint: **1×1**. Collision: `[{min:[0,0,0], max:[1,1,1]}]` — 1 block tall.

Classic fat barrel: `wood_oak_mid` staves, `iron_dull` bands. Visible bung hole (1-voxel dark indent) on top and bottom face. Primary food/drink storage vessel.

---

#### Brewing Vat (`base:furniture:brewing_vat`)

Footprint: **1×1**. Collision: `[{min:[0,0,0], max:[1,2,1]}]` — 2 blocks tall.

Larger open-topped vessel. Dark liquid surface (`#2A1808`) visible from above. `copper_body` tap fitting at base. Slightly dented sides.

---

#### Chest / Crate (`base:furniture:storage_crate`)

Footprint: **1×1**. Collision: `[{min:[0,0,0], max:[1,1,1]}]` — 1 block tall.

Rectangular crate with visible plank seams. Iron corner brackets. Lid slightly ajar (1–2 voxels offset). `wood_plank_mid` body, `iron_dull` fittings.

> **Functional container since doc 19** (`base:furniture:storage_chest`, capacity 24). The
> placed-form GLB is generated by `tools/generate_furniture_glbs.py`.

---

#### Storage Shelf (`base:furniture:storage_shelf`) — added 2026-07-11 (doc 19)

Footprint: **1×1**, 2 blocks tall, **ground piece** (Alen, 2026-07-11 — no wall
requirement). Collision: `[{min:[0,0,0], max:[1,2,1]}]`.

Heavy oak corner uprights (`wood_oak_mid`), base plinth + mid shelf + top cap in planks
(`wood_plank`, `wood_plank_dark` edges), iron brackets (`iron_dull`) under each level
against the posts — **open and symmetric from all four sides, no back panel** (readable
from any camera angle). Wood per the 2026-07-11 material rule. **Contents render on the
shelf**: stored item GLBs sit on the 8 anchor points (4 per level, defined in
`data/furniture/storage_shelf.json`) at ~0.5 scale — capacity equals anchor count,
WYSIWYG. **Model slated for hand-authoring by Alen**; the
`tools/generate_furniture_glbs.py` version (which has a back panel) is the interim
stand-in — remove the shelf from the generator output when the authored asset lands.
**Item form: the shared packed box** (one-box rule, Alen 2026-07-11 — the §5.7 ore
one-shape rule applied to furniture): every packed furniture item renders as the SAME
rope-lashed plank crate, `assets/models/items/furniture/packed_furniture.glb`. The box
says "packed furniture"; the ghost says which piece it becomes.

---

#### Bed (Dwarf Bunk) (`base:furniture:dwarf_bunk`)

Footprint: **2×1** (laid lengthwise, X = length). Collision: two regions —
- Mattress body: `{min:[0,0,0], max:[2,1,1]}` — full length, 1 block tall
- Headboard end: `{min:[0,0,0], max:[0.5,2,1]}` — head-end only, 2 blocks tall

**Wood frame (material rule, Alen 2026-07-11 — furniture is woodwork).** Heavy plank frame
(`wood_plank`, `wood_plank_dark` grooves) with thick corner posts — dwarven-stout, not
joinery-delicate. Mattress: packed hay (`cloth_undyed`) with slight colour variation. Wooden
headboard (the tall end): a 2-block-tall plank slab with a single iron-inlay runic notch
(`iron_dull`). No footboard — the foot end is open so the dwarf can swing their legs out.
The carved stone ALCOVE the bunk sits in is the room's stonework, not the furniture's.

---

#### Chair (`base:furniture:wooden_chair`)

Footprint: **1×1**. Collision: `[{min:[0,0,0], max:[1,2,1]}]` — 2 blocks tall (includes backrest).

Squat wooden seat (`wood_plank`, `wood_oak_dark` shadow) with solid armrests and a
straight-backed headrest — thick-legged, dwarven-heavy, no thin spindles. No cushion.
Slightly concave seat surface (1-voxel dip at centre, worn smooth). The 2-block collision
height matches the visible backrest and prevents dwarves from pathing through chairs.

---

#### Table (`base:furniture:wooden_table`)

Footprint: **2×2**. Collision: `[{min:[0,0,0], max:[2,1,2]}]` — 1 block tall (just the slab; dwarves can walk around, not through or over).

Thick plank-slab top (`wood_plank`, `wood_plank_dark` grooves) on two solid squat wooden
pillars. Top surface `wood_oak_light` (worn highlight). Iron corner brackets (`iron_dull`)
break the wood and add the dwarven-iron accent. Legs are solid from floor to underside of
slab — no gap to crawl through.

---

#### Torch Wall Mount (`base:furniture:wall_torch`)

Footprint: **wall-placed** (no floor footprint, no floor collision region).

Iron bracket (`torch_bracket`) holding a stick torch (`torch_handle`) with a 3-voxel flame cap: `flame_core` → `flame_mid` → `flame_tip`. Mesh only — the Godot `OmniLight3D` is a separate child node added by the scene builder, not part of the GLB.

---

#### Bookshelf / Rune Shelf (`base:furniture:rune_shelf`)

Footprint: **1×1**. Collision: `[{min:[0,0,0], max:[1,2,1]}]` — 2 blocks tall (full visual height).

Stone upright slab, carved surface on the front face: alternating `stone_mid` / `stone_shadow` horizontal rows with small `iron_highlight` voxel accents suggesting runes. Decorative — improves room appeal. The 2-block collision correctly blocks line of sight and movement past it.

---

#### Anvil (`base:furniture:anvil`)

Footprint: **1×1**. Collision: `[{min:[0,0,0], max:[1,1,1]}]` — 1 block tall.

Classic anvil silhouette: heavy iron block narrowing at the waist, flaring to a horn. `iron_dull` body, `iron_highlight` working surface (worn smooth), `iron_dark` underside. Silhouette must be unmistakable at colony zoom.

---

#### Stockpile Crate Stack (`base:furniture:stockpile_marker`)

Footprint: **1×1**. Collision: `[{min:[0,0,0], max:[1,1,1]}]` — 1 block tall.

Stack of 2–3 mismatched crates and sacks. `wood_plank_mid` crates, `cloth_undyed` sacks. Visual territory marker for stockpile zones — not a functional storage unit.

---

### 5.5 Workshop Props

These are the visual representations of workshop blocks. Path: `res://assets/models/workshops/{workshop_id}.glb`

Workshop props may have a footprint larger than 1×1 — the JSON defines the footprint. All workshop models must fit exactly within their declared footprint.

#### Brewery (`base:workshop:brewery`)

1×1×2 footprint (1 wide, 1 deep, 2 tall). Mounted brewing vat (same as furniture vat but fixed to the wall). An iron pipe running from the base to the floor. Copper `copper_body` fittings. A small gauge dial on the side (round `ceramic_grey` face with `iron_dark` needle) — decorative only.

#### Aging Cellar (`base:workshop:aging_cellar`)

2×2×2 footprint. A recessed oak cask rack. Two large barrels on their sides in an X-frame cradle. `wood_oak_mid` barrels with iron bands. The front face has a small chalkboard (`stone_dark` surface with `stone_highlight` streak marks) implying batch records. Temperature matters in lore — so frost-rime voxels (`#D0E8F0`) on the barrel faces indicate a correctly cold cellar in the inspect UI icon (not the world model).

#### Beehive (`base:workshop:beehive`)

1×1×1 footprint. Woven-wicker dome shape, placed on a small wooden base. Wicker: alternating `wood_oak_dark` and `rope_natural` voxel rows to imply weave texture. Top is slightly domed. A small entrance hole (1-voxel dark gap) at the base front. A single `honey_gold` drip voxel below the entrance. Must read immediately as a beehive — the silhouette is the tell.

#### Smelter (`base:workshop:smelter`)

2×1×2 footprint (the largest workshop). A stone furnace body with a domed iron top and a chimney stack rising 2 blocks high. Front face: iron door (`iron_dull`) with a small `ember_glow` visible through a 2×2 voxel grate (simulated by a recessed dark area with glow-coloured voxels behind). Chimney: `stone_mid` column tapering slightly at the top. Overall shape reads as industrial and dangerous. The 2×2 footprint means the operating dwarf stands at the front 1×2 face — keep that face clear of geometry overhangs.

#### Forge (`base:workshop:forge`)

1×1×2 footprint (floor block + anvil block above). Lower half: a stone plinth with bellows on one side (`cloth_undyed` accordion folds). Upper half: the anvil (`base:furniture:anvil` aesthetic but integrated — same iron tones). A shallow `ember_glow` coal basin between plinth and anvil.

---

### 5.6 Decorative & World Objects

Path: `res://assets/models/world/{object_id}.glb`

These are scatter objects placed by world-gen or by the player as decoratives. They carry no functional system logic.

#### Stone Boulder

Irregular rounded stone mass. 1×1 footprint, ~0.75 blocks tall (sits lower than full block). `stone_mid` body, `stone_highlight` top, `stone_shadow` base. Used by world-gen as surface obstacle clutter.

#### Mining Cart

1×1 footprint, ~0.75 blocks tall. Iron frame (`iron_dull`), wooden slat base (`wood_plank_dark`), four visible wheels (`iron_dark` discs). Tipped 10° to imply it was just parked. Can contain a mound of `coal_body` or `stone_mid` ore voxels on top.

#### Water Barrel (Outdoor)

1×1 footprint. Larger than the indoor barrel — this is a rain-catch or well supply barrel. Same aesthetic as `base:furniture:barrel` but taller (1.5 blocks) and with a rope handle loop across the top and visible waterline stain ring (`stone_shadow` horizontal band at 60% height).

#### Fence Post / Wood Palisade

1×1 footprint, 2 blocks tall. Sharpened log post. `wood_pine_mid` body with visible `wood_pine_light` grain streaks. Top is sharpened to a point (pyramid of 4 voxels). Used at colony perimeter and animal pens.

#### Runic Standing Stone

1×1 footprint, 3 blocks tall. A rough-hewn `stone_mid` monolith with carved rune-marks on the front face: simple geometric patterns in `stone_shadow` — Xs, horizontal lines, chevrons. No literal text or alphabet — keep it abstract. Found near mountain entrances and ancient sites.

#### Mushroom Lantern (Underground Decorative)

1×1 footprint, 1.5 blocks tall. A cultivated bioluminescent mushroom in a stone pot. Pot: `stone_mid`. Stalk: `mushroom_stalk`. Cap: `glow_blue_bright` on top, `glow_blue` on underside. This is the underground alternative to a torch — its `glow_blue` palette contrasts with the amber torch tones and signals a well-maintained tunnel.

---

### 5.7 Item Drops — Ore Chunks (shipped 2026-06-10)

Path: `res://assets/models/items/ore/{item_id}.glb` — generated by `tools/generate_ore_glbs.py`
(items class: **8 voxels per block**, the **0.125 scale baked into exported vertex positions**
per the dwarf-generator convention — Godot import Root Scale stays 1.0; never hand-edit
`.import`).

**The one-shape rule (Alen, 2026-06-10, Stonehearth-style):** every metal-ore drop is the
SAME stepped rock lump with the SAME surface fleck patches — only the **fleck colours** change
per ore. At RTS zoom the shape says "ore chunk", the colour says which ore. The shape and
fleck pattern are fully deterministic (fixed generator seed); regeneration is byte-identical.

| Property | Value |
|---|---|
| Rock body shape | **Hand-authored by Alen in Voxelator (2026-06-10): `tools/ore_base_shape.obj`** — the canonical basis for all stone and ore drops. 8×8×8, fully octahedrally symmetric (identical from all six faces and under 90° rotations); layer profile 4×4 / 6×6 / 8×8 ×4 / 6×6 / 4×4. The generator parses the OBJ and solid-fills the interior (304 voxels; the authored file is a hollow shell). To change the shape: re-sculpt in Voxelator, re-export the OBJ over that file, rerun the generator. |
| Size contract | Occupies the full 8×8×8 voxel envelope of ONE game block (1.0 × 1.0 × 1.0). A drop must never exceed the block that produced it. Base at Y=0, centred X=Z. |
| Body colours | Cool blue-grey trio (`#9AA3AA` / `#7C858C` / `#5A626A`) matching the mountain rock bands, height-banded + mild per-voxel variation |
| Flecks | 5 procedural patches (3–7 voxels) grown over the authored surface at fixed directions so several read from any camera angle; each two-tone (main above patch midline, shadow below) |

Fleck colours per ore (terrain vein hex where it reads on grey; readability-pushed where noted):

| Item | Main | Shadow | Note |
|---|---|---|---|
| `copper_ore` | `#C87533` | `#8F4E1E` | terrain copper |
| `tin_ore` | `#A9C49A` | `#74906A` | terrain tin, green pushed for contrast |
| `iron_ore` | `#7A5C45` | `#52392A` | terrain iron |
| `silver_ore` | `#E9EEF6` | `#AAB2C2` | terrain silver, brightened for contrast |
| `gold_ore` | `#E8B820` | `#A87810` | `gold_bright` / `gold_mid` family |
| `coal` | *(all-dark exception — Alen, 2026-06-10)* | | NO stone-grey body: the whole lump is dark — body banded `#39434B` / `#252D33` / `#161C21`, fleck patches as near-black seams `#0E1318` / `#070B0E`. Same shape and patch pattern. |

**Rough Stone** (`stone/rough_stone.glb`, added 2026-06-10): the plain stone drop from mined
rock bands — the same authored shape with body greys only, no fleck patches. The player's
future void-fill / construction material (`43_mining_materials.md`).

**Soil** (`soil/{light_soil,dark_soil,cave_soil}.glb`, added 2026-06-26, `tools/generate_soil_glbs.py`):
the SAME authored rock lump as Rough Stone, recoloured into earthy brown ramps — one per soil
type — with body banding only, no fleck patches. Decided by Alen (2026-06-26) over the earlier
"low mound" attempt: beside the real stone drops in the pit, a recoloured stone chunk reads
better than a separate flat mound. Brown ramps (light/mid/dark) derive from the terrain soil
hex; dark and cave are pushed darker than the near-olive terrain values so the three soils read
apart. This is the one family that does NOT get its own shape — it reuses the stone silhouette.

Review renders: `tmp/ore_drop_review/*.png`. **Future drop families** (gems = crystal cluster,
flora = produce) get their own shapes via the same generator pattern; the one-shape-per-family
+ colour-coding rule applies to each family.

---

## 6. Naming Conventions

### File Paths

```
res://assets/models/
  flora/
    trees/        ← surface trees
    bushes/       ← surface shrubs, berry bushes
    crops/        ← farm crops (per-stage GLBs)
  furniture/      ← furniture pieces
  workshops/      ← workshop block visuals
  world/          ← scatter / world-gen decoratives
  dwarves/        ← dwarf body parts (see 41b — not this doc)
  equipment/      ← weapons, armour, tools (future)
```

### File Name Pattern

```
{species_or_id}_{stage}_{season}.glb    ← for flora
{furniture_id}.glb                       ← for furniture (no stage, no season)
{workshop_id}.glb                        ← for workshops
{object_id}.glb                          ← for world decoratives
```

Stages and seasons must match the string values used in the JSON registry exactly. If a JSON definition uses `"mature"` as the stage key and `"autumn"` as the season key, the file must be `{id}_mature_autumn.glb`. The registry loader will construct the path at runtime by string concatenation.

### ID Prefix

Every model file must have an ID whose namespace prefix matches the game system:
- `base:flora:` → flora system
- `base:furniture:` → furniture system
- `base:workshop:` → workshop system

The file path does not include the namespace prefix — only the leaf name. The registry resolves the full `res://` path.

---

## 7. Per-Asset Quality Checklist

Before committing any GLB:

- [ ] **Silhouette test**: At 64×64 pixels, the asset's silhouette is immediately recognisable as its type (tree / barrel / mushroom / etc.)
- [ ] **Scale test**: Asset is positioned at correct world scale relative to a 0.5×0.5×0.5 reference cube
- [ ] **Colour discipline**: All colours are from the master palette (Section 4); no stray white or black voxels
- [ ] **Flat shading**: No smooth normals; the voxel block edges must be crisp
- [ ] **No collision on plants**: Farm crops and cave flora have no `CollisionShape3D`
- [ ] **Footprint match**: Asset visual extent fits within its declared `footprint` from JSON
- [ ] **Season completeness**: Trees have all four season variants; underground plants have `summer` only (the fallback)
- [ ] **Highlight/shadow gradient**: No material is flat-filled with a single colour; top faces are lighter, underside/recesses darker
- [ ] **Dwarven weight check**: Nothing looks thin, elegant, or elven. If it does, widen the trunk/legs/frame.

---

## 8. Dwarven Fantasy Aesthetic Reference (Per Category)

Use these as design intent checks when reviewing or prompting asset creation.

### Surface Trees
Think ancient forest clearing around a mountain fortress. Oaks are gnarled and wise — not decorative park trees. Pines stand like sentinels on ridge lines. Apple trees are the one piece of comfort dwarves maintain on the surface. Every tree should look like it has survived a few dwarf logging runs and grown back defiant.

### Cave Flora
This is alien biology. The plump helmet is not a woodland mushroom — it is a subterranean crop cultivated underground for centuries. It should feel simultaneously familiar (mushroom cap shape) and otherworldly (its glow accent, its deep purple, its stout bulk). Cave plants never look fragile. They are adapted survivors.

### Furniture
A dwarven bedroom is a carved stone alcove furnished with heavy woodwork — the hall is
stone, the furniture is wood (material rule, Alen 2026-07-11). A dwarven tavern has thick
wooden benches worn smooth by generations of broad backsides. Warmth comes from wood grain
and torchlight colour, not from soft materials. The one luxury is worked detail — iron
inlay, rune-notched headboards, polished plank surfaces. Every piece of furniture implies
function first. Stone furniture exists only where stone is the point: the anvil's mass,
the trade counter's permanence, the rune shelf's monument-feel.

### Workshop Props
These are the core of the colony's economy. The Smelter should radiate industrial danger; the Forge should look like weapons are made here, not decorations. The Brewery is warm, steam-touched, slightly chaotic — copper pipes going in unexpected directions, crocks in a row, a barrel that doesn't quite fit. The Aging Cellar is cold, deliberate, and still.

### Decorative Objects
World scatter should feel like archaeology — as if the site has been occupied for generations and objects have been placed, forgotten, moved, and placed again. A Mining Cart is dented. A Runic Standing Stone leans 3°. A barrel has a dark stain. These micro-details are achieved through asymmetric voxel placement, not additional geometry complexity.

---

*Prev: [`52_combat_military.md`](../50_world_events/52_combat_military.md)*
