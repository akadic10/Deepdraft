# 48 — Object explorers and tree felling

Session milestone: 2026-10-04 — implemented and accepted in player testing.

Delivered: shared object explorers, click/rectangle tree-felling designation,
axe markers, species-specific 1×1 logs, automatic 24-unit produce crates, visible
axe/pick work animations, procedural work sounds with camera attenuation, and
tree/mining completion effects. The player approved the mining visuals and
confirmed the finished sound/effects pass works well. Scope and follow-ups are
recorded below; carpentry and the remaining forestry features are future work.

## 1. Object explorers — implemented

Left-click an existing tree, furniture plan, or installed furniture piece to open
one shared **Object explorer**. It uses `UIWindowManager` for movement, close,
focus and position persistence. It is a context window: selection is not restored
on loading a save. Empty ground, Escape, closing the window, hiding an object with
the slice tool, or removing an object clears selection. Ground clicks still reach
existing zone inspectors. Active designation/placement/room/walk-test tools own
their clicks; right mouse remains camera orbit.

Every tree uses these rows in exactly this order and position:

1. Growth stage: Sapling, Mature, Ancient.
2. Fruit: N/A, Too young, Out of season, or In season.
3. Fruit season: the authored harvest season, or N/A.
4. Felling yield: guaranteed drops for the current stage, or None.
5. Felling: standing, marked, approaching, chopping, or awaiting a reachable route;
   partial progress appears here as a percentage.

Possible drops and their chances appear below those rows. Apples have autumn
fruit; their saplings show Too young. Oak and pine have no seasonal fruit. Juniper
currently defines berries as possible felling drops, not a seasonal harvest, so
those appear under possible extras. These are descriptions of existing JSON rules;
growth timers and fruit gathering remain planned. Felling actions are implemented
in checkpoint 2.

Furniture shows status, required packed item or live storage information, and
retains cancel placement, uninstall/cancel uninstall, and the existing DEV actions.
The main scene uses the shared explorer. The old furniture window remains available
to standalone art/test fixtures that do not contain an explorer controller.

### Ownership and picking

- `ObjectExplorerController` owns the window, nearest-hit arbitration and selection
  outline. Providers own descriptions and actions. The same provider contract can
  support plants when live plant entities are introduced.
- `SurfaceFloraSpawner` and `FurniturePlacementController` are providers. No new
  registry or autoload is required; data still comes from its existing owner.
- Picking tests cached mesh triangles behind a bounds check. Visual canopy and
  sapling selection does not add physics or navigation collision. The nearest
  slice-visible terrain hit limits the ray so objects cannot be selected through
  rock. Providers reject slice-hidden visuals.
- Tree identities use their deterministic world X/Z anchor within the current
  world. Explorer metadata survives seasonal despawn/recreation; selected data
  refreshes while the replacement model is queued. No selection state is saved.
- Context data refreshes at 0.15 seconds while selected. Tree row controls are
  reused across selections, and optional information never removes a fixed row.

Validation: `scripts/tests/ObjectExplorerTest.gd` exercises all four species and
three stages, real visual picking, empty silhouette space, terrain occlusion,
slice and active-tool exclusion, UI input isolation, furniture actions and contents,
season replacement, and identical tree row positions. The save/load integration
test remains the full-scene regression check.

## 2. Felling jobs — implemented

**Raw-material decision (2026-10-04):** oak felling yields oak logs and possible
acorns, never oak staves. The intended crafting chain is oak logs → carpenter-made
oak staves → oak aging casks. Staves have been removed from mature and ancient
oak drop tables. Carpentry recipes belong to a later workshop milestone.

Use the existing axe dock menu: **Chop → Chop Trees**. Click a tree or drag a
rectangle over an area, then release to mark its trees. The rectangle snaps to the
ground grid, locks its projection to the starting floor plane, and includes visible
tree trunk centres inside its X/Z bounds across terrain heights. A live count shows
the selection; a drag shorter than six pixels remains a single-tree click. Reverse
drags work identically. Escape, switching tools, focus loss or release over a UI
window discards an unfinished rectangle; confirmed jobs stay queued.

Marked trees show **🪓 above their canopy** until cancelled or felled, including
after leaving Chop mode. These mouse-transparent CanvasLayer labels follow the
camera and hide with sliced/streamed-out trees. They rebuild from saved designation
state, not a second saved UI state. Repeated clicks/drags do not duplicate jobs.
The rectangle reprojects every frame after camera movement; its tree count stays
throttled to 0.08 seconds and is refreshed on release. The dock axe highlights only
while its menu is open. Once Chop Trees closes that menu, the hint indicates the
active tool until Escape, Cancel or switching tools.
The tree explorer offers **Fell tree**
and **Cancel felling** through the same flora-owned API. Other tools deactivate the
chop tool. Forestry Zone and Clear Stumps remain disabled future actions; this
checkpoint does not introduce forestry zones or persistent stump objects.

Each designated tree owns one `FELL_TREE` lease at priority 50. A dwarf finds a
walkable position along the trunk footprint, walks there, and accumulates work.
Blocked routes retry with scheduler backoff and alternative trunk sides. Sleep,
interruption and cancellation release the reservation without losing work. Felling
pauses with the clock; work seconds and the axe animation scale with clock speed.

Stage data under `felling.work_seconds` supplies the initial tuning (seconds at 1×):

| Species | Sapling | Mature | Ancient |
|---|---:|---:|---:|
| Pine | 2 | 6 | 12 |
| Oak | 2 | 10 | 20 |
| Apple | 2 | 8 | 16 |
| Juniper | 2 | 6 | 12 |

Completion removes the visual and trunk occupancy, then emits authored raw yields
through `ItemDropManager`. Saplings have no timber yield. Logs use the existing Wood
stockpile filter and hauling pipeline. Oak, pine, apple and juniper now have raw-log
models with bark and cut end grain; each fits one **1×1 tile**, even at an arbitrary
loose-drop yaw. Their native dimensions are 0.625×0.625×0.75 units, authored at eight
voxels/block with 0.125 baked export scale and linear vertex colors. The existing
item keys/model paths, carrying and stockpile rules are unchanged. Bonus drops use
the produce crates below. Regenerate timber with `tools/generate_timber_logs.py`; inspect
the imported items with `tools/TimberLogPreview.gd`.

`SurfaceFloraSpawner` owns saved changes keyed by the deterministic X/Z tree anchor:
namespaced species, stage, floor origin, partial work, designation and felled state.
The optional `flora` save section restores at priority 15, after mining and before
items/dwarves. A missing section leaves an older save's seeded forest untouched.
Leases and dwarf reservations are rebuilt, never serialized. Felled records suppress
seasonal/streaming respawns without replaying drops. Trunk occupancy stays registered
during seasonal visual replacement, including while a dwarf is working.

Validation: `TreeFellingTest.gd` covers the existing menu, click/reverse-rectangle
viewport input, preview/release, UI isolation, gesture cancellation, axe projection
and slice visibility,
actual scheduler/worker execution, cancellation, sleep/resume, paused work, seasonal
replacement, partial and felled JSON restores, one-time drops, hauling, saplings and
unreachable retries. `SaveManagerRoundTripTest.gd` includes active, cancelled and
felled flora records in the full manual/autosave/backup reload regression.

## 2.1. Produce crates — implemented 2026-10-04

All five formerly missing tree bonus drops (acorns, cones, apple/juniper seeds
and juniper berries) now appear in the same wooden crate. The system also covers
the other authored fruit, berries, seeds and cuttings: 15 types, each with low,
half and full presentation. Loose and stored goods share the crate. It holds up
to 24 of one type and occupies one cell/slot; logs keep their individual models.

Crates use 16 voxels per block with chunky frame boards and finer contents.
Fill levels represent 1–8, 9–16 and 17–24 goods; clicking a ground crate opens
the shared object explorer with its exact quantity, contents and storage status.
The crate is automatic packaging with no separate production or resource cost.

Hauling tops up partial crates first, including several dwarves delivering into
the same crate. Reservations include quantity; pickups split when only part of
a source crate fits. Cancelling, removing storage, withdrawing single units and
loading a save all conserve contents. Shelves render one crate per anchor;
container inventory and colony totals still count individual goods.

Validation: `ProduceCrateTest.gd`, `VerifyShelf.gd`, `TreeFellingTest.gd`,
`SaveManagerRoundTripTest.gd`, and `ProduceCratePreview.gd` (native model render
and bounds checks for all 45 variants). Preview: `tmp/produce_crate_review/crates.png`.

## 3. Dwarf felling animation — implemented 2026-10-04

Every dwarf is assumed to carry an axe and mining pick. No inventory, crafting,
equipment slot, delivery, or tool durability requirement is introduced.

Tree felling shows a wooden-handled iron axe held by both floating hands. Each
1.15-second cycle has a wind-up, fast strike, brief contact hold and recovery,
with a small body twist and staggered feet. The visual stance steps back where
needed to clear the large head/beard; navigation and collision stay unchanged.
No arms or legs are added.

`DwarfFellingPose.gd` owns this cosmetic pose. On beginning work, the tree source
queries its visible mesh once for the trunk contact point, with a footprint
fallback when no mesh is available. The blade reaches that point at impact.
Work progress and completion remain owned by the existing job; swing phases are
transient and are not saved. Pause freezes both work and pose, and clock speed
scales both. Movement, cancellation, sleep, completion and task changes hide the
axe and restore the original part positions, rotations and signed mirror scales.

`DwarfAssets` owns `assets/dwarves/tools/felling_axe.glb`. Regenerate it with
`tools/generate_dwarf_axe.py`: eight voxels/block, baked 0.125 scale and linear
vertex colors. It has its own material and does not inherit the hand's skin tint.
Mining pick art and animation are implemented in checkpoint 6.1 below.

Validation: `TreeFellingTest.gd` verifies both grips throughout a swing, blade
contact, slice visibility, pause/speed, and pose/tool cleanup on interruptions,
sleep, cancellation and completion, including preservation of mirrored parts.
`ProduceCrateTest.gd` and `SaveManagerRoundTripTest.gd` pass with the new animation.
`tools/DwarfFellingPreview.gd` renders native frames from a real assigned felling
job; `--side` selects the side view. Review animation:
`tmp/dwarf_felling_review/felling.gif`.

## 4. Gameplay acceptance — felling animation accepted 2026-10-04

The player reports the felling animation works really well. Automated integration
checks and the native animation preview also pass. Continue regression coverage
for reaching the tree, chopping, drops, hauling, cancellation, sleep/task
interruption, unreachable trees, season changes and save/load without duplicated
drops or returning trees.

After adding `ObjectExplorerController`, use **Project → Reload Current Project**
before playtesting in an editor that was already open.

## 5. Chopping sound and completion effects — implemented and accepted

Player request: procedurally generate axe chopping sounds and add a dust/"poof"
effect when a tree is felled. Build and review these for chopping first, then
apply the same approach to mining. Both implementations shipped and were accepted
in the 2026-10-04 session. Further sound tuning can build on the current baseline.

### 5.1. Sound sample review

`tools/generate_chopping_audio.py` generates six original 48 kHz mono PCM WAV
impacts and a heavier completion crack/rustle under `assets/audio/work/`. Seeded
noise and short inharmonic resonances layer the sharp wood crack, lower knock
and splinter tail. No external samples are used. The generator checks finite
samples and peak headroom; sample peaks are 0.70. The audible sampler is
`tmp/chopping_feedback_review/chopping_sampler.wav`, retained as a reference for
the weighty, stylized sound and any later tuning.

Audio is generated once, imported as project assets and reused in play. Immediate
variant repeats are avoided, with ±3.5% pitch and ±0.8 dB volume variation. One wood
family is shared by all tree species. Completion uses the heavier crack/rustle
without implying a long physical tree-toppling animation.

### 5.2. Chopping playback

`WorkFeedback` is a shared autoload owning short work audio and transient effects;
the broader ambient/combat AudioManager remains planned. It loads tuning from
`data/audio/work_feedback.json`. One impact event is synchronized with the transition into the axe's contact phase
(currently 0.54 of its 1.15-second cycle), not with a free-running audio loop or
the per-frame pose application. Handle wrapped/skipped phases without duplicate
hits or an audible backlog. Cancellation before contact produces no hit.

Positional playback uses horizontal distance from the smoothed RTS camera focus:
full proximity gain within 6 blocks, smooth fade to silence at 65 blocks, plus
zoom attenuation beyond 24 units. Camera altitude does not silence nearby work.
Live sound tails update when panning; native 3D audio supplies subtle stereo.
The eight-voice pool favors nearby impacts over distant tails and applies crowd
headroom. Work sounds share a runtime `Work` bus with volume/mute methods. Clock speed changes event cadence,
not sample pitch; pause produces no new impacts. Already-started short sound tails
may finish. Slice-hidden work is suppressed; reload clears transient playback.

### 5.3. Tree completion poof

Successful felling emits 28 tan/brown dust cubes and eight smaller bark/wood
flecks around the trunk base/lower trunk. They drift, shrink and fade over 0.72
simulation seconds, quickly revealing the logs/crates. Stage scales are 0.55 for
saplings, 1.0 for mature and 1.3 for ancient trees. Each `WorkDustBurst` uses one
MultiMesh draw, no shadows or collision; at most twelve bursts exist at once.
The native preview checks readability at gameplay framing.

The effect triggers exactly once from SurfaceFloraSpawner's committed completion
path, capturing position before model removal. General visual removal during
restore/streaming does not trigger it. The burst survives the tree node's deletion
and cleans itself up afterwards. `WorkFeedback` owns both chopping and mining
effects; instances are transient, have no collision or item identity, obey slicing
and pause/speed, and use separate cosmetic RNG. Drops and hauling are immediately
available. Small per-strike wood chips remain optional future polish.

### Validation and ongoing regression coverage

Passing checks: `WorkFeedbackTest.gd` (real worker events, phase wraps/long frames,
cancel, pause/speed, camera gain, variation, bounded voices/effects, slicing,
completion/loot, restore and scene cleanup); `TreeFellingTest.gd`; and
`SaveManagerRoundTripTest.gd` (full scene manual/autosave/backup restore).

`WorkAudioPlaybackTest.gd` runs with an audio device and records only the game's
Work bus. Actual stereo PCM confirms quieter pan-away/zoom-out output, correct
left/right balance, and eight simultaneous hits below clipping. No microphone is
used. Output captures: `tmp/work_audio_review/chop/`.

`tools/ChoppingFeedbackPreview.gd` renders the real final swing, committed tree
removal, dust and immediate logs. Preview: `tmp/chopping_feedback_review/poof.gif`.
When first adopting this milestone in an already-open editor, run **Project →
Reload Current Project** to register the added WorkFeedback autoload. Player
acceptance is complete; retain these checks for future changes:

- Listen to generated variants when changing their weight, brightness or volume.
- Confirm sound lands on visible axe contact, including low frame rate and 2×/3×
  speed, with no replay on cancel/resume, slice changes or load.
- Check near/far camera positions, zoom and several simultaneous workers for
  audibility, repetition and excessive combined volume.
- Confirm one completion burst, prompt cleanup, readable loot, no burst from
  seasonal replacement/streaming/restore, and unchanged work/yield/hauling rules.
- Cover saplings, mature and ancient trees; verify pause and slicing while the
  effect is active, then rerun relevant felling and save/load regressions.

## 6. Mining tool, sound and effects

### 6.1. Pickaxe and mining animation — implemented, visuals approved

`assets/dwarves/tools/mining_pickaxe.glb` has a long wooden haft, stepped iron
point and opposing chisel. Regenerate with `tools/generate_dwarf_pickaxe.py`:
eight voxels/block, baked 0.125 scale, linear vertex colors, lower-hand grip
origin. `DwarfAssets` owns its preload. Tools remain implicit equipment.

`DwarfMiningPose.gd` supplies two-handed recovery, wind-up and strike, adjusting
angle and grip height to the target. The tip reaches the near voxel face (top
face for underfoot work) across the existing five-up/one-down reach. The visual
stance clears the head/beard without changing logical footprint or reach.
Contact is phase 0.92, held through the existing end-of-swing work boundary.
Both rigs share attachment, material and mirrored-part restoration through
`DwarfWorkToolPose.gd`. Movement, cancel, sleep, completion, lost reservations
and task changes stow the active tool. Both tools are never visible together.

Mining now honors WorldClock pause/speed. Authored hardness, durability and
1× work time remain unchanged; fractional time carries through swing boundaries
at low FPS/high speed, capped at the current reserved block. Existing release
rules remain: partial block work resets, completed blocks remain mined.

Underfoot testing exposed stale navigation before the immediate floor snap.
Successful mining now refreshes the edited nav chunk and its lower clearance
neighbor before choosing the next floor/block. The controller still owns terrain
writes and drops; the dwarf now settles correctly after mining beneath itself.

Passing validation: `MiningAnimationTest.gd` (real jobs, every reach height,
cardinal headings, grips/contact, slicing, pause/speed, interrupt/sleep/cancel,
work timing, floor snap and tool swaps), `TreeFellingTest.gd`,
`WorkFeedbackTest.gd`, and `SaveManagerRoundTripTest.gd`.
`tools/DwarfMiningPreview.gd -- --case=wall|high|low|underfoot` renders 36-frame
pose studies from assigned jobs. Preview: `tmp/mining_animation_review/mining_poses.gif`.
Actual cycle duration is derived from the mined block.

### 6.2. Mining sound and dust — implemented and accepted 2026-10-04

The player confirmed the completed mining feedback works well after approving
the visible pickaxe and animation. This closes the chopping/mining feedback pass.

`tools/generate_mining_audio.py` synthesizes six stone strikes with short steel
resonances and gritty ticks, plus six quieter earth thuds/scrapes. Mono 48 kHz
PCM WAVs live in `assets/audio/work/`; no external recordings are used. Grass
and dirt share the soil bank; exposed rock, ores and gems share the stone bank.
The existing Work bus supplies camera-focus attenuation, zoom gain, subtle
stereo panning, variant/pitch variation and the shared eight-voice limit.

`DwarfAgent` detects phase-0.92 contact crossings and routes valid reservations
through `MiningZoneComponent` to the controller. Six small chips launch outward
from the struck face, lasting 0.28 simulation seconds. Long frames coalesce
crossed strikes into one feedback event and stop at the current block; contact
holds, pause, cancellation and revealing a hidden target never replay a hit.
The controller uses authored strata for concealed faces and actual block color
only when the facing neighbour was mined open, matching terrain rendering.
Missing strata uses the renderer's neutral rock07 fallback, never hidden ore.

Successful `execute_zone_block_mined` emits one small 0.48-second puff of sixteen
dust cubes and seven chips at the removed block, using its captured material.
Restore, DEV edits and generic terrain writes do not emit feedback. Actual drops
remain immediately available. Both effects use the existing `WorkDustBurst`
MultiMesh and shared twelve-burst cap, no collision or saved state, independent
cosmetic RNG, simulation-time pause/speed and scene-exit cleanup. Slice-hidden
or distant events are discarded without a replay queue. Mining duration,
hardness, yield, reach and save rules remain unchanged.

Passing validation: `MiningFeedbackTest.gd` (real jobs, contact/wrap/long frames,
pause/speed, slice/camera/cancel, stone/soil, resource concealment, authoritative
completion, shared caps and cleanup), `MiningAnimationTest.gd`,
`WorkFeedbackTest.gd`, `TreeFellingTest.gd`, and `SaveManagerRoundTripTest.gd`.
`WorkAudioPlaybackTest.gd -- --kind=mining_stone|mining_soil` verifies actual
stereo PCM attenuation and eight-strike headroom; captures are under
`tmp/work_audio_review/`. `tools/MiningFeedbackPreview.gd -- --family=stone|soil`
renders real final swings and block commits. Review outputs:
`tmp/mining_feedback_review/mining_feedback.gif` and `mining_sampler.wav`
(stone first, then soil). Restart the running game to hear the imported sounds;
no new autoload or global script class was added in this step.

## 7. Follow-ups outside the completed milestone

- Carpentry: implement oak logs → oak staves → oak aging casks, with recipes,
  quantities and work time defined in a later workshop milestone. Other timber
  species retain their distinct raw logs; their crafting uses remain to be designed.
- Forestry: growth/regrowth, seasonal fruit gathering, Forestry Zone, and Clear
  Stumps remain future features. The latter two dock actions stay disabled.
- Explorers: add live plant providers when those entities exist, preserving the
  shared window contract and consistent tree field layout.
- Audio/polish: a general audio settings UI and broader ambient/combat audio are
  future work. Per-strike wood chips are optional; mining already has contact chips.
