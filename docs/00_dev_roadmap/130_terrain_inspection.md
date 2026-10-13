# 130 — Clickable terrain faces

Implemented 2026-10-12 after exposed underground material could not be reached
with the technical Block Inspector.

## Player behavior

Click a bare terrain wall, floor or ceiling to open **Object explorer**. It names
the visible material (for example Cave soil, Iron ore or Jade), outlines the
selected block, and shows its type, surface, level and natural/constructed status.
Constructed stone and both permanent floors identify their finished material.
Names and brief descriptions live in each block's `inspection` metadata in
`data/terrain/terrain_blocks.json`, owned by BlockRegistry.

Furniture, loose items, dwarves and other objects retain selection priority.
Mining orders and stockpile floors retain their existing inspectors. Active
designation and placement tools keep their clicks. Mining away a selected block,
covering its face or hiding it above the slice closes the selection.

Slice caps and planned openings reveal only the displayed strata. The inspector
does not disclose hidden ore, gems or caves. Mining and discovered cave air
expose actual material on their adjacent faces. Inspecting terrain is read-only
and does not add discovery or save state.

**Development → DEV: Block Inspector** now holds the technical tool formerly
under Menu. It retains generation IDs, coordinates and rendering diagnostics.
Its live-block lookup respects AIR in edited chunks, fixing the old fallback
that could resurrect original rock in front of the exposed face being inspected.

## Ownership and verification

`TerrainExplorerProvider` is a scene-owned provider with an exported renderer
reference. It reads current terrain plus the renderer's cut, built and discovered
sets; it does not own a second visibility map. Object explorer uses it as a
fallback behind ordinary objects and zones. ObjectPicking's optional sampler
supports these visual cuts while leaving work/designation rays unchanged.

`TerrainExplorerTest` exercises actual wall clicks, material labels, concealment,
slice/terrain changes, visible cuts, developer live-air reads, construction,
furniture/tool/zone priority, the Development button and compact window layouts.
It passes headlessly and with a native capture. ObjectExplorerTest,
ConstructionInputTest, FloorConstructionTest, WallMountHeightTest, TreeFellingTest,
DwarfInspectorTest and the full-scene SaveManagerRoundTripTest also pass.
Logs and the native preview are in `tmp/terrain_explorer_20261012/`.

Restart Play. No new autoload or save migration is required.
