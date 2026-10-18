# Torch reach and construction size

2026-10-17. The player requested farther-reaching torches with a gentler
transition to darkness, and construction drags wider than the existing 16 limit.

Both **Log torch** and **Wall Torch** now have a **20-voxel light radius**, up
from 12. Their existing 0.6 attenuation stretches the native smooth outer fade
over the larger area. No additional shader cutoff or room-wide ambient fill is
introduced. Light energy stays at 2.6 / 3.2 respectively; colour, flame flicker,
shadows and heat remain as authored. Existing installed lights adopt the updated
furniture definition on scene reload.

**Stone block**, **Simple plank floor** and **Simple stone floor** now allow
**32×32** construction footprints in either drag direction. Endpoints beyond
that span clamp to 32 cells per horizontal axis. Stone height remains adjustable
from 1–8; floor previews remain one layer. Slice clipping, obstacle validation,
material costs, per-voxel work and floor worker availability are unchanged.
All tuning lives in the existing furniture and construction JSON definitions.

Native Godot 4.7.2 / Forward+ / D3D12 verification:

- `TorchReachTest` renders both real torch models/lights through the production
  underground material. With flicker frozen, it compares the previous 12 radius
  to the new definition at quarter-voxel intervals. Floor samples remain lit at
  16 and faintly at 18 voxels; 22 is back to the unlit baseline. The maximum
  outer brightness drop per quarter voxel falls from 0.01110 to 0.00448 for log
  torches and 0.01259 to 0.00569 for wall torches. A solid wall still returns the
  far-side sample to the unlit baseline. Before/after captures were inspected.
- `BedroomLightingTest` passes in the generated source world: a furnished room
  remains readable with its installed torch, the closed door blocks light into
  the corridor, and the room becomes dark when the torch is hidden.
- `ConstructionInputTest` retains its menu, inspector, slice, wall-picking and
  layout checks, and now drags oversized 40×40 areas in both directions for all
  three construction tools. Each preview and committed order contains exactly
  1,024 cells at the expected 32×32 bounds; cancellation releases each order.

Captures, profiles and final native logs are in
[the evidence folder](concepts/torch_reach_20261017/summary.json).
The torch profile is an isolated surface comparison; the bedroom test supplies
the full-world regression. No broad performance benchmark was run.

Restart Play to load the definitions. No new global class, autoload, save schema
or Windows playtest export.
