# 23 — User Interface

## Overview

All UI is implemented as Godot `Control` nodes on a `CanvasLayer`. No 3D world-space UI elements. The interface is divided into four zones: **Status Bar** (top), **Side Panel** (right), **Dock** (bottom — a floating command bar), and **Notification Layer** (overlay).

## Stockpile Display Readouts

The top status bar shows live colony resource counters.

### Layout

```
[ 🪨 Stone: 1,204 ]  [ 🍺 Ale: 47 ]  [ 🌾 Food: 312 ]  [ ⛏ Ore: 88 ]  [ 💰 Trade Goods: 5 ]
```

### Item Counter Rules

- Counters update via signal (`StockpileManager.stockpile_changed`) — **never poll per frame**.
- Numbers above 9,999 are displayed as `9.9k`, `10k`, `100k` etc.
- A counter flashes **red** for 2 seconds if the quantity drops to zero.
- A counter flashes **green** for 1 second when a batch of goods is received (trade delivery).

## Floating Dock (Bottom Command Bar)

The bottom zone is a **floating dock** — a centered, rounded, semi-transparent bar
(macOS-dark-mode style) that sits above the 3D viewport on the `CanvasLayer`. It is the
single bottom UI surface and **replaces** the older tabbed build bar. Icons are **emoji
glyphs** rather than an authored texture atlas.

### Data-Driven Layout

Dock order, icons, and action bindings live in `data/ui/dock.json` and are loaded by the
`UIRegistry` autoload (Registry Pattern — no other script reads the file directly). The
data file's scope is **layout only**: order, emoji, label, tooltip, and an action *id*.
The action *logic* lives in GDScript — the dock node maps each `action` string to a handler
via a dispatch table — per the JSON-vs-GDScript rule (*JSON = what things are, GDScript =
what things do*). Buildable-entry catalogs (costs, `action_type`, `requires_floor`) are a
separate concern and are **not** part of `dock.json`. When those catalogs are specced they
will be JSON loaded by their owning registry, never `.tres` Resources (see AGENT.md).

```json
{
  "items": [
    { "id": "mine",  "emoji": "⛏️", "label": "Mine",  "action": "open_panel",    "target": "mine" },
    { "type": "separator" },
    { "id": "labor", "emoji": "👷", "label": "Labor", "action": "toggle_window", "target": "labor" }
  ]
}
```

`UIRegistry.get_dock_items()` returns the ordered, validated list. Separator entries are
`{ "type": "separator" }`; button entries carry `id`, `emoji`, `label`, `tooltip`,
`action`, and `target`. Malformed entries are skipped with a warning at load.

### Action Types

| `action` | Effect |
|---|---|
| `open_panel` | Opens a build/designation panel above the dock. Panels are **mutually exclusive** — opening one closes any other. `target` names the panel. |
| `toggle_window` | Toggles a movable floating window (labor, stockpiles, trade). `target` names the window. |

### Save / Load Menu

The far-right utility button uses **💾 Save / Load** and opens the standard mutually
exclusive action panel above the dock. Its actions are **💾 Save Game**,
**📂 Load Game**, and **🕒 Load Autosave**. `DockUI` owns only the presentation and emits
`save_game_requested`, `load_game_requested`, or `load_autosave_requested`; `SaveManager`
owns the timer, file I/O, and state serialization.

The manual quick save lives at `user://saves/quicksave.json`; a separate automatic save is
written every five minutes of ready, non-generating world time to
`user://saves/autosave.json`. Both use schema version 1, validate a temporary snapshot
before replacement, and retain one matching backup. If a selected primary is corrupt,
Load recovers that slot's backup and repairs its primary automatically. Autosaving shows a
brief **Autosaved.** toast and never replaces the player's manual save.
The save records the deterministic world seed plus authoritative deltas/state: mined
blocks and designations, the settlement flag and dwarf roster, stockpile zones and
contents, furniture ghosts/installed pieces and container inventories, loose items,
calendar/weather, camera, and slice state. Load regenerates the seed-identical base
world and reapplies those sections in dependency order. Tasks, leases, reservations,
navigation/render caches, and interior-region tables are transient or derived and are
rebuilt. Snapshot creation is observational: it never releases a worker, changes an
assignment, or clears a reservation. Items currently in transit are recorded with their
carrier and materialize loose at that dwarf's saved position on load, where rebuilt work
sources can reclaim them. The dock shows a short success/error toast, including the
no-save-yet and world-still-generating cases.

The complete schema, ownership contract, restore lifecycle, and verification record live
in `00_dev_roadmap/20_save_load.md`.

Some `toggle_window` targets are intercepted in `DockUI._toggle_window` and routed to a real
system instead of a generic window: `world_info` / `block_inspector` toggle their overlay
CanvasLayers, `clock` opens the live Clock window, and `slice` toggles the **Slice tool**
(see below). `xray` remains a stub until the X-Ray tool exists (`11_slice_xray_plan.md` §4).

### The Slice Tool (shipped 2026-06-05 — doc 11 Phase 2)

The dock's `slice` entry toggles the slice view rather than opening a window. The tool is
owned by `SliceController` (scene node; DockUI only routes the toggle and mirrors active
state on the button). While active, a small palette window shows: **▲▲ Cell up**,
**▲ Block up**, a live `Y = N` readout (`Off` at Y127), **▼ Block down**, **▼▼ Cell down**.

| Input | Effect |
|---|---|
| `\` | Toggle the slice view |
| `]` / `[` | Step the plane one 4-block cell up / down (snaps to cell tops) |
| `Ctrl+]` / `Ctrl+[` | Step one block up / down |

Clamps: Y4 floor (Bedrock Protocol — one mineable layer always visible) to Y127 = off.
First activation seeds the plane from the camera's surface column; afterwards the height is
fully manual and remembered across toggles. Its active state, current height, seeded flag,
and last manual height persist in the version-1 quick save.
Activating Slice will force the future X-Ray tool off, and vice versa — mutual exclusion
lives in the tool layer, never the renderer.

### Default Items

| Order | Emoji         | Label      | Action          | Target       |
| ----- | ------------- | ---------- | --------------- | ------------ |
| 1     | ⛏️            | Mine       | `open_panel`    | `mine`       |
| 2     | 🪓            | Chop       | `open_panel`    | `chop`       |
| 3     | 🧺            | Gather     | `open_panel`    | `gather`     |
| 4     | 🔨            | Build      | `open_panel`    | `build`      |
| —     | *(separator)* |            |                 |              |
| 5     | 📦            | Storage Zone | `open_panel`  | `storage_zone` |
| 6     | 🌾            | Farm       | `open_panel`    | `farm`       |
| —     | *(separator)* |            |                 |              |
| 7     | ⚔️            | Military   | `open_panel`    | `military`   |
| —     | *(separator)* |            |                 |              |
| 8     | 👷            | Labor      | `toggle_window` | `labor`      |
| 9     | 📦            | Stockpiles | `toggle_window` | `stockpiles` |
| 10    | 💰            | Trade      | `toggle_window` | `trade`      |
| —     | *(separator)* |            |                 |              |
| 11    | 🕒            | Clock      | `toggle_window` | `clock`      |
| 12    | 📅            | Calendar   | `toggle_window` | `calendar`   |
| —     | *(separator)* |            |                 |              |
| 13    | 👀            | Slice      | `toggle_window` | `slice`      |
| 14    | 🩻            | X-Ray      | `toggle_window` | `xray`       |
| —     | *(separator)* |            |                 |              |
| 15    | 🚩            | Settle     | `toggle_window` | `flag`       |
| 16    | 🧔            | Dwarves    | `toggle_window` | `dwarves`    |
| 17    | 📊            | World      | `toggle_window` | `world_info` |
| 18    | 🔍            | Inspect    | `toggle_window` | `block_inspector` |
| —     | *(separator)* |            |                 |              |
| 19    | 💾            | Save / Load | `open_panel`   | `save_load`  |

### Panels (opened by `open_panel`)

| Panel | Contents |
|---|---|
| Mine | Designate mining zones, clear rubble, channel floors |
| Build | Place workshops, doors, furniture, stockpile zones — **LIVE for storage furniture (doc 19, 2026-07-11):** 📥 entries (Barrel / Storage Chest / Storage Shelf) activate the furniture ghost tool; a dwarf fetches the packed item and installs it. Installed pieces' windows carry the **📤 Uninstall** toggle (SH parity). Workshops/doors join as their systems land. |
| Farm | Designate soil plots, assign crops |
| Military | Set patrol routes, guard posts (future) |

### Emoji Rendering Requirement

Emoji icons require an **emoji-capable fallback font** in the project theme (e.g. Noto
Color Emoji). Godot's default theme font does not render emoji. Godot 4 supports
color-glyph fonts (COLR/CPAL, CBDT/CBLC, sbix) once one is loaded. Verify with a small
smoke test (a `Label` reading `⛏️🌾⚔️` on a `CanvasLayer`) before building the full dock.

## Stockpile Zone System

> **IMPLEMENTED (doc 18 — Stockpiles & Hauling, banked 2026-07-11).** Ground zones shipped:
> `StockpileZoneComponent` (work source posting HAUL leases), `StockpileDesignationController`
> (marquee tool, per-zone overlay, zone window with Remove — zones stay click-selectable with
> the tool off, mining parity), `StockpileManager` autoload (zone registry + aggregates), and
> the loose-item index on `ItemDropManager`. v1 zones accept everything; the filter panel below
> remains the design for the UI pass. Item defs are queried through `ItemDropManager`
> (registry pattern) — there is no separate ItemRegistry autoload.
>
> **Capacity rule SUPERSEDED (Alen, 2026-07-06 — Stonehearth parity):** ground zones store
> **one item per tile, no stacking** — quantity is WYSIWYG and capacity = empty cells. The
> `tile_count × 8` rule and `stack_max` below are retired from ground zones and reserved for
> the storage-container path (barrel/chest/shelf — doc 18 §2.5 follow-on).

A **stockpile zone** is a player-designated rectangular region of floor tiles that dwarves haul items into and workshops draw inputs from. Zones are defined by their **filter** — a set of accepted `material_tags` that controls which item categories are accepted.

### Zone Designation Flow

1. Player selects **Build → Stockpile Zone** from the build menu and drag-paints floor tiles.
2. A `StockpileZone` node is created covering those tiles. Its default filter accepts `["stockpile_stone", "stockpile_ore", "stockpile_gem", "stockpile_soil", "stockpile_wood", "stockpile_food", "stockpile_drink", "stockpile_seed", "stockpile_misc"]` — i.e., everything.
3. The player can open the zone's filter panel (click the zone) to toggle individual tag categories on or off.

### StockpileZone Data Model

```gdscript
class_name StockpileZone extends Node3D

var zone_id:      int                  # unique ID, used by HaulTask payload
var tile_cells:   Array[Vector3i]      # all floor cells belonging to this zone
var filter_tags:  Array[String]        # accepted material_tags; empty = accept nothing
var inventory:    Dictionary           # { item_uri: int } — current counts per item type
# capacity is IMPLICIT (superseded rule, see note above): one item per tile —
# a zone is full when no empty unreserved cell remains
```

### Filter Tag Categories

These are the top-level tag groups shown in the filter panel UI:

| UI Label | Filter Tag | Covers |
|---|---|---|
| Stone | `stockpile_stone` | Mined rock and construction stone |
| Ore | `stockpile_ore` | Copper, tin, iron, silver, coal, gold |
| Gems | `stockpile_gem` | Raw ruby, raw sapphire |
| Soil | `stockpile_soil` | Cave soil, light soil, dark soil |
| Wood | `stockpile_wood` | Juniper logs (and future timber) |
| Food | `stockpile_food` | Mushrooms, grains, berries, seeds |
| Drink | `stockpile_drink` | Ale, mead (finished brews) |
| Seeds | `stockpile_seed` | Planting seeds of all species |
| Misc | `stockpile_misc` | Cloth, water buckets, fossil fragments |

### Acceptance Check

When a dwarf carrying an item looks for a valid stockpile destination, the check is:

```gdscript
func accepts_item(zone: StockpileZone, item_uri: String) -> bool:
    var item_def := ItemRegistry.get(item_uri)   # loaded from resources.json
    var overlap  := item_def.material_tags.filter(func(t): return t in zone.filter_tags)
    return overlap.size() > 0 and zone.inventory.values().reduce(func(a,b): return a+b, 0) < zone.capacity
```

An item is accepted if **at least one** of its `material_tags` matches a tag in the zone's `filter_tags` and the zone is not at capacity.

### Workshop Input Lookup

Workshops do not maintain their own input buffer. When a BREW/BUILD task begins, the worker polls `StockpileManager` for the nearest zone that:
1. Accepts the required input item (via the acceptance check above).
2. Has `inventory[item_uri] >= required_count`.
3. Is reachable via the navigation graph.

`StockpileManager` (Autoload) owns all zones and exposes:

```gdscript
func find_nearest_zone_with(item_uri: String, count: int, from: Vector3i) -> StockpileZone
func register_zone(zone: StockpileZone) -> void
func deregister_zone(zone: StockpileZone) -> void
signal stockpile_changed(zone: StockpileZone, item_uri: String, delta: int)
```

> **Agent note:** Item counts in `StockpileZone.inventory` are the authoritative source. The top status bar counters (Stone, Ale, Food, etc.) are aggregated from all zones by `StockpileManager` on every `stockpile_changed` signal — not tracked separately.

## Warning Toast Notifications

Short-lived overlay messages alerting the player to critical colony events.

### Toast Parameters

| Parameter | Value |
|---|---|
| Display duration | 4 seconds |
| Fade out | 0.5 s ease-out |
| Max simultaneous | 5 (oldest dismissed first if exceeded) |
| Position | Top-right, stacked vertically with 8 px gap |

### Severity Levels

| Level | Colour | Example trigger |
|---|---|---|
| `INFO` | White | "New migrants have arrived" |
| `WARN` | Amber | "Ale stockpile is low" |
| `ALERT` | Red | "A dwarf has died" |
| `CRITICAL` | Flashing red | "Flood detected on level 12" |

```gdscript
# Usage
ToastManager.push("Ale stockpile is low", ToastManager.WARN)
```

## Labor Assignment Window

Opened via the right-side panel. Shows all dwarves and their current job assignments.

### Columns

| Column | Description |
|---|---|
| Name | Dwarf name + health dot (green / amber / red) |
| Job | Current active task label |
| Priority | Drag-sortable priority score (1–10) |
| Skills | Icon row: mining, hauling, farming, brewing |
| Idle | Checkbox — manually force dwarf to idle |

### Rules

- Assignments are suggestions; the **Task System** (see `31_task_system.md`) retains final allocation authority.
- Forcing a dwarf idle via the checkbox inserts a high-priority `TaskIdle` token that blocks other task allocation for that dwarf.

## Active Task Tracking Log

A scrollable log in the right panel below the labor window. Shows the last 50 completed and in-progress tasks with timestamps.

```
[12:04]  ⛏  Urist mines Granite (Level 7)       ✓ done
[12:05]  📦  Bomrek hauls Stone × 8 to Stockpile  ⟳ in progress
[12:05]  🍺  Dastot brews Longbeard Ale            ⟳ in progress
```

---

*Prev: [22_mouse_input.md](./22_mouse_input.md) | Next: [31_task_system.md](../30_simulation_systems/31_task_system.md)*
