# 103 — Evening session handoff: 2026-10-09

**Historical handoff:** superseded by [112 — Water and wildlife, 2026-10-10](112_session_handoff_2026_10_10.md).
This was the starting point after [89 — Earlier handoff](89_session_handoff_2026_10_09.md).
The earlier handoff retains the world, caves, plants, hauling and ladder history.
This session added wildlife and arrivals, profession screens and Miner progression,
starter tools, camp furniture and leisure, then physical Carpenter promotion and
equipment feedback. This wrap-up changes documentation only.

## Where we stopped

The player can craft a crude carpentry kit, promote a Worker by having them collect
and equip it, and see the actual tool under **Equipment** in Colony or the world
inspector. A short chime marks completed promotion. The latest UI/audio checks
pass, including compact screens. The player has not yet reported a playtest of
this final Equipment/chime update.

**Carpenter promotion is live; Carpenter specialist production is still planned.**
The equipped kit grants no work-speed bonus. Rudimentary crafting remains
Worker-only, so keep a Worker available for the current recipes. Other allowed
general jobs remain available to the Carpenter. Iron saw and iron pickaxe are
explicit future previews, not craftable or assignable upgrades.

## Completed work

| Area | Current behavior | Detailed record |
|---|---|---|
| Rabbits | Seeded rabbits hop, flee dwarves, graze and sleep. Hunger is gentle; no starvation damage. Quiet selection and eating sounds follow the existing audio controls. | [90 — Rabbits](90_rabbit_wildlife.md), [91 — Audio](91_rabbit_audio.md) |
| Deer and wolves | Deer form loose herds and flee predators. Sparse wolves hunt rabbits/deer with hunger, retry and meal-satisfaction gates, protected prey reserves and no colonist attacks. All species have voxel animation, inspection, sound and persistence. | [92 — Deer](92_deer_wildlife.md), [93 — Wolves](93_wolf_wildlife.md), [45 — Wildlife](../40_economy_colony/45_wildlife.md) |
| Off-map arrivals | Shared event owner schedules bounded rabbit, deer and wolf opportunities. Animals physically enter through validated map-edge routes. Population/habitat/pressure checks can prevent entry; kills never accelerate or enlarge arrivals. | [94 — Rabbit arrivals](94_rabbit_arrival_events.md), [95 — Deer/wolf arrivals](95_deer_wolf_arrivals.md) |
| Colony and professions | Shared dwarf inspection, career map, appointment requirements and real Work permissions. Worker/Miner changes retain experience. Miners get first refusal on eligible mining and levels 1–5 from completed blocks; Workers still mine. | [96 — Professions](96_professions_and_miner.md) |
| Starter tools | Workers craft stone hoes, hunting spears, crude carpentry kits and stone hammers from one allowed log plus one Rough Stone at the crude workbench. Tools are physical, stored and saved goods. Only Carpenter's tool promotion is active so far. | [97 — Starter tools](97_starter_profession_tools.md), [101 — Tool promotion](101_tool_based_promotion.md) |
| Crafting assignment | New batches compare eligible idle Workers at the actual first ingredient, validating pickup and workshop routes. Loose and stored sources compete; failed nearby routes do not hide other candidates. Active batches retain their worker. | [98 — Selection](98_crafting_worker_selection.md) |
| Idle activity | Dwarves take short nearby walks, look around and use exclusive seats while remaining available for work. Work interrupts leisure immediately. Sitting creates no new needs or bonuses. | [99 — Leisure](99_dwarf_idle_activity.md) |
| Craft navigation | Craft opens profession icon submenus above the dock. Rudimentary opens live Worker recipes; specialists show planned sections. Crafters returns to the chooser. The old profession dropdown is removed. | [100 — Camp crafting](100_profession_crafting_camp.md) |
| Camp furniture | Craft, haul and install campfires and 1×1 stump stools. Campfire centers on a tile within a 3×3 area. Stools fit directly beside its four sides; seated dwarves use the revised pose and prefer facing a visible nearby fire. Packed items appear in Place. | [100 — Camp crafting and follow-ups](100_profession_crafting_camp.md) |
| Physical promotion | Carpenter reserves and collects a real kit before changing profession. Cancellation and interruption release goods safely. Changing professions returns the kit. Inventory distinguishes equipped goods from available stock and cargo; current saves retain equipped and pending state. | [101 — Tool promotion](101_tool_based_promotion.md) |
| Equipment and sound | Both dwarf inspector hosts have an Equipment tab with picture, name, materials and actual benefit, plus planned upgrade paths. Completion plays a promotion chime; request/cancel/demotion/load do not. Paused Miner promotion is audible. | [102 — Equipment feedback](102_equipment_view_promotion_feedback.md) |

## Decisions to preserve

- Use **Hunter**, not Trapper, and **Stonemason**, not Stonesmith.
- **Rudimentary** is the starter crafting category. Profession submenus belong
  above the main dock, following the supplied Stonehearth navigation reference.
- Miner starts freely with the default pickaxe. Profession experience and crafted
  equipment are separate progression systems. Leveling must not create free tools.
- Carpenter starts with a wooden mallet/stone adze kit, avoiding a Blacksmith
  dependency. A forged saw is a later upgrade. Do not introduce a wooden saw.
- Future iron/advanced-metal picks may occasionally complete additional valid,
  marked voxels. Limits and balance remain future implementation; see
  [43 — Mining](../40_economy_colony/43_mining_materials.md).
- Animal needs should create enjoyable visible behavior, not constant emergencies.
  Arrivals are opportunities, not a reward for wiping out animals. Wolf predation
  does not count as player hunting pressure.
- **Older development saves do not need compatibility.** Do not add migrations,
  obsolete definitions or branches to preserve old layouts. Use current definitions
  on load; keep current-version item conservation and save/load reliable.

## Recommended next milestone

Complete the first useful **Carpenter production loop**:

1. Add a Carpenter workbench that can be established using the current kit and
   starter economy, without forged tools or a circular workshop dependency.
2. Choose a small first recipe set from useful wooden furniture/storage. Exact
   recipes, costs, durations and progression should be settled at the start of
   that pass; the existing planned catalog is not an implemented recipe list.
3. Connect Carpenter-only production to the existing profession submenu, physical
   material delivery, workshop claims, interruption, placement and save owners.
4. Verify the full player route: Worker makes kit → dwarf collects/promotes →
   establish workbench → craft an item → haul/install it. Cover multiple eligible
   workers, unavailable materials, cancellation and current-version save/load.

This is the recommended resumption point, not work performed by this wrap-up.
Read [44 — Crafting](../40_economy_colony/44_crafting_workshops.md),
[101](101_tool_based_promotion.md) and [102](102_equipment_view_promotion_feedback.md)
before implementation. Preserve the useful Rudimentary bootstrap recipes.

## Still planned or deferred

- Farmer, Hunter, Stonemason, Blacksmith and other specialist gameplay. Their
  previews or starter goods do not mean those professions are playable.
- Farming, animal berry nibbling/crop theft, player hunting, animal loot,
  domestication and breeding. Rabbits/deer currently graze ordinary vegetation.
- Actual iron saw/pickaxe recipes, upgrade assignment, automatic upgrades,
  equipment bonuses, durability and repair. The Equipment view is informative.
- Goblin/orc/trader arrival providers. The shared entry framework is ready for
  expansion, but no such visitor/raid behavior is claimed implemented here.
- Campfire fuel, cooking, social gatherings, dining needs, bed use and dwarf
  hunger/mood systems. Current seating is ambient, interruptible leisure.
- Earlier cave/content checks, honey/flower integration, resource balance,
  season-transition performance and optional ladder planning remain in
  [89 — Earlier handoff](89_session_handoff_2026_10_09.md).
- [Issue 001](00_open_issues.md) remains open for its original mining-face stall;
  Issue 002 remains parked for dwarf/terrain overlap. New crafting selection and
  idle movement fixes do not establish either old report resolved.

## Verification and working state

Milestones 90–102 record their individual behavior, native rendering/audio and
save/backup checks. This does not claim every historical suite was rerun after
the final edit. The latest Equipment/chime pass verified:

- `EquipmentFeedbackTest`: real kit ownership, completed versus pending/cancelled
  promotion, pause/resume, silent restore, bounded playback, and both inspector
  hosts at 960×540, 1280×720 and 2560×1440. Native captures were reviewed.
- `PromotionAudioPlaybackTest`: actual game-output PCM, including audible paused
  feedback, reduced volume, silent mute/cleanup and clipping headroom.
- ToolPromotion, DwarfInspector, DwarfRoster, DwarfProfessionPanel, WorkFeedback
  and RabbitAudio regressions. The cramped compact roster detail area was fixed
  and its final run passes. Editor import and whitespace checks also pass.

Latest evidence: `tmp/equipment_ui_review/`, especially
`EquipmentFeedbackTest_final.log`, `DwarfRosterTest_final.log`, `audio.log`,
the named regression logs and native PNGs. Earlier failed logs may remain beside
the final passing runs. Existing fixture sky/weather warnings are not new errors.
The preceding physical-promotion milestone also checked full scene save/autosave
and backup restoration; see [101](101_tool_based_promotion.md).

Tests use isolated APPDATA/LOCALAPPDATA profiles. Preserve the player's saves and
running editor/game. Restart play to load the final Equipment/chime changes;
that last update introduced no global class or autoload requiring a project reload.

The workspace contains substantial uncommitted code, data, original assets,
tests and documentation from the session, including untracked files. This wrap-up
does not commit, reset or clean them. Documentation links and whitespace are
checked; gameplay suites are not rerun for these prose-only changes.
