# 279 — Nightly fires

From the owner (2026-10-28): review the campfire and hearth art, and make them require a
log. The owner pointed at Stonehearth, where the fire pit draws no wood: a log is placed
there at night and lit. Asked how the hearth should burn, the owner chose dusk to dawn,
like the campfire, even though dwarves who sleep by day can then sleep chilly.

On 2026-10-29 the owner liked the campfire but found the hearth still the old box with
its logs taken out, and asked what a rudimentary stone hearth for heating a room
overnight would look like. Of four concepts the owner chose B, the fire-back (below).

The rules now live in docs 34 (Nightly fires), 31, 62 and 64. This doc records the
review, the choices and what is still open.

## The review

Rendered with the fire gallery and the hearth-room test world (`tmp/fire_review_20261028/`,
`tmp/hearth_room/`):
- **Both fires bleached their own stone.** The stone colours match the rest of the game;
  the fire light at point-blank range washed the campfire ring and the hearth's firebox
  out to cream-white.
- **The drawn logs hardly showed**: thin crossed logs under the flame, and a small "+" of
  cut ends behind the hearth's flame.
- **The hearth's soot read as a hole**: a dark rectangle framed by stones above the lintel.

## What changed for the player

- **The fires hold no wood.** By day the campfire is a stone ring on grey ash and the hearth
  flagstones and a fire-back over a patch of ash: no flame, light, heat or crackle. Seated
  dwarves didn't turn to face them either, until the owner chose on 2026-10-29 that stools
  face a campfire by day too (doc 41, "Idle activity").
- **At dusk** (the sky's seasonal sunset) each cold fire posts a job. A worker brings the
  nearest log of any wood, oak included, sets it in the fire and the fire lights. The fire
  shows that log in its own wood.
- **At dawn** it goes out and the log is gone: one log per fire per night. A worker still on
  the way drops the log intact.
- **No log, no fire.** The panel's status line reads "Cold · lit at dusk", "No log to light
  it", "Waiting for a worker to light it", "A worker is bringing a log" or "Burning until
  dawn"; a burning hearth then names the room it heats.
- **Warm rooms (2026-10-29, doc 282):** a fire in a sealed room that is Comfortable without
  it stays unlit and reads "Unlit · the room is warm enough"; doc 34 has the rule.
- **The hearth is fed from in front of its fire**: its worker stands there when it can, any
  other side otherwise.
- **A cold fire still counts as its room's light**, so a bedroom lit by a hearth stays a
  bedroom by day; only the heat waits for the fire.

## Art

- **Campfire.** The proposal model stays verbatim in `proposal.mjs`; `write_data.py` drops
  its logs, char and embers, paints the ash grey (`stone_dark`) with a char centre, and puts
  soot on each stone's face toward the fire.
- **Hearth** (`tier1.mjs`): the fire-back, below. Its first pass (2026-10-28) only took the
  logs out of the old box and sooted its firebox.
- **The log in the fire** is the stockpile log's own model, scaled 0.75 in the ring and 0.7
  on the hearth's ash (`nightly_fire.log_position`, `log_scale`, `log_yaw_degrees`).
- **Menu pictures** of both show them burning a pine log (`FurnitureCatalogThumbnails.gd`
  places it from the same data).
- The campfire lost its `material_palette`: no wood is left to recolour. It keeps
  `material_group` for its product name and appeal.

## The hearth: four concepts and the fire-back

Drawn in real Hearthblock cells beside the old hearth and a dwarf, cold by day and lit at
night (`tmp/hearth_concepts_20261029/`: `concepts.mjs`, `build_concepts.py` and the renders):
- **A · Heat mound** (1.56 blocks): fieldstone courses stepping in to a capstone over a fire
  chamber, a lintel over the mouth; the stone mass gives the warmth back all night, but the
  fire and log only show through the mouth.
- **B · Fire-back** (1.81 blocks), **chosen**: an open fire on four flagstones against three
  stacked slabs that shield the wall and throw the heat back, with low wing stones.
- **C · Horseshoe kerb** (0.94 blocks): a knee-high U of flat dry-stone slabs with
  capstones, open to the room and the sky.
- **D · Smoke hood** (2.75 blocks): stacked jambs under a corbelled hood and a short flue;
  it would need a taller collision envelope, a contract change.

The fire-back as built: the flagstones are scorched (`stone_dark`) round the ash, which has
a char centre; soot is black by the fire and fades in steps up the fire-back. It keeps the
2 × 2 × 2 envelope, and its worker stands in front of the fire (`light_from: "front"`).
- **Flame:** the hearth's flame family (`voxel_fire_effects.json`) is taller and stands in
  front of the fire-back: anchor (0, 0.5, -0.125), height 0.95, inside y 0.5–1.4, so it
  burns well below the fire-back's top (1.81).
- **Log and light:** the log lies at (0, 0.25, -0.125), scaled 0.7; the light sits at
  (0, 1.05, 0.1).
- The menu picture was rendered again, and the recipe and placement texts now speak of a
  fire-back ("its fire-back to a wall").

## How it works

- **Data:** `nightly_fire` in `campfire.json` and `hearth.json`: `fuel_tag` (`timber`, any
  log), the log's position, scale and turn, and `light_from: "front"` for the hearth.
- **`FurnitureFires`** (owned by `FurniturePlacementController`) follows
  `WorldClock.is_night()` every frame and on `hour_changed`. It posts jobs at dusk, puts
  fires out at dawn, shows or hides the light, flame and log, counts heat through
  `RoomManager.set_fire_lit`, and gives the status line. The burning log is saved on the
  installed piece (`fire_log`, `fire_log_material`); jobs are posted again after a load.
- **`FireLightingComponent`** extends `FurnitureGhostComponent`: the placement fetch with
  any log as the item. `fetch_keys()` lets `FurnitureFetchPlanner` quote every log; it never
  redirects a storage haul; completion lights the fire.
- **`RoomManager`** counts a nightly fire's light at install, as a fixture, and its heat
  only while it burns. `FurnitureLighting.set_lit` switches light and flame;
  `FurnitureFireSound` skips cold fires (the stools' fire facing did too, until
  2026-10-29).

## Tests

- **`FireLightingTest`** (furniture area): cold by day; at dusk a job that waits for a log;
  a real worker carries a pine log and lights the fire; the log is used; flame, light, log
  and heat once; the panel rows; save and restore; dawn; a delivery cut off by dawn drops
  the log; a hearth's worker stands in front of its fire, and its log lies where the data
  says.
- **Updated:** `BedroomTest._put` lights the heating fixtures (hearth-room, bedroom-comfort
  and bed-ownership tests); `SaveManagerRoundTripTest`'s campfire burns a saved log;
  `CraftMaterialTest` no longer expects campfire wood.

## Open

- Not seen in the game under Hearthblock lighting yet: the owner's look is pending.
- Lighting is the set-down itself; there is no separate lighting action yet.
- Dark weather by day does not light the fires, as Stonehearth's does.
- Torches stay always lit.
- `FireLightingTest` could join the job gate.
