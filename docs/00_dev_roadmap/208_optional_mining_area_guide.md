# Optional 32×32 mining guide

2026-10-17. The player requested removal of the automatic per-voxel outlines,
replacing them with an optional guide for digging even areas.

**Orders → Mine blocks** now opens without terrain grid lines. Its mode controls
include a **32×32 mining guide** toggle, off by default. The choice is retained
when leaving and reopening the tool; a newly loaded scene starts with it off.
The guide is visible only during mining. It is an alignment aid and does not
snap, resize or change designations, existing orders or the mining cursor.

The guide marks world X/Z multiples of 32, anchored at the world origin. Its
warm, depth-tested ribbons are 0.16 voxels wide, with no shadows. Each side of a
boundary follows its own visible terrain height; a perpendicular cliff receives
a continuous vertical stripe. Slice changes, planned cuts and completed mining
update the visible surfaces through the existing mining overlay lifecycle.
The old individual top/side voxel-outline emitters have been removed.

Only columns touching a 32-block boundary are sampled. Coverage follows camera
position and zoom, expanding for ultrawide aspect ratios. Stationary views reuse
their mesh. Disabling the toggle or leaving mining clears it, and disabled guides
do not rebuild geometry in response to terrain changes. Geometry tuning remains
in the existing mining owner's `data/terrain/mining_config.json` configuration.
The toggle lives in `OrdersShelf`; no new scene, global class, autoload or save
schema is required.

Native source validation extends OrdersShelfTest with actual toggle clicks,
default-off state, world alignment and thickness, panning/cache behavior, slice
height, mined floors, cliff stripes, tool switching and disabled invalidation.
Its input and layout regression checks cover 960×540, 1280×720, 1680×720 (21:9),
2560×720 (32:9) and 2560×1440, including moved inspectors. ConstructionInputTest
and MiningFeedbackTest cover neighboring controls and existing work feedback.
The rendered [off](concepts/mining_guide_20261017/guide_off.png) and
[on](concepts/mining_guide_20261017/guide_on.png) captures were inspected.
Results and logs are in [the evidence summary](concepts/mining_guide_20261017/summary.json).

Restart Play. No Windows playtest was created or updated.
