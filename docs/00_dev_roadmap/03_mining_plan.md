# 03 - Mining Tool Plan

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = keep</span> |
> <span style="color:#d29922;">Yellow = review / move to a more specific plan</span> |
> <span style="color:#f85149;">Red = safe to delete or archive once you are comfortable</span>

## Document Review - 2026-05-31

The first mining-designation slice is mostly implemented in `scripts/systems/MiningDesignationController.gd`, `scripts/ui/DockUI.gd`, `scripts/systems/WorldRenderer.gd`, and `scripts/systems/ChunkMesher.gd`.

Use this file as a mining UX/parity backlog. Delete the completed planning scaffolding once you are comfortable, keep the active behavior rules, and move performance-specific work to `04_mining_performance.md`.

---

## <span style="color:#3fb950;">KEEP - Source References</span>

These references are still useful when tuning Stonehearth-like mining behavior.

- <span style="color:#3fb950;"><strong>KEEP:</strong></span> Deepdraft input rules: `docs/20_player_interface/22_mouse_input.md`.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> Deepdraft mining/material rules: `docs/40_economy_colony/43_mining_materials.md`.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> Deepdraft mining config: `data/terrain/mining_config.json`.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> Stonehearth precision mining references:
  - `P:\stonehearth\call_handlers\mining_call_handler.lua`
  - `P:\stonehearth\services\client\selection\xz_region_selector.lua`
  - `P:\stonehearth\ui\root\js\stonehearth\stonehearth_client.js`
  - `P:\stonehearth\renderers\mining_zone\mining_zone_renderer.lua`

---
## <span style="color:#3fb950;">KEEP - Current Player-Facing Behavior</span>

Keep this as the compact current UX spec.

1. <span style="color:#3fb950;"><strong>KEEP:</strong></span> Player clicks the dock's Mine button.
2. <span style="color:#3fb950;"><strong>KEEP:</strong></span> Dock requests `mine_precision`.
3. <span style="color:#3fb950;"><strong>KEEP:</strong></span> Cursor enters mining designation mode.
4. <span style="color:#3fb950;"><strong>KEEP:</strong></span> Hovering valid terrain shows a precision mining preview.
5. <span style="color:#3fb950;"><strong>KEEP:</strong></span> Left mouse down anchors the region.
6. <span style="color:#3fb950;"><strong>KEEP:</strong></span> Dragging expands the region from the anchor.
7. <span style="color:#3fb950;"><strong>KEEP:</strong></span> Left mouse up confirms the zone and keeps the tool active for repeated designations.
8. <span style="color:#3fb950;"><strong>KEEP:</strong></span> Ctrl while confirming subtracts from existing mining zones.
9. <span style="color:#3fb950;"><strong>KEEP:</strong></span> Right-click or Escape cancels and exits mining mode.
10. <span style="color:#3fb950;"><strong>KEEP:</strong></span> Clicking a confirmed zone opens a compact `Mining Zone` window with `Remove` and `X`

---
## <span style="color:#3fb950;">KEEP - Tool Mode And Controls</span>

The first implemented tool is precision/custom-block mining only. The large snapped 4 x 4 x 4 Dig tool remains deferred.

| Setting | Deepdraft value | Source |
|---|---:|---|
| Default horizontal size | 1 block | `data/terrain/mining_config.json` |
| Default vertical size | 1 block | `data/terrain/mining_config.json` |
| Max horizontal size | 8 blocks | `data/terrain/mining_config.json` |
| Max vertical size | 8 blocks | `data/terrain/mining_config.json` |
| Max drag length | 40 blocks | `data/terrain/mining_config.json` |
| Max workers | 4 | Future mining zone execution |

| Input | Effect |
|---|---|
| Left click + drag | Designate the mining region |
| Shift + MouseWheel | Increase / decrease horizontal block size |
| Alt + MouseWheel | Increase / decrease vertical block size |
| Ctrl held while confirming | Remove / subtract existing mining zones under the selected region |
| Right-click | Cancel / exit mining tool |
| Escape | Cancel / exit mining tool |

---
## <span style="color:#3fb950;">KEEP - Selection Rules</span>

- <span style="color:#3fb950;"><strong>KEEP:</strong></span> Precision mining produces a variable-size rectangular region anchored from the clicked terrain face.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> The precision tool does not snap to 4-block cells.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> Single click selects a region with the current horizontal and vertical sizes.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> Dragging expands from the anchor to the current hit, rounded up to the active horizontal size.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> Vertical thickness uses the active vertical size.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> Out-of-bounds positions are ignored.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> Transparent blocks are ignored.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> Water is not selected by this mining tool.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> Bedrock is never selectable. Any block with `y <= 3` is invalid.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> If a preview region contains no valid mineable blocks, confirmation does nothing.

---
## <span style="color:#3fb950;">KEEP - Custom-Block Region Math</span>

This behavior is implemented by `_build_precision_region()` and `_map_precision_axis()` in `MiningDesignationController.gd`. Keep this here until the helper has direct tests or is documented in a permanent mining spec.

Inputs:

```text
anchor           # clicked block
current          # current drag block
normal           # face normal of clicked block
size_horizontal  # current horizontal size, 1..8
size_vertical    # current vertical size, 1..8
```

Vertical range:

```text
if normal.y != 0:
    min_y = anchor.y + 1 - size_vertical
    max_y = anchor.y + 1
else:
    min_y = anchor.y - floor(size_vertical / 2)
    max_y = anchor.y + floor(size_vertical / 2 + 0.5)
```

Keep these invariants:

- <span style="color:#3fb950;"><strong>KEEP:</strong></span> The origin block is always included.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> Horizontal extents round up to a multiple of the current horizontal size.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> The region grows away from the clicked face when there is a horizontal face normal.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> When there is no normal component on an axis, the selection is centered by half the horizontal size.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> Max drag length is enforced by trimming one horizontal-size step when needed.

---
## <span style="color:#3fb950;">KEEP - Visual Terrain Cut Model</span>

This is the correct direction and should stay as the renderer-state model until real worker mining exists.

- <span style="color:#3fb950;"><strong>KEEP:</strong></span> Confirmed mining zones visually cut terrain without mutating `WorldData`.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> `ChunkMesher` skips cut blocks and treats adjacent cut blocks as transparent.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> Block-face overview recomputes visible surfaces after subtracting cut blocks.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> Actual terrain deletion, worker task selection, completed-region subtraction, and reservation are future mining-system work.

---
## <span style="color:#d29922;">REVIEW / MOVE - Active Parity Backlog</span>

These are the parts of the old Stonehearth parity review that still look active.

1. <span style="color:#d29922;"><strong>REVIEW / MOVE:</strong></span> **Drag height locking.** During drag, intersect the mouse ray against an anchor-height plane instead of raycasting terrain every update. This keeps selection stable on slopes and terraces.
2. <span style="color:#d29922;"><strong>REVIEW:</strong></span> **Selection support offset / validity display.** Keep the preview visually rectangular, but make invalid or filtered blocks clearer before confirmation.
3. <span style="color:#d29922;"><strong>REVIEW:</strong></span> **Size labels and rulers.** Current `Label3D` size labels exist, but they are not full X/Z rulers and may still be hard to read.
4. <span style="color:#d29922;"><strong>REVIEW:</strong></span> **Modifier redraw.** Force preview rebuild on Ctrl press/release so removal color changes immediately even if the mouse hit did not change.
5. <span style="color:#d29922;"><strong>REVIEW:</strong></span> **Cursor and user feedback.** Add a small mining-mode instruction callout; cursor assets can wait.
6. <span style="color:#d29922;"><strong>REVIEW:</strong></span> **Mining terrain grid visibility.** Generate the grid from visible/exposed faces only; do not rely on `no_depth_test` to draw every nearby candidate line.
7. <span style="color:#d29922;"><strong>REVIEW / MOVE:</strong></span> **Zone data model.** When worker mining begins, split full zone blocks, completed blocks, destination blocks, and reserved blocks.

---
## <span style="color:#d29922;">REVIEW / MOVE - Performance Work Belongs In 04</span>

<span style="color:#d29922;"><strong>MOVE TO 04:</strong></span> The current visual-cut sync still uses `set_visual_cut_blocks()` with a rebuilt full dictionary. Localized add/remove cut deltas and tiled overview invalidation belong in `04_mining_performance.md`.

## <span style="color:#d29922;">REVIEW - Deferred Mining System</span>

These are still future work, but they should become a dedicated mining-system plan rather than stay in this first-slice UX plan.

- <span style="color:#d29922;"><strong>REVIEW / MOVE:</strong></span> `MiningSystem.gd` autoload or scene-owned system for persistent mining zones.
- <span style="color:#d29922;"><strong>REVIEW / MOVE:</strong></span> Zone validation beyond the current placeholder storage.
- <span style="color:#d29922;"><strong>REVIEW / MOVE:</strong></span> `MINE` task publishing.
- <span style="color:#d29922;"><strong>REVIEW / MOVE:</strong></span> Destination block calculation for reachable work.
- <span style="color:#d29922;"><strong>REVIEW / MOVE:</strong></span> Completed-region subtraction when workers remove blocks.
- <span style="color:#d29922;"><strong>REVIEW / MOVE:</strong></span> Item drops and mining durability integration.

---

*Prev: [02_resource_distribution_plan.md](./02_resource_distribution_plan.md)*
