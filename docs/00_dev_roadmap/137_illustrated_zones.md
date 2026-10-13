# 137 — Illustrated Zones submenu

Status: **implemented** — 2026-10-12.

## Player experience

Zones now opens three square Hearth & iron illustrations directly above its
main-dock button. There are no permanent captions; hover or keyboard focus shows
the name and explanation. The row uses the same 64 px desktop / 56 px compact
buttons, copper connector and active frame as Orders.

| Entry | Artwork | Availability |
|---|---|---|
| Storage | Stacked crates, sack and logs on marked ground | Live: draw a stockpile, then inspect its filters and contents. |
| Farming | Tilled rows, crops and hoe | Planned: crop-growing zones and farming work are not implemented. |
| Animal pasture | Sheep, grass and rustic fence | Planned: livestock zones and animal keeping are not implemented. |

Planned icons remain visible, dimmed and marked with a lock. They can receive
keyboard focus. Hover, click or Enter explains their status; they never emit a
tool request, become the active brush, create a zone or interrupt Storage.
The sheep illustrates the future category, not a new animal or livestock feature.

Storage keeps its existing controller, ground validation, filters, hauling,
inspection and undo receipts. Its compact mode panel shows live valid-cell
counts during a drag. Done/Escape and closing the shelf retain the established
behavior. Farming and pasture simulation remain separate future milestones.

## Ownership

- `data/ui/dock.json` defines the three entries, atlas regions, descriptions and
  explicit `planned` metadata. `UIRegistry` remains the only data reader.
- `DockIconButton` owns shared artwork, planned badges and hover/focus help.
- `OrdersShelf` presents both Orders and Zones, anchors each to its parent and
  prevents planned entries from dispatching tools. It still avoids inspectors.
- `StockpileDesignationController` owns live storage work and its short summary.
- `assets/ui/dock/zones_atlas.png` is the new full-color source sheet, preserved
  intact; runtime `AtlasTexture` regions select the three icons.

No global script class, autoload, save schema, farming job, pasture job or item
definition was added. Restart Play to load the menu and artwork.

## Verification

The shared `OrdersShelfTest` covers normal storage creation/undo and existing
Orders input. Extended checks exercise all three zone icons at 960×540,
1280×720 and 2560×1440: parent alignment, square artwork, hover and keyboard
help, Enter/click on planned entries without dispatch or state mutation, and
tooltip cleanup when the submenu closes. Native captures and test logs live in
`tmp/zones_art_20261012/`. Godot import and headless/native runs passed without
script errors; native captures at all three sizes were visually reviewed.

## Artwork provenance

Generated with the built-in imagegen tool, using the existing Deepdraft Orders
atlas as a style reference. Stonehearth supplied layout inspiration only; no
Stonehearth art was used in the asset. The full generation prompt is recorded
in [137 — Zones art prompt](concepts/137_zones_prompt.md).
