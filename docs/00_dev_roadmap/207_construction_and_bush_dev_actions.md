# Construction and bush DEV actions

2026-10-17. Adds two player-requested testing shortcuts to the source project.

Select a structural Stone block blueprint or its temporary materials crate and
click **DEV: Finish construction** in Object explorer. It completes the selected
project immediately, including while paused, using delivered stone first and
supplying any missing materials for free. Active builders and haulers release
through the normal task lifecycle; carried supplies return to the ground.
Completion removes the crate, work sources and reservations. Existing floor
plans retain their **DEV Build** button.

The shortcut retains the normal occupancy, water, discovery, support and slice
checks. Blocked cells stay pending with the reason in the inspector. Supported
spans finish even when their supported end comes last in designation order.
Partial completion removes completed work records and keeps staged stock within
the remaining requirement, so unfinished plans can still save and resume.
Constructed stone uses the authored geology and normal terrain/navigation updates.

**Development → Spawn Bushes** creates one mature uprooted blueberry, elderberry
and wild strawberry bush on clear, dry ground near the view centre. These use
the actual seasonal packed models and ordinary item/hauling system. Choose
**Place → Plants** to have dwarves carry and replant them. The flora manager
allocates persistent player-created identities with packed state before spawning
the loose items; no duplicate planted bush appears at the spawn point. Save/load
and subsequent spawning preserve those identities. No new global class, save
schema, art asset or autoload is required.

Validation uses native Godot source fixtures: ConstructionDevTest covers
unfunded completion, pause, active hauling/building, staged resource counts,
crate/task cleanup, blocked-cell retry, partial save/restore and supported spans.
ShrubTransplantTest additionally exercises the real menu command, packed models,
identity save/restore, physical dwarf carrying/replanting and repeated spawning.
RemainingMenusTest checks stable command routing and menu fit at 960×540,
1280×720 and 2560×1440. Existing floor, construction staging and complete save
round-trip fixtures cover regressions. Results are retained in
[the evidence summary](concepts/dev_buttons_20261017/summary.json).

Restart Play to load the buttons. No Windows playtest was created or updated.
