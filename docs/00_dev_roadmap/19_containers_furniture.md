# 19 - Storage Containers & Furniture Placement (Third Colony Milestone)

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = decided / ready to build</span> |
> <span style="color:#d29922;">Yellow = decision needed or tune-in-engine</span> |
> <span style="color:#f85149;">Red = explicitly out of scope for this milestone</span>

Status: plan, drafted 2026-07-11; **revised same day after the P:\stonehearth deploy/undeploy
source review (Alen's ask — furniture placed FROM storage, 📥 place / 📤 uninstall).**

**Why this milestone:** doc 18 shipped ground stockpiles with a deliberate density ceiling —
one item per tile, WYSIWYG (Alen, 2026-07-06). Density was explicitly deferred to
**containers**, the Stonehearth-verified upgrade path (small crate 8 → large crate 32 →
vault 256; doc 18 §2.5). Containers need a **furniture pipeline**, which does not exist —
and that pipeline is the gateway for every future placeable: workshop props (doc 44),
tavern furniture (doc 51), the Armory's stands and displays (doc 52), beds, torches.
Following the Stonehearth review (§2 below), furniture is not conjured — it is an **item**
that dwarves fetch from storage and install, and uninstall back into storage. Both
directions ride the doc 18 haul pipeline. The doc 16 architectural bet gets its third and
fourth tests: containers post HAUL leases; placement ghosts post FETCH-AND-BUILD leases.

Deliverable: **the player 📥-places a barrel, chest, or storage shelf as a ghost from the
Build panel; a dwarf fetches the furniture item and installs it; dwarves haul loose drops
into the installed container; 📤 marks it for uninstall — a dwarf breaks it down into its
item form (contents dumped loose) and normal hauling restocks everything — with every step
interruptible under the release protocol.**

---

## 1. Where Deepdraft stands today (gap analysis)

| Piece | State today | Gap |
|---|---|---|
| Furniture data schema | `data/furniture/trade_counter.json` — rich canonical schema (footprint, collision_regions, room_anchor…) but nothing loads it | No loader, no other furniture defs, no ITEM-form defs |
| Furniture assets | **None.** `assets/models/` has flora + items only; doc 61 §5.4 has authored SPECS for barrel + storage crate | Full-size GLBs (placed form) + item-drop GLBs (carryable form); shelf needs a doc 61 spec |
| Placement tool | `FlagPlacementController` — single-entity ghost + validity tint + `PlacedEntityRegistry.register_box` (256 lines, one-shot) | No data-driven ghost tool, no rotation, no fulfilment leases |
| Entity occupancy | `PlacedEntityRegistry` + `occupancy_changed` → NavGrid invalidation, proven by flag + trees | Nothing — reused as-is |
| Item pipeline | `ItemDropManager` loose-item index + reservations + hauling, shipped + verified 2026-07-11 | Furniture item defs join `resources.json`; a new `stockpile_furniture` filter tag |
| Storage logic | `StockpileZoneComponent` — accept/reserve/deposit + the pouch haul loop, designed as the future shared contract (doc 18 §2.5) | Extract the contract; container implements it with slots instead of cells |
| Source ids | Mining raw; stockpile zones at 1M offset; **doc 18 tech debt: TaskManager allocator "when a third source system appears"** | Third AND fourth families arrive (containers, ghosts) — the debt is due |
| UI | Dock `build` panel entry exists, panel is a stub | Build panel gets 📥 placement; furniture window gets 📤 |

---

## 2. Stonehearth reference findings (verified from `P:\stonehearth` source, 2026-07-11)

Read directly from `components/entity_forms/entity_forms_component.lua`,
`lib/entity_forms/entity_forms_lib.lua`, `call_handlers/place_item_call_handler.lua`,
`ai/actions/pickup_placed_item_adjacent_action.lua`, `place_item_type_on_structure_2.lua`,
and `data/commands/undeploy_item/`.

### The three-form model

Every placeable item is ONE logical entity with three representations:

| Form | What it is | Where it lives |
|---|---|---|
| **Root** | Full-size deployed object | In the world, registered with nav/collision |
| **Iconic** | Small carryable lump | In stockpiles/containers, in a worker's hands, loose on the ground |
| **Ghost** | Translucent placement preview | In the world as a **persistent task marker** until fulfilled |

The player's inventory tracks root XOR iconic depending on which is in-world — a parent
trace swaps them (`_on_parent_changed`). The ghost copies the root's collision shape but
sets it to `RegionCollisionShape.NONE`: **nav is unaffected until the item is actually
installed.**

### Place = a standing request, type-matched

`place_item_type_in_world` drops a ghost and asks the town for fulfilment. The AI action
matches **any iconic of that URI** (not a specific instance) that is not itself being
placed, leases it, and a worker carries it to the ghost and swaps ghost → root. The UI
returns `more_items` so the tool can stay active while stock remains.

### Undeploy = a restock toggle, then normal hauling

`undeploy_item` sets `should_restock` on the placed item (a TOGGLE — clicking again
cancels), shows an overlay effect, and cancels competing tasks. A worker executes
`pickup_placed_item_adjacent`: walk adjacent, `work` effect, unparent the root, pick up
the **iconic** — from that moment it is ordinary restockable inventory and the doc 18-style
restock machinery stores it. Undeploying and placing are mutually cancelling
(`_place_item` calls `set_should_restock(false)`; restocking cleans up placement tasks).

### Gear worth stealing later (recorded, not v1)

- **Command locking:** an item placed ON another (lamp on table) locks the base item's
  move/undeploy commands until the child leaves (`_on_children_changed`).
- **Placement limits:** `stonehearth:item_placement_limit` caps per-town placements by tag.
- **Ladders:** wall placements auto-request pickup/put-down ladders — skip until walls.
- **Move-item:** relocation = the same ghost pipeline with `moving_placed_item = true`.

### <span style="color:#3fb950;">What doc 19 adopts</span>

The full three-form pipeline, translated: furniture ITEM defs in `resources.json` (iconic ≙
our existing item drops), full-size placed form registered in `PlacedEntityRegistry`, ghost
as a work source posting a FETCH-AND-BUILD lease, 📤 as a toggle flag that posts an
UNINSTALL lease, type-matched fetches, nav untouched by ghosts. Skipped: walls/ladders,
placement limits, move-item (uninstall + re-place covers v1), command locking (nothing
stacks on furniture yet).

---

## 3. ARCHITECTURE

### <span style="color:#3fb950;">3.0 Direction</span>

1. **Furniture is an item with a placed form — never conjured.** The item form is a normal
   `resources.json` entry (drop GLB, `stockpile_furniture` tag) that mining… does not
   produce; v1 items enter via a DEV spawner (economy fills this via crafting/trade later).
   The placed form is the full-size GLB + occupancy + (for storage pieces) a storage
   component.
2. **The ghost is a work source (doc 16 §2.1, fourth family).** Placing with 📥 creates a
   `FurnitureGhost` that posts ONE fetch-and-build lease, type-matched against the
   loose-item index and storage aggregates. No dwarf, no fulfilment — the ghost waits
   patiently, exactly like a mining designation.
3. **📤 is a toggle, not a command (SH parity).** It flags the placed piece; the flag posts
   an uninstall lease; clicking 📤 again clears flag + lease. Uninstall dumps stored
   contents as loose drops, swaps placed form → item form at the stand cell, and the
   ordinary doc 18 hauling puts everything away.
4. **One storage contract, many faces (doc 18 §2.5).** `StorageComponent` base owns the
   haul-loop machinery; ground zone = per-item floor cells; container = capacity slots
   behind one stand cell. The `DwarfAgent` haul executor is untouched.
5. **The WYSIWYG split is a principle:** ground zones + shelf show every item they hold
   (shelf capacity = anchor count); barrel/chest trade visibility for density and show
   counts in their window.
6. **Release stays cheap and legal (Hard Rule 12):** an interrupted fetcher drops the
   furniture item at its feet (it re-enters the index; the ghost re-leases); an
   interrupted uninstaller leaves the piece installed with the 📤 flag still set.

### 3.1 Furniture data

Three defs following the `trade_counter.json` schema, `furniture_category: "storage"`, plus
NEW shared fields: `item_key` (the resources.json item form), `placement` (`"floor"` |
`"floor_wall"`), `yaw_steps: 4`, and a `storage` block for containers:

| Def | Footprint | Storage block | Item form (resources.json) |
|---|---|---|---|
| `base:furniture:barrel` | 1×1, 1 tall | `{ "capacity": 8, "render_contents": false }` | `base:resources:furniture:barrel` |
| `base:furniture:storage_chest` | 1×1, 1 tall | `{ "capacity": 24, "render_contents": false }` | `base:resources:furniture:storage_chest` |
| `base:furniture:storage_shelf` | 1×1×2, **ground** (Alen 2026-07-11 — wall req. dropped; model to be hand-authored symmetric) | `{ "capacity": 8, "render_contents": true, "anchors": [×8] }` | `base:resources:furniture:storage_shelf` |

Item forms get `material_tags: ["stockpile_furniture"]` (new filter tag; zones' v1
accept-everything default gains it) and `weight_class: "heavy"`. `storage.anchors` are
local float offsets (blocks) where stored item GLBs render on the shelf.

**Loader:** `FurniturePlacementController` owns `data/furniture/*.json` (system-owns-its-
data, doc 13). Item defs stay solely with `ItemDropManager`.

### 3.2 Placement tool — 📥 (`FurniturePlacementController`, scene node)

- Build panel: one 📥 entry per placeable → `tool_requested("furniture")` + def key; joins
  the click-tool exclusion contract (2026-07-06 fix).
- **Ghost preview** on the cursor: the placed-form GLB, translucent, validity-tinted
  (flag-tool language), yaw in 90° steps on <span style="color:#d29922;">**R** (lean — the
  wheel is contractually camera/brush, doc 21)</span>.
- **Validity:** footprint cells NavGrid-walkable at one floor Y, unoccupied
  (`PlacedEntityRegistry`), not on stockpile-zone cells, not water; `floor_wall` probes the
  block behind the ghost's back face for solidity.
- **On confirm:** a `FurnitureGhostComponent` is created (translucent node stays in-world —
  the SH persistent task marker; **no occupancy registration** — ghosts are non-solid) and
  registered as a work source. Tool stays active while matching items remain (SH
  `more_items`); ESC-only cancel.
- **Click-select with the tool off** (the doc 18 A3 lesson, built in from day one): clicking
  a ghost opens its window (item wanted, Cancel 📥); clicking an installed piece opens
  contents summary + **📤 Uninstall** (toggle) + the container inventory list.

### 3.3 Fetch-and-build lease (the ghost work source)

```
1. Ghost posts ONE lease (type-matched: item_key present loose OR in colony storage)
2. Dwarf pulls: nearest matching item — loose (index) first, else withdraw from the
   nearest zone cell / container holding one (storage components gain
   withdraw(item_key, dwarf_id) -> Node3D; zone cell empties, container count drops)
3. Carry to the ghost's stand cell (heavy carry speed) -> `work` swing timer
4. Swap: item node freed; placed form instanced; collision_regions boxes registered with
   PlacedEntityRegistry (NavGrid invalidates); storage component created + registered
   with StockpileManager; ghost destroyed; lease completes
5. Interrupt anywhere: item drops at the feet (re-enters index), ghost re-leases —
   Hard Rule 12
```

No matching item in the colony → the lease stays PENDING under the normal backoff; the
ghost window shows *"needs: barrel (none in colony)"*.

### 3.4 Uninstall lease — 📤

📤 toggles `flagged_uninstall` on the placed piece. While set: an overlay tint on the
piece (SH's undeploy overlay, our validity-tint language), its storage component stops
posting HAUL leases and cancels live ones, and ONE uninstall lease posts:

```
1. Dwarf walks to the stand cell -> `work` swing timer
2. Stored contents dump as loose drops at the stand cell (jittered — 2026-07-11 fix)
3. Placed form freed; occupancy unregistered (NavGrid); storage deregistered;
   item-form drop spawns at the stand cell
4. Everything on the ground is now ordinary loose inventory — existing zone/container
   leases wake on drop_spawned and put it all away
```

📤 again before step 1 completes → flag cleared, lease cancelled, piece untouched.

### 3.5 Storage contract extraction (`scripts/components/StorageComponent.gd`)

The doc 18 §6.5 lean, executed: hoist from `StockpileZoneComponent` everything that is not
cell-specific —

```gdscript
# StorageComponent (base, RefCounted) — the haul work-source machinery
#   update_leases / on_task_gone / reserve_haul / cancel_haul / take_item /
#   skip_item / commit_haul / nearest_stand_target          (doc 18 §2.2–2.3, unchanged)
# Subclass surface (abstract):
#   _reserve_deposit(item_key, near, dwarf_id) -> Variant   # zone: cell; container: slot token
#   _release_deposit(token) / _commit_one(token, item_key) / _has_any_room()
#   _deposit_walk_target() -> Vector3i                      # zone: first cell; container: stand cell
#   _place_visual(node, token) -> void                      # zone: place_stored; container: absorb/anchor
#   withdraw(item_key, dwarf_id) -> Node3D                  # NEW (fetch-and-build, §3.3)
```

`StockpileZoneComponent extends StorageComponent` — behaviour identical; **the doc 18
verification checklist re-runs as the regression gate.** New
`ContainerStorageComponent extends StorageComponent`: flat inventory (item_key → count),
capacity check, one stand cell, counted-slot reservations. `render_contents` false → the
deposited node is freed (the barrel absorbs it; window shows counts); true → the node
snaps to the next free anchor at <span style="color:#d29922;">~0.45 scale (tune by
eye)</span>, slice-culled. `StockpileManager` registers containers like zones; aggregates
and `stockpile_changed` span both.

### 3.6 Source-id allocator (the doc 18 tech debt, now due twice)

`TaskManager.allocate_source_id() -> int` — monotonic from 10,000,000. Containers and
ghosts use it. <span style="color:#d29922;">Migrating mining (raw ids) and zones (1M
offset) is optional cleanup — lean: new families only.</span>

### <span style="color:#f85149;">3.7 Explicitly out of scope</span>

Crafting/buying furniture items (v1 source = DEV spawner; doc 44 crafting and doc 51 trade
fill it for real). Input/output bins + restock priority bands (doc 44). Filter panel UI.
Move-item (uninstall + re-place). Wall/structure placement, ladders. Command locking
(nothing stacks on furniture yet). Placement limits. Trade counter placement (needs room
detection, doc 51). Beds, tavern, Armory furniture. Save/load (whole-project gap;
NOTE: ghosts and 📤 flags join the growing unsaved-state list).

---

## 4. Milestone phases

### Phase 0 — Instrument first (doc 07 lesson, third time)

Overlay `storage:` row grows `containers N`; new `furniture:` row: ghosts N / installed N /
uninstalling N. DEV: **Spawn Furniture Items** button (one item of each of the three).

### Phase 1 — Assets + data

`tools/generate_furniture_glbs.py` (items class: **8 vox/block, 0.125 baked**, the doc 61
§5.7 convention): `barrel.glb`, `storage_crate.glb`, `storage_shelf.glb` per doc 61 §5.4
specs (+ NEW shelf spec: 1×1×2, heavy wood uprights, two plank levels, iron brackets —
material rule, Alen 2026-07-11: furniture is woodwork; GROUND shelf, same-day revision:
no wall requirement, model slated for Alen's hand-authoring, symmetric from all angles;
anchors clear of uprights — add to doc 61 when the asset ships). Item-form drop GLBs
(mini versions, same generator). `resources.json` gains the three item defs + the
`stockpile_furniture` tag; three furniture JSONs (§3.1). Review renders to
`tmp/furniture_review/`.

Acceptance: placed + item forms load in-engine at correct scale beside a dwarf; doc 61 §7
silhouette checklist passes.

### Phase 2 — Ghost placement tool

§3.2 without fulfilment: Build panel 📥 wiring (`dock.json`, DockUI), ghost preview +
validity + R-rotation, confirmed ghosts persist (non-solid, slice-culled), ghost window
with Cancel, click-select with tool off, tool exclusion verified. DEV: **Instant Build**
button on the ghost window (materialises without a dwarf — the DEV-mine precedent) so
Phase 4 storage work can proceed before Phase 3 lands.

Acceptance: place ghosts for all three pieces on flats/terraces (~~shelf wall
requirement~~ — dropped, Alen 2026-07-11: ground shelf; the `floor_wall` machinery stays
for future wall pieces — wall torch, wall display); ghosts never block pathing; ESC exits;
cancel cleans up; zones cannot be painted under ghosts/furniture and vice versa.

### Phase 3 — Fetch-and-build + uninstall leases

§3.3 + §3.4 + allocator (§3.6). DEV-spawn items → dwarves fetch and install; 📤 →
break-down + restock chain end to end.

Acceptance: ghost + item in the world → a dwarf installs it (nav blocks only on install);
ghost with NO item → lease waits, window says needs; interrupt the fetcher mid-carry →
item drops, another dwarf finishes; 📤 a stocked barrel → contents + barrel item all end up
back in zones; 📤 twice quickly → nothing happens; the doc 18 conservation check holds
(loose + stored + carried + installed is constant).

### Phase 4 — Storage contract + container hauling

§3.5: extract `StorageComponent`, re-base the zone (**regression gate: full doc 18
checklist re-run**), add `ContainerStorageComponent` + StockpileManager registration.

Acceptance: zone AND installed barrel near a drop field → both fill via leases; barrel
absorbs (window count climbs, stops at 8); withdraw works (a fetch lease pulls a stored
furniture item OUT of a zone/container); interrupt mid-trip → Rule 12; overlay reconciles.

### Phase 5 — Shelf contents + polish

Anchor rendering, slice-culling of anchored items, container window inventory list,
aggregates verified, carry/deposit visuals against the walk gait.

Acceptance: 8 mixed drops onto a shelf → all 8 visibly sit on the levels; slice hides
shelf + contents together; 📤 the shelf → 8 + the shelf item drop loose; `get_total()`
matches zones + containers throughout.

---

## 5. Hard rules honoured (checklist for review)

1. **Rule 12** — fetcher drops the item, uninstaller leaves the piece installed; §3.3/§3.4.
2. **O(intents)** — one lease per ghost, per uninstall flag, per container stream; no
   per-item tasks; indexes event-maintained.
3. **JSON vs GDScript** — capacities, anchors, footprints, yaw, item_key in
   `data/furniture/*.json`; item defs in `resources.json`; behaviour in components.
4. **Namespaced IDs** — `base:furniture:*` + `base:resources:furniture:*`; never ints.
5. **Registry pattern** — FurniturePlacementController sole reader of `data/furniture/`;
   item defs only via `ItemDropManager`.
6. **Entity decoupling (doc 12)** — terrain grid never learns about furniture; occupancy
   via `PlacedEntityRegistry` boxes; ghosts register nothing.
7. **Scene decoupling** — controller is a scene node; components RefCounted; cross-system
   flow via TaskManager/StockpileManager signals.
8. **Never touch `.tres` / `.import`.**

---

## 6. Build order & file touch list

| Step | Files | Depends on |
|---|---|---|
| 0. Overlay rows | `DebugLoadingOverlay.gd` | — |
| 1. Assets + data | new `tools/generate_furniture_glbs.py`, `assets/models/furniture/*.glb`, `assets/models/items/furniture/*.glb`, `data/entities/items/resources.json`, new `data/furniture/{barrel,storage_chest,storage_shelf}.json`, doc 61 §5.4 shelf spec | — |
| 2. Ghost tool | new `scripts/systems/FurniturePlacementController.gd`, new `scripts/components/FurnitureGhostComponent.gd`, `data/ui/dock.json`, `DockUI.gd`, `debug_world.tscn` | 1 |
| 3. Fetch/build + uninstall | `FurnitureGhostComponent.gd`, new `scripts/components/InstalledFurnitureComponent.gd`, `DwarfAgent.gd` (FETCH/UNINSTALL executor arms), `TaskManager.gd` (allocator + task types), `Task.gd` | 2 |
| 4. Contract + containers | new `scripts/components/StorageComponent.gd`, `StockpileZoneComponent.gd` (re-base + withdraw), new `scripts/components/ContainerStorageComponent.gd`, `StockpileManager.gd`, **doc 18 checklist re-run** | 2 (DEV Instant Build) |
| 5. Shelf + windows | `FurniturePlacementController.gd`, `ContainerStorageComponent.gd`, `ItemDropManager.gd` (anchor helpers) | 3, 4 |

Docs to update on completion: `23_user_interface.md` (Build panel, 📥/📤), doc 61 §5.4
(shelf spec), `13_architecture.md` (allocator), `31_task_system.md` (FETCH/UNINSTALL
types), doc 18 §2.5 (container follow-on shipped), doc 12 (placed-entity forms note),
this doc's build log.

---

## 7. Open decisions (resolve before or during build)

1. <span style="color:#3fb950;">~~Chest capacity~~ — **DECIDED (Alen, 2026-07-11): 24.**
   The ladder step from barrel 8 stays meaningful without obsoleting ground zones at v1.</span>
2. <span style="color:#3fb950;">~~Rotation input~~ — **DECIDED (Alen, 2026-07-11): R key.**
   The wheel stays contractually camera/brush (doc 21); R goes in the tool's hint window.</span>
3. <span style="color:#d29922;">**Allocator migration scope**</span> — new families only
   (lean) vs migrating mining/zone keyspaces. *SH reference (2026-07-11): SH keys everything
   by globally-unique engine entity ids — ONE id space, no per-system keyspaces. Supports
   the single allocator as the direction; the migration question is our local wart with no
   SH analogue. Lean stands.*
4. <span style="color:#3fb950;">~~New Task.Type entries~~ — **SH-VERIFIED (2026-07-11):
   first-class.** SH has a dedicated `placement_task_group` (band 0.40–0.93, work_order_tag
   "haul", permanent place_item tasks) distinct from restock; undeploy's pickup rides the
   restock flow. Adopt FETCH_BUILD + UNINSTALL as first-class types — and note SH's
   placement band TOPS restock's (0.93 vs 0.8): installing furniture outranks putting
   things away, so FETCH_BUILD default priority goes above HAUL (45 vs 40).</span>
5. <span style="color:#3fb950;">~~Shelf anchor scale~~ — **SH-VERIFIED (2026-07-11): 0.5.**
   SH's input bins/shelves render stored items on ATTITEM bones at `sca [0.5,0.5,0.5]`
   with varied per-anchor rotations (scattered, hand-placed look). Adopt 0.5 + per-anchor
   yaw variation.</span>
6. <span style="color:#3fb950;">~~`stack_max` on containers~~ — **SH-VERIFIED (2026-07-11):
   flat item count.** `storage_component` capacity is a plain number everywhere (crate
   8/32, vault 256); per-type stacking does not exist in SH storage. v1 flat; the per-type
   density idea keeps its reserved note but has no SH precedent.</span>
7. <span style="color:#3fb950;">~~Ghost visual~~ — **SH-VERIFIED (2026-07-11): the real
   model, translucent.** `ghost_form_renderer` is 3 lines: material override
   `ghost_item.json` → transparent-with-depth at **alpha 0.3**. Adopt: placed-form GLB
   with a ~0.3-alpha transparent material (validity tint modulates colour).</span>
8. <span style="color:#3fb950;">~~Hauler target preference~~ — **SH-VERIFIED (2026-07-11):
   nearest wins, no type preference.** `RestockDirector:_rate_storage_for_item` =
   `-distance²` — pure proximity; containers and ground stockpiles compete equally. The
   only preferential storage is the input crate's separate higher-priority director
   (doc 44's problem). v1 nearest-first is exact parity; nothing to watch.</span>

---

## 8. Build log

### Playtest notes

0. **"Dwarves don't want to place the shelf" (Alen, 2026-07-11, Phase 4 session) — the
   builder-entombment defect.** The ghost's stand target was its own origin cell: the
   fetcher stood ON the ghost, built, and the install registered occupancy around them —
   the trapped dwarf's every later probe failed, so each install silently ate a worker
   until the crew stood frozen inside furniture (screenshot: the whole squad clustered on
   the installed pieces; hauling froze mid-chest at 12/24). → **Fixed same day:** ghost
   `nearest_stand_target` returns the nearest walkable cell BESIDE the footprint (never
   inside it — the mining stand-cell model), plus a dwarf-side guard that starts the build
   swing only from a legal stand cell. Already-trapped dwarves need a fresh run (no save
   system — every run regenerates anyway). Incidentally confirmed working in the same
   screenshot: container hauling (chest at 12/24 with live per-item counts).
   *Postscript: applying this fix uncovered that the Phase 3 commit had captured a
   TRUNCATED FurnitureGhostComponent blob (the mount's stale-size cache cut it at the old
   file length — parse-valid by coincidence) while the game ran the correct on-disk file.
   Restored to git in full with the fix; a repo-wide working-tree-vs-blob audit found no
   other damage. Session rule going forward: after any Write-tool rewrite of an EXISTING
   .gd file, verify the git blob size matches the working tree before trusting the commit.*

1. **"The dwarves aren't reacting to it" (Alen, 2026-07-11, first Phase 2 session)** —
   expected at this point, not a defect: ghosts are inert designations until Phase 3
   (fetch-and-build leases). The doc 18 precedent, recorded so the expectation is explicit.
   Interim: the ghost window's DEV: Instant Build materialises the piece without a dwarf.
2. **"Why can't I place the shelf" (Alen, 2026-07-11)** — by design (floor_wall needs a
   solid block behind the back panel; open ground can never be valid) but a UX failure:
   a permanently-red ghost with no explanation breaks the mining-ruler lesson. → **Shipped
   same day:** a billboard hint above the ghost when the wall requirement is the blocker
   ("Needs a solid wall behind — R rotates").
3. **Ground shelf (Alen, 2026-07-11, superseding note 2's premise)** — the wall
   requirement itself is dropped: the shelf is a plain floor piece, placeable anywhere.
   `placement` flipped to "floor" in storage_shelf.json; the `floor_wall` validity path +
   hint stay in the controller for genuinely wall-mounted pieces (wall torch, wall
   display, doc 52). Alen will hand-author a replacement model, symmetric from all
   angles (no back panel); the generated GLB is interim and the generator carries a
   do-not-overwrite note for when the authored asset lands.

| Date | Steps | State |
|---|---|---|
| 2026-07-11 | **Phase 5 (shelf contents on the anchors — the last milestone piece).** `ContainerStorageComponent` grew the anchor renderer: `render_contents` pieces snap each deposited node onto the next free anchor as a CHILD of the piece's visual node (footprint-local offsets from `storage_shelf.json`, re-centred to the node origin) at `anchor_scale` 0.5 with deterministic per-anchor yaw variation (SH ATTITEM parity) — the piece's own rotation and slice-culling apply for free. Withdraws visibly remove an anchored item (`_pop_anchor_node`) before the pre-reserved drop spawns at the stand cell; uninstall dump clears the anchors then respawns counts as loose drops. Barrel/chest keep absorbing. Controller hands `display_parent` at install. | **Implemented — NOT yet verified in-engine.** Verify per Phase 5 acceptance: haul 8 mixed drops onto an installed shelf → all 8 visibly sit on the two levels (scaled ~0.5, varied yaw); the shelf holds at 8; slice hides shelf + contents together; fetch-withdraw from the shelf visibly removes one; 📤 the stocked shelf → 8 drops + the packed shelf, all re-stored by hauling. Alen's hand-authored shelf model still slots in whenever ready (anchors are data, not mesh). |
| 2026-07-11 | **Phase 4 (StorageComponent extraction + container hauling).** The doc 18 §6.5 contract, executed: new `StorageComponent` base owns the ENTIRE haul work-source machinery hoisted verbatim from the zone (lease posting w/ the "zone_id" payload key kept so the DwarfAgent executor is untouched, pouch bundle, owner-guarded reservations, release protocol) against an abstract token surface (`_reserve_deposit`/`_release_deposit`/`_commit_one`/`_deposit_walk_target`/`_place_visual`/`_has_any_room`; tokens are Variant — cells for zones, slot tickets for containers; changed_callback fires in base commit). **`StockpileZoneComponent extends StorageComponent`** — cells/WYSIWYG behaviour preserved line-for-line. **New `ContainerStorageComponent`**: flat inventory (SH parity), capacity slots, stand-cell walk target, absorb-on-deposit (shelf anchors = Phase 5), `withdraw_nearest` via new `ItemDropManager.spawn_reserved` (containers hold counts, not nodes — withdrawn items spawn pre-reserved at the stand cell), `dump_contents` for teardown, `suspended` flag. **StockpileManager**: container registry (register/deregister, lease pass, task routing, withdraw fallback, stats). **Controller `_install`**: storage defs get a container with its OWN source id (a storage piece runs two sources: UNINSTALL + HAUL); 📤 flag suspends the container + cancels its live leases; teardown dumps contents loose BEFORE the packed item spawns. Installed window shows live `Stored: N / cap` + per-item counts. Overlay storage row gains `containers N`. Mount-sync note: the zone rewrite hit the stale-attr NUL-padding variant; recovered via delete + fresh write. | **VERIFIED in-engine by Alen, 2026-07-11 ("pass") — both gate parts: the doc 18 regression against the re-based zone AND container acceptance (fill/compete/uninstall-dump/withdraw), after the builder-entombment fix (note 0). Phase 4 BANKED.** ~~TWO-PART GATE:~~ (1) **doc 18 regression re-run against the re-based zone** — paint a zone by a drop field: pouch bundles, one-item-per-tile, full-zone stop, interrupt drops, zone removal returns items; (2) container acceptance — install a barrel near drops → it absorbs items (window count climbs, stops at 8); zone AND barrel compete nearest-first; 📤 a stocked barrel → haul leases stop, dwarf tears it down, contents + packed item all end up back in zones; fetch withdraws FROM a container when no loose/zone item exists. Editor reload NOT needed for scripts (no new autoloads) BUT three new/rewritten class_name files — **Project → Reload Current Project first** (AGENT.md handoff note). |
| 2026-07-11 | **One-box rule (Alen: "all uninstalled furniture should look like a box" — keep it simple).** The per-piece item minis (mini barrel, mini crate, shelf kit) are replaced by ONE shared `packed_furniture.glb` — a rope-lashed plank crate (rope straps distinguish it from the iron-bracketed storage chest). All three resources.json furniture items point at it; the three old item GLBs deleted (orphaned .import files left for Godot to clean on rescan — never hand-touched). The ore §5.7 one-shape rule, applied to the furniture family: the box says "packed furniture", the ghost says which piece it becomes. Doc 61 §5.4 updated. | Implemented — verify by eye: spawn furniture items → three identical rope-lashed boxes; fetch/install/uninstall unchanged. |
| 2026-07-11 | **Phase 3 (fetch-and-build + 📤 uninstall).** `Task.Type` gains first-class FETCH_BUILD (45 — SH placement-band-tops-restock) + UNINSTALL (40); `TaskManager.allocate_source_id()` (monotonic from 10M — the doc 18 debt paid); `task_config.json` gains `furniture` (build/uninstall_time_s 2.0). **Ghost = fifth work-source family:** ONE type-matched FETCH_BUILD lease posted only while a matching item is AVAILABLE (loose unreserved or in storage aggregates); wake sources drop_spawned + stockpile_changed, throttled 0.25 s in the controller (StockpileManager pattern). Fetch pull: loose-first (`nearest_loose_of_key`), else **storage withdraw** — `StockpileManager.withdraw_item` → `zone.withdraw_nearest` → `ItemDropManager.stored_node_at`/`withdraw_stored` (stored node re-enters the loose index PRE-RESERVED by the fetcher — no race window). Dwarf executor: reserve → walk → pick up (carry visual, heavy ×0.7 applied AT pickup) → walk to ghost → build swing → `complete_build` → the controller's shared `_install` (same path as DEV Instant Build); the carried item node is consumed. **📤 = InstalledFurnitureComponent** (sixth family): SH-parity toggle; flag posts ONE UNINSTALL lease (cancel-toggle cancels it; released leases stay counted; cancelled/failed leases re-post while flagged); dwarf walks to a walkable footprint-neighbour stand cell, teardown swing, `complete_uninstall` → shared teardown (occupancy freed, packed item drop spawns → ordinary hauling restocks). Windows: ghost shows waiting/needs state; installed window primary button is the 📤 toggle (DEV: Remove kept). Rule 12 wired into abort/sleep/DEV-interrupt for both arms (fetch drops the carried item; uninstall leaves the piece installed + flagged). Overlay: `uninstalling` count. | **VERIFIED in-engine by Alen, 2026-07-11** — after a false alarm: the first run showed dwarves ignoring ALL new tasks (no hauling, no uninstall response) with leases pending. Root cause: **stale Godot global class cache** — Phase 3 added a new `class_name` script (InstalledFurnitureComponent) and rewrote another outside the editor; the doc 16 reload lesson applies to ANY new class_name, not just `[autoload]` edits. **Project → Reload Current Project fixed everything**: fetch-and-build, 📤 uninstall, and zone hauling all confirmed working together. LESSON (session protocol): after a work session that adds new `class_name` scripts, reload the project before playtesting. Remaining micro-checks (zone withdraw, mid-carry interrupt, 📤 double-toggle) ride along in Phase 4/5 sessions. |
| 2026-07-11 | **Phase 2 (ghost placement tool).** New `FurniturePlacementController` (scene node; sole reader of `data/furniture/*.json` — defs need `placement` + `item_key`, so trade_counter correctly skips) + `FurnitureGhostComponent` (Phase 3 grows it into the FETCH_BUILD work source). Tool: Build panel 📥 entries (label→key map in DockUI; announce `tool_requested("furniture")` then `activate_for(key)`), translucent placed-form cursor ghost (SH parity: real model, alpha 0.30, validity tint cyan/red), **R** rotates 90° (footprint W/D swap for future non-square pieces), height-field-march hover, per-cell validity (bounds, bedrock, water, NavGrid walkable, no zone/ghost/installed overlap — zone tool mirrors via `blocks_zone_cell` / `is_zone_cell`), `floor_wall` probes solid blocks behind the yaw-rotated back row. Confirmed ghosts persist non-solid + slice-culled. Windows: ghost (Cancel 📥 + **DEV: Instant Build** — shares `_install()` with the future fetch executor; occupancy boxes from `collision_regions`, yaw-swapped extents) and installed (**DEV: Remove** → drops the packed item). Click-select works with the tool off (A3 lesson, day one). Overlay `furniture:` row (ghosts/installed). Scene: controller node added to `debug_world.tscn`. Gotcha logged: GDScript `\U` escapes take SIX hex digits (not Python's eight) — 📥 embedded as literal chars instead. | **VERIFIED in-engine by Alen, 2026-07-11 ("phase 2 pass")** — with two same-day playtest revisions along the way: the why-invalid hint (note 2) and the ground-shelf decision (note 3). Phase 2 BANKED. |
| 2026-07-11 | **Phases 0 + 1 (assets, data, DEV source).** `tools/generate_furniture_glbs.py` (items class, deterministic): placed forms `barrel` / `storage_crate` / `storage_shelf` — all wood + iron per the same-day material rule — and item forms (mini barrel, mini crate, "shelf kit" bundle); review sheet `tmp/furniture_review/furniture_sheet.png`. Data: `data/furniture/{barrel,storage_chest,storage_shelf}.json` (trade_counter schema + doc 19 fields `item_key`/`placement`/`yaw_steps`/`storage`; shelf carries 8 anchors + `anchor_scale` 0.5); `resources.json` gains the three packed-furniture items + `stockpile_furniture` tag; zone `DEFAULT_FILTER_TAGS` accepts it. DEV: "Spawn Furniture" button on the Storage Zone panel (`dev_spawn_furniture`, shared `_dev_spawn_mix`). Doc 61 §5.4 gains the shelf spec + chest container note. Overlay `furniture:` row deferred to Phase 2 (no controller to count yet — the row lands with the ghost tool). | **VERIFIED in-engine by Alen, 2026-07-11 ("works")** — packed items spawn, read at scale, and haul into zones like ordinary drops. Phases 0+1 BANKED. |

---

*Prev: [18_stockpiles_hauling.md](./18_stockpiles_hauling.md)*
