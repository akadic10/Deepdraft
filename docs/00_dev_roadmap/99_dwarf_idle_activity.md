# 99 — Dwarf idle activity

Implemented 2026-10-09 after the player reported dwarves remaining at their exact
work positions when jobs finished. Previously there was only a breathing pose;
no autonomous leisure movement or chair use existed.

## Player-visible behavior

- A newly idle dwarf waits 2.5–5 simulation seconds, then chooses a local activity.
- Short flat-ground walks stay within nine blocks of the last work/spawn position.
  Stops avoid stockpiles, planned furniture, installed furniture edges, ladder
  approaches and other dwarves' current/planned stops. Straight routes must have
  full ordinary dwarf clearance. Leisure does not climb ladders or roam farther
  away to find a destination.
- Between activities they pause for 8–18 seconds and look around. Attempts and
  timings are staggered with a per-dwarf RNG independent of world generation.
- When a nearby suitable wooden chair is free, they may walk to an authored
  access tile and sit for 18–35 seconds. Standalone and dining-table chairs work.
  Old narrow chairs and benches without a defined rest pose are not used.
- A chair is reserved by at most one dwarf, including while approaching it.
- On round log stools, dwarves rest their hands in front and prefer facing the
  nearest campfire within six blocks on the same level. The chosen seated pose
  must fit, and terrain must not hide the fire. The body keeps a stable quarter-turn
  facing for the visit; the head gently aims toward off-axis flames. A stool's
  placed rotation is unchanged. Backed wooden chairs retain their placed facing.
- Work interrupts leisure immediately. Dwarves remain in the scheduler's idle
  pool throughout, preserving task priorities and nearby-worker comparisons.
- The inspector/roster show Looking around, Strolling nearby, Going to sit,
  Sitting or Getting up. These activities count as idle availability, not work
  or sleep. Pause freezes them; game speed scales their timers and movement.

This is ambient leisure, with no new hunger, morale, comfort or sleep benefit.
Eating, social conversations, bed use, communal benches and tavern gatherings
remain separate work.

## Ownership and lifecycle

`DwarfIdleBehavior.gd` is a per-agent RefCounted component, without a new global
class or autoload. TaskManager remains the owner of `task_config.json`; its
`idle` section supplies all timing, radius, spacing and attempt settings.

Leisure uses short validated flat segments, not global A* calls. Wander attempts
are capped; chair discovery considers one installed piece per frame. An enclosed
dwarf waits rather than teleporting or repeatedly searching the whole map.
Movement rechecks its straight route and stopping location during travel.

`InstalledFurnitureComponent.idle_seat_owner` is a transient exclusive claim.
Its `idle_seat_yaw_steps` reserves the occupant's actual facing, used by shared
clearance checks for both seating and subsequent furniture placement. Both fields
clear on every release path and are never serialized. Round stools opt in with
`seating_chair.face_nearby_fire`; campfires identify themselves with
`seating_focus: "fire"`. TaskManager's `idle.seat_focus_radius` supplies the range.
Missing, distant, hidden or uninstalling fires leave the valid placed facing as
the fallback. Removing the focus during rest stops the head turn without rotating
the sitter or cancelling a still-valid seat.

`seating_chair.rest_pose` in the existing wooden-chair definition supplies visual
offsets. Body and feet follow the approved seating study; hands rest by the
chair arms. Entering/leaving normally blends the visual offsets over 0.5 seconds.
The logical actor stays on the proven access floor while its visual parts move
into the chair. This keeps path assignment and saved positions out of solid
furniture; interruption immediately resets the pose at that access position.

Work assignment, external walk commands, abort, sleep, restore and node teardown
cancel leisure and release seats. Chair uninstall/removal, lost support, blocked
access or newly obstructed seated clearance also end the activity. The head-room
check refreshes after navigation changes and uses FurnitureSeating's placement
rules, excluding the seat itself. Its detailed furniture geometry permits
stools immediately beside a campfire while preserving terrain and head clearance
(see [100 — Camp furniture](100_profession_crafting_camp.md)).

Leisure state, routes, RNG and seat claims are deliberately not saved. Existing
agent position/needs and furniture persistence remain the only saved owners.
Loaded dwarves begin available on their saved walkable access floor.

## Verification

`DwarfIdleBehaviorTest` runs a real crafting completion into a stroll, then a
new craft order that interrupts it. It covers local bounds, available-pool
membership, activity labels, pause/speed, free-chair use, competing dwarves,
work/sleep interruption, uninstall/removal, runtime restore, table-compatible
seating, normal stand-up, enclosed-ground fallback and explicit walk commands.

Native renders check all four chair rotations, using the existing dwarf meshes.
CampfireStoolTest additionally checks four independently facing stool occupants,
blocked/hidden/distant/removed fires, an off-axis head target, backed-chair facing,
claim cleanup and body-part clearance around the flames. Native views cover the
resting hands with long beards and side braids; rounded beard clearance protects
the head turn. Evidence: `tmp/stool_rest_review/` and the campfire stool captures.
Related passing regressions cover starter tools, crafting selection, hauling
selection, surface work, inspector/roster, ladder navigation/mining, dining
placement and full save/load/backup restoration. The surface selection fixture's
fixed eight-wake assertion timed out under concurrent world generation; its
unchanged suite passed when run alone. Evidence: `tmp/idle_review/`.

Restart play mode to load the changes. No new save fields are required.
