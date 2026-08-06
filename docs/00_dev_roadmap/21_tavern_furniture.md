# 21 — Tavern Furniture (Bar, Bench, Hearth)

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = decided / ready to build</span> |
> <span style="color:#d29922;">Yellow = decision needed or tune-in-engine</span> |
> <span style="color:#f85149;">Red = explicitly out of scope for this milestone</span>

Status: **SHIPPED (data + assets + placement) — 2026-08-03.** Art specs, GLB models, JSON
defs, and Build-panel/DEV-spawner wiring are complete and ride the existing doc 19
furniture pipeline unmodified. **Not verified in-engine yet** — this needs an editor
Reload + playtest pass before being marked BANKED (see *Verification* below). Tavern room
detection, the heat/temperature system, and traveler AI are explicitly out of scope — see
*Deferred*.

**Why this milestone:** doc 62 (furniture catalogue vs. Stonehearth) flagged tavern
furniture — bar, bench, hearth — as "the first post-19 asset batch with real system pull,"
since it is the one asset batch that touches three separate future systems at once: doc 34
(heat sources), doc 41 (dwarf thoughts/mood), and doc 51 (traveler income). Building the
furniture now means those systems need zero furniture-side work when they land.

**Scope correction found during planning (2026-08-03):** doc 51 describes Trade Counter's
room-anchor mechanism (`room_anchor`, `room_type`, `room_compatible_categories`) as though
it drives working Shop-room detection. It doesn't — grep across `scripts/` turns up zero
references to `room_type`, `RoomData`, or `shop_room` anywhere in the codebase. Those
fields exist only as **data** on `trade_counter.json`, read by nothing. Worse:
`trade_counter.json` has no `item_key`/`placement` fields, so `FurniturePlacementController`
skips it entirely — the Trade Counter is not placeable in-game today. This milestone does
not fix that (out of scope), but it means "room-anchor bar" and "plain placeable prop" are
currently the *same* runtime behaviour — the only difference is whether the JSON is ready
for a future room-detection system. `tavern_bar.json` carries both the doc 19 placement
fields (so it actually IS placeable, unlike Trade Counter) and the inert room-anchor fields.

---

## 1. Deliverable

The player 📥-places a Tavern Bar, Bench, or Hearth as a ghost from the Build panel; a
dwarf fetches the packed item and installs it, exactly like the doc 19 storage set. No new
GDScript was needed — `FurniturePlacementController` auto-discovers any `data/furniture/*.json`
that carries `placement` + `item_key`, so this milestone is almost entirely **data +
assets**, with three small, mechanical registration edits.

## 2. What was built

### Art specs (doc 61 §5.4)

| Piece | Footprint | Collision | Material | Notes |
|---|---|---|---|---|
| Tavern Bar | 2×1 | `[{min:[0,0,0], max:[2,2,1]}]` | **Wood** (oak body, iron rail + tap fittings) | Deliberately not stone — distinct from the (currently unplaceable) Trade Counter |
| Bench | 2×1 | `[{min:[0,0,0], max:[2,1,1]}]` | Wood | 1 block tall — no backrest, unlike `wooden_chair` |
| Hearth | 1×1 | `[{min:[0,0,0], max:[1,1,1]}]` | **Stone** (material-rule exception — industrial/utility anchor, same bucket as Trade Counter and workshop bodies) | Ring + iron grate + embers; mesh only, no light node (wall-torch convention) |

### GLB generation

`tools/generate_furniture_glbs.py` gained `build_tavern_bar()`, `build_bench()`, and
`build_hearth()`, plus `STONE_HI` / `STONE_MID` / `STONE_DARK` / `EMBER_GLOW` / `FLAME_CORE`
palette constants (doc 61 hex values). All three ride the existing `Voxels` /
`mesh_from_voxels` / `write_glb` pipeline from `generate_dwarf_glb.py` — deterministic,
fixed seed, byte-identical on rerun. Item forms reuse the existing one-box rule: all three
point at the same `assets/models/items/furniture/packed_furniture.glb`, no new item GLB.

Generated and reviewed (`tmp/furniture_review/furniture_sheet.png`):

```
furniture/tavern_bar.glb   1898 voxels  195392 B
furniture/bench.glb         336 voxels   95276 B
furniture/hearth.glb         81 voxels   32708 B
```

### Data

- `data/furniture/tavern_bar.json` — `room_anchor: true`, `room_type: "tavern"`,
  `max_per_room: 1` (data only, see scope correction above).
- `data/furniture/bench.json` — plain placeable, no room/storage fields.
- `data/furniture/hearth.json` — `heat_source.heat_units: 400` (data only until doc 34
  exists to read it; sits between Torch's 200 and the future Brazier's 600).
- `data/entities/items/resources.json` — three new packed-item entries
  (`base:resources:furniture:{tavern_bar,bench,hearth}`), `stockpile_furniture` tagged,
  same as the doc 19 set.

### Registration (the only GDScript touched)

- `scripts/ui/DockUI.gd` — `FURNITURE_PANEL_ITEMS` gained three 📥 entries.
- `scripts/systems/StockpileDesignationController.gd` — `DEV_FURNITURE_MIX` gained three
  entries so **DEV: Spawn Furniture** drops one of each for testing.

No autoload changes, no new `class_name` scripts — per `AGENT.md`'s playtest handoff note,
**no editor reload is required** for this milestone.

## 3. Deferred (explicitly out of scope)

<span style="color:#f85149;">Tavern room detection</span> — no sealed-room flood-fill,
`RoomData`, or `room_type` consumer exists anywhere. This is a new system, not a furniture
follow-on; doc 34 (temperature) needs the same flood-fill and is the natural place to build
it once.

<span style="color:#f85149;">Heat / temperature</span> — `heat_source.heat_units` is
inert data. Doc 34 itself has no implementation status marker as of this doc.

<span style="color:#f85149;">Traveler AI / ale consumption / lodging</span> — doc 51's
`APPROACHING → DRINKING → LODGING` state machine is unbuilt. Placing a Tavern Bar changes
no traveler behaviour today.

<span style="color:#f85149;">Dwarf sit-down / seating behaviour on the Bench</span> —
depends on doc 41's needs/mood system, which is not yet implemented.

## 4. Verification (not yet done)

Per `AGENT.md`'s Scene Editing Protocol and the doc 19 precedent, this needs an in-engine
pass before being marked BANKED:

- [ ] Godot import: confirm all three GLBs import cleanly at `Root Scale = 1.0`.
- [ ] Build panel: `📥 Tavern Bar`, `📥 Bench`, `📥 Hearth` appear and activate the
      placement ghost tool.
- [ ] Ghost ↔ ground: bar and bench (2×1) rotate correctly with R; hearth (1×1) places
      cleanly.
- [ ] `DEV: Spawn Furniture` drops one packed item of each new kind.
- [ ] Fetch-and-build: a dwarf fetches and installs each piece (doc 19 Phase 3 pipeline).
- [ ] Uninstall: 📤 breaks each piece back down to its packed item.
- [ ] Visual check against `tmp/furniture_review/furniture_sheet.png` at RTS zoom —
      confirm the hearth's ember ring reads clearly from top-down.

---

*Prev: [20_save_load.md](./20_save_load.md) | Next: [22_doors_temperature.md](./22_doors_temperature.md)*
