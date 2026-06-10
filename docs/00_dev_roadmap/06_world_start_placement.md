# 06 - World-Start Placement (Settlement Flag & 3D Preview)

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = keep</span> |
> <span style="color:#d29922;">Yellow = review / decide before building</span> |
> <span style="color:#f85149;">Red = safe to delete or archive once you are comfortable</span>

Status: rewritten 2026-06-06. This file was originally the *startup-performance* plan
("Initial World Load, Sky, Fog, and View Distance"). **That problem is solved** — see
`07_performance_tuning.md` (TARGET MET: ~5.0 s to interactive in a release build), achieved
algorithmically without the bounded-generation rewrite this doc once proposed. The obsolete
performance baselines, hypotheses, fog/camera budget, and Stonehearth staging research were
removed on 2026-06-06 (recoverable in git; the file keeps its old name so doc 07's link stays
valid).

What remains here is the one piece of forward-looking content that was *not* a performance
concern and is captured nowhere else: the **world-start placement flow** — a player-facing
feature, still backlog, **nothing implemented**. Build it when world-start UX matters, not
before.

## <span style="color:#3fb950;">KEEP - Feature Goal</span>

Give the world a deliberate start: instead of dropping the player into the full debug world,
show a bounded 3D placement preview, let them choose a start anchor (the Settlement Flag), and
hand off into early play around that anchor. The anchor becomes the camera target, the
fog/view boundary, and — later — the camp/settlement origin for simulation systems.

Performance is **not** the motivation (startup is already fast). The motivation is a coherent,
intentional new-world experience and a home location for future settlement systems.

## <span style="color:#d29922;">REVIEW - Current Artifacts</span>

- Settlement Flag item: `base:items:special:settlement_flag` in
  `data/entities/items/resources.json` — **data only; referenced by no script yet.**
- Placeholder model: `res://assets/models/items/misc/settlement_flag.glb`
  (one-tile footprint, three blocks tall).

## <span style="color:#d29922;">REVIEW - Proposed Flow</span>

1. **Bounded 3D placement preview.** Show a limited generated surface with a working camera —
   not the full world. Deepdraft's authored identity (NW mountain, SW lake, valley corridor,
   foothill transitions) should read in the preview and fogged horizon. Static flora may
   appear if cheap. No dwarves, animals, jobs, economy, or settlement AI.
2. **Choose the start anchor.** Player places the Settlement Flag on a valid standable
   surface, or the system auto-picks a recipe-valid point. Either way it is internally a
   world-start anchor.
3. **Reveal the first patch.** Center the camera and fog/view boundary on the anchor. The
   player cannot pan outside the promised/fogged area during start.
4. **Post-flag handoff (optional, later).** Reveal a small area around the anchor, fog-of-war
   the rest, and spawn non-simulated starter placeholders (crates, bedrolls, dwarf markers).
   No real dwarves/animals/food/jobs/economy yet.

The flag stays thin: it picks the anchor and gives future settlement systems a home. It does
**not** need population, territory, storage, jobs, economy, or permanent save state yet.

## <span style="color:#d29922;">REVIEW - Open Questions</span>

- Auto-pick the anchor, or require player flag placement? (Auto-pick is enough to ship a
  basic flow; player placement is the richer feature.)
- Is the placement preview a genuinely bounded local generation, or just the existing fast
  full-world boot with camera/fog framing? Given startup is already ~5 s, framing the existing
  world may be sufficient — the bounded-generation path in `07` "remains available only if the
  world grows."
- When the flag becomes the real camp anchor, it must respect the hard rules: bedrock at Y=0,
  namespaced block IDs, 3-block nav clearance, deterministic generation from `world_seed`.

## <span style="color:#3fb950;">KEEP - Cross-References</span>

- Startup performance (solved): `07_performance_tuning.md`.
- Sky / clock / weather (shipped): `08_sky_plan.md`.
- Camera config: `data/camera/camera_settings.json`, `21_camera.md`.
- World identity & determinism: `11_overview.md`, `12_world_grid.md`,
  `43_mining_materials.md`.

---

*Prev: [00_dev_roadmap](.) — performance plan superseded by doc 07 (2026-06-06); only the
world-start placement feature survives here.*
