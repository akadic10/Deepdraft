# 19 - Storage Containers & Furniture Placement (Third Colony Milestone)

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = decided / ready to build</span> |
> <span style="color:#d29922;">Yellow = decision needed or tune-in-engine</span> |
> <span style="color:#f85149;">Red = explicitly out of scope for this milestone</span>

Status: plan, drafted 2026-07-11. Nothing implemented.

**Why this milestone:** doc 18 shipped ground stockpiles with a deliberate density ceiling —
one item per tile, WYSIWYG (Alen, 2026-07-06). Density was explicitly deferred to
**containers**, the Stonehearth-verified upgrade path (small crate 8 → large crate 32 →
vault 256; doc 18 §2.5). Containers need a **furniture placement tool**, which does not
exist — and that tool is itself the gateway for every future placeable: workshop props
(doc 44), tavern furniture (doc 51), the Armory's stands and displays (doc 52), beds,
torches. This milestone builds the general placement pipeline and proves it on the three
storage pieces, extracting the storage contract doc 18 deliberately kept clean for exactly
this moment (doc 18 §6 decision 5). The doc 16 architectural bet gets its third test:
containers are work sources posting HAUL leases, same as mining zones and ground stockpiles.

Deliverable: **the player places a barrel, chest, or storage shelf from the Build panel;
dwarves haul loose drops into them through the existing lease pipeline; shelf contents are
visible on the shelf; removing a container returns its contents to the world as loose
drops — with hauling interruptible at any point under the release protocol.**

---

## 1. Where Deepdraft stands today (gap analysis)

| Piece | State today | Gap |
|---|---|---|
| Furniture data schema | `data/furniture/trade_counter.json` — rich canonical schema (footprint, collision_regions, room_anchor…) but nothing loads it | No loader, no other furniture defs |
| Furniture assets | **None.** `assets/models/` has flora + items only; doc 61 §5.4 has authored SPECS for barrel + storage crate | Generate GLBs (barrel, chest, shelf); shelf needs a doc 61 spec |
| Placement tool | `FlagPlacementController` — single-entity ghost + validity tint + `PlacedEntityRegistry.register_box` (256 lines, one-shot) | No data-driven multi-item tool, no rotation, no removal |
| Entity occupancy | `PlacedEntityRegistry` + `occupancy_changed` → NavGrid invalidation, proven by flag + trees | Nothing — reused as-is |
| Storage logic | `StockpileZoneComponent` — accept/reserve/deposit surface + the full pouch haul loop, designed as the future shared contract (doc 18 §2.5) | Extract the contract; zone keeps behaviour, container implements it with slots instead of cells |
| Haul pipeline | Leases, pouch bundles, release protocol, owner-guarded reservations — shipped + verified 2026-07-11 | Container as a third work-source family |
| Source ids | Mining zones raw ids; stockpile zones at `1_000_000 + zone_id`; **doc 18 recorded tech debt: TaskManager-owned allocator "when a third source system appears"** | The third system is here — the debt is due |
| UI | Dock `build` panel entry exists (`open_panel` / `build`), panel is a stub | Build panel gets the three storage pieces |

---

## 2. ARCHITECTURE

### <span style="color:#3fb950;">2.0 Direction</span>

1. **One storage contract, many faces (the SH model, doc 18 §2.5).** A shared
   `StorageComponent` base class owns the generic haul-loop machinery (lease posting, pouch
   `reserve_haul` / `cancel_haul` / `take_item` / `skip_item` / `commit_haul`, owner-guarded
   reservations). Subclasses answer only: *where does a deposit go, and how much room is
   left?* Ground zone = per-item floor cells; container = capacity slots behind one stand
   cell. The doc 18 haul executor on `DwarfAgent` does not change at all.
2. **The WYSIWYG split is a principle, not an accident (Alen, 2026-07-06 + SH parity):**
   fully-visible storage (ground zones, the shelf) shows exactly what it holds; opaque
   density containers (barrel, chest) trade visibility for capacity and show counts in
   their window. The shelf's capacity IS its anchor count — never render fewer items than
   it holds.
3. **Placement is general, storage is the first client.** The placement tool reads
   `data/furniture/*.json` and knows nothing about storage; it places, registers occupancy,
   and emits. A furniture def with a `storage` block additionally gets a storage component
   registered with `StockpileManager`. Workshop props and Armory furniture later reuse the
   tool untouched.
4. **Release stays cheap and legal (Hard Rule 12):** nothing in this milestone touches the
   interrupt path — a hauler interrupted mid-trip to a barrel drops the pouch at its feet
   exactly as today.

### 2.1 Furniture data + the loader

Three new defs following the `trade_counter.json` schema, `furniture_category: "storage"`:

| Def | Footprint | Collision | Storage block |
|---|---|---|---|
| `base:furniture:barrel` | 1×1 | 1 block tall (doc 61 §5.4) | `{ "capacity": 8, "render_contents": false }` |
| `base:furniture:storage_chest` | 1×1 | 1 block tall (doc 61 §5.4 crate) | `{ "capacity": 24, "render_contents": false }` |
| `base:furniture:storage_shelf` | 1×1, **wall-adjacent** | 2 blocks tall | `{ "capacity": 8, "render_contents": true, "anchors": [[…], ×8] }` |

New shared fields: `placement` (`"floor"` \| `"floor_wall"` — shelf requires a solid block
face behind its back side), `yaw_steps: 4` (placement rotation). `storage.anchors` are local
float offsets (in blocks) where stored item GLBs render on the shelf.

**Loader:** `FurniturePlacementController` owns `data/furniture/*.json` (the system-owns-its-
data pattern, doc 13 — same as VisitorManager owning merchant_catalog). It hands the parsed
def to whatever the placed piece needs (storage component, future workshop component). No
separate registry autoload until a second consumer needs the file.

### 2.2 Furniture placement tool (`FurniturePlacementController`, scene node)

The flag tool generalised, data-driven:

- Build panel button per placeable → `tool_requested("furniture")` + def key. The tool joins
  the click-tool exclusion contract (all tools deactivate on any other tool's id — the
  2026-07-06 fix).
- **Ghost preview** at the hovered cell: the def's GLB, validity-tinted (flag-tool language),
  yaw-rotated in 90° steps on <span style="color:#d29922;">**R** (lean — the wheel belongs to
  camera zoom / the mining brush, doc 21 tool contract)</span>.
- **Validity:** every footprint cell NavGrid-walkable at one shared floor Y, unoccupied
  (`PlacedEntityRegistry`), not on a stockpile-zone cell (a blocked deposit cell starves the
  zone), not water/bedrock-adjacent (the doc 18 zone rules); `floor_wall` additionally probes
  the block behind the ghost's back face for solidity.
- **On confirm:** instance the visual (project vertex-colour material), register the
  collision_regions box(es) with `PlacedEntityRegistry` (NavGrid invalidates via
  `occupancy_changed` — the flag precedent), create the storage component if the def carries
  a `storage` block, emit `furniture_placed`. Tool stays active for repeat placement (mining
  precedent); ESC-only cancel.
- **Click-select with the tool off** (the doc 18 A3 lesson, learned 2026-07-11 — built in
  from day one this time): left-click on a placed piece's footprint opens its window:
  contents summary + **Remove**.
- **Remove:** cancel the component's leases, dump stored items as loose drops at the stand
  cell (`drop_loose` — jittered since 2026-07-11), unregister occupancy, free the nodes.

### 2.3 Storage contract extraction (`scripts/components/StorageComponent.gd`)

The doc 18 §6.5 lean, executed: hoist from `StockpileZoneComponent` everything that is not
cell-specific —

```gdscript
# StorageComponent (base, RefCounted) — the haul work-source machinery
#   update_leases / on_task_gone / reserve_haul / cancel_haul / take_item /
#   skip_item / commit_haul / nearest_stand_target        (doc 18 §2.2–2.3, unchanged)
# Subclass surface (abstract):
#   _reserve_deposit(item_key, near, dwarf_id) -> Variant  # zone: cell; container: slot token
#   _release_deposit(token) -> void
#   _commit_one(token, item_key) -> void                   # zone: cell_stacks; container: inventory
#   _has_any_room() -> bool
#   _deposit_walk_target() -> Vector3i                     # zone: first reserved cell; container: stand cell
#   _place_visual(node, token) -> void                     # zone: place_stored(cell); container: absorb or anchor
```

`StockpileZoneComponent extends StorageComponent` (behaviour identical — **the doc 18
verification checklist re-runs as the regression gate**). New
`ContainerStorageComponent extends StorageComponent`: flat `inventory: Dictionary`
(item_key → count), capacity check, one **stand cell** (the walkable cell the placement
tool validates in front of the piece), reservations as counted slots. `place_visual`:
`render_contents` false → the carried node is freed on deposit (the barrel absorbs it —
counts live in the window); true → the node snaps to the next free anchor at
<span style="color:#d29922;">~0.45 scale (tune by eye)</span>, slice-culled as usual.

`StockpileManager` registers containers exactly like zones (`register_container` /
`deregister_container`), aggregates include container inventories, `stockpile_changed`
fires on container deposits — the doc 23 counters stay one API.

### 2.4 Source-id allocator (the doc 18 tech debt, now due)

`TaskManager.allocate_source_id() -> int` — a monotonic counter starting above every
existing keyspace (10,000,000). Containers use it. <span style="color:#d29922;">Migrating
mining zones (raw ids) and stockpile zones (1M offset) onto the allocator is optional
cleanup — lean: allocate for NEW families only, migrate nothing this milestone.</span>

### <span style="color:#f85149;">2.5 Explicitly out of scope</span>

Input/output bins and restock priority bands (land with workshops, doc 44 — the SH
input_crate model is already recorded in doc 18 §2.5). Filter panel UI (containers accept
everything, like v1 zones). Furniture as craftable/haulable items — placement is **free**
this milestone; costs, BUILD tasks, and undeploy-to-item arrive with the crafting economy.
Trade counter placement (needs room detection, doc 51). Beds, tavern, Armory furniture
(their systems don't exist). Moving placed furniture (remove + re-place covers v1).
Save/load (whole-project gap, unchanged).

---

## 3. Milestone phases

### Phase 0 — Instrument first (doc 07 lesson, third time)

Overlay `storage:` row grows: `containers N` / container stored count folded into `stored`.
DEV drop spawner reused unchanged.

### Phase 1 — Assets + data

`tools/generate_furniture_glbs.py` (items class: 8 vox/block, 0.125 baked into vertices —
the ore-drop generator convention, doc 61 §5.7): `barrel.glb`, `storage_crate.glb`,
`storage_shelf.glb` per doc 61 §5.4 specs. The shelf spec is new — add to doc 61 when the
asset ships: 1×1×2, hewn stone uprights, two plank shelf levels, iron brackets
(doc 18 §2.5, Alen's ask); anchor points clear of the uprights. Three furniture JSONs
(§2.1). Review renders to `tmp/furniture_review/`.

Acceptance: GLBs load in-engine at correct scale beside a dwarf; silhouettes pass the
doc 61 §7 checklist (64×64 silhouette test, dwarven weight).

### Phase 2 — Placement tool

§2.2 complete: Build panel wiring (`dock.json` gets the three pieces under `build`;
DockUI routes), ghost + validity + R-rotation, occupancy registration, click-select window
with Remove (storage-less window first — Remove just deletes), tool exclusion verified
against mining/zone/flag tools.

Acceptance: place all three pieces on flats and terraces; shelf refuses to place without a
wall behind and rotates to face away from it; pieces block dwarf pathing immediately
(NavGrid); invalid cells tint red; ESC exits; placing then removing leaves the world clean;
zones cannot be painted under furniture and vice versa.

### Phase 3 — Storage contract + container hauling

§2.3 + §2.4: extract `StorageComponent`, re-base the zone on it, add
`ContainerStorageComponent` + StockpileManager registration + allocator. **Regression gate:
the full doc 18 verification checklist re-runs against the re-based zone (one-item-per-tile,
pouch interrupts, spam, tool-off select) before the container work continues.**

Acceptance: paint a zone AND place a barrel near a drop field → both fill via leases; the
barrel absorbs items (window count climbs) and stops at 8; interrupt a hauler mid-trip to
the barrel → pouch drops at feet, another dwarf finishes; remove a stocked barrel → 8 loose
drops at the stand cell; overlay counts reconcile (loose + stored + carried is conserved).

### Phase 4 — Shelf contents + polish

Anchor rendering (§2.3 `place_visual`), slice-culling of anchored items, container window
contents list (per-item counts), aggregates verified against the overlay, carry/deposit
visuals checked against the walk gait.

Acceptance: haul 8 mixed drops onto a shelf → all 8 visibly sit on the shelf levels; slice
hides shelf + contents together; removing the shelf drops all 8 loose; `get_total()` matches
the sum of zones + containers throughout.

---

## 4. Hard rules honoured (checklist for review)

1. **Rule 12 (release protocol)** — untouched; containers ride the existing executor.
2. **O(intents)** — one lease stream per container, capacity-capped; no per-item tasks.
3. **JSON vs GDScript** — capacities, anchors, footprints, yaw in `data/furniture/*.json`;
   behaviour in components. Tunables join `task_config.json` `hauling` only if shared.
4. **Namespaced IDs** — `base:furniture:*` keys; inventories store item keys, never ints.
5. **Registry pattern** — FurniturePlacementController is the sole reader of
   `data/furniture/*.json`; item defs still only via `ItemDropManager`.
6. **Entity decoupling (doc 12)** — the terrain grid never learns about furniture;
   occupancy via `PlacedEntityRegistry` boxes only.
7. **Scene decoupling** — controller is a scene node; components are RefCounted owned by
   their controller; cross-system flow via TaskManager/StockpileManager signals.
8. **Never touch `.tres` / `.import`** — GLBs land via the generator + editor import.

---

## 5. Build order & file touch list

| Step | Files | Depends on |
|---|---|---|
| 0. Overlay row | `DebugLoadingOverlay.gd` | — |
| 1. Assets + data | new `tools/generate_furniture_glbs.py`, `assets/models/furniture/*.glb`, new `data/furniture/{barrel,storage_chest,storage_shelf}.json`, doc 61 §5.4 shelf spec | — |
| 2. Placement tool | new `scripts/systems/FurniturePlacementController.gd`, `data/ui/dock.json`, `DockUI.gd`, `debug_world.tscn` | 1 |
| 3. Contract extraction | new `scripts/components/StorageComponent.gd`, `StockpileZoneComponent.gd` (re-base), **doc 18 checklist re-run** | — |
| 4. Container storage | new `scripts/components/ContainerStorageComponent.gd`, `StockpileManager.gd`, `TaskManager.gd` (allocator only) | 2, 3 |
| 5. Shelf rendering + window | `FurniturePlacementController.gd`, `ContainerStorageComponent.gd`, `ItemDropManager.gd` (anchor place/release helpers) | 4 |

Docs to update on completion: `23_user_interface.md` (Build panel state), doc 61 §5.4
(shelf spec + generator note), `13_architecture.md` (allocator note on TaskManager),
doc 18 §2.5 (container follow-on shipped), this doc's build log.

---

## 6. Open decisions (resolve before or during build)

1. <span style="color:#d29922;">**Chest capacity**</span> — 24 vs SH's 32. Lean 24: the
   ladder step from barrel 8 should feel meaningful but not obsolete ground zones at v1.
2. <span style="color:#d29922;">**Rotation input**</span> — R key (lean) vs wheel. Wheel is
   contractually camera/brush (doc 21); R is free and discoverable in the hint window.
3. <span style="color:#d29922;">**Allocator migration scope**</span> — new families only
   (lean) vs migrating mining/zone keyspaces now.
4. <span style="color:#d29922;">**Hauler target preference**</span> — v1 keeps nearest-item-
   first per source with no cross-source ranking; the SH restock-priority band arrives with
   input bins (doc 44). Watch whether barrels starve zones in play.
5. <span style="color:#d29922;">**Shelf anchor scale**</span> — ~0.45; tune by eye on the
   review renders, then in-engine.
6. <span style="color:#d29922;">**`stack_max` on containers**</span> — v1 capacity is a flat
   item count (SH parity). Whether stack_max later modulates per-type container density
   stays reserved (doc 18 §2.4 note) — do not wire it in v1.

---

## 7. Build log

| Date | Steps | State |
|---|---|---|
| — | — | — |

---

*Prev: [18_stockpiles_hauling.md](./18_stockpiles_hauling.md)*
