# 17 - Dwarf Visual Polish (Backlog)

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = decided / scoped</span> |
> <span style="color:#d29922;">Yellow = decide at build time</span> |
> <span style="color:#f85149;">Red = out of scope for this pass</span>

Status: **backlog**, created 2026-06-10 from Alen's review of the first walking dwarves
(doc 16 Phase 1/3b verification). Deliberately NOT part of the First Dwarf Milestone — the
milestone continues on its critical path (TaskManager → mining execution); this pass runs
after it, or interleaved when a visual break is wanted. Doc 15 (asset rework) fixed the
anatomy *contract*; this pass fixes the *quality*.

**Verdict being addressed (Alen):** "The dwarf GLBs are too basic/lazy." Specifically:
heads should be a little bigger; hands and feet are ugly; no basic clothes; the walking
animation is terrible — too fast and the gait doesn't line up with actual steps.

Already handled at review time (not in this backlog): name tags now default OFF with a DEV
toggle in the Dwarves window.

---

## 0. Reference findings — hearthling part anatomy (verified from `P:\stonehearth`, 2026-06-10)

Parsed `entities/humans/male/*.qb` directly (parser + renders in `tmp/hearthling_review/`).
Hearthling parts are **sculpted, not boxes**:

| Part | Measured | Shaping observed |
|---|---|---|
| Head | 17×14×11 vox (vs 9-wide torso — clearly dominant) | 1-voxel chamfer on every edge, double-stepped crown (rounded read), **protruding nose block** on the face |
| Hands | 4×2×6 palm + thumb (2 segments) + 3 fingers (2 segments each) | Fully articulated — but only because hearthlings have a **skeleton** (every sub-matrix is a named joint) |
| Feet | 6×5×7 boot + separate 6×3×3 **toe matrix** (bends in the walk) | Stepped heel, boot silhouette |
| Body | torso 9×9×7 with shoulder notches; **pelvis 11 wide** (bottom-heavy stance) | Baked **dark belt band** + shirt/pants colour separation |
| Whole | 33 vox tall at 0.1 scale = 3.3 blocks | Matches our visual height target exactly |

**Adoption rule:** take the SHAPING, never the rig (doc 41 contract: four detached parts,
no skeleton). Fingers/toes become carved grooves and colour breaks, not joints.

## 1. Asset regeneration (`tools/generate_dwarf_glb.py` + doc 41b)

> **SHIPPED 2026-07-02 (approved by Alen from the QA sheet;
> `tmp/dwarf_regen_preview/qa_sheet.png`, renderer kept as
> `tools/render_dwarf_qa.py`).** All four green items landed: hearthling-ratio
> heads (14 vox wide, chamfered edges, double-stepped crown, 2×2 protruding
> nose), mitten hands with finger-groove colour breaks, stepped leather boots,
> and clothes BAKED into `body_base.glb` (tunic + dark belt/buckle + 10-wide
> trouser pelvis + shoulder notches; overlay parts remain the later path for
> profession colours). Tint split implemented: body/feet baked, head/hands
> skin-tinted (`DwarfAgent._apply_tints`). Bonus: a combinatorial audit found
> the old frame always shipped hair⊂head cell overlaps (latent z-fighting) —
> the generator now subtracts a forbidden-cell set; all 1,536 combos verify
> overlap-free. Face detail beyond the nose stays opportunistic (§3).
> Details: doc 41b 2026-07-02 note.
>
> **Second pass, same day (approved by Alen — "this looks better"):** Alen's
> verdict on pass 1 was "still very blocky", so the hearthling `.qb` files
> were parsed DIRECTLY from `P:/stonehearth` (QB parser + reference renders;
> layer maps of `male/head.qb`, `beard.qb`, `body.qb`, hair styles). Derived
> shaping rules now in the generator: masses are built from OCTAGONAL-plan
> rows (`_rounded_row`, corner cut 2–3) tapered at BOTH ends (head profile
> `_HEAD_PROFILE`: jaw taper + crown steps); eye sockets are CARVED into the
> face with the eyes part sitting flush inside; hair caps SHRINK-WRAP the
> dome (`_scalp` follows a head top-map); beards are jaw-hugging CRESCENTS
> with a mouth notch and rounded hanging tips (`_beard_crescent`); hair and
> beards are TWO-TONE (deterministic highlight/shadow voxels on exposed
> surfaces — survives the tint multiply); body gains rounded corners, a chest
> curve, and a flared shoulder plate. Part z-fights are prevented
> structurally: every hair/beard subtracts a forbidden-cell set (all head
> tiers + eyes + brow zone + body); audited overlap-free across all combos.
> **Verified in-engine by Alen, 2026-07-02 ("looks good") — §1 asset pass
> BANKED.** Remaining in this doc: §3 opportunistic extras only (face detail,
> body lean into turns) and the future clothes-overlay path for profession
> colours.

All shape work happens in the generator (the doc-15 pipeline: regen into a tmp preview
folder, visual QA render, then replace `assets/dwarves/`). Contract rules that MUST
survive: four detached parts, no arms/legs, shared authoring frame, 8 vox/block with 0.125
baked, neutral tint palettes, ~3.3-block visual height (logical 3 stays untouched).

| Item | Direction | Notes |
|---|---|---|
| <span style="color:#3fb950;">**Bigger heads**</span> | Hearthling ratio (§0): head ~1.9× torso width. At our 8 vox/block: head ~13–14 vox wide vs torso ~7–8. Chamfer every edge 1 voxel, double-step the crown, add a 2×2×1 protruding nose | Keep total height ~3.3 blocks: grow head, compress torso. Affects all 4 age tiers + every hair/beard/brow/scar part (shared frame — regenerate together). |
| <span style="color:#3fb950;">**Better hands**</span> | Hearthling-derived mitten: palm slab + thumb mass on one side, finger grooves as 1-voxel notches/colour breaks on the outer edge (NO joints — §0 adoption rule) | Still detached, still mirrored at runtime. |
| <span style="color:#3fb950;">**Better feet**</span> | Hearthling boot (§0): stepped heel, forward toe step, darker sole band | Boots-by-default also softens the "no clothes" problem from most camera angles. |
| <span style="color:#3fb950;">**Basic clothes**</span> | Hearthling model (§0): bake into `body_base.glb` — tunic torso, **dark belt band**, contrasting trouser band; shoulder notches; pelvis slightly WIDER than chest (squat dwarf stance, even more than the hearthling) | <span style="color:#d29922;">Decide: baked single outfit (cheap; skin tint then applies only to head/hands) vs separate `clothes_*.glb` overlay parts (enables profession colours per doc 41). Lean: baked now, overlay later. NOTE: clothed body areas must use baked colours, not the skin-tint neutral — the tint pipeline needs a per-part "tintable" split or clothes baked in non-neutral colours.</span> |
| <span style="color:#d29922;">Face detail pass</span> | Nose mass, eye sockets reading at RTS zoom | Opportunistic — only if the bigger head makes room for it. |

QA loop: regen → `tmp/dwarf_visual_qa/` renders (front/side, assembled, one per age tier,
clothed) → Alen review → replace live GLBs → verify in-engine height against terrain.

## 2. Walk animation rework (`DwarfAgent.gd`, runtime only)

> **SHIPPED 2026-07-02; verified in-engine by Alen same day ("feels more natural now") —
> default dials accepted as-is.** Gait cycle is now
> driven by distance travelled (`_walk_cycle += moved / (stride_length × 2)`); feet alternate
> a sine-lift SWING half-phase and a flat PLANT half-phase whose backward slide (relative to
> the body) exactly cancels body motion — the planted foot stays world-fixed. Hands
> counter-swing at half amplitude; body/head lean `walk_lean_deg` (2.5°) into travel. All
> three dials are exports on `DwarfAgent`: `walk_speed` (3.0 → **2.2**), `stride_length`
> (0.7), `walk_lean_deg`. Turn banking was skipped (turns are already smoothed via
> `lerp_angle`; add only if walking reads flat). Tune by eye in-engine and adjust the
> exports — no code needed.

Current gait was a placeholder sine bob: cycle speed an arbitrary constant, feet slid
("doesn't line up with actual steps"), everything too fast.

| Item | Direction |
|---|---|
| <span style="color:#3fb950;">**Distance-driven gait**</span> | Drive the cycle from DISTANCE TRAVELLED, not time: `cycle += distance / stride_length` (stride ~0.7 blocks). Feet then plant in sync with ground covered at any speed — the core fix for "steps don't line up". |
| <span style="color:#3fb950;">**Plant/lift foot phases**</span> | Replace pure sine with a stepped curve: a foot holds still (planted) for half the cycle while the other swings forward — fake but readable footsteps, Stonehearth-style. Hands counter-swing at half amplitude. |
| <span style="color:#3fb950;">**Tune walk speed**</span> | `WALK_SPEED` 3.0 reads too fast. Try 2.0–2.4 blocks/s; expose as an export for in-engine tuning. Mining-skill speed bonuses (doc 41) scale task time, not walk speed — unaffected. |
| <span style="color:#d29922;">Body lean</span> | 2–4° forward pitch while walking, slight bank into turns. Cheap charm; tune by eye. |
| <span style="color:#f85149;">Skeletal animation / AnimationPlayer</span> | Never — transform offsets on the four parts is the doc-41 contract. |

## 3. Sequencing

1. Walk animation rework first — pure GDScript, no asset churn, biggest feel win per hour.
2. Asset regeneration second (one regen covers head size + hands + feet + clothes).
3. Face detail + body lean last, only if the rest lands well.

Docs to touch when this ships: `41b_dwarf_appearance_glb.md` (part dimensions, clothes
decision), `61_voxel_art_guide.md` §3 table if proportions change, doc 16 build log.

---

*Prev: [16_first_dwarf_milestone.md](./16_first_dwarf_milestone.md)*
