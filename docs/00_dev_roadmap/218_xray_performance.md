# 218 — X-ray update performance

The player's October 17 quicksave reproduced large frame stalls in Full X-ray.
The view itself was correct. This change preserves its appearance, discovery,
selection, lighting and slice behavior.

## Cause and correction

Every completed X-ray chunk marked the shared visible volume dirty. The normal
renderer treated that notification as a reason to rebuild its entire physical
cavity shell. Uploading a small inspection chunk therefore triggered an
unrelated colony-wide mesh rebuild on the next frame. Water updates followed
the same path and also rebuilt both inspection terrain meshes.

- `WorldRenderer` now invalidates the physical cavity directly when the actual
  slice changes. Existing terrain, designation, discovery and season paths
  continue to invalidate it. Inspection visibility still notifies overlays,
  but does not rebuild unchanged physical terrain or shadow geometry.
- `XrayController` reuses its existing Full and Flat meshes when switching
  modes. Re-entering from Off still refreshes from current world truth. Slice
  notifications also update the cached level, avoiding duplicate invalidation.
- Water-only work builds and replaces only the water mesh. Terrain meshes,
  picking sets, reference outlines and the physical cavity remain intact.

No visual budgets, quality settings, simulation rates, save schemas or geometry
rules changed. Temporary timing wrappers were removed after measurement.

## Copied-save measurement

Native Godot 4.7.2, AMD Ryzen 7 9800X3D, Radeon RX 9070 XT, **7680×2160**.
Both runs use the same copied quicksave and saved camera, slice 53 and pinned
reference 47. Vsync is disabled only in the diagnostic. Each phase samples
12 real seconds after 20 warmup frames. Initial/steady phases are paused;
the last phase resumes normal simulation. Autosaving is disabled in the copy.

| Phase | Before median / p95 / worst | After median / p95 / worst |
| --- | --- | --- |
| First X-ray build | 12.21 / 298.77 / 318.76 ms | 4.58 / 11.39 / 25.01 ms |
| Following paused view | 5.41 / 11.16 / 300.40 ms | 4.51 / 6.05 / 11.32 ms |
| Active colony | 12.38 / 27.32 / 310.16 ms | 11.86 / 26.45 / 34.99 ms |

The original first window ended with 262 queued chunks; the corrected window
ended with none. The following original window still contains initial-build
work, so it is not a comparison of two fully settled views. The main measured
gain is removal of the repeated long stalls; normal simulation still accounts
for much of the active frame time. These short observations are not a guarantee
for every colony, camera movement or terrain-edit workload.

Both full-resolution captures were inspected. Their mean absolute channel
difference is 0.168/255; 0.127% of pixels differ by more than 8 in any channel.
Flame/lighting animation was not synchronized. Floors, walls, props, lighting
and lower-level guides retain their presentation.

## Regression coverage

`XrayViewTest` now verifies that inspection uploads and mode switches preserve
physical terrain mesh identity, Full/Flat reuse their meshes, and filling or
draining a pool updates the water while retaining terrain and references.
Actual slice and terrain changes still rebuild the physical cavity. Its existing
stacked-room, discovery, selection, tool, live-edit and aspect-ratio checks remain.

Native regressions: X-ray view, time/slice HUD, terrain explorer, construction
input and bedroom lighting. Results and logs are in the evidence folder.

Evidence: [measurements, checks and save hashes](concepts/xray_performance_20261017/summary.json),
[before](concepts/xray_performance_20261017/baseline.png),
[after](concepts/xray_performance_20261017/optimized.png).
The four original save files remain byte-for-byte unchanged. Restart Play and
reload the existing save. No Windows playtest or export was produced.
