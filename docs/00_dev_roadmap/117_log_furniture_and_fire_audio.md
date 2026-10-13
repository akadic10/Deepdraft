# 117 — Log furniture and fire ambience

Implemented 2026-10-11 from the playtest request for simpler starter furniture,
three doorway widths and audible campfires/torches.

**2026-10-12 art revision:** starter log doors are now frameless. Alen reserved
fixed jambs and top beams for better doors in later tiers. The live 2-, 3- and
4-wide models contain only swinging log leaves, with uneven cut tops, simple
wooden battens, pegs and pulls. The leaves fill the opening and pivot at its
outer edges (`door_animation.hinge_inset: 0`). Footprints, recipes, material
variants, walkability and room sealing retain their existing behavior.

All three placed-form icons are regenerated. Existing installed doors use the
new art after restarting Play and loading a current save; no rebuild is required.
`LogFurnitureTest` and native `DoorLightingTest` pass, including rotations,
either-side opening, room boundaries and restoration. Native closed/open previews
and the previous framed model references are in `tmp/frameless_doors_20261012/`.

## Furniture

The existing Door is now **Log door (2 wide)**, with one swinging leaf.
**Log door (3 wide)** also has one leaf; **Double log door (4 wide)** has two.
All use rough vertical logs, wooden cross battens and pegs, and wooden pulls.
There is no separate frame. Tops vary between 30 and 31 art voxels (maximum
3.875 world blocks) beneath a four-block opening. Footprints are respectively
2×1, 3×1 and 4×1.

`FurnitureDoorAnimation` reparents named leaf meshes onto hinges when installed.
Dwarves approaching open the leaves away from their arrival side. Direction
stays stable during passage; doors close after the last dwarf clears the area.
Pause freezes the pose. Hinges are cosmetic, recreated closed on load, with no
new save fields. RoomManager recognizes the `door` category for every width and
seals all footprint columns regardless of pose. Doors remain walkable.

**Bench** is now **Log bench**: a split half-trunk on short cross-log supports,
retaining its 2×1 footprint and one-block height. Its existing scenery/occupancy
behavior remains; multi-dwarf bench seating is separate work. **Wooden torch**
becomes **Log torch**, a charred branch with coarse fibre binding on one low
wooden peg. Its wall mount, light, heat and animation still fit three-block tunnels.

Existing `door`, `bench` and `wooden_torch` keys/model paths remain. New
`log_door_3` and `log_door_4` definitions have matching packed items. All use
the full furniture crate. Place exposes doors under Rooms and the bench under
Dining. Craft → Rudimentary adds Rooms for doors and the bench under Camp
furnishings. Each costs one selected log at a crude workbench: 12/18/24 seconds
for the doors and 10 seconds for the bench. Torch crafting keeps its one-log,
four-torch batch in six seconds.

`tools/generate_log_furniture.py` owns all five models: native 0.125 vertex
scaling, unit roots, exposed cube faces and linear vertex colors. The canonical
furniture builder uses the new bench and multipart doors; the Worker generator
delegates its torch. Five placed-form thumbnails are regenerated.

## Fire ambience

Installed campfires and both log/iron wall torches supply nearby fire sounds.
Campfires have a fuller crackle; torches are softer. Packed goods and placement
ghosts stay silent. As with the existing flames, no fuel upkeep is added.

`tools/generate_fire_audio.py` creates original twelve-second mono WAV loops
from periodic colored noise and wrapped, damped crackles. Private seeded NumPy
generation runs offline, independent of simulation randomness. Runtime looping
uses duplicated imported streams; importer settings are never hand-edited.

`FurnitureFireSound`, owned by the furniture controller, has at most four
spatial players on the existing **Work** bus. Every quarter-second it selects
the strongest visible sources using camera focus, zoom and vertical separation.
Voices share a bounded power budget and retain playback phase while selected.
Fades smooth camera/source changes. Pause, zero speed, loading, loss of camera,
hidden/sliced sources and uninstall/free silence playback. Scene teardown frees
all players. Speed does not change pitch; Work volume/mute controls apply.

`data/audio/work_feedback.json` owns tuning: campfire range 20 blocks / −10 dB,
torch range 12 / −15 dB, before Work volume and distance/zoom attenuation.

## Verification

- `LogFurnitureTest`: actual Worker crafting, crate conservation, hauling and
  installation; leaf counts/motion, either-side opening, pause, walking through,
  all rotations, room sealing, removal and restoration of each doorway width.
- `FireAudioTest`: authored PCM headroom/seams, source gates, bounded voices,
  unchanged pitch, freed-source safety and cleanup. Native Master-bus recordings
  check actual playback, balance, volume/mute and distant/hidden/removed/paused
  silence. Campfire RMS 0.00752, torch 0.00426, peak below 0.071; silent captures zero.
- `WorkerCraftingTest`, native `CraftingBrowserTest` at 1920×1080, 1280×720 and
  960×540, and full `SaveManagerRoundTripTest` pass. The save test deliberately
  corrupts isolated saves to verify backup recovery.
- Native `UndergroundLightingTest` passes: door boundaries still stop daylight,
  replacement/restore retain the seal, and uninstall restores entrance light.
- Editor import succeeds; all 122 production scripts have zero language server
  errors or warnings. Native art reviewed closed/open beside an actual dwarf.

Captures/logs: `tmp/log_furniture_20261011/`. Repeatable art review:
`tools/LogFurniturePreview.gd`. Restart Play and load a current save to use the
new art and sounds; existing furniture does not need rebuilding.
