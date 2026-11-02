# 278 — Peeled logs

From the owner, 2026-10-28: watching log-cabin videos, "people always seem to remove the
bark". The owner asked for a review of the fence post, the gate and the upright and
horizontal built logs, and a direction for them. The proposal page "Peeled Logs" compared
today's pieces with two peeled looks, rendered from real cells in the studio and in a copy of
the owner's colony. The owner chose **A, peeled**, with every recommendation: flat-topped
posts, the gate's hinge on the post's face, stockpile logs keeping their bark, and only these
four pieces.

Built 2026-10-28. The owner's look in Play is next.

## Why

- Log builders strip the bark before a log goes into a wall or a fence. Bark holds water
  against the wood and hides beetles, then loosens and falls away in patches. Peeling is
  hand work with a drawknife or a bark spud, so it fits Tier 1.
- Barked walls were the same brown as the tree trunks, so a cabin sank into the forest at
  the default camera distance. Three bark plates a block also repeated across a wall as a
  grid of squares. Peeled walls read as built, as one warm shape with clear courses.
- The stockpile log keeps its bark: it is the log as felled, and the bark comes off when the
  dwarves build with it.

## What changed for the player

- **Built logs** (Build → Wood, upright and horizontal) are peeled in all four woods, with
  the same shape, size, pieces and joints:
  - the surface is each wood's peeled colour: oak amber, pine gold, juniper rose-grey,
    apple warm rose;
  - on a lying log the upper corner steps are lit and the lower ones shaded, so each course
    reads apart in a wall;
  - knots trimmed flush and drying checks replace the bark plates, never on a lying log's
    top, which the play camera sees most;
  - the ends keep their ring, pith and drying split, with a peeled rim, and notches show
    fresh-cut wood.
- **Log Fence Post:** a peeled pole, 6 × 6 cells (it was 4 × 4) and 20 cells tall, with an
  earth-dark foot, a knot, a drying check and a flat top showing its rings. The rope bands
  are gone: the rails go straight into the posts.
- **Rails:** peeled split poles, 4 × 3 cells, split face up, at Y5 and Y14.
- **Log Gate:** peeled stiles with chopped tops and two split rails at the fence's heights.
  One brace, 2 cells tall, is laid over the front from the hinge's foot to the latch's
  head. Rope ties the hinge stile and loops the latch, two pegs pin the brace, and a one-cell
  gap at the latch shows the leaf swings free.
- **Menu pictures:** Build's eight log pictures, the Place pictures of the post and the
  gate, and Zones' Animal pasture icon, which shows a corner of the fence. Build's own icon
  (the dock's Build button) shows a peeled log in its wall, where it still showed the plank
  block that doc 275 retired (owner, 2026-10-28).

## How it works

- `tools/voxel_assets/built_logs.py` has the peeled recipe: the `riven_dark` body
  (`hewn_peel`), `riven` and `pith` corner facets, knots and checks by variant (`KNOTS`,
  `CHECKS`), a peeled end rim and `wood_top` shoulders. The 80 pieces of
  `construction/logs.glb` keep their names (`_p0` to `_p3` are now mark variants), so
  `BuiltLogs.gd` is unchanged.
- `fencePost`, `fenceRails` and `gateLeaf` in `tools/hearthblock/art/tier1.mjs` are the peeled
  pieces. Their rows in `write_data.py` use the `hewn` palette, and `log_fence.json` and
  `log_gate.json` name `hand_hewn_timber`, the built logs' source palette. A pine fence now
  matches a pine cabin exactly.
- The wider posts put the leaf's hinge stile at the post's face: `hinge_inset` in
  `log_gate.json` went from 0.14 to 0.1875. The opening and every fence rule are unchanged.
- In `icons.mjs`, the Build icon's `logCube` (a peeled log at the loose log's 12-cell
  size) replaces `woodCube`, which only that icon used. The plank colours stay for the
  Carpenter icon.
- The peeled colours were already in every wood's palette (`hewn_peel`, the furniture's riven
  grain lines), so no colour was added.
- Each piece is cheaper: a single log is 448 triangles (614 before), because the plates'
  cut grooves are gone.

## Saves

Nothing saved changed: block IDs, furniture keys and origins are the same.

## Checks

- The peeled pieces in `built_logs.py` match the approved study cell for cell (all 80).
- `build.py furniture` and `construction` were reviewed in the gallery, installed and
  imported, and `--check` regenerates them byte for byte. The voxel Python tests pass
  (65); `test_furniture.py` now pins the 6 × 6 post and the new rail rows.
- The art tests pass (9/9; `FurnitureArtTest` checks the hand-hewn recolour in all four
  woods and the new hinge), the construction tests (17/17) and `UiIconDataTest` and
  `ToolBarTest`. The job gate passes (55/55), and the lint finds nothing new.
- Seen in the game on a copy of the owner's 27 October autosave, isolated, nothing saved:
  the Log cabin starter built for real, a yard of eleven pine posts with nine rails and a
  gate, the gate swung open, and the colony's own log building drawn peeled.
- Not checked: winter snow, night and torch light, and the underground slice view.

The proposal's renders and study scripts are in `tmp/peeled_logs_20261028/`.
