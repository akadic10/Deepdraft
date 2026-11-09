# 298 — Dwarf animation pass

From the owner (2026-11-03): "Can we perform an animation review on all the animations Dwarves
have and give them a score so we can see which ones need improvement?", then "Can we create this
in a markdown file and start the updates".

**Status (2026-11-06):** every step in the plan is built. The owner has started looking in play. That
look found a step pose fault, fixed the same day (changelog 2026-11-06, `DwarfStepFeetTest`). Later that
day, from the owner: "So far the animations look good, I'll let you know if I spot something unusual."

## Where to resume

**Next:** the owner's look in play, then re-score against the table below if wanted.

**Waiting on the owner's look in play:**

- Confirmed so far: the hammer swing, no glide when felling a tree, and on 2026-11-06 eating, blinking
  and climbing a ladder ("looked better").
- Not yet confirmed: arrival at mining, boulders, building (especially on a raised floor) and bench
  work; the step back, including its speed; a sitter called away, where the feet now step while the
  body rises.
- The rest of the 2026-11-05 work in steps 4 and 5. Only sampled frames from staged clips have been
  checked, not motion or real jobs.

**Watch for:** a dwarf standing idle for no reason near a build. Off-centre positions caused this
twice during arrival work, as navigation's 0.3 margin and the support check both fail a job silently.

**Tools:**

- `tools/DwarfPillarBuildPreview.gd` records a real pillar job, with `--leave`, `--mine` or `--approach`.
- `DwarfWorkArrivalTest`, `DwarfBuildArrivalTest`, `DwarfBenchArrivalTest` and `DwarfPoseBlendTest` hold
  the measurements. They are not in the gate, so run them by name with the gate after rig changes.
- Scores and flipbooks from the review are in `tmp/anim_review_20261103/index.html`. They predate this
  pass, so re-score before relying on them.

---

## How the review was done

34 motions, played on the real rig and pose code, with frames from three cameras and measurements
of every part (`tmp/anim_review_20261103/index.html` has the flipbooks).

- **Scores are judgement,** from sampled frames and measurements, not from watching in motion. The
  owner's eye overrides them.
- **Weighting:** reading at game zoom 25%, motion 25%, blending in and out 20%, body use 15%,
  contact 15%.
- **Stages were arranged:** the capture script placed the dwarf, furniture and contact points, so
  a pose can differ a little against real terrain.
- **Fix priority** is (10 − score) × how often the player sees it (1 to 5).

## Scores before this pass

Average 5.7 of 10.

| Score | Motion | Seen | Priority | Main issue | Step |
|---:|---|:--:|---:|---|:--:|
| 3.2 | Build hammer, chest-height block | 4 | 27.2 | Hammer stays inside the head and chest | 3 |
| 5.2 | Idle | 5 | 24.0 | Moves under 1 pixel at the default zoom | 4 |
| 4.2 | Eating, standing | 4 | 23.2 | Only one hand moves | 4 |
| 4.7 | Step up one block | 4 | 21.2 | Slides up a ramp; a foot clips the corner | 4 |
| 3.6 | Building or removing a ladder, packing a water stone | 3 | 19.2 | Hands inside the chest | 2 |
| 6.2 | Walk carrying | 5 | 19.0 | Stiff; a log and four stones ride alike | 4 |
| 3.8 | Ladder climb | 3 | 18.6 | Hands inside the head for 79% of the climb | 2 |
| 5.5 | Carpenter at the bench | 4 | 18.0 | Reused felling swing | 5 |
| 5.5 | Eating at a table | 4 | 18.0 | Head stays still | 4 |
| 4.1 | Taking food | 3 | 17.7 | Hands inside the chest, not aimed at the food | 2 |
| 6.8 | Mining, chest height | 5 | 16.0 | Opens on the strike pose; pick passes the hair | 1, 4 |
| 4.8 | Build hammer, low block | 3 | 15.6 | Passes through the face | 3 |
| 5.2 | Mason and Blacksmith at the bench | 3 | 14.4 | Reused felling swing; smith looks like a mason | 5 |
| 6.5 | Felling | 4 | 14.0 | 2.3-block hand snap on starting | 1 |
| 6.5 | Gather from a shrub | 4 | 14.0 | Looping dip, no picking motion | 4 |
| 5.5 | Fishing: cast | 3 | 13.5 | Left hand teleports 1.7 blocks | 2 |
| 3.4 | Ladder with load | 2 | 13.2 | As the climb; the load floats behind | 2 |
| 3.5 | Grilling a fish | 2 | 13.0 | Stick inside the body on the carry; hard cuts | 1, 2 |
| 6.8 | Gather from the ground | 4 | 12.8 | Nervous 1-second loop | 4 |
| 6.0 | Mining, overhead | 3 | 12.0 | Hands pass through the head | 4 |
| 6.1 | Sit | 3 | 11.7 | Straight slide through the air | 4 |
| 6.1 | Fishing: wait | 3 | 11.7 | 25 s of total stillness | 4 |
| 7.7 | Walk | 5 | 11.5 | Foot snap on start and stop | 1 |
| 7.7 | Put down, plant | 5 | 11.5 | Fine | |
| 7.2 | Add to a load | 4 | 11.2 | Fine | |
| 6.4 | Fishing: bite and land | 3 | 10.8 | Snaps back to the cast | 1 |
| 7.4 | Sleep in bed | 4 | 10.4 | Getting in passes through the frame | |
| 6.7 | Mining, low and underfoot | 3 | 9.9 | Needs blending only | 1 |
| 8.1 | Pick up | 5 | 9.5 | Best clip in the game | |
| 7.2 | Sleep on the ground | 3 | 8.4 | Tilts over in mid-air | |
| 1.9 | Ladder drop | 1 | 8.1 | No animation; rare | |
| 6.1 | Board game | 2 | 7.8 | Repeats exactly every 2 s | |
| 6.2 | Hanging fish on the rack | 2 | 7.6 | Hands carry nothing up | |
| 6.8 | Sleep sitting | 2 | 6.4 | Fine | |

**Correction to the first report:** it called the ladder row "Furniture install/remove". That clip
is really for building or removing a ladder and packing a water stone. Placing furniture uses the
put-down clip.

## Plan

### Step 1 — Blend between clips (built)

Hands jumped up to 2.5 blocks in one frame whenever work started or stopped.

- `DwarfBodyRig` crossfades over 0.18 s of game time whenever a clip changes. Any
  `reset_part_offsets` starts one, and so do the grill's pose changes and a new catch.
- It blends each part about its own centre, so a fist travels straight instead of swinging around
  the dwarf's feet.
- Each frame's clip still writes its true pose. `begin_frame` restores it before the next clip
  runs, because some clips write only part of a pose and a blended value would otherwise stick.
- A block's first mining swing opens on the ready pose instead of the strike, and still lands
  when the work reaches contact.
- Presentation only: nothing is saved, and job timing is unchanged.

### Step 2 — Clipping and teleport bugs (built)

- **Ladder:** hands climb beside the head, where every camera sees them. Hands and feet move half
  a block per half cycle, so they stay planted for the climb. The body sways a little, and a load
  sits against the back.
- **Grill:** the carried stick stands beside the head instead of inside the dwarf.
- **Ladder work and water stones:** hands work at arm's length in front of the chest.
- **Taking food:** hands reach toward the food, and never into the dwarf's own chest.
- **Fishing cast:** the free hand travels to the rod over the swing.

Measured largest one-frame step, in blocks:

| Clip | Before | After |
|---|---:|---:|
| Felling | 2.30 | 0.33 |
| Mining, chest height | 1.85 | 0.39 |
| Build hammer, chest height | 1.77 | 0.26 |
| Fishing: cast | 1.71 | 0.15 |
| Grilling | 1.64 | 0.23 |
| Ladder climb | 1.35 | 0.24 |
| Eating, standing | 1.07 | 0.15 |
| Walk | 0.53 | 0.10 |

Hands inside the head on the ladder went from 79% of frames to 0%.

`DwarfPoseBlendTest` covers these.

### Step 3 — Rework the build hammer (built)

The hammer's strike timing and job timing are unchanged: contact stays at 0.72 of a 1 s cycle.

- **One hand, on the right.** The strike point moves 0.3 block to the dwarf's right along the face,
  and the handle leans in from the fist, which keeps the fist beside the body.
- **Raised beside the head,** with a short pause at the top, then an accelerating strike. The hammer
  rests on the block briefly and bounces off.
- **The free hand steadies the block** beside the strike, and takes a little of each blow.
- **Effort lands on the strike.** Body twist and lean now peak at contact, not mid-cycle (`effort`
  was `sin(phase*PI)`).
- **Stance.** The dwarf stands 0.2 block further back from the face, feet staggered. Feet stay
  planted across all heights, as `ConstructionContinuityTest` requires. On high blocks the head
  looks up about the neck.
- **Standing back from a wall (owner's report: "after construction the dwarf moved forward into the
  stone structure").** The head reaches 0.75 ahead of the actor and a wall starts 0.5 ahead, so a
  dwarf at rest facing a wall had its head and beard in it. An idle dwarf now stands 0.3 back when a
  block is at head height ahead and there is room behind. It is drawn only: the actor stays on its
  cell centre. It covers any idle dwarf at a wall, not only builders. Heads still overlap walls at
  the sides, and in a tunnel with no room behind.
- **Keeping the hammering spot (owner: "no, it is still wrong", then a test scene of a real pillar).**
  The stand-back above only stopped the body short of the wall: it still slid forward 0.44 block
  with no step when the hammer stopped. A builder now stays drawn on its hammering spot until it
  next walks. `tools/DwarfPillarBuildPreview.gd` runs a real builder on a real order for a 1x1
  pillar, three blocks tall, and records it through to walking off.
- **Walking off (owner: "completed 2/3 blocks and then moved half a block in before walking off").**
  The hammering spot is only drawn back, so the first step pulled the body 0.58 block forward to the
  cell centre. `DwarfBodyRig.leave_work_spot` now moves the actor to the drawn spot as the walk
  starts, with no change on screen: 0.00 block toward the pillar in the scene with `--leave`. The
  actor enters the cell behind only if it is walkable; otherwise it stops at its own cell's edge and
  the rest eases away. This moves the real position, but only at the start of a walk.

Box check of the hammer inside the dwarf, share of frames:

| Block | Head before | Head after | Body before | Body after |
|---|---:|---:|---:|---:|
| Chest height | 80% | 33% | 75% | 30% |
| Low | 53% | 13% | 32% | 5% |

The check uses whole-part boxes, so it overstates clipping. The frames show the hammer beside the
head on the raise, with no sign of the earlier hammer under the chin.

### Finish pass (built)

From the owner: "please observe the movement when a dwarf finishes a task, I don't want these
movements that look bad". A temporary logger in `DwarfBodyRig` recorded every dwarf's drawn parts on
every frame across the whole test suite, 98,000 rows of real jobs, ranked by how far the body moved
without walking.

- **Any tool work now ends where the dwarf stood.** The builder's rule covers mining, felling,
  boulders and bench work. The dwarf stays drawn back until it next walks, and the walk starts from
  there (`DwarfBodyRig._work_spot`, `leave_work_spot`).
- **Reaching from that spot.** Putting down and gathering keep the body, head and feet there
  (`DwarfCarryPose.work_spot`), where they used to pull it forward.
- **Long moves take longer.** The crossfade grows with the body's distance, from 0.18 s up to 0.6 s,
  so a dwarf called out of a chair rises instead of snapping a block in 0.18 s.

Peak speed of the drawn body when leaving work, blocks per second, with walking at 3.4:

| Finish | Before | After |
|---|---:|---:|
| Mining, then to the next stand | 9.3 | 0.0 |
| Building, then walking | 5.9 | 0.3 |
| Felling, then standing | 5.2 | 1.4 |
| Mining, then standing | 4.6 | 1.0 |

The rows are from tests, whose dwarves sometimes get moved by the test itself, so rows where the actor
jumped were left out. `tools/DwarfPillarBuildPreview.gd --mine` renders a real miner through its
finish. Felling, boulders and bench work are measured but were not rendered through their finish.

**Not changed, for the owner to judge:**

- **Starting work from the spot.** See "Arrival" below for what is fixed. A dwarf already standing on
  its stand cell has no walk to shorten, and still glides back, now over about 0.45 s.
- **Waking and rising.** See step 4 for the getting-up motion.

### Arrival (built)

From the owner: "the dwarf approaches the tree, then slides back before he starts chopping it". On
the real felling job the drawn body retreated 0.75 block from the trunk, from all four sides.

- **The walk ends where the swing stands.** `DwarfMovement.stop_short_of` aims the last stretch at the
  drawn spot, for felling, boulders and mining. `DwarfBodyRig.arrive_at` then moves the actor to the
  cell centre, already facing the work, with no change on screen, and the crossfade turns the body.
  The job still starts on its cell centre, so every stand check is unchanged.
- **Owner's look (2026-11-03):** felling confirmed in play: "he did not glide". Mining, boulders,
  building and bench arrival are not yet confirmed.
- **Measured:** retreat 0.75 to 0.00 block from all four sides, and the body never moves faster than
  a walk (`DwarfWorkArrivalTest`).
- **Building and bench work (owner: "yes, fix building and bench work next").** The builder's slide
  back went from 0.68 to 0.00 block and the crafter's to 0.06 (`DwarfBuildArrivalTest`,
  `DwarfBenchArrivalTest`). A crafter arrives with goods in hand: the load is held from the same spot
  (`DwarfCarryPose.work_spot`), it turns to its work over the last block of the walk, and it sets the
  goods down from there, so neither the goods nor the body jump as the walk ends.
- **Rules that came out of the gate:**
  - The last stretch must be level. A spot behind a step up hangs over the lower floor, the support
    check drops the dwarf, and the job fails over and over (`ConstructionStagingTest` caught it).
  - `leave_work_spot` moves the actor only if a clear line leads back to its cell centre. Navigation
    keeps a 0.3 side margin, so an actor pressed against a block cannot start any walk.
- **Not covered:**
  - Gathering, fishing and a bench's hand work have no swing to stand back for.
  - A dwarf arriving by a step up or a ladder keeps the glide.
  - Starting a walk with a load swings the goods quickly through a sharp turn, up to 0.56 block in
    one frame, because they ride 1.6 ahead of the actor. It predates this pass and is unchanged.

### Step back (built)

From the owner: "start the step back". Where a body still has to move with no walk, it now steps:
any crossfade that moves the body 0.2 block or more while the dwarf is not walking. The left foot
takes the first half and the right the second, each planted while the other is up, and the body rises
a little with each step (`DwarfBodyRig._stepped`). It is drawn only: timing, pathfinding and the
actor's position are unchanged.

- **Measured on a real felling job, already on the stand:** the body moves back 0.81 block in both
  cases. Feet sliding on the ground went from 1.67 to 0.04 block, and the feet now lift 0.18
  (`DwarfWorkArrivalTest`).
- **Also covers,** by the same rule, though not measured: arriving by a step or ladder, a wall stand-back,
  and a sitter called away or a sleeper woken with no walk yet.
- **Not covered:** a body gap left over as a walk starts (a tight spot) stays a glide under the walk's
  own feet.

### Step 4 — Liven up what is seen most

**Built 2026-11-05:**

- **Idle (`DwarfIdleGesture`).** Breathing rises from 0.018 to 0.04 block. Each 7 s slot may hold a weight
  shift, a look around, a head or beard scratch or a stretch, chosen from the time and the dwarf alone,
  so nothing is saved and a squad never moves together. A blink every 4.3 s shows the sleep eyelids
  for 0.13 s. Hands carrying goods keep to the load.
- **Eating.** The head dips into each bite and chews as the hand comes down, standing, seated and at the
  fire. The free hand rises a little with each bite.
- **Step up and down (`DwarfStepPose`).** The actor still moves in a straight line, so path timing is
  unchanged. Feet are drawn planted on real floors: rising, a foot lifts before it crosses the edge;
  descending, it crosses before it drops. Each step leads with the other foot, and carried goods follow
  the body. Footsteps sound as each foot lands.
- **Ladder hands (owner: "farther out than the ladder itself").** The head is 2 blocks wide and the rails
  are 0.56 apart, and the actor stands in the ladder's own cell, so hands on the rails were inside the
  head. The body now climbs 0.55 behind the rails (0.15 with a wall behind), and the hands reach over the
  head onto the rails, never above the ladder's top. Near the top they hold it as the body rises.
- **Mining pace (owner: yes to slowing it).** `execution.visible_swing_s` is 0.9. Hardness alone sets a
  block's dig time, as before, and swings divide it evenly: rock (hardness 3) goes from 3 swings of 0.5 s
  to 2 of 0.75 s. Practice and Strength still shorten a swing. Replacing a block digs on the same pace.

**Built 2026-11-05, second batch:**

- **Carrying.** The load rocks against the stride and eases out over a few frames when the walk stops, so
  stopping never jerks it. A heavy item, or a growing handful, leans the dwarf back and deepens the bounce
  (`DwarfCarryPose.heft_of`).
- **Load swing.** A laden dwarf turns at up to 6 radians a second (`DwarfMovement.LADEN_TURN`), with goods
  1.6 blocks ahead. For a moment after a sharp turn it walks a little sideways. The last block of an
  arrival is exempt, as it has its own turn.
- **Sitting and getting up.** The feet step to the seat, then the body lowers leaning into it; getting up
  is the reverse. `seat_transition_s` goes from 0.5 to 0.9 s. A dwarf called away, or leaving a meal, leans
  into the crossfade when it rises (`DwarfBodyRig._lean_up`).
- **Knees.** Stool, chair and bench hands move from 0.81 to 0.44 ahead, so they stop short of the toes.
  Table seats keep their hands on the table.
- **Lying down and waking.** The body lowers first and tips once it is low; waking sits up, then rises. Into
  a bed it arcs over the frame. There is still no separate motion for rolling out of bed.
- **Gathering.** One hand at a time reaches out over 1.7 s while the other waits at the belt
  (`gather_loop`), for bushes, foraging and harvests. A single reach such as taking food is unchanged.
- **Fishing wait.** Breathing, a slow shift and glances, eased out before the cast and the bite.
- **Mining raise.** The fists arc out and forward around the head.

Share of a swing with a fist inside the head's box, which overstates clipping:

| Block height | Before | After |
|---:|---:|---:|
| 1.4 | 14% | 2% |
| 2.2 | 26% | 14% |
| 3.0 | 31% | 12% |
| 3.6 | 20% | 0% |
| 4.15 | 18% | 0% |

The rest is the strike itself at face height, and a wider arc barely reduced it.

### Step 5 — Crafters' own motions (built 2026-11-05)

`DwarfFellingPose.apply_bench`, with `craft_motion` in `professions.json`. Each keeps the swing's 1.15 s
cycle and contact point, so job time and sound timing are unchanged.

- **Carpenter (`adze`):** a short two-handed stroke in front of the chest.
- **Stonemason (`tap`):** a small one-handed tap, with the free hand on the stone.
- **Blacksmith (`blow`):** the hammer rises high beside the head, pauses and comes down hard, with the free
  hand on the work.
- **Worker:** keeps the axe swing at the workbench.

## Open questions for the owner

- **`durability` in `block_resources.json`.** Nothing reads it now that hardness sets the swings. Remove
  it, or keep it for a later use? **Answered 2026-11-09:** removed (the project review's batch 4).

## Not covered

- Lighting the bedtime fire was not captured.
- Dwarves snap to face their work with no turning motion, and that is not scored.
- Removing furniture has no pose of its own, as `UNINSTALL_WORKING` only poses sources with
  `advance_removal`.
- Hurt, talking, drinking and cheering animations do not exist yet.
