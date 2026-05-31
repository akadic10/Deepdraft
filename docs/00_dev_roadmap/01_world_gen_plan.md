# 01 - World Generation Roadmap

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = keep</span> |
> <span style="color:#d29922;">Yellow = review / move to a more specific plan</span> |
> <span style="color:#f85149;">Red = safe to delete or archive once you are comfortable</span>

## Document Review - 2026-05-31

This file is no longer the source of truth for world generation design. The original plan has been implemented, and the permanent rules now live in the reference docs linked below.

Use this file only as a small follow-up backlog until the remaining yellow items are moved, completed, or deleted.

---

## <span style="color:#3fb950;">KEEP - Where The Plan Moved</span>

These links are still useful breadcrumbs to the permanent source-of-truth docs.

- <span style="color:#3fb950;"><strong>KEEP:</strong></span> **Design intent** - plateau terrain rule, surface strata rule, grass palette rule, design north star, core world composition, and Stonehearth reference moved to `40_economy_colony/43_mining_materials.md` section *World Design Intent (North Star)*.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> **Generation pipeline** - noise, domain map, heightmap, macro-cell lakes, surface skin, and ore/rock fill moved to `43_mining_materials.md` section *World Generation Pipeline*.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> **Render modes and debug tools** - near chunk mesh, block-face overview, world-edge slab, debug overlay, and block inspector moved to `20_player_interface/24_world_rendering.md` sections *Terrain Render Modes* and *Debug Overlay & Block Inspector*.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> **Resource distribution** - ore, gem, and cave-soil placement moved to `02_resource_distribution_plan.md`.

## <span style="color:#d29922;">REVIEW / MOVE - Second Milestone</span>

These are the remaining active worldgen follow-up items. Keep them here only if this file is still acting as the worldgen backlog. Otherwise move each item into a focused plan.

1. <span style="color:#d29922;"><strong>REVIEW / MOVE:</strong></span> Add the world-edge presentation slab. Source: `24_world_rendering.md` section *Terrain Render Modes*.
2. <span style="color:#d29922;"><strong>REVIEW / MOVE:</strong></span> Improve overview side-face merging.
3. <span style="color:#d29922;"><strong>REVIEW / MOVE:</strong></span> Add sampled comparison tests between the overview mesh and generated chunks.
4. <span style="color:#d29922;"><strong>REVIEW / MOVE:</strong></span> Add a road / path mask through the valley.
5. <span style="color:#3fb950;"><strong>KEEP:</strong></span> Add scatter maps for future flora and boulders.
6. <span style="color:#d29922;"><strong>REVIEW / MOVE:</strong></span> Add screenshots / repeatable debug captures for terrain review.

## <span style="color:#3fb950;">KEEP - Future Scatter Maps</span>

<span style="color:#3fb950;"><strong>KEEP:</strong></span> Worldgen does not spawn flora yet, but should eventually produce maps that make placement easy: dense edge forest, valley trees, mountain pines/junipers, boulders, scree, flowers/shrubs, road-side detail, and lake-bank reeds.

Placement rules for later:

- <span style="color:#3fb950;"><strong>KEEP:</strong></span> Large props need local flatness checks.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> Plant visual overhangs add no terrain collision.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> Props are placed entities, not terrain blocks.
- <span style="color:#3fb950;"><strong>KEEP:</strong></span> Entity and collision rules live in `40_economy_colony/42_farming_brewing.md`.

## <span style="color:#d29922;">REVIEW - Open Questions</span>

Keep any question you still want to answer. Delete any question that no longer matters.

- <span style="color:#d29922;"><strong>REVIEW:</strong></span> Should the mountain always be northwest, or should future seeds rotate the macro composition?
- <span style="color:#d29922;"><strong>REVIEW:</strong></span> Should the first trade road be visible immediately as packed dirt?
- <span style="color:#d29922;"><strong>REVIEW:</strong></span> Should snow or cold high-altitude stone exist in a future pass?
- <span style="color:#d29922;"><strong>REVIEW:</strong></span> Should settlement candidates become real UI hints, or stay debug-only?
- <span style="color:#d29922;"><strong>REVIEW:</strong></span> How calm should the eventual world-edge slab be, compared with the current block-face overview?

---

*Next: [02_resource_distribution_plan.md](./02_resource_distribution_plan.md)*
