# 18 - Stockpiles & Hauling (Second Colony Milestone)

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = decided / ready to build</span> |
> <span style="color:#d29922;">Yellow = decision needed or tune-in-engine</span> |
> <span style="color:#f85149;">Red = explicitly out of scope for this milestone</span>

Status: **SHIPPED — milestone closed 2026-07-11** (drafted 2026-07-06). Carry-forward
items live in §2.5 (worker-scaled hauling, haul-utility priority band, containers/shelf,
input-output bins) and §6 (max_haulers dial, rough-stone flood watch).

**Why this milestone:** mining works, but its output is dead weight — drops litter the pit
and nothing can collect them (doc 16 shipped them as "inert item nodes, hauling is a later
milestone"). Every economy system queued behind this one needs stockpiles to exist: workshops
poll stockpiles for inputs (doc 23 §Workshop Input Lookup), farming yields deposit into food
stockpiles (doc 42), trade sells from shop storage (doc 51), the status-bar counters aggregate
zones (doc 23). This is also the first test of doc 16's architectural bet — that the
work-source/lease pattern generalises beyond mining ("a stockpile system posts haul tasks per
item-batch, not per item", doc 16 §2.1). If the pattern holds here, workshops are next for free.

Deliverable: **the player paints a stockpile zone on flat floor; dwarves collect loose drops
into it, stack them per cell, and the colony's stored counts are queryable — with hauling
interruptible at any point under the existing release protocol.**

---

## 1. Where Deepdraft stands today (gap analysis)

| Piece | State today | Gap |
|---|---|---|
| Stockpile spec | Doc 23: zone data model, filter tags, acceptance check, `StockpileManager` API — complete design | No code at all |
| Item definitions | `resources.json` complete: `stack_max`, `weight_class`, `material_tags` with `stockpile_*` tags on every item | Nothing reads `stack_max`/`weight_class` yet |
| Drops | `ItemDropManager` spawns inert per-unit nodes (GLB, slice-culled, floor-snapped) | No loose-item index, no reservation, no pickup API |
| Task system | `TaskManager` + work-source registry + release protocol shipped and proven (doc 16) | `HAUL` exists in the enum only; no executor |
| Dwarf agent | Walk, gait, zone-lease mining executor, sleep-lite interrupts | No carry state/visual, no haul executor |
| UI | Dock + panels exist; mining marquee proven | No stockpile designation tool, no zone overlay, no counters |

---

## 2. HAUL ARCHITECTURE

### <span style="color:#3fb950;">2.0 Direction (follows doc 16 §2.1 — recorded as the plan's premise)</span>

1. **The stockpile zone is the work source, not the item.** A zone posts at most
   `max_haulers` HAUL leases (default 2 per zone, data-driven). A lease is a claim on the
   zone's *intake*, never on a specific item.
2. **A dwarf holding a haul lease pulls one item at a time** from the loose-item index:
   nearest unreserved loose item the zone accepts → reserve item + destination cell → path,
   pick up, carry, deposit → pull the next. The per-item task never exists as a queued object.
3. **Release is cheap and legal (Hard Rule 12):** interrupted mid-carry, the dwarf drops the
   carried item at their feet as a normal loose drop (it re-enters the index), reservations
   are freed, zone progress is never corrupted. This was recorded as the pattern in doc 16
   §2.8 before hauling existed; this milestone makes it real.

### 2.1 Loose-item index (`ItemDropManager` grows up)

`ItemDropManager` already owns every drop node. It gains:

```gdscript
# Registration is automatic — spawn_drop() indexes what it spawns.
func loose_items() -> Dictionary                      # item_key -> Array[Node3D] (unreserved only)
func nearest_loose(accepted_tags: Array, from: Vector3i) -> Node3D
func reserve(node: Node3D, dwarf_id: int) -> bool     # false if already reserved
func unreserve(node: Node3D) -> void
func take(node: Node3D) -> String                     # removes from world, returns item_key (pickup)
func drop_at(item_key: String, cell: Vector3i) -> Node3D   # release-protocol drop + deposit placement
```

Index is event-maintained (spawn/take/drop), never rebuilt by scanning — the doc 16 §2.5
discipline. Reservations live on the manager, not the node meta.

### 2.2 StockpileZone + StockpileManager

Per doc 23's data model, trimmed to v1:

```gdscript
# scripts/components/StockpileZoneComponent.gd — work source (mirrors MiningZoneComponent)
var zone_id:     int
var tile_cells:  Array[Vector3i]          # flat floor cells (validated walkable at designation)
var filter_tags: Array[String]            # v1: all stockpile_* tags (accept everything)
var cell_stacks: Dictionary               # cell -> { "item": String, "count": int }  (one stack per cell)
var reserved_cells: Dictionary            # cell -> dwarf_id (deposit destination reservations)

func accepts(item_key: String) -> bool    # tag overlap + a free/compatible cell exists
func reserve_deposit_cell(item_key: String, near: Vector3i, dwarf_id: int) -> Vector3i
func deposit(cell: Vector3i, item_key: String) -> void   # stack += 1, respects stack_max
```

`StockpileManager` (autoload, after TaskManager) owns zones and the aggregate view
(doc 23 API): `register_zone` / `deregister_zone` / `find_nearest_zone_with()` /
`get_total(item_key)` / `signal stockpile_changed(zone, item_key, delta)`. Workshop input
lookup lands with workshops — the API surface is created now so doc 23 stays true.

### 2.3 Worker loop (dwarf holding a HAUL lease on zone Z)

```
1. pull = ItemDropManager.nearest_loose(Z.filter_tags, dwarf_cell)
   none in reach -> lease completes (zone re-posts when new drops appear — event-driven)
2. reserve item; reserve deposit cell in Z (nearest to the item, same-stack preferred)
   either fails -> unreserve both, try next item; 3 fails -> release lease w/ backoff
3. path to item -> pick up (take); carried item parented to MeshHandR, weight_class
   sets carry speed (light ×1.0, heavy ×0.7 per resources.json)
4. path to deposit cell -> deposit(); stockpile_changed fires; item node snaps to the
   cell as a stored drop (slice-culled as before)
5. goto 1   (interruption at any step: carried item -> drop_at(feet), reservations freed)
```

Lease posting mirrors mining: a zone with accepted loose items in the world and free
capacity posts `min(max_haulers, needed)` leases; `ItemDropManager` spawn events and
`stockpile_changed` are the wake sources. **No polling.**

### 2.4 Storage is physical — one item per tile (REVISED, Alen 2026-07-06)

Deposited items remain visible drop nodes snapped to their zone cell (Stonehearth's look —
the stockpile IS the pile). **Ground zones never stack: one item per tile, exactly like
Stonehearth's ground stockpiles.** The first build stacked invisibly per cell (`stack_max`),
which Alen's playtest caught immediately: physical storage with hidden counts is a hybrid SH
deliberately avoids — quantity must be WYSIWYG. `stack_max` in `resources.json` is retired
from ground zones and reserved for the CONTAINER path (barrel/chest/shelf capacity), which is
also the SH split (readable ground zones, dense containers). Capacity = empty cells; doc 23's
`tile_count × 8` rule is superseded — update doc 23 when the UI pass lands.

---

## 2.5 Stonehearth reference findings (verified from `P:\stonehearth` source, 2026-07-06)

Read directly from `components/storage/storage_component.lua`,
`services/server/inventory/restock_director.lua`, `ai/task_groups/restock_task_group.lua`,
`entities/containers/*`, and `data/constants.json`. What Stonehearth actually does:

### One storage component, many faces

The ground stockpile is **not a separate system** — `entities/construction/stockpile` is just
`"stonehearth:storage": { "type": "stockpile" }`. Every storage form shares one
`storage_component` with a `type` field:

| Type | Behaviour |
|---|---|
| `stockpile` | Ground zone, 1 item per tile |
| `crate` / `urn` | Placeable container, no special behaviour — pure capacity density |
| `input_crate` | **Kept filled by workers** pulling from other storage; single-filter; own restock director at HIGHER priority than general hauling (0.5–1 vs 0–0.8) |
| `output_crate` | Crafters deposit products; haulers never restock it |
| `backpack` | Private per-character storage — every hearthling carries capacity **4** |
| `crafter_backpack` | Infinite ingredient-gathering pouch for crafters |
| `escrow` | Temporary holding during shop transactions |

### The container ladder (capacity / gold value)

Small crate **8**/2g → large crate **32**/4g → large urn **32**/13g → chests → vault
**256**/150g. Containers are the *upgrade path* from ground zones: same filter UI, same
hauling, ~4–32× the density per tile. Flavour variants (wood/clay/stone/iron/woven) are
pure reskins of the same component.

### Shelves exist — and display their contents

`input_shelf_wall_*` (wall-mounted!), `input_shelf_ground_*`, input bins/corners/tables, and
`output_box_*` all carry `"render_contents": true` — stored items are **visibly placed on the
shelf**. A shelf is not new machinery; it is a storage container whose contents render.
Market shelves (`market_shelf_tall_*`) extend the same idea toward trade display.

### Hauling efficiency: errands + backpacks

The per-player **restock director** keeps a priority queue of loose restockable items and
builds **errands**: one main item + up to `MAX_EXTRA_ITEMS = 3` nearby items bound for the
same storage — a worker's 4-slot backpack carries the batch in one trip
(`fill_backpack_from_items` → `fill_storage_from_backpack`). Errands are leased to a worker
(1 s consider lease, permanent on execute); unreachable items go to a failed list requeued
after 10 min in batches of 50 (their equivalent of our backoff). Undeploying a container
dumps its contents after a `DROP_ALL_TIMEOUT` (2 h).

### <span style="color:#3fb950;">What doc 18 adopts now</span>

- **Design the zone as one face of a storage interface, not a one-off.** v1 ships the ground
  zone only, but `StockpileZoneComponent`'s accept/reserve/deposit surface becomes the shared
  contract (`accepts` / `reserve_deposit_cell` / `deposit` / `stockpile_changed`) that
  container entities implement in the follow-on — matching how doc 61's Barrel and
  Chest/Crate furniture become *functional* later.
- **Trip batching — the pouch (SHIPPED 2026-07-06, same day):** full SH parity. A haul pull
  is a BUNDLE: the nearest accepted item plus up to `pouch_capacity − 1` (3) extras within
  `pouch_bundle_radius` (8) of it, visited in greedy nearest-neighbour order, carried as a
  visible stack, multi-deposited in one trip. **The pouch carries anything, stone included**
  (Alen 2026-07-06 — SH has no weight limit; the first cut's heavy-solo rule would have made
  the pouch useless for mining output, since nearly all mining drops are `heavy`). Any heavy
  item aboard applies ×`carry_speed_mult_heavy` for the whole trip. Config keys in
  `task_config.json` `hauling`; `resources.json` weight_class comment updated to match.
- **Failed-item requeue = our backoff** — already how TaskManager works; no new machinery.

### Parameter comparison (verified from source, 2026-07-06 — Alen's ask)

| Parameter | Deepdraft | Stonehearth | Note |
|---|---|---|---|
| Concurrent haulers | 2 per zone (`max_haulers_per_zone`) | global `max(10, active restock workers)` — no per-storage cap | SH rations errands per COLONY, scaled to workforce; our per-zone cap idled 3 of 5 dwarves in the first playtest |
| Items per trip | 1 | 4 (backpack 4 = main + `MAX_EXTRA_ITEMS` 3) | the pouch upgrade (below) |
| Haul vs mine priority | fixed MINE 50 > HAUL 40 | mine fixed 0.4; restock a 0.2–0.7 utility band — good errands OUTRANK mining | worth a scheduler colony-bonus pass later |
| Failed-item retry | backoff 2^n ≤ 30 s | flat 10 min, batches of 50 | ours recovers faster — keep |
| Reservation expiry | release-protocol only | 1 s consider lease / 3 h storage lease / 20 s validity cache | their timers guard races Hard Rule 12 prevents structurally |
| Carry speed | heavy ×0.7 | none found | deliberate Deepdraft flavour — keep |
| Ground-zone density | ~~stack per cell~~ → **1 item/tile (adopted 2026-07-06)** | 1 item/tile; density via containers | hidden stacking failed the readability test in play; SH parity chosen, density deferred to containers |

### <span style="color:#d29922;">Recorded for follow-on milestones (not v1)</span>

- **Worker-scaled hauling (the SH model):** replace the per-zone cap with a colony-level
  errand budget scaled to available workers (`max(10, active haul workers)` in SH). Interim
  dial: `max_haulers_per_zone` 2 → 4 (2026-07-06, after the 3-idle-dwarves playtest). The
  pouch half of this item shipped 2026-07-06 (§ above).
- **Haul-utility priority band:** close item + close storage should be able to outrank mining
  (SH: restock 0.2–0.7 vs mine 0.4). Touches the scheduler's colony-bonus model (doc 16 §2.2).

- **Container entities** (barrel = small crate 8, chest = large crate ~24–32, shelf below) —
  placeable storage sharing the zone's interface; needs the furniture-placement tool first.
- **Storage Shelf** (Alen's ask, 2026-07-06): a 1×1, 2-block-tall wall-adjacent furniture
  piece, capacity ~8–12, **contents rendered on the shelf** (micro-voxel drop GLBs already
  exist — placing them on shelf anchor points is the same trick as ground stacks). Dwarven
  aesthetic per doc 61 §5.4: hewn stone uprights, plank shelves, iron brackets.
- **Input/output containers** land with workshops (doc 44): brewery input bin (single-filter,
  restocked at higher priority) and output box slot directly into the doc 23 workshop-lookup
  API — this is the Stonehearth-verified answer to how workshops stay fed.
- **Escrow** pattern noted for the doc 51 trade session.

---

## 3. Milestone phases

### Phase 0 — Instrument first (doc-07 lesson, again)

Overlay row before any behaviour: zones N, stored N, loose N, reserved N, active hauls N.
DEV button: "spawn 20 mixed drops here".

### Phase 1 — Zone designation tool

- Flat marquee on walkable floor (reuse the mining drag/ruler pattern at fixed 1-high;
  `FlagPlacementController`'s validity-tint language). Cells must be standable
  (NavGrid-walkable) at designation time; invalid cells drop out of the preview.
- `StockpileZoneComponent` + per-zone ground overlay (own colour, per-zone node —
  the doc 43 adjacency lesson: zones never merge).
- Dock entry `stockpile` (toggle tool); click a zone → compact window: Remove, filter
  summary, stored count.

Acceptance: paint/remove zones on terraces and flats; overlay obeys the slice; zones
persist across slice steps; no designation on water/occupied/unwalkable cells.

### Phase 2 — Loose-item index + reservations

§2.1. DEV-spawned drops appear in the overlay counts; reserve/unreserve round-trips clean.

### Phase 3 — HAUL leases + executor

§2.2–2.3 end to end with accept-everything filters. Stress: 200 loose drops, 3 zones,
5 dwarves → drops drain nearest-first, frame time flat (the doc 16 §2.5 budgets already
bound the scheduler; haul pulls must stay inside the lease executor, not the scheduler).

Acceptance: mine a pit, paint a zone, watch dwarves clear the pit into tidy stacks;
interrupt mid-carry (DEV button) → item drops at feet, another dwarf finishes the job;
sleep interruption behaves identically; zone full → hauling stops without churn.

### Phase 4 — Aggregates + polish

`StockpileManager.get_total()` + `stockpile_changed` wired to the overlay (status-bar
counters come with the real UI pass, doc 23). Carried-item visual verified against the
walk gait. Heavy-item speed penalty tuned in play.

### <span style="color:#f85149;">Out of scope</span>

Filter panel UI (v1 accepts everything; the data model carries `filter_tags` so the panel
is purely UI later). Status-bar counters. Workshop input consumption. Stack-count badges.
Hauling *between* zones / zone priorities. Save/load (whole-project gap).

---

## 4. Hard rules honoured (checklist for review)

1. **Rule 12 (release protocol)** — carried item drops at the dwarf's feet; §2.3 step 5.
2. **O(intents)** — leases per zone, never per item; index event-maintained, no scans.
3. **JSON vs GDScript** — `max_haulers`, carry speeds already in `resources.json`
   (`weight_class`); new tunables go to `data/tasks/task_config.json` under a `hauling` block.
4. **Namespaced IDs** — `cell_stacks` stores item keys, never runtime ints.
5. **Registry pattern** — `ItemDropManager` stays the sole owner of `resources.json`;
   StockpileManager queries it, never opens the file.
6. **Scene decoupling** — zone components owned by their controller; cross-system flow via
   TaskManager signals; StockpileManager is simulation state → autoload (doc 16 dividing line).

---

## 5. Build order & file touch list

| Step | Files | Depends on |
|---|---|---|
| 0. Instrumentation + DEV drop spawner | `DebugLoadingOverlay.gd`, `DockUI.gd`, `ItemDropManager.gd` | — |
| 1. Designation tool + zone component + overlay | new `scripts/systems/StockpileDesignationController.gd` (scene node), new `scripts/components/StockpileZoneComponent.gd`, `DockUI.gd`, `data/ui/dock.json`, `debug_world.tscn` | — |
| 2. Loose-item index + reservations | `ItemDropManager.gd` | — |
| 3. StockpileManager autoload | new `scripts/systems/StockpileManager.gd`, `project.godot` `[autoload]` (after TaskManager) | 1, 2 |
| 4. HAUL leases + executor + carry visual | `StockpileZoneComponent.gd`, `TaskManager.gd` (HAUL wiring only), `DwarfAgent.gd`, `data/tasks/task_config.json` | 2, 3 |
| 5. Aggregates + overlay wiring | `StockpileManager.gd`, `DebugLoadingOverlay.gd` | 4 |

Reminder from doc 16: after the `[autoload]` edit, **Project → Reload Current Project**
clears the stale analyzer errors.

Docs to update on completion: `23_user_interface.md` (zone model implemented-state,
capacity rule), `31_task_system.md` (HAUL live), `13_architecture.md` (StockpileManager),
this doc's build log.

---

## 6. Open decisions (resolve before or during build)

1. <span style="color:#d29922;">**Deposit-cell choice policy**</span> — nearest-to-item vs
   same-item-stack-first vs fill-from-corner. Lean: same-stack-first, then nearest free
   cell; decide by watching real piles.
2. <span style="color:#d29922;">**`max_haulers` per zone**</span> — start at 2 (mining uses
   4, hauls are shorter trips); pure data, tune in play.
3. <span style="color:#3fb950;">~~Stored-item representation~~ — **DECIDED (Alen,
   2026-07-06): one item per tile, no ground stacking (SH parity).** Every stored item keeps
   its own node on its own cell; quantity is WYSIWYG. `stack_max` moves to the container
   path. Supersedes the earlier one-node-per-stack lean.</span>
4. <span style="color:#d29922;">**Rough-stone flood, round 2**</span> — hauling makes the
   0.25 drop rate a labour sink, not just clutter. Watch whether haul labour swamps mining;
   the dial is `block_resources.json`.
5. <span style="color:#d29922;">**Storage interface shape**</span> — §2.5 adoption: how much
   of the container-facing interface to formalise in v1 (a thin `StorageTarget` contract the
   zone implements vs just keeping the zone's methods clean for later extraction). Lean:
   clean methods now, extract the contract when the first container ships.
6. <span style="color:#d29922;">**Container milestone scope**</span> — barrel/chest/shelf as
   the immediate doc 19 (needs the furniture placement tool), or defer containers until
   workshops force the input/output bin question. Alen's shelf interest suggests sooner.

---

## 7. Build log

### Playtest notes — logged 2026-07-06 (Alen, first Phase 1 session)

1. **"Free workers are not carrying things to the zone"** — expected at this point, not a
   defect: hauling is Phases 2–3 (loose-item index + HAUL leases), not yet built. Zones are
   inert paint until then. Recorded so the expectation is explicit.
2. **Show the marquee size while drawing** — the player should never count voxels. Add a
   live `W × D — N cells` readout on the drag (the mining tool's ruler lesson, doc 43).
   → **Shipped same day** (build-log row below).
3. **Zone filtering UI** — clicking a zone must eventually open a real filter panel (what is
   and isn't stored there). The data model already carries `filter_tags` and the zone window
   is the entry point; the panel itself stays a follow-on (out-of-scope list, §3) — likely
   alongside the doc 23 category UI. Stonehearth reference: hierarchical filter groups with
   per-category toggles + an optional single-filter mode for input bins (§2.5).

| Date | Steps | State |
|---|---|---|
| 2026-07-11 | **Closeout session.** (a) Spam-robustness review of the full interrupt/release surface (the pouch row's open item): found and fixed an **owner-clobber race** — `ItemDropManager.unreserve` had no owner check, so an interrupted hauler's bundle cancel (`cancel_haul` unreserving `items[taken..]`) could erase another hauler's reservation of a skipped-then-re-reserved item; `unreserve(node, dwarf_id)` now guards on the reserving dwarf. Also fixed: pouch drops at the feet landed dead-centre with no jitter — 4 items read as 1 (the WYSIWYG failure again); `drop_loose` now jitters like `spawn_drop`. (b) **Checklist defect (Alen): a stocked zone was unremovable with the tool off** — zone click-select was gated on `_active`, unlike the mining controller's INACTIVE branch; `_try_select_zone_at_screen` added, mining parity. Docs 23 (capacity rule, implemented state) + 31 (HAUL live) updated. | **VERIFIED in-engine by Alen, 2026-07-11 — full checklist: one-item-per-tile (20 drops → 20 tiles, full zone stops clean, zone removal returns items loose), flag-crash repro clean, pouch interrupt drops 4 visible items, interrupt spam leaves no stuck dwarves or orphaned reservations, tool-off zone select works. MILESTONE CLOSED.** Live tuning dials carried forward: `max_haulers_per_zone` (4), rough-stone drop rate (0.25), haul-utility priority band. |
| 2026-07-06 | **The pouch (Alen: "they still grab one item at a time" — SH batching adopted).** `reserve_haul` now reserves a BUNDLE: main item + up to `pouch_capacity − 1` (3) light extras within `pouch_bundle_radius` (8) of the main, each pairwise with a reserved deposit cell (partial bundles when the zone runs short; **pouch carries anything incl. heavy — Alen's call, since ~all mining drops are heavy; any heavy aboard = ×0.7 trip speed**). Items returned in greedy nearest-neighbour visit order; the executor chains HAUL_TO_ITEM per item (skips broken/unreachable ones — only an entirely empty-handed round counts as a failure), carries the pouch as a visible chest-height stack (`CARRY_STACK_STEP`), and multi-deposits onto per-item cells. `cancel_haul`/`skip_item` free partial reservations; interrupts drop the WHOLE pouch at the feet (Hard Rule 12). New: `ItemDropManager.loose_near` (radius search), config keys `pouch_capacity` 4 / `pouch_bundle_radius` 8. Component bundle block isolation-parsed. | **VERIFIED in-engine by Alen, 2026-07-06 ("works") — pouch BANKED.** Interrupt-spam robustness on a full pouch still worth a pass in a future session. |
| 2026-07-06 | **One-item-per-tile revision (Alen playtest: "rocks are stacking without me being able to see that").** Hidden per-cell stacking confirmed (rough stone ×10, iron ×15 behind one visible lump) and compared against SH source: their ground stockpiles reserve space per item and never stack; their `stonehearth:stacks` is an internal uses-left counter (clay mound = 60 digs), tooltips only; containers hide contents behind UI; shelves render contents on `ATTITEM*` bones. Decision (Alen): **SH parity — one item per tile.** `_find_deposit_cell` takes empty cells only, `commit_haul` always keeps the node (WYSIWYG), `_has_any_room` = any empty unreserved cell; `stack_max` reserved for containers. §2.4 + §6.3 + comparison table updated. | Implemented — verify: haul 20 drops into a ≥20-cell zone → 20 visible items on 20 tiles, nearest-cell-first; a full zone stops hauling cleanly. |
| 2026-07-06 | **Defect fix (Alen, in-engine: drew a zone, placed the flag, crash).** Two stacked bugs: (1) `_on_left_release` built the 1×1 short-click list with a ternary — `[x] if c else []` yields a plain `Array` and crashes assigning to `Array[Vector3i]` at RUNTIME (gdparse-invisible; house rule extended: never build typed arrays via ternary); (2) the tool-exclusion wart made it reachable — the flag button never announced itself, so the still-active zone tool consumed the flag-placement click as a short-click confirm. Fixed properly: DockUI's flag branch now emits `tool_requested("flag")`, and ALL THREE click-tools (mining, storage zone, flag) deactivate on any other tool's id — the doc 16 known wart is closed, not worked around. | Implemented — re-run the crash repro: draw a zone, then place the flag; the zone tool should visibly deactivate the moment the flag tool opens, and the flag should place clean. |
| 2026-07-06 | Phases 2 + 3 (hauling live): **ItemDropManager** grew the loose-item index (§2.1 API: `nearest_loose`/`count_loose`/`reserve`/`take`/`place_stored`/`drop_loose`/`release_stored_cells`, `drop_spawned` signal, `get_item_def` accessor — registry pattern holds); **StockpileZoneComponent** is now a work source (`update_leases` posts ≤ max_haulers HAUL leases; `reserve_haul`/`take_item`/`commit_haul`/`cancel_haul`; `nearest_stand_target` for the scheduler probe hook, which was **generalised from MINE-only to any source** in TaskManager); new **StockpileManager** autoload (zone registry, lease wake plumbing throttled at 0.25 s, aggregates + `stockpile_changed`, hauling config via new `TaskManager.get_config_section` — task_config.json gains a `hauling` block); **DwarfAgent** HAUL executor (§2.3 loop: pull → walk → pick up (carried node at chest, heavy ×0.7 walk speed) → walk → deposit; 3 failures release with backoff; carried item drops at the feet on ANY interrupt — Hard Rule 12 wired into sleep/DEV-interrupt/abort teardown). Work-source id collision avoided by `SOURCE_ID_BASE = 1_000_000` (tech debt: TaskManager-owned allocator when a third source system appears). Review catch: released leases stay PENDING and keep counting against max_haulers — only completed/cancelled/failed erase the lease id. All parse-verified. | **Implemented — NOT yet verified in-engine.** Verify per Phase 3 acceptance: mine a pit (or DEV: Spawn Drops), paint a zone → dwarves clear the drops into tidy per-cell stacks (same-stack-first); DEV interrupt mid-carry → item drops at feet, another dwarf finishes; tire a hauler → same; zone full → hauling stops without churn; remove a stocked zone → items return loose (stacked counts respawn); overlay `storage:` row: stored climbs, loose drains, reserved breathes. REMINDER: new autoload `StockpileManager` → **Project → Reload Current Project** after opening, per the doc 16 lesson. |
| 2026-07-06 | Playtest note 2 fix: live drag-size readout — a billboard `Label3D` above the marquee centre showing `W × D — N cells` (or `N of M valid` when cells drop out). gdparse-clean. | Implemented — verify with the Phase 1 re-run. |
| 2026-07-06 | Phases 0 + 1: `StockpileZoneComponent` (data model + the §2.5 storage-contract surface: accepts / reserve_deposit_cell / deposit, same-stack-first policy per §6 decision 1 lean); `StockpileDesignationController` scene node (flat marquee with anchor-plane height lock, per-cell NavGrid validity with invalid cells dropping out, 1×1 short-click zones, per-zone fill+perimeter overlay in blue-cyan, slice culling, compact zone window with Remove, ESC-only cancel per doc 21); dock Storage Zone panel wired (Draw Zone activates the tool; DEV: Spawn Drops scatters the 20-item mix at the view centre — all keys have real GLBs); overlay `storage:` row (zones/cells/stored/loose/reserved); `ItemDropManager.get_stats` extended with loose/reserved; scene wiring in `debug_world.tscn`. All new/edited scripts gdparse-clean. Known warts, accepted: mining tool ignores `tool_requested("storage_zone")` (the existing tool-exclusion DEV wart — my controller does deactivate when another tool activates); dock button active-state refreshes on next dock interaction rather than instantly on ESC. | **Implemented — NOT yet verified in-engine.** Verify per Phase 1 acceptance: paint/remove zones on terraces and flats (marquee stays flat on the anchor plane across slopes); invalid cells (water/occupied/steep) drop out of the preview; short click = 1×1; click a zone → window with live cell/stored counts + Remove; overlay obeys the slice; DEV: Spawn Drops litters ~20 mixed drops at the view centre and the overlay `storage:` row counts them as loose. REMINDER: no new autoloads this pass — no editor reload needed. |

---

*Prev: [17_dwarf_visual_polish.md](./17_dwarf_visual_polish.md)*
