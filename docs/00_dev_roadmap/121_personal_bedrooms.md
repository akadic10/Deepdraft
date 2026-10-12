# 121 — Personal bedrooms, barracks and sleep comfort

Implemented 2026-10-11 after the first furnished-bedroom playtest.

Select an installed bed in Object explorer and use **Assign bed…**. The menu
lists colonists and Unassigned. Each colonist can own one bed; choosing someone
who already owns another moves that assignment. Unassigned beds remain available
to anyone. Ownership is distinct from the temporary sleeper claim and survives
waking and saving. Uninstalling/removing the bed removes its assignment.

Tired dwarves try their assigned bed first, then nearby unassigned beds and the
existing ground-rest fallback. Other colonists never take an assigned bed. Routes
and access still have to be valid. Reassignment during sleep releases any displaced
sleeper and restarts their search without resetting their remaining sleep need.

RoomManager derives these types from complete bed footprints inside a sealed room
with a door and an installed light:

- One unassigned bed: **Bedroom**, available for assignment.
- One assigned bed: **Personal bedroom**, identifying its resident.
- Two or more beds: **Barracks**, regardless of the individual bed assignments.

The room inspector shows the type and resident or shared-quarters explanation.
Changing assignments does not require a terrain flood-fill; changes to beds,
lights, doors and enclosure use the existing room rebuild.

The first live comfort thought is **Slept in my own bedroom**. Completing a rest
with at least three game hours actually asleep in one's personal bedroom grants
+10 happiness for 24 game hours. Base happiness is 50%; the bonus raises it to
60% (Happy). Repeating the thought refreshes its duration instead of stacking.
Walking to bed, settling, unassigned beds and barracks do not earn this thought.
The dwarf inspector shows happiness in Overview and the thought/time in Details.
Timers honor pause and clock speed and survive mid-sleep and post-sleep saves.
Temperature thoughts and bedroom leisure privacy followed in milestone 122.
Food, drink, quality effects and tantrums remain unimplemented.

Ownership is serialized by FurniturePlacementController on bed pieces. DwarfMood
owns qualifying sleep progress and the thought timer, serialized by DwarfAgent.
TaskManager loads the `mood` tuning in `data/tasks/task_config.json`. Room type,
room resident and current sleeper remain derived or transient. Save validation
checks assignment identities/uniqueness and mood timer types and signs.

## Torch lighting

The flame already sits above the log bed's headboard. The old six-block log-torch
range cut off the far end of a 4×7 bedroom. Log and iron wall torches now use a
12-block range, 0.6 attenuation and a 0.25 source size. Energy, mounting height,
placement clearance, heat and audio are unchanged. Furniture and terrain still
cast shadows; no ambient light is added through closed doors or solid rock.

## Verification

BedOwnershipTest covers the actual assignment menu, owner preference, exclusive
use, personal/barracks transitions, interrupted and completed sleep, pause/speed,
JSON restore, unassignment/reassignment and compact inspectors. BedroomLightingTest
recreates the reported 112-block room in generated terrain with a real bed, door
and torch, compares native before/after pixels and checks the adjacent dark corridor
and the unlit room. SaveManagerRoundTripTest includes a real assigned bed and
saved sleep/thought progress through scene replacement and backup recovery.
Native captures are in `tmp/personal_bedroom_20261011`.
