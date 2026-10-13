# 115 — Dwarf support recovery

Implemented 2026-10-11 after a playtest left two idle dwarves hovering above
an excavation and unable to start the development walk test.

## Cause and behavior

Dwarves use direct grid movement rather than physics gravity. The previous
floor check ran only after the actor's own mining commit and searched at most
four blocks downward. Other miners could remove an idle dwarf's floor without
updating its position. Pathfinding then started from an unsupported cell.

`DwarfAgent` now checks support before every unpaused tick, ahead of work,
leisure and sleep. An unsupported dwarf settles in the same XZ column onto the
first solid terrain block or completed bridge deck below, preserving facing.
The search spans the remaining world depth, stopping at physical support even
if water or headroom makes that floor non-walkable. Rungs, supported fractional
steps and the existing ladder fall handler retain their vertical movement.

After settling, ordinary interruption cleanup releases source/seat/tool claims,
clears obsolete routes and drops any cargo intact at the landing. Awake dwarves
return to the scheduler; sleeping dwarves retain their remaining rest. Own-floor
mining still settles immediately before selecting the next target. Slice
visibility updates when the dwarf reaches the lower floor.

No save schema changes. Current saves with hovering dwarves recover on the first
unpaused tick under this build. Restart the play session to load the code.
This change uses immediate settling; gravity animation and fall injuries remain
outside its scope. A genuinely isolated pit still needs a navigable exit.

## Raised floors and shallow excavations — 2026-10-12

Permanent-floor playtesting exposed two further cases. DEV Build correctly skips
the tile occupied by a dwarf, but flat-only leisure could leave that dwarf waiting
in the resulting shallow hole. When no flat stroll is available, idle dwarves now
try one adjacent step up using ordinary navigation and three-block clearance.
The inspector reports **Stepping up**. Work can interrupt this movement normally;
the local leisure radius and bedroom privacy still apply. Walls and deeper pits
without a walkable step remain obstacles. Retry DEV Build after the dwarf leaves
to complete the occupied tile.

If a terrain edit or saved position already leaves a dwarf's feet inside a solid
block, footing recovery also lifts them onto that block when the full standing
space above it is clear. It does not search through ceilings or walls. Valid
fractional step movement and ladders retain control of their height. Interruption
uses the same cargo, claim and sleeping-state cleanup as downward settling.
Current saves need no new fields; recovery runs after restarting Play and
unpausing.

Verified 2026-10-12: all 26 job/save gate fixtures plus DwarfRestTest,
BedroomTest, BedroomComfortTest, BedroomPrivacyTest and LogBridgeTest pass.
The new regression cases reproduced the failures before the fix. Evidence:
`tmp/floor_recovery_20261012/` (before, targeted, gate, rest_and_bridges).

## Verification

- `DwarfSupportTest`: real mining under two idle bystanders, both subsequently
  walking out; interruption of an actual hauler with exact goods and claims;
  saved hovering positions, pause, deep shafts, sleeping actors, slice visibility,
  failed-walk cleanup, normal steps, physical headroom obstruction, ladder and
  bridge support; raised-floor cargo recovery, embedded saved positions and
  ceiling rejection.
- `FloorConstructionTest`: an actual DEV Build leaves an occupied tile pending,
  the idle dwarf steps onto the completed flooring, and a retry fills the hole.
- MiningAnimationTest, NavigationRegressionTest, LadderMiningTest, LadderTest,
  HaulingAnimationTest, LooseItemSupportTest, LogBridgeTest and
  DwarfIdleBehaviorTest pass.
- SaveManagerRoundTripTest passes, including manual saves, autosaves and backup
  recovery. Its intentional corrupt-save cases emit expected recovery warnings.
- Godot editor diagnostics cover all 120 production scripts with no errors or
  warnings. Isolated fixtures still emit their pre-existing SkyController warning
  because they do not create an Environment resource.

Runtime ownership remains in DwarfAgent; no scheduler, mining protocol, item
ownership, navigation clearance or world geometry rules were relaxed.
