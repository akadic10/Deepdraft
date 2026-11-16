# 41b — Dwarf Appearance & GLB Construction

## Overview

**Current art: Hearthblock** ([64](../60_asset_creation/64_hearthblock_art_direction.md),
doc 256). Every part is authored in
`tools/hearthblock/art/dwarves.mjs`, exported to `tools/art_data/voxel_hearthblock.json` and
built by the `dwarves` family in `tools/voxel_assets/`. There are 41 appearance GLBs
under `assets/models/characters/dwarves/` plus the two work tools. The parts are:
- the square head in four ages;
- bead eyes with a glint;
- a flared tunic with a brass buckle;
- a mitten hand with a separate tunic cuff mesh;
- a cuffed square boot;
- all 14 hairstyles, 7 beards, 8 brow styles and 4 portrait scars.

A dwarf with a trade also wears its hat: five hat GLBs, and each of the 14 hairstyles
once more as it lies under a hat (see [Trade hats](#trade-hats)).

All appearance IDs, pools and save fields are kept. Parts share one frame in world
units with root scale 1. Hands and feet are detached, and the logical body is 1×1×3.
The head layout rules and tool grips are listed in 64.

Limb lighting (doc 175): to keep both hands and boots lit evenly, the right-part rig
root keeps its negative X scale for poses and anchors, while its inner mesh uses
cached reflected geometry plus a
counter-reflection. Final rendered transforms are positive. Reflect normals and
tangents and reverse winding with positions; preserve baked colors and runtime
tints. Never replace this with a plain negative mesh scale or separate right-side
color compensation. Imported left/source meshes and appearance save IDs remain
unchanged. With a plain negative scale the reflected surfaces were lit in reverse:
the right hand rendered blue-grey and the right boot near-black (2026-10-13).
`DwarfBodyRig` applies `DwarfAssets.mirrored_limb_mesh()`, which uses the shared
`RigidMeshReflection` cache (doc 63), so all dwarves share one derived mesh per source
part.

This document catalogues every visual attribute a dwarf can have and defines the modular GLB file strategy for constructing them at runtime. The design goal is the minimum set of authored files that can express all valid combinations without duplicating geometry per color variant.

---

## Attribute Catalogue

All attributes are drawn from `data/dwarves/appearance.json`. They fall into two categories: **color attributes** (applied via runtime material/shader tinting — no separate mesh per value) and **shape attributes** (each variant is a distinct GLB file).

### Color Attributes — Both Genders

| Attribute | Values | Notes |
|---|---|---|
| `skin_tone` | pale · medium · tan · dark | Applied to `head_[age].glb` and `hand.glb`; body/boots retain baked colors |
| `eye_color` | grey · blue · green · brown · amber · red | Shown on the bead eye's glint in portraits; world eyes are untinted |
| `hair_color` | black · dark_brown · brown · auburn · red · blonde · grey · white | Applied to all hair/beard/brow shape meshes |

### Shape Attributes — Both Genders

| Attribute | Values | Representation |
|---|---|---|
| `age_tier` | young · adult · middle · elder | 4 head GLBs — tonal cheek/temple creases, common crown and facial slots |
| `scar` | none · cheek_slash · brow_notch · nose_bridge · chin_split | Portrait-only overlay child; "none" = no node added |

### Shape Attributes — Male

| Attribute | Values | GLB files |
|---|---|---|
| `hair_style` | short_back · shaved · wild_loose · braided_back · bald | 4 GLBs (`hair_m_[id].glb`); bald = no node added |
| `beard` | full_long · full_braided · short_trimmed · forked · mutton_chops · goatee · braided_long · *(none)* | 7 GLBs (`beard_[id].glb`); no beard = no node added |
| `eyebrow_style` | thick_flat · bushy · arched · unibrow | 4 GLBs (`brows_m_[id].glb`) |

### Shape Attributes — Female

| Attribute | Values | GLB files |
|---|---|---|
| `hair_style` | bun · braid_side · braid_long · short_practical · twin_braids · half_up · loose_long · shaved_sides · cropped · wild | 10 GLBs (`hair_f_[id].glb`) |
| `eyebrow_style` | thin_arched · thick_flat · bushy · sharp_angled | 4 GLBs (`brows_f_[id].glb`) |

---

## GLB File Inventory

All current appearance parts live under `assets/models/characters/dwarves/`. Total: **41 appearance GLB files**.
Work tools are additional assets, described below.

```
assets/models/characters/dwarves/
  body/
    head_young.glb
    head_adult.glb
    head_middle.glb
    head_elder.glb
    eyes.glb          ← shared across all age tiers and genders; tinted at runtime
    body_base.glb  <- compact torso + neck only; no arms or legs
    hand.glb          ← mirrored for left/right at runtime
    foot.glb          ← mirrored for left/right at runtime

  hair/
    hair_m_short_back.glb
    hair_m_shaved.glb
    hair_m_wild_loose.glb
    hair_m_braided_back.glb
    hair_f_bun.glb
    hair_f_braid_side.glb
    hair_f_braid_long.glb
    hair_f_short_practical.glb
    hair_f_twin_braids.glb
    hair_f_half_up.glb
    hair_f_loose_long.glb
    hair_f_shaved_sides.glb
    hair_f_cropped.glb
    hair_f_wild.glb

  beards/
    beard_full_long.glb
    beard_full_braided.glb
    beard_short_trimmed.glb
    beard_forked.glb
    beard_mutton_chops.glb
    beard_goatee.glb
    beard_braided_long.glb

  eyebrows/
    brows_m_thick_flat.glb
    brows_m_bushy.glb
    brows_m_arched.glb
    brows_m_unibrow.glb
    brows_f_thin_arched.glb
    brows_f_thick_flat.glb
    brows_f_bushy.glb
    brows_f_sharp_angled.glb

  scars/
    scar_cheek_slash.glb
    scar_brow_notch.glb
    scar_nose_bridge.glb
    scar_chin_split.glb

  hair_hatted/        ← each of the 14 hairstyles as it lies under a hat, under its hair/ name
  hats/
    hat_miner.glb     ← the hat, and its candle's flame as a second mesh
    hat_ranger.glb
    hat_carpenter.glb
    hat_stonemason.glb
    hat_blacksmith.glb
```

> **bald** male hair style and **none** beard/scar = simply no child node added. No GLB needed.

---

## Scene Hierarchy

Every dwarf scene at runtime follows this structure:

```
DwarfAgent (CharacterBody3D)
  ├─ MeshHead    (MeshInstance3D)  ← head_[age_tier].glb
  │   ├─ MeshEyes  (MeshInstance3D)  ← eyes.glb                      (always present; tinted per eye_color)
  │   ├─ MeshHair  (MeshInstance3D)  ← hair_[gender]_[style].glb     (absent if bald; hidden under a hat)
  │   ├─ MeshHairHatted               ← hair_hatted/ the same style       (only under a hat)
  │   ├─ MeshHat                      ← hats/hat_[trade].glb              (only with a trade; holds HatLight for the Miner)
  │   ├─ MeshBeard (MeshInstance3D)  ← beard_[style].glb             (absent if none)
  │   ├─ MeshBrows (MeshInstance3D)  ← brows_[gender]_[style].glb    (always present; map mesh + portrait)
  │   └─ MeshScar  (MeshInstance3D)  ← scar_[id].glb                 (absent if none; portrait only)
  ├─ MeshBody    (MeshInstance3D)  ← body_base.glb
  ├─ MeshHandL   (MeshInstance3D)  ← hand.glb
  ├─ MeshHandR   (MeshInstance3D)  ← hand.glb  (scale.x = -1 to mirror)
  ├─ MeshFootL   (MeshInstance3D)  ← foot.glb
  └─ MeshFootR   (MeshInstance3D)  ← foot.glb  (scale.x = -1 to mirror)
```

Equipment (helmets, armour, boots, weapons) attaches as **additional children** of the relevant part node — identical to how the hair/beard slots work. Equip = add child node. Unequip = remove child node.

Anatomy contract:

- `MeshBody` must never include arms, legs, wrist connectors, ankle connectors, or fused appendage mass.
- `MeshHandL`, `MeshHandR`, `MeshFootL`, and `MeshFootR` are detached floating parts.
- Shared absolute authoring coordinates are allowed for simple identity transforms, but the geometry must remain logically separated by GLB.

---

## Color Application Strategy

Tinted roles are authored near white with baked shading, and a runtime material
multiplies them by the dwarf's colour. Everything else is baked.

### Palette roles

`dwarves.mjs` paints semantic roles, and `proposal.mjs` → `TINTED` lists the tinted ones:
- `skin`, `skin_shade`, `nose`, `blush` and `mouth` take the skin tone on the head and
  mittens.
- `hair`, `hair_mid` and `hair_shade` take the hair colour on hair, beards and brows.
- `tunic`, `tunic_dark` and `tunic_light` are recoloured to the dwarf's clothing colour
  on the torso and both cuffs (`DwarfAssets.CLOTHING`, `CraftMaterials.apply_colors`).
  The colour is saved in the appearance as `clothing`. A dwarf without one gets it from
  its id (`DwarfAssets.clothing_for`), so neighbours differ and no other appearance roll
  changes.
- Boots, belt, buckle, eyes and the work tools keep their baked colours.

The live code is `DwarfAgent._apply_tints`. The sketch below shows the original idea.

### Runtime Tinting in Godot

Use a simple unlit shader on each mesh that multiplies vertex color by a `tint` uniform:

```gdscript
# On DwarfAppearance (attached to DwarfAgent)

const SKIN_TONES = {
    "pale":   Color(0.96, 0.84, 0.77),
    "medium": Color(0.85, 0.65, 0.50),
    "tan":    Color(0.71, 0.50, 0.35),
    "dark":   Color(0.42, 0.28, 0.18),
}

const HAIR_COLORS = {
    "black":      Color(0.10, 0.08, 0.08),
    "dark_brown": Color(0.25, 0.15, 0.10),
    "brown":      Color(0.42, 0.26, 0.14),
    "auburn":     Color(0.58, 0.25, 0.10),
    "red":        Color(0.78, 0.22, 0.08),
    "blonde":     Color(0.88, 0.76, 0.44),
    "grey":       Color(0.62, 0.62, 0.62),
    "white":      Color(0.92, 0.92, 0.92),
}

const EYE_COLORS = {
    "grey":   Color(0.55, 0.60, 0.62),
    "blue":   Color(0.25, 0.55, 0.85),
    "green":  Color(0.25, 0.65, 0.30),
    "brown":  Color(0.48, 0.30, 0.12),
    "amber":  Color(0.82, 0.55, 0.10),
    "red":    Color(0.80, 0.10, 0.10),
}

func apply_appearance(data: DwarfAppearanceData) -> void:
    _tint_mesh($MeshHead,             SKIN_TONES[data.skin_tone])
    _tint_mesh($MeshBody,             SKIN_TONES[data.skin_tone])
    _tint_mesh($MeshHandL,            SKIN_TONES[data.skin_tone])
    _tint_mesh($MeshHandR,            SKIN_TONES[data.skin_tone])
    _tint_mesh($MeshFootL,            SKIN_TONES[data.skin_tone])
    _tint_mesh($MeshFootR,            SKIN_TONES[data.skin_tone])
    _tint_mesh($MeshHead/MeshEyes,    EYE_COLORS[data.eye_color])
    _tint_mesh($MeshHead/MeshHair,    HAIR_COLORS[data.hair_color])
    _tint_mesh($MeshHead/MeshBeard,   HAIR_COLORS[data.hair_color])  # null-safe; absent if no beard
    _tint_mesh($MeshHead/MeshBrows,   HAIR_COLORS[data.hair_color])

func _tint_mesh(node: MeshInstance3D, color: Color) -> void:
    if node == null: return
    var mat := node.get_active_material(0).duplicate() as ShaderMaterial
    mat.set_shader_parameter("tint", color)
    node.set_surface_override_material(0, mat)
```

> **Beard color independence:** `appearance.json` reserves a `bear_color_independent` flag for future use. When implemented, add an optional `beard_color` field to `DwarfAppearanceData` that defaults to `hair_color` if absent. The `apply_appearance` call above already isolates beard tinting to a single line — swapping in `data.beard_color` later is a one-line change.

---

## Map Mesh vs Portrait

The same scene is used for both representations. The difference is which children are **active**:

| Child node | Map mesh | Portrait |
|---|---|---|
| MeshEyes | ✓ | ✓ |
| MeshHair | ✓ | ✓ |
| MeshBeard | ✓ | ✓ |
| MeshBrows | ✓ | ✓ |
| MeshScar | ✗ | ✓ |
| MeshHat, MeshHairHatted | ✓ | ✓ |
| The candle's flame and light | ✓ | ✗ |

Eyebrows are visible at colony zoom and contribute meaningfully to character silhouette and personality — they should always be present. Only scars are portrait-only. For the map mesh, simply skip adding `MeshScar`. For the portrait render, add all applicable children.

---

## DwarfAppearanceData Resource

Define appearance as a typed runtime `Resource` so agents can pass it around without loose
dictionaries. `DwarfAgent.serialize_state()` explicitly copies its fields into the
version-1 save dictionary; the save never stores a `.tres` path or Resource instance.

```gdscript
# res://scripts/dwarves/dwarf_appearance_data.gd
class_name DwarfAppearanceData
extends Resource

@export var gender:        String  # "male" | "female"
@export var age_tier:      String  # "young" | "adult" | "middle" | "elder"
@export var skin_tone:     String  # "pale" | "medium" | "tan" | "dark"
@export var eye_color:     String  # "grey" | "blue" | "green" | "brown" | "amber" | "red"
@export var hair_color:    String  # "black" | "dark_brown" | "brown" | "auburn" | "red" | "blonde" | "grey" | "white"
@export var hair_style:    String  # gender-specific style id; "bald" for no hair
@export var eyebrow_style: String  # gender-specific eyebrow id
@export var beard_style:   String  # male only; "" if none
@export var scar:          String  # "none" | "cheek_slash" | "brow_notch" | "nose_bridge" | "chin_split"
```

---

## DwarfAssetRegistry Autoload

All GLB resources are preloaded once in a single autoload singleton. The factory and appearance system query it by key — no `preload` calls scattered across files, no dynamic `load()` strings at runtime.

```gdscript
# res://scripts/dwarves/dwarf_asset_registry.gd
# Registered as autoload "DwarfAssets" in Project Settings.
extends Node

var heads: Dictionary = {
    "young":  preload("res://assets/models/characters/dwarves/body/head_young.glb"),
    "adult":  preload("res://assets/models/characters/dwarves/body/head_adult.glb"),
    "middle": preload("res://assets/models/characters/dwarves/body/head_middle.glb"),
    "elder":  preload("res://assets/models/characters/dwarves/body/head_elder.glb"),
}
var eyes:  Mesh = preload("res://assets/models/characters/dwarves/body/eyes.glb")
var body:  Mesh = preload("res://assets/models/characters/dwarves/body/body_base.glb")
var hand:  Mesh = preload("res://assets/models/characters/dwarves/body/hand.glb")
var foot:  Mesh = preload("res://assets/models/characters/dwarves/body/foot.glb")

var hair_male: Dictionary = {
    "short_back":   preload("res://assets/models/characters/dwarves/hair/hair_m_short_back.glb"),
    "shaved":       preload("res://assets/models/characters/dwarves/hair/hair_m_shaved.glb"),
    "wild_loose":   preload("res://assets/models/characters/dwarves/hair/hair_m_wild_loose.glb"),
    "braided_back": preload("res://assets/models/characters/dwarves/hair/hair_m_braided_back.glb"),
    "bald":         null,
}
var hair_female: Dictionary = {
    "bun":             preload("res://assets/models/characters/dwarves/hair/hair_f_bun.glb"),
    "braid_side":      preload("res://assets/models/characters/dwarves/hair/hair_f_braid_side.glb"),
    "braid_long":      preload("res://assets/models/characters/dwarves/hair/hair_f_braid_long.glb"),
    "short_practical": preload("res://assets/models/characters/dwarves/hair/hair_f_short_practical.glb"),
    "twin_braids":     preload("res://assets/models/characters/dwarves/hair/hair_f_twin_braids.glb"),
    "half_up":         preload("res://assets/models/characters/dwarves/hair/hair_f_half_up.glb"),
    "loose_long":      preload("res://assets/models/characters/dwarves/hair/hair_f_loose_long.glb"),
    "shaved_sides":    preload("res://assets/models/characters/dwarves/hair/hair_f_shaved_sides.glb"),
    "cropped":         preload("res://assets/models/characters/dwarves/hair/hair_f_cropped.glb"),
    "wild":            preload("res://assets/models/characters/dwarves/hair/hair_f_wild.glb"),
}
var beards: Dictionary = {
    "full_long":      preload("res://assets/models/characters/dwarves/beards/beard_full_long.glb"),
    "full_braided":   preload("res://assets/models/characters/dwarves/beards/beard_full_braided.glb"),
    "short_trimmed":  preload("res://assets/models/characters/dwarves/beards/beard_short_trimmed.glb"),
    "forked":         preload("res://assets/models/characters/dwarves/beards/beard_forked.glb"),
    "mutton_chops":   preload("res://assets/models/characters/dwarves/beards/beard_mutton_chops.glb"),
    "goatee":         preload("res://assets/models/characters/dwarves/beards/beard_goatee.glb"),
    "braided_long":   preload("res://assets/models/characters/dwarves/beards/beard_braided_long.glb"),
}
var brows_male: Dictionary = {
    "thick_flat": preload("res://assets/models/characters/dwarves/eyebrows/brows_m_thick_flat.glb"),
    "bushy":      preload("res://assets/models/characters/dwarves/eyebrows/brows_m_bushy.glb"),
    "arched":     preload("res://assets/models/characters/dwarves/eyebrows/brows_m_arched.glb"),
    "unibrow":    preload("res://assets/models/characters/dwarves/eyebrows/brows_m_unibrow.glb"),
}
var brows_female: Dictionary = {
    "thin_arched":  preload("res://assets/models/characters/dwarves/eyebrows/brows_f_thin_arched.glb"),
    "thick_flat":   preload("res://assets/models/characters/dwarves/eyebrows/brows_f_thick_flat.glb"),
    "bushy":        preload("res://assets/models/characters/dwarves/eyebrows/brows_f_bushy.glb"),
    "sharp_angled": preload("res://assets/models/characters/dwarves/eyebrows/brows_f_sharp_angled.glb"),
}
var scars: Dictionary = {
    "cheek_slash": preload("res://assets/models/characters/dwarves/scars/scar_cheek_slash.glb"),
    "brow_notch":  preload("res://assets/models/characters/dwarves/scars/scar_brow_notch.glb"),
    "nose_bridge": preload("res://assets/models/characters/dwarves/scars/scar_nose_bridge.glb"),
    "chin_split":  preload("res://assets/models/characters/dwarves/scars/scar_chin_split.glb"),
}

func hair_for(appearance: DwarfAppearanceData) -> Mesh:
    var table := hair_male if appearance.gender == "male" else hair_female
    return table.get(appearance.hair_style)

func brows_for(appearance: DwarfAppearanceData) -> Mesh:
    var table := brows_male if appearance.gender == "male" else brows_female
    return table.get(appearance.eyebrow_style)
```

---

## Construction Code Sketch

```gdscript
# res://scripts/dwarves/dwarf_factory.gd

func build_dwarf(data: DwarfData, portrait_mode: bool = false) -> DwarfAgent:
    var agent: DwarfAgent = DWARF_SCENE.instantiate()
    var a := data.appearance  # DwarfAppearanceData

    # 1. Head (age tier)
    agent.get_node("MeshHead").mesh = DwarfAssets.heads[a.age_tier]

    # 2. Eyes (always present)
    _attach(agent.get_node("MeshHead"), "MeshEyes", DwarfAssets.eyes)

    # 3. Hair (absent if bald)
    var hair_mesh := DwarfAssets.hair_for(a)
    if hair_mesh:
        _attach(agent.get_node("MeshHead"), "MeshHair", hair_mesh)

    # 4. Beard (males only, if style assigned)
    if a.gender == "male" and a.beard_style != "":
        var beard_mesh := DwarfAssets.beards.get(a.beard_style)
        if beard_mesh:
            _attach(agent.get_node("MeshHead"), "MeshBeard", beard_mesh)

    # 5. Eyebrows (always present — visible at map scale)
    _attach(agent.get_node("MeshHead"), "MeshBrows", DwarfAssets.brows_for(a))

    # 6. Scar overlay (portrait only)
    if portrait_mode and a.scar != "none":
        var scar_mesh := DwarfAssets.scars.get(a.scar)
        if scar_mesh:
            _attach(agent.get_node("MeshHead"), "MeshScar", scar_mesh)

    # 7. Apply color tints
    agent.get_node("DwarfAppearance").apply_appearance(a)

    return agent

func _attach(parent: Node3D, node_name: String, mesh: Mesh) -> void:
    var node := MeshInstance3D.new()
    node.name = node_name
    node.mesh = mesh
    parent.add_child(node)
```

---

## Trade hats

A dwarf with a trade wears its hat, and a Worker goes bare-headed (owner, 2026-11-12: "it's hard
to tell for me who's who from looking at the game only"; doc 304). Hats are costume, not goods:
nothing is crafted, stored, hauled or saved. The hat follows `profession`.

| Trade | Hat | What tells it apart from above and behind |
|---|---|---|
| Miner | A hard ochre cap, one seam over the top | A tallow candle standing on it in a rope ring |
| Ranger | A moss cap swept back to a point | A pheasant's feather pinned flat along its top |
| Carpenter | A soft plum cap, broad and flat, slumped to one side | Sewn in four, buttoned with a slice of branch |
| Stonemason | A flat-topped cap of grey felt, square as a knocked stone | Stone dust pale on its top, inside the rim |
| Blacksmith | A rust kerchief tied tight over the skull | Its knot and two tails behind, one corner scorched |
| Farmer | A broad-brimmed straw hat pushed back on the head, the brim wide at the sides and behind and a short lip in front (doc 309) | A slate-blue band round the crown, knotted at one side; the round the straw was woven in shows on its top |

- **Who wears one.** A career names its `hat` in `professions.json`. `DwarfBodyRig.wear_hat` hangs
  it on the head when the body is built and whenever the profession changes
  (`DwarfAgent._complete_profession_change`). A career without one leaves the head bare: the
  Worker, and careers still planned. A career that goes live needs its hat, or its dwarves read
  as Workers.
- **The hat line is y 45.** Brows end at y 44. A hat is solid from the line up and covers the
  head of every age (an elder's dome reaches y 52), so one model sits alike on a bald head, a
  cropped one and a full head of hair.
- **Hair under a hat.** `MeshHair` is hidden, not removed, and `MeshHairHatted` takes its place:
  the same style cut at the hat line (`under_hat` in `tools/voxel_assets/dwarves.py`: the cells
  below y 45, and those behind z -13 up to y 49, which only the bun has). The cuts are built
  beside the full styles, in `hair_hatted/` (`DwarfAssets.hair_under_hat`). Hair below the line
  stays, so plaits, buns and beards still say who the dwarf is.
- **What every hat keeps** (`test_hats_sit_on_every_head` in `test_dwarves.py`, for every hat
  on every head, brow, beard and hairstyle):
  - it covers the head from the hat line up;
  - below y 50 nothing goes past z 12, three cells proud of the face: more hides the brows and
    eyes from a camera that looks down 45 to 60 degrees. Trades differ on top, at the sides and
    behind, never in front;
  - its back stands at z -13 where a bun can lie (the kerchief's knot does it), so the bun's
    cut meets it;
  - it shares no face with what it sits on: two faces in one place flicker.
- **Height.** Hats end at y 54 as hair does, but for the Ranger's feather (y 60) and the Miner's
  candle (y 60, its flame y 65). In a tunnel three blocks high these stand in the ceiling's
  rock, as hair tops do, and show under the slice.
- **Colours.** Ochre, moss, plum and rust are the tunics' own dyes (`DwarfAssets.CLOTHING`); the
  Stonemason's greys are the worked stone of the benches. Teal was tried for the Carpenter: by
  torch it turned the Ranger's green. Torchlight pulls ochre and rust together, so shape and the
  mark on top carry a hat, never colour alone.
- **Portraits** copy the head with what it wears, so they show the hat. `DwarfPortrait` leaves
  out the candle's light and hides its flame.
- **Sleep.** A dwarf sleeps in its hat. The lying head rests as its hair does
  (`DwarfRestBehavior` leaves the hat out of its measure), and the hat gives into the bed.
- **The Miner's candle** is `DwarfHatLight`, hung on the hat when the career has a `hat_light`.
  Its rule is in [41](41_dwarf_agents.md#profession-system) and its light in
  [24](../20_player_interface/24_world_rendering.md#underground-lighting-model).
- **A new hat:** draw it in `dwarves.mjs` under `hats/`, list it in `voxel_dwarves.json` (`parts`)
  and `voxel_expected.json`, build the `dwarves` family ([61](../60_asset_creation/61_voxel_art_guide.md)),
  and name it as the career's `hat`. Show the owner first
  ([64](../60_asset_creation/64_hearthblock_art_direction.md), "Making new art").

The concepts and the option passed over (one cap in five colours) are in
`tmp/proposals_20261111/hats/`.

## Work tools — felling axe and mining pick

`assets/models/characters/dwarves/tools/felling_axe.glb` is separate from the 41 appearance parts.
`DwarfAssets` owns its preload; `DwarfFellingPose.gd` instantiates it under the
right hand when felling starts and hides it when work stops. Dwarves implicitly
carry their work tools, with no inventory, delivery or durability requirement.

Both tools are Hearthblock models (`tools/felling_axe` and `tools/mining_pickaxe` in
`dwarves.mjs`). They are stone bound with rope, as the careers' crafting tools are (owner,
2026-11-10, doc 301): square hafts with a lit grain face and rope grip bindings, heads in the
benches' worked stone, a dark skin with pale fresh stone where it was ground or knocked. The
axe is a ground blade set through the haft's swollen head and bound above and below it, its
butt showing at the back. The pickaxe is one long stone knapped to a point at each end,
seated across the haft's top and lashed there. The Carpenter's adze is a flat blade lashed
under the haft's bent knee, and the Stonemason's maul a hammerstone with a rope band round it.
The iron axe and pickaxe are drawn and wait in `tools/art_data/studies/iron_work_tools.mjs`
for the Blacksmith's upgrade; nothing builds that file.
They are exported in world units with a unit root.
Unlike the shared-frame body parts, its origin is the lower hand grip, with the
haft along +Y and blade facing +Z. Both hands rotate around their authored palm
centres and stay on the handle throughout the swing. The tool attachment cancels
the right hand's reflection; pose cleanup explicitly restores the original signed
scales so subsequent walking cannot flip the mirrored hand or boot. The axe uses
its own lit vertex-color material and is never skin-tinted. Navigation and
collision retain their existing logical footprint.

**The copper hoe** (`tools/copper_hoe` in `dwarves.mjs`, doc 309) is the Farmer's, and the first
copper tool in a dwarf's hands: the hoe good's own blade (the owner's pick B), lashed under the
bent knee of a haft nearly as long as the pickaxe's, set across it and swept forward and down
to an edge ground bright. It keeps the tools' grips (the lower grip at the origin, the upper at
`(0,.625,0)`), and its edge is `(0,1.375,.625)` (cell 0, 22, 10). `DwarfHoePose` raises it
beside the head, chops it into the tile a step ahead and draws it back through the soil; the
career names it as its `field_tool` (`DwarfAssets.field_tool`). `FarmingTest` checks the edge
and the hand it is held in.

**The blowing stick** (`tools/blow_stick` in `dwarves.mjs`, doc 300) is a hand prop of the same
kind: a peeled green stick 21 cells long with the pith pushed out, bark left on where the hand
holds it, its far end burnt black. Its origin is the grip, three cells from the mouth end, and
it runs up +Y. `DwarfSmeltPose` holds it in the right hand only while a Blacksmith blows on the
basic smelter's fire, and stretches it a little along its length so that its burnt end stays in
the fire hole.

The tool goods and the UI icons draw these same tools (owner, 2026-11-11). A tool good is the
item a dwarf collects on promotion (`starter()` in `tools/voxel_assets/hearthblock_goods.py`).
- **The Ranger's kit** is two tools crossed on the ground and lashed where they cross, heads
  together, so from above it is an X and never a bundle of sticks: a stone-tipped spear and the
  peeled rod, its line wound on and its float tied beside. The hafts run aslant, so they are
  drawn in one-cell steps. The crude carpentry and masonry kits, drawn the same way, were retired
  on 2026-11-13 (doc 306).
- **The copper tools** (doc 306; the owner's picks of 2026-11-13 from the sheet
  `tmp/profession_path_20261113/tools_sheet.png`: A for the pick, the saw and the chisel, B for
  the hoe): the pick is the stone
  pick's outline cast as one copper bar pointed at both ends, seated across the haft's top and
  lashed; the saw is a Japanese pull saw (the owner's words), a ryoba with a long corded handle
  in line with a blade that widens to its end, fine teeth down one edge and coarse down the
  other; the chisel lies crossed with the hammerstone maul that drives it, lashed where they
  cross as the kits were; the hoe has its blade lashed under the haft's bent knee, as the old
  carpentry kit's adze was, and lies on its side, the blade on edge, so from above it is a hoe's
  own profile.
  Copper is the copper bar's body colour on its shade, with its pale colour only on ground
  edges, points and teeth (doc 64, "Copper tools"); no tool holds more copper than one bar.
- **On the rack.** A tool hangs from a tool rack's hook by the end its head is at. The Ranger's
  kit is 39 cells long, which is the hook's height, so a longer tool would reach into the floor;
  the copper tools are 27 to 37 (`test_items.py` pins it).
- **In the hands.** The dwarves still hold the stone tools, but for the Farmer's copper hoe
  (above): the copper pick, the saw and the chisel in hand are doc 306's step 2. The nine icons that show a hand tool
(Orders, Mine, Chop, Clear stones, Clear plants, Miner, Carpenter, Stonemason and Blacksmith in
`icons.mjs`) draw it in worked stone and rope too, each in its own picture: the pickaxe, the
axe, a hammerstone maul, a stone sickle, the adze biting a split log, a stone point and the
maul at a Rough Stone knocked square, and the smelter's hollowed boulder with its fire and its
pot. None of them draws an iron tool before the Blacksmith makes one; the Miner's, the
Carpenter's and the Stonemason's still show stone tools, which doc 306's step 2 redraws in copper. The Worker's icon replays
the axe and the pickaxe themselves.

Both impact points are vertices in the meshes. The contract: the lower grip is the
origin, the upper grip is `(0,.625,0)`, the axe edge is `(0,1.0625,.6875)` (cell
0, 17, 11) and the pick point is `(0,1.375,.9375)` (cell 0, 22, 15).
`ItemArtTest`, `DwarfArtTest`, `MiningAnimationTest` and `TreeFellingTest`
check grips and strike points.
`assets/models/characters/dwarves/tools/mining_pickaxe.glb` has a longer haft and uses the
same material and grip convention. `DwarfMiningPose.gd` aims at the target voxel face
for wall, overhead, low and underfoot mining. Both rigs now inherit attachment,
material and mirrored-part reset behavior from `DwarfWorkToolPose.gd`. No body
parts or appearance IDs changed. Phase-0.92 pick contact now emits material-aware
sound and small chips through `WorkFeedback`; successful removal adds a brief
dust puff (doc 48 §6.2). Feedback is separate from pose evaluation, so previews,
contact holds and visibility changes do not replay sounds.

---

## Summary: What Needs to Be Authored

To have a fully working male dwarf with all options:
- **4** head base meshes (age tiers) + **1** eyes mesh + 1 torso-only body + 1 hand + 1 foot (base anatomy: **8**)
- **4** male hair style meshes
- **7** beard meshes
- **4** male eyebrow meshes
- **4** scar overlays
- **Total for males: 27 GLBs**

Add female hair styles (+10 GLBs) and female eyebrows (+4 GLBs) for full gender coverage: **41 GLBs total**, plus the work tools, the five trade hats and the 14 hairstyles as they lie under a hat.

Colours need no extra files: 8 hair and 4 skin colours are runtime tints, 6 eye colours
show on the portrait glint, and 6 tunic colours are shared recoloured meshes.

---

*Prev: [41_dwarf_agents.md](./41_dwarf_agents.md) | Next: [42_farming_brewing.md](./42_farming_brewing.md)*
