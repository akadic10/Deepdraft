# 68 — Caves and discovery

Implemented 2026-10-07, following [66 — Seeded world layout](66_seeded_world_layout.md)
and [67 — World generation diagnostics](67_world_generation_diagnostics.md).
The user approved an initial useful-cave pass, requested a developer inspection
tool, and asked that the other cave suggestions be retained for later.

## What discovering a cave gives the player now

- **Usable underground space:** two or three connected chambers with rough
  outlines and enough clearance to walk through. The player saves excavation
  work, but still needs an access tunnel, light and any desired room fittings.
- **Mining leads:** existing ore and gem veins become visible where they meet
  the cave walls or floor. Caves do not add a treasure deposit or guarantee a
  particular resource. Carving also removes blocks that would otherwise have
  been rock or ore, so a full resource-balance review is still needed.
- **Cave soil:** existing deposits can be exposed, and some chambers receive an
  additional rough floor patch. This creates locations for later agriculture;
  it does not implement farming, crop growth, saturation or irrigation.

Every system is initially dry, enclosed and concealed. Mining a block next to
its air discovers the **whole connected system** and shows a discovery toast.
The normal slice and mining preview cannot prospect through untouched rock.
After discovery, the cave is dark except where actual entrance light or placed
lights reach it. This version reveals a connected cave immediately; gradual
exploration by dwarves remains a later design choice.

## Easy playtest

1. Stop and restart play mode to generate a world with the cave pass.
2. Open **Menu → Development → DEV: Cave explorer**.
3. Choose a cave and press **Focus + slice**. The gold outline marks the selected
   cave through the concealed terrain; cyan outlines mark other caves.
4. Enable **Preview interior with DEV lighting** to inspect the actual floor,
   rough walls, passages, soil and exposed veins. **Previous/Next** focuses each
   cave in turn. The panel reports coordinates, floor Y, floor area, air volume,
   exposed resource blocks, soil blocks and discovery state.
5. Close the window to restore the prior camera, slice and normal lighting.
   Inspection does not excavate blocks or mark caves discovered. Existing mining
   plans and genuine discoveries survive opening and closing the preview.

For a discovery check, use an outline to locate a cave, turn off interior preview,
and designate a tunnel into its wall at the indicated floor level. The existing
DEV instant-mine action can execute the designation without waiting for workers.
A wall breach should show the toast and leave the cave revealed after closing the
explorer. Bring a torch to inspect it under normal lighting. Saving and loading
should preserve that discovery through the saved mining edits.

Native examples: [seed 1234 preview](../../tmp/world_layout_review/caves_1234_preview.png)
and [seed 65535 preview](../../tmp/world_layout_review/caves_65535_preview.png).
The matching `highlight` captures show concealed terrain with outlines; the
`discovered` captures show normal underground darkness after a real mining edit.

## Generation contract

`WorldGenerator` loads `data/world_gen/caves_v1.json` on the main thread. The
background generation pass calls `scripts/components/CaveLayout.gd` after the
final rough-cliff and shoreline maps are ready, before publishing `_maps_ready`.
Geometry uses independent seeded RNG and roughness noise. The resulting catalog,
air spans and soil mask are immutable while the world is active.

| Setting | Initial value / behavior |
|---|---|
| Systems | Target 8; up to 240 placement attempts |
| Placement | Beneath elevated terrain; no surface entrances |
| Floor height | Y16–80, further limited by the local roof envelope |
| Chambers | 2–3 generated room centers, connected by passages |
| Chamber radius | 6–12 blocks, with rough voxel boundaries |
| Floor | One shared level per system |
| Headroom | 4–8 air blocks; rounded chamber ceilings, 4-high passages |
| Passage radius | 2 blocks |
| Rock shell | At least 6 blocks around the cave's safe envelope |
| Water separation | No lake/tarn columns in its bounding box expanded by 8 |
| Other systems | Bounds separated by an 8-block margin |
| Additional soil | 45% chance of one roughly radius-5 floor patch per system |

Placement is bounded: unsafe candidates are rejected, never forced through the
surface or water to meet the count. Eight systems appeared in every tested seed;
the target is not an exhaustive all-seed guarantee. Nearby room centers can merge
into a larger chamber. Existing soil noise can expose soil even when no extra
patch is selected. Gem and metal replacement takes precedence over added soil.

The pass does not change surface height, waterlines, rough cliff/shore detail,
the Y115 summit requirement, or player-chosen settlement placement. Foundation
and bedrock remain intact. Each cave's footprint is reduced to its connected
component, so rough edges cannot leave disconnected air pockets. Current caves
have no vertical shafts, hanging isolated floors, underground water or creatures.

## Discovery, rendering and persistence

- Real generated block queries return the cave air before authored strata.
  Concealed strata queries omit cave air, resource veins and added cave soil.
- `InteriorTracker.on_blocks_mined()` checks the six neighboring cells, records
  newly discovered systems once and publishes all their air to renderer/lighting.
- Render cuts have separate owners for mining plans, executed mining, discovered
  caves and temporary developer preview. Removing one owner preserves the others.
  Exposed cave faces show the real remaining block identity.
- The mining picker treats hidden natural air as concealed strata. Discovery
  removes now-empty mining designations after the current mining commit finishes.
- Newly discovered air is initialized to underground darkness throughout the
  cave. The existing bounded lighting solver handles the breach and installed
  lights, including cave air beyond the breach's immediate update radius.
- Save files store actual mined blocks only. Regenerating the seed and replaying
  those edits reconstructs discovery, interior membership and render/light state.
  Natural air is not serialized as an enormous list of mined blocks. Developer
  highlight/preview settings and its temporary lighting are not persisted.

The explorer is a plain scene script on a CanvasLayer, registered with the
existing window manager. It is the explicitly requested developer exception to
normal concealment. It does not add a global class or autoload; restarting play
mode is sufficient. No save migration was added, consistent with the user's
confirmation that this is early development with no existing saves to preserve.

Repeated generation tests also exposed shared packed-map buffers being resized
to the same size before threaded row writes. New generations now allocate fresh
height/domain/water buffers before those writes, avoiding concurrent copy-on-write
detach when a previous snapshot still holds the old arrays.

## Verification

- `CaveGenerationTest.gd`: eight seeds, 64 systems. Checks deterministic rebuilds,
  unchanged surface/water maps, connected and walkable floors, minimum headroom,
  protected foundation/roof, water buffers, real air versus concealed strata,
  preview cleanup with overlapping plans, mining discovery, navigation from a
  breach and reconstruction from mining-only state.
- Across those seeds: floor Y16–68, 260–1,112 floor blocks per system. Some soil
  appeared in 4–8 systems per seed. These are observations, not tuning guarantees.
- `CaveLivePreview.gd`: actual scene and native renderer, seeds 1234 and 65535.
  Menu route, focus/slice, outline/preview screenshots, nonmutating inspection,
  view restoration, real mining discovery, removal of empty plans and dark cave
  lighting all pass.
- `SaveManagerRoundTripTest.gd`: normal and backup save/load pass with a discovered
  cave in the full colony fixture; terrain/cave fingerprints match and renderer
  discovery is rebuilt without additional mined-air deltas.
- `UndergroundLightingTest.gd`: entrance falloff, occlusion, doors, reopening,
  placed-light behavior and native light measurements pass.
- `WorldGenerationTest.gd`: eight-seed regression passes for existing seeded
  terrain, Y115 summit, water, rough edges, flora, navigation, mining and strata,
  with caves included in generation.

Evidence: `tmp/world_layout_review/caves_report.json`, `caves_test.log`,
`caves_render.log`, `caves_render65535.log`, `caves_save.log`, `caves_lighting.log`
and `caves_world_regression.log`. Native lighting measurements/captures are copied
to `caves_lighting_checks.json`, `caves_lighting_night.png` and
`caves_lighting_torches.png` in the same folder. Test profiles are isolated from
player saves. Historical lighting artifacts and doc 67 resource reports are
preserved. Final logs contain no script errors or failed checks.

Example PowerShell command from the project root:

```powershell
$env:APPDATA = 'P:\Deepdraft\tmp\world_layout_review\appdata_cave_check'
$env:LOCALAPPDATA = 'P:\Deepdraft\tmp\world_layout_review\localappdata_cave_check'
$caveCheck = Start-Process -FilePath 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' -WindowStyle Hidden -Wait -PassThru -ArgumentList '--headless --path P:\Deepdraft --log-file P:\Deepdraft\tmp\world_layout_review\caves_test.log --script res://scripts/tests/CaveGenerationTest.gd'
if ($caveCheck.ExitCode -ne 0) { throw 'Cave checks failed; inspect the log.' }
Select-String -Path tmp/world_layout_review/caves_test.log -Pattern 'SCRIPT ERROR|ERROR:|\bFAIL\b'
# Native explorer capture: omit --headless and use
# --script res://tools/CaveLivePreview.gd -- --seed=1234
# Do not use --quit-after for this asynchronous scene verification.
```

## Suggestions retained for later

These are recorded opportunities, not approved implementation work or current
player rewards. Ordinary tunneling should remain a viable way to build a colony;
finding a cave should offer a choice rather than determine whether a seed works.

| Opportunity | Player benefit | Work to resolve first |
|---|---|---|
| Underground pools, springs and irrigation | Local water supply and agricultural sites | Fluid containment/pressure, soil saturation, drainage and flood behavior; do not connect live lakes blindly |
| Fungi and distinctive cave plants | Food, brewing inputs and cave ecology worth discovering | Farming/harvesting loop, yields and regrowth, cave light/water requirements, visual assets and placement |
| Ruins, artifacts and signs of earlier inhabitants | Stories, unusual finds and exploration goals | Discovery content, item use, rewards and placement rules that preserve usable space |
| Cave inhabitants and hazards | Decisions about securing, avoiding or exploiting a cave | Combat/hazard systems, readable warning signs and counterplay; avoid unavoidable early punishment |
| Multiple levels, shafts and deeper networks | Routes into new depths and richer exploration | Stairs/ramps, navigation and worker reachability, ceiling/floor integrity and usable slice presentation |
| Resource distribution and cave specializations | Distinct reasons to explore different regions | Measure remaining ore after carving, exposed veins, gem precedence, access costs and ordinary mining yield |
| Progressive discovery | Exploration beyond the first wall breach | Line-of-sight or dwarf exploration state, partial discovery rendering and persistence |
| Access and colony logistics | Meaningful choice between adapting a cave and digging custom rooms | Travel/hauling distance, lighting, doors, room sealing and temperature; playtest benefits against excavation saved |

The next useful review is a visual/playable pass across several seeds: chamber
shape, size, spacing, depth and the effort needed to reach them. Tune those from
play before adding the deferred rewards and risks.

**2026-10-08 follow-up:** the user confirmed caves appear in the explorer and
chose to defer these additional manual checks, proceeding to the
[resource distribution review](69_resource_distribution_review.md). The automated
checks above remain the recorded verification; the deferred playtest is not
marked complete. No further cave-shape tuning was made in that resource pass.
