# 63 — Shared world art standard

**Atmosphere (2026-10-13):** [166 — Diorama sky](../00_dev_roadmap/166_diorama_sky.md)
adds a continuous blue full-sphere backdrop with restrained stars, warm celestial
discs and broad cloud forms. Keep this backdrop quieter than the colony. Haze
must follow time/weather and physical roof cover. Sky tuning belongs to the
sky/weather JSON; no textured sky dome or duplicate model family is needed.

Finalized **2026-10-13** from the player-approved terrain, surface clutter,
[dwarf](../00_dev_roadmap/150_dwarf_art_pilot.md),
[deer](../00_dev_roadmap/151_animal_art_pilot.md) and
[starter furniture](../00_dev_roadmap/152_furniture_art_pilot.md).
This completes the authoring-standard step of the
[world art roadmap](../00_dev_roadmap/144_world_art_direction_handoff.md).

**Direction: voxel-inspired, stylized low-poly forms on an editable voxel world.**
Use broad flat-shaded planes, strong silhouettes, restrained color variation and
selective bevels. Keep the weight and warmth of dwarven craft, the character of
each plant and animal, and clear material differences at normal colony zoom.

This is the visual standard for new art and planned conversions. It supersedes
the universal cube-only, integer-vertex, fixed voxel-resolution and master-palette
assumptions in [61](61_voxel_art_guide.md). That guide and the family documents
retain existing inventories, dimensions, state mappings and gameplay contracts.
An approved style does not replace an asset in normal Play: migrate each family
explicitly, retaining its IDs, variants and interaction behavior.

## Approved references and integration status

| Family | Reference | Status in normal Play |
|---|---|---|
| Rock, dirt, grass and damp ground | [145 — Terrain](../00_dev_roadmap/145_base_world_terrain_art_plan.md) | Integrated, including the shoreline correction. |
| Pine, oak, apple and juniper | [146](../00_dev_roadmap/146_tree_art_pilot.md), [147](../00_dev_roadmap/147_complete_tree_family.md) | All 94 current tree models integrated. |
| Berry bushes, wildflowers and reeds | [148 — Surface vegetation](../00_dev_roadmap/148_surface_vegetation.md) | All 76 current models integrated, including required states. |
| Boulders and loose stones | [149 — Ground stones](../00_dev_roadmap/149_ground_stones.md) | All six models integrated. |
| Dwarves | [150 — Dwarf pilot](../00_dev_roadmap/150_dwarf_art_pilot.md), [154 — Conversion](../00_dev_roadmap/154_complete_family_conversion.md) | All 41 appearance parts integrated; eight approved exports retained exactly. |
| Wildlife | [151 — Deer pilot](../00_dev_roadmap/151_animal_art_pilot.md), [154](../00_dev_roadmap/154_complete_family_conversion.md) | All 21 parts across rabbit, deer, wolf and duck integrated. |
| Furniture | [152 — Furniture pilot](../00_dev_roadmap/152_furniture_art_pilot.md), [154](../00_dev_roadmap/154_complete_family_conversion.md) | All 30 definitions and 41 forms integrated, including access, legacy and packed forms. Stump correction in 159; fire conversion in 160. |
| Loose goods and work tools | [155 — Resource drops and work tools](../00_dev_roadmap/155_resource_drops_and_work_tools.md) | All remaining 62 item definitions / 92 presentations and both animated tools integrated. |
| Fire effects | [160 — Faceted fire](../00_dev_roadmap/160_faceted_fire.md) | Six static flames and all 42 frames in five shared animation libraries converted. Furniture bodies, light/heat and timing retained. |

The illustrated Hearth & iron menus and HUD keep their own established style.
Cave flora, growing crops and unconverted effects
keep their current art until their family is reviewed. Retain pieces that already
fit; this standard does not require replacing every model.

## Production asset layout

[156 — Legacy art cleanup](../00_dev_roadmap/156_legacy_art_cleanup.md) removes
superseded voxel exports and duplicate pilots.
[157 — Folder layout](../00_dev_roadmap/157_asset_folder_layout.md) then removes
the redundant `faceted` directory layer.
[158 — Asset structure](../00_dev_roadmap/158_asset_structure.md) puts every
3D model under `assets/models/`. The asset root groups media types (`models`,
`audio`, `ui`); model folders group subject families, then useful species or
part categories. Use these production locations:

| Family | Folder | GLBs |
|---|---|---:|
| Trees | `assets/models/flora/trees/` | 94 |
| Bushes, flowers and reeds | `assets/models/flora/{bushes,flowers,reeds}/` | 76 |
| Ground stones | `assets/models/rocks/{boulders,scree}/` | 6 |
| Dwarf appearance | `assets/models/characters/dwarves/` (body, hair, beards, eyebrows, scars) | 41 |
| Wildlife | `assets/models/animals/<species>/` | 21 |
| Furniture and packed forms | `assets/models/furniture/` | 41 |
| Loose goods | `assets/models/items/` | 92 |
| Animated work tools | `assets/models/characters/dwarves/tools/` | 2 |

Keep rig-specific work tools beside dwarf parts; independent dropped/carried
goods belong in `items/`. Trees, bushes, flowers and reeds are peer flora
categories. Rocks have an explicit family instead of a generic `details` folder.
Add species or part subfolders when the inventory calls for them, and add new
families when actual assets need them. Avoid style/version folders and duplicate
production exports. Generators and JSON paths must target the same structure.

The three construction-floor GLBs remain in `construction/`; the five flame
animation libraries remain in `furniture/animations/`.
The `wooden_chair_legacy` production model supports an existing furniture form;
its name does not mean it is obsolete art. Earlier reports preserve historical
paths, screenshots and costs; those paths are no longer a live asset inventory.

## Form, proportions and detail

The post-conversion [visual scale study](../00_dev_roadmap/162_visual_scale_review.md)
compares these dimensions against the earlier settlement concept. Its 90% actor
and 75% tree instances are review trials, not new export standards. Keep the
production contracts below until a specific proportion change is accepted.
The [Stonehearth comparison](../00_dev_roadmap/163_stonehearth_scale_comparison.md)
confirms nearly equal character heights and matching pine heights in the sampled
references, with broader Deepdraft dwarf proportions. Its height-matching toggle
also remains a study-only trial.
The player selected **Balanced dwarves and Large wolves** from the
[proportion trials](../00_dev_roadmap/164_dwarf_wolf_proportion_trials.md).
[165 — Approved proportions](../00_dev_roadmap/165_approved_actor_proportions.md)
integrates them while keeping dwarf and pine heights fixed. Dwarf resting span
is now 2.16 blocks; the standing wolf is 2.392 high and 3.411 long. Wolf navigation
uses four-wide, three-high clearance and retains two-cell flat strides.

Start with the silhouette beside a one-block cube and the approved dwarf. Make
the object recognizable from the ordinary RTS camera before adding close-up
detail. At colony zoom, foliage reads as clusters, stone as broad fractures,
wood as substantial members, and faces through head, hair and beard shape.
Preserve species differences; animal limbs and flower stems need not have the
same thickness as furniture legs or a dwarf's boots.

Use flat normals and deliberately placed planes. Tapered prisms, rotated masses,
sloped faces and fractional world coordinates are normal authoring tools.
Bevel an edge when it improves the silhouette or catches useful light; keep a
broad face between bevels. Match the approved family reference at the same scale
instead of applying one bevel width to everything. Avoid smooth inflated forms,
dense microfacets, random per-face noise and separate leaves that disappear at
play distance. Sparse grain, seams, pegs and chips should explain construction.

| Family | Shape language |
|---|---|
| Trees and bushes | Closed foliage masses, visible branch structure where useful, tapered faceted wood; preserve distinct crowns and bush profiles. |
| Flowers and reeds | Closed faceted leaves/petals and tapered stems; small clumps with readable blooms or seedheads. |
| Natural stones | Irregular broad fracture planes and selective softened corners; loose stones stay grounded with open gaps. |
| Dwarves | Broad expressive heads, shaped hair/beards, substantial mittens and boots, simple clothing planes; detached hands and feet retain the existing rig. |
| Animals | Recognizable anatomy and species proportions; tapered limbs/muzzles, pointed ears and restrained coat planes. The deer sets the finish, not every species' body shape. |
| Starter furniture | Rough logs, uneven cuts, simple pegs and loose fibre. The crude workbench is a solid bark-covered stump with an axe-hewn top, not a fitted table. Log bridges use whole bark-covered trunks on cross logs, with no sawn plank deck. Stool has no arms/back; bed has loose hay; log doors remain frameless. |
| Later craft tiers | Introduce shaped joinery, dressed stone, metal fittings or upholstery only where the item's existing tier calls for them. |
| Loose goods and tools | Fractured raw stone/ore, dressed blocks, bark-covered timber, broad jewel facets and open crates with readable contents. Starter inventory tools remain stone and pegged wood; existing cosmetic work tools retain iron heads and grip wraps. |

Terrain retains its production treatment: merged exposed faces with subtle edge
shading. True terrain chamfers remain a study alternative. Keep coherent grey
rock with deterministic local variation, restrained earth and **full seasonal
grass voxels**. Height-based rock bands, grass edge-color rings and moving pale
shoreline bands are retired. Damp ground darkens through the shared terrain
palette. Turf caps, soil sides inside a grass voxel and grass fringes are deferred.

## Color and material ownership

Use muted natural greens and coherent grey rock, with warm wood and firelight.
Reserve stronger colors for readable identity: fruit, flowers, character features,
ore or an established magical material. Let scene lighting reveal facets; subtle
authored variation can describe material and recesses without painting hard
sunlight, mandatory bright top bands or deep shadows onto every face.

| Color source | Authoring rule |
|---|---|
| Terrain | Use `data/terrain/appearance_profiles.json` and `surface_palettes.json` through their existing owner. Preserve seasonal and damp-ground behavior. |
| Trees, surface vegetation and ground stones | Use the accepted `data/art/tree_pilot.json`, `surface_vegetation.json` and `ground_stones.json` profiles. Keep variant and seasonal relationships coherent. |
| Dwarves | Preserve runtime skin, hair and eye tints. Clothing and boots keep baked colors and white tint treatment. Use `data/art/dwarf_pilot.json`, `dwarf_roster.json` and the assembly rules in [41b](../40_economy_colony/41b_dwarf_appearance_glb.md). |
| Wildlife | Use `data/art/deer_pilot.json` and `wildlife.json` with the existing animal material path; retain species and sex palettes. |
| Furniture | Exact semantic wood swatches come from `data/materials/craft_materials.json`. The stool uses `camp_log`; other selectable wood including the converted campfire uses `oak_log`. Independent hay/leaves use `furniture_pilot.json`; stone, metal and fabric use `furniture_catalog.json`. |
| Items and work tools | `data/art/items.json` owns offline palettes. Selectable starter tools use the exact `starter_tool` swatches from CraftMaterials. Keep shared ore/gem shapes across material identities, coal dark throughout, and existing gem gloss through ItemDropManager. |

For the new baked-color GLBs, convert authored sRGB colors to linear `COLOR_0`
once. Retain the owner's color interpretation; do not introduce a second
conversion. Dwarf runtime tinting remains a separate established contract.
CraftMaterials must recognize both source linear values and Godot's packed
RGBA8 values. Do not reuse semantic wood colors on hay, leaves, stone, metal or
flame in a mapped model. Verify pine, oak, juniper and applewood against the
actual imported resource, preserving geometry and non-wood colors. Recolor
cached copies through the owner; keep source meshes unchanged. Shared packed
furniture crates stay neutral.

Use the existing lit material and slicing/lighting path for each owner. Solid
props default to one opaque vertex-color surface per mesh, without new textures
or unnecessary material splits. Reuse resources through existing caches; avoid
adding per-instance materials. Existing animal/dwarf material behavior remains
in place. Water, fire and other established effects retain their own transparency,
emission and animation requirements.

## Scale, geometry and interaction contracts

**One world block is one Godot unit.** Export new geometry in world units with
unit root transforms and import root scale 1. Bake any internal modeling scale
once. Most standing assets are centered horizontally with ground at Y0; retain
explicit family origins for cell-aligned structures and joint-local parts.
Do not recenter individual modular parts or apply scale twice. Dwarf right-side
rig frames remain mirrored, but rendered limb transforms must have a positive
determinant. `DwarfAssets.mirrored_limb_mesh()` caches reflected geometry with
corrected normals, tangents and triangle winding; `DwarfAgent` counter-reflects
the inner mesh node. Preserve that pairing, source colors and immutable imported
meshes. A plain negative render scale caused the mismatched hand/boot lighting
fixed in [175](../00_dev_roadmap/175_dwarf_limb_lighting.md). Verify paired limbs
under matched daylight and torchlight without changing their shared tint rules.

The approved assembled proportions are explicit rig presentation settings:
`DwarfAssets` owns `data/entities/dwarves/proportions.json`; `WildlifeManager`
owns the wolf definition's `visual_scale`. Dwarf body/head X factors are .8/.93;
wolf visual X/Y/Z factors are 1.65/1.30/1.75. Meshes keep their existing unit
roots, shared coordinates and articulation pivots. Do not bake these factors
into exports as well. Portraits, eyelids and work/rest resets must retain them.

Build closed components with finite, nondegenerate triangles and consistent
outward normals. Avoid coplanar overlays, floating bases and visible gaps during
motion. Several closed masses may form one model. Keep separate meshes wherever
the runtime needs articulation, animation, tinting or a named attachment; do not
merge a character or door assembly merely to reduce mesh count.

| Contract | Boundary to preserve |
|---|---|
| Dwarf | Logical 1×1×3 body; the approved adult reaches 3.32 visually with a 2.16 resting hand span. Body/head X factors .8/.93; relaxed hands/feet inset .22/.06 per side. Shared feet frame, floating hands/feet, palm `(1.0625, 1.25, .1875)`, local eye/lid coordinates and tool/carry contacts stay fixed. Do not add limbs to the torso. |
| Deer | Logical 2×2 footprint and four-block clearance. Neck pivot `(0, 1.5, -.3)`, head origin `(0, 2.65, -.55)`, hip height `1.25`; leg mesh remains hip-local. Preserve grazing reach, sole contact and antler clearance through the live poses. |
| Wolf | Approved Large rig: standing 2.392×1.287×3.411 H/W/length. Full 4×4 support footprint, three-block clearance; two-cell flat strides and four-cell terrace transitions with proportionate duration. Preserve source pivots, scaled hop/rest offsets, capture rules and pose-ground contact. |
| Log stool and bed | Stool fits 1×1 with top at `.75`; bed fits 4×3 with sleep surface `.75`, head hay no higher than 1 and head at local −X. Preserve production sitting/sleeping contacts and rotations. |
| Crude workbench | One-tile solid stump with its central cut face at the existing `.875` crafting height; all four sides remain usable. Preserve worker material/axe contacts and selectable wood palettes. See [159](../00_dev_roadmap/159_crude_workbench_stump.md). |
| Log bridge | Four rough trunks across the existing two-wide crossing, in five span lengths. Keep the bank-relative origin, Y0 log crowns and buried bank tails; selection, support and navigation use the existing grid. See [172](../00_dev_roadmap/172_rudimentary_log_bridge.md). |
| Two-wide door | Fit 2×1 beneath four-block clearance; all moving geometry belongs to `leaf_left`, hinged at the outer edge, local X −1. Keep the opening frameless. Wider doors retain their own leaf contracts. |
| Trees and plants | Visual canopy/leaf overhang is separate from logical trunk/support occupancy. Preserve trunk origin, stage envelope and required walkable space; never add canopy collision. Planting spacing is a separate rule. |
| Ground stones | Boulder fits 2×2×2; scree fits 3×3 below `.5` height. Owner retains boulder blocking and scree walkability. |
| Loose items | Ground at Y0; logs and crates fit radius `.5` at every yaw. Crates retain 24-unit capacity and low/half/full thresholds 1–8 / 9–16 / 17–24. Long inventory tools retain their category envelope and ground orientation. |
| Animated work tools | Root at lower-hand grip, shaft +Y, strike +Z. Support grip `(0,.625,0)`, axe edge `(0,1.0625,.6875)`, pick point `(0,1.375,.9375)`. Keep these points in actual mesh geometry; poses and reach are unchanged. |
| Terrain and floors | Preserve grid identity, support, mining, water, discovery and slice concealment. Permanent floor previews fill a full support voxel with their existing cell origin and top height. |

Gameplay definitions remain with their registry/manager. Do not embed collision
in the new art GLBs or change occupancy to follow every silhouette detail.
Preserve IDs, save fields, recipes, yields, work times, navigation and selection
behavior. An actual footprint or interaction change is separate gameplay work.

## Authoring and acceptance workflow

The accepted generators are `tools/generate_tree_pilot.py`,
`generate_surface_vegetation.py`, `generate_ground_stones.py`,
`generate_dwarf_faceted.py`, `generate_wildlife_faceted.py` and
`generate_furniture_faceted.py`, `generate_items_faceted.py` and
`generate_fire_faceted.py` in the same directory.
The pilot-named helper generators now write directly to production locations;
family generators rebuild their approved base geometry instead of copying duplicate
exports. Matching `data/art/` profiles are offline authoring inputs, not runtime
gameplay registries. `fire_effects.json` owns tapered flame geometry and warm
vertex-color gradients. The fire generator updates all six static named flames
and all five clips together; the furniture builder uses the same first frames.
The unused legacy `furniture_flames.json` mesh dump was removed in 160 after
external backup. Update the current sources and regenerate the affected family.
Historical voxel export commands remain guarded. Manual modeling can follow
the same exported GLB contracts.
Use Godot's importer; never hand-edit `.import` or `.tres` files.

Follow-up revisions are recorded with exact previous/current fingerprints in
`data/art/asset_revisions.json`. Offline audits check these explicit revisions
while keeping the original milestone reports and unrelated export hashes intact.

Each family change should provide:

1. **Reproducible art:** generator `--check` and relevant geometry checks; validate
   imported roots, bounds, materials, colors and required part names in Godot.
2. **Complete state coverage:** keep appearance pools and seasonal/stage indices;
   picked variants remove only fruit, while packed plants preserve the plant above
   the root bundle. Preserve existing state availability instead of inventing
   growth or harvest behavior.
3. **Native visual comparison:** matched lighting, scale and camera at close and
   colony zoom. Check silhouettes, contacts, shadows and slice visibility. Use
   actual runtime poses and material variants; include portraits/catalogue
   previews when integrating the family.
4. **Relevant gameplay checks:** exercise affected workers, placement, picking,
   navigation, interactions and current-save restoration. Use existing fixtures
   and focused adapters; an attractive posed viewer is not behavioral evidence.
5. **Recorded cost and scope:** retain triangle, visible mesh/surface and file-size
   comparisons, evidence paths and an explicit list of converted assets. Preserve
   accepted unrelated families and identify remaining variants.

The approved dwarf uses 2,572 assembled triangles, the deer 1,308 and the three
furniture pieces 5,214 total. These are reference counts from the pilot reports,
not universal budgets or measured full-game speedups. Spend geometry where it
changes the visible form; avoid adding meshes or surfaces for detail that does
not survive normal play distance.

## Production-scale comparison and future batches

Roadmap step 3 is measured in
[153 — Settlement art comparison](../00_dev_roadmap/153_settlement_art_comparison.md).
The approved art has comparable rendering cost in the 24-dwarf workload on the
tested machine. The shader-instance capacity correction is integrated; existing
CPU-side world-processing spikes remain. Full dwarf, wildlife and furniture
migration is complete in [154](../00_dev_roadmap/154_complete_family_conversion.md),
including another full-world run and restoration of a pre-conversion save.

For subsequent performance comparisons, run a representative settlement with active
dwarves and wildlife, dense trees, placed furniture and lights. Compare existing
and pilot model substitutions in the same saved/seeded scenario, with accepted
terrain and vegetation fixed. Cover ordinary camera zooms, day/night lighting,
slicing and repeated terrain edits. Record hardware, resolution, renderer,
population/object counts and matching scene conditions.

Measure frame-time distributions, update spikes, memory and draw/geometry counts;
separate simulation and terrain-update costs from art costs. Establish target
hardware and budgets before declaring a performance target met. The combined
comparison and earlier family measurements are evidence for those workloads,
not guarantees for every population or future asset. Apply this same acceptance
workflow to remaining cave flora, growing crops and future effect work.
Turf caps and new path/floor gameplay remain separate decisions.
