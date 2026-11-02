# 34 — Temperature and room comfort

**Stronger, tended hearths (owner, 2026-10-30):** a lit hearth left Furin's 605-cell bedroom
Chilly (10.8°C to 13.4°C), and the owner chose stronger hearths. A hearth now has 9600 heat
units (was 1600), enough for a bedroom of about 600 cells through the winter, and a sealed
room's fires are tended: together they warm it to 18°C (`tended_fire_c`) before its doors
leak, and no further, so a small room is never overheated. Doors still leak as before, so an
entry room still matters. In the open air a fire adds at most 11°C. See "Heat and cold
spreading", from "Tended fires".

**The climate (2026-10-29, doc 282 phase 1):** every spot has a temperature now, not only
sealed rooms. Higher is colder (1°C per 12 blocks, for air and rock), the year runs from
about −8 to 26°C in the valley, rock damps the seasons, and outside air reaches about 12
blocks into open tunnels until a door stops it. See "The climate".

**The Temperature view (2026-10-29, doc 282):** T colours every floor in view by its
temperature word over the dimmed world, and its hover card tells what sets a spot's
temperature. See doc 23 "The Temperature view".

**Food spoilage (2026-10-29, doc 282 phase 2):** stored, loose and carried food spoils by
the temperature where it is and the open sky over it (doc 42 "Spoilage").

**Heat and cold spreading (2026-10-29, doc 282 phase 3):** a burning fire outside a sealed
room warms the open air within a few walking steps, and each door pulls its sealed room a
tenth of the way toward the other side, so a hearth room warms the room next door and a
door to the open air lets a little of the day and weather in. See "Heat and cold
spreading".

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
absolute-Y cold gradient, with early hearth crafting and actual sleep discomfort. The
climate replaced the sheltered rock on 2026-10-29 (doc 282).

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
throttled to 0.5 seconds. Hour and weather changes recalculate temperatures without flooding
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

## The climate

RoomManager alone reads `data/world_gen/temperature.json`. Its `Climate` component
(`scripts/components/Climate.gd`) holds the rule, and a sealed room adds its heat:

```
T       = mean + season × season_share + (day + weather) × air_share + heat
mean    = 9°C − (height − 19) / 12        a degree colder for every 12 blocks up, warmer below
season  = 12°C × WorldClock.solstice_cosine(day_of_year)     warmest on summer's first day
day     = 5°C × sin((hour − 8) / 24 × TAU) × the weather's daily_swing_scale
weather = the weather's offset_c
rock    = exp(−cover / 8)                 cover: the solid blocks over the spot in its column
heat    = burning sources' heat units / max(volume, 128)     sealed rooms only, tended:
          the room's fires take it to tended_fire_c (18°C) at most before its doors leak
```

| Spot | air_share | season_share | Height |
|---|---|---|---|
| Open sky: nothing solid above, built roofs included | 1 | 1 | its own |
| Under a roof, not sealed | a | max(a, rock) | its own |
| Sealed room, on its own | 0 | mean of rock over its columns, cover over each column's lowest air | its mean floor (lowest air) |
| Solid rock: what a sealed room dug there would feel | 0 | rock | its own |

A sealed room's doors then pull it toward their other sides, and a fire outside a sealed
room adds its warmth to the air round it (see "Heat and cold spreading").

- **a**, the outside air: 1 under open sky, falling evenly to 0 at `outside_air_reach_blocks`
  (12) walking steps through air from the nearest open sky. A door's sealing cells stop it,
  and a search past 4,096 cells gives up (a = 0). Day and night travel only this way; rock
  passes only the season.
- **Cover** counts every solid block over the spot in its column as it is now: rock, built
  blocks, and caves the colony has not found, so temperature never gives a hidden cave away
  (Hard Rule 11). Mining above a room, or stacking stone on a hut, changes it. Until
  2026-10-29 cover came from the natural heightmap.
- **Weather:** each `data/weather/*.json` has a `temperature` block. Clear keeps the whole
  day's swing; overcast keeps half and foggy 0.4; rain (−1°C), storm and snow (−2°C) keep 0.4.
  `wet` marks rain, storm and snow for spoilage (doc 282). Weather reaches a sealed room only
  through a door to the open air.
- **The season** reads the calendar's day of year and solstice (`data/calendar/calendar.json`),
  so it turns smoothly across season boundaries. Until 2026-10-29 (doc 281) it hard-coded a
  28-day season and a 112-day year.
- **Cost:** temperatures are worked out when asked and never saved. Rooms recompute on each
  game hour, on a change of weather and when rebuilt. The component caches each column's solid blocks and each
  spot's reach to open sky; a block change clears its column and the reach within 12 blocks,
  and door changes and cave discoveries clear what they touch. Nothing runs per frame.
  A column is read a chunk at a time (the generator's surface and cave span where no chunk
  is loaded), about 0.012 ms a column in the owner's colony; the cache starts again past
  65,536 columns (about 13 MB), as the Temperature view reads some 20,000.
- **Highest solid:** `highest_solid(x, z, top)` finds a column's highest solid block at or
  under a height from its cached profile; the Temperature view finds each column's floor
  under the slice with it.

What it gives, each checked at the year's extremes by `ClimateTest` to 1°C:

| Place | Over a year |
|---|---|
| Valley, open sky | −8 to 26°C |
| Summit (Y115), open sky | −16 to 18°C |
| Tunnel into a Y35 shelf, 6 blocks from open air | 0 to 17°C |
| The same tunnel 12 or more blocks in | 7 to 11°C |
| Sealed valley cellar under 12 solid blocks, its door onto the valley | 5 to 13°C (6 to 12°C before doors leaked) |
| Sealed cellar just under the summit (floor Y100), its door into rock | −0.4 to 5°C, frozen for about two weeks around winter's first day |
| Deep under the mountain at the valley's height | 9°C, steady |
| Near bedrock under the valley (Y6) | 7 to 13°C |

Dwarves sleeping outside a sealed room feel their spot: under open sky the whole swing, in a
tunnel what reaches them, and beside a lit campfire up to 6°C more. Nothing freezes all
year; only cellars just under the summit freeze, in the depth of winter.

## Heat and cold spreading

Built 2026-10-29 (doc 282 phase 3; owner's rules). RoomManager's `HeatSpread` component
(`scripts/components/HeatSpread.gd`) holds it; the numbers are in `temperature.json` and
each fire's `heat_source`.

- **Fires warm open air.** A burning fire whose air is not in a sealed room warms the air
  round it by walking steps through air: heat units ÷ `open_air_heat_per_degree` (150) at
  the fire, at most `open_air_fire_max_c` (11°C), fading evenly to nothing at its
  `heat_source.radius`. Solid blocks, doors and sealed rooms stop it; fires that reach the
  same air add up. In a sealed room a fire heats the room as before, and warms no open air.
  The cap keeps a hearth sized for a big room (2026-10-30) no warmer outdoors than before.

  | Fire | At the fire | Reaches |
  |---|---:|---:|
  | Campfire (900 units) | 6°C | 5 steps (4.8°C one step out, 1.2°C at four) |
  | Hearth (9600) | 11°C, the cap | 4 steps |
  | Log torch (75) | 0.5°C | 2 steps |

- **Doors leak.** Each door piece pulls a sealed room `door_leak` (0.1) of the way toward
  the temperature on its other side, times 128 ÷ its volume for rooms bigger than 128 cells.
  The other side is the room or rooms beside its doorway, else the open air there, with any
  fire's warmth in it. `door_leak_passes` (2) passes each take the neighbours' last values,
  so a chain of rooms settles at once. With 6.25°C of heat (an 800-unit fire) in a
  4 × 4 × 4 room, the fire's room keeps 5.69°C, the room next door gains 0.56°C and the one
  beyond 0.06°C (`ClimateTest`). A door into rock, or between two parts of one room, leaks
  nothing.
- **Doors to the open air** let in a share of the day, the weather and the season beyond
  the room's rock: 9% for a 6 × 6 × 4 cellar (0.1 × 128 ÷ 144). So the valley cellar runs 5
  to 13°C instead of 6 to 12. A one-hearth 6 × 6 × 4 bedroom is held at 18°C before its door
  leaks; with the door straight onto the valley it falls to 15.7°C, Chilly, on the coldest
  nights. Behind an entry room it stays Comfortable, about 17 to 17.6°C all year, and the entry
  room is about a degree warmer for the hearth next door (`HearthRoomTest`). An 8 × 8 × 4
  barracks with its door outside is 16.7°C on a winter night with one hearth, and a second
  adds nothing. The owner kept this (2026-10-29): entry rooms are worth building, and doors
  to the open air leak as much as any other door. Since 2026-10-30 one hearth warms a room
  of up to about 600 cells, so a second hearth is for a bigger room.
- **Forms.** Temperatures are linear forms, Vector3(base, season share, day-and-weather
  share): a room's own (`own_form`, its rock and heat) and after its doors (`temp_form`).
  A leak blends forms, so the clock moving changes none of them; the Temperature view's
  shader reads `temp_form`. A room whose fires can hold it at the tended 18°C has a flat
  form there; as the season turns it moves between that and rock-plus-fire at the hourly
  recompute, and only then does the view build its tiles again.
- **What the fires and doors add.** The leak is linear, so `HeatSpread.kept_share` runs
  its passes over a room's heat alone to find what the room keeps of it (0.9 behind one
  door to the open air). `climate_at` gives `heat_c`, what a room's fires add after its
  doors, and `door_c`, what its doors add with its own fires left out, so a room's
  temperature is its rock's plus `heat_c` plus `door_c`; and `fire_c`, a fire's warmth in
  open air. `heat_kept(air_cell, units, burning)` gives one source's share of the room's
  tended heat, or for a source not burning what it would add on top of those that burn;
  the hearth's panel shows it ("This hearth +7.1°C", "+7.0°C while lit") and the
  fire-lighting rule uses it.
- **No warm-up.** All of this settles at once and is never saved: on each game hour, on a
  change of weather and on room rebuilds, and once a frame at most after a fire is lit or
  goes out, a door changes or a block changes within a fire's reach. `warmth_changed(cells)`
  tells the Temperature view which open-air cells changed. Thermal mass can come later if a
  feature needs it, such as an ice house.
- **Big halls:** space past 4,096 cells stays unsealed. Far from open air it sits at rock
  temperature anyway, and fires warm it locally.

| Installed source | Heat units |
|---|---:|
| Log torch | 75 |
| Campfire | 900 |
| Rudimentary hearth | 9600 (1600 until 2026-10-30) |

The wall torch (100) and the brazier (3200) left the game with the other uncraftable
furniture (doc 234).

A stone hearth is available in Rudimentary → Rooms: two matching logs,
four rough stones and 18 seconds at a crude workbench. **Tended fires (owner, 2026-10-30):**
a sealed room's fires together warm it to `tended_fire_c` (18°C) before its doors leak and
no further: the dwarves feed them only so much. A room they can warm past 18°C is held there;
one whose rock is already warmer gets nothing from them. The 9600-unit hearth adds 16°C to a
600-cell room, so one keeps Furin's 605-cell bedroom (floor 56, 40% open to the season)
Comfortable all year: 17.9°C lit on a summer night, 16.8°C on the coldest one
(`HearthRoomTest`). Any room up to about 600 cells sits at 18°C less its doors' leak: a
valley cellar under 12 solid blocks stays about 17 to 17.6°C behind an entry room, and falls
to 15.7°C, Chilly, on the coldest nights with its door straight onto the valley. One just
under the summit, its door into the rock, stays at 18°C all year, and a second hearth adds
nothing (until 2026-10-30 one gave 10 to 16°C and two overheated it to 28°C in summer). A
bigger room gets 9600 ÷ its volume, so past about 600 cells a second hearth helps. A hut under
a one-block roof feels nearly the whole season (about −2 to 19°C unheated in the valley); its
hearth stays unlit on nights the hut is already Comfortable (see "Warm rooms keep their fires
unlit"). A room can still turn Hot from its own rock or a warmer neighbour, never from its
fires. Torches principally supply light.
The campfire stays an outdoor gathering fire in its 3 × 3 camp area; the hearth is the
room heater, its fire-back to a wall and its fire turned into the room (docs 199, 279). Heating a room needs a detected
enclosed room: a campfire indoors still adds its 900 units; outdoors a fire warms only the
air within a few steps. `heating_contribution()` is the one formula for a room's heat before
the tended cap; a burning source's share is the room's tended heat in proportion to its
units, so several hearths never each claim it all, and `heat_kept()` is that share less what
the room's doors leak away. Ghosts, packed and carried pieces emit no heat; removal and save reconstruction
update installed contributions exactly once.

**Nightly fires (owner, 2026-10-28, doc 279).** The campfire and the hearth hold no wood
of their own. At dusk a worker sets a log in each cold one and lights it, and it burns
until dawn, when the log is gone: one log per fire per night. Dusk and dawn are the sky's
seasonal sunset and sunrise (`WorldClock.is_night()`). A fire heats only while it burns
(`RoomManager.set_fire_lit`); a dwarf going to bed before dusk lights its own (see
"Bedtime fires"). A cold fire still counts as its room's light, so a bedroom keeps its kind
by day. Torches need no fuel. Exhaust is not implemented.

**Warm rooms keep their fires unlit (owner, 2026-10-29, doc 282).** A fire in a sealed room
is lit only while the room is below Comfortable (16°C) without that fire's own heat (what
the room keeps of it past its doors, `RoomManager.heat_kept`). Each
room change re-checks it (`FurnitureFires.needed`, on RoomManager's `room_updated` and
`room_removed`): a job that is no longer needed is retired, and a worker already carrying
the log drops it intact. So a second hearth stands down once the first has warmed the room,
and a summer hut keeps its log instead of overheating. Its panel line reads "Unlit · the
room is warm enough". A cold fire that would add nothing, because another already holds the
room at the tended 18°C, stays unlit too, even in a room its door leaves Chilly: "Unlit ·
another fire already heats the room" (2026-10-30). A fire outside any sealed room, such as the
campfire, is lit every dusk as before. A lit fire burns until dawn even if the room warms;
being tended, it never takes its room past 18°C.

**Bedtime fires (owner, 2026-10-30).** Furin went to bed at 20:40 on a summer evening, before
the 22:00 dusk, and slept beside his unlit hearth. Now a tired dwarf (sleep at the 0.25
threshold) whose first-choice bed (`DwarfBedRest.ranked_beds`) stands in a sealed room
with a cold fire that the room needs lights that fire before lying down, by day too.
- **The job.** The dwarf takes the fire's own light job (`FurnitureFires.bedtime_job`,
  handed over by `TaskManager.assign_to`): it fetches a log from storage or the floor,
  sets it in and lights it, then goes to bed. Ordinary hunger still waits for waking.
- **When it is skipped.** If another worker already has the job, there is no log, the
  dwarf stands on a ladder, or the trip passes `rest.bedtime_fire_hours` (2 game hours),
  the dwarf goes to bed anyway. It tries once per bedtime, and by day nobody else
  takes up a job that its sleeper dropped.
- **Burning by day.** A fire lit by day burns while a dwarf who is asleep, or tired
  enough to sleep, is in its room (`FurnitureFires._slept_in`). It goes out, its log
  spent, at dawn or when the last sleeper wakes (`dwarf_woke`), never on a room
  re-check or a load: rooms are rebuilt a moment after loading, and the clock is restored
  after the furniture. If night falls first, the fire burns until dawn as usual.
- **Panel lines.** A cold fire in a sealed room reads "Cold · lit at dusk or at bedtime";
  one burning by day reads "Burning while a dwarf sleeps here".
- **Heat decides comfort.** With the 1600-unit hearth of the day, lighting it took Furin's
  605-cell bedroom only from 10.8°C to 13.4°C, still Chilly. The owner chose stronger
  hearths the same day: lit, it now reaches 17.9°C (see "Tended fires" above).

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

`get_room_at(air_cell)` exposes `temp_c`, `heat_bonus_c`, `own_form`, `temp_form`,
`is_frozen_vault` and room classification. `temperature_at(cell)` gives any spot's
temperature, a fire's warmth included. `climate_at(cell)` adds its word (`temperature_word`:
Frozen at 0°C and below, then the sleep words), what sets it (kind `open_sky`, `sheltered`,
`room` or `rock`, with its steps from open air and its cover), its range over a year in
clear weather with today's fires and doors, `fire_c`, `heat_c` and `door_c` (see "Heat and
cold spreading"), and whether the weather is wet. The DEV block inspector prints it for the
inspected air, and the Temperature view's hover card shows it (a heated room's year without
its fires). The view's floors carry each floor's base temperature and shares (`mean_c` and
`exposure` plus a fire's warmth, or a sealed room's `temp_form`), so its shader gives
`temperature_at`'s value from `season_c()` and `day_and_weather_c()`. Frozen status is an actual
temperature of 0°C or below. Food spoilage reads `temperature_at`, `is_open_sky` and
`is_wet` each game hour (doc 42 "Spoilage"), so a frozen room keeps food almost as it is.
Temperature-gated brewing/aging is not implemented; earlier doc 34 freezing-by-depth and
aging examples are superseded, not live mechanics.

`ClimateTest` covers the climate and its spreading, and `TemperatureViewTest` the view; BedroomComfortTest, BedroomPrivacyTest, BedOwnershipTest,
HearthRoomTest and SaveManagerRoundTripTest cover rooms and sleep. The bedroom tests that
measure comfort stack stone on their rooms (`BedroomTest._bury`) so they stand for cellars.
