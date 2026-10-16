# Deepdraft — Agent Navigation Index

**Performance work paused (2026-10-15) — current direction:**
Camera panning and slicing feel substantially better, and several major hitches
have been reduced. Pause proactive performance targets and retain the existing
measurements as the baseline. The latest duck change reduces CPU work without
establishing a reliable overall FPS gain; do not automatically continue through
the older performance follow-up lists below.

Next focus: gameplay and usability, beginning with a fresh construction workflow
discussion in [193](docs/00_dev_roadmap/193_arrival_preparation_performance.md).
The intended direction is to deliver all project materials to a drop box, then
hammer for a duration that may scale with block count. Discuss batch deliveries
to address one-stone trips; carrying capacity, multiple builders, completion
timing and cancellation/material recovery remain open design questions.

Keep routine performance awareness during ordinary play. Revisit profiling for
a repeatable hitch or clear regression. The longer normal-speed 30-dwarf soak
through saves, arrivals and seasons remains a later checkpoint; ordinary duck
flight-planning spikes remain recorded for later investigation. Water appearance
and performance, and review findings in 177, stay parked. The intended population
target remains 30 dwarves. The current Windows build and evidence are linked in
[197](docs/00_dev_roadmap/197_duck_update_performance.md).

**Duck updates optimized (2026-10-15) — retained baseline:**
[197 — Duck update performance](docs/00_dev_roadmap/197_duck_update_performance.md)
retains raw-solid/placed-obstacle body clearance through AnimalNavigation's
bounded, edit-invalidated cache. Normal-speed 30-dwarf profiling with 11 ducks
reduces total duck CPU 17–18% and total wildlife CPU about 8%. Whole-frame
controls are mixed; no reliable overall FPS or worst-frame improvement is claimed.
Ordinary flight planning can still spike to ~17 ms. Duck movement, reactions,
feeding, animation and offscreen updates keep their existing cadence; live water
and canopy checks retain their observation rules. All 1,200 differential updates,
1,017 new clearance assertions, 12 fixtures and 26 final native packaged checks
pass. The package check compares at existing JSON save precision; its initial
over-strict assertion and tiny numeric differences are documented in 197.
Windows build/ZIP refreshed and actual EXE startup passes; restart Play or launch
the release linked in 197. Only two existing runtime files changed; the original
save and all water code remain unchanged. Further performance work is paused
as recorded above; the longer normal-speed 30-dwarf soak is a later checkpoint.
Construction workflow design is the next discussion, before revisiting its
waiting/eligibility implementation. Water appearance/performance and findings
in 177 remain parked. No fog of war or population cap is introduced.

**Shared atmosphere shipped (2026-10-15) — resume here:**
[196 — Shared atmosphere performance](docs/00_dev_roadmap/196_shared_atmosphere_performance.md)
replaces fog/sky broadcasts to ~1,300 materials with one scene-owned 320-byte
texture update at the existing maximum 20 Hz. Two normal-speed 30-dwarf controls
reduce first-pan means 20.08–21.36→16.16–16.40 ms and later pans
16.44–17.20→13.04–14.16 ms. First-pan render setup drops ~88%; GPU stays near
3 ms. Repeating the old path confirms a 20.20 ms first pan. P95 remains above
the 60 FPS budget, so further spikes remain. Eight old/new shader image pairs
are pixel-identical. All ten final fixtures, 3,494 native packaged save/reload
checks and release startup pass. Texture ownership stays local to each scene;
day/night, weather, camera overrides, room darkness and save schema are preserved.
Windows build/ZIP refreshed; restart Play or launch the release linked in 196.
Water work is deferred to a later session (user direction, 2026-10-15): the
player is unhappy with its current appearance. Revisit the visual direction
alongside water performance; do not treat today's appearance as an approved target.
The proposed water-focused 30-dwarf profile is parked too. A longer general
normal-speed soak through autosaves, arrivals and seasons remains a follow-up.
Construction/eligibility stays parked for the drop-box and timed-building design
discussion in 193; findings in 177 remain parked. No fog of war or population cap
is introduced. Original save and unrelated existing scripts are unchanged.

**Normal-speed rendering profiled (2026-10-15) — resume here:**
[195 — Normal speed rendering profile](docs/00_dev_roadmap/195_normal_speed_rendering_profile.md)
uses copied 30-dwarf settlements at x1 calendar speed. First-pan controls average
20–21 ms/frame; later pans 16–17 ms, with P95 still 31–38 ms. GPU averages about
3 ms; reducing resolution to 720p barely changes whole-frame time. The broad
renderer timer includes water and lighting; its own callback is about 0.2 ms
after mining settles. Shared fog/sky broadcasts to ~1,300 materials are the next
rendering target: direct calls peak at 6.7 ms and cause extra render setup.
A controlled, deliberately stale-fog diagnostic lowers mean frames 18.60→15.98 ms
and render setup 1.15→0.18 ms. This is evidence for sharing live atmosphere data,
not a shipped optimization or promised gain. Actor-light checks cost ~0.6 ms;
cavity-shell rebuilds reach 9.6 ms during mining. Six native runs pass; all 337
production GDScripts and the player save are unchanged after instrumentation.
The release from 194 remains current. Next: shared scene-owned fog/sky data,
then the longer soak. Construction/eligibility and findings in 177 stay parked.

**Gradual overnight season changes (2026-10-15) — resume here:**
[194 — Gradual season transition](docs/00_dev_roadmap/194_gradual_season_transition.md)
spreads tree/ground-plant art and existing terrain recolours from midnight to
sunrise. Tree bodies stay alive; logical season/crop rules still turn at midnight.
Queues share a soft 2 ms art/admission budget; terrain uses normal worker batches
and existing upload budgets. Pause/speed follow the calendar; paused loads rebuild
target art within frame budgets. No save schema change or new global class.
At 5/20/30 dwarves, clock peaks fall from 19–20 to 6–7 ms; all 2,925 trees stay
present, versus a baseline dip to 14. The 30-dwarf maximum falls 114→82 ms.
Accelerated-night mean frame times are 3–9% higher: this is a smoother transition,
not an average-FPS improvement. All 14 fixtures and native packaged mid-night
save/load, final art and slice checks pass; Windows build/ZIP refreshed.
Restart Play or launch the new release. Next: profile steady CPU within the
30-dwarf target, then a longer soak. Construction stays deferred for the later
drop-box/material-staging and timed-building discussion in 193. Findings in 177
stay parked; no fog of war or population-cap change is introduced.

**Wildlife arrival hitch reduced (2026-10-15) — resume here:**
[193 — Arrival preparation performance](docs/00_dev_roadmap/193_arrival_preparation_performance.md)
identifies duck habitat/flight planning as the main stall. It now resumes across
main-thread frames under a shared soft 2 ms preparation budget. Peak event CPU
falls from 254–260 to 13–14 ms at 5/20/30 dwarves; whole-frame peaks fall from
297–322 to 71–88 ms. Average timings are mixed; this is a hitch improvement.
The same animals enter, with ducks about 3–4.4 seconds later. Attempts, safety
checks and save format remain intact. Pending searches restart from saved seeds.
All 12 fixtures, 45 exact planner comparisons, packaged pending-save recovery
and release startup pass. Windows build/ZIP refreshed; restart Play or launch it.
Construction waiting/access and repeated eligibility probes from 191 are deferred
for a fresh design discussion later (user direction, 2026-10-15; see 193): stage
all project materials in a drop box, then hammer for a duration possibly scaled
by block count. Discuss batch deliveries to address one-stone trips before
optimizing the current workflow. No construction implementation is authorized
by this handoff. Seasonal hitches and a longer soak remain performance follow-ups.
The known baseline dwarf teardown error is retained in 193's evidence; final
runs are clean. Findings in 177 stay parked, and no fog of war or population-cap
change is introduced.

**Autosave freeze reduced (2026-10-15):**
[192 — Autosave performance](docs/00_dev_roadmap/192_autosave_performance.md)
moves formatting, JSON, validated file transactions and private-data cleanup to
one worker. Capture stays on the main thread; requests fall from 0.77–1.41 s
to 14.7–17.6 ms. Consecutive 30-dwarf peak frames fall from 1,415 to 80 ms.
The transaction still takes about 1–2 s; ordinary frame variability remains.
Eight fixtures, shutdown joining, native packaged saves/backup recovery and
release startup pass. Windows build/ZIP refreshed; restart Play or launch it.
Save request booleans now mean accepted; completion signals mean committed.
Busy saves/loads reject overlapping requests. Snapshot capture is observational.
Next: wildlife arrival route preparation (up to 348 ms in 191), followed by
construction waits and post-season drift. Use 5/20/30 dwarves. Findings in 177
stay parked; no fog of war or population-cap change is introduced.

**First work effect hitch reduced; event review complete (2026-10-15):**
[191 — Event hitch review](docs/00_dev_roadmap/191_event_hitch_review.md)
traces the remaining first-mining stall to dust rendering pipeline preparation.
Shared dust resources and one hidden loading instance remove that compilation
from the first live impact. Standard 30-dwarf first-pan peaks fall from 215.05
to 59.64 ms; later pan timings are essentially unchanged. Ten fixtures, three
native effect checks, packaged copied-save checks and release startup pass.
Windows build/ZIP refreshed; restart Play or launch the new release.
Copied 5/20/30-dwarf event runs identify **autosave as the next priority**:
natural autosave frames reach 1.43–1.54 seconds. Then profile arrival route
preparation (up to 348 ms in WorldEventDirector), construction waits and the
modest post-season frame-time drift. The few-minute runs are not a leak proof
or an hours-long soak. Baseline shutdown errors from 190 recur after sampling
and remain documented; the final run exits cleanly. Findings in 177 stay parked.

**Lighting cleanup hitch reduced (2026-10-15):**
[190 — Lighting buffer disposal](docs/00_dev_roadmap/190_lighting_buffer_disposal_performance.md)
identifies the large hitch as clearing the previous calculation's CPU buffers.
One worker now disposes of those private buffers while published lighting stays
available. Native 30-dwarf lighting peaks fall from 231.49 to 5.78 ms; a separate
168.18 ms frame stall remains. The five-dwarf copied settlement runs essentially
unchanged. Eight exact lighting comparisons, all 13 fixtures, native packaged-save
checks and release startup pass. Windows build/ZIP refreshed; restart Play or
launch the new release. Cleanup still consumes CPU and teardown joins it.
Next: [189's](docs/00_dev_roadmap/189_session_handoff_2026_10_14.md) long-session/event
review at 5/20/30 dwarves, tracking completed work and waits alongside frame times.
The diagnostic run's dwarf shutdown errors are recorded in 190 for later review.
Findings in 177 remain parked; no fog of war or population cap is introduced.

**Colony size direction (2026-10-14):** The intended maximum is **30 dwarves**.
Use 5/20/30 dwarves for routine performance reviews, with a busy mature
30-dwarf settlement as the main target. The 50/100-dwarf results in 187 are
optional stress evidence, not shipping requirements. Prioritize camera/slice
smoothness, reliable job progress, accumulated items/rooms and long-session
events within the intended population. Thirty dwarves are now measured in
[188](docs/00_dev_roadmap/188_job_scheduling_performance.md). This records design direction; runtime population
enforcement is not part of the performance changes.

**30-dwarf job preparation improved (2026-10-14):**
[188 — Job scheduling performance](docs/00_dev_roadmap/188_job_scheduling_performance.md)
shares hauling eligibility work across workers and retains prepared construction
stands between route-search slices, with fresh validation before assignment.
Controlled hauling-query CPU falls 88%. Two native 30-dwarf runs build 10–12
blocks and store 12–38 items, versus 1/0 before; the final 20-dwarf run also
progresses in all three jobs. Later 30-dwarf frame times are 11–21% higher as
the world does more work; this is not an FPS win or a complete waiting fix.
All 34 fixtures, native packaged-save checks and release startup pass.
Windows build/ZIP refreshed; restart Play or launch the new release.
Next: long-session/event hitches, including an identified 250 ms lighting
update. Findings in 177 remain parked; no population cap is implemented.

**Colony scaling measured; construction scans reduced (2026-10-14):**
[187 — Colony scaling performance](docs/00_dev_roadmap/187_colony_scaling_performance.md)
adds a reproducible 5/20/50/100-dwarf mining/building/hauling yard. A synchronous
construction call now shares obstacle checks across candidate blocks; controlled
query CPU falls 89%, with 35 exact comparisons. Yard mean frame time falls
35–38% at 5 dwarves and 11–17% at 20; 50/100-dwarf tail performance is mixed.
Heavy-colony hauling still stalls, and dwarf updates/renderer CPU dominate at
100. This is not a complete scaling fix. Twelve fixtures, native PCK copied-save
checks and release startup pass. Windows build/ZIP refreshed; restart Play or
launch the new release. Opportunity 3 is long-session/event hitches; the report
also records remaining scheduling, dwarf-update and actor-lighting targets.
Findings in 177 remain parked.

**Duck navigation work reduced (2026-10-14):**
[186 — Duck query performance](docs/00_dev_roadmap/186_duck_query_performance.md)
reuses water and clearance queries within one synchronous wildlife update,
then discards them. Saved-game duck CPU falls 19–20%, total wildlife CPU 13%,
and active-pan mean frame time 10–11%; frame P95 falls 6–9%. Isolated stalls
remain. All 1,200 differential updates and 882 navigation comparisons match;
11 fixtures, native packaged-save checks and release startup pass. Offscreen
activity, flight/animation, water and saves retain their behavior. Windows
build/ZIP refreshed; restart Play or launch the new release. Larger-colony
scaling and long-session/event hitches remain opportunities 2 and 3. Findings
in 177 remain parked.

**Room rebuild hitches reduced (2026-10-14):**
[185 — Room rebuild performance](docs/00_dev_roadmap/185_room_rebuild_performance.md)
spreads detection and room metadata across frames with a soft 1.5 ms budget.
Saved-game repeated-rebuild peaks fall from 35–42 ms to 1.8–2.1 ms; active-pan
whole-frame maxima fall from 59/64 to 43/47 ms. Average FPS is mixed: total
detector CPU increases 35–43%, and complete room metadata arrives later.
15 exact scheduling scenarios, 36 controlled comparisons, 12 fixtures, native
lighting/inspector checks, copied-save export checks and release startup pass.
Door lighting boundaries remain immediate; saves and water/wildlife are unchanged.
Windows build/ZIP refreshed. Restart Play or launch the new release. Findings in
177 remain parked; later natural pans still have non-room camera spikes.

**Water flow loop improved (2026-10-14):**
[184 — Water flow loop performance](docs/00_dev_roadmap/184_water_flow_loop_performance.md)
reuses transfer quantities and receiving ceilings, and avoids temporary reach
arrays. Matched uninterrupted camera runs show 15–22% cheaper water updates
and 8–12% lower whole-frame P95. Controlled full-world water CPU falls 21%.
All 3,200 differential ticks match the prior solver; 16 final-source fixtures,
12,000 stability ticks, native views, packaged-save checks and release startup
pass. Simulation cadence, water behavior and saves remain unchanged. Windows
build/ZIP are refreshed; restart Play or launch the new release. Isolated stalls
remain, including a 37 ms room rebuild. Findings in 177 stay parked.

**Water current-animation spikes reduced (2026-10-14):**
[183 — Water current animation performance](docs/00_dev_roadmap/183_water_current_performance.md)
captures compact current inputs and processes them across frames with a soft
1 ms budget. Saved-game current-update peaks fall from 13–14 ms to about 2.3 ms;
first/later pan P99 falls from 35.3/34.5 to 26.5/25.5 ms. Average frame times
change little; the benefit is shorter stalls. Nine fixtures, 103 scheduling
checks, native water views, packaged conservation/slicing and release startup
pass. Simulation, geometry and saves remain unchanged. Windows build and ZIP
are refreshed; restart Play or launch the new release. Findings in 177 stay parked.

**Periodic damp-ground hitch removed (2026-10-14):**
[182 — Moisture rendering performance](docs/00_dev_roadmap/182_moisture_rendering_performance.md)
replaces whole-mesh moisture rebuilds with 16×16 tiles, incremental notifications
and a soft 1 ms frame budget. Worst measured moisture update falls from about
37 ms to 1.4 ms. Both fresh/saved pan samples have zero frames above 50 ms;
saved-pan P95 improves from 35.3/31.6 to 24.5/21.9 ms. Fresh averages are slightly
slower: this trades some steady CPU work for shorter stalls. Nine fixtures and
12 exact geometry comparisons pass. Slice/discovery concealment remains immediate;
simulation and saves are unchanged. Findings in 177 remain parked.
Native visuals, packaged-save conservation/slicing and release startup pass;
Windows build and ZIP are refreshed. Restart Play or launch the new release.

**Water simulation performance improved (2026-10-14):**
[181 — Water simulation performance](docs/00_dev_roadmap/181_water_simulation_performance.md)
reuses unchanged space ceilings/reach geometry and avoids redundant neighbor
wakes. Native fresh-world average water-update cost falls by about one third;
first/later pan P95 improves from 26.5/33.7 to 21.0/25.8 ms. The original and final
solvers match across 1,400 differential ticks; all 13 regression fixtures pass.
Water behavior, simulation schedule, saves and offscreen activity are unchanged.
Saved-pan first/later P95 improves from 41.8/39.7 to 35.3/31.6 ms. Native water
views, packed-save conservation/slicing and release startup pass; Windows build
and ZIP are refreshed. Restart Play or launch the new release. Renderer spikes
remain a profiling target; this is not steady 60 FPS. Findings in 177 remain parked.

**Wildlife navigation performance improved (2026-10-14):**
[180 — Wildlife navigation performance](docs/00_dev_roadmap/180_wildlife_navigation_performance.md)
reuses terrain, clearance and support checks with immediate edit/occupancy/water
invalidation and bounded storage. Wildlife still simulates every frame offscreen.
Saved-pan mean improves from 29.3 to 16.5 ms; P95 from 59.0 to 41.8 ms. Later
fresh-world wildlife P95 falls from 29.4 to 5.9 ms. Ten fixtures, 392 navigation
comparisons and native packaged-save checks pass. Windows build/ZIP refreshed;
restart Play or launch the new release. Water simulation/presentation remain the
next CPU targets; this is not steady 60 FPS. Findings in 177 remain parked.

**Water mesh rebuild performance improved (2026-10-14):**
[179 — Water mesh rebuild performance](docs/00_dev_roadmap/179_water_mesh_rebuild_performance.md)
moves geometry construction to snapshot-only workers, coalesces dirty requests,
prioritizes nearby water and budgets main-thread preparation/uploads. Final saved
pan P95 improves from 82.6 to 59.0 ms; fresh-world initial pan from 65.6 to 30.8 ms.
Seven relevant fixtures, 36 exact geometry comparisons and native water views
pass. The refreshed Windows ZIP passes packaged save/slice and native release
startup checks. Simulation, visual detail and saves are unchanged; further CPU
work is needed for steady 60 FPS. Earlier findings in 177 remain parked.

**Performance baseline measured (2026-10-14):**
[178 — Performance baseline and camera stutter](docs/00_dev_roadmap/178_performance_baseline_and_camera_stutter.md)
records three native runs, reproducible profiling tools, and the measured water
and wildlife CPU costs behind camera stalls. Production behavior is unchanged;
optimization priorities and validation targets are proposed there. The unrelated
review findings in [177](docs/00_dev_roadmap/177_project_review_deferred_2026_10_14.md)
remain parked at the user's request.

**Temporary build exclusion corrected (2026-10-13):**
The root `.gitignore` now excludes all new `tmp/` output, including extracted
playtest executables. Earlier rules covered only selected logs/profiles and let
a 104 MiB test EXE appear in GitHub Desktop's commit list. Keep durable review
evidence under `docs/00_dev_roadmap/concepts/`; do not force-add scratch builds.
Existing tracked review files and local test/build files are preserved.

**Session closed (2026-10-13) — resume here:**
[176 — Session handoff](docs/00_dev_roadmap/176_session_handoff_2026_10_13.md)
records the completed art, scale, sky/audio/weather and friends-playtest work,
the latest mining/limb fixes, validation boundaries and current Windows build.
Balanced dwarves and Large wolf are approved and live. Latest fixes have native
verification; player review after restart remains pending. Grass caps, cave/crop
art and broader performance work remain deferred or future work. No new feature
is assigned by this documentation-only closeout.

**Mismatched dwarf limb lighting fixed (2026-10-13):**
[175 — Dwarf limb lighting](docs/00_dev_roadmap/175_dwarf_limb_lighting.md)
fixes the dark blue/grey right hand and boot caused by rendering reflected
double-sided meshes. Cached reflected geometry preserves the existing signed
rig transforms and work anchors while presenting positive transforms to the
renderer. All four skin tones match across hands/boots in daylight and torchlight;
six art/gameplay fixtures and a copied-save Ulvrek review pass. Restart Play or
use the refreshed Windows release and ZIP. Existing appearance saves are unchanged.

**Mining resumes after furniture moves (2026-10-13):**
[174 — Mining furniture access](docs/00_dev_roadmap/174_mining_furniture_access.md)
fixes cached zero-face mining zones after a bed or other obstruction moves.
Nearby occupancy changes refresh work positions and re-arm pending leases;
rapid changes coalesce without losing removals. Seven fixtures pass. A native
copy of the player's save completes the real bed Move and both remaining wall
blocks. Existing saves need no migration or redesignation. The Windows ZIP
and a new isolated release directory include the fix.

**Ledge pickup and Windows export lifetime fixed (2026-10-13):**
[173 — Ledge pickup and safe exports](docs/00_dev_roadmap/173_ledge_pickup_and_safe_exports.md)
lets dwarves collect reachable drops two blocks above the adjacent floor, with
live obstruction checks and unchanged navigation clearance. Ten gameplay/UI
fixtures pass. All three door widths and all 41 packed furniture models load;
the missing door preview came from overwriting a running game's PCK. Exports
now use unique `build/windows/releases/` folders. Close the old game and launch
the freshly exported EXE, or extract the refreshed playtest ZIP into a new folder.
Existing saves work without migration.

**Rudimentary bridge corrected (2026-10-13):**
[172 — Rudimentary log bridge](docs/00_dev_roadmap/172_rudimentary_log_bridge.md)
replaces pale flat boards with four bark-covered trunks on rough cross logs across
all five spans. The catalogue icon is refreshed; bank anchors, walking surface,
palettes, placement and saves remain intact. Four fixtures and native comparisons
pass; all other 376 GLBs are unchanged. The Windows playtest ZIP is refreshed.
Restart Play or relaunch the exported game to see the new bridge.

**Windows friends playtest prepared (2026-10-13):**
[171 — Windows playtest](docs/00_dev_roadmap/171_windows_playtest.md) fixes all ten
main-scene GDScript warnings without disabling diagnostics. Seven affected
regression fixtures pass, including full save/load and backup recovery. The
Windows x86-64 release includes all 102 runtime JSON definitions and excludes
development files. Share `build/windows/Deepdraft-Windows-Playtest.zip`; keep
its EXE and PCK together. Native DirectX 12 startup/world generation passes.
Rebuild using `tools/windows_playtest/Export.ps1`. Player data stays separate.

**Environmental sound details and rain/storm weather added (2026-10-13):**
[170 — Environment sound details](docs/00_dev_roadmap/170_environment_sound_details.md)
completes daytime insects, individual chirps, dry leaves, winter wind, tree
creaks, shoreline laps, warm-night frogs, discovered wet-cave drips and actual
wolf howls. Rain/Storm are scheduled and saved weather types with roof-clipped
rain, muted roof patter, thunder and sky-dial symbols. Cosmetic precipitation
does not add simulated water. Audio follows fractional water surfaces as well
as terrain. Eleven regression fixtures, all 12 new sound families in the native
mixer, and five generated-world reviews pass. Restart Play; existing saves and
audio preferences work. Final listening balance is ready for player review.

**Room sound perspective fixed (2026-10-13):**
[169 — Room audio perspective](docs/00_dev_roadmap/169_room_audio_perspective.md)
anchors listening to the terrain at screen centre, using the visible slice and live
mined cells. An elevated orbit pivot had silenced bedroom torches and weakened
nearby snoring. One cached ray supplies all sound owners. Focused camera/audio
fixtures and native playback from a copied player save pass. Restart Play and
load normally; the original save and audio preferences remain unchanged.

**Environmental ambience added (2026-10-13):**
[168 — Environmental ambience](docs/00_dev_roadmap/168_environment_ambience.md)
adds wind, nearby foliage, daytime birds, warm-night insects and sparse owls.
Seasonal sunrise, weather, physical shelter and overview zoom shape the mix.
Menu → Audio controls Ambience and Effects independently; preferences survive
scene changes. Native mixer/UI checks, existing fire/water/menu tests, full
save/load regression and generated-world day/night captures pass. Reload the
current project once for the new AmbientAudio autoload, then restart Play.
Existing saves work; listening balance is ready for player review.

**Sky save-load lifetime fixed (2026-10-13):**
[167 — Sky scene lifetime](docs/00_dev_roadmap/167_sky_scene_lifetime.md)
fixes sun/moon global-transform errors during the gap in scene reload. The sky
autoload clears scene references on Environment exit and resumes on rebind.
The exact reproducer, sky state checks and full dock-driven save round trip pass.
A native copy of the player's latest quicksave restores five dwarves and 19
furniture pieces; original saves remain byte-identical. Restart Play and load
normally. No migration, new world or art change is required.

**Full-sphere diorama sky implemented (2026-10-13):**
[166 — Diorama sky](docs/00_dev_roadmap/166_diorama_sky.md) replaces grey clear
nights with a blue atmosphere, stable stars and a crescent moon. The backdrop
continues below the horizon; day/dawn/dusk and weather drive color, clouds and
haze. Roof-aware fog shares the sky gradient and enclosed rooms remain dark.
Existing celestial light curves, terrain, actors, streaming and saves stay intact.
Six fixtures pass, including 85 native sky checks; 18 final production captures
and before/after evidence are recorded. Restart Play for player review.

**Balanced dwarves and Large wolves integrated (2026-10-13):**
[165 — Approved actor proportions](docs/00_dev_roadmap/165_approved_actor_proportions.md)
ships the player's selection from 164. Dwarf resting span is 2.16 blocks with
fixed height; torso/head width factors .8/.93 come from registry-owned proportions.
Work, rest, portraits and interruption resets retain the new shape. Wolves are
2.392 high and 3.411 long, with four-wide/three-high navigation clearance;
two-cell flat strides preserve speed, and longer terrace strides adjust duration.
All 17 affected fixtures, 364 native viewer checks, a full 24-dwarf settlement
and pre-change settlement restoration pass. All 381 GLBs stay byte-identical;
pines, other animals and the world grid keep their sizes. Restart Play; tested
current-format saves load without migration. Standard 63 records the live rig factors.

**Dwarf and wolf proportion trials ready (2026-10-13):**
[164 — Dwarf and wolf proportion trials](docs/00_dev_roadmap/164_dwarf_wolf_proportion_trials.md)
adds Current/Balanced/Lean dwarves and Current/Balanced/Large wolves beside the
local Stonehearth reference. Launch `Launch Proportion Study.cmd` for two dwarf
appearances, live poses, multiple angles and settlement comparisons. Dwarf/pine
heights stay fixed; dwarf resting spans are 2.60/2.16/2.00 blocks and wolf heights
are 1.84/2.116/2.392. All 363 study checks and headless import pass; 63 captures
are recorded. Balanced is the moderate recommendation for each family, awaiting
player selection. Both taller wolves exceed current navigation clearance and
need gameplay review before integration. Production art, code and saves stay current.

**Stonehearth scale comparison ready (2026-10-13):**
[163 — Stonehearth scale comparison](docs/00_dev_roadmap/163_stonehearth_scale_comparison.md)
measures the supplied `P:/stonehearth` QB models using resolved render scales
and displays them beside current Deepdraft art. Launch `Launch Stonehearth Comparison.cmd`.
Dwarf/hearthling heights are 3.32/3.30; our resting hand span is 37% wider.
Mature/ancient pine heights already match 20/27 blocks. Wolf proportions differ
substantially; 75% trees in 162 are a concept trial, not a Stonehearth correction.
Four parser fixtures and 78 native checks pass; 39 source files stay unchanged.
The height-matching toggle affects only study instances. Production stays current.

**Visual scale study ready (2026-10-13):**
[162 — Visual scale review](docs/00_dev_roadmap/162_visual_scale_review.md)
adds an isolated native lineup, furnished room comparison, camera/tree trials
and the earlier settlement concept. Double-click `Launch Scale Study.cmd`.
Dwarves measure 3.32 blocks high, with a 2.6-block resting hand span. Review
character width, compact room layouts and smaller settlement trees before
changing global actor height. All 80 study checks pass. These are candidates
awaiting player review; production art, scales, gameplay and saves are unchanged.

**Save-menu reload fixed (2026-10-13):**
[161 — Save menu scene teardown](docs/00_dev_roadmap/161_save_menu_scene_teardown.md)
fixes the null viewport error when loading from the dock. Persistence commands
close the menu before emitting signals, and queued layout callbacks ignore
detached docks. Three fixtures pass, including real menu-driven scene reloads.
A copy of the player's pre-fire quicksave restores five dwarves and 14 furniture
pieces with current art; all four original save files remain byte-identical.
Restart Play and load normally; no save migration is needed.

**Fire effects converted (2026-10-13):**
[160 — Faceted fire](docs/00_dev_roadmap/160_faceted_fire.md) replaces retained
voxel flames on campfires, both torches, hearths, braziers and smelters. All six
static forms and 42 frames across five clips use tapered flame tongues and
warm color gradients. Flames are self-lit from every view; world light, heat,
audio, timing and gameplay definitions remain unchanged. Bodies retain exact
geometry/colors; 370 other models are untouched. Nine affected fixtures and
native day/night/frame reviews pass. Use `tools/generate_fire_faceted.py` and
`data/art/fire_effects.json`; the unused voxel mesh dump is removed and backed
up outside the project. Thumbnails are refreshed. Restart Play; saves work.

**Crude workbench corrected (2026-10-13):**
[159 — Crude workbench stump](docs/00_dev_roadmap/159_crude_workbench_stump.md)
replaces the overbuilt plank table with the intended rough bark-covered stump.
The cut top matches the existing `.875` crafting height. Its model and catalogue
thumbnail are updated; the other 380 models and all gameplay definitions remain
unchanged. Five affected fixtures, four wood variants and all-sided worker
crafting pass. Exact follow-up art fingerprints are in `data/art/asset_revisions.json`.
Restart Play to refresh cached models and thumbnails; existing saves work.

**Production asset structure unified (2026-10-13):**
[158 — Asset structure](docs/00_dev_roadmap/158_asset_structure.md) places all
381 models under `assets/models/`, grouped into animals, characters, flora,
rocks, construction, furniture and items. Dwarves belong to
`characters/dwarves/`; trees, bushes, flowers and reeds are peers under flora.
All 146 moved files retain their bytes and importer settings. Definitions,
registry paths, generators, audits, viewers and fixtures use the new locations.
Ten authoring checks, 16 fixtures, native family galleries and pre-change
settlement restoration pass. Standard 63 is the current folder guide. Restart
Play; no new world or save migration is needed. Notes below retain dated layouts.

**Production asset folders flattened (2026-10-13):**
[157 — Asset folder layout](docs/00_dev_roadmap/157_asset_folder_layout.md)
removes all seven redundant `faceted` folders and moves 297 models directly
under their family/species/part categories. All 381 model files retain their
exact bytes; moved import settings are preserved. Definitions, registry paths,
generators, audits, review tools and tests use the new layout. Standard 63 lists
the current paths. All 16 affected fixtures pass, and a pre-change settlement
save restores its actors, furniture, trees, wildlife and terrain. Restart Play;
no new world or save migration is needed. Generator filenames still describe
the faceted art style; prior notes and reports below are dated milestones.

**Legacy asset cleanup complete (2026-10-13):**
[156 — Legacy art cleanup](docs/00_dev_roadmap/156_legacy_art_cleanup.md)
removes 353 superseded voxel exports and 17 duplicate pilot exports. All 373
approved production GLBs and eight retained floor/effect models are byte-identical.
Trees now live under `assets/models/flora/trees/faceted/`; definitions, generators
and review tools use production paths. Old export commands are guarded; historical
images and cost reports remain. Six retained furniture flame meshes now have
independent offline source data, without dependencies on retired furniture bodies.
All 16 affected fixtures and native reviews pass; a pre-cleanup settlement save
restores all actors, trees, furniture and terrain. Restart Play; no migration is
needed. Cave flora, growing crops and effects remain future art batches. Full
grass voxels remain; turf caps are deferred. Notes below are dated milestones.

**Resource drops and work tools integrated (2026-10-13):**
[155 — Resource drops and work tools](docs/00_dev_roadmap/155_resource_drops_and_work_tools.md)
completes all remaining 62 item definitions / 92 model presentations and the
animated axe and pickaxe. This includes 23 previously missing models, all crate
fill states, material-selectable starter tools and refreshed inventory thumbnails.
All 1,507 imported-art checks and 15 distinct fixtures pass. Real mining, felling,
carrying, storage, crafting and save/reload retain their existing behavior.
Use `tools/generate_items_faceted.py` and `data/art/items.json`; original exports
remain for comparisons. Model paths alone changed in production definitions and
the tool registry. Restart Play; no new world or save migration is needed.
Cave flora, growing crop stages and effects remain future art batches. Full
grass voxels remain; turf caps are deferred. Prior notes below are milestones.

**Dwarf, wildlife and furniture conversions integrated (2026-10-13):**
[154 — Complete family conversion](docs/00_dev_roadmap/154_complete_family_conversion.md)
ships all 41 dwarf appearance parts, 21 wildlife parts and 41 furniture forms
(30 definitions, legacy chair, ladder/bridge variants and packed forms).
The 17 approved pilot exports are byte-identical. All 7,583 new art checks and
30 distinct gameplay/UI/art fixtures pass, including native door/bedroom lighting.
The full 24-dwarf/48-furniture settlement and pre-conversion save restoration pass.
Catalog thumbnails now match the integrated art; portraits include saved scars.
Gameplay IDs, bounds, recipes, behavior and save schemas are unchanged. Restart
Play; no new world is needed for current-format saves. Standard 63 is canonical.
Use `generate_dwarf_faceted.py`, `generate_wildlife_faceted.py` and
`generate_furniture_faceted.py`; retain old files for comparisons. The core family
migration in roadmap step 4 is complete. Loose items and tools follow in 155 above;
cave flora, growing crops and effects remain future batches. Full grass voxels remain.
The dated pilot/comparison notes below describe their original milestones.

**Production-scale art comparison (2026-10-13):**
[153 — Settlement comparison](docs/00_dev_roadmap/153_settlement_art_comparison.md)
tests the accepted dwarf, deer and starter furniture in the full generated world:
24 dwarves, 48 furniture pieces, eight lights, 2,953 trees and live wildlife.
Current/pilot runs retain matching starting-state and world hashes. Rendering
cost is comparable, with fewer primitives and unchanged paused draw counts;
real worker interactions and native save/reload pass. An existing shader-instance
capacity limit caused black actor parts; `project.godot` now doubles the uniform
buffer to 131072 slots. Restart Play. CPU world-processing spikes remain in both
art sets; no minimum-hardware or FPS guarantee is implied. Roadmap steps 1–3 are
complete. Subsequent full dwarf, animal and furniture integration is recorded in
154 above; the preserved measurements here describe the earlier pilot comparison.

**Shared world art standard finalized (2026-10-13):**
[63 — Shared art standard](docs/60_asset_creation/63_shared_art_standard.md)
consolidates the approved environment, dwarf, deer and starter furniture work.
New art uses broad flat-shaded forms, selective bevels, restrained owned palettes
and world-unit exports. It supersedes universal legacy voxel-modeling rules in
61 while preserving gameplay footprints, anchors, IDs, states and material roles.
Terrain, surface clutter, dwarves, wildlife and the furniture catalogue are
integrated. The production-scale pilot comparison is in 153; family migration
is in 154. Full grass voxels remain;
turf caps are deferred. This standard adds no runtime changes.

**Furniture art pilot visually approved (2026-10-13):**
[152 — Starter furniture art pilot](docs/00_dev_roadmap/152_furniture_art_pilot.md)
adds a faceted log stool, hay bed and frameless two-wide door in an isolated
current/pilot viewer. Launch `Launch Furniture Pilot.cmd` for all four wood
materials, sitting/sleeping with the approved dwarf and production door hinges.
All 70 asset checks and four gameplay adapters pass; 28 native comparisons are
recorded. Shipping furniture, definitions, worker behavior and saves are unchanged.
The player approved the furniture direction, completing all three pilot subjects.
Their shared authoring standard is finalized in 63; production-scale results are
in 153 and family migration follows.

**Deer art pilot visually approved (2026-10-13):**
[151 — Animal art pilot](docs/00_dev_roadmap/151_animal_art_pilot.md) adds six
faceted deer parts in an isolated current/pilot viewer. Launch
`Launch Animal Pilot.cmd` for standing, walking, fleeing, grazing and resting,
plus the approved dwarf as a size reference. All 66 imported-asset/pose checks
and the existing wildlife fixture with both current and pilot art pass.
Thirty native comparisons are recorded. Shipping animal models, definitions,
behavior and saves remain unchanged. The player approved the deer direction;
the furniture pilot is also approved and the shared standard is finalized in 63.

**Dwarf art pilot visually approved (2026-10-13):**
[150 — Dwarf art pilot](docs/00_dev_roadmap/150_dwarf_art_pilot.md) adds one adult
faceted dwarf in an isolated comparison viewer. Launch `Launch Dwarf Pilot.cmd`
to compare walking, mining, felling, carrying, seating and sleep using live rigs.
Eight modular GLBs preserve anchors, tints and the logical 1×1×3 body. All 173
asset/pose checks and three gameplay adapters pass; native views and portraits
are recorded. Shipping dwarf art, pools, saves and accepted environment assets
remain unchanged. The player approved the pilot's look; use it as the visual
reference when the appearance roster conversion is undertaken.
The approved deer and furniture pilots are in 151–152; the shared standard is in 63.

**Ground stones completed (2026-10-13):**
[149 — Boulders and loose stones](docs/00_dev_roadmap/149_ground_stones.md)
converts all six models to broad faceted grey stone, completing current surface
clutter. Boulder blocking and scree walkability, worker yields/times, placement,
picking and saves are unchanged. All 476 asset/spawner checks, four gameplay
fixtures and native worker captures pass. Matched world hashes/draws stay fixed;
source triangles fall from 9,204 to 1,140 with no measured GPU regression.
All 170 accepted tree/plant models are byte-identical. Offline authoring:
`tools/generate_ground_stones.py`, `data/art/ground_stones.json`. Restart Play;
existing worlds work. Character/animal/furniture production migration and turf caps remain future work.

**Surface vegetation completed (2026-10-13):**
[148 — Bushes, wildflowers and reeds](docs/00_dev_roadmap/148_surface_vegetation.md)
adds 76 low-poly models for all three berry bushes, three wildflower colors and
both reed variants, including seasonal, young, picked and applicable packed forms.
The 1,831 asset/spawner checks and ten gameplay fixtures pass, including real
worker moves/planting, crop regrowth and save/load. Native paired seed-1234 views
retain plant identities and draw counts with no measured GPU regression. All
94 accepted trees and terrain stay unchanged. Offline authoring:
`tools/generate_surface_vegetation.py`, `data/art/surface_vegetation.json`.
Restart Play; existing worlds work. Main surface vegetation conversion is complete.

**Complete tree family (2026-10-13):**
[147 — Apple/juniper completion](docs/00_dev_roadmap/147_complete_tree_family.md)
adds 52 clustered GLBs, including apple blossom/fruit and all picked junipers.
All four live species now use the new style (94 models); approved pine/oak are
byte-identical. All 2,064 asset/spawner checks, real juniper harvesting, felling,
picking, navigation and save/load pass. Matched 2,953-tree production captures
add ~0.12 ms median GPU time for the new pair in the 2560×1440 overview on RX 9070 XT.
No gameplay/stat changes; apple worker harvesting remains future work. Generator:
`tools/generate_tree_pilot.py`; profile: `data/art/tree_pilot.json`. Evidence in
147 and `tmp/tree_family_20261013/`. Restart Play; no new world needed.

**Pine/oak art pilot (2026-10-13):**
[146 — Tree art pilot](docs/00_dev_roadmap/146_tree_art_pilot.md) integrates
42 clustered low-poly GLBs across every existing stage, season and variant of
pine/oak. Placement, footprints, felling, yields and saves remain unchanged;
apple/juniper completion is recorded in 147 above. Offline profile/generator:
`data/art/tree_pilot.json`, `tools/generate_tree_pilot.py`. All 976 asset/spawner
checks plus picking, chopping, navigation and save/load pass. Native matched
2,953-tree views retain draw counts; the 2560×1440 overview adds 0.577 ms median
GPU time on RX 9070 XT. Evidence and limits in 146. Restart Play; no new world.
Broader character/animal/furniture migration and turf caps remain deferred.

**Shoreline colour correction (2026-10-13):** The reported moving pale shoreline
band came from `MoistureRenderer` covering the new linear terrain palette with
old sRGB vertex colours. Damp grass/dirt now share terrain profiles and shading,
with gradual darkening and paused-season refresh. Explicit moisture coverage
remains a separate debug palette. Five focused fixtures pass, including 314
overlay checks. Matched native 0/30/90-second captures preserve identical water
and moisture states. Evidence: `tmp/shoreline_art_20261013/` and roadmap 145.
Restart Play; no new world or save migration is needed.

**Base world terrain art implemented (2026-10-13):**
[145 — Base world terrain art plan](docs/00_dev_roadmap/145_base_world_terrain_art_plan.md)
records all five completed phases. The base terrain uses one
coherent grey rock palette with subtle local variation, full grass voxels,
and restrained dirt. Height-driven rock colour bands and generated grass edge
rings are retired. Turf-over-dirt caps remain deferred. Production uses soft
terrain-only edge shading on merged faces; the real-chamfer comparison stays in
the study. Overview jobs finish asynchronously with stale-result rejection and
a 4 ms soft upload budget. All 41 distinct regression fixtures pass, including
564 appearance checks, generation, concealment, construction and current save/load.
Native 1600×1000/2560×1440 comparisons and limits are recorded in 145: existing
large mining-command and active-simulation spikes remain. Restart Play.

**Wider art direction handoff (2026-10-12):**
[144 — World art direction and next session](docs/00_dev_roadmap/144_world_art_direction_handoff.md)
records the original native study, terrain/path rules and the staged move to
voxel-inspired stylized low-poly world assets. Plan 145 supersedes its turf-cap
recommendation; 146–152 record the environment migration and approved pilots.
Standard 63 completes the shared authoring rules; 153 records the production-scale
comparison. The full dwarf, wildlife and furniture migration is complete in 154.

**Small-world visual study (2026-10-12):** [143 — Visual quality study](docs/00_dev_roadmap/143_visual_quality_study.md)
adds an isolated 32×32 native scene with paired current/study treatments.
Art pass 2 adds stone chamfers, fir/oak prototypes, ground/room dressing, flowing
water presentation and revised lighting. The player likes the individual stone
and upgraded trees. Pass 3 adds individual dirt/grass blocks, softer edges and
turf over soil; G compares ground passes without changing trees or lighting.
Day/dusk/night, slice and real terrain
edits remain testable. Double-click
`Launch Visual Study.cmd` for a visible standalone window; F5 still runs the game.
F6 requires the study .tscn selected in Godot's scene tabs, not just its script.
Latest captures: `tmp/visual_study_20261012/art_pass_3/`; 42 checks pass. GPU medians
are 1.71–2.22 ms at 1600×1000 on RX 9070 XT; synchronous fixture remesh is ~100 ms.
Earlier pass images/reports are retained, including `art_pass_2/`.
This is an art/lighting experiment, not the production renderer or a full-world
performance result. Main-world shaders, assets, save behavior and project settings
are unchanged. No new autoload/global class; no project reload required.

**Fixed time/Slice controls (2026-10-12):** [142 — Utility HUD](docs/00_dev_roadmap/142_fixed_time_slice_hud.md)
adds illustrated Pause, 1×, 2× and Slice at the bottom right. A permanent tower
above Slice has exact ±1/±4 arrows and a live level; off reads Full world and
retains the last height. Wheel over the tower steps height; world scrolling
still zooms. The old upper-left controls, Slice window and Menu shortcut are
removed. The main dock makes room, with a stacked fallback at narrow widths;
menus avoid the utility controls. Native input/layout, saved state, Sky Dial and
navigation checks pass. Logs: `tmp/time_slice_20261012/`. Restart Play.

**Sky Dial (2026-10-12):** [141 — Clock/weather HUD](docs/00_dev_roadmap/141_sky_dial.md)
replaces the Clock window, Menu shortcut and upper-left calendar button with a
permanent illustrated upper-right dial. Live time, season/day, seasonal lighting
anchors and current Clear/Foggy/Overcast/Snow drive its original art. Hover/focus
shows year, phase and rise/set. Pause/speed/Slice remain separate; food warnings
sit below and ordinary windows make room. UIRegistry owns the art definitions;
there are no simulation/save changes or new autoloads. Restart Play.

**Remaining illustrated menus (2026-10-12):** [140 — Delivery](docs/00_dev_roadmap/140_remaining_illustrated_menus.md)
implements approved plan 139: Craft, Place, Colony, Menu/Development, Inventory
and Rooms. Shared original art, hover/focus names and planned catalog badges
retain direct browser/room flows. World Build and time/weather tests now live in
Development; save/test dispatch uses stable IDs. Colony's flag entry inspects
the actual flag/order or opens its packed Place flow without founding again.
Native layouts, browser stability, worker flag moves and menu checks pass.
Logs: `tmp/remaining_menus_20261012/`. Restart Play; dwarf-screen work stays separate.

**Illustrated Construction (2026-10-12):** [138 — Construction menus](docs/00_dev_roadmap/138_illustrated_construction.md)
adds stone-block and Floors icons, then plank/stone floor icons with a Back arrow.
The two floor tools stay usable DEV previews, with flask badges and hover/focus
explanations. Stone costs, floor worker locks and DEV Build are unchanged. Menus
anchor above Construction, which stays highlighted during building. Checks and
native captures: `tmp/construction_art_20261012/`. Restart Play.

**Illustrated Zones (2026-10-12):** [137 — Zones submenu](docs/00_dev_roadmap/137_illustrated_zones.md)
adds Storage, Farming and Animal pasture art above Zones. Storage remains live;
the latter two are dimmed, locked planned entries with mouse/keyboard explanations
and no tool dispatch. The shared shelf now uses illustrated controls for both
groups. Native layouts and input checks: `tmp/zones_art_20261012/`. Restart Play.

**Illustrated Orders (2026-10-12):** [136 — Orders submenu](docs/00_dev_roadmap/136_illustrated_orders_plan.md)
delivers six approved illustrated icons anchored above Orders, with hover/focus
names, a separated Cancel command and compact live tool feedback. Icons wrap
beside moved inspectors; Zones subsequently gained matching art in 137. Shared icon setup,
real input/cancel/undo and native 960/1280/2560 layouts pass. Captures and checks:
`tmp/orders_art_20261012/`. No simulation/save changes; restart Play.

**Illustrated dock (2026-10-12):** [135 — Command dock](docs/00_dev_roadmap/135_illustrated_command_dock.md)
uses the approved Hearth & iron art for all ten bottom commands, with hover/focus
names, square responsive buttons and a copper active notch. UIRegistry owns atlas
regions in dock.json; DockIconButton owns presentation; existing dispatch remains.
Native button/menu/tooltip checks cover 960/1280/2560. Dwarf-screen redesign is
still separate. Captures: `tmp/dock_art_20261012/`.

**Food stage 2 (2026-10-12):** [131 — Food and dining](docs/00_dev_roadmap/131_dwarf_food_and_dining.md)
now includes emergency berry picking, dining, hunger/dining penalties and serving
presentation. Stored/loose food wins; only famished dwarves forage within 24 routed
blocks. SurfaceDetailManager owns crop claims/progress/commit. Seats share leisure
claims; tables claim access spots. Dining thoughts replace rather than stack.
Hungry/famished work speed is 90%/75%, mood −5/−15; no starvation damage/death.
Overview shows effects; Details shows last meal/thoughts; failed food searches
drive a quiet HUD warning. Current saves preserve meals, mood and crop work.
The job gate now has 32 fixtures, including DwarfDiningTest. Stage 3's character
screen reorganization remains deferred. Logs/captures: `tmp/dining_20261012/`.

**Distant shrub Moves (2026-10-12):** [134 — Distant Move planning](docs/00_dev_roadmap/134_distant_shrub_move_planning.md)
fixes idle wandering repeatedly discarding long uprooting route searches.
Surface work and exact-item Move searches renew their leisure hold while making
measured progress. Surface assignments prove/cache the exact work stand.
Search budgets and normal need/priority interruptions remain unchanged; the
handoff regression includes slow distant routes with live leisure/supervision.

**Settlement flag furniture (2026-10-12):** [133 — Settlement flag](docs/00_dev_roadmap/133_settlement_flag_furniture.md)
makes the banner clickable in Object explorer with normal Move/Uninstall and
worker transport. Place → Rooms recovers a packed flag. The founding controller
grants the first flag/squad once and retains the last anchor during transit;
reinstallation updates it. Furniture owns the physical flag and occupancy.
Current saves use required settlement `founded` state; restoration never creates
a second physical flag. The shared job gate now has 31 fixtures.

**Furniture Move (2026-10-12):** [132 — Furniture Move](docs/00_dev_roadmap/132_furniture_move.md)
adds Move to installed furniture/workbench and container inspectors. Confirm a
normal placement preview, then workers pack, carry and install that exact piece.
Material, bed ownership and container filters persist; contents empty through
normal uninstall. Cancelling before packing keeps the original; afterwards the
packed item remains recoverable. Current saves include required furniture move
records and destination identities; old development saves need no migration.
The shared job gate now includes FurnitureMoveTest (30 fixtures).

**Dwarf food foundation (2026-10-12):**
[131 — Food, dining and character screen](docs/00_dev_roadmap/131_dwarf_food_and_dining.md)
records the agreed plan. Stage 1 adds general edible-item data (five fruits now),
game-hour hunger, reachable storage-first portions, allowed loose-food fallback,
safe interruption/current saves and a Food bar in the shared dwarf inspector.
Berry bushes regrow after two planted days in eligible seasons; packing and
off-season time pause growth. Development → Dwarf tools can make a dwarf hungry
for testing. Stage 2 is now live as described above; only the character-screen
redesign remains stage 3. No starvation damage/death.
The shared job gate includes food/regrowth and now has 29 fixtures.

**Clickable terrain (2026-10-12):**
[130 — Terrain inspection](docs/00_dev_roadmap/130_terrain_inspection.md)
adds player material names and facts to Object explorer for exposed walls,
floors and ceilings. Slice/planned faces conceal resources; object and zone
selection retain priority. Block Inspector now lives in Development and honors
mined AIR when reading live chunks. Terrain metadata is owned by BlockRegistry.

**Wall-light mounting heights (2026-10-12):**
[129 — Wall mount heights](docs/00_dev_roadmap/129_wall_mount_heights.md)
lets the player aim at a wall cell or use Alt + wheel for either torch. Install
and uninstall share five-block bracket reach from a clear, reachable work floor.
Saved positions stay fixed when floors change; pending lights wait for renewed
access. Actual bracket loss still removes them. Room heat samples the mount's
air cell. Automatic access ladders remain deferred. The job gate has 27 fixtures.

**Permanent floors — development preview (2026-10-12):**
[128 — Permanent floors](docs/00_dev_roadmap/128_permanent_floor_preview.md)
adds Construction → Floors → Simple plank/stone floor. Mine a supporting layer,
then plan full blocks; click a blue plan for DEV Build. Carpenter/Stonemason
construction stays locked, with no jobs or inventory claims. Original 8×8×8 voxel
art repeats across the grid and uses live terrain lighting. Completed interior
floor coverage adds +5 flooring appeal in Rooms; mixed materials and tiles under
furniture count. Floor kinds, built terrain and pending plans save. The job gate
included 26 fixtures at this milestone. Rugs, pelts and fitted carpets remain deferred.

**Floor excavation recovery (2026-10-12):** Installed wall torches now depend on
their bracket supports, preserving their height/light/heat when the floor below
is dug out. Milestone 129 also preserves pending plans while access is missing.
Idle dwarves can step
up out of shallow unfinished floor tiles, and footing recovery lifts embedded
feet onto a clear raised floor, including current saved positions. See
[115](docs/00_dev_roadmap/115_dwarf_support_recovery.md) and
[128](docs/00_dev_roadmap/128_permanent_floor_preview.md).

**Development navigation (2026-10-12):** Development is a standalone dock entry
at the far right, after Menu. Its tools cover spawning, dwarf tools, block
inspection, water, cave inspection and arrival status. The 15 cycling object/arrival commands,
their dispatch, locator methods and cursor state have been removed. QA previews
select explicit fixtures through normal inspection. Current documentation and
playtest instructions use the new menu and ordinary click selection.

**Frameless log doors (2026-10-12):** [117 — Log furniture](docs/00_dev_roadmap/117_log_furniture_and_fire_audio.md)
now uses only rough swinging log leaves at all three widths. Fixed frames are
reserved for later door tiers. The live generator, placed icons, hinge positions
and art/catalogue notes agree. Native art, door lighting, passage, sealing and
restoration checks pass. Restart Play/load a current save to refresh existing art.

**Structural stone construction — live (2026-10-12):**
[127 — Structural stone](docs/00_dev_roadmap/127_structural_stone_construction.md)
adds Construction → Stone block. Each full voxel costs one physically delivered
rough stone and uses the existing natural rock layer at its height. Mining and
building are separate actions. Constructed slice caps now match natural cut-face
shading; genuine exposed tops keep their normal color. Native comparisons and
construction regressions pass. Real terrain supports navigation and room sealing;
unfinished areas, partial work and built provenance save. Normal mining recovers
one stone. BlockRegistry owns construction definitions; ConstructionController
owns orders and provenance. Wall coverings, combined replacement and floor/rug/pelt
features are outside this milestone. Roadmap 23 is historical and superseded.
Blue plans are clickable during and after construction mode: Object explorer
shows remaining blocks, stone, worker and progress, with safe cancellation.
Additional wall types are deferred and wall finishes remain excluded. Permanent
wood and stone floor previews follow in milestone 128 above. Fitted carpets are
grouped with rugs and pelts for later work.

**Shared job lifecycle and recovery — live (2026-10-11):**
[126 — Lifecycle and recovery](docs/00_dev_roadmap/126_job_lifecycle_and_recovery.md)
implements the four steps from [125 — Architecture review](docs/00_dev_roadmap/125_jobs_and_dwarves_architecture_review.md):
saved order identity, attempt fencing, progress supervision, complete furniture
fetch planning, shared work execution and fair retained searches. Dwarf development
has a Job inspector with waiting reasons and retry. Run the 25-fixture gate in
`tools/run_job_reliability.ps1`; source/inventory owners remain authoritative.
Receipts are runtime guards, not durable event replay. Current saves include jobs
diagnostics and craft order IDs; no legacy save migration was added.

**Earlier gameplay session handoff:** [124 — Starter colony, 2026-10-11](docs/00_dev_roadmap/124_session_handoff_2026_10_11.md)
collects today's bridges, furniture/materials, bedrooms, warmth/privacy, mining
progression, placement timing and grouped storage. It records final verification,
next-session playtests, current save policy and issue status. On 2026-10-12, Alen
provisionally closed issues 001 and 002 as presumed resolved. Neither is active
work; reopen only if the player reports it again.

**Ladder extension dispatch (2026-10-11):** [88 — Ladder task reachability](docs/00_dev_roadmap/88_ladder_task_reachability.md)
records the late-session saved-game fix: repeated mining searches above an
unfinished ladder starved its construction job. Budget yields now give other
job types a turn while preserving each type's search progress. The copied save
completes its two remaining sections; no replacement order or new world is needed.

**Grouped storage contents (2026-10-11):** [59 — Storage filters](docs/00_dev_roadmap/59_storage_filters.md)
now shows alphabetical totals by item/material across ground zones and containers.
Allow/Disallow is outside-storage only, including Object explorer. Stored goods
remain available colony stock; acceptance filters and relocation keep their roles.

**Immediate furniture placement (2026-10-11):** [123 — Placement timing](docs/00_dev_roadmap/123_furniture_placement_timing.md)
removes the hidden two-second build wait for ordinary furniture. All 25 designs
install during one 0.65-second set-down, aimed at their actual floor footprint or
wall mount. Bridges/ladders and plants retain their animated work durations.
Native/headless timing, rotated placement, interruption, cargo and task-family
regression checks pass.

**Privacy, heating and mining progression — live (2026-10-11):**
[122 — Bedroom comfort and mining progression](docs/00_dev_roadmap/122_bedroom_comfort_and_mining_progression.md)
adds bedroom leisure privacy with normal visitor exits and filtered sleep routes,
rudimentary hearth crafting (two logs/four stones), sheltered 10°C rock baseline and
actual cold/chilly/hot sleep thoughts. RoomManager owns temperature.json. Ore/gem
progression now requires immutable cover from the natural exterior, including
cliffs, with descent gates for precious resources. Eight fresh-seed samples and
the copied player save are verified; existing mined goods are untouched.

**Rudimentary hearth art (2026-10-11):** [30 — Hearth visual redesign](docs/00_dev_roadmap/30_hearth_visual_redesign.md)
now uses low uneven fieldstones, exposed logs/coals and simple stepped flames.
The starter hearth has no dressed masonry or iron fittings. Its existing 2×2
footprint, 2400 heat, recipe, sound and stable keys are retained; ten animated
frames, native renders, placement/save and bedroom crafting/heat checks pass.

This file is the **entry point** for any AI agent working on this codebase. Read it first. It maps every design document to its purpose and tells you which file to consult before touching any system.

**Development save policy (2026-10-09, user decision):** Backward compatibility
with older development saves is not required. Do not add legacy definitions,
migrations or compatibility branches just to preserve old saves unless the user
explicitly requests them. Keep current-version save/load working; development
changes may invalidate older saves. Use current definitions when loading rather
than retaining obsolete layouts that require players to rebuild items manually.

**Bed ownership and comfort — live (2026-10-11):** [121 — Personal bedrooms](docs/00_dev_roadmap/121_personal_bedrooms.md)
adds bed assignments through Object explorer, exclusive use and one assigned bed
per colonist. A single assigned bed makes a personal bedroom; multiple beds make
a barracks. Completed sleep with at least three hours in one's personal bedroom
grants +10 happiness for 24 game hours. Assignments and thought timers save.
Torch range/falloff now light a furnished 4×7 room while doors retain shadows.

**Log beds and bedrooms — live (2026-10-11):** [120 — Beds and bedrooms](docs/00_dev_roadmap/120_log_beds_and_bedrooms.md)
adds Worker-crafted 4×3 log beds with wood variants, real reachable/exclusive bed
sleep and ground fallback. Bedrooms require a whole bed, door, enclosure and light;
classification is derived on edits and load. Firelight energy is doubled. A faint
silhouette preserves dwarf readability behind nearby walls/ladders without changing
navigation. Native art/UI, sleep, lighting, cover and save checks are documented.

**Dwarf movement and ground rest — live (2026-10-11):** [119 — Walking and ground rest](docs/00_dev_roadmap/119_dwarf_walking_and_ground_rest.md)
raises walking speed to 3.4 blocks/second with a longer planted stride. Sleepers
seek a nearby wall or tree, sit or recline with closed eyes and breathing, then
stand up before returning to work. Quiet spatial snores replace the old emoji.
Bed use followed in milestone 120; no new save fields. Rest search, poses, audio
and lifecycle are tested.

**Crafted materials and appeal — live (2026-10-11):** [118 — Crafted materials and appeal](docs/00_dev_roadmap/118_crafted_materials_and_appeal.md)
preserves pine/oak/juniper/applewood through crafting, hauling, storage, equipment,
installation, recovery and saves. Shared wood palettes and a material selector
keep one catalog entry per design. Object appeal combines design and material;
copper/gold profiles prepare future recipes. Appeal-driven room scores/moods and
craftsmanship quality remain later work; bedroom/temperature thoughts are live.
Reload Current Project for the new CraftMaterials registry autoload.

**Log furniture and fire audio — live (2026-10-11):** [117 — Log furniture and fire ambience](docs/00_dev_roadmap/117_log_furniture_and_fire_audio.md)
adds single log doors at two/three blocks wide and a double at four, with
approach-driven hinges and full room sealing. The bench and starter torch now
use simpler log art and names. Worker recipes and icons cover the new doors and
bench. Campfires and both torches have quiet spatial crackles on the Work bus;
pause, slices, visibility and source removal silence them. Current saves retain
installed items. Art, crafting, movement, audio and save/backup checks pass.
Door faces now sample their own side of the room seal, fixing black outdoor wood
and light leaking from jambs onto open leaves. All widths/rotations and restore
are covered by `DoorLightingTest`; see [24 — World rendering](docs/20_player_interface/24_world_rendering.md).

**Full packed furniture crates — live (2026-10-11):** [116 — Full furniture crates](docs/00_dev_roadmap/116_full_furniture_crates.md)
enlarges the shared packed furniture model to an 8×8×8-voxel wooden shipping
crate, one full world block, with recessed planks and stepped braces. The 22
shared furniture items use it at native loose/carry size and fit existing shelf
slots. Native art, actual hauling and camp furniture installation are verified.

**Dwarf footing — fixed (2026-10-11):** [115 — Dwarf support recovery](docs/00_dev_roadmap/115_dwarf_support_recovery.md)
checks every dwarf before work, leisure or sleep. If another miner removes its
floor, the dwarf settles onto the first physical support below, releases obsolete
routes/claims and drops cargo intact. Current saves with hovering dwarves recover
when resumed. Normal steps, ladders and bridge supports retain their behavior.

**Crafting browser — live (2026-10-11):** [114 — Crafting browser](docs/00_dev_roadmap/114_crafting_browser.md)
replaces the tall recipe tiles and permanent queue column with compact icons
under category headings, recipe/category search, and Recipes / Orders tabs.
The selected item's illustration, materials and crafting actions share one
detail card. Queue and Place stay visible on compact screens; live updates
preserve keyboard focus, order controls and scroll positions.

**Log bridges — live (2026-10-11):** [113 — Log bridges](docs/00_dev_roadmap/113_log_bridges.md)
adds Worker-crafted kits, Place → Access previews, two-block decks spanning up
to five water blocks between equal-height banks, and installation from one bank.
Completed decks support walking/hauling while water flows underneath. Closing,
evacuation, kit recovery, interrupted work and current saves are verified.
Placement now snaps bank faces/riverbed hits to landings and auto-aligns across
the river; real mouse clicks and the playtest seed are covered by the input fix.
Workers can build from either landing regardless of the preview's anchor bank,
fixing saved plans that demanded a route across the unbuilt crossing. Opposite-bank
mouse placement, real delivery and builder facing are regression-tested.
Bogorn's bridge-corner fall is fixed: moving shortcuts now check the actual actor
position, with safe recentering after interruption. See doc 32 and
`BridgeCornerWalkingTest`; already submerged saved actors require recovery.
Start a fresh development world; older saves lack the required bridges section.

**Previous session:** [112 — Water and wildlife, 2026-10-10](docs/00_dev_roadmap/112_session_handoff_2026_10_10.md)
retains the finite-water, finished-gem, movable-stone and duck implementation history.
Use handoff 124 above for the current starting point and remaining work.

**Ducks — live (2026-10-10):** [111 — Duck wildlife](docs/00_dev_roadmap/111_duck_wildlife.md)
adds seeded calm-water flocks, male/female voxel art, swimming, shore activity,
short obstacle-checked flights and scheduled aerial arrivals. Quacks/splashes
use Work audio; picking, Follow, slices, live levels and current saves are covered.
Click ducks near water to inspect or Follow them. Start a fresh development world;
old saves without duck fields are not migrated. Egg/breeding/domestication and
duck predation remain future work. Doc 45 owns wildlife behavior.

**Spring-fed rivers and flooding — live (2026-10-10):**
[105 — Rivers and water](docs/00_dev_roadmap/105_rivers_and_water.md) implements the
agreed high rock spring, downhill river/pools/waterfalls and protected lake outlet.
`WaterManager` owns finite water in integer millionths of a block cubed, active
flow, measured extraction, gradually wetting/drying soil, and current-save state.
Terrain edits can flood banks and excavations; submerged sources stop. Separate
voxel water meshes, square sparkles/splashes, local waterfall audio, damp soil and
a moisture overlay follow live levels. Navigation and placement use live water.
The terrace-spill fix routes free waterfalls into the lower channel, checks
detailed river banks and adds plunge pools. Films below 1/16 block look damp and
remain walkable. Normal river reaches are now about five voxels across, with
short narrows and wider pools; all water shares one palette with subtle depth
shading. [106 — Spring caves and water edges](docs/00_dev_roadmap/106_spring_caves_and_water_edges.md)
replaces the decorative spring mouth with real terrain air, a dry ledge and a
wet stone feeding a small pool. Hairline water gaps are closed and tiny
steps share surface lighting. The spring outlet stays aligned for four cells before
its first bend; rough cliff lips are opened through real cave air. Water layout
version 5 requires a fresh development world.
[107 — Water appearance](docs/00_dev_roadmap/107_water_appearance.md) replaces fixed
scrolling/bands with sparse glints following measured local currents, quiet lake
shimmer, localized fall foam/splashes and distance fading. Presentation telemetry
does not change water volumes or saves. Whole-world startup coverage is verified.
[108 — Water ambience](docs/00_dev_roadmap/108_water_ambience.md) adds procedural
waterfall rush and gentler river burbling, following visible measured currents,
camera focus/zoom and the shared Work volume/mute controls. Still lakes stay quiet.
[109 — Loose water stones](docs/00_dev_roadmap/109_loose_water_stones.md) uses the
exact ore-drop shape for both stones: turquoise flecks beside the cave pool and
muted flecks on the lakebed. The old terrain patches and shoreline arch are gone.
Source/drain positions, rates, discharge cap and retained lake level are unchanged.
[110 — Permissions and movable stones](docs/00_dev_roadmap/110_item_permissions_and_water_stones.md)
adds outside-storage Allow/Disallow and real Pack/Move/Place work. Natural stones
start disallowed and keep working; Allow alone never auto-hauls placed stones.
Packed/carried/stored stones are inactive; placing restarts their effect at the
new position. Permissions, exact identities, packing progress and move plans save.
Extra stone pairs share the same lifecycle through a grant API; scenario acquisition
remains future work. Initial hydrology is unchanged. Existing development saves
without these fields are rejected, with no migration required.
Development → DEV: Water locates features and provides a reversible test dam.
Ordinary dam construction jobs and physical brewery hauling/recipes remain planned;
flood damage, drowning, floating goods, pumps and pressurized pipes are not enabled.
Reload Current Project after pulling this new autoload. Older development saves
need no migration, per the policy above. Doc 33 owns the water contract.

**Finished gem artwork — live (2026-10-10):** [104 — Gem drops](docs/00_dev_roadmap/104_gem_drop_artwork.md)
adds six stepped voxel gem models and matching inventory thumbnails. Jade, Amethyst,
Ruby, Sapphire, Emerald and Diamond are shiny and finished immediately when mined.
**User decision: no Jeweller profession/workshop or cutting/polishing stage.**
The old deferred Jeweller proposal is superseded. Stable `_raw` identifiers stay;
display names omit "Raw". Gem-only gloss respects sky access and local lights,
including carried/shelved goods. Native art/lighting, item lifecycle, inventory,
loose support and full save/backup regressions pass; see 104 for captures.
The user rejected the initial angled polygon faces: gems now use only cube
faces on the standard eight-voxels/block grid, with square highlights.

**Equipment view and promotion feedback — live (2026-10-09):** [102 — Equipment feedback](docs/00_dev_roadmap/102_equipment_view_promotion_feedback.md)
adds a shared Equipment tab to the Colony detail column and standalone inspector.
It shows the actual owned kit, thumbnail, materials and benefit, plus clearly
planned Iron saw / Iron pickaxe upgrade paths. No upgrade goods or bonuses are
invented. A short original chime plays on completed promotion, including paused
Miner appointments; requests, cancellation, demotion and restoration are silent.
Native UI at three resolutions, completion/restore checks, audio PCM/volume/mute
and existing promotion/inspector/roster/profession/work/wildlife tests pass.

**Carpenter tool promotion — live (2026-10-09):** [101 — Tool promotion](docs/00_dev_roadmap/101_tool_based_promotion.md)
requires an available crude carpentry kit. A dwarf reserves and physically picks
it up before becoming a Carpenter. The inspector shows equipped tools; inventory
counts them separately from cargo. Cancellation/sleep and changing professions
release real goods without loss. Equipped and pending promotions survive current
save/load and backup recovery. Miner keeps free promotion/default pickaxe;
Carpenter specialist workshop/recipes and other starter-tool careers remain planned.

**Profession crafting and camp furniture — live (2026-10-09):** [100 — Camp crafting](docs/00_dev_roadmap/100_profession_crafting_camp.md)
opens Craft's profession-button submenu above the dock, then the selected
profession's recipes/orders or planned preview. The old dropdown is removed;
Rudimentary contains the live Worker recipes and a Crafters button returns to
the submenu. Profession buttons wrap into two rows on compact screens.
Campfires and compact 1×1 stump stools are craftable at the crude workbench,
physically hauled and installed. Campfires center on a tile in a 3×3 placement
area and animate/light; idle dwarves use stools directly beside all four sides.
Stool occupants rest their hands in front and independently face a nearby clear
campfire, with a small head turn for off-axis fires. Rounded head/beard clearance
and separate low body/fire regions permit this spacing. Preview
gating, save/load, compact layouts and existing crafting regressions pass.

**Dwarf idle activity — live (2026-10-09):** [99 — Idle activity](docs/00_dev_roadmap/99_dwarf_idle_activity.md)
adds staggered local strolls, looking around and exclusive use of nearby wooden
chairs after work. Leisure stays interruptible and in the scheduler's available
pool. Same-level local movement, seat removal/sleep cleanup, save-safe poses,
inspection and native seated views are covered; needs and dining are separate.

**Crafting worker selection — fixed (2026-10-09):** [98 — Crafting selection](docs/00_dev_roadmap/98_crafting_worker_selection.md)
extends pickup proximity to every Worker recipe. All eligible idle dwarves are
compared at the first material, with bounded pickup/workbench route checks and
exact material reservation. Loose, stockpiled and container ingredients compete;
failed nearby routes cannot hide other workers, materials or workbenches.

**Starter profession tools — live (2026-10-09):** [97 — Starter tools](docs/00_dev_roadmap/97_starter_profession_tools.md)
adds Worker-crafted stone hoes, hunting spears, carpentry kits and stone hammers
at the crude workbench, each from one allowed log plus one Rough Stone. Physical
material trips, safe interruption, storage, save/load, Tools inventory and native
menus are covered. Profession cards show tool stock; Carpenter pickup/equipping
followed in milestone 101. Other specialist promotions remain planned.
A forged saw is a Carpenter upgrade, not its entry gate.

**Professions and Miner — live (2026-10-09):** [96 — Professions](docs/00_dev_roadmap/96_professions_and_miner.md)
adds the career map and appointment card, usable Worker/Miner changes, and planned
Farmer/Hunter/Carpenter/Stonemason/Blacksmith careers. Colony Labor opens real Work
permissions. Miners receive mining preference and levels 1–5 from completed blocks;
Workers retain normal mining. Safe release, retained XP, permission saves, native
compact layouts and gameplay/save regressions are covered in the milestone.
The agreed equipment follow-up is planned: Miner keeps its default pickaxe/free
promotion; crafted iron and later advanced-metal picks add bounded multi-voxel
mining. Selected careers will need starter tools. See the equipment sections in
[41 — Dwarves](docs/40_economy_colony/41_dwarf_agents.md) and
[43 — Mining](docs/40_economy_colony/43_mining_materials.md). Starter tools are now
craftable (97); Carpenter equipping is live (101), while equipment bonuses remain planned.

**Deer and wolf arrivals — live (2026-10-09):** [95 — Deer/wolf arrivals](docs/00_dev_roadmap/95_deer_wolf_arrivals.md)
extends shared events with 2–4 deer every 4–7 days and 1–2 wolves every 7–12
days, capped at 18 deer / 4 wolves. Full-footprint routes, separate herd homes,
prey-surplus/local-food gates and saved group progress preserve gentle balance.
Wolves settle before hunting; kills never accelerate or enlarge events.
Startup planning waits for tree occupancy. **DEV: Arrival status** covers all
species; entered animals use ordinary click inspection and Follow.
Four-seed routes, mixed save/backup restoration and wildlife regressions pass.

**Rabbit arrival events — live (2026-10-09):** [94 — Rabbit arrivals](docs/00_dev_roadmap/94_rabbit_arrival_events.md)
adds the shared WorldEventDirector scene owner and rabbit provider: scheduled
1–4-member opportunities every 2–4 days, validated edge-to-inland routes,
staggered entry, population caps and expiry. Kills never accelerate or enlarge
arrivals. Saved local hunting pressure is wired for future player hunting;
predation does not add it. Mid-group/mid-stride saves, backup restoration,
four-seed routes, native inspection/Follow and wildlife regressions pass.
**Development → DEV: Arrival status** reviews opportunities and their outcomes.
Deer/wolf support followed in milestone 95; visitor/raid providers remain future work.

**Rabbit wildlife — live (2026-10-09):** [90 — Rabbit wildlife](docs/00_dev_roadmap/90_rabbit_wildlife.md)
adds seeded rabbits, gentle grazing and sleep, dwarf avoidance, voxel animation,
shared inspection/Follow and persistence. Click a rabbit to inspect it.
Behavior, native picking/art and full save/backup checks pass.
[45 — Wildlife](docs/40_economy_colony/45_wildlife.md) records ownership, tuning
and deferred berries and farm theft.

[91 — Rabbit audio](docs/00_dev_roadmap/91_rabbit_audio.md) adds three quiet
selection and three grazing variations using the existing Work audio bus/pool.
Click cooldown, nearby/zoom attenuation, pause-aware eating, slice/source cleanup
and native PCM checks pass; audio never changes wildlife needs, RNG or saves.

**Deer wildlife — live (2026-10-09):** [92 — Deer wildlife](docs/00_dev_roadmap/92_deer_wildlife.md)
adds up to eighteen deer in six loose groups, articulated grazing/rest/walking,
faster escape and quiet selection/eating sounds. Click deer to inspect them.
Shared GrazerAgent preserves rabbit behavior; species-specific navigation uses
the full deer footprint. Herd identity and mixed populations persist in current
saves. Native, behavior, audio and save checks pass.

**Wolves — live (2026-10-09):** [93 — Wolf wildlife](docs/00_dev_roadmap/93_wolf_wildlife.md)
adds four sparse predators with hunger-gated, bounded hunts, prey escape,
atomic captures, long meal satisfaction and protected prey reserves. Wolves
avoid dwarves. Art, soft selection/eating sounds, inspection and saved pursuits
are included. Click wolves to inspect them. Behavior,
four-seed population, native, audio, save/backup and grazer regression checks pass.

**Previous session handoff:** [103 — Evening 2026-10-09](docs/00_dev_roadmap/103_session_handoff_2026_10_09_evening.md)
records wildlife/arrivals, professions, starter tools, crafting selection, camp
furniture/leisure, physical Carpenter promotion and Equipment/promotion feedback.
Its recommended next milestone was Carpenter's workbench and first specialist
recipes; promotion is live but specialist production and tool upgrades are not.
It preserves naming/save decisions, final verification and outstanding work.
[89 — Earlier handoff](docs/00_dev_roadmap/89_session_handoff_2026_10_09.md) retains
the world, caves, plants and ladder history. Read the relevant system docs as well.

**Seeded world layout — live (2026-10-07):** [66 — Seeded world layout](docs/00_dev_roadmap/66_seeded_world_layout.md)
replaces fixed compass geography with seeded ridges, a guaranteed ≥32×32 Y115
summit, substantial mountains, one lowland lake and an optional tarn. Players
choose and clear their own location: no starting plateau or tree exclusion is
generated. All natural cliffs and shores receive rough ledges; summit interiors
stay intact. Full column checks, gameplay,
rendering and save/load verification are recorded there. The user confirmed no
existing saves: no legacy generator or migration path is retained.

**World diagnostics and tin (2026-10-07):** [67 — World generation diagnostics](docs/00_dev_roadmap/67_world_generation_diagnostics.md)
records the actual-block surface census, current layout debug measurements, and
tin's 0.66 → 0.64 threshold correction. Four-seed before/after resource samples,
eight-seed gameplay checks and a native debug capture pass. Broader resource
balance remains a separate decision.

**Caves and discovery (2026-10-07):** [68 — Caves and discovery](docs/00_dev_roadmap/68_caves_and_discovery.md)
adds connected dry chambers, existing exposed veins and occasional floor-soil
patches. Mining into a cave reveals its connected system; ordinary slicing keeps
it concealed. **Development → DEV: Cave explorer** provides outlines,
camera/slice focus and temporary interior lighting without changing discovery.
The document records playtest steps, verification and deferred cave content.

**Resource review (2026-10-08):** [69 — Resource distribution review](docs/00_dev_roadmap/69_resource_distribution_review.md)
records resource measurements with caves, full-resolution deep-gem counts and
the diamond threshold correction (0.90 → 0.91) that restores emerald at Y5–12.
Eight-seed checks pass. Large connected metal deposits motivated the subsequent
prototype and integration passes below; this audit preserved ore noise, depth
bands and temporary testing drop rates.
The user deferred the additional manual cave checks to proceed with this review.

**Ore shape prototypes — offline only (2026-10-08):** [70 — Ore vein prototypes](docs/00_dev_roadmap/70_ore_vein_prototypes.md)
compares current deposits, a finer shared field, and separate metal fields with
broader coal on the same eight seeds. Separate fields were the recommended
direction for smaller metal patches, with gold/tin abundance flagged for review.
Tools and measured sections are available for comparison. Live generation,
resource rules and drops were not changed by this prototype study.

**Independent ore fields — live (2026-10-08):** [71 — Independent ore fields](docs/00_dev_roadmap/71_independent_ore_fields.md)
integrates smaller separate metal patches with broad coal. All field settings
and fitted cutoffs live in BlockRegistry's `block_resources.json`; gem/soil
selection, depths, drops and terrain shape remain unchanged. Eight seeds set
the cutoffs and eight additional seeds check abundance. This supersedes the
shared-metal-field tuning rules above; final economy balance remains open.

**Surface details — stones and seasonal plants live (2026-10-08):** [72 — Surface details plan](docs/00_dev_roadmap/72_surface_details_plan.md)
records the numbered asset, placement, clearing and verification sequence for
boulders, scree, shrubs, flowers and lakeside reeds. [73 — Boulder pilot](docs/00_dev_roadmap/73_boulder_pilot.md)
implements three boulder variants, deterministic placement, worker clearing and
persistent removal. Click a visible boulder for inspection. Eight-seed layout,
clearing, forestry regression and save/load checks pass.
**Orders → Clear stones** supports boulders and gatherable scree with click/rectangle
designation and live counts; Cancel orders, Undo and View order keep partial work.
[74 — Gatherable scree](docs/00_dev_roadmap/74_gatherable_scree.md) adds three low,
walkable clumps at cliff bases. Three seconds of hand gathering yields one rough
stone, with persistent removal and automatic construction/support displacement.
Click loose-stone clumps to inspect them. Worker, eight-seed, Orders and save checks pass.
[75 — Seasonal wild shrubs](docs/00_dev_roadmap/75_seasonal_shrubs.md) adds blueberry,
elderberry and wild strawberry with four-season voxel art, picked-crop variants,
deterministic habitats and nonblocking single-tile support. **Harvest plants**
keeps plants for one crop per eligible season; **Clear shrubs** permanently removes
them and yields one cutting (100% for all three species, configured in JSON).
Cutting growth subsequently shipped in milestone 80 below. Separate partial work, harvested cycles and removals persist.
Click shrubs to inspect them. Worker, native Orders, eight-seed and full
save/load checks pass.
[76 — Seasonal wildflowers](docs/00_dev_roadmap/76_seasonal_wildflowers.md) adds three
small clump variants with four seasonal appearances and deterministic grassy
habitats. **Clear plants** now covers shrubs and flowers; flower clearing takes
1.5 seconds, yields no items and persists through seasons/load. Building and
support loss also remove flowers. Click flower clumps to inspect them.
Worker, mixed Orders, eight-seed and full save/load checks pass.
[77 — Seasonal reeds](docs/00_dev_roadmap/77_seasonal_reeds.md) adds short/tall clumps
with four-season voxel art on dry lake/tarn banks near the actual local waterline.
**Clear plants** includes reeds: 1.5-second hand clearing, no yield, persistent
removal and partial work. Click reed clumps to inspect them. Native lake/tarn,
worker, mixed Orders, eight-seed, regression and full save/load checks pass.
[78 — Combined surface-detail review](docs/00_dev_roadmap/78_surface_detail_review.md)
records twelve-seed placement/persistence checks and four-seed native comparisons
against worlds with details disabled. Current density and art scales are retained.
Seasonal refresh enqueue work drops from about 9.8 to 3.2 ms with the same plant
identities and pending order. Broader season-rebuild spikes, also present with
details disabled, remain documented performance follow-up. This completes the
five-category surface-detail plan; larger populations need a fresh review.
[79 — Move and uproot mature shrubs](docs/00_dev_roadmap/79_shrub_transplanting.md)
adds inspector **Move / Uproot** and **Place → Plants** for the three mature berry
shrubs. Exact plant identity, crop state, seasonal packed art and unfinished work
survive carrying, storage and save/load. Moving grants no fruit or cutting;
Clear plants still yields its guaranteed cutting. Native worker/UI, storage,
inventory and complete save/backup checks pass.
[80 — Shrub cutting growth](docs/00_dev_roadmap/80_shrub_cutting_growth.md):
**Place → Plants** consumes one cutting per young shrub;
JSON defines 3/4/3 growth days and seasonal rates, with winter dormancy. Twelve
young seasonal GLBs, saved player-created identities and **DEV: Grow to maturity**
are live. Native worker/UI, split-crate, storage, seasonal growth and full
save/backup checks pass. Farm plots and honey remain later milestones.
[81 — Surface worker selection](docs/00_dev_roadmap/81_surface_worker_selection.md)
fixes distant idle dwarves winning shrub, tree and surface-clearing jobs by queue
order. New work compares eligible idle workers at reachable adjacent work cells,
with resumable ranking/probes, priorities and existing assignments preserved.
Multi-worker and hauling/planting/crafting/mining regressions pass.
[82 — Shrub Move handoff](docs/00_dev_roadmap/82_shrub_move_handoff.md) closes the
remaining gap between uprooting and the separate pickup/carry/replant lease.
An available uprooter already beside the packed plant continues the Move;
reachable nearby replacements handle interruption or unavailability. Two-worker
full-Move, equal-distance, budget, cancellation and blocked-route checks pass.
[83 — Shrub planting animation](docs/00_dev_roadmap/83_shrub_planting_animation.md)
replaces stationary planting work followed by set-down with one immediate
reach/lower/release action. Mature shrubs take 1.25 seconds, configured in JSON;
cuttings retain three seconds with continuous animation. Native captures and
timing, interruption, planting, hauling, furniture and crafting checks pass.
[84 — Juniper berry harvesting](docs/00_dev_roadmap/84_juniper_berry_harvesting.md)
adds one autumn crop from standing mature/ancient junipers (2/4 berries; three
seconds, all in JSON). Inspector and Harvest plants support picking, with mixed
shrub/tree rectangles, cancellation and Undo. Saved crop cycles, separate work,
eight berry-free GLBs and nearby-worker selection pass focused/native/save tests.
[85 — Plant habitats, spacing and flower relocation](docs/00_dev_roadmap/85_plant_habitats_spacing_flowers.md)
restricts wild berries to soil below Y44, allows cultivation on soil at any height,
and reserves nonoverlapping 3×3 areas for bushes, flowers and pending/cutting
plants. Flowers now support Move/Uproot/storage/Place with exact variant and
seasonal packed art. JSON bloom seasons and planted-clump queries prepare the
future honey connection; native, eight-seed and full save checks are recorded.
[86 — Rudimentary ladders](docs/00_dev_roadmap/86_rudimentary_ladders.md)
adds Worker-crafted wooden sections at the crude workbench: one raw log per
exactly four blocks of height, with no extra top cap. Place → Access previews
the full route/cost; workers
carry and install from below. Explicit rung navigation supports climbing and
hauling, safe interruption, section recovery, and saved partial construction.
The document records native, gameplay, storage, UI and save/backup checks.
The player confirmed the final ladder correction and a staircase made by mining.

[87 — Placement over storage hauling](docs/00_dev_roadmap/87_placement_over_storage_hauling.md)
keeps owned furniture available in Place while reserved for storage or being
hauled. Confirmed placement takes priority; a dwarf already carrying the packed
item continues directly to installation. Paused UI, ownership, cancellation,
storage relocation, plant/ladder regressions and save checks are recorded there.

[88 — Ladder task reachability](docs/00_dev_roadmap/88_ladder_task_reachability.md)
fixes tall ladder routes passing DEV Walk but failing mining assignment. Shared
reachability searches resume within scheduler budgets; unfinished searches do
not trigger unreachable backoff. The follow-up handles isolated natural cliff
shelves by searching all exact mining stands and handing the proven route to
the worker. The reported seed's 32-block zone now completes automatically.
Native climbing/mining, route invalidation,
worker-selection, hauling, placement and save checks are recorded there.

**Required later connection:** wildflowers must support honey production through
nearby seasonal forage; beekeeping must account for bloom state and clearing.
The proposed design and unresolved tuning are recorded in [42 — Beehives](docs/40_economy_colony/42_farming_brewing.md#required-future-connection-wildflower-forage).
This honey connection is not implemented yet.
Resource placement remains depth-based for now, as agreed with the user.

**Worker crafting (2026-10-07):** [64 — Worker crafting](docs/00_dev_roadmap/64_worker_crafting.md)
records the timber → crude workbench/stump → wooden torch loop, Craft menu,
batch/maintain orders, Pine-default wood choices, four-side access and axe sounds.
First benches are crafted at the timber pickup spot; inspector destinations use
the actual work position. Physical cargo and partial work survive interruptions/load.

**Loose items and explorer correction (2026-10-07):** [63 — Loose item support and explorer](docs/00_dev_roadmap/63_loose_item_support_and_explorer.md)
records settling after mining removes support, repair of hovering loose goods on
load, safe pickup interruption, and the shared cabinet styling for Object explorer.

**Entrance lighting follow-up (2026-10-07):** [24 — World rendering](docs/20_player_interface/24_world_rendering.md)
records the longer entrance fade and actor lighting across solid cells. Movement
clipping was separately recorded as [Issue 002](docs/00_dev_roadmap/00_open_issues.md),
provisionally closed by Alen on 2026-10-12; reopen only if reported again.

**Storage follow-up (2026-10-06):** [59 — Storage filters](docs/00_dev_roadmap/59_storage_filters.md)
records the shared storage inspector, exact/category rules, relocation ownership,
save compatibility, and runtime/native UI verification.

**Hauling follow-up (2026-10-06):** [60 — Hauling worker selection](docs/00_dev_roadmap/60_hauling_worker_selection.md)
fixes newly idle cutters losing nearby lumber to older idle entries or returning
haulers that bypassed worker selection after depositing.

**Colony overview follow-up (2026-10-06):** [61 — Colony overview](docs/00_dev_roadmap/61_colony_overview.md)
combines the compact dwarf roster and shared personal details in one window.

**Separate zones navigation (2026-10-06):** [53 — Navigation](docs/00_dev_roadmap/53_hearth_iron_navigation.md)
records the navigation foundation, dedicated Rooms button, Orders/Zones split and
lower active-tool banner.

**Tunnel lighting (2026-10-06):** [24 — World rendering](docs/20_player_interface/24_world_rendering.md)
records live roof-aware skylight, placed lights, entity shading, slice invariance,
door occlusion and the accepted fog/darkness correction, with native/save-load
verification. Visibility only; dwarf work is unchanged.

---

## Project Identity

| Field | Value |
|---|---|
| Engine | Godot 4.x |
| Language | GDScript |
| Genre | Subterranean colony-builder RTS |
| Core loop | Dig → Brew → Trade |
| Perspective | Top-down RTS only (no WASD direct control) |
| Godot install path | `S:\STEAM\steamapps\common\Godot Engine` |

---

## Document Map

### 📁 Core Foundation — `docs/10_core_foundation/`

| File | Read before you… |
|---|---|
| [`11_overview.md`](docs/10_core_foundation/11_overview.md) | Start any work at all. Contains the invariant design boundaries. |
| [`12_world_grid.md`](docs/10_core_foundation/12_world_grid.md) | Touch block storage, chunk loading, JSON static data registries, registry lookups, or save files. |
| [`13_architecture.md`](docs/10_core_foundation/13_architecture.md) | Add or modify Autoloads, Autoload registration, boot sequence, JSON file-loading systems, or serialisation logic. |

### 📁 Player Interface — `docs/20_player_interface/`

| File | Read before you… |
|---|---|
| [`21_camera.md`](docs/20_player_interface/21_camera.md) | Work on the camera rig, orbital controls, or layer slicing. |
| [`22_mouse_input.md`](docs/20_player_interface/22_mouse_input.md) | Implement raycasting, voxel selection, or drag-to-select. |
| [`23_user_interface.md`](docs/20_player_interface/23_user_interface.md) | Build or modify any UI panel, counter, toast, or labor window. |
| [`24_world_rendering.md`](docs/20_player_interface/24_world_rendering.md) | Work on fog, sky, atmosphere, world-edge treatment, or the slice view's visual behaviour. |

### 📁 Simulation & Systems — `docs/30_simulation_systems/`

| File | Read before you… |
|---|---|
| [`31_task_system.md`](docs/30_simulation_systems/31_task_system.md) | Add task types, change priorities, or modify the worker polling loop. |
| [`32_navigation_3d.md`](docs/30_simulation_systems/32_navigation_3d.md) | Modify pathfinding, walkability rules, or step-assist logic. |
| [`33_water_simulation.md`](docs/30_simulation_systems/33_water_simulation.md) | Touch springs, rivers, water volume/levels, flooding, irrigation or water rendering. |
| [`34_temperature.md`](docs/30_simulation_systems/34_temperature.md) | Work on room sealing, heat sources, the aging cellar temperature check, or food preservation. |

### 📁 Economy & Colony Content — `docs/40_economy_colony/`

| File | Read before you… |
|---|---|
| [`41_dwarf_agents.md`](docs/40_economy_colony/41_dwarf_agents.md) | Work on dwarf stats, needs, state machine, or skill system. |
| [`42_farming_brewing.md`](docs/40_economy_colony/42_farming_brewing.md) | Add crops, recipes, farm logic, or plant visual meshes. |
| [`43_mining_materials.md`](docs/40_economy_colony/43_mining_materials.md) | Add block types, change noise generation, or touch collapse logic. |
| [`44_crafting_workshops.md`](docs/40_economy_colony/44_crafting_workshops.md) | Work on the Smelter or Forge workshops, Blacksmith/Weaponsmith/Armorsmith professions, metalworking recipes, or ingot stockpile logic. |
| [`45_wildlife.md`](docs/40_economy_colony/45_wildlife.md) | Work on rabbits/deer/wolves/ducks, wildlife needs, ground/swim/flight navigation, flocks, hunting, spawning, inspection or future food connections. |

### 📁 World Events — `docs/50_world_events/`

| File | Read before you… |
|---|---|
| [`51_visitors.md`](docs/50_world_events/51_visitors.md) | Work on live wildlife arrival events and `WorldEventDirector`, or planned merchants, travelers, invaders, taverns and combat triggers. |
| [`52_combat_military.md`](docs/50_world_events/52_combat_military.md) | Work on military professions, the Armory room, enlistment/arming flow, patrol routes, invader waves, or combat resolution. |

### 📁 Asset Creation — `docs/60_asset_creation/`

| File | Read before you… |
|---|---|
| [`61_voxel_art_guide.md`](docs/60_asset_creation/61_voxel_art_guide.md) | Find existing asset specifications, naming, historical voxel pipelines and family dimensions. Read 63 first for the current shared art direction and export rules. |
| [`62_furniture_catalog.md`](docs/60_asset_creation/62_furniture_catalog.md) | Plan a furniture or decoration milestone, or pick the next asset batch. Full Deepdraft furniture inventory (status per piece) compared against Stonehearth's catalogue (enumerated from source 2026-07-11), with the variant strategy and archetype gap list. |
| [`63_shared_art_standard.md`](docs/60_asset_creation/63_shared_art_standard.md) | Author, review or convert world art. Approved form/palette rules, world-unit exports, material ownership, family anchors, acceptance workflow and integration status. |


---

## Session Start Protocol

> **On every new session, read ALL files listed in the Document Map below using the `Read` tool before performing any work. Do not rely on shell directory listings to discover files — use the paths listed here directly.**

---

## Hard Rules (Never Violate)

These constraints appear in individual documents but are listed here for quick reference:

1. **Bedrock Protocol**: Never allow any action to modify or mine `Y = 0`. (`12_world_grid.md`)
2. **RTS-only camera**: No first-person, no WASD direct control. (`11_overview.md`)
3. **Block ID format**: Save files store namespaced strings, never runtime integers. (`12_world_grid.md`, `13_architecture.md`)
4. **3-block dwarf nav clearance**: Dwarf pathfinding requires 3 empty air blocks above every floor node. (`32_navigation_3d.md`) Wildlife uses separate species clearance; never relax dwarf NavGrid for animals. (`45_wildlife.md`)
5. **Single-tile plant footprint**: Plant visual overhangs must never have collision shapes. (`42_farming_brewing.md`)
6. **Visual vs logical dwarf height**: Use 3-block logical height for nav/collision, not the 3.3-block visual mesh. (`41_dwarf_agents.md`)
7. **No 3D UI elements**: All UI lives on a `CanvasLayer`. (`23_user_interface.md`)
8. **Deterministic world generation**: Generation must be fully deterministic from `world_seed`; use position-derived hashes or seeded noise, never `randi()` / `randf()` for streamed terrain identity. (`43_mining_materials.md`)
9. **Terrain identity lives in data**: Block identity must come from generated block data and JSON registries, not renderer tricks, fog, camera distance, or painted heightmaps. (`24_world_rendering.md`, `43_mining_materials.md`)
10. **Scene Decoupling Contract (recommended default)**: Prefer `@export` variables for scene references and signals for cross-node communication over explicit node paths (`$Node` / `get_node()`). The agent MAY now create and edit `.tscn` files and register autoloads / set the main scene / register `[input]` actions in `project.godot` — but keep logic scene-agnostic by default and only hardcode node paths when there is a clear reason. Never edit `.tres` or `.import` files. (`13_architecture.md`, File Ownership Rules)
11. **Slice concealment**: The normal slice view must never reveal undiscovered resources. Plane-cut floors render authored strata only; mining into a cave reveals its connected air and facing resources. The explicitly requested DEV Cave explorer is a temporary inspection exception, never saved discovery. (`24_world_rendering.md`, `43_mining_materials.md`, roadmap `68_caves_and_discovery.md`)
12. **Releasing a task is always cheap and always legal**: No task type may be designed such that abandoning it mid-way corrupts state. Release returns the task to PENDING, frees reservations, and never loses source-level progress; a future carried item is dropped at the dwarf's feet. (`16_first_dwarf_milestone.md` §2.8, `31_task_system.md`)

---

## Godot Project Structure (expected)

```
DwarfVoxel/
├── AGENT.md                  ← you are here
├── docs/
│   ├── 10_core_foundation/
│   │   ├── 11_overview.md
│   │   ├── 12_world_grid.md
│   │   └── 13_architecture.md
│   ├── 20_player_interface/
│   │   ├── 21_camera.md
│   │   ├── 22_mouse_input.md
│   │   ├── 23_user_interface.md
│   │   └── 24_world_rendering.md
│   ├── 30_simulation_systems/
│   │   ├── 31_task_system.md
│   │   ├── 32_navigation_3d.md
│   │   ├── 33_water_simulation.md
│   │   └── 34_temperature.md
│   ├── 40_economy_colony/
│   │   ├── 41_dwarf_agents.md
│   │   ├── 42_farming_brewing.md
│   │   ├── 43_mining_materials.md
│   │   └── 44_crafting_workshops.md
│   └── 50_world_events/
│       ├── 51_visitors.md
│       └── 52_combat_military.md
├── project.godot             ← agent may edit [autoload], main scene, and [input] only; leave other config to human
├── data/                     ← agent-owned JSON definitions
│   ├── biome/
│   ├── entities/
│   ├── furniture/
│   ├── professions/
│   ├── terrain/
│   ├── visitors/
│   ├── workshops/
│   └── world_gen/
├── scripts/                  ← agent-owned GDScript
│   ├── registries/           ← registry autoloads (BlockRegistry, PlacedEntityRegistry,
│   │                            DwarfAssets, UIRegistry)
│   ├── systems/              ← simulation autoloads (WorldClock, WorldData, WorldGenerator,
│   │                            NavGrid, TaskManager, InteriorTracker, RoomManager,
│   │                            SkyController, WeatherManager) + scene-node systems
│   │                            (WorldRenderer, Camera, SliceController,
│   │                            MiningDesignationController, FurniturePlacementController,
│   │                            FlagPlacementController, SurfaceFloraSpawner, ItemDropManager…)
│   │                            — authoritative autoload list + load order: docs/10_core_foundation/13_architecture.md
│   ├── components/           ← reusable logic components, no autoload (MiningZoneComponent)
│   ├── entities/             ← agent scripts (DwarfAgent, DwarfFactory, DwarfDirector,
│   │                            DwarfAppearanceData)
│   └── ui/                   ← UI logic scripts (DockUI, DebugLoadingOverlay)
└── scenes/                   ← agent may create and edit scenes (git-tracked)
    ├── main/
    ├── ui/
    └── entities/
        └── resources/
```

---

## File Naming Conventions

When creating any new file, follow the convention for its type:

| File type | Convention | Examples |
|---|---|---|
| `.gd` scripts | `PascalCase` | `MiningSystem.gd`, `BlockRegistry.gd` |
| `.json` data | `snake_case` | `terrain_blocks.json`, `aging_cellar.json` |
| `.md` docs | `NN_snake_case` (numbered prefix) | `43_mining_materials.md` |
| `.glb` assets | `snake_case` | `apple_mature_autumn.glb` |

GDScript filenames must match their `class_name` declaration exactly — this is a Godot requirement, not a style choice.

---

## File Ownership Rules

### Agent MAY read and write:
- `data/**/*.json` — all static definitions and content tables
- `scripts/**/*.gd` — all GDScript logic and autoloads
- `docs/**/*.md` — design documents
- `scenes/**/*.tscn` — create and edit scenes freely (see Scene Editing Protocol below)

### Agent MAY edit, but only for specific purposes:
- `project.godot` — the `[autoload]` section (register/reorder autoloads), the main scene setting (`run/main_scene`), and the `[input]` section (register input actions for tools/hotkeys — approved 2026-06-05; first use: the Slice tool, `11_slice_xray_plan.md` Phase 2). Do not change rendering, physics, display, or other config unless explicitly asked.

### Agent MUST NEVER touch:
- Any `.tres` file
- Any `.import` file (editor-generated on asset import; hand-editing desyncs the asset)

---

## JSON vs GDScript: The Decision Rule

> **JSON = what things are. GDScript = what things do.**

| Use JSON for… | Use GDScript for… |
|---|---|
| Block definitions and stats | Block registry loader |
| Item and material definitions | Task scheduler |
| Recipe tables | Pathfinding logic |
| Dwarf trait and skill definitions | State machines |
| Biome and noise parameters | Combat resolver |
| Visitor and invader spawn tables | Water CA simulation |
| Temperature thresholds | Signal handlers and events |
| Crafting costs and unlock conditions | Runtime behavior and AI |

If a designer could edit it in a spreadsheet → **JSON**.
If it contains logic, conditionals, or runtime state → **GDScript**.

**No custom Resource instances as data stores.** All static definitions live in JSON, loaded by a registry Autoload. Never use `.tres` files to store game data.

---

## Registry Pattern (Mandatory)

All JSON loading goes through a dedicated registry Autoload. Raw JSON file I/O is never scattered across scripts.

```
scripts/registries/
└── BlockRegistry.gd     ← loads data/terrain/terrain_blocks.json
                            and data/terrain/block_resources.json
```

Workshop, recipe, flora, and visitor data is loaded by the Autoload that owns that system (e.g. `VisitorManager` loads `data/visitors/merchant_catalog.json`). No separate registry Autoload is created for these — each system owns its own data loading.

**Rule:** No script may call `FileAccess.open()` on a JSON file directly. All data access goes through the owning registry or system Autoload:

```gdscript
# Correct
var block = BlockRegistry.get("dwarf:stone_granite")

# Never do this in a non-registry script
var f = FileAccess.open("res://data/terrain/terrain_blocks.json", FileAccess.READ)
```

---

## Script-to-Scene Contract

The agent may now author scenes, but the decoupling discipline below is still the **recommended default** — it keeps logic testable and resilient to scene reorganisation. Deviate only with a clear reason.

1. **Prefer `@export` over hardcoded node paths.** Avoid `get_node("UI/HealthBar")` / `$NavigationAgent3D` in logic scripts where an `@export` reference would do.
2. **Declare node dependencies as `@export` variables** at the top of each script. The wiring can now be done by the agent directly in the scene — it is no longer a human-only step.
3. **Signals are the preferred interface** between scene structure and script logic.
4. **Keep scripts scene-agnostic** where practical — logic should not break if a script is moved in the tree.

### Scene Editing Protocol

`.tscn` is a structured text format with fragile internal references. When creating or editing a scene:

- **Read before edit.** Always read the existing `.tscn` before modifying it.
- **Preserve UIDs.** Keep existing `uid://…` ext_resource IDs and the scene's own UID intact. Scripts are referenced by the UID stored in their `.gd.uid` file.
- **Commit first.** Prefer committing pending work to git before a large scene edit, so the change lands as an isolated, revertible diff.
- **Verify it loads.** After editing, sanity-check that every referenced resource path/UID exists and that node and `[connection]` blocks are well-formed.

```gdscript
# Correct — human wires this in the editor
@export var health_bar: ProgressBar
@export var nav_agent: NavigationAgent3D

# Never do this
func _ready():
    var health_bar = get_node("UI/HealthBar")
```

### Playtest Handoff Note

Godot caches global script classes. After any work session that **adds a new `class_name`
script or registers an autoload**, tell the human to run **Project → Reload Current
Project** before playtesting — a stale cache half-loads the changes and produces ghost
bugs (first hit: doc 16 autoloads; second: doc 19 Phase 3, where pending tasks were
silently never assigned until the reload). Sessions that only edit existing scripts don't
need it.
