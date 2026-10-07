# 62 — Session handoff: 2026-10-06

The player accepted the latest room-darkness result and ended the session.
This is the current starting point, superseding the navigation and next steps in
[58 — Previous handoff](58_session_handoff_2026_10_05.md). No next feature has been
selected. This documentation update does not begin another implementation pass.

## Current player experience

The bottom toolbar is **Orders · Zones · Rooms · Place · Colony · Inventory · Menu**.
Hearth & iron remains the approved visual direction: charcoal panels, copper
accents, warm text, serif headings and actual game models for thumbnails.
Stonehearth supplies interaction inspiration, not a one-to-one layout or asset copy.

| Area | Current behavior | Detailed reference |
|---|---|---|
| Storage | Ground zones and containers share Filters / Contents. Players can accept categories or exact goods, including exceptions: Stone in one zone, only Oak Log in another. Rule edits apply immediately; rejected contents remain owned and visible until compatible storage can receive them. | [59 — Storage filters](59_storage_filters.md) |
| Hauling | New loads compare eligible idle workers against accepted pickup goods. A newly idle cutter can collect its own lumber. Successful delivery ends the lease so the next load also goes through matching. Existing reservations and higher-priority work remain authoritative. | [60 — Hauling selection](60_hauling_worker_selection.md) |
| Colony → Dwarves | One window combines the compact roster and selected dwarf's Overview / Details. Live activity, cargo, rest, search, filters, Locate and Follow remain available. Labor controls were deliberately deferred. | [61 — Colony overview](61_colony_overview.md) |
| Place | An empty visible catalog has no selected-item card or item actions. It no longer shows Personal Dining Table when nothing is available. Explicitly browsing all designs still permits inspecting unavailable furniture. | [54 — Place](54_place_catalog.md) |
| Orders / Zones | Orders contains mining, chopping and cancellation. Zones contains Stockpile. The unimplemented Farm plot tile is omitted. The active-tool banner sits above the shelf or dock and adapts around inspectors. | [53 — Navigation](53_hearth_iron_navigation.md), [55 — Orders](55_orders_shelf.md) |
| Mining camera | Plain wheel input zooms while Mine blocks is selected. Shift + wheel changes width; Alt + wheel changes depth. Scrolling over UI stays isolated from the world. | [21 — Camera](../20_player_interface/21_camera.md) |
| Rooms | A dedicated toolbar button toggles inspection. Second click / Escape exits; switching groups ends room inspection. The former Colony command is removed. | [53 — Navigation](53_hearth_iron_navigation.md) |
| Slice / Room panels | Both use the shared movable window design. Slice has a large level readout, paired cell/block steps and Show full world. Room Overview shows temperature, lighting, volume and doors; Details contains technical readouts. Selection uses an outline with a very faint floor tint. | [23 — UI](../20_player_interface/23_user_interface.md) |
| Underground lighting | Actual roof cover and door boundaries stop daylight, independently of the camera slice. Torches and braziers provide local light. Fog no longer washes sealed rooms bright, and the minimum glow is reduced. | [24 — Rendering](../20_player_interface/24_world_rendering.md) |

Inventory remains the colony supplies view. Place installs finished furniture;
it does not provide crafting or structural building. Labor and Trade remain
previews. Developer controls remain under **Menu → Development**.

## Final accepted correction: room darkness

The room was darker than outdoors but still appeared evenly lit. Two independent
contributions caused this: the constant visibility glow was too strong, and the
scene's automatic fog added sky colour after lighting had been calculated.
Earlier native room tests disabled fog and therefore missed the gameplay result.

The shared underground shader now applies fog opacity according to physical sky
access, using the active Environment's distance/height falloff and procedural sky
gradient. It updates scene parameters at 20 Hz without an extra render pass or
terrain rebuild. `SkyController` remains the only reader of sky JSON. Current
tuning in `data/sky/sky_settings.json` is:

- `entrance_reach_blocks: 7`
- `readability_floor: 0.008` (previously `0.05`)

With native scene fog enabled, the generated-room fixture measured unlit floor
luminance of **0.010**, compared with **0.150** using the previous fog/glow behavior.
Doubling camera distance left the dark floor unchanged. An interior brazier
raised it to **0.154**. A torch outside the closed door did not illuminate the
room. Exposed-terrain comparisons against automatic fog were unchanged at the
near sample and differed by about **0.003** at the far day/night samples.
These are measurements of the test scene, not universal brightness guarantees.

The correction applies to terrain and world entities using the shared material.
Portraits retain studio materials. Unshaded flame visuals and placement ghosts
retain their existing materials. The player said the result looks good.

The model remains a bounded skylight approximation, not bounced global
illumination. Analytic aerial fog does not reproduce the engine's blurred sky
radiance or volumetric fog. The current world uses depth fog and a ProceduralSky.
Lighting affects visibility only: it does not prevent work, slow dwarves, alter
needs or change scheduling. Slice visibility does not remove the physical roof.

## Verification at close

The final lighting change reran the first two checks below. The other entries
record successful checks from their respective implementation passes; this is
not a claim that the entire suite ran again after the final shader change.

| Check | Result and evidence |
|---|---|
| RoomLightingTest | Passed with real generated terrain, scene fog enabled, closed door, exterior torch, interior brazier, camera-distance/day/night comparisons, room selection/dragging and compact panel layouts. `tmp/room_lighting_review/darkness_fix/verified.log` and `.err`; report and native images in `tmp/room_lighting_review/`. |
| UndergroundLightingTest | Passed: entrance falloff, blocked passages, doors, skylights, edits during updates, stacked floors, torch illumination and mining replay. Final sampled deep floor: 0.027 unlit, 0.172 with torches. Lighting update work peaked at 2.63 ms in this run. `tmp/underground_lighting_review/darkness_fix/verified.log` and `.err`. |
| NavigationPreview | Passed seven-entry dock, Rooms toggle/exit, menu routing, input exclusivity and 960/1280/2560 layouts. `tmp/rooms_navigation_review/navigation.log`. |
| SaveManagerRoundTripTest | Passed saved/unsaved door and brazier restoration, stale-boundary cleanup, no duplicate light/heat, plus normal save and backup recovery checks. `tmp/room_lighting_review/save/save.log`. |
| OrdersShelfTest | Passed plain-wheel mining zoom, modifier resizing in either input order, UI wheel isolation, tools/Undo and native layouts. `tmp/mining_zoom_review/OrdersShelfTest.log`; later group checks in `tmp/zones_navigation_review/`. |
| Storage, hauling and colony checks | Their full test matrices are recorded in docs 59–61. Evidence directories: `tmp/storage_filter_review/`, `tmp/haul_selection_review/`, `tmp/haul_return_review/`, `tmp/colony_overview_review/`. |

All runtime tests used isolated APPDATA/LOCALAPPDATA directories, protecting player
saves and UI preferences. The final generated-world fixture reports the known
autoload-before-scene SkyController / WeatherManager startup warnings; it reports
no script or shader errors. Documentation was updated after testing without
another gameplay change.

## Persistence and ownership to preserve

- Storage saves category tags, exact inclusions and exclusions as stable strings.
  Old saves migrate their existing category rules; explicit empty rules mean
  accept nothing. Rejected goods must not disappear when rules change.
- Hauling quotes do not reserve goods. Normal pickup/delivery owns claims and
  cargo; existing trips are not stolen by a newly idle, closer dwarf. Distance
  ranking uses a Manhattan estimate and bounded reachability, not a globally
  optimal path assignment.
- Lighting data is derived, scene-owned and rebuilt from terrain edits and
  installed doors. It is not serialized. SaveManager clears old room, door,
  heat and light registrations before furniture restoration.
- The room light count comes from installed light definitions, separately from
  heat units. A light outside the room is not counted as an interior source.
- The 8×4 communal table and eight chair positions remain approved. Trait
  descriptions remain visible with their effects explicitly labeled inactive.

## Next-session starting point

1. Read this handoff and the relevant system docs from `AGENT.md`. Restart play
   mode to pick up the latest scripts, shader and tuning.
2. Choose the next feature with the player. Roster labor controls, profession
   progression, crafting, farming, full needs, bed use and autonomous dining were
   not added by today's UX and lighting work.
3. Treat lighting restrictions on dwarf work as a separate design decision; the
   accepted scope remains visibility only.
4. Keep [Issue 001](00_open_issues.md) open. The older mining-face stall that ended
   on another zone's completion has not been reproduced and resolved by today's
   two confirmed hauling fixes. Use its original diagnostic plan if it recurs.

The workspace retains uncommitted implementation, data, assets and documentation
from this and the previous session. No commit or repository reset was requested
or performed for this handoff.

Commit preparation follow-up: GitHub Desktop encountered Windows' path-length
limit while staging generated Godot shader caches inside isolated test profiles.
Root `.gitignore` now excludes `tmp/**/appdata/`, `tmp/**/localappdata/` and
`tmp/**/shader_cache/`. Keep test user-data isolated and ignored on future runs;
review captures and reports retain the repository's existing tracking policy.
The CRLF-to-LF messages were normalization warnings, not the commit failure.
