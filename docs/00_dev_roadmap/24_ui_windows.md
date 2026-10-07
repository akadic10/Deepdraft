# 24 — UI Window System v1 (Movable Windows)

**2026-10-05 update:** the approved Hearth & iron migration has delivered dwarf
inspection and the shared visual theme. All current UI uses `UITheme`; the manager,
position persistence and CanvasLayers remain. Mining Zone and Storage Zone have
also migrated to movable manager windows, including saved positions and context
selection cleanup. The remaining independent legacy panels share the style but
still await the manager migration.
See [51 — Dwarf inspection](51_hearth_iron_dwarf_inspector.md) and
[52 — Shared UI theme](52_hearth_iron_shared_theme.md). The original v1 design below
is retained as historical context; its old palette, font sizes and radii are superseded.

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = decided / ready to build</span> |
> <span style="color:#d29922;">Yellow = decision needed or tune-in-engine</span> |
> <span style="color:#f85149;">Red = explicitly out of scope for this milestone</span>

Status: **IN PROGRESS — drafted 2026-08-20 from the full-UI review; approved by Alen the
same day (look-and-feel mockup: `24_ui_windows_mockup.html`).** This is the design pass
for unifying every in-game window under one movable-window system — the macOS model: any
window can be dragged by its title bar, clicked to the front, and left open while the
player keeps working.

**Current presentation (2026-10-05):** [stage 2](52_hearth_iron_shared_theme.md)
shares Hearth & iron styling across the existing surfaces and migrates Mining Zone
and Storage Zone to movable manager windows. [Stage 3](53_hearth_iron_navigation.md)
replaces the icon row with five labeled navigation groups, adds live clock controls
and uses right-hand defaults for object inspectors. Saved window preferences still
take precedence. [Place](54_place_catalog.md), [Colony Inventory](56_colony_inventory.md)
and the [Colony roster](57_colony_dwarf_roster.md) now use manager windows too.
`dwarves` is the player roster; developer controls use `dwarves_dev` under Menu →
Development. Both remember position but start closed rather than restoring open
state. The inventory and findings below describe the original review.

> **Build log — checkpoint A (2026-08-20):** Phase U1 is built (`UITheme.gd`,
> `UIWindow.gd`, `UIWindowManager.gd`, scene node wired, `user://ui_layout.json`
> persistence), plus the first four U2 migrations (Clock, Labor/Stockpiles/Trade,
> Dwarves, Slice palette) and the U3 `dock.json` cleanup (Calendar/X-Ray/Gather hidden,
> Stockpiles emoji → 🗃️). NOT yet migrated: Storage Zone, Furniture, Rooms, Mining
> Zone, Block Inspector, World Build — their windows still use their old chrome until
> checkpoint B. **Awaiting Alen's playtest before continuing.** New class_names —
> run Project → Reload Current Project once after pulling.

**Why this milestone:** the dock itself is healthy (data-driven from `dock.json`, one
owner, one visual language), but the ten windows it opens were built by six different
scripts across six milestones, each hand-rolling its own panel, header, close button,
and stylebox. Only the two *debug* windows (Block Inspector, World Build) can be moved;
every gameplay window is bolted to a hard-coded left-edge position, and several of those
positions collide. A player who wants the Clock and the Storage Zone window open while
mining simply cannot arrange that today. Doc 23 (wall building) will add at least one
more tool window — this must stop being a per-milestone copy-paste before it grows
again.

---

## 1. Review findings (2026-08-20)

### 1.1 Window inventory

| # | Window | Built by | Position | Draggable | Close | Style | Layer |
|---|--------|----------|----------|-----------|-------|-------|-------|
| 1 | Labor / Stockpiles / Trade | `DockUI._make_window` | cascade from (32,130) | no | "X" plain | dark, r8 | 20 |
| 2 | Clock | `DockUI._make_clock_window` | same cascade | no | "X" plain | dark, r8 | 20 |
| 3 | Slice palette | `SliceController` | fixed (18,130) | no | "X" plain | dark, r8 | 22 |
| 4 | Mining Zone | `MiningDesignationController` | fixed (18,118) | no | "X" plain | **brown/orange, r6** | **24** |
| 5 | Storage Zone | `StockpileDesignationController` | fixed (18,300) | no | "X" plain | dark, r8 | 22 |
| 6 | Dwarves (DEV) | `DwarfDirector` | fixed (18,420) | no | "X" plain | dark, r8 | 22 |
| 7 | Furniture (ghost/installed) | `FurniturePlacementController` | fixed (18,470) | no | "X" plain | dark, r8 | 22 |
| 8 | Room info | `RoomOverlayController` | fixed (24,432) | no | flat "✕" | dark, r8, smaller fonts | 22 |
| 9 | Block Inspector | **`WorldRenderer`** | (48,128) | **yes** | red X | dark, r7, real title bar | 1 |
| 10 | World Build (world_info) | `DebugLoadingOverlay` | (16,16) | **yes** | red X | dark, r7, real title bar | 1 |

Non-window HUD surfaces (kept as concepts, folded into the shared theme): the dock, the
action panel above it, the save/load persistence toast, and the mining tool hint
callout.

### 1.2 Inconsistencies

1. **Only the two debug windows are movable.** Every gameplay window is fixed.
2. **Fixed positions collide**: Mining Zone (18,118) under the Slice palette (18,130);
   Dwarves (18,420), Rooms (24,432), Furniture (18,470) pile into one corner.
3. **Z-order is arbitrary and frozen.** Mining always on top (layer 24); Block
   Inspector and World Build render *below the dock* (layer 1 vs 20). No click-to-front
   anywhere.
4. **Three close-button designs** in three sizes; two header designs (real title bar
   vs inline label row).
5. **`_style()` is copy-pasted into 8 files** and has drifted: radius 8/7/6,
   background 0.065/0.070, border alpha 0.12/0.16, margins via `MarginContainer` in
   most, via stylebox content margins in Rooms.
6. **Close semantics differ**: DockUI windows `queue_free()` on close (cascade
   resets); controller windows hide; nothing remembers positions between sessions.
7. **Dock pressed-state is a patchwork**: `_target_canvas_visible()` special-cases
   seven targets plus per-controller signal hookups — no single source of truth for
   "what is open."
8. **~250 lines of Block Inspector UI live inside `WorldRenderer.gd`** — legal under
   Hard Rule 7 (it is on a CanvasLayer) but against the spirit of the
   presentation split.

### 1.3 Bugs found during the review

- **Gather** opens an empty action panel — no `_panel_actions` entry.
- **Calendar** and **X-Ray** open blank 360×260 windows — `toggle_window` targets fall
  through to `_make_window` with no `_window_rows` content.
- `DockUI._world_info_rows()` is dead code (already flagged in-file 2026-08-06).
- Two identical 📦 emoji on the dock (Storage Zone and Stockpiles).

---

## 2. Scope decisions

<span style="color:#3fb950;">**Chrome/content split. Controllers keep owning what is
IN their window; one shared system owns how windows look and behave.**</span> The Scene
Decoupling Contract is untouched: each controller builds a plain content `Control`,
registers it with the window manager (push-registration, the existing
`register_*_controller` pattern), and keeps its node refs to update labels. The manager
owns title bar, close button, drag, z-order, placement, and persistence. No controller
ever touches another window.

<span style="color:#3fb950;">**Hand-rolled `PanelContainer` windows — NOT Godot native
`Window` nodes.**</span> Embedded native Windows bring OS-chrome, focus, and
embedding-mode complexity for nothing: the current look is already right, the drag
pattern is already proven twice in this codebase (DebugLoadingOverlay, Block
Inspector), and everything stays on one CanvasLayer under Hard Rule 7.

<span style="color:#3fb950;">**Layout persists in a settings file, not the save file
(Alen, 2026-08-20).**</span> Window layout is a player preference: it survives across
every save, load, and new game. `user://ui_layout.json`, single owner
`UIWindowManager` (Registry-Pattern discipline applied to user data — no other script
reads or writes it). The save schema is untouched; this milestone adds **no** save
section.

<span style="color:#3fb950;">**The Mining Zone window normalizes to the shared dark
theme (Alen, 2026-08-20).**</span> The warm brown/orange chrome goes; mining's identity
lives in its world overlays and its orange DEV-button text, which stays.

<span style="color:#3fb950;">**Unbuilt dock entries are hidden (Alen,
2026-08-20).**</span> Calendar, X-Ray, and Gather leave `dock.json` until their
features exist. Labor, Stockpiles, and Trade stay (placeholder content, real movable
chrome). The dead `_world_info_rows()` is deleted with the DockUI migration.

<span style="color:#3fb950;">**Two window classes: `persistent` and
`context`.**</span> Persistent windows (Clock, Labor, Stockpiles, Trade, Dwarves,
World Build, Block Inspector) are user-opened, restorable at startup, and stay open
across tool switches — the "keep some open at all times" behaviour. Context windows
(Mining Zone, Storage Zone, Furniture, Room info) exist only while their subject
exists: they still auto-close when the zone is removed, the ghost is cancelled, or the
seal breaks, and they are never restored at startup. The Slice palette is **tool
state**, not layout state: its visibility follows the slice tool's active flag (which
already round-trips through the save file, doc 20) — the layout file remembers only
its position.

<span style="color:#3fb950;">**The announce-first tool contract is untouched.**</span>
`tool_requested` and `tool_active_changed` keep exactly their 2026-07-06 semantics.
This milestone moves window chrome; it does not touch click-tool activation.

---

## 3. Architecture

Three new files, all under `scripts/ui/` (new `class_name`s — remember the
editor-reload house rule):

**`UITheme.gd`** — static owner of the visual language. One place for: window
background/border, title-bar stylebox, the standard close button factory, panel button
styles (standard / dev-orange / danger-red), font sizes (title 16, body 14, small 13),
margins, corner radius (8 everywhere), and the dock's existing normal/hover/active
button trio. Every `_style()` / `_panel_style()` / `_window_style()` copy in DockUI,
SliceController, DwarfDirector, StockpileDesignationController,
FurniturePlacementController, RoomOverlayController, MiningDesignationController,
DebugLoadingOverlay, and WorldRenderer is deleted in favour of `UITheme` calls.

**`UIWindow.gd`** (`extends PanelContainer`) — the standard window. Structure: title
bar (`emoji + title` label, drag surface, `CURSOR_MOVE`) + close button + content
slot. Behaviour: drag via title-bar `gui_input` (the proven DebugLoadingOverlay
pattern), position clamped to the viewport on drag *and* on viewport resize, any
mouse-down anywhere in the window emits `focus_requested` for bring-to-front. Closing
**hides** (never frees) and emits `closed` — content and position survive for reopen.

**`UIWindowManager.gd`** (`extends CanvasLayer`, layer 22) — one layer hosting every
window. API sketch:

```
register_window(id, title, emoji, content: Control,
                opts = {persistent: bool, default_pos: Vector2, min_size: Vector2}) -> UIWindow
open(id) / close(id) / toggle(id) / is_open(id) -> bool
signal window_state_changed(id: String, open: bool)
```

- **Z-order**: `focus_requested` → `move_child(window, -1)`. Last-clicked wins, always.
- **Placement**: first-ever open uses `default_pos`, else the classic cascade
  (+28,+28 per open window, wrapping); once the player drags a window, its position is
  remembered and reused.
- **Persistence**: loads `user://ui_layout.json` at ready; saves debounced on
  drag-end/open/close. Schema:
  `{ "schema_version": 1, "windows": { "clock": { "x": 32, "y": 130, "open": true } } }`.
  `open` is honoured only for `persistent`-class windows.
- **One signal for the dock**: DockUI connects `window_state_changed` once;
  `_open_windows`, the per-window close lambdas, and the window half of
  `_target_canvas_visible()` are deleted. Tool pressed-state (slice, flag, mine,
  storage, rooms) keeps the existing `tool_active_changed` path — tools are not
  windows.

**Scene wiring**: `UIWindowManager` is presentation → a scene node in
`debug_world.tscn` (autoloads are for simulation state). Controllers reach it the same
way they reach the dock today — an exported NodePath + push-registration in `_ready`.

**Layer plan**: dock 20, all windows 22 (ordered within the layer by child order),
always-on-top mouse-ignoring HUD (mining hint callout, persistence toast) 24. This
fixes the Block Inspector / World Build windows rendering under the dock (they were on
layer 1) and removes mining's unconditional always-on-top (was 24).

**Block Inspector extraction**: the ~250 UI lines leave `WorldRenderer.gd` for a new
`scripts/ui/BlockInspectorWindow.gd`. The renderer keeps what is genuinely its own —
`_find_block_on_ray`, `_inspect_block_id`, the yellow outline mesh — exposed as a small
`inspect_at_screen(pos) -> Dictionary` API the window calls. Same split for the World
Build panel: `DebugLoadingOverlay` becomes a content provider; the manager owns its
chrome.

---

## 4. Behaviour spec (the macOS feel)

- **Drag** anywhere on the title bar; the window clamps so the title bar can never
  leave the viewport (a window can never become unreachable).
- **Click-to-front** on any mouse-down inside a window.
- **Windows swallow their clicks.** Controls already consume mouse events before
  `_unhandled_input`, which is what every click-tool raycasts from — each migration's
  checklist re-verifies that clicking/dragging a window never leaks a designation into
  the world.
- **Close = hide.** Reopening restores content state and position. Context windows
  additionally self-close when their subject disappears (existing behaviour, kept).
- <span style="color:#d29922;">**Esc order (tune in playtest):** active click-tool
  first (unchanged — Esc deactivates the tool), else close the topmost open window,
  else nothing. If tool-first feels wrong in play, flip to window-first for context
  windows only.</span>
- <span style="color:#d29922;">**Stockpiles dock emoji** duplicates Storage Zone's 📦 —
  pick a replacement in-engine when the dock entry is touched (candidates: 🏷️ 📚 🗃️).</span>

---

## 5. Phases

### Phase U1 — Foundation
`UITheme.gd`, `UIWindow.gd`, `UIWindowManager.gd`; manager node added to
`debug_world.tscn`; layout file load/save.

- [ ] A `UIWindow` with dummy content can be opened, dragged, clamped, closed,
      reopened at the same position, and brought to front by clicking.
- [ ] `ui_layout.json` appears in `user://`, survives a restart, and a hand-corrupted
      file falls back to defaults with a warning (no crash).

### Phase U2 — Migration (one window per step, playtest checkpoint each)
Order, lowest risk first: **Clock → Labor/Stockpiles/Trade → Dwarves → Slice palette →
Storage Zone → Furniture → Rooms → Mining Zone → Block Inspector (renderer extraction)
→ World Build.** Each step: controller builds content, registers, deletes its local
chrome and `_style()` copy.

- [ ] Every window in §1.1 renders with identical chrome and is draggable.
- [ ] The three-window overlap corner (Dwarves/Rooms/Furniture) can be hand-arranged
      and stays arranged after a restart.
- [ ] Dock pressed-states still track open/close and tool activation exactly
      (including Esc-cancel of every click-tool).
- [ ] Zero `StyleBoxFlat` window styles remain outside `UITheme.gd`.
- [ ] Clicking and dragging windows never triggers mining/storage/furniture/flag
      designations underneath.
- [ ] `WorldRenderer.gd` contains no Control/CanvasLayer code.

### Phase U3 — Dock & content cleanup
- [ ] Calendar, X-Ray, Gather removed from `dock.json`; every remaining dock button
      does something real.
- [ ] `_world_info_rows()` and the rest of DockUI's dead window code deleted.
- [ ] Stockpiles emoji deduped.
- [ ] Doc `20_player_interface/23_user_interface.md` updated to describe the window
      system as built.

---

## 6. Out of scope for v1

<span style="color:#f85149;">**Resize handles / minimize / collapse-to-title-bar /
edge snapping.**</span> The component is shaped so these can be added later; none ship
now.

<span style="color:#f85149;">**Real Labor / Stockpiles / Trade content.**</span> They
keep placeholder rows; their windows just become movable. Real content arrives with
their systems (docs 41/18/44-era work).

<span style="color:#f85149;">**Godot native `Window`/theming-resource rework.**</span>
No `.tres` theme resources (Hard Rule: never edit `.tres` by hand); `UITheme.gd` stays
code.

<span style="color:#f85149;">**Gamepad/keyboard window navigation.**</span> Mouse-only,
matching the RTS input model (doc 22_mouse_input).
