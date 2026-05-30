# 23 — User Interface

## Overview

All UI is implemented as Godot `Control` nodes on a `CanvasLayer`. No 3D world-space UI elements. The interface is divided into four zones: **Status Bar** (top), **Side Panel** (right), **Build Menu** (bottom), and **Notification Layer** (overlay).

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

## Build / Designation Menus

The bottom build bar contains tabbed categories:

| Tab | Contents |
|---|---|
| Mine | Designate mining zones, clear rubble, channel floors |
| Build | Place workshops, doors, furniture, stockpile zones |
| Farm | Designate soil plots, assign crops |
| Military | Set patrol routes, guard posts (future) |

### Menu Item Entry Format

Each buildable entry is a `BuildEntry` resource:

```gdscript
class_name BuildEntry extends Resource
@export var display_name: String
@export var icon: Texture2D
@export var cost: Dictionary          # { "base:resources:stone:granite": 4 }
@export var action_type: StringName   # &"mine", &"place_block", &"designate_farm"
@export var requires_floor: bool      # must have solid floor below
```

## Stockpile Zone System

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
var capacity:     int                  # max total items across all cells (tile_count × 8)
```

### Filter Tag Categories

These are the top-level tag groups shown in the filter panel UI:

| UI Label | Filter Tag | Covers |
|---|---|---|
| Stone | `stockpile_stone` | Granite, basalt, limestone, marble |
| Ore | `stockpile_ore` | Copper, iron, coal, gold, gold nuggets |
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
