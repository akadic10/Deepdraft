# 01 — World Generation Roadmap

The original world-generation plan has been implemented. Its enduring content has been parked in
the permanent reference docs; this file is now a forward-looking roadmap only.

**Where the plan moved:**

- **Design intent** (plateau terrain rule, surface strata rule, grass palette rule, design north
  star, core world composition, Stonehearth reference) → `40_economy_colony/43_mining_materials.md`
  § *World Design Intent (North Star)*.
- **Generation pipeline** (noise, domain map, heightmap, macro-cell lakes, surface skin, ore/rock
  fill) → `43_mining_materials.md` § *World Generation Pipeline*.
- **Render modes & debug tools** (near chunk mesh, block-face overview, world-edge slab, debug
  overlay + block inspector) → `20_player_interface/24_world_rendering.md` § *Terrain Render
  Modes* / *Debug Overlay & Block Inspector*.
- **Resource distribution** (ore / gem / cave-soil placement) → `02_resource_distribution_plan.md`.

**Hard guardrails** (enforced across the above): bedrock immutable at `Y0–3`; generation fully
deterministic from `world_seed`; block IDs namespaced at save boundaries; terrain identity lives
in data, not renderer tricks.

---

## Status — First Milestone (done)

The low-risk shape and validation pass is complete: macro layout maps; NW mountain, central
valley, SW basin, SE highland, and edge belt; terrace quantization; macro-region surface
materials; lowland lake + mountain tarn; debug metrics; and inspector/generated/render
agreement. The mountain reads as exposed stone, the valley exposes settlement candidates, water
has non-grass banks, the surface is not a grass blanket, and the overview is block-face based.

---

## Second Milestone (next)

1. Add the world-edge presentation slab (see `24_world_rendering.md` § Terrain Render Modes).
2. Improve overview side-face merging.
3. Add sampled comparison tests between the overview mesh and generated chunks.
4. Add a road / path mask through the valley.
5. Add scatter maps for future flora and boulders (see *Future scatter* below).
6. Add screenshots / repeatable debug captures for terrain review.

## Future scatter maps (not yet built)

Worldgen does not spawn flora yet, but should eventually produce maps that make placement easy:
dense edge forest, valley trees, mountain pines/junipers, boulders, scree, flowers/shrubs,
road-side detail, lake-bank reeds. Placement rules for later: large props need local flatness
checks; plant visual overhangs add no terrain collision; props are placed entities, not terrain
blocks. (See `40_economy_colony/42_farming_brewing.md` for the entity/collision rules.)

## Open questions

- Should the mountain always be northwest, or should future seeds rotate the macro composition?
- Should the first trade road be visible immediately as packed dirt?
- Should snow or cold high-altitude stone exist in a future pass?
- Should settlement candidates become real UI hints, or stay debug-only?
- How calm should the eventual world-edge slab be, compared with the current block-face overview?

---

*Next: [02_resource_distribution_plan.md](./02_resource_distribution_plan.md)*
