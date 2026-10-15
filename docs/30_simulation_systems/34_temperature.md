# 34 — Temperature and room comfort

**Room scheduling (2026-10-14):** [185 — Room rebuild performance](../00_dev_roadmap/185_room_rebuild_performance.md)
keeps the 0.5-second coalescing delay, then spreads detection and geometry-derived
metadata across frames under the soft 1.5 ms budget in `data/rooms/detection.json`.
RoomManager publishes complete room/cell maps together and refreshes temperatures
at that point. Readers retain the previous complete result while work is pending.
Edits to examined chunks or furniture changes cancel pending work; distant unread
chunks are sampled live. World reload discards pending results. Door lighting
boundaries still update immediately. Formulas, sealing and saved data are unchanged.
This reduces individual stalls while adding total CPU and room-update latency;
see 185 for measured limits and correctness checks.

Updated 2026-10-11. [Milestone 122](../00_dev_roadmap/122_bedroom_comfort_and_mining_progression.md)
replaces the original absolute-Y cold gradient with sheltered rock temperature,
early hearth crafting and actual sleep discomfort.

## Ownership and room detection

RoomManager is the authoritative autoload for sealed rooms, temperature, beds,
owner and installed light/heat counts. Rooms are derived state, rebuilt from
terrain and furniture on load. No separate room records are saved.

**Flooring appeal (2026-10-12):** RoomManager also owns `data/rooms/appeal.json`.
All interior walking surfaces covered by constructed plank/stone floors grant
one +5 flooring bonus, shown with coverage in Rooms. Mixed materials and tiles
under furniture count; door seal columns are excluded. Terrain changes/load
recompute the contribution. No heat or happiness effect is attached to floors.
See [128 — Floors](../00_dev_roadmap/128_permanent_floor_preview.md).

Each door footprint seals four air cells above its floor, independently of its
hinge animation. Flood fills begin on both sides of each door. A finite air
volume bounded by terrain and doors is sealed; a fill beyond 4096 cells is
treated as open. Furniture does not seal air. Edits, doors, beds and lights dirty
the room cache, with rebuilds throttled to 0.5 seconds. Hour changes recalculate
weather exposure without flooding again. Heat registers once per source;
floor furniture samples the air above its floor anchor. Wall lights sample their
actual mounted air cell, so changing placement height or excavating below does
not associate them with another level's room. See
[129 — Wall mount heights](../00_dev_roadmap/129_wall_mount_heights.md).

A sealed room with a complete bed footprint, a door and a light becomes a
bedroom. One assigned bed makes it personal; multiple beds make it a barracks.
Bed ownership and privacy are described in milestones 121/122. Losing a required
component revokes the classification. Light count is not inferred from heat.

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
| Wall torch | 100 |
| Campfire | 900 |
| Rudimentary hearth | 2400 |
| Brazier | 3200 |

A stone hearth is available in Rudimentary → Camp furnishings: two matching logs,
four rough stones and 18 seconds at a crude workbench. It warms an ordinary
256–324-block starter bedroom to roughly 19–21°C. Larger halls need more heat;
small rooms can overheat. Torches principally supply light. The 128-block minimum
thermal mass moderates tiny rooms. Ghosts, packed and carried pieces emit no
heat; removal and save reconstruction update installed contributions exactly once.
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
not a cold-zone label. Dwarf Overview and Details show happiness and active thoughts.

## Future consumers

`get_room_at(air_cell)` exposes `temp_c`, `heat_bonus_c`, `is_frozen_vault` and room
classification. `temperature_at(air_cell)` also handles unsealed positions.
Frozen status is an actual temperature of 0°C or below. Food spoilage,
temperature-gated brewing/aging and freezer benefits are not implemented; earlier
doc 34 freezing-by-depth and aging examples are superseded, not live mechanics.

BedroomComfortTest, BedroomPrivacyTest, BedOwnershipTest and SaveManagerRoundTripTest
cover the current behavior. See milestone 122 for the saved-player-room measurements.
