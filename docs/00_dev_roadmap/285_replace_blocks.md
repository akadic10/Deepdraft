# 285 — Replacing blocks

2026-10-29. Built (phase 1). The owner's look in game is next.

From the owner: "we might encounter a block we may not like and want to replace it with a
normal stone or dirt block, how should we give the player this option". The owner took the
recommended design: "Build it as recommended".

## What was there

- **Two orders.** Mine blocks, wait until the dig is done, then Build into the hole. Build
  refuses a solid cell ("Mine existing terrain before building").
- **Built blocks already pass for untouched ground.** Built stone becomes the natural rock of
  its layer, and built dirt and grass are the world's own (doc 43, "Built blocks"). Replacing
  needs no new block types.
- **Milestone 127 left "combined replacement" out** (changelog, 2026-10-12). It was never
  ruled out. Wall facing, which covers a block instead of removing it, stays excluded;
  Replace takes the old block out.

## Decisions (owner, 2026-10-29)

1. **Replace is a switch on Build**, not a tool of its own or a choice on Mine blocks.
2. **The block's own panel** (the card a click on terrain opens) gets a Replace action.
3. **One job per block, not mine-then-build.** The cell never opens.

## How it plays

- **Build → Replace (F, or the switch on the tool bar).** A click or drag picks the blocks you
  point at instead of the air in front of them, and the material row (Q and E, and Stone's and
  Wood's menus) says what goes in. The tool bar names the tool Replace while the switch is on.
  Height reaches up a wall as it does for building; the tag counts the blocks and their goods
  against the stock, Undo takes the plan back, and Ctrl + drag takes blocks out of plans.
- **Only the blocks you can see.** A block needs an open face: air or water the colony knows,
  beside it. A drag across a wall takes its face, never the rock behind it, and a cave or
  deposit the colony hasn't found reads as the rock around it (Hard Rule 11).
- **Blocks that already match are left.** Stone leaves natural rock (built stone is its
  layer's rock), dirt leaves dirt, grass leaves grass, and a log leaves a log of the same wood.
  So one drag of stone across a whole wall swaps out only its ore, gem and soil spots.
- **The block's panel** lists Replace when the block can be replaced. It opens a list of
  Build's materials, each as its chosen type with its stock; picking one plans that block at
  once and shows the plan. It does not open the tool: the pointer is on the panel, not the
  block.
- **The plan** is an ordinary construction plan, named "Replace with native stone" and so on:
  blue over the blocks, one materials crate, its Materials card, Cancel and the DEV finish.

## The work

- **The goods come first.** As with every plan, a builder starts once all of a good is in the
  crate. A colony short of stone leaves the wall untouched, never a row of holes.
- **One job per block.** The builder stands beside the block, digs it with the pick for its
  mining time (its hardness, as Mine blocks counts it), then hammers the new block in for the
  material's build time. The swap is one terrain write: the cell is solid before and after.
  - Water beside it can't get in, nothing on it is left floating, nobody steps into a hole,
    and nothing behind it comes to light.
  - **The old block drops what mining it would**, at the builder's feet, since its own cell
    stays solid: copper ore at copper's chance, a log its log, rough stone at rock's.
  - Miner experience doesn't shorten the dig; it is building work at its base time.
- **Release is cheap (Hard Rule 12).** Nothing changes before the swap. An interrupted
  builder keeps the plan's progress on that block, as builders do.
- **A block that changes under the plan leaves it.** Mined out, or made to match, it is taken
  out of the plan as Ctrl + drag would take it, and the crate gives back what it no longer
  needs.
- **What it refuses:** bedrock and the bottom layers (y ≤ 3), air and water, a block marked
  for mining, a block already planned, grass anywhere but under open sky, and a block with no
  open face.

## Saves

A replace plan saves `"replace": true` with its cells and their progress. The swapped blocks
are ordinary terrain edits.

## Built (2026-10-29)

- **`ConstructionController`:** the switch (`_replace`, F, the bar's name and its keys),
  `replace_reason`, `open_face`, the panel's `replace_options` and `replace_block`, a replace
  plan's origin at a builder's floor (so its crate is sought where a builder stands, not inside
  a wall), the drop at the builder's feet in `commit_block`, and `_sweep_replaced` for blocks
  that change under a plan. A plan is the ordinary `create_order` with `replace`.
- **`ConstructionWork`:** `replace`, the dig before the hammer (`work_seconds_of`,
  `dig_seconds_of`, `digging`, `hammer_progress`), `blocked_reason` for both kinds of plan, and
  depth 1 for every swapped block.
- **`DwarfCarryWork` and `DwarfWorkExecution`:** the pick's pose and strikes while digging, then
  the hammer's (`_construction_work_pose`, `_construction_strike`).
- **Mining:** `MiningDesignationController.is_marked` and `spawn_block_drops` (the drop roll,
  now public in `MiningZoneWork`).
- **The panel:** `TerrainExplorerProvider` offers Replace… unless it shows the block as strata;
  `CompactObjectPanel`'s option list shows a choice's own picture; `compact_panel.json` gives
  the action Build's picture.
- **The bar:** `ToolBar` shows another entry's keys when the tool names one;
  `tool_bar.json` has `construct_replace` and F on `construct_build`.
- **Tests:** `ReplaceBlocksTest` (construction area): the rules, a drag of a row, the swap with
  a release mid-dig, a log's drop at the builder's feet, blocks changing under a plan, saves,
  the switch, and the panel's list and action. `ConstructionInputTest` (gate) drives Replace
  with the real F key and a real drag along a wall. `MiningAreaGuideTest` finds the guide by id,
  since Replace is now Build's first switch.

## Phases

1. **Build it.** The switch, the panel's list, the swap job and its animation, saves. A
   focused test (`ReplaceBlocksTest`) and the job gate.
2. **The owner's look in game.** Then the rules move into docs 23, 31 and 43, and this doc
   goes.

## Not in this milestone

- Replace in Shapes (for paths and borders inlaid in a floor) and in blueprints. A plan on a
  solid cell is also what `00_todo.md`'s "Dig and build" for blueprints needs.
- Turning a log in place: a log of the same wood counts as a match.
- A picture of its own for the panel's Replace action, which uses Build's.
