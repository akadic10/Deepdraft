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
| **Stone and iron first** | The dominant materials underground are grey granite, dark iron, and amber torch-light. Wood, leather, and bone are surface imports — they feel warmer and more precious. Prioritise cool stone hues for underground objects, warm amber/brown for surface. |
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

In Godot, imported GLBs must use the project-wide **unlit vertex-colour shader**:

```gdscript
# World object shader (unlit, vertex colour only)
shader_type spatial;
render_mode unshaded, cull_back;

void fragment() {
    ALBEDO = COLOR.rgb;
    ALPHA  = COLOR.a;
}
```

World assets (unlike dwarf parts) do **not** use a runtime `tint` uniform. Their colours are baked at authoring time. If a future system needs runtime recolouring (e.g. banner dye), it will use a separate shader with a tint uniform identical to the dwarf shader in `41b`.

---

## 3. Scale Reference

**The single universal rule: 1 game block = 0.5 Godot units = 8 MagicaVoxel voxels.**

This applies to every asset in this document, dwarf body parts (see `41b`), and anything added in future. There is no per-class variation.

| Game concept | Godot units | MV voxels |
|---|---|---|
| 1 block (0.5 m) | 0.5 | 8 |
| 1 m | 1.0 | 16 |
| Dwarf height, visual (3.3 blocks) | 1.65 | ~26 |
| Mature oak canopy (7 blocks tall) | 3.5 | 56 |
| Ancient oak canopy (10 blocks tall) | 5.0 | 80 |

**Export scale multiplier: `0.0625`** (0.5 ÷ 8 = 0.0625 Godot units per MV voxel).

Set this once in Godot's GLB import settings: **Scene → Root Scale = 0.0625**. This is the only scale value used across the entire project. If you want to change it later, it is one number in one place.

> **Practical check:** A single 1×1×1 game block of stone should appear as a 0.5×0.5×0.5 unit cube in Godot. A dwarf (3.3 block visual height) should appear ~26 MV voxels tall in the MagicaVoxel scene, and ~1.65 Godot units tall at runtime.

### Comparison with Stonehearth

Stonehearth uses **10 QB voxels per block** at a fixed `"scale": 0.1` world units per voxel in each entity's JSON — the same pipeline step as Godot's GLB import root scale. Their Hearthling is 44 voxels tall visually. Deepdraft at 8 vox/block gives dwarves ~26 voxels — close enough for facial detail to read, and intentionally chunkier to suit the aesthetic.

| | Stonehearth | Deepdraft |
|---|---|---|
| Voxels per block | 10 | **8 (universal)** |
| Character height (voxels) | 44 visual / 35 collision | ~26 visual / 24 logical |
| Scale value | 0.1 wu/vox | **0.0625 Godot/vox** |
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

Collision rule (from `42_farming_brewing.md`): trees are the **only** surface entities with `CollisionShape3D`. The XZ extents of the collision box must match the canopy spread listed below. Collision runs full height Y=0 to mesh top.

#### Oak (`base:flora:oak_tree`)

All oak bounding boxes at **8 MV voxels per block, scale 0.0625**.

| Stage | MV Bounding Box | Canopy spread | Trunk width | Visual notes |
|---|---|---|---|---|
| Sapling | 8×8×16 MV | 0 (no canopy yet) | 2–3 MV | Single thin trunk, 2–3 leaf clusters on top. Lighter spring green. |
| Mature | 24×24×56 MV | 3×3 blocks | 6–8 MV | Broad spreading canopy, many leaf clusters in layers. Thick gnarled trunk. Dark bark. |
| Ancient | 40×40×80 MV | 5×5 blocks | 10–12 MV | Massive trunk with visible root flares at base. Canopy irregular, heavy, ancient-feeling. Some dead branch stubs. Bark is `stone_dark`-tinted. |

**Seasonal colour mapping for oak:**
- Spring: `leaf_spring` + `leaf_summer` mixed
- Summer: `leaf_summer` dominant, `leaf_summer_shadow` for deep interior
- Autumn: `leaf_autumn_gold` and `leaf_autumn_rust` in 60/40 mix
- Winter: `leaf_winter_bare` branch tips only, no leaf voxels — expose full trunk

#### Pine (`base:flora:pine_tree`)

All pine bounding boxes at **8 MV voxels per block, scale 0.0625**.

| Stage | MV Bounding Box | Canopy spread | Notes |
|---|---|---|---|
| Sapling | 8×8×12 MV | 0 | Conical tip with 2–3 needle rings |
| Mature | 16×16×48 MV | 2×2 blocks | Classic Christmas tree cone; rings of needle clumps decrease in radius toward top |
| Ancient | 24×24×72 MV | 3×3 blocks | Taller than wide; lower branches droop under weight; some dead branch stubs mid-trunk |

Pine has no seasonal colour change — needles stay `needle_dark` / `needle_highlight` year round. Winter variant may add subtle white-grey voxels on top surfaces (snow cap), but needle colour does not change.

#### Juniper (`base:flora:juniper_tree`)

All juniper bounding boxes at **8 MV voxels per block, scale 0.0625**.

| Stage | MV Bounding Box | Canopy spread | Notes |
|---|---|---|---|
| Sapling | 6×6×8 MV | 0 | Very thin column (sub-block XZ is fine for a young columnar) |
| Mature | 8×8×32 MV | 1×1 block | Dense columnar shrub; dark berries visible as small `iron_highlight` blue-grey voxels |
| Ancient | 16×16×48 MV | 2×2 blocks | Broader, slightly gnarled; berry clusters more prominent |

Juniper berry voxels: `#4A5878` (dusty blue-grey). They must be visible as distinct 1-voxel dots in the mature canopy so a dwarf harvest task makes visual sense.

#### Apple (`base:flora:apple_tree`)

Shares canopy spread and bounding box with Oak at each stage. Differences:

- Trunk is lighter: `wood_oak_light` for bark highlights (younger-feeling wood)
- Spring: blossom clusters — small white/pink voxels (`#F0C8C8`, `#F8F0F0`) scattered across canopy
- Summer: denser leaf cover than oak, slightly rounded canopy top
- Autumn (FRUITING state): canopy goes `leaf_autumn_gold` AND small red voxels (`#C03018`) appear — the apples. They must be visible as 1–2 voxel clusters against the gold leaves.
- Winter: same bare-branch treatment as oak

The **FRUITING** state is a separate model (autumn + apples) referenced by the `fruit_harvest` event. Path: `oak_mature_autumn_fruiting.glb`. This is additional to the standard seasonal set.

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

---

#### Bed (Dwarf Bunk) (`base:furniture:dwarf_bunk`)

Footprint: **2×1** (laid lengthwise, X = length). Collision: two regions —
- Mattress body: `{min:[0,0,0], max:[2,1,1]}` — full length, 1 block tall
- Headboard end: `{min:[0,0,0], max:[0.5,2,1]}` — head-end only, 2 blocks tall

Carved stone frame — dwarves sleep in alcoves, not on raised beds. Mattress: packed hay (`cloth_undyed`) with slight colour variation. Stone headboard (the tall end): a 2-block-tall slab with a single runic notch. No footboard — the foot end is open so the dwarf can swing their legs out.

---

#### Chair (`base:furniture:stone_chair`)

Footprint: **1×1**. Collision: `[{min:[0,0,0], max:[1,2,1]}]` — 2 blocks tall (includes backrest).

Squat stone seat with solid armrests and a straight-backed headrest. Carved from a single block. No cushion. Slightly concave seat surface (1-voxel dip at centre). The 2-block collision height matches the visible backrest and prevents dwarves from pathing through chairs.

---

#### Table (`base:furniture:stone_table`)

Footprint: **2×2**. Collision: `[{min:[0,0,0], max:[2,1,2]}]` — 1 block tall (just the slab; dwarves can walk around, not through or over).

Thick stone slab top on two solid pillars. Top surface `stone_highlight`. A `wood_plank` insert across the centre breaks the stone and provides a working surface feel. Legs are solid from floor to underside of slab — no gap to crawl through.

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
A dwarven bedroom is carved stone. A dwarven tavern has stone benches worn smooth by generations of broad backsides. Warmth comes from torchlight colour, not from soft materials. The one luxury is carved detail — rune marks, iron inlay, polished surfaces. Every piece of furniture implies function first.

### Workshop Props
These are the core of the colony's economy. The Smelter should radiate industrial danger; the Forge should look like weapons are made here, not decorations. The Brewery is warm, steam-touched, slightly chaotic — copper pipes going in unexpected directions, crocks in a row, a barrel that doesn't quite fit. The Aging Cellar is cold, deliberate, and still.

### Decorative Objects
World scatter should feel like archaeology — as if the site has been occupied for generations and objects have been placed, forgotten, moved, and placed again. A Mining Cart is dented. A Runic Standing Stone leans 3°. A barrel has a dark stain. These micro-details are achieved through asymmetric voxel placement, not additional geometry complexity.

---

*Prev: [`52_combat_military.md`](../50_world_events/52_combat_military.md)*
