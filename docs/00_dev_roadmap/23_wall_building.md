# 23 — Wall Building & Construction v1

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = decided / ready to build</span> |
> <span style="color:#d29922;">Yellow = decision needed or tune-in-engine</span> |
> <span style="color:#f85149;">Red = explicitly out of scope for this milestone</span>

Status: **PROPOSED — drafted 2026-08-14, revised same day after Alen's review.** Nothing
in this doc is built. This is the design pass for the first player construction
mechanic: dwarves placing solid terrain blocks from stocked rough stone — **anywhere
there is air**, carved or natural, underground or on the surface.

> **Revision note (Alen, 2026-08-14):** the first draft restricted v1 to backfilling
> carved-open cells, on the theory that the block-face overview couldn't cheaply render
> blocks above the generated heightmap. Alen rejected the restriction — and re-deriving
> the renderer plan showed the premise was wrong: built blocks don't need the overview at
> all. They render through a dedicated sparse-set mesh pass (the cavity-shell technique,
> §2), which costs the same whether the block sits in a mined corridor or on open
> grassland. Freestanding construction is **in scope**. The revised design is also
> simpler: construction never touches mining's renderer bookkeeping.

**Why this milestone:** doc 22 shipped doors and sealed-room temperature, but a room can
only be sealed where rock happens to surround it — there is no way to *make* a wall.
`WorldData.set_block()` has never been called with anything but `AIR_ID` (doc 22 noted
this explicitly), and rough stone's entire designed purpose — *"the player will use
stocked rough stone to wall up and backfill unwanted openings via a future BUILD
designation (mechanic not yet designed)"* (doc 43) — has been waiting since 2026-06-10.
Construction completes the loop the doors started: mine a cavern → wall it into rooms →
door the gaps → `RoomManager` seals them. With freestanding building in scope it also
opens **surface architecture** from day one: wall + roof a structure on the settlement
plain, add a door, and it seals like any cave room (a fully roofed volume is already
exactly what `RoomManager` requires — a shaft open to sky is a genuine leak, doc 22
Addendum 6). It is the load-bearing prerequisite for every furniture-defines-the-room
system downstream (Tavern, Shop, Armory — docs 51/52) and for the Aging Cellar's
build-at-the-right-depth gameplay (docs 34/42).

---

## 1. Scope decisions made during planning

<span style="color:#3fb950;">**Built blocks render through a dedicated `BuiltBlocksMesh`
pass — never through the generated-data overview.**</span> The overview renders generated
column data minus the mined/cut sets; teaching it about arbitrary player geometry (above
the heightmap, floating, mid-air) would mean rewriting its effective-top walks and greedy
tile mesher. Instead, built blocks are a sparse set (player-placed — thousands at most,
against 134M generated), and the cavity shell already proves the pattern: iterate a
sparse block dictionary, emit faces, one `ArrayMesh`, coalesced dirty-flag rebuild at
most once per frame. Construction gets the mirror image: the shell draws faces of solid
blocks *around* carved air; the built mesh draws faces *of* the built solids themselves.
Same vertex-colour material, same slice behaviour. Full face rules in §3.

<span style="color:#3fb950;">**Construction never mutates mining's renderer
bookkeeping.**</span> `_visual_cut_blocks` / `_mined_blocks` keep exactly one meaning:
*the generated block at this cell is not present*. Backfilling a mined cell does **not**
remove it from those sets — the overview keeps rendering the hole, and the built mesh
fills it visually. This is what makes backfill and freestanding identical: in both cases
`add_built_blocks()` only adds to `_built_blocks` and marks the built mesh dirty. No
cross-set edits, no cache-poisoning of the shell's memoised generated-id lookups
(`_shell_exact_ids` / `_shell_strata_ids` stay purely *generated* — built cells are
simply excluded from shell drawing, §3), and the first draft's ugliest problem —
backfilled ore holes repainting with the mined-away ore colour — cannot occur, because
built cells are never rendered from generated data at all.

<span style="color:#3fb950;">**Built blocks are real terrain, with their own
identity.**</span> One new block, `base:terrain:constructed:stone`, added to
`terrain_blocks.json` (kind `constructed`, hardness 3) and `block_resources.json`. It is
written into `WorldData` by the normal `set_block` path (chunk materialised from the
generator first — mining's rule), so **everything downstream works with zero new code**:
`NavGrid` sees a solid floor/obstacle via `BlockRegistry.is_solid()` + `chunk_dirtied`;
`RoomManager` sees a sealing surface the same way (doc 34: "any terrain block … and any
constructed wall block qualifies") and rebuilds on the same dirty signal; the mining tool
can designate it and dwarves can mine it back out. Constructed stone is deliberately a
**single material** for v1 — the doc 62 variant strategy (quality tiers, materials)
waits for crafting.

<span style="color:#3fb950;">**Concealment is untouched.**</span> Hard Rule 11 protects
*undiscovered natural* information. A constructed block is player knowledge by
definition and always renders its own identity. Designation targets **air cells only**,
so a build ghost can never probe solid rock. The Block Inspector gets a `built`
hit-source label so its generated-vs-actual agreement check reports the intentional
disagreement instead of flagging a defect.

<span style="color:#3fb950;">**Construction is the sixth face of the lease pattern, not a
new scheduler concept.**</span> A build zone is a work source posting `BUILD` leases (the
enum member has existed unused since doc 16) — the same shape as mining zones (doc 16),
stockpile zones (doc 18), and furniture ghosts (doc 19). Source ids come from
`TaskManager.allocate_source_id()`. The executor is a hybrid of two proven pieces: the
**fetch** half of FETCH_BUILD (reserve a loose item via `ItemDropManager.reserve()`,
else `StockpileManager.withdraw_item()` — zones, then containers) and the
**swing-at-a-cell-from-a-stand-cell** half of mining. The §2.8 release protocol applies
unchanged: any interrupt drops the carried stone at the dwarf's feet, frees the cell
reservation, and loses nothing.

<span style="color:#3fb950;">**Height is governed by the mining reach envelope, not a new
rule.**</span> A dwarf builds from a walkable stand cell beside the target, reaching
`reach_up_blocks` (5) above / `reach_down_blocks` (1) below their stand floor
(`mining_config.json execution.*` — construction reads the same values, or mirrors them
in its own config section). Building higher than reach means standing on something —
walls become their own scaffolding, which is emergent and correct. Roof spans follow the
same logic: buildable from atop the walls or from within reach below.

<span style="color:#3fb950;">**Stand-beside, never inside — and never build your own
cell.**</span> The doc 19 builder-entombment lesson is a hard rule from day one: the
stand target is the nearest walkable cell *beside* the footprint (the mining stand-cell
model), the target cell itself is never a legal stand cell, and the commit re-checks at
swing time that no dwarf occupies the target cell (release + retry if one wandered in).

<span style="color:#d29922;">**Entombment by topology is mitigated, not solved.**</span>
Building *closes* space — a valid per-swing stand cell does not guarantee the dwarf can
still exit the pocket after N commits (the inverse of mining, which only opens space).
v1 mitigation: within a zone, cells are handed out **farthest-first from the zone's open
boundary** (deterministic ordering), which makes "wall up this corridor" and "roof this
room" naturally build from the inside out. A true escape-path guarantee (probe a path to
outside the zone before each commit) is priced as a follow-up; decide in-engine whether
the heuristic is enough. Worst case is recoverable: the player mines the dwarf back out.

<span style="color:#3fb950;">**Occupancy rules at designation AND commit:**</span> a cell
is not buildable if it is solid (generated, built, or water — `BlockRegistry.is_solid()`
false for water, so an explicit water check joins the filter: <span
style="color:#d29922;">v1 forbids building into water cells; displacing the future water
CA is its own problem</span>), occupied by a placed-entity footprint
(`PlacedEntityRegistry.occupies()` — tree trunks, furniture, the flag), occupied by a
dwarf, or holding loose items (v1: **forbid**, don't displace — the player hauls them
clear first; a toast explains). All checks re-run at commit; failure releases per §2.8.

<span style="color:#d29922;">**Cost: 1 rough stone per block; mining a built block
refunds at `chance: 1.0`.**</span> Full refund makes walls freely rearrangeable (no
resource bleed while experimenting), matching rough stone's void-fill purpose rather
than an economy sink. Flag for balance later alongside the 5% testing-convenience drop
rates (doc 22 Addendum 3) — at 5%, stone is scarce in playtests; **DEV: Spawn Drops**
already covers testing supply.

---

## 2. What gets built

### Data

- `data/terrain/terrain_blocks.json` — `base:terrain:constructed:stone`
  (`kind: "constructed"`, `hex_color` a worked-masonry grey distinct from all eleven
  natural rocks — the player must read built vs natural at a glance,
  <span style="color:#d29922;">exact hex tune-in-engine against the doc 61 stone
  ramp</span>, `hardness: 3`).
- `data/terrain/block_resources.json` — durability 3, drops 1× rough stone at 1.0,
  `material_tags` matching the rock rows.
- `BlockRegistry` needs **no changes** — the new key rides the existing loader;
  `is_solid` / `is_transparent` fall out of the definition.
- `data/tasks/task_config.json` — new `construction` section (max workers per zone,
  swing time base, reach values if not shared with mining; single-owner rule — read via
  `TaskManager.get_config_section()`).

### `WallDesignationController` (new scene node + `class_name` — editor Reload required)

The designation tool, following the mining/stockpile marquee conventions: dock-routed
activation, drag-marquee, ESC-only cancel, RMB reserved for orbit, zones
click-selectable with a Remove window while the tool is off (mining parity). Raycasting
reuses the slice-aware voxel DDA (the doc 22 Addendum 2 port) but anchors on the **air
cell adjacent to the clicked face** (`place_pos`, doc 22 §Hit Result) — the precision
mining tool inverted: click a floor and drag a footprint along it, then extend
**vertical extent 1–8 via Alt+wheel and horizontal via Shift+wheel** (mining's exact
modifier contract; the tool claims the wheel through `Camera.set_zoom_suppressed`).
Drag-height locking to the anchor plane keeps wall footprints flat across terrain
steps. Selection filter: buildable air cells only (§1 occupancy rules); a selection with
zero buildable cells confirms to nothing. Designation is clipped to the visible volume
(WYSIWYG under slice, doc 11 Phase 3).

Owns the `construction` save section (§4) and the authoritative
`built_blocks: Dictionary` (Vector3i → namespaced key).

### `WallZoneComponent` (new plain class, `scripts/components/`)

The work source — `MiningZoneComponent`'s shape with the block-state split inverted:
**pending** (designated, not built), **reserved** (a dwarf holds the cell),
**completed**. Posts ≤ `max_workers` `BUILD` leases (priority 45 — the infrastructure
band, above HAUL 40, below MINE 50); destination = pending cells with ≥1 walkable stand
cell within reach, recomputed lazily on `chunk_dirtied` / commits inside zone bounds
(note: **each commit can create stand cells** — building the first course of a wall
makes its top a stand candidate for the second, so the recompute naturally unlocks
upward progress); cells hand out farthest-first (§1); zone auto-destroys when empty.

### `DwarfAgent` — the BUILD executor

```
pull BUILD lease → reserve target cell + reserve 1 rough stone
  (loose first via ItemDropManager.reserve(), else StockpileManager.withdraw_item())
→ path to the stone, pick up (carried item, existing pouch slot)
→ path to nearest walkable stand cell BESIDE the target, within the reach envelope
→ swing timer (base_time × hardness, mining's formula — profession hooks later)
→ commit (§3) → consume carried stone → loop within lease
```

Interrupt at any step: §2.8 — stone drops at the dwarf's feet as a loose item, cell
returns to pending. <span style="color:#d29922;">Bundling (carry up to 4 stones per
trip, the doc 18 pouch pattern) is a natural follow-up if one-stone-per-trip feels
sluggish — the pouch machinery exists; decide after the first playtest.</span>

---

## 3. Renderer contract — the `BuiltBlocksMesh` pass

New sibling to the cavity shell in `WorldRenderer`: a `MeshInstance3D` built from
`_built_blocks: Dictionary` (Vector3i → runtime id), material `_material` (shared
vertex-colour), coalesced dirty-flag rebuild at most once per frame (the shell's
`_cavity_shell_dirty` pattern, same rationale: per-swing synchronous rebuilds went
O(N²) once already).

**Face rules, per built block `b`, per 6 directions, neighbour `n = b + dir`:**

- skip the whole block if `b.y > slice_y` (hard clip — flora/furniture convention);
- skip the face if `n` is built (interior of a built run);
- skip the face if `n` is generated-solid **and not carved open** (buried face —
  `n ∉ _visual_cut_blocks` and generated id not transparent);
- otherwise **draw** `b`'s face with `b`'s own block colour: this covers `n` in the cut
  sets (backfill boundary), natural air above the surface (freestanding), natural cave
  air, and `n.y > slice_y` (the face at the slice cut — built geometry below the plane
  stays closed, matching the overview's cut-top behaviour).

**Cavity shell coordination (one added check):** the shell's neighbour loop skips faces
toward built cells (`_built_blocks.has(n)` → continue) — a backfilled cell is no longer
open cavity, and the built mesh owns that boundary. The shell's cavity iteration itself
needs no change: a backfilled cell still sits in `_visual_cut_blocks`, and the faces the
shell would draw *around* it terminate against the built mesh's geometry. Overdraw
between two solids (built face coplanar with a buried shell face) is invisible and
harmless at v1 scale.

**Overview coordination: none.** The overview keeps rendering generated-minus-cut,
oblivious. A cut floor under a backfilled cell is buried geometry — wasted verts,
no visual error. <span style="color:#f85149;">Per-chunk built-mesh nodes and
overview-integration cleanups are the scale path (the shell's own noted follow-up),
not v1.</span>

### The commit path (one function, used live AND on restore)

```
1. Re-check occupancy (dwarf/entity/item/solid/water) — abort → release per §2.8
2. WorldData.set_block(cell, constructed_id)     # chunk materialised first (mining's rule)
3. WorldRenderer.add_built_blocks([cell])        # _built_blocks[cell] = id; built mesh
                                                 #   dirty; NO cut-set edits (§1)
4. Bookkeeping: controller's built_blocks[cell] = key; zone pending → completed
```

`WorldData.chunk_dirtied` then does the rest for free: `NavGrid` invalidates the chunk's
walkability cache, `RoomManager` re-runs its throttled rebuild (walling the last gap +
placing a door = sealed room, no construction-specific hook), scheduler wake events
re-probe blocked tasks.

**Un-building is mining.** No new removal tool: designate the built block with the
mining tool, a dwarf mines it, the refund drops. The construction controller subscribes
to `chunk_dirtied` and prunes any `built_blocks` entry whose `WorldData` id no longer
matches, calling `WorldRenderer.remove_built_blocks([cell])` in the same breath —
data-driven, no cross-controller call, the RoomManager precedent. Implementation note
for the mining side: `add_mined_blocks()` on a cell whose *generated* id is transparent
(a freestanding built block mined away — generated says air there) must be a no-op for
the cut sets, or harmlessly tolerated — verify which during the build, and leave a
comment either way.

---

## 4. Save / load

New scene section, per the doc 20 ownership contract:

| Priority | Section | Owner | Content |
|---:|---|---|---|
| 15 | `construction` | `WallDesignationController` | Built cells as `[[x,y,z], "base:terrain:constructed:stone"]` pairs + outstanding zone cell sets |

Priority **15** slots between mining (10) and the settlement flag (20): restore replays
history — mining voids first, construction adds its blocks — by running the same §3
commit path per cell. **This is the first system to exercise doc 12's dormant rule:**
*"if a future construction system persists a non-void terrain block, it must store the
block's permanent namespaced key and resolve it through `BlockRegistry` on load."*
Runtime integer ids never cross the boundary. Mining's saved state is untouched by
construction (no cross-owner edits); the ordered replay reproduces the live sequence,
and `RoomManager`/`NavGrid`/renderer state rebuilds as derived (the doc 22 DERIVABLE
precedent). `SaveManagerRoundTripTest` gains a construction round-trip: build (one
backfill cell, one freestanding surface cell) → save → load → both restore constructed,
mined hole intact, room still sealed.

---

## 5. UI

- **Build panel (🔨)** gains a `🧱 Wall` entry above the 📥 furniture rows. `DockUI`
  announces `tool_requested("wall")`; the controller self-toggles (stockpile-tool
  convention); every other click-tool deactivates (one-active-tool contract).
- Ghost preview: designated cells render a translucent **grey ghost volume** (mining
  owns yellow, stockpiles blue-cyan, rooms green) with the exterior-faces +
  deduped-outline treatment (the doc 22 Addendum 7 lesson — no doubled corner lines).
- Zone window: cell count, stone delivered/required, `Remove`, and a
  **DEV: Build Instantly (no cost)** button — the DEV-mine convention, same pipeline
  minus the dwarf and the stone.
- World Info (`DebugLoadingOverlay` — the live panel, not the dead
  `DockUI._world_info_rows()`): a `built` count line.

---

## 6. Verification checklist (for the build session)

- [ ] Boot clean; editor **Reload Current Project** done (new `class_name` — the doc 19
      Phase 3 lesson).
- [ ] 🧱 designates air only; solid, entity-occupied, dwarf-occupied, item-holding, and
      water cells all refuse (toast explains items).
- [ ] Dwarf fetches a rough stone (loose → zone → container fallback order) and builds
      from a stand cell beside the target; interrupt mid-carry drops the stone at their
      feet and the cell re-pends.
- [ ] **Backfill:** fill a mined-out ore cell — renders constructed grey from every
      angle (no ore colour anywhere); Inspector shows `source: built`, agreement flagged
      intentional; cavity shell shows no seams or z-fighting at the built/carved
      boundary.
- [ ] **Freestanding:** build a 3-long, 2-high wall on open grass — renders correctly
      from all orbits and zooms, slices correctly (hidden above the plane, closed face
      at the cut), casts/receives light like terrain.
- [ ] **Reach/scaffolding:** a dwarf builds course 2 standing on ground (within
      reach_up 5), and a 7-high tower requires standing on the wall — destination
      recompute unlocks upper cells as lower courses complete.
- [ ] **Surface room:** wall + roof a 4×4 structure on the plain, add a door →
      Rooms count increments, 🚪 overlay hugs the built shell, hearth heat applies,
      temperature reads plausibly for its (shallow) mean floor Y. Mine one roof block →
      seal breaks (sky leak — correct per doc 22 Addendum 6).
- [ ] Mine a built block → refund drops at 100%, World Info `built` count drops,
      renderer override pruned; mine a freestanding built block → no cut-set residue
      (§3 implementation note verified).
- [ ] Nav: dwarves path OVER a 1-high built step (step-assist) and are blocked by a
      3-high wall; walkability updates within one chunk_dirtied cycle.
- [ ] Save/reload mid-zone: built cells restore (constructed, not natural), unfinished
      cells re-pend, leases repost, sealed rooms re-seal. Round-trip test passes
      headless.
- [ ] Farthest-first ordering: a dwarf walling a dead-end corridor exits before the
      last block; deliberately try to entomb via two zones — note behaviour, decide on
      the escape-probe follow-up.
- [ ] No global invalidation on any build edit; frame-time stays flat while a 30-cell
      zone completes (built-mesh rebuild coalesces to once per frame).

---

## 7. Deferred (explicitly out of scope)

<span style="color:#f85149;">Non-stone materials & quality variants</span> — one
constructed stone only; wood walls, brick, and the doc 62 quality multipliers wait for
crafting.

<span style="color:#f85149;">Ramps, stairs, ladders</span> — doc 32's future
vertical-traversal blocks. Construction placing them is trivial *after* nav supports
them; nav first.

<span style="color:#f85149;">Support pillars / collapse interaction</span> — doc 43's
collapse model is itself unimplemented; built blocks get support scores whenever that
lands.

<span style="color:#f85149;">Escape-path guarantee</span> — the per-commit reachability
probe (§1). Priced, not built; farthest-first plus player rescue is the v1 answer
unless playtests say otherwise.

<span style="color:#f85149;">Item displacement / water displacement on build</span> —
v1 forbids building on cells holding loose items or water rather than resolving either.

<span style="color:#f85149;">Per-chunk built-mesh nodes & overview integration</span> —
the scale path once colonies carry thousands of built blocks (the cavity shell carries
the same note).

<span style="color:#f85149;">Blueprints / templates / multi-cell structures</span> —
Stonehearth-style building plans. v1 is blocks; structure is emergent.

---

## 8. Docs to update on ship

`43_mining_materials.md` (rough stone note → shipped; drop table row; mining a
constructed block), `12_world_grid.md` (non-void save rule → exercised; save schema
example), `23_user_interface.md` (Build panel row, zone window), `24_world_rendering.md`
(BuiltBlocksMesh pass + exposure-principle extension), `31_task_system.md` (BUILD live —
sixth work-source family), `20_save_load.md` (section table + priority 15),
`13_architecture.md` (scene-node list), `AGENT.md` (structure tree; Hard Rule
cross-refs if any wording shifts).

---

*Prev: [22_doors_temperature.md](./22_doors_temperature.md)*
