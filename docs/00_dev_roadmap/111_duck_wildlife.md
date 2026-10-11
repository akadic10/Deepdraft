# 111 — Ducks, swimming and short flights

Implemented 2026-10-10 after approval of ducks for rivers/lakes and occasional
flight. They spend most of their time paddling, foraging, preening and resting.

## Live behavior

- Three seeded flocks of 2–4 ducks favor calm water beside grass/dirt shores.
  The first habitat search favors the river; lakes and tarns also qualify.
  Waterfall approaches, cave water, solid terrain and placed obstacles are excluded.
- Ducks follow the actual finite water level, climb reachable banks, keep loose
  flock spacing, and flee nearby dwarves and wolves. Their presence does not
  extract water, irrigate soil or consume plants/crops.
- Close danger, drained/unsafe water and occasional relocation trigger short
  flights. Tired ducks can land on a nearby bank. Flight paths sweep the body
  and wingspan against live terrain, placement occupancy and full tree canopies.
  Wings stay tucked in narrow launch/landing sections. A newly blocked path
  stops before contact and is replanned; no teleporting through cliffs or trees.
- Both sexes use original eight-voxel/block art: green-headed male, mottled
  brown female, broad bills, feet, separate head and articulated wings. Swimming
  has restrained bobbing, small square wakes and a brief landing splash.
- Three original procedural quacks and three splashes use the existing Work
  bus, distance/zoom attenuation, mute/volume and pause handling. Selection can
  sound while paused; ambient sounds are occasional and simulation-aware.
- Scheduled aerial opportunities bring 2–5 ducks every 4–7 days, subject to
  seasonal chance, safe habitat, local hunting pressure and the 16-duck cap.
  They enter at a map edge, fly inland and settle; kills never accelerate events.
- Shared object picking, inspector, Locate and Follow support all movement
  modes. Slicing hides ducks and wakes together. Full-world view includes birds
  flying above the highest terrain layer.

## Ownership and saves

`WildlifeManager` owns `duck.json`, model loading, actors and saved duck records.
`DuckAgent` reuses common wildlife identity/needs and supplies amphibious/air
motion. `DuckNavigation` reads live water and terrain; `DuckPopulation` handles
seeded habitats and aerial entry plans. `SurfaceFloraSpawner.flight_obstacles`
queries existing nearby tree bounds without changing ground occupancy.

Saved data includes flock/sex, water/land/air mode, position, step origin/progress,
flight waypoints/cursor, takeoff and relocation timers, needs, pose, quack timer
and exact RNG state as decimal text. Pending arrival members remain in the
existing event owner. Structural validation rejects malformed duck states and
arrival routes before restoration. Cosmetic wake/splash particles are rebuilt.
Older development saves without the duck section are not migrated, per policy.

Wolf diets remain rabbits/deer; duck hunting, eggs, breeding, domestication and
seasonal migration departures are separate future work.

## Verification

- `DuckWildlifeTest.gd`: finite-water height, swimming, shore access, foraging,
  rest, danger takeoff, landing, drainage escape, canopy and new-block clearance,
  pause/speed, picking/slicing, strict save fields and JSON future equivalence.
- `DuckPopulationTest.gd`: seeds 42, 1234, 1675083273 and 20261010 produce three
  repeatable safe flocks, with continuous edge-to-water aerial arrivals.
- `SaveManagerRoundTripTest.gd`: complete colony saves, autosaves, both backup
  recovery paths, mid-flight ducks and a partially entered duck flock. The
  validator also rejects 156 malformed complete snapshots.
- Existing rabbit/deer/wolf behavior, rabbit audio, rabbit arrivals and herd
  arrival regressions pass.
- `RabbitAudioPlaybackTest.gd -- --duck`: actual Work-bus PCM verifies quacks,
  splashes, paused selection, stereo panning, distant/overview silence and paused
  ambient tails. No microphone input. Peak output remains below 0.13.
- `tools/DuckLivePreview.gd`: native full-world art, loaded forest clearance,
  public locator/inspector/Follow, a completed flight and two simulated minutes
  of ordinary wildlife. Review captures and logs: `tmp/duck_review/`.

## Playtest

Start a fresh development world and use **Menu → Development → DEV: Next duck**.
Keep the camera close to hear occasional quacks. Use Follow to watch a duck
paddle, visit shore or fly; approaching with a dwarf startles it. **DEV: Next
duck arrival** finds members of later flocks once they have entered.
