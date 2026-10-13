# 143 — Small-world visual quality study

For the subsequent material/asset direction and next-session starting point,
see [144 — World art direction handoff](144_world_art_direction_handoff.md).
It preserves the preferred native references and distinguishes future migration
from the implemented experiment documented here.

Implemented 2026-10-12 after approval to test the proposed world art direction
in a smaller world. This is an isolated native Godot experiment, not a change
to the settlement renderer or an AI-painted representation of a running game.
**Art pass 2** added native environment geometry and dressing after the player
found the first lighting pass insufficient. The player likes the individualized
stone and considers the pass 2 trees a significant visual upgrade. **Art pass 3**
now extends that treatment to dirt and grass, retaining those trees and stone.

## Play the study

Double-click **`Launch Visual Study.cmd`** in the project root. It opens a visible
window titled **Deepdraft - Visual study (32 x 32)**, independently of Godot's
current editor scene. The launcher waits for the study's ready marker and
reports startup errors. Interactive logs are `interactive.out` / `interactive.err`
in the capture folder; they do not overwrite the capture logs.

**F5 runs the normal game.** F6 runs the scene currently selected in Godot's
scene tabs: open `scenes/studies/visual_study.tscn` itself before using F6. Opening
a script or viewing the file in Codex does not select that scene in Godot.
The double-click launcher avoids that dependency.

Alternatively, from the project directory:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/visual_study/Launch.ps1
```

The launcher uses a separate user-data profile. The scene also redirects
SaveManager to a study-only path, never loads a settlement, and pauses simulation.
No new autoload, global class, main-scene setting or project reload is required.

| Control | Action |
|---|---|
| Compare button / C | Switch current and study treatments |
| Ground button / G | Compare pass 2 and pass 3 ground with the same trees, stone and lighting; enabled in Study |
| Day / Dusk / Night, or 1 / 2 / 3 | Change lighting; dusk uses the actual seasonal sunset |
| −4 / −1 / +1 / +4 | Move the visible terrain plane |
| [ / ] | Lower / raise one level |
| Full | Show all fixture terrain |
| Mine test opening / Restore test wall | Edit actual block data, then rebuild and update daylight |
| Whole scene / Rooms / Stream / Trees | Camera presets |
| Ground close-up | Inspect turf tops, exposed soil and block edges |
| Right drag / mouse wheel | Orbit / zoom |
| Esc | Close study |

These are compact lab controls, independent of the game's illustrated HUD.

## What is being compared

The 32×32-block footprint contains a cliff, an uneven stepped approach, a stream
and fall, two connected furnished rooms, plank/stone flooring, six torches,
trees/shrubs and three posed dwarves. Eight populated 16³ chunks retain real
bedrock, plus 28 empty neighbor chunks establish the bounded edges. The display
crops the lower plinth at Y14; the actual bedrock remains in WorldData. The global
1024×128×1024 coordinate limits are unchanged; the large world is not generated.

Both modes use the same voxel data, camera, time, existing furniture/dwarves and
physical roof-light field. **Current assets** uses the shipped trees, terrain/
actor shader and ordinary sky/torch lighting. **Environment art · Pass 3** adds
the prototypes below. The Ground toggle retains pass 2 as a focused comparison.
Geometry and art now intentionally differ between modes;
this is no longer the first pass's shader-only comparison. Neither mode is a
pixel-identical copy of the production overview renderer and its distant fog.

Study treatment experiments with:

- Actual stone chamfers and recessed joints, with deterministic cell colour
  variation. Only exposed faces are expanded. Artificial caps use this fixture's
  uniform stone family, never the identity of concealed resources.
- Individual dirt and grass blocks with softer recessed edges, deterministic
  colour variation and subtle distance-filtered grain. Grass has a green top
  and an uneven turf fringe over brown soil on exposed sides. Turf is drawn
  only on actual grass blocks with open air above. The bevel perimeter closes
  at the logical cell boundary to prevent background gaps at terrain steps.
  All geometry remains inside its original block; support heights and block
  identities are unchanged. The new faces join the existing terrain batch.
- Two native prototype tree designs: layered fir branches and a spreading oak
  canopy, with smaller foliage clusters, visible trunks and roots. Six instances
  replace the comparison trees. These are flat-shaded procedural art meshes,
  not new production flora definitions or imported GLBs.
- Ground tufts, stones, moss at the waterline, path slabs, timber shelving and
  supply crates. Dressing is batched by its support height for slice visibility.
  It is display-only: it adds no navigation, resource or furniture behavior.
- Muted ground and stone colours, ACES tone mapping, SSAO, modest glow and 4×
  MSAA. Authored GLB palettes remain unchanged. The current comparison retains
  the project's disabled MSAA setting, so timings compare complete treatments.
- Terrain casting sunlight shadows in this bounded scene. The main renderer's
  terrain shadow exclusion remains unchanged.
- Two small, unshadowed, manually positioned room fill lights approximate warm
  bounce. This is authored lighting for the fixture, not simulated indirect light.
- A contour-following stream with a blue-green surface, animated flow lines,
  vertical falling water and foam. Strips share three meshes grouped by slice
  level rather than one draw per strip. Both modes share the water geometry;
  Current uses the shipped surface shader. Flow is scripted, not live water CA.

The comparison shader is assembled in memory from the shipped underground
shader and `tools/visual_study/terrain_detail.gdshaderinc`. It shares the real
UndergroundLighting pages, fog updates and dwarf light samples. Study materials
are registered in that scene-owned material cache; no production shader is edited.

`StudyTerrain.gd` uses ChunkMesher output and ConstructionFloorArt. Real block
identities drive material tags. `StudyMesh.gd` expands exposed stone faces;
`StudyEnvironmentArt.gd` generates the isolated tree/dressing prototypes. Their
vertex palettes are linear. Recessed terrain samples the adjacent air cell so
its bevels cannot inherit the solid-cell daylight fallback and glow inside rooms.
This does not introduce wall finishes, recipes, new structural blocks or a
gameplay Replace action. The Restore button only restores the lab's nine cells.

## Native validation and captures

Regenerate on the actual GPU:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/visual_study/Launch.ps1 -Capture
```

Current images and report: `tmp/visual_study_20261012/art_pass_3/`, including
`current_day.png`, `study_day.png`, paired dusk/night/room views, close-up tree/
stream views, paired `pass_2_ground.png` / `pass_3_ground.png` and whole-scene
comparisons, slice captures, a mined view and `report.json`. Stdout/stderr stay
in the parent folder as `run.out` / `run.err`. Capture mode fixes water animation time.
Each timing discards 30 warm-up frames and samples 90 rendered frames.

The final native run passed **42 checks**: actual Compare click and keyboard
switching, original/prototype visibility, time keys, slice keys, camera wheel
input, the G key and Ground button, preserved block data across ground comparison,
exactly one sun and one moon, fixed clear weather, low daylight under the roof,
unchanged physical roof lighting at three slice heights, all nine mined cells,
exact restoration and preserved bedrock. The opening raises its inside daylight
sample from 0 to 0.4444; restoration returns it to 0. The separate roofed-room
sample remains 0.00694 through slicing. No script or shader errors were logged.
Two startup warnings are expected from autoloads running before the fixture:
SkyController is rebound after deferred scene startup and WeatherManager is
reseeded and forced to clear before the comparison; autonomous processing is
paused. Direct scene launches also remove the redundant moon created by the
autoload before rebinding. This fixes the purple cast seen in the first direct
launch. `VISUAL_STUDY_LIGHTS` records the actual sun/moon state for both entry paths.

Godot 4.7.2, Forward+ / D3D12, AMD Radeon RX 9070 XT, 1600×1000:

| View | Current GPU median | Study GPU median | Study p95 |
|---|---:|---:|---:|
| Day | 0.81 ms | 2.22 ms | 2.32 ms |
| Dusk | 0.81 ms | 2.01 ms | 2.27 ms |
| Night | 0.73 ms | 1.71 ms | 1.96 ms |

Current reports 70 visible draws / 49,298 primitives; Study reports 76 draws /
158,342 primitives for the whole-scene view. Folding the remaining soil/grass
faces into the detailed terrain batch removes three small plain-geometry draws.
Prototype trees and dressing account
for 76,796 authored triangles before visibility. These are viewport rendering
measurements, not whole-game FPS.
Background GPU activity and clock changes affect such short samples. A full
fixture remesh takes 61–62 ms for Current and 99–100 ms for Study synchronously:
acceptable for this manual lab toggle, not an implementation to transfer into
production mining.

## Assessment and next gate

The test makes detailed native geometry, a more restrained palette and richer
local lighting reviewable in the actual engine. It does **not** establish performance
for a 1024×1024×128 settlement. The production renderer uses different batching,
and this fixture has no active worker AI, pathfinding, river simulation or large
visible forest. This pass is closer in silhouette and colour separation, but
does not reproduce the illustration's architectural detail, material richness
or soft indirect lighting. Existing furniture and dwarves are unchanged. The
prototype trees also need production LODs and batching before use across a forest.

Review the native comparison first. Keep further art decisions in this scene
until the silhouettes, palette and stone treatment are accepted. Then measure the
chosen treatment in a representative generated settlement using production
tile batching, zoom ranges, slice cuts, repeated mining edits and many trees/
lights before considering wider integration. No production visual defaults
have been changed by milestone 143.

## Earlier passes retained for reference

Pass 2's images and 39-check report remain in `art_pass_2/`. Its Study GPU medians
were 1.91 / 1.88 / 1.62 ms for day / dusk / night, with 79 visible draws / 135,090
primitives and a ~76 ms synchronous fixture remesh. The pass 3 Ground toggle
uses that pass's terrain treatment with the same trees, dressing and lighting.

The earlier shader/lighting study and its 35-check report remain in the parent
capture folder. It used the same existing assets in both treatments: 71 visible
draws / 49,158 primitives, with Study GPU medians of 1.19 / 1.19 / 1.24 ms for
day / dusk / night. It demonstrated shader detail and contact shading but did
not address the asset-quality gap. Current capture runs preserve those files.
