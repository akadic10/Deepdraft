# 176 — Session handoff · 2026-10-13

The player ended the session after the mining-access and mismatched dwarf-limb
fixes. The sky, environmental audio and Windows friends-playtest package are
implemented. The art pass of that day was later replaced by the Hearthblock
style ([64](../60_asset_creation/64_hearthblock_art_direction.md)), so its rows
are left out here. The latest fixes have automated/native verification; player
confirmation after restarting the updated build is still pending.

## Completed today

| Area | Delivered state and source |
|---|---|
| Base world | [145](145_base_world_terrain_art_plan.md): coherent grey rock with subtle local variation, full grass voxels, restrained surface/edge shading and stable shoreline colors. Height-based rock bands and grass edge-color treatment are retired. |
| Asset organization | [157](157_asset_folder_layout.md)–[158](158_asset_structure.md): all production 3D families grouped under `assets/models/`. |
| Rudimentary furniture | [172](172_rudimentary_log_bridge.md): bridges use bark-covered whole logs across all five spans, with updated icons. Craft categories put beds in Rooms and eating furniture in Dining. |
| Sky and save/load | [166](166_diorama_sky.md): full 360-degree diorama sky, day/night, stars, moon and weather. [161](161_save_menu_scene_teardown.md) and [167](167_sky_scene_lifetime.md): UI/sky teardown errors during save loading fixed. |
| Sound and weather | [168](168_environment_ambience.md)–[170](170_environment_sound_details.md): time/season/weather ambience and local details; room listening makes snoring and nearby fires audible. Rain and Storm are saved weather types with roof-aware rain/patter and thunder. |
| Friends playtest | [171](171_windows_playtest.md): ten main-scene debug warnings fixed at source, Windows x86-64 package prepared. [173](173_ledge_pickup_and_safe_exports.md): exports now use a unique release directory every time. |

## Decisions to retain

- Keep full grass voxels; grass-over-dirt caps and fringes are deferred by the player.
- The illustrated Hearth & iron HUD remains the accepted UI direction.
- Rain is cosmetic precipitation; it does not add simulated water. Sound
  settings are player preferences, separate from settlement saves.
- Matching limb colors still receive ordinary directional shading. The fix
  removes the reversed lighting caused by reflected meshes; do not compensate
  for it with different left/right skin or leather colors.

## Latest playtest fixes and evidence

**Ledge copper and door placement — [173](173_ledge_pickup_and_safe_exports.md).**
Reachable loose goods can be collected from an adjacent floor up to two blocks
below their support, with live obstruction checks and unchanged walking limits.
A copied player save verified collection/storage of all three copper drops.
All three door widths and all 41 packed furniture models load. The missing door
preview was caused by our export replacing the PCK of a running game, rather
than a door footprint defect. Unique release directories prevent that overwrite.

**Mining after moving a bed — [174](174_mining_furniture_access.md).**
Navigation already removed the obstruction correctly; the mining zone retained
an empty cached work-face list. Occupancy changes now invalidate nearby zones,
refresh pending work and clear stale route/backoff state. Seven fixtures pass.
A native copied-save review reproduced three failed retries, issued a real bed
Move order, mined both remaining blocks and completed the move. Distant orders
and active worker ownership remain intact.

**Mismatched hands/boots — [175](175_dwarf_limb_lighting.md).**
Right-side negative mesh transforms caused reversed lighting despite equal
tints. Shared reflected geometry and a counter-reflection preserve signed rig
frames and tool anchors while rendering with positive transforms. Native tests
pass 32 paired samples across four skin tones, daylight/torchlight and both
standard/world materials. The art fixture passes 6,828 checks across 800
appearances; proportion integration passes 205 checks. Mining, chopping,
hauling and rest fixtures pass. A copied-save Ulvrek review verifies all four
limb transforms and paired tints.

These tests used isolated APPDATA and copied saves. Existing player saves need
no migration or new colony. Restart Play or launch the new release before
reviewing the fixes. Detailed captures and machine-readable results are linked
from each milestone. No gameplay tests were rerun for this documentation-only
closeout; the results above belong to the implementation passes.

## Current Windows build

Latest tested executable, relative to the project root:

`build/windows/releases/20261013-212541-918-28808c06/Deepdraft/Deepdraft.exe`

Share `build/windows/Deepdraft-Windows-Playtest.zip` with friends. Its SHA256 at
this handoff is:

`93B8DA4F6FB792A11A36F3761227515E143D9CB8F12E4DDB63D3835DD15650E8`

The latest exported game completed native startup/world generation and exited
cleanly. The build uses Godot 4.7.2, Windows x86-64 and DirectX 12 / Forward+;
it is unsigned. Extract the complete ZIP into a new folder and keep the EXE/PCK
together. Earlier milestone hashes describe earlier packages, not this ZIP.

Rebuild with `tools/windows_playtest/Export.ps1`. Each run creates a new
`build/windows/releases/<build-id>/Deepdraft/` directory and refreshes the share
ZIP. Never overwrite the executable or PCK of a running game. See [171](171_windows_playtest.md)
for packaging instructions and [173](173_ledge_pickup_and_safe_exports.md) for
the failure diagnosis. Builds, temporary test profiles and logs are local ignored
outputs; the milestone evidence is under `docs/00_dev_roadmap/concepts/`.

**Closeout follow-up:** GitHub Desktop exposed an untracked 104 MiB executable
in `tmp/windows_playtest_20261013/unpacked/`. The old ignore rules excluded only
selected logs/profiles, despite the intended local-output policy. The root
`.gitignore` now excludes all new `tmp/` content, including extracted builds.
Previously tracked review files remain tracked; no local files or history were
removed. Keep durable new evidence in the concepts directory above.

## Resume next session

1. Start with this handoff, standard 63 and the latest three fix reports. Use
   the current build above and the existing settlement for player review of
   bed-move mining recovery and Ulvrek's hands/boots.
2. Continue the friends playtest as feedback arrives. Other GPUs and long
   sessions remain unverified; a clean startup is not broad compatibility or
   endurance certification.
3. Choose the next art/gameplay batch with the player. Cave flora, growing crop
   art and remaining unreviewed effects are future work. Grass caps/fringes
   remain deferred. No next feature was authorized at this closeout.

Existing CPU world-processing stalls remain a separate concern. The measurements
in 145/153 establish comparable art cost on this machine, not a solved 60 FPS
target. The historical issues 001/002 in [00 — Open issues](00_open_issues.md)
remain closed by the player's decision unless re-reported; these newer fixes
do not establish their original causes.
