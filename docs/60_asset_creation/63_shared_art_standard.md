# 63 — Technical art standard

These are the renderer, pipeline and acceptance rules for every solid model. The look
itself is defined in [64 — Hearthblock art direction](64_hearthblock_art_direction.md),
and [61](61_voxel_art_guide.md) walks through building a model. World lighting is owned
by `SkyController`'s `hearthblock_lighting` block
([64 §Lighting](64_hearthblock_art_direction.md#lighting), doc 255).

All **385** production models are built by `tools/voxel_assets/` on the 1:16 grid.

## Scale and form

One world block is one Godot unit. The **1:16 ratio is linear on every axis**: sixteen
cells span one world-block edge, so one cell is **1/16 block = 0.0625 Godot unit**. A
full block holds 16×16×16 possible cells. Objects may span several blocks; they are not
limited to 16×16×16 cells.

- Solid object vertices lie on this local grid, with unit export and root transforms.
- Author occupied cells, or box and notched-box operations, and bake their exposed
  surfaces with the shared greedy mesher.
- Never create a node per voxel.

Keep local origins and articulation coordinates:
- Most standing forms are centred horizontally with the ground at Y0.
- Bridges sit below their walking plane.
- Limbs and tools keep joint-local coordinates.

Don't recentre parts. Uniform fitting in storage and catalogues is intentional.
Navigation, occupancy, interaction coordinates and save IDs belong to the gameplay
definitions. When the art needs a different rig, move the rig into data (see the
art-over-rigs rule in [64](64_hearthblock_art_direction.md)). Don't bend a gameplay
contract to fit the art.

Family contracts:
- **Trees** keep species crowns, growth stages, seasons, fruit and picked forms, and
  deterministic variants. They also keep their height envelopes, ground contact, trunk
  footprints and four-block clearance under the canopy. Fruit and blossoms touch the
  final canopy and stay visible, and juniper picking removes only the berries. Bare
  winter limbs stay connected to the grounded trunk. `voxel_trees.json` and `trees.py`
  own the forms.
- **Bushes, flowers and reeds** keep every young, seasonal, picked and packed path
  (`plants.py`, `voxel_plants.json`). Young crowns fit below their clearance with real
  depth. Packing translates the exact plant, and picking removes only the fruit.
- **Dwarves** keep detached hands and feet, all appearance pools, contacts and
  occupations. The hand is a mitten plus a separate untinted cuff mesh, and the closed
  eyelids (`presentation/`) sit exactly over the open bead eyes. The head layout
  rules and tool grips are listed in [64](64_hearthblock_art_direction.md). Any
  hairstyle may meet any beard and brows, so `dwarves.py` clips wearables against the
  torso, beards against every man's hairstyle and brows against hair and beards. It then
  covers the shared head's skin faces with one outward cell (`separate_overlay`), since
  the same head serves bald dwarves: no pairing may share cells or coincident faces.
- **Animals** are rigid voxel parts on rigs read from each definition's `visual_pose`;
  `wildlife.py` splits the deer and wolf legs at the same `visual_pose.knee_y`. Only the
  visual root squashes and stretches, and only while the animal moves
  (`GrazerAgent._squash_stretch`, amount in `visual_pose.squash`), keeping volume and
  feet. Parts are never scaled on their own.
- **Furniture** keeps footprints, collision, seat and sleep heights, hinges and walking
  surfaces. Table chair profiles, working points, material IDs and saved identities
  belong to the furniture definitions.
- **Goods** read at inventory and carrying scale and keep their footprints. Mined
  fragments stay within 12×12×12 cells (0.75 units) with ground contact. Crates have
  distinct low, half and full contents.

## Production inventory and sources

| Family | Location under `assets/models/` | GLBs |
|---|---|---:|
| Trees | `flora/trees/` | 94 |
| Bushes, flowers, reeds | `flora/{bushes,flowers,reeds}/` | 76 |
| Defined crops | `flora/crops/` | 14 |
| Ground stones | `rocks/` | 6 |
| Dwarves and their work tools | `characters/dwarves/` | 43 |
| Eyelids and meal servings | `presentation/` | 3 |
| Wildlife | `animals/` | 23 |
| Furniture, support forms and flame libraries | `furniture/` | 33 |
| Loose goods | `items/` | 86 |
| Materials crate and built log pieces | `construction/` | 2 |
| **Total** | | **380** |

Crops fill **defined art paths** only; they don't add farming behaviour.

Authoring inputs:
- Hearthblock operations in `tools/art_data/voxel_hearthblock.json`, written from
  `tools/hearthblock/art/*.mjs` by `write_data.py` and replayed by `hearthblock.py`;
- the family profiles `tools/art_data/voxel_*.json`;
- semantic swatches in `data/materials/craft_materials.json`;
- the family builders in `tools/voxel_assets/`.

The pipeline:
1. `build.py FAMILY` writes a complete staged manifest and GLBs.
2. `Gallery.gd --family=FAMILY` reviews the staged bytes in Godot.
3. `activate.py` installs, but only after that complete, exact-hash review.
4. `build.py FAMILY --check` regenerates and compares every installed byte.

Installed manifests in `tools/art_data/voxel_manifests/` are the export authority.
`test_coverage.py` checks production coverage and hashes.
Coverage requires each family to produce exactly the paths listed for it in
`tools/art_data/voxel_expected.json`.
- A new model: add its path there.
- A removed model: delete its path there, and delete the `.glb`, its `.import` file
  and any staged copy.

Don't hand-edit `.import` or `.tres`; use Godot's importer. Root scale stays 1.

## Baked occlusion

Occlusion is opt-in (`greedy_mesh_from_voxels(..., occlusion=...)`); families without it
rebuild byte for byte.
- Each face corner counts its two side cells and one diagonal cell, on the curve
  `[0.5, 0.68, 0.85, 1.0]` from `tools/art_data/voxel_occlusion.json`.
- Floors (a model's `ground` setting) and the wall behind a wall-mounted piece (`wall`,
  the torch) count as solid for shading only, never for face culling.
- Faces merge only when their colour and all four corner levels agree; each quad's
  diagonal follows the brighter pair of corners.
- Each shaded vertex stores its shade in UV2, because a darkened swatch can equal another
  swatch of the same wood. `CraftMaterials` matches the unshaded swatch at that shade
  within one 8-bit step. `test_hearthblock` simulates that recolour.

Trees skip occlusion: on their large stepped faces it tripled the triangle count.

## Materials and shadows

Use one opaque vertex-colour surface per rigid mesh, with shared, cached resources
through the existing owner.
- Convert authored sRGB to linear `COLOR_0` exactly once. No palette texture is needed.
- A shared material helps reuse but doesn't guarantee one draw call for unrelated
  MeshInstances.

Recolouring:
- Skin, hair and eye tints are applied at runtime.
- The tunic and mitten cuffs are recoloured per dwarf (`DwarfAssets.dress` →
  `CraftMaterials.apply_colors`), with one shared mesh per colour.
- Furniture and starter tools use exact semantic wood colours from `CraftMaterials`.
  Hay, stone, metal, leaves and flame must not share recolourable wood swatches. A
  definition's `material_palette` names its source profile (`source_palettes` in
  `craft_materials.json`), the authored wood swatches to replace. The recolour also
  matches each swatch as Godot imports it, truncated to 8 bits, and caches one copy per
  original mesh, profile and material (doc 118).
- Test pine, oak, juniper and applewood on real imported geometry. Recolour copies
  through the owner without modifying cached source meshes.
- Keep gem gloss, flame emission and underground and slice lighting.

Each shadow-casting rigid part contains **VoxelVisual / VoxelShadowProxy** siblings under
the same moving pivot (doc 222), so animation, mirroring and slice visibility move the
pair together. A multi-part GLB names them `VoxelVisual__<part>` and
`VoxelShadowProxy__<part>`, because Godot's glTF importer makes node names unique across
the whole file, not only among siblings (`export_asset` in `tools/voxel_assets/common.py`).
- The proxy is an inscribed coarse mesh (`tools/voxel_shadow.py`). Cells are binned at
  stride 4, only fully occupied bins survive, boundary bins are clipped to the asset's
  bounds and holes stay open, so the proxy never swells past the visible surface and
  falsely shadows it. Colour is ignored. Below 60% of the source volume, or 80% of its
  span on any axis, the stride halves and the proxy is rebuilt, so thin branches, limbs
  and tiny objects keep finer proxies. Manifests record each part's stride, retained
  volume and triangles.
- `VoxelShadowSetup.configure(root)` sets the visual mesh to **Off** and the proxy to
  **Shadows Only**, with proxy GI disabled. Every loader must configure its output
  before rendering, including galleries and special placement paths.
  - World loaders get it from `UndergroundLighting.bind_world_tree()` and `bind_tree()`,
    even before a lighting owner exists. Meshes added later under a bound tree are
    configured as they enter.
  - An editor-authored scene adds a node with `VoxelShadowSetup.gd` under the asset's
    wrapper; its `_ready()` configures the parent in the editor and at runtime.
  - glTF can't store Godot's shadow-casting setting, so a bare GLB applies neither role.
- `set_casting(root, false)` keeps a non-casting policy through later world-light
  binding. Use it for ghosts, thumbnails, portraits and floor icons. `FurnitureLighting`
  sets it on every piece with a light unless its definition sets `body_shadows` (the
  hearth's masonry does), so a torch never shadows its own light.
- Flames, eyelids and servings carry explicit non-casting metadata (glTF extras
  `voxel_cast_shadow: false`). Never give a proxy a visible, emissive or transparent
  material.
- Picking, bounds, recolouring, readability outlines, portrait cloning, menu pictures
  and terrain floor baking use the visual meshes only (`VoxelShadowSetup.visual_meshes`).

Rigid reflections use `RigidMeshReflection.gd` (reflected vertices, corrected normals,
tangents and winding, cached immutable meshes, positive render scales). Closed voxel
actors and furniture use backface culling. The closed and underground shaders share
one lighting body; don't fork the lighting equations.

## World and effect boundaries

- World terrain blocks stay simple one-unit voxels. Stone, grass and earth carry the
  Hearthblock dressing in `terrain_appearance.gdshaderinc` (values in
  `appearance_profiles.json` → `dressing`); bedrock and ore blocks are unchanged. Marks
  are whole 1:16 cells that fade out before a cell shrinks below a pixel and stay quiet
  on slice caps. The dressing's fine seam replaces those profiles' soft seam
  (`seam_strength` 0), and zeroing a profile's `dressing` turns it off.
- Built logs (doc 275) are not terrain faces. `BuiltLogs` draws each log block as a piece
  of `construction/logs.glb`: 80 named parts (lying, upright and joint pieces, each in four
  plate variants) made by `tools/voxel_assets/built_logs.py` from the loose log's recipe,
  in the hand-hewn source palette that CraftMaterials recolours for each wood. Build's
  log pictures are the same recipe in each wood (`icons.py`, rendered by
  `GenerateUiIcons.gd`). See doc 24, "Built logs".
- Liquid simulation, sky, fog and weather keep their owners. The atmosphere stays the
  quiet diorama backdrop of doc 166, whose rules are in
  [24 §Sky](../20_player_interface/24_world_rendering.md#sky).
- Dust and chip cubes, splash foam and duck wakes are intentional non-casting effects.
  Keep their opacity, fading and motion.
- UI icons are Hearthblock models in a staged-only `icons` family: their GLBs never ship;
  `tools/GenerateUiIcons.gd` renders them to PNGs in `assets/ui/icons/` (doc 259).
- The Sky Dial's pieces are Hearthblock models in a staged-only `sky` family, rendered the
  same way to layers in `assets/ui/sky_dial/` that share one framing (doc 23, "The Sky
  Dial").
- The remaining illustrated menus, outlines and painted loading screens keep their own
  visual language.

## Required acceptance for a model change

1. Regenerate every defined variant, not only the mature summer example. Keep state
   availability, IDs, paths and saved forms.
2. Pass the source mesher and proxy tests and the imported root, grid, palette and part
   checks. Source vertices are exact; imported compression uses the documented tolerance.
3. Review the gallery, then the game under Hearthblock lighting, close up and at colony
   zoom. Cover all relevant poses, materials, portraits, catalogue, carrying and packed
   states.
4. Exercise the affected gameplay: worker tasks, contacts, storage, placement, picking,
   navigation, season refresh and save/restore. Change tests that only pin old shapes,
   but never waive a behaviour assertion.
5. Record byte-identical regeneration, full coverage and the geometry cost. Re-render
   the menu pictures that show the model.

Use copied saves in isolated profiles. Never touch the player's original saves, and
don't make a Windows playtest export unless asked. Compare full-world frame and GPU
cost against a matched fixture; a static gallery or a triangle reduction is not a
whole-game speedup.
