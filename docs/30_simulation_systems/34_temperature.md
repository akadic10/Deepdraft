# 34 — Temperature and room comfort

**Room scheduling (2026-10-14, doc 185):** RoomManager keeps the 0.5-second coalescing
delay, then advances `RoomRebuild` across frames under a soft 1.5 ms budget, checked
every 16 operations (`data/rooms/detection.json`). Every stage resumes on the main
thread; no worker thread reads world data. RoomManager installs the complete room and
cell maps together, with temperatures from the clock at that moment, before any
`room_updated`/`room_removed` signal; readers keep the previous complete result while
work is pending. A change to a chunk the scan has already read, or a door, light, heat,
bed or bed-owner change, cancels the scan, which restarts on the next frame without
another coalescing delay; chunks not read yet are sampled live, so distant streaming
cannot keep restarting it. World reload discards pending results. Door lighting
boundaries still update immediately. Formulas, sealing and saved data are unchanged.
The synchronous drain (`_rebuild_all_rooms`) is for fixtures and development tools
only. The budget is soft: one operation, the final publication and signal callbacks
cannot be split, and continuous edits in examined chunks postpone publication. The
trade is shorter stalls for more total CPU and a short delay before room data updates.

Updated 2026-10-11 (doc 122): sheltered rock temperature replaced the original
absolute-Y cold gradient, with early hearth crafting and actual sleep discomfort.

## Ownership and room detection

RoomManager is the authoritative autoload for sealed rooms, temperature, beds,
owner and installed light/heat counts. Rooms are derived state, rebuilt from
terrain and furniture on load. No separate room records are saved.

**Room appeal data:** RoomManager also owns `data/rooms/appeal.json` (doc 23 "Room
appeal"); the appeal's word reaches happiness through the room thoughts (doc 41). A room's
walking tiles (solid blocks under its air, even below furniture; door seal columns
excluded) set the share a large room counts. The +5 finished-floor bonus left with the
permanent floors on 2026-10-26.

Each door footprint seals four air cells above its floor, independently of its
hinge animation. Flood fills begin on both sides of each door. A finite air
volume bounded by terrain and doors is sealed; a fill beyond 4096 cells is
treated as open. Furniture does not seal air: only door pieces seal, never log gates
or fences (doc 198). Edits, doors, beds and lights dirty the room cache, with rebuilds
throttled to 0.5 seconds. Hour changes recalculate weather exposure without flooding
again. Heat registers once per source; floor furniture samples the air above its floor
anchor. Wall lights sample their
actual mounted air cell, so changing placement height or excavating below does
not associate them with another level's room (doc 129).

**Room kinds** are data: RoomManager owns `data/rooms/room_kinds.json`. A sealed
room takes the first kind whose needs it meets, in the file's order; with none it
is a plain room. The kinds are:
- personal bedroom: one whole bed, with an owner, a light and a door;
- bedroom: the same with no owner;
- barracks: two or more beds, a light and a door.

Bed ownership and bedroom privacy are in doc 41. An owner change reclassifies rooms
at once, without a flood fill (`on_bed_assignment_changed`), and restarts a rebuild in
progress. Losing a required component revokes the classification. Light count is not
inferred from heat. Only installed pieces count: a bed only when its whole footprint
lies inside the room, and a light by the same anchor cell as heat, so a light outside
never counts (doc 120).
`missing_needs()` and `nearest_kind()` give the room window what a room lacks,
and `room_furniture(room)` lists its furniture by the same anchors as lights and
heat; a door belongs to each room it seals. The room window is described in
`23_user_interface.md` (The Rooms Tool).

## Temperature formula

RoomManager alone reads `data/world_gen/temperature.json`:

```
cover = max(original surface Y - lowest interior Y - 4, 0), per floor column
exposure = 0.25 * mean(exp(-cover / 16))
base = 10°C
season = 6°C * cos((day_of_year - 28) / 112 * TAU) * exposure
daily = 2°C * sin((hour - 8) / 24 * TAU) * exposure
heat = sum(installed heat units) / max(room volume, 128)
temperature = base + season + daily + heat
```

The natural heightmap is immutable under mining. Lower absolute Y does not make
ordinary rock colder; cover damps seasonal and daily variation. Outdoor/unsealed
sleep uses the same baseline/weather curve with full exposure attenuated by
overburden. Deliberately cold biomes, weather-event offsets and thermal diffusion
are future extensions. The current normal mountain has no automatic frozen zone.

| Installed source | Heat units |
|---|---:|
| Log torch | 75 |
| Campfire | 900 |
| Rudimentary hearth | 1600 |

The wall torch (100) and the brazier (3200) left the game with the other uncraftable
furniture (doc 234).

A stone hearth is available in Rudimentary → Rooms: two matching logs,
four rough stones and 18 seconds at a crude workbench. The compact 2×2 open-front
heater warms a 6×6 room with four air blocks of height (144-cell volume) to
19.1–23.1°C across seasonal extremes. One hearth plus a log torch in the minimum
128-cell thermal mass reaches at most about 25.1°C. A larger 8×8×4 winter room
is 14.25°C with one hearth and 20.5°C with two. Multiple heaters can still
overheat a small room; there is no thermostat. Torches principally supply light.
The campfire stays an outdoor gathering fire in its 3 × 3 camp area; the hearth is the
room heater, its opening turned into the room (doc 199). Heating needs a detected
enclosed room: a campfire indoors still adds its 900 units, but outdoors no fire warms
the air around it. `heating_contribution()` is the one formula for a room's total and
for a single source's share, so several hearths never each claim the room's whole
heat. Ghosts, packed and carried pieces emit no heat; removal and save reconstruction
update installed contributions exactly once.
Fuel use, ignition and exhaust are not implemented yet.

## Comfort and sleep thoughts

| Temperature | Room label | Sleep thought |
|---|---|---:|
| Below 8°C | Cold | −20 happiness |
| 8 to below 16°C | Chilly | −5 happiness |
| 16 through 26°C | Comfortable | No penalty |
| Above 26°C | Hot | −15 happiness |

DwarfMood records exposure only while actually asleep, at the bed's room or
ground sleep cell. After one game hour in a category, its thought lasts 24 game
hours and refreshes during continued exposure. Only the strongest remembered
thermal penalty applies, alongside the personal-bedroom +10 bonus. At 4°C the
cold penalty outweighs owning the bedroom. Walking and settling do not count.
Timers follow pause/speed and survive saves. Work-temperature reactions,
injuries, sickness, hunger and thirst remain separate future systems.

Both room inspectors show the actual temperature label, computed heating bonus,
volume, doors and seasonal influence. Mean floor level is diagnostic information,
not a cold-zone label. The character sheet shows happiness in its header and each
thought with its hours left on its Mood tab (doc 23).
The installed hearth's compact panel ([23](../20_player_interface/23_user_interface.md#object-selection-implemented-2026-10-04))
names its current room and temperature on its status line. Outside a detected room the
status says there is no enclosed room to heat, and hovering the description explains
that walls, a roof and a door are needed. These values are read from
RoomManager's current derived room map; topology and hour changes refresh them.

## Future consumers

`get_room_at(air_cell)` exposes `temp_c`, `heat_bonus_c`, `is_frozen_vault` and room
classification. `temperature_at(air_cell)` also handles unsealed positions.
Frozen status is an actual temperature of 0°C or below. Food spoilage,
temperature-gated brewing/aging and freezer benefits are not implemented; earlier
doc 34 freezing-by-depth and aging examples are superseded, not live mechanics.

BedroomComfortTest, BedroomPrivacyTest, BedOwnershipTest and SaveManagerRoundTripTest
cover the current behavior.
