# 144 — World art direction and session handoff

**Latest resume point:** [176 — October 13 handoff](176_session_handoff_2026_10_13.md)
records the full day's completed work, latest playtest fixes and current build.

**Post-conversion proportions are approved and live:** The native
[162 — Visual scale review](162_visual_scale_review.md),
[Stonehearth comparison](163_stonehearth_scale_comparison.md) and
[trials](164_dwarf_wolf_proportion_trials.md) led to the player's choice of
**Balanced dwarves and Large wolf**, integrated in
[165](165_approved_actor_proportions.md). Dwarf and pine heights remain fixed;
dwarf width and wolf proportions changed. The earlier study captures remain
comparison evidence. This is separate from the workload/performance study in 153.

**Current status (2026-10-13):** Terrain and current surface clutter are complete
through [149](149_ground_stones.md). The player approved the
[dwarf](150_dwarf_art_pilot.md), [deer](151_animal_art_pilot.md) and
[starter furniture](152_furniture_art_pilot.md) pilots. Their combined
[shared art standard](../60_asset_creation/63_shared_art_standard.md) is finalized.
The production-scale comparison is recorded in
[153 — Settlement art comparison](153_settlement_art_comparison.md).
**Sequence steps 1–4 are complete for the core families.**
The art has comparable rendering cost on the tested machine. Existing CPU-side
world-processing spikes remain a separate performance concern, not a solved target.
[154 — Complete family conversion](154_complete_family_conversion.md) integrates
all dwarf appearances, all four live animal species and the full furniture
catalogue, including packed/access forms. Current-format saves work with the new
art. [155 — Resource drops and work tools](155_resource_drops_and_work_tools.md)
also completes all remaining loose goods and both animated work tools.
[160 — Faceted fire](160_faceted_fire.md) completes all six fire sources and
their 42 animated frames. Cave flora, growing crops and other unconverted
effects remain future batches; full grass voxels remain.
[156 — Legacy art cleanup](156_legacy_art_cleanup.md) removes obsolete and
duplicate exports and updates authoring and review tools.
[157 — Folder layout](157_asset_folder_layout.md) then removes the redundant
`faceted` folders; production models live directly under their asset families
and categories. [158 — Asset structure](158_asset_structure.md) unifies all
3D art under `assets/models/`, with peer animal, character, flora, rock,
construction, furniture and item families. All approved models and current
saves retain their behavior.

Later follow-ups complete the [rough workbench](159_crude_workbench_stump.md),
[whole-log bridges](172_rudimentary_log_bridge.md),
[360-degree sky](166_diorama_sky.md), and
[environmental audio with rain/storm weather](170_environment_sound_details.md).
[175](175_dwarf_limb_lighting.md) corrects the reflected-limb lighting defect.
These are integrated production changes; cave/crop art and grass caps remain
outside the completed batches.

**Updated direction (2026-10-13):** The base terrain migration is implemented; start with
[145 — Base world terrain art plan](145_base_world_terrain_art_plan.md).
The player chose a coherent grey rock palette with subtle variation and full
grass voxels. Terrain now uses subtle edge shading on merged faces; real chamfers
remain a measured study alternative. This foundation precedes the character/animal/furniture
pilots; grass-over-dirt caps and fringes are deferred. The captures and performance
results below remain the historical October 12 study reference.

Recorded **2026-10-12** for resuming on **2026-10-13**. Deepdraft's proposed
direction is **voxel-inspired, stylized low-poly art built on editable voxel
terrain**. The native study now gives us a concrete starting point: retain the
individual stone treatment and improved trees from pass 2, with pass 3's dirt
and grass as the preferred ground baseline.

The player likes these study improvements and asked to preserve the wider
direction before continuing. At the October 12 handoff, converting dwarves,
animals, furniture and production terrain was proposed work. The October 13
terrain implementation is recorded in 145; 146–149 complete current surface
clutter, 150–152 record approved pilots, and 63 defines the shared standard.

## Resume here

For the current session state and player-review items, start with
[176](176_session_handoff_2026_10_13.md). The references below explain the art
baseline and preserve the study history.

1. Read [63 — Shared art standard](../60_asset_creation/63_shared_art_standard.md)
   and the approved pilot reports in 150–152. They define the current direction
   and the remaining art boundaries. The integrated inventories are in 154.
2. Read [153](153_settlement_art_comparison.md) for the matched settlement results,
   shader-capacity correction and remaining CPU/update limits. They establish
   relative art cost on this machine, not minimum hardware or a shipping FPS target.
3. Read [154](154_complete_family_conversion.md) for the completed dwarf, wildlife
   and furniture conversion, authoring sources, native review scenes and save QA.
   [155](155_resource_drops_and_work_tools.md) completes the loose resource/tool
   catalogue. [159](159_crude_workbench_stump.md) restores the intended crude
   stump; [160](160_faceted_fire.md) converts the retained voxel flames. Review
   these in normal Play before choosing cave flora, growing crops or other
   effects; grass caps remain a separate deferred decision.
4. Use [143](143_visual_quality_study.md) and `Launch Visual Study.cmd` only for
   historical study comparisons. Its turf caps and true terrain chamfers are not
   the current production baseline. **F5 loads the normal game.**

## Decisions and current status

| Subject | Current position |
|---|---|
| Individual stone blocks | Approved visual direction; production uses merged faces with subtle edge shading in 145. True chamfers remain a study alternative. |
| Trees | All four live species use the accepted clustered foliage and shaped trunks in 146–147. |
| Dirt and grass | Pass 3 remains a reference for softened ground forms. The October 13 decision keeps grass as a full voxel and defers its turf-over-dirt treatment. |
| Wider asset style | Standard 63 governs the integrated 41 dwarf parts, 21 wildlife parts and 41 furniture forms in 154. |
| Ground rules below | Plan 145 now governs the base terrain migration. Seam strength and softening remain visual tuning choices; turf fringe and functional path design are deferred. |
| Large world integration | Terrain and surface clutter have production measurements in 145–149. The combined 24-dwarf settlement comparison is in 153; art cost is comparable, but baseline CPU stalls remain. The October 12 experiment is only 32×32. |
| Menus and HUD | The player likes the illustrated main menus. Retain their Hearth & iron theme; this is world-art work. |

The original illustration remains an aspiration for composition, atmosphere and
material richness. It is not an engine screenshot or a promise that the native
game already achieves its detail or performance. The saved references below
are actual native captures.

## Shared visual language

The finalized rules are in [63](../60_asset_creation/63_shared_art_standard.md).
Use strong, chunky silhouettes, broad flat-shaded planes, a restrained palette
and selective bevels. Timber should feel substantial; stone should feel heavy;
foliage should read in clusters. Warm wood and firelight should sit comfortably
against cooler rock and muted greens. Retain the established dwarven identity
and room for underground bioluminescence.

Low-poly does not mean smoothing everything into rounded objects or adding a
bevel to every cube. Spend detail on silhouette, joints, recognisable materials
and features visible at normal RTS zoom. Keep wear and colour variation subtle
enough that mining, placement and selection remain legible.

Craftsmanship must remain visible. Starter items should still look crude;
shaped joinery, dressed masonry, metal fittings and framed doors belong to
appropriate later tiers. In particular, keep existing log doors frameless.

## Terrain surfaces and paths

The world grid remains the authority for digging, support, navigation, water,
room sealing, resources and saves. The renderer can shape the visible skin of
an exposed voxel without creating smaller simulation cells or changing its
material identity. Existing 1:8 art detail is an authoring scale, not a requirement
to subdivide the world simulation or to build floors one-eighth of a block thick.

| Surface | Recommended treatment | Gameplay boundary |
|---|---|---|
| Natural stone | Retain individually readable blocks, subtle edge shading and deterministic grey shade variation. True chamfers remain a study alternative. Differentiate rock from dressed construction through material treatment where appropriate. | Existing block identity and mining yield remain authoritative. Do not add a wall-finish system. |
| Dirt | Softer edges, earth-colour variation and occasional small stones. Aim for continuous earth with weaker joints than laid masonry. | Rendering must not turn dirt into a new resource, obstacle or stack of constructed bricks. |
| Grass | A full grass voxel using the seasonal grass palette on exposed faces, with restrained local variation. Thin turf, soil sides within a grass block and fringes are deferred. | Grass and dirt remain separate voxel materials; see plan 145. |
| Constructed stone paths | Fitted, chunky stones with shallow joints, modest variation and a visually level walking surface. | A future functional path needs a real persistent construction designation and inspectable material. Study slabs are decorative only. |
| Permanent indoor floors | Carry the same material language into repeatable plank and laid-stone patterns. | Preserve [128 — Permanent floors](128_permanent_floor_preview.md): mine a full supporting layer and replace it to restore the walking height. |

Grass colour belongs to grass voxels, including their exposed side faces; digging
or slicing rock/dirt must not add a grass coating. The historical pass 3 study
adds turf only to actual grass blocks with open air above, but that treatment is
deferred by plan 145. Retain existing seasonal palette behaviour. Grass spreading
and other new ground simulation are separate work.

Surface treatments must meet cleanly at terrain steps and chunk boundaries.
Mining, construction and restoration must update neighbouring exposed surfaces
without cracks, floating tufts or mismatched natural/constructed slice caps.
The player's earlier constructed-stone top-face mismatch is a regression to avoid.
Artificial cuts must continue to conceal undiscovered resources.

The study path is not yet a buildable path and grants no movement bonus. Path
costs, unlocks, effects and whether it becomes a distinct catalogue entry are
undecided. Do not quietly reinterpret it as a thin flooring overlay. Rugs,
pelts and fitted carpets remain a separate deferred category. Wall coverings
and a combined Mine and Replace action remain excluded.

## Dwarves and other world assets

| Asset family | Proposed art treatment | Preserve during the pilot |
|---|---|---|
| Dwarves | Chunky proportions, expressive hair and beards, clearer faces, clothing and equipment; use shaped planes where they improve the silhouette. | Recognisable character variation, appearance assembly, animation anchors, equipment/carry poses, seating and sleeping alignment, existing logical clearance. |
| Animals | Species-specific silhouettes, tapered limbs and suitable fur or feather clusters. | Species size, movement/animation, ground or water alignment and existing navigation rules. |
| Furniture and stations | Thick timber, selective softened edges, readable joints and clear material/craftsmanship tiers. | Footprints, interaction and seating points, door hinges, wall mounts, material variants, placement ghosts and packed forms. |
| Trees and plants | Build from the fir/oak prototypes, then extend the language to bushes, flowers and other flora. | Species recognition, growth/season/crop states, harvest and transplant behaviour, authored footprints and slice visibility. |
| Items and props | Simplify forms around material and purpose, with detail appropriate to their screen size. | Item identity, quantity readability, carry/storage scale and the existing economy. |

Not every asset needs replacement. Review existing pieces in the new setting
and retain those that already fit. This is a staged art migration, with gameplay
contracts kept explicit for each family.

## What the study proves and what it does not

Pass 3 contains native stone/soil/turf geometry, six prototype trees, ground and
room dressing, decorative path slabs, scripted stream/waterfall presentation
and a different lighting treatment. Existing dwarf and furniture art is still
used. The scene uses real block data and roof-light sampling, but its actors
are posed and simulation is paused. Two manually positioned room fill lights
approximate bounce; they are not a production indirect-light solution.

The recorded pass 3 run passed **42 checks**, including comparison controls,
unchanged block data across the ground toggle, slicing, mining/restoration,
roof lighting and bedrock preservation. At 1600×1000 on an RX 9070 XT, Study GPU
medians were **1.71–2.22 ms** across night/dusk/day. The whole-scene view reported
76 draws and 158,342 primitives. A synchronous fixture remesh took about
**100 ms**, which is not suitable as the production mining update strategy.
See [143](143_visual_quality_study.md) for the complete conditions and results.

These are small-scene measurements, not full-game FPS or evidence that a large
colony and forest can use the same implementation unchanged. Production work
must address exposed-face batching, cached/instanced props where suitable,
distance detail levels, bounded terrain updates, lighting cost and memory.
There is no reason to render every stored world voxel as an individual object.

## Implementation sequence

**October 13 tree pilot:** After the five terrain phases, the user authorized
pine and oak as the first production asset pilot. [146](146_tree_art_pilot.md)
records the completed models, native references, gameplay checks and matched
forest costs. The user approved it, and [147](147_complete_tree_family.md) now
completes apple/juniper and the full live tree family.
The broader asset exercise includes the approved isolated dwarf in
[150](150_dwarf_art_pilot.md) and the approved deer in
[151](151_animal_art_pilot.md). The small starter furniture set is approved
in [152](152_furniture_art_pilot.md); their shared standard is finalized in 63.

**October 13 order:** The terrain phases in
[145](145_base_world_terrain_art_plan.md) were completed first, followed by surface
clutter. Core family migration is now complete in 154; the pilot measurement and
remaining performance limits are preserved in 153.

1. **Asset pilot in the study — complete and approved.** Add one dwarf, one animal and a small coherent
   furniture set beside the preferred trees/ground. Keep the old versions for
   direct comparison. Include basic motion and a relevant interaction pose so
   an attractive static model does not conceal broken use or proportions.
2. **Set the authoring standard — complete in [63](../60_asset_creation/63_shared_art_standard.md).** Refine proportions, palette, bevel strength,
   detail density, mesh/material conventions and animation anchors from that
   pilot. Update the shared art guide when those choices are established.
3. **Test production scale and behaviour — measured in [153](153_settlement_art_comparison.md).** Exercise a representative generated
   settlement with active dwarves, wildlife, many trees and lights, normal zoom
   ranges, slicing and repeated terrain edits. Measure frame time, update spikes
   and memory; compare against the same scene using current art. Agree on target
   hardware and budgets before treating the small study as a performance target.
4. **Migrate by asset family — core families complete in [154](154_complete_family_conversion.md).**
   All dwarf appearances, four wildlife species and the furniture catalogue use
   the accepted treatment. Contacts, wood variants, saves and UI previews pass.
   All remaining item/tool forms follow in [155](155_resource_drops_and_work_tools.md).
   Apply the same checks to future cave flora, growing crops and effect batches.

The furniture pilot covers the starter log stool, bed and two-wide door. The
settlement comparison retains accepted terrain and clutter and separates art
costs from existing simulation and terrain-edit spikes. No absolute performance
target or minimum hardware requirement has been established. Profile the CPU
spikes separately; do not claim the visual migration fixes them.

## Native reference images

Copies are preserved beside this document so the visual baseline does not depend
on the temporary capture folder. These show the October 12 study, including
existing dwarf/furniture models; they are not examples of completed replacements.

### Whole scene

![Native pass 3 study with individual terrain blocks, clustered trees and existing furniture](concepts/144_art_direction/pass_3_scene.png)

### Dirt and grass

![Native pass 3 ground close-up showing turf caps and exposed soil](concepts/144_art_direction/pass_3_ground.png)

### Tree forms

![Native study tree close-up showing the retained pass 2 tree designs](concepts/144_art_direction/study_trees.png)

## Files and verification to resume with

| Location | Purpose |
|---|---|
| [Study scene](../../scenes/studies/visual_study.tscn) | Isolated native experiment |
| [VisualStudy.gd](../../tools/visual_study/VisualStudy.gd) | Comparison, cameras, lights and study setup |
| [StudyTerrain.gd](../../tools/visual_study/StudyTerrain.gd) | Fixture block data and exposed terrain rebuilding |
| [StudyMesh.gd](../../tools/visual_study/StudyMesh.gd) | Chamfers, turf/soil faces and mesh construction |
| [StudyEnvironmentArt.gd](../../tools/visual_study/StudyEnvironmentArt.gd) | Prototype trees, slabs and other dressing |
| [Terrain detail shader](../../tools/visual_study/terrain_detail.gdshaderinc) | Study surface shading |
| [CaptureStudy.gd](../../tools/visual_study/CaptureStudy.gd) | Native captures and checks |
| [Shared art standard](../60_asset_creation/63_shared_art_standard.md) | Current visual/export rules and acceptance workflow |
| [Asset guide](../60_asset_creation/61_voxel_art_guide.md) | Existing specifications and historical voxel authoring conventions |
| [Dwarf appearance guide](../40_economy_colony/41b_dwarf_appearance_glb.md) | Existing character asset contracts |

Run from `P:\Deepdraft` to regenerate the study evidence:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/visual_study/Launch.ps1 -Capture
```

The latest full captures and [report](../../tmp/visual_study_20261012/art_pass_3/report.json)
remain in `tmp/visual_study_20261012/art_pass_3/`; previous passes are retained.
The launcher uses a separate study profile and does not load settlement saves.
This documentation handoff adds no runtime changes. The working tree already
contains substantial earlier work; preserve it and avoid broad resets or
regeneration of unrelated assets when resuming.
