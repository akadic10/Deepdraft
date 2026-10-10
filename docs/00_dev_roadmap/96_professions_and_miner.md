# 96 — Professions and Miner

Implemented 2026-10-09 after the player approved the career map, Miner behavior,
and named Farmer, Carpenter, Stonemason and Hunter as planned professions.

**Later status:** [101 — Tool promotion](101_tool_based_promotion.md) activates
Carpenter after real kit collection, and [102 — Equipment feedback](102_equipment_view_promotion_feedback.md)
adds the Equipment tab and completion chime. Carpenter specialist production and
equipment upgrades remain planned. The original milestone scope below is historical.

## Player flow

**Colony → Dwarves → select a dwarf → Profession** opens a career map with a
personal appointment card, requirements, retained experience and progression.
The same action is available when inspecting a dwarf in the world. Worker and
Miner are available; Farmer, Hunter, Carpenter, Stonemason, Blacksmith,
Weaponsmith and Armorsmith are inspectable **Planned** entries. The last two
branch from Blacksmith. A connection means career ancestry, not which craftsperson
will eventually make a tool. No planned role can be assigned through the API.

Promote/Resume Miner and Return to Worker work while paused. The screen names its
subject explicitly and revalidates roster membership. Closing it releases the
portrait; Escape returns to the underlying roster. A removed/reloaded subject
closes the screen. The map and descriptive panels scroll independently; compact
layouts keep the selected career and action visible above the dock.

The roster now has **Overview / Work** views. **Colony → Labor** also opens the
real Work view, replacing the sample Labor window. Per-dwarf Haul, Gather, Mine,
Build and Craft checkboxes govern new jobs and release a now-disallowed active
job. Necessary transport within an allowed assignment remains allowed. Rest is
automatic. Craft remains Worker-only; its retained permission becomes available
again after returning to Worker. Other permissions are preserved across careers.

Dock popup menus use CanvasLayer 23 so Colony → Labor stays clickable over the
wide roster at layer 22. The dock itself stays at 20; HUD callouts remain at 24.

## Miner behavior

- Workers retain normal mining speed and all existing capabilities.
- Idle Miners receive first refusal on mining leases within the existing priority
  buckets. Higher-priority work still wins, and existing jobs are not stolen.
- An unreachable Miner cannot block a reachable Worker. Failed worker probes are
  remembered across scheduler budget yields and invalidated by pool/navigation
  changes. A lease backs off only after all eligible idle candidates fail.
- Successful block removal awards exactly one Miner experience, including the
  final block that synchronously destroys its zone. Partial swings, cancellation,
  walking, hauling and Worker mining award none.
- Cumulative thresholds are 0 / 10 / 100 / 500 / 2500 blocks for levels 1–5.
  Digging duration multipliers are 1 / .95 / .90 / .85 / .80. These are initial
  balance values; walking, other jobs and resource yields do not change.
- Returning to a profession retains its experience. Worker leveling, legendary
  level 6, equipment gates, tool durability and new profession recipes are deferred.

Promotion and permission changes use existing abort/release behavior. Goods are
set down safely, reservations are released and source-owned progress remains.
An unfinished mining block retains its full durability, consistent with the existing
mining interruption contract. Sleeping dwarves are never requeued early.

## Agreed follow-up — equipment (2026-10-09, not implemented)

After playtesting Miner promotion, the player approved crafted tools as a separate
progression path alongside profession choice and retained experience. Miner stays
available with the default pickaxe; selected future careers will require starting
tools. Iron pickaxes are the first planned upgrade, with occasional two-voxel
completion; advanced metal can later allow occasional three-voxel completion.
Effects stay inside valid designated mining work and do not chain.

The future promotion/inspector screens will show tool requirements, availability,
maker and equipped benefits, with automatic upgrades and manual allocation.
Workers must be able to establish the first specialists without circular tool
requirements. Durability and repairs remain deferred. The authoritative design is
[41 — Equipment progression](../40_economy_colony/41_dwarf_agents.md#agreed-equipment-progression--planned-2026-10-09)
and [43 — Pickaxe upgrades](../40_economy_colony/43_mining_materials.md#pickaxe-upgrades--planned-2026-10-09).
This follow-up records the agreement only; milestone 96 still has no equipment
inventory, tool gates or multi-voxel mining.
Milestone [97 — Starter tools](97_starter_profession_tools.md) subsequently adds
craftable/storable starter goods for Farmer, Hunter, Carpenter and Blacksmith,
plus tool stock/maker in the profession preview. Equipping, specialist promotion
and upgraded-tool bonuses remain future work.

## Ownership and persistence

`DwarfAssets` owns `data/professions/professions.json`, including presentation,
availability, experience thresholds and work-category definitions. Runtime role
availability is the explicit `promotion_enabled` allowlist; legacy `status: active`
values do not activate planned content. No new autoload or global class is added.

`DwarfProfessionPanel` presents the tree/card; `DwarfDirector` registers its window.
The existing inspector and roster remain shared. `DwarfAgent` owns role changes,
permissions, completed-block experience and its digging multiplier. `TaskManager`
filters eligibility and preserves bucket priorities, scheduler budgets and
resumable probes. Permission lookup is cached by task name in the registry.

Profession and experience use their existing save fields. Optional
`work_permissions` is saved/restored with the dwarf; missing fields allow all
normal work for older saves. Hunter and Stonemason keys join the generation list.

## Verification

`MinerProfessionTest` exercises real block removal, threshold boundaries, timing,
interruptions, retained experience, sleeping promotions, permissions, Miner-first
assignment, unreachable-Miner fallback and higher-priority competing work.
`DwarfProfessionPanelTest` covers real UI clicks, future-role rejection, paused
promotion while carrying cargo, Work controls, retained levels, stale subjects,
Escape and native 960×540 / 1280×720 / 2560×1440 layouts.

The full `SaveManagerRoundTripTest` includes a sleeping Miner, experience and mixed
work permissions through save/load and backup restoration. Roster, inspector,
mining animation, surface-worker selection, hauling selection, Worker crafting,
shrub Move handoff, placement-over-hauling, ladder mining and natural-ledge mining
regressions are also exercised. The inspector fixture now initializes its waterline
map for the existing camera zoom test instead of reading an empty array.
The native navigation preview checks the actual last visible catalog tile; it no
longer assumes the aging rack is last after plants and ladders were added.

Native captures and isolated test logs: `tmp/profession_review/`.

Restart play mode to review. No editor project reload is required.
