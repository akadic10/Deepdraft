# 41b — Dwarf Appearance & GLB Construction

## Overview

This document catalogues every visual attribute a dwarf can have and defines the modular GLB file strategy for constructing them at runtime. The design goal is the minimum set of authored files that can express all valid combinations without duplicating geometry per color variant.

---

## Attribute Catalogue

All attributes are drawn from `data/entities/dwarves/appearance.json`. They fall into two categories: **color attributes** (applied via runtime material/shader tinting — no separate mesh per value) and **shape attributes** (each variant is a distinct GLB file).

### Color Attributes — Both Genders

| Attribute | Values | Notes |
|---|---|---|
| `skin_tone` | pale · medium · tan · dark | Applied to `head_[age].glb` and `body_base.glb` |
| `eye_color` | grey · blue · green · brown · amber · red | Applied to `eyes.glb` — separate node, not embedded in head |
| `hair_color` | black · dark_brown · brown · auburn · red · blonde · grey · white | Applied to all hair/beard/brow shape meshes |

### Shape Attributes — Both Genders

| Attribute | Values | Representation |
|---|---|---|
| `age_tier` | young · adult · middle · elder | 4 head base GLBs — geometry differs (wrinkle depth) |
| `scar` | none · cheek_slash · brow_notch · nose_bridge · chin_split | Portrait-only overlay child; "none" = no node added |

### Shape Attributes — Male

| Attribute | Values | GLB files |
|---|---|---|
| `hair_style` | short_back · shaved · wild_loose · braided_back · bald | 5 GLBs (`hair_m_[id].glb`); bald = no node added |
| `beard` | full_long · full_braided · short_trimmed · forked · mutton_chops · goatee · braided_long · *(none)* | 7 GLBs (`beard_[id].glb`); no beard = no node added |
| `eyebrow_style` | thick_flat · bushy · arched · unibrow | 4 GLBs (`brows_m_[id].glb`) |

### Shape Attributes — Female

| Attribute | Values | GLB files |
|---|---|---|
| `hair_style` | bun · braid_side · braid_long · short_practical · twin_braids · half_up · loose_long · shaved_sides · cropped · wild | 10 GLBs (`hair_f_[id].glb`) |
| `eyebrow_style` | thin_arched · thick_flat · bushy · sharp_angled | 4 GLBs (`brows_f_[id].glb`) |

---

## GLB File Inventory

All files live under `assets/dwarves/`. Total: **~45 GLB files**.

```
assets/dwarves/
  body/
    head_young.glb
    head_adult.glb
    head_middle.glb
    head_elder.glb
    eyes.glb          ← shared across all age tiers and genders; tinted at runtime
    body_base.glb
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
```

> **bald** male hair style and **none** beard/scar = simply no child node added. No GLB needed.

---

## Scene Hierarchy

Every dwarf scene at runtime follows this structure:

```
DwarfAgent (CharacterBody3D)
  ├─ MeshHead    (MeshInstance3D)  ← head_[age_tier].glb
  │   ├─ MeshEyes  (MeshInstance3D)  ← eyes.glb                      (always present; tinted per eye_color)
  │   ├─ MeshHair  (MeshInstance3D)  ← hair_[gender]_[style].glb     (absent if bald)
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

---

## Color Application Strategy

Colors are never baked per-file. Every shape GLB is authored in a **neutral palette** (e.g. mid-grey for hair, light pink for skin). At runtime, a material override applies a tint.

### Palette Reservation (MagicaVoxel)

When authoring in MagicaVoxel, reserve specific palette index ranges per semantic use:

| Palette slot range | Semantic |
|---|---|
| 1 – 4 | Skin (highlight → shadow) |
| 5 – 8 | Hair (highlight → shadow) |
| 9 – 10 | Eye (iris, pupil) |
| 11 – 14 | Clothing/body base |
| 15+ | Free use per mesh |

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

Eyebrows are visible at colony zoom and contribute meaningfully to character silhouette and personality — they should always be present. Only scars are portrait-only. For the map mesh, simply skip adding `MeshScar`. For the portrait render, add all applicable children.

---

## DwarfAppearanceData Resource

Define appearance as a typed `Resource` so it serializes cleanly with the save system and can be passed around without loose dictionaries.

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
    "young":  preload("res://assets/dwarves/body/head_young.glb"),
    "adult":  preload("res://assets/dwarves/body/head_adult.glb"),
    "middle": preload("res://assets/dwarves/body/head_middle.glb"),
    "elder":  preload("res://assets/dwarves/body/head_elder.glb"),
}
var eyes:  Mesh = preload("res://assets/dwarves/body/eyes.glb")
var body:  Mesh = preload("res://assets/dwarves/body/body_base.glb")
var hand:  Mesh = preload("res://assets/dwarves/body/hand.glb")
var foot:  Mesh = preload("res://assets/dwarves/body/foot.glb")

var hair_male: Dictionary = {
    "short_back":   preload("res://assets/dwarves/hair/hair_m_short_back.glb"),
    "shaved":       preload("res://assets/dwarves/hair/hair_m_shaved.glb"),
    "wild_loose":   preload("res://assets/dwarves/hair/hair_m_wild_loose.glb"),
    "braided_back": preload("res://assets/dwarves/hair/hair_m_braided_back.glb"),
    "bald":         null,
}
var hair_female: Dictionary = {
    "bun":             preload("res://assets/dwarves/hair/hair_f_bun.glb"),
    "braid_side":      preload("res://assets/dwarves/hair/hair_f_braid_side.glb"),
    "braid_long":      preload("res://assets/dwarves/hair/hair_f_braid_long.glb"),
    "short_practical": preload("res://assets/dwarves/hair/hair_f_short_practical.glb"),
    "twin_braids":     preload("res://assets/dwarves/hair/hair_f_twin_braids.glb"),
    "half_up":         preload("res://assets/dwarves/hair/hair_f_half_up.glb"),
    "loose_long":      preload("res://assets/dwarves/hair/hair_f_loose_long.glb"),
    "shaved_sides":    preload("res://assets/dwarves/hair/hair_f_shaved_sides.glb"),
    "cropped":         preload("res://assets/dwarves/hair/hair_f_cropped.glb"),
    "wild":            preload("res://assets/dwarves/hair/hair_f_wild.glb"),
}
var beards: Dictionary = {
    "full_long":      preload("res://assets/dwarves/beards/beard_full_long.glb"),
    "full_braided":   preload("res://assets/dwarves/beards/beard_full_braided.glb"),
    "short_trimmed":  preload("res://assets/dwarves/beards/beard_short_trimmed.glb"),
    "forked":         preload("res://assets/dwarves/beards/beard_forked.glb"),
    "mutton_chops":   preload("res://assets/dwarves/beards/beard_mutton_chops.glb"),
    "goatee":         preload("res://assets/dwarves/beards/beard_goatee.glb"),
    "braided_long":   preload("res://assets/dwarves/beards/beard_braided_long.glb"),
}
var brows_male: Dictionary = {
    "thick_flat": preload("res://assets/dwarves/eyebrows/brows_m_thick_flat.glb"),
    "bushy":      preload("res://assets/dwarves/eyebrows/brows_m_bushy.glb"),
    "arched":     preload("res://assets/dwarves/eyebrows/brows_m_arched.glb"),
    "unibrow":    preload("res://assets/dwarves/eyebrows/brows_m_unibrow.glb"),
}
var brows_female: Dictionary = {
    "thin_arched":  preload("res://assets/dwarves/eyebrows/brows_f_thin_arched.glb"),
    "thick_flat":   preload("res://assets/dwarves/eyebrows/brows_f_thick_flat.glb"),
    "bushy":        preload("res://assets/dwarves/eyebrows/brows_f_bushy.glb"),
    "sharp_angled": preload("res://assets/dwarves/eyebrows/brows_f_sharp_angled.glb"),
}
var scars: Dictionary = {
    "cheek_slash": preload("res://assets/dwarves/scars/scar_cheek_slash.glb"),
    "brow_notch":  preload("res://assets/dwarves/scars/scar_brow_notch.glb"),
    "nose_bridge": preload("res://assets/dwarves/scars/scar_nose_bridge.glb"),
    "chin_split":  preload("res://assets/dwarves/scars/scar_chin_split.glb"),
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

## Summary: What Needs to Be Authored

To have a fully working male dwarf with all options:
- **4** head base meshes (age tiers) + **1** eyes mesh + 1 body + 1 hand + 1 foot (base anatomy: **8**)
- **4** male hair style meshes
- **7** beard meshes
- **4** male eyebrow meshes
- **4** scar overlays
- **Total for males: 27 GLBs**

Add female hair styles (+10 GLBs) and female eyebrows (+4 GLBs) for full gender coverage: **41 GLBs total**.

All colors (8 hair, 4 skin, 6 eye) are zero additional files — handled by the tint shader.

---

*Prev: [41_dwarf_agents.md](./41_dwarf_agents.md) | Next: [42_farming_brewing.md](./42_farming_brewing.md)*
