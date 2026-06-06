# 05 - Mining Tech Debt

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = keep</span> |
> <span style="color:#d29922;">Yellow = review / move to a more specific plan</span> |
> <span style="color:#f85149;">Red = safe to delete or archive once you are comfortable</span>

## Status - 2026-06-06

This file is **the consolidated mining backlog**. The three 2026-06-05 RESOLVED sections
(config source of truth; foreground/background overlay readability; per-zone overlay split +
orange selection) were removed on 2026-06-06 — they shipped and verified, and their permanent
specs already live elsewhere:

- Tool spec: `43_mining_materials.md` §Mining Tools
- Mining zone entity + no-merge adjacency decision: `43_mining_materials.md` §Mining Zone Entity
- Terrain invalidation contract: `24_world_rendering.md` §Mining-Edit Invalidation Contract

Resolved-item detail remains recoverable in git history (consolidation commit `29e6c81` and the
2026-06-05 shipping commits). **Open items: parity polish 1–7 below**, all re-verified against
`MiningDesignationController.gd` on 2026-06-06.

## <span style="color:#d29922;">REVIEW - Stonehearth Parity Polish</span>

Mining-UX polish items from the retired `03_mining_plan.md` parity review. The permanent tool
spec lives in `43_mining_materials.md` §Mining Tools.

1. <span style="color:#d29922;"><strong>REVIEW:</strong></span> **Drag height locking.**
   During drag, intersect the mouse ray against an anchor-height plane instead of raycasting
   terrain every update (`_update_hover_preview` re-raycasts terrain each frame today). Keeps
   selection stable on slopes and terraces.
2. <span style="color:#d29922;"><strong>REVIEW:</strong></span> **Selection support offset /
   validity display.** Keep the preview visually rectangular, but make invalid or filtered
   blocks clearer before confirmation.
3. <span style="color:#d29922;"><strong>REVIEW:</strong></span> **Size labels and rulers.**
   `Label3D` size labels exist (`_label_horizontal` / `_label_vertical`), but they are not full
   X/Z rulers and may still be hard to read.
4. <span style="color:#d29922;"><strong>REVIEW:</strong></span> **Modifier redraw.** Force
   preview rebuild on Ctrl press/release — today `_update_hover_preview` early-returns on an
   unchanged hit (`_dict_equal_hit`), so the removal colour only updates when the mouse hit
   changes.
5. <span style="color:#d29922;"><strong>REVIEW:</strong></span> **Cursor and user feedback.**
   Add a small mining-mode instruction callout; cursor assets can wait.
6. <span style="color:#d29922;"><strong>REVIEW:</strong></span> **Zone data model (worker
   prep).** The mined/designation set split shipped with slice Phase SO-2b; the remaining
   split — completed blocks, destination blocks, reserved blocks — lands with real mining
   execution (spec: `43_mining_materials.md` §Mining Zone Entity).
7. <span style="color:#d29922;"><strong>REVIEW:</strong></span> **Adjacent-zone seam
   outline.** Adjacent zones draw a doubled outline at their shared boundary. Zones are
   deliberately NOT merged (decision + reasoning: `43_mining_materials.md` §Mining Zone
   Entity, 2026-06-05); if the seam bothers in play, suppress outline faces against
   any-zone neighbours via `_zone_by_block` — presentation only, never data merging.

---

*Prev: [00_dev_roadmap](.) — docs 03 and 04 retired 2026-06-05; specs moved to
`43_mining_materials.md` §Mining Tools and `24_world_rendering.md` §Mining-Edit Invalidation
Contract. Resolved sections removed 2026-06-06 (git history retains them).*
