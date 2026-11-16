# 304 — Trade hats and the Miner's candle

**Status:** built 2026-11-12 from the owner's picks of the same day. The owner's look the same day: "Looks good". The seven decisions below were not answered one by one, so this doc stays until they are.

## What the owner asked

> When playing my game, we have the ability to promote a Dwarf to become a miner, ranger, etc...
> but it's hard to tell for me who's who from looking at the game only. I think Dwarves with jobs
> should get a hat that in some cases may need special features. The miner should get a hat with
> a candle on it which turns on when the surrounding is dark and he needs to mine but not turn on
> when he's trying to sleep for example. I don't think I want to craft the hat, it's just a visual
> basically

Two concepts were proposed on three sheets (`tmp/proposals_20261111/hats/`): **A**, a hat for
each trade, and **B**, one cap in five colours. The owner's answer:

> 1, A / 2 candle on top / 3 agree with your direction

So: concept A, the Miner's candle standing on the cap (not at the front of its rim), and the
candle burning through all of a Miner's waking hours in the dark, not only while mining.

## What was built

| | For the player | Where |
|---|---|---|
| Hats by trade | A dwarf with a trade wears its hat from the moment the trade is theirs, and loses it on going back to Worker. A Worker is bare-headed. | `hat` in `professions.json`; `DwarfBodyRig.wear_hat` |
| Miner | A hard ochre cap, one seam over the top, a tallow candle standing on it in a rope ring | `hats/hat_miner` in `dwarves.mjs` |
| Ranger | A moss cap swept back to a point, a pheasant's feather pinned flat along its top | `hats/hat_ranger` |
| Carpenter | A soft plum cap, broad and flat, slumped to one side, buttoned with a slice of branch | `hats/hat_carpenter` |
| Stonemason | A flat-topped cap of grey felt, square as a knocked stone, stone dust pale on its top | `hats/hat_stonemason` |
| Blacksmith | A rust kerchief tied tight, knotted behind with two tails, one corner scorched | `hats/hat_blacksmith` |
| Hair under a hat | Hair below the brow line stays, so plaits, buns and beards still say who the dwarf is | 14 cuts in `hair_hatted/`, made by `dwarves.py` |
| The candle | Lit in the dark, out in the light and in sleep; its light shows the Miner, the rock they work and whoever is near | `hat_light` in `professions.json`; `DwarfHatLight.gd` |
| Portraits | Every portrait shows the hat, with the candle unlit | `DwarfPortrait.gd` |

Hats are costume, not goods: nothing is crafted, stored, hauled or saved. The hat follows
`profession`, which the save already holds.

## The rules, and where they now live

- **The look and its limits** (the hat line at y 45, nothing more than three cells proud of the
  face, every hat's back at z -13, what rises above y 54): doc 64, "Art over rigs" → Dwarves;
  doc 41b, "Trade hats".
- **Who wears one, and the candle's rule:** doc 41, "Profession System".
- **The candle's light** (where it hangs, what shadows it, the slice): doc 24, "Underground
  Lighting Model".
- **The models and their checks:** doc 63, family contracts; `test_dwarves.py`,
  `DwarfHatTest.gd`.

## Decisions I took, for the owner to confirm

1. **A Worker wears nothing.** "Dwarves with jobs" was read as dwarves with a trade, so a bare
   head is a Worker.
2. **The Farmer's hat waits for farming.** No dwarf can be a Farmer yet, so no hat was drawn for
   one.
3. **A dwarf sleeps with its hat on,** candle out. The hat does not lift the lying head: the head
   rests as its hair does and the hat gives into the bed.
4. **Portraits show the hat.** The character sheet, the roster and the career map copy the dwarf
   as it is, so they show it too; the candle is drawn unlit there.
5. **"Dark" is daylight, torches and fires.** The candle is out where daylight reaches (the sky
   that reaches the dwarf, times how far the day has come) and where a lit torch, campfire or
   hearth is in sight within 60% of its own reach. Another Miner's candle does not count, or two
   Miners would put each other's out.
6. **It burns on the walk to bed** and goes out as the dwarf settles down.
7. **The candle's light is small:** 8 blocks of reach against a torch's 20. Rock and built log
   walls shadow it; dwarves, goods and furniture do not, so a Miner never darkens their own
   ground. A closed door therefore lets it through.

## Found on the way: the pale shapes in dark tunnels

In a dark tunnel three blocks high under the slice, every dwarf showed a pale shape on its head.
`DwarfReadability` draws a faint outline of a dwarf behind nearby rock; it counted rock the slice
had cut away, so the dwarf's own hair, reaching into the hidden ceiling, was painted with the
outline of the head beneath it. Rock above the cut is no longer cover. `DwarfHatTest` holds it.

## Checked

- `build.py dwarves --check`: all 83 models regenerate byte for byte; the 64 that existed are
  unchanged.
- `tools/voxel_assets` unit tests, 67 of 67. `test_hats_sit_on_every_head` puts every hat on all
  4 heads, 8 brows, 7 beards and 14 hairstyles: it covers the head from the hat line up, leaves
  the face clear, and shares no face with what it sits on. Above the hat line only a bun shows.
- `DwarfHatTest` (new): hats by trade, nothing added to the save, a Miner read from a save, the
  candle's rule both ways (day, night, a torch in sight, a torch behind a wall, an unlit torch, on
  the way to bed, asleep, underground at noon), the light's place at a wall and under the slice,
  portraits, the lying head, and sliced-away cover.
- The gate, 55 of 55, and lint; the dwarves, art, sky, furniture, ui, saves, mining, rooms and
  construction areas, 140 of 140.
- A copy of the owner's colony with the game's own code (`tmp/proposals_20261111/hats/built/`):
  the three saved trades wear their hats on load, the line-up matches the proposal, the candle is
  out at noon and by torch and lit in a dark tunnel, and the pale shapes are gone.
- Cost: six lit candles in that tunnel added about 0.55 ms of CPU to a frame and no GPU time
  outside the noise (two runs; a first run measured 2.4 ms and is taken for warm-up).

Not checked: a dwarf at a table or on a ladder with a hat on, the game at 30 dwarves with many
Miners, and the look in the owner's own play.

## Left for later

In `00_todo.md`, "Trade hats left for later": the Farmer's hat, doors and the candle, and hats on
the career map.
