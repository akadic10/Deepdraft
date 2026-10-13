# 129 — Player-selected wall-light heights

Implemented 2026-10-12 for the log torch and iron wall torch.

## Player behavior

Choose a light in Place and point at the desired wall block. The preview takes
its height and facing from that face. Alt + mouse wheel shifts the mount one
block at a time, including when using a slice. Aiming at the adjoining floor
starts at the design's usual height and leaves R available for facing.
The hint and Object explorer show the mount's world level.

Both designs can be installed or removed with the bracket on blocks 1–5 above
a reachable standing floor. A higher mount needs a reachable raised work floor;
this feature does not create ladders automatically or allow working from rungs.
Normal three-air-block dwarf clearance still applies. The worker must have an
unobstructed reach to the bracket. The entire light, including its flame, must fit
in air and below the visible slice. Wall support and furniture overlap checks
still apply. There is no blanket four-block room-height rule for the iron torch:
a lower mount can fit a lower ceiling.

Excavating below a mounted light leaves its position, light and heat unchanged.
An unbuilt plan also keeps its height if access disappears; Object explorer says
**Waiting for reachable work position**. Restoring access allows the same plan
to continue. Removing actual bracket support still cancels a plan or drops one
packed item from an installed light. Uninstall uses the same access rules.

## Ownership and persistence

`WallFurnitureMount.gd` owns coordinate conversion, bracket support, bounds and
candidate work floors. Reach is authored as `furniture.wall_reach_up_blocks`
in TaskManager's `data/tasks/task_config.json`. Fetch planning tries candidate
delivery floors; removal also searches all valid floors, retaining the selected
route goal. DwarfAgent checks actual reach again before either final commit.
Losing access releases work and preserves the carried item.

Furniture's saved `origin` remains a stable reference cell plus yaw. Each
definition's fixed `wall_mount.origin_offset_y` maps that reference to the model
base (2.5 for log, 3.5 for iron). It is not a required floor. This retains existing
saved world positions without adding a save field or migration. Room membership
and heat sample the actual mounted air cell, independently of the work floor or
reference height. Packed refunds originate at the mount and settle physically.

## Stonehearth reference

Reviewed the local source, without modifying it:

- `P:/stonehearth/services/client/build_editor/item_placer.lua`: the selected
  terrain brick determines placement; the surface normal determines orientation.
- `P:/stonehearth/components/ghost_form/ghost_form_component.lua` and
  `components/entity_forms/entity_forms_component.lua`: placement/put-down can
  request access ladders for wall items.
- Stone torch and clay wall lamp definitions both allow wall placement.

Deepdraft adopts direct wall-cell selection and shared light placement. Automatic
access construction remains separate future work.

## Verification and handoff

`WallMountHeightTest` covers both designs on four faces at all five reachable
heights, real click/wheel input, slice/ceiling/overlap rejection, raised access,
blocked reach, pending and installed restoration, lost/restored access, physical
worker delivery/removal, room heat anchors and interrupted placement cargo.
It joins the job/save reliability gate as fixture 27. Native captures and logs
are under `tmp/wall_height_20261012/`.

Verified: all 27 job/save fixtures and BedroomTest pass. The native mounting
fixture passes and `mounting_heights.png` shows low/default/high mounts beside
a dwarf. Generated-world RoomLightingTest passes with zero failures, including
door shadowing, room light membership, slices and room UI. Its native run uses
isolated APPDATA under `tmp/wall_height_20261012/room_lighting_review/`.
No player save was rewritten.

Restart Play to load the updated definitions and scripts. No editor reload,
new global class or autoload is required.
