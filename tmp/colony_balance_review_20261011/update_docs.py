from pathlib import Path
root=Path('P:/Deepdraft')
temperature='''# 34 — Temperature and room comfort

Updated 2026-10-11. [Milestone 122](../00_dev_roadmap/122_bedroom_comfort_and_mining_progression.md)
replaces the original absolute-Y cold gradient with sheltered rock temperature,
early hearth crafting and actual sleep discomfort.

## Ownership and room detection

RoomManager is the authoritative autoload for sealed rooms, temperature, beds,
owner and installed light/heat counts. Rooms are derived state, rebuilt from
terrain and furniture on load. No separate room records are saved.

Each door footprint seals four air cells above its floor, independently of its
hinge animation. Flood fills begin on both sides of each door. A finite air
volume bounded by terrain and doors is sealed; a fill beyond 4096 cells is
treated as open. Furniture does not seal air. Edits, doors, beds and lights dirty
the room cache, with rebuilds throttled to 0.5 seconds. Hour changes recalculate
weather exposure without flooding again. Heat registers once at a source's
floor anchor; membership tests the air cell above that anchor.

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
| Stone hearth | 2400 |
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
'''
(root/'docs/30_simulation_systems/34_temperature.md').write_text(temperature,encoding='utf-8')
entries={
'AGENT.md':'''**Privacy, heating and mining progression — live (2026-10-11):**
[122 — Bedroom comfort and mining progression](docs/00_dev_roadmap/122_bedroom_comfort_and_mining_progression.md)
adds bedroom leisure privacy with normal visitor exits and filtered sleep routes,
stone hearth crafting (two logs/four stones), sheltered 10°C rock baseline and
actual cold/chilly/hot sleep thoughts. RoomManager owns temperature.json. Ore/gem
progression now requires immutable cover from the natural exterior, including
cliffs, with descent gates for precious resources. Eight fresh-seed samples and
the copied player save are verified; existing mined goods are untouched.
''',
'docs/40_economy_colony/41_dwarf_agents.md':'''**2026-10-11 — Privacy and thermal sleep comfort:** Idle visitors leave bedrooms;
owners may relax in their own, and unassigned bedrooms are for sleep. Work access
remains open. Cold/chilly/hot sleep creates a −20/−5/−15 happiness thought after
one actual game hour asleep; strongest thermal penalty only, lasting 24 hours.
See [122](../00_dev_roadmap/122_bedroom_comfort_and_mining_progression.md).
''',
'docs/40_economy_colony/44_crafting_workshops.md':'''**Stone hearth (2026-10-11):** Rudimentary → Camp furnishings now offers a
stone hearth: two matching logs and four rough stones, physically delivered to
a crude workbench before 18 seconds of work. It emits 2400 heat units and quiet
fire audio when installed. Repeated ingredients appear as one quantity in the
recipe detail. Fuel upkeep remains future work. See milestone 122.
''',
'docs/00_dev_roadmap/71_independent_ore_fields.md':'''**Superseded balance targets (2026-10-11):**
[122 — Mining progression](122_bedroom_comfort_and_mining_progression.md) deliberately
changes depths, cutoffs, deposit scales and yields. Independent seeded metal
fields remain, with natural-cover gating that includes cliffs. The historical
abundance-preservation comparison below is no longer an acceptance target.
''',
'docs/30_simulation_systems/32_navigation_3d.md':'''**Bedroom leisure privacy (2026-10-11):** Normal work navigation still passes
through rooms and doors. Bed searches may supply a per-search floor filter to
avoid other colonists' bedrooms and take a public detour. These routes bypass
the shared work-path cache; sleep string pulling honors the same privacy rule.
Idle/ground-rest visitor exits use bounded checked segments. See milestone 122.
'''
}
for name,entry in entries.items():
    p=root/name
    s=p.read_text(encoding='utf-8')
    first=s.index('\n')+1
    p.write_text(s[:first]+'\n'+entry+s[first:],encoding='utf-8')
p=root/'docs/00_dev_roadmap/121_personal_bedrooms.md'
s=p.read_text(encoding='utf-8').replace('Food, drink, temperature thoughts, quality effects and tantrums remain unimplemented.','Temperature thoughts and bedroom leisure privacy followed in milestone 122.\nFood, drink, quality effects and tantrums remain unimplemented.')
p.write_text(s,encoding='utf-8')
p=root/'scripts/systems/RoomManager.gd'
s=p.read_text(encoding='utf-8')
a=s.index('## doc 34 "Full Temperature Formula", ported verbatim.')
b=s.index('func _recompute_temp',a)
s=s[:a]+'## Sheltered rock climate and installed heating; tuning is owned by this autoload.\n'+s[b:]
s=s.replace('(aging cellar / dwarf-comfort hooks land here per doc 34 — not built yet).','(sleep comfort is live; future aging/spoilage consumers use this query).').replace('Temperature (doc 34, formula ported verbatim)','Temperature (doc 34, sheltered rock climate)')
a=s.index('\t# Cheap path (doc 34 "Recalculation Triggers")')
b=s.index('\tfor room_id:',a)
s=s[:a]+'\t# Hourly weather updates reuse room geometry and its precomputed exposure.\n'+s[b:]
p.write_text(s,encoding='utf-8')
