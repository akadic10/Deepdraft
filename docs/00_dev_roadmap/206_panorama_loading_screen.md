# Panoramic loading screen

2026-10-17. The user requested concept art during loading, no gameplay HUD,
16:9 / 21:9 / 32:9 support that reveals more scenery at the sides, and a small
beer-themed progress indicator. The world must remain covered until the complete
overview finishes, corresponding to the renderer's 1,024-tile completion log.

`WorldLoadingScreen` is the last scene-owned CanvasLayer in `debug_world.tscn`.
It covers the first rendered world frames, hides existing gameplay CanvasLayers,
consumes input and takes a transient WorldClock loading hold. Camera key polling
and edge scrolling respect that hold. Normal camera settling and all generation,
mesh uploads and restored scenery preparation continue. No new autoload or global
script class was introduced. The old DebugLoadingOverlay remains the separate
World info diagnostics window.

The gate reads live owner state, never console text or a fixed loading duration:
generator maps and requested columns are complete; the entire overview is built
with no queued/in-flight tiles; terrain additions/cavity shells, water meshes and
underground lighting are settled; trees, ground details and wildlife have finished
initialization; restored seasonal art has caught up; SaveManager is no longer
restoring. Three quiet frames and a brief filled-mug presentation precede reveal.
The earlier near-camera radius milestone cannot dismiss it. Scene reload creates
a fresh loading screen; ordinary terrain edits after reveal do not reopen it.

Progress combines actual completed generation phases and overview tile coverage,
with the final portion reserved for scenery/restoration. It never counts time
toward completion. The mug fills upward with amber beer, foam and subtle bubbles;
a slim companion bar and percentage report the same progress. Quiet animated
dots indicate activity during long generation phases. Player-facing copy contains
no renderer diagnostics. UIRegistry owns `data/ui/loading_screen.json`.

`LoadingArtwork` draws one fixed-height 32:9 band from the panorama and clips its
left/right sides for narrower viewports. There is no stretching, letterboxing or
aspect-dependent vertical reframing at the supported ratios. The main gate,
bridge and dwarves remain in the central 16:9 composition. The lower margin has
a smooth dark gradient for legibility. The title and progress indicator remain
centered and scale with display height.

The original image was generated with the built-in imagegen tool and copied into
`assets/ui/loading/mountain_settlement.png`. Its exact prompt is saved beside it
in `mountain_settlement.prompt.txt`. The original 2103×748 image remains intact;
Godot selects its centered panoramic band at runtime. It depicts a lantern-lit
dwarven mountain gateway, workers, a river/bridge and forests extending outward.
The beer indicator is native 2D drawing, so its fill remains live and crisp.

WorldClock separates the saved player pause preference from transient loading
holds. Restoring a running save cannot resume actors behind the screen, and
capturing state never records the hold as the player's pause choice. Hold
acquisition/release is idempotent; reveal and early scene teardown release it.
Previous HUD visibility is restored, including leaving World info closed.

All five validation fixtures pass in native source-project runs with isolated
save directories and zero script/runtime errors:
LoadingArtworkTest checks crop geometry and captures 1280×720, 1680×720 and
2560×720 plus empty/full mugs. WorldLoadingScreenTest checks first-frame coverage,
hidden HUD, blocked pause/pan input, frozen time, the early-radius milestone,
all 1,024 tiles, final water/scenery/light readiness, monotonic progress, save
reload, saved pause state and early teardown. Actual startup was also captured
at the user's 7680×2160 fullscreen resolution. WorldTerrainStartupTest exercises
full-map coverage, local changes, stale async results and restored slices;
SaveManagerRoundTripTest covers scene contents, paused saves and backup recovery.
SeasonalRefreshTest covers paced natural transitions and immediate restored art.
Known fixture startup warnings and intentionally corrupt-save recovery warnings
remain distinct from script/runtime errors. Full-resolution captures remain in
`tmp/loading_screen_20261017/`; the evidence bundle retains the three smaller
aspect previews and capture dimensions/hashes.

The initial import caught two untyped dynamic booleans; explicit types resolved
them. Visual review also caught overlapping gradient strips, replaced with a
smooth interpolated polygon. Final native captures were reviewed at all three
aspect ratios. Results, compressed logs and screenshots are retained in
[the evidence summary](concepts/loading_screen_20261017/summary.json).

## Underground alternative (2026-10-17)

Added `assets/ui/loading/underground_settlement.png` with the built-in imagegen
tool; the exact prompt is in `underground_settlement.prompt.txt`. The new scene
depicts a cavern settlement with carved halls, workshops, dwarves, warm firelight
and an underground stream. The original mountain panorama remains byte-for-byte
unchanged (SHA-256 `1dbb06e75125e3f4ec0da2cebf70969f82aeb5c3f9a7aabc97cc3123d8ca1a90`).

The JSON now owns a `backgrounds` list. Each new WorldLoadingScreen chooses one
entry uniformly, once in `_ready`, using a private randomized RNG so presentation
does not consume the simulation's random stream. Both startup and save reload
therefore make a fresh 50/50 selection; consecutive loads can choose the same art.
Only the selected texture is loaded. Readiness, HUD hiding, progress and crop
geometry retain their existing behavior.

Both targeted native fixtures pass: LoadingArtworkTest loads both assets and
checks/captures each at 1280×720, 1680×720 and 2560×720. The three underground
captures were visually reviewed for composition and indicator legibility.
WorldLoadingScreenTest verifies a configured image is selected and stays fixed
throughout startup and save reload, alongside its existing readiness/HUD checks.
There are no script/runtime errors; isolated fixture startup warnings remain.
Results, compressed logs and the new aspect previews are in
[the follow-up evidence](concepts/loading_variants_20261017/summary.json).

Restart Play. No Windows export or playtest package was created or updated.
