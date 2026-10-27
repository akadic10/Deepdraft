# 23 — User Interface

**The Sky Dial: the sky window (2026-10-26, 272):** the dial is Hearthblock. A stone
window under a hewn-oak lintel shows the sky at this hour and the season's land. The sun
crosses it from sunrise to sunset, and the moon by night, with the weather in it. A plate
under it gives the time, the date and the year's seasons, with the days to the next
season. See "The Sky Dial".

**Counts, profession pictures and the view banner (2026-10-26, 272):**
- Colony on the dock counts the idle dwarves, and Place what is ready to place. Each
  count's hover card says what it counts. See "Counts".
- Each row of Colony Dwarves shows the profession's picture beside the portrait, and
  Miners a bar to the next level.
- While Appeal or X-ray is on, a banner at the top centre names the view, and the toasts
  sit below it. See "Views".

**Type (2026-10-26):** every word is set in fonts shipped with the game: Fredoka for names,
headings, buttons and the HUD's titles, Nunito for text, and a symbol font behind both.
Sizes come from one type scale of seven steps, so a heading or a label is the same size in
every window. The Sky Dial's clock no longer wobbles as its minutes change. See "Type".

**The UI scale (2026-10-25):** Settings has an Interface tab with the UI scale: Auto, 100,
125, 150 or 200%. Everything drawn over the world grows together, and the world keeps its
full resolution. Auto follows the scale Windows sets for the screen. See "The UI scale".

**The tool bar (2026-10-25):** every tool shows one bar above the dock: its picture, name
and keys, its settings as steppers, the last order with View, then Undo and Done · Esc. A
held drag shows a tag with what it would order and its cost against the stock. Undo and
Ctrl + Z take back the newest order of any tool. See "The tool bar".

**The DEV item stamper (2026-10-25):** Development's Spawn Drops, Spawn Furniture and Spawn
Bushes are replaced by one Item stamper. It puts any item on a floor as one pile, chosen in
a window laid out as Place, with search, wood and amount. See "The item stamper".

**The title screen (2026-10-25):** the game opens on a title screen over the painted
panorama instead of in the newest save: Continue (that save, on a pine board), New game,
Load game…, Settings… and Exit game. The game menu gains Quit to main menu…, which asks
first and returns here. See "The title screen".

**Keys and Settings' Controls (2026-10-25):** Space pauses and resumes, 1 and 2 pick the
speed, V turns the Appeal view on and off and X X-ray; their buttons' hover cards name the
keys. Settings has a third tab, Controls, listing every key and mouse control. See "Keys".

**Personal tastes (2026-10-25):** each dwarf loves, likes and dislikes a few
furniture designs and woods, found by using them. The character sheet's new Tastes tab shows
them ("?" until found) and how their own bedroom feels to them; the journal tells each
found taste; and a found taste moves the appeal they feel, named in the room's thought.

**The Appeal view (2026-10-25):** a new view toggle before X-ray dims the world,
tints each sealed room's floor by its appeal word and lights the pieces it counts. Its
scale rises above the dock, hovering a room shows its parts, and clicking it opens the room
window on its Appeal tab. See "The Appeal view".

**Room appeal (2026-10-25):** a sealed room's appeal adds up what it holds, for its
size, and its word (Horrid, Plain, Pleasant, Beautiful) shows on the room window's banner
and its new Appeal tab, which lists every part. A sleep, a meal or a game in a room leaves
its word's thought. See "Room appeal".

**The journal (2026-10-25):** Colony's page has a journal beside its rows: what the
dwarves said, newest day first, complaints then praises, one line per thought a day with
the speaker's face, name and words and how many share it. See "Colony's page".

**Settlement overview (2026-10-25):** Colony on the dock opens the settlement's own
page instead of a menu: its name, when it was founded, a badge for each profession, the
colony's mood, Colony's entries, and five rows at a glance (dwarves at work, food in days,
own bedrooms, storage and happiness). Planting the flag now asks for the settlement's
name, and the name shows in the founding toast and Events, the game menu's title and the
Load slots. See "Colony's page" and "Naming the settlement".

**Events (2026-10-24):** the colony's event log has its own window, opened from a
brass bell on the dock after Inventory: standing warnings at the top, then the days
newest first, each entry with Locate. The bell counts what is new and turns rust while
a warning stands. The hungry-dwarves box under the Sky Dial is gone; its warning stands in
Events. See "Toasts and the event log".

**Hearthblock Colony (2026-10-23, 259):** Colony's Dwarves (two of the colony's
dwarves), Settlement flag, Labor (a ticked work ledger) and planned Trade (a balance with
coins and goods) use Hearthblock icons on the people tile; since 2026-10-25 they are the
entries on Colony's page. This completes the menu icon pass.

**Hearthblock professions (2026-10-23, 259):** each profession has one Hearthblock
icon, named in `professions.json` and shared by the Crafters menu (on the settlement
tile), the career map and the equipment view. Planned careers dim their icon. The
copper line icons and the painted Crafters art are gone.

**Hearthblock Zones and Construction (2026-10-23, 259):** Storage, Farming and Animal
pasture, and Build, Shapes, Copy and Blueprints, use Hearthblock
icons on the work tile. Farming and Animal pasture stay locked. Build (Stone block until
2026-10-26) shows a wall going up in stone, wood and grass-topped earth, its next block the
cyan plan the game draws; Shapes shows a ring of walls beside a flight of stairs, its top
step a plan; Copy a small hut inside the blue copy box; Blueprints a blue sheet with a
room drawn on it, rolled at the back.

**Hearthblock Orders and world markers (2026-10-23, 259):** the six Orders tools use
Hearthblock icons on the work tile. The markers over ordered trees, bushes, flowers,
reeds and stones show the same pictures on a small tile, replacing the emoji, and
Uproot has its own icon.

**Time and view controls (2026-10-23, 259):** Pause, 1× and 2× hang centred under
the Sky Dial. X-ray and Slice end the dock as its last group, plain icons the same size
as the others. The slice arrows and the X-ray options rise from Slice only while that
view is on.
See [Live Status HUD](#live-status-hud).

**Dwarf concern badges (2026-10-17, 214):** serious hunger, exhaustion and unhappiness
(Unhappy or Miserable on the character sheet's mood scale) show one small icon above the
animated head. The character sheet's Right now gives the reason and an action, and the
compact panel shows the icon beside the activity. A scene-owned CanvasLayer projects the
icons, respects terrain/slices/loading, and fades them at distant zooms.
- **One concern at a time** (`DwarfConcern`), the first that applies: Famished; exhausted
  (rest at 15% or less, or a rest search or trip still unresolved after six seconds);
  Hungry after a food search actually failed; Unhappy or Miserable, naming the strongest
  bad thought. A hungry dwarf still looking for food shows nothing. A reserved portion
  reads "Collecting food" and a meal in hand "Has a meal"; exhaustion clears once the
  dwarf settles into sleep, and a bed search reports no bed only after falling back to
  ground rest.
- **Display** (`DwarfNeedIndicators`, layer 19): needs and terrain occlusion are re-read four
  times a second, also while paused. A badge pulses when its concern changes, fades when
  it resolves and never takes a click. Hidden slices, off-screen heads and heads behind
  terrain (the slice-aware picking ray, or X-ray's visible faces while X-ray is on) hide
  it, and the screen's height sizes it. Thresholds and sizes are in
  `data/ui/dwarf_indicators.json` (UIRegistry).
- **Pictures** (2026-10-26): each badge is its concern's Hearthblock icon on a people tile,
  as the world order markers sit on theirs: an apple for food, a crescent moon with two Zs
  for rest, and the mood scale's Unhappy face for mood. The character sheet and the compact
  panel show the same pictures. `dwarf_indicators.json` names them and the tile's `family`.

**Optional mining guide (2026-10-17, 208; dotted lines 2026-10-26):** Mine blocks no
longer automatically outlines individual terrain voxels. The tool bar's **32 × 32 guide**
switch, off by default, draws thick lines on the world X/Z multiples of 32, counted from
the world origin, and thinner dotted lines halfway between them, on the other multiples of
16, so each 32 × 32 square shows its four 16 × 16 quarters. Its card reads "Thicker lines
every 32 blocks and dotted lines every 16 while mining. A guide only: mining still marks
single blocks." It is an alignment aid only: it never snaps, resizes or changes
designations, orders or the cursor. The choice holds when switching tools or
reopening Mine blocks, a newly loaded scene starts with it off, and the guide shows
only while mining. Doc 24 has how it draws.

**DEV construction and plants (2026-10-17, 207):** select a stone blueprint or
its materials crate for **DEV: Finish construction** (its rules are under
"Construction" below). Development also had
**Spawn Bushes**, creating one uprooted bush of each berry species near the view
centre, ready for hauling or **Place → Plants**; since 2026-10-25 the item stamper
makes them (see "The item stamper").

**Panoramic loading (2026-10-17, 206):** `WorldLoadingScreen` hides the game HUD
and consumes controls until the full terrain overview, water/lighting/scenery
queues and save restoration are complete. A fixed-height panorama reveals more
of its sides at 21:9 and 32:9 than at 16:9. A small beer mug and slim progress bar
track actual generation work. Each startup or save reload randomly chooses the
mountain or underground-settlement panorama, holding that image until reveal.
UIRegistry owns the artwork list in `data/ui/loading_screen.json`;
the historical DebugLoadingOverlay remains World info.
- **The gate** reads its owners every frame, never a timer or log text: the generator's
  maps, every overview tile built with none queued, the cavity shell, added terrain,
  water, underground lighting and seasonal art settled, trees, ground details and
  wildlife ready, and SaveManager done restoring. Three ready frames in a row, then a
  full mug for a quarter second, come before the reveal. The first near-camera tiles
  never end it, and later terrain edits never bring it back; a reloaded scene makes a
  new one.
- **Progress** weighs real work (the maps, the overview tiles, then the scenery) and
  never counts time, so the mug only rises.
- **The art** is one fixed-height band of the panorama, at most 32:9 wide
  (`panorama_aspect`) and centred. Narrower screens lose its sides, never its height,
  with no stretching or bars, so the gate, the bridge and the dwarves stay in the middle
  16:9; the title screen crops its art the same way (`LoadingArtwork.band_rect`). A
  dark gradient over the lower part keeps the title and the mug readable, and both scale
  with the screen's height. The mug is drawn, not painted, so its fill stays live.
- **The pick** uses its own random generator, so the art never draws from the
  simulation's random numbers, and only the chosen picture loads.
- **While it shows,** every other CanvasLayer is hidden and gets its own visibility back
  at the reveal (World info stays closed if it was), and the clock is held (a WorldClock
  loading hold, doc 13), which the reveal and an early scene exit release.
- **A failed generation** never reveals: the screen stays up and shows `failed_label`
  from `loading_screen.json` with the reason (`WorldGenerator.generation_error`, doc 13),
  instead of waiting forever (doc 258).

**Audio preferences (2026-10-13, 168 and 170):** the Audio tab of the game menu's
Settings: separate Ambience and Effects sliders, Mute buttons and Restore defaults.
Preferences persist across settlements. Ambience includes the new
weather/season-aware woodland soundscape and softens on pause; Effects includes
existing work, wildlife, water, fires and notifications. The doc 170 expansion adds
rain, thunder, seasonal textures, shoreline, frogs and cave drips to Ambience.
Actual wolf howls use Effects. The Sky Dial shows Rain and Storm (see "The Sky
Dial"). The soundscape's rules are in doc 13 (`AmbientAudio`).

**Fixed time/Slice HUD (2026-10-12, 142; placement replaced 2026-10-23, 259):**
Slice's tower has exact ±1/±4 arrows and a live level, and Slice keeps the last
height while off. Wheel over the tower steps the plane. The old upper-left strip, movable Slice window and
Menu shortcut are removed. See "The Slice Tool" and "Live Status HUD".

**Sky Dial (2026-10-12, 141; its painting replaced 2026-10-26 by the sky window, 272):** the
upper-right HUD presents season/day/time, current weather and the seasonal day/night
cycle. Hover/focus adds year, phase and sunrise/sunset. It replaces the Clock window and
Menu shortcut. Pause and speed hang under the dial (259), and ordinary windows make room.
See "The Sky Dial".

**Remaining illustrated menus (2026-10-12, 140; partly replaced 2026-10-23 to 25, 259):**
Craft and Development share the illustrated submenu rail. Room furnishings replaces the
Place category name Rooms. Room facts have small supporting symbols. Colony's flag entry
locates/inspects its existing flag or order, or opens its packed recovery in Place (see
"Colony's page"). Planned crafting catalogs remain browsable with explicit status. Since
the overhaul, Colony opens its page and Menu the game menu, and Place and Inventory have
no category pictures or dropdown.

**Illustrated Construction (2026-10-12, 138; icons now Hearthblock, 259):** the
Construction entries use the same art style and hover/focus names as the dock.
See "Floating Dock" and "Construction".

**Illustrated Zones (2026-10-12, 137; icons now Hearthblock, 259):** Storage,
Farming and Animal pasture use the same icon-only rail and parent anchoring as Orders. Storage is usable;
Farming and Animal pasture are dimmed with lock badges and explain their planned
status on hover, focus or activation. They cannot dispatch work or switch tools.
See "Floating Dock" and "Tool shelves".

**Illustrated Orders (2026-10-12, 136; icons now Hearthblock, 259):** six caption-free
command icons form a short rail above Orders, with hover/focus names, active copper
borders and a gap before Cancel. The 64/56 px icons wrap beside moved inspectors. The
live counts, mining width/depth, Undo and Done · Esc are the tool bar's since 2026-10-25.
Zones subsequently adopted matching art in 137; all order ownership remains intact.
See "Floating Dock" and "Tool shelves".

**Illustrated command dock (2026-10-12, 135; icons now Hearthblock, 259):** the bottom
bar's commands are pictures with no permanent captions. Hover or keyboard focus
shows a name and explanation; the active command has a copper outline and bottom
notch. Square 72 px desktop / 56 px compact buttons retain the existing order,
with gaps before Menu and Development. Menus fit above the measured rail.
See "Floating Dock".

**Settlement flag (2026-10-12, 133):** the placed banner is ordinary furniture
on the compact panel, including Move/Uninstall, occlusion and slice picking rules.
Packed flags appear in Place → Room furnishings. Reinstallation updates the settlement
anchor; the initial founding command remains once-only. Packing the flag never
unfounds the colony: its last installed place stays the anchor until it is installed
again, Uninstall grants no second free flag, and only founding brings the starting
dwarves. The packed flag is an ordinary crate in storage with no recipe, and the item
stamper refuses it (one per colony).

**Furniture Move (2026-10-12):** installed furniture and crafting stations offer
Move on the compact panel. Aim/rotate the normal preview and click
to queue worker relocation; Escape before confirming leaves the piece installed.
Source and destination offer Cancel move. The chosen piece retains its material
and bed ownership (doc 132).
- The destination keeps every normal placement rule, wall height and reach included.
  It cannot overlap the piece itself, which stays installed, reading "Waiting to
  move", until a worker packs it.
- A worker packs that exact piece, carries it and installs it; no spare item is used.
  Cancelling before packing keeps the piece where it stands; afterwards the packed
  piece stays a loose item for storage or Place, and a dwarf carrying it sets it down.
- A Move plan has no DEV Instant Build, as it needs its real item. A busy workbench
  releases its order, which resumes at an installed bench (doc 44).

**Storage window:** a storage zone's window is a filter of pictures
with Filter and Contents tabs hanging under it; see "The storage window" under the
Stockpile Zone System.

**Food indicator (2026-10-12, 131):** the character sheet shows Food beside Rest, with Satisfied/Hungry/Famished states. Its hover gives
the last meal, how long ago, the arrangement and the food-search status; while hungry,
the hunger effects show under its bar. The dining thoughts are on the Mood tab.
Current activity distinguishes food search, emergency berry picking, dining and
eating. Hungry dwarves unable to find reachable food raise a warning in Events, with
harvesting/storage-access guidance, until they eat (see "Toasts and the event log"). The
food and dining rules are in doc 41.

**Development menu (2026-10-12):** Development is its own dock entry at the far
right, after Menu. It opens directly with no parent/back link. Its eight actions
are Block inspector, World Build, Cave explorer, Dwarf tools, Water tools,
Arrival status, Item stamper and Time & weather (the stamper replaced Spawn Drops, Spawn
Furniture and Spawn Bushes on 2026-10-25). The last panel
owns +1 Hour, +1 Season and weather cycling; the player clock shows facts only.
Block Inspector moved here in 130; World Build and time/weather tests in 140.
All 15 cycling locator commands and their runtime handlers/state
have been removed. Normal click inspection and Locate/Follow remain available.

**Development tools switch (2026-10-22, doc 258):** `data/ui/dev_tools.json` →
`enabled`, read once at startup; a missing or malformed file reads as off. Set it to
false before handing a build to players. Off removes:
- the Development dock button and menu (`"dev": true` in `dock.json`);
- every DEV window (Cave explorer, Water, Dwarf tools, Job inspector, Time & weather),
  the World Build overlay and the block inspector;
- every object-window action with the `dev` variant (DEV Build, DEV: Finish
  construction, DEV: Instant Build, DEV: Remove, DEV: Grow to maturity) and DEV Mine
  in the mining zone window, along with the DEV notes in their descriptions. The
  furniture window lives in `FurnitureWindow.gd` and the mining zone window in
  `MiningZoneWindow.gd`; both check `UIRegistry.dev_tools_enabled` themselves.
  `tools/lint_project.py` (`dev-gate`) fails a script with DEV buttons that never checks
  the switch, and a DEV dock entry outside a `dev` menu.

The rising-water warning is player feedback, so it stays on. `DevToolsSwitchTest` checks
the off state. `SaveManager.configure_storage_for_testing` is not a DEV tool: its
`OS.is_debug_build()` check keeps tests away from the player's saves, so it stays outside
the switch. **DEV: Instant Build** takes one matching packed item through the ghost's own
fetch path and installs in that item's material; with none available it builds free. (It
once left the item in place, a free copy; `DevInstantBuildTest`, gate.)
Native menu routing and layouts pass at 960×540, 1280×720 and 2560×1440;
captures and checks are in `tmp/development_menu_20261012/`.

**Construction (2026-10-12):** the dock entry sits between **Rooms** and **Place**
and opens **Build**, **Shapes**, **Copy** and **Blueprints** (since 2026-10-26). The
Floors submenu and its plank and stone floors were removed on 2026-10-26 (doc 12, "No
separate floor blocks").

**Build (2026-10-26, docs 273 and 275):** Stone block became Build, which places blocks of
four materials. The materials and their order are in `data/construction/materials.json`;
each holds construction kinds from `data/construction/blocks.json` (those whose `tool` is
`build`):

| Material | Its menu | Costs | Builds | When mined |
|---|---|---|---|---|
| Stone | Native stone | 1 rough stone | the natural rock of its layer | as that rock |
| Dirt | — | 1 soil | `base:terrain:surface:dirt` | as dirt |
| Grass | — | 1 soil | `base:terrain:surface:grass`, one block tall, only under open sky | as grass |
| Wood | Upright log, Horizontal log; oak, pine, juniper or apple | 1 log of the chosen wood | `base:construction:log:<wood>:<up, x or z>` | its log back |

- **The choice:** the tool bar shows the four as pictures, the chosen one lit; Q and E step
  through them. Build opens on the last material used.
- **Menus (the owner's format A, 2026-10-26, doc 275):** Stone's and Wood's pictures open a
  menu above the bar: the dock's menu slab, joined to the picture by a short copper line.
  - Stone's holds native stone, the only stone for now; Wood's holds its two logs over its
    four woods, each wood's stock on its tile's corner, in rust at none.
  - A picture shows its material's chosen type, Wood's in the chosen wood, and each material
    keeps its type. The first wood is the one the colony holds most logs of.
  - Its hover card is named for the material, then names the chosen type (owner,
    2026-10-26): "Wood", then "Upright oak log. Stands on end. …" and "Click it for the Wood
    menu."
  - The menu stays open while the player picks. Esc closes it before it ends the tool; so do
    a press off the menu and the bar (that press still reaches the world), the picture
    again, and another material.
- **Logs** fill their block (doc 24, "Built logs"). An upright log stands; a horizontal one
  lies along the drag's longer side, and R turns it for a click or a square drag. The preview
  shows green ghost logs lying as they will be built (the owner's pick). The crate takes only
  the chosen wood, and the tag counts it: "18 blocks · 18 pine logs · 6 in stock".
- **Grass** refuses a cell with any block above it ("Grass needs open sky above"). The tool
  hides the height, since grass is one block tall.
- **Cave soil** is never built: farm ground for cave crops is found by mining (doc 43).
- Everything below holds for every material: the stone named in the panel and the crate
  is the material's own good (rough stone, soil or logs).
- Each material plans, stages its good, builds, mines and saves as a stone block does
  (`BuildMaterialsTest`); a log plan also keeps its wood and each log's direction.

**Shapes (2026-10-26, doc 273):** the shelf's second entry lays Build's materials out as a
shape, each block still planned, built and mined on its own. The tool bar shows the
shape (Tab, Shift + Tab back) and the material (Q and E) as rows of pictures:
- **Rectangle:** dragged corner to corner, up to 32 across; one wide, it is a wall. Hollow
  keeps its edge, one block thick; Filled (F, or the switch) makes a slab or a platform.
  Height as Build's. A hollow rectangle's Door (Shift + wheel) leaves a gap 2, 3 or 4 wide
  (as the doors come) and 3 tall in the middle of the side facing the camera, keeping its
  corners; a side too short for it, such as a wall's end, passes it to the other side in
  view.
- **Circle:** dragged from its centre, up to 31 across: a ring one block thick, or filled.
  A cell is in when its centre lies within the radius and a half.
- **Stairs:** dragged from the foot toward the top, one block up a step along the longer
  axis, as wide as the drag across it, each step a solid column under its tread so it
  stands on the ground and beside the step before. Rock (or an unexplored cave) in the 3
  blocks above a step stops the flight there, and the tool bar says which step. Grass, one
  block tall, makes no stairs.
- **Logs in a shape** (doc 275): a hollow rectangle lays each side along its length, so its
  corners are L joints; a filled one lays them along its longer side, a circle along the
  ring and stairs across the flight.
- The shapes are in `data/construction/shapes.json` (read by `BlockRegistry`), their cells
  in `ConstructionShapes`; one drag is one plan, so Undo takes back a whole shape
  (`ShapeToolTest`).

**Copy and Blueprints (2026-10-26, doc 273):** the shelf's third and fourth entries.
- **Copy** (`BlueprintController`, made by `ConstructionController` as its child): drag a
  box's footprint, Height (Alt + wheel) up to 16, With floor (F) reaching one layer down to
  take the ground the box stands on. The box stands on the ground: a drag begun
  on a wall's face starts on the floor below it. The tag gives the box's size and how many
  blocks it would copy. On release every solid block in it becomes the material that builds
  it: rock, ore and gems stone; dirt (cave soil too) and grass themselves; a log its wood
  lying its way (`log:pine:x`, doc 275); plans their own. Natural blocks count too, since built stone is the natural
  rock of its layer: a copy of plans alone would leave out every stone block built. Air,
  water and bedrock stay empty. What the colony has not seen copies as the slice shows it,
  its strata, so a copy never gives away a cave, a buried deposit (cave soil would copy as
  dirt) or water inside the rock (Hard Rule 11): a block counts as seen once it was dug,
  built or explored, or faces open air or such a cell (2026-10-26, after a copy of a
  mountainside showed its buried soil). The copy, trimmed to its blocks, is kept as
  "Blueprint N",
  and the Blueprints window opens on it with its name chosen, ready to type over. Copy
  makes no orders, so its bar has no Undo; it shows what it last copied.
- **Blueprints** (`BlueprintLibraryPanel`, registered by `DockUI.register_blueprint_controller`),
  laid out as Place: the starters (stone hut, log cabin, stair flight, garden terrace,
  in materials workers build), then Yours, as pictures; the chosen one's card with its name (a field for the player's
  own), size, picture, each material's blocks against the stock (rust when short) and its
  file; Place, Rename, Delete (the player's own, pressed twice: "Delete for good") and Open
  folder. Opening the window reads the folder again; files it cannot read are named at the
  bottom with why.
- **Placing:** Place announces `blueprint_place`, so the other tools step aside. The
  blueprint follows the pointer as a green ghost, its corner at the air beside the face under
  it; R turns it a quarter (Shift + R back), a lying log turning with it. Blocks in the way show in rust and are left out;
  unexplored space shows as rock does; the slice hides what is above it. The tag gives the
  turned size, the blocks and each material against the stock, and what is in the way. A
  click plans it, one plan a material, and one Undo takes the placement back whole. Esc or
  Done ends placing.
- **Files:** one JSON file a blueprint in `user://blueprints/` (see `BlueprintLibrary` in
  doc 13), its picture beside it. To share one, copy its file; a friend's dropped into the
  folder appears the next time the window opens. `BlueprintTest` covers the files, Copy
  and placing.
- **Shelf hover cards** stand above the whole shelf (`DockIconButton.shelf`), so on a shelf
  of two rows a card never covers the row above it.

**Taking blocks out of plans (2026-10-26):** in Build and Shapes, Ctrl + drag a
box over plans (or Ctrl + click one) to take their blocks out, every planned block in the
box's columns up to the slice, shown in rust while held. A plan left empty is gone; its
crate gives back the goods it no longer needs, and a builder at a taken block lets go.
Cancel construction, on the plan's panel, and Undo still take back a whole plan.

Click a terrain face or drag a footprint to plan full voxels in adjoining air.
Every block is planned, built and mined on its own, and a finished block is ordinary
terrain: Deepdraft never makes a building object (owner, 2026-10-23).
Designing is building: a shape or a blueprint becomes plans at once, in the world, beside
the rock, ore and furniture it has to fit. The 2026-10-26 concept also drew a drafting
board in a window, laid out in the world later; it was not taken, and there is no design
mode with a commit step, no paint tool, and no palette of doors or furniture apart from
Place.
Alt + wheel, or the tool bar's Height stepper, adjusts height (1–8 blocks), and a drag
clamps at 32 × 32 cells in either direction (`max_height` and
`max_drag_size` in `data/construction/blocks.json`). The displayed slice limits
the actual order. Green previews show the selected cells, with their blocks and stone
against the stock on the tool bar's tag; blue cells mark pending work. Ctrl + drag takes
planned blocks out, the tool bar's Undo takes back the newest plan, and Escape or
Done ends the tool. Click a blue cell or the project's materials crate, during
construction mode or afterward, to select its whole pending area: the outline marks it,
and the compact panel's status names the stage (Waiting for stone, Delivering
materials, No delivery access, Waiting for builder, Building, Needs attention) with
the stone delivered or blocks built so far. The crate shows up to six stones; the
status holds the exact count. **Cancel construction** removes the
remaining plan while keeping completed stone and unconsumed materials. With DEV tools
on, the plan (or its materials crate) also offers **DEV: Finish construction** (doc 207):
it builds the plan at once, even while paused, spending the staged stone first and
supplying the rest free. Workers on the project release through the normal task
lifecycle and drop what they carry. Every normal check still applies (occupancy, water,
discovery, support and the slice), so a blocked block stays planned and the panel's
description says why; supported spans finish whichever end was planned first. A plan
left unfinished keeps only the staged stone it still needs, and saves and resumes as
before; a finished one removes its crate, work and reservations. Hidden
plans cannot be clicked through terrain; completion, cancellation or lowering the
slice below the whole area closes the inspector. Existing solid terrain
must be mined first. What a plan may occupy is in doc 12 (roadmap 127).

**Crafting browser (2026-10-11):** Craft → profession now opens compact recipe
icons grouped by the categories in recipe data, with case-insensitive search
by name or category. Recipes / Orders (count) tabs share the left column; the
selected recipe has one illustrated parchment detail card on the right.
Crafting keeps the browser open and updates the order count. Materials and
descriptions scroll independently of the fixed wood, quantity, Queue and Place
controls. Live stock changes preserve focused icons, order rows and scrolling.
Planned professions retain their preview without recipe/order tabs or actions.
As of 2026-10-13, Rudimentary uses Workshops, Lighting, Access, Rooms, Dining and
Starter tools. Rooms groups beds, hearths and doors; Dining groups stools and
benches; Lighting groups torches and campfires, matching their Place categories
(doc 114). The window was rebuilt on 2026-10-24: see "The crafting window".

**Object permissions (updated 2026-10-11, 110):** loose goods and placed water stones
expose Allow/Disallow on the compact panel. Stored goods have no permission action
and are available colony stock. Inventory still reports Disallowed for goods
outside storage alongside available/reserved goods. Disallow never hides an
object or stops a placed stone's water effect.
Allowed placed stones offer Move and Pack for storage; allowed packed stones
can be placed through their inspector (Place stone) or Place → Water. A placed
stone's status reads "Working while placed", "Packing requested" or "Disallowed:
dwarves leave it here". The stones' rules are in doc 33.

**Profession crafting (2026-10-09):** Craft opens profession icon submenus above
the dock. Choosing Rudimentary opens Worker recipes with grouped categories and
that section's live Orders; since 2026-10-24 the window's Crafters row switches
professions. Planned profession sections preview their purpose without enabling fake crafts;
Miner's equipment preview is separate from its already playable profession.
Campfires and log stools are new Rudimentary recipes. Campfires center on the
cursor tile within a visible 3×3 placement area. Queue and Place remain
visible at 960×540; windows settle their wrapped layout and stay above the dock
(doc 100); the campfire's placement area is under "Placing" in "The Place window".

**Ladder workflow (2026-10-09):** Craft offers ladder sections at the crude
workbench. Place → Access shows the complete route, height and required section
count. Aim at a cliff face, its top edge or the floor beside its base: a wall hit
picks the facing, R turns a ground or edge aim, and Esc finishes. Short of sections,
the hint names the height, the sections needed, those available and how many more to
craft; the upper landing must be inside the slice. The ladder inspector pauses/resumes building
and requests or cancels dismantling. Dwarf inspection identifies installation,
climbing with cargo and safe descent. Craft's recipe list scrolls on small
windows. The ladder's rules are in doc 32 (roadmap 86).

**Plant placement update (2026-10-09, 85):** bushes, cuttings and flowers display a
3×3 cursor/queued outline and a specific reason when blocked: soil or a level 3×3
patch, clearance, spacing from plants or queued orders, or open sky
(`FurnitureGhostVisuals`). Flower inspectors add Move/Uproot; Place → Plants
lists three stored flower shapes with thumbnails. The dwarf inspector labels
flower lifting/carrying/replanting appropriately.

## Overview

All UI is implemented as Godot `Control` nodes on a `CanvasLayer`. No 3D world-space UI elements. The interface is divided into four zones: **Status Bar** (top), **Side Panel** (right), **Dock** (bottom — a floating command bar), and **Notification Layer** (overlay).

Interaction principles every surface keeps:

- Selecting something leads straight to its action when one is available, with no
  extra confirmation click (for example, clicking an available Place tile starts
  its placement preview).
- Live counts update in place; they never move or reorder click targets.
- **Locate** moves only the camera. It never orders a dwarf to walk or changes
  their task.
- Authored data does not mean a mechanic is live. UI shows descriptions apart from
  active effects and says so when an effect is not implemented (Details labels
  trait effects as not active yet).
- A number carries a word: "13.3°C Chilly", "81% · Satisfied", "Plain · 4.5".

**Stonehearth as the reference (owner, 2026-10-23):** the UI looks to Stonehearth for how
things work, never for how they look. Each idea is redrawn in Hearthblock and in
Deepdraft's own terms (doc 64), never copied as it is. Not taken:
- multiplayer;
- trapping grounds (hunting is the planned Hunter's work, doc 45);
- net worth and town tiers;
- military strength (combat's UI is doc 52's);
- settlement-wide bonuses;
- citizen attribute numbers.

**Screen shapes (owner, 2026-10-26):** the HUD keeps its corners at every width. The Sky Dial
and its time controls stay top right at 21:9 and 32:9, while the dock, the tool bar, the
compact panel and the windows sit in the middle. Wide screens only need to not break. A
HUD width setting, keeping the corner pieces inside a 16:9 or 21:9 area, waits until
players ask. Layout care goes first to the common sizes, 1920×1080 and 2560×1440, and to the
small end: 1366×768 and 1280×800.

**Storage inspection (updated 2026-10-22):** clicking a ground zone opens the
Hearth & iron storage panel. Storage furniture (barrels, chests, shelves) was
removed on 2026-10-22 and returns with the barrel/chest milestone. Filters and
Contents share a persistent capacity readout: occupied cells and total goods.
Players can select whole categories, individual items, or mixtures; partial
categories show a dash. Accept all goods and Clear all filters act immediately.
Contents groups totals by item/material in alphabetical order, preserving wood
variants and counting all units in produce crates. It has no Allow/Disallow
buttons. Goods excluded by the filters remain listed with Awaiting relocation;
dwarves move them only after reserving accepting storage with room. Zone removal,
native window dragging and world-input isolation remain. The filter model is
under Stockpile Zone System below.

## Object selection (implemented 2026-10-04)

**Compact object panel (2026-10-23):** every world object opens a compact panel beside
the dock. That covers:
- furniture (installed pieces, plans and moves) and loose or stored goods;
- dwarves;
- trees, shrubs, flowers, reeds, boulders and scree;
- wildlife;
- ladders, bridges and water stones;
- construction plans and terrain faces.

**Tools keep their clicks:** while a tool is on, the explorer leaves world clicks to it.
The scene's tools are its `click_tool_paths`; tools made at run time, Copy and placing a
blueprint, join the `click_tool` group (2026-10-26: until then a press with Copy selected
the ground instead). `ConstructionInputTest` drags Copy round a wall with the real mouse.

The explorer window's general layout is retired (phase 6): its one window is a dwarf's
character sheet. Rooms, storage and DEV tools keep their own windows, and a click on a
storage or mining zone opens that zone's window, never the panel. The rules:
- **Dwarves.** The panel shows:
  - the name on a band in the people colour, with the mood badge beside it: happiness
    beside its mood step's face, with the mood and thoughts on hover;
  - the live portrait on a people tile at the left;
  - the profession on its people tile (its tool on hover);
  - the activity on a moss tag, with a concern icon when one needs the player;
  - Follow (lit while the camera follows), Locate, and the bigger Character sheet.

  Character sheet opens the dwarf's character sheet (see "The character sheet" under
  the floating dock). Closing that window keeps the dwarf selected; selecting another
  dwarf keeps it open on the new dwarf. While Colony → Dwarves is open, the overview shows the dwarf instead, as
  before.
- **Style.** The panel is Deepdraft's own Hearthblock style (option A of doc 259; the
  owner chose it on 2026-10-23 to replace the Stonehearth-style format):
  - the hover card's dark hearth slab in voxel cells (4 px; 3 px below 1200 pixels
    across), with notched corners, a dark outline and a dark skirt;
  - a band across its top in the selected kind's family colour, holding the name and
    the badge. The name is never cut short: the panel grows with it, up to 900 px (600
    px on compact screens), and only longer names trim, whole on hover;
  - the badge on a pale stone chip, for the key number:
    - appeal, or the quantity of goods without appeal (a crate as "17 / 24", a stack as
      a count; a single good has no badge). The appeal's hover splits it into design and
      material, and packed goods read "Appeal when installed" (doc 118);
    - a ripe crop (fruit or berries) or a stone's clearing yield;
    - a floor plan's room appeal;
  - the object's picture on a tile in the family colour, like the dock's icons, and one
    flavour line (the description's first sentence; the full description shows on hover
    when it is longer):
    - furniture, goods, ladders, bridges, water stones and plans use their thumbnail
      or construction icon;
    - trees, plants, stones and wildlife show a live portrait of the object itself;
    - terrain has no picture;
  - the status on a tag in its tone: moss when fine, hay when waiting, rust when
    blocked. A tag holds its whole text up to the text column's width;
  - Hearthblock icon tiles. DEV actions sit on DEV tiles at the right edge and only
    show with the DEV switch on;
  - Assign owner opens a list of dwarf portraits, drawn like a hover card with the
    work family's colour behind its title.
- **No Details button (owner, 2026-10-23).** A Details tile was built, then removed:
  the owner judged that it repeated the panel. The panel carries the facts that matter
  on its band, badge, status and flavour. The explorer rows stay in the provider data
  for tests, but these facts are no longer on screen, so any can come back if play
  shows a need:
  - a bed's current sleeper, a hearth's own heat contribution, the game table's stool
    count and mood effect;
  - a plan's required item, footprint and wall mount level;
  - shrub harvest seasons;
  - wildlife appetite, rest, diet and plumage;
  - ladder sections and materials, and a bridge's crossing size and kit;
  - the construction worker, current block, stone on the way, delivery workers and work
    remaining.
- **Place.** Left of the dock and bottom-aligned when there is room (7680×2160);
  otherwise above the dock's left end. On narrow screens it slides left, or rises, only
  to clear the time controls and the slice tower or X-ray options while they are open.
  It does not stay clear of where they could open: that left it floating mid-screen at
  1280×720. Dock menus keep clear of it. The Orders shelf rises above it where neither side has
  room.
- **Layers and closing.** The panel shares the dock's layer 20; its owner list sits on
  the hover layer 30. Esc or a click on empty ground closes it, and selecting another
  object replaces it. Scrolling over the panel never zooms the world.
- **Family colours.** Each provider names its `family`, matching the dock menu where
  the player finds the thing:
  - settlement (terracotta) for furniture and its plans, goods, ladders, bridges and
    water stones;
  - work (blue) for trees, plants, stones, terrain, construction plans and wildlife;
  - people (teal) for dwarves.

  Missing or unknown families take the system colour.
- **Data.** Providers keep `get_explorer_data` and `perform_explorer_action`. Data
  has a `title`, a `family`, `rows`, `details` and `actions`, and optionally:
  - `picture` (a texture path);
  - `badge` {kind, value, tooltip};
  - `status` {text, tone};
  - `flavour`.
  Missing fields fall back to the Status row and the description's first sentence.
  The rows themselves stay in the data for tests; nothing shows them. The data has no
  `kind` label: only the retired window showed it.
  Actions may be marked `active` (the tile stays lit) or `primary` (a bigger tile).
  Bed owner options carry `dwarf_id`, so the owner list shows portraits.
  A dwarf's data says `presentation: "dwarf"` and adds `profession_icon`, a mood `badge` and
  its Follow and Locate actions; the explorer adds the Character sheet action itself.
  `portrait` names a world node the panel shows as a live still (`ObjectPortrait.gd`:
  copies of its visible meshes in their own world, rendered once). A `badge` may name
  its own `icon`, such as the fruit a tree is ready to give.
- **Action pictures** come from `data/ui/compact_panel.json`, owned by UIRegistry. An
  action may name its own `icon`. Actions with no picture keep their words on a tan
  button.
- **Style pieces** live in `UITheme`:
  - `cell_slab` (the voxel slab) and `cell_style`: plain tooltips, keycaps, the badge
    "chip" and the "tag_fine", "tag_waiting" and "tag_blocked" tags;
  - `TAG_TONES` and `tag_ink`;
  - `icon_tile_style` for the family tiles;
  - `display_font` (the names face, Fredoka) and `body_font` (the rows face, Nunito Bold).

  The tan button stays for an action with no picture. The olive band and blue tabs
  (`title_band_style`, `tab_style`) wait for windows to take a new look.
- **Type:** fonts shipped with the game, one face per role and one type scale (see
  "Type").
- **Implementation notes.**
  - The panel (`CompactObjectPanel.gd`), the hover card (`HoverCard.gd`) and the
    portraits (`ObjectPortrait.gd`, `DwarfPortrait.gd`) are preloaded scripts with no
    `class_name`. `ObjectExplorerController` hands the panel to the dock through its
    `dock_ui_path` export.
  - The panel is built once and updates in place on every refresh (0.15 s). Action
    tiles are rebuilt only when the actions change, and the text column keeps room for
    every flavour line, so the panel never jumps in size.
  - Godot passes mouse-wheel events through a control unless it accepts them, so the
    panel's frame accepts them; its frame stops clicks too.
  - Wrapped labels only know their height after layout, so the panel re-fits and the
    hover card re-places itself once more, deferred. The band's depth comes from
    minimum sizes instead, so the first drawing is already right.
  - A texture made in `_draw()` must be kept as a member: the canvas keeps only its RID,
    and a freed texture draws white.
  - Cell art is scaled to whole pixels per cell, and draws nearest whatever its control's
    filter (`UITheme.cell_texture`), so the cells stay crisp under the UI scale too.
  - Labels that trim with an ellipsis report no minimum width, so the name and the tags
    are sized to their text.
  - A portrait renders only once its viewport is inside the tree, so the owner list
    makes portraits after adding its rows.
  - `DockIconButton.key_text()` reads a key's own character: asking the display server
    for the keyboard layout fails in headless runs.

**Terrain faces (2026-10-12, 130):** bare walls, floors and ceilings are clickable.
The compact panel names the visible material, shows the kind of face and its level on
its status line ("Soil floor · level 35") and outlines the block. Slice caps and planned openings
keep ore/gems concealed: they name the authored strata, and a cap the slice cuts reads
"Slice surface" with "Excavate to reveal the material inside this slice." Mining and
discovered cave air show the real material on the faces they open. Ordinary object,
mining-zone and storage-zone inspectors take precedence; active tools keep their inputs.
Mining the block away, covering its face or slicing it out of view closes the panel.
Inspecting is read-only: it discovers nothing and adds nothing to the save.
- **Names** come from each block's `inspection` entry (`name`, `category`,
  `description`) in `data/terrain/terrain_blocks.json`, read through BlockRegistry; a
  block without one cannot be inspected. Built stone shows the rock it was laid as, and
  a built log its wood and the way it lies ("Pine log", "Upright oak log").
- Technical block diagnostics are under Development (doc 24, "Debug Overlay & Block
  Inspector").

**Wildlife (updated 2026-10-10):** rabbits, deer, wolves and ducks share the
compact panel, Locate and Follow. Ducks remain inspectable while swimming, on shore
and in flight; wakes/splashes do not enlarge their pick bounds. Hidden slice
levels hide birds and effects together; full-world view includes high flights.
Click a visible duck to inspect it or use Follow, including birds from later
flocks (doc 111; wildlife rules in [45](../40_economy_colony/45_wildlife.md)).

**Juniper berries (2026-10-09, 84):** tree Fruit/Fruit season rows now show juniper's
autumn crop, including too young, out of season, ready, worker progress and
picked states. **Harvest berries / Cancel harvest** keeps the tree standing.
**Orders → Harvest plants** accepts ripe junipers and shrubs in one rectangle;
live counts, Cancel orders, Undo and View work across both owners. Apple trees
(252) use the same rows and tools; their action is **Gather apples**, named by
`fruit_harvest.action_label`.

**Surface stones (2026-10-08):** the compact panel exposes Clear boulder / Cancel
clearing for boulders, Gather stones / Cancel gathering for walkable scree, plus
work status/progress and rough-stone yield. Projected markers identify active orders
(see World order markers below).
**Orders → Clear stones** supports single clicks and ground rectangles with a
live count. Cancel orders includes both categories alongside blocks and trees; Undo and
View are the tool bar's. Cancellation retains partial clearing work.
Click a visible boulder or loose-stone clump to inspect it without changing
its work state.
Dwarf inspection and the roster distinguish hand gathering, boulder breaking
and tree chopping.

**Window placement (2026-10-07):** a window stays inside the viewport; saved and dragged
positions are preserved. Selection outlines use the shared copper accent. The frame is
the Hearthblock slab with a family band (see "Window system").

Trees and furniture share `ObjectExplorerController`'s selection and the compact panel.
Tree data keeps Growth stage, Fruit, Fruit season, Felling yield and Felling status in
fixed rows, including N/A values.
The **Orders → Chop trees** command supports single clicks and ground rectangles
with a live tree count. Release commits the rectangle; Escape cancels the gesture
and exits the tool. The rectangle redraws every frame after camera movement, with
the tree count refreshed separately. The Orders group highlights its open menu;
the active tile and the tool bar indicate the selected mode.
Marked trees keep a mouse-transparent marker above their canopy, projected on a
CanvasLayer and hidden with sliced-out trees.

**World order markers (2026-10-23, 259):** every ordered tree, bush, flower, reed and
stone shows its order as a 36 px marker: the order's Hearthblock icon on the work
tile, the same picture as the Orders tool that marked it. A marker is projected UI on
layer 19, never a pick target.

| Order | Marker |
|---|---|
| Fell a tree | Chop trees |
| Harvest a fruit tree or a bush | Harvest plants |
| Clear a boulder or gather scree | Clear stones |
| Clear a bush, flower or reed | Clear plants |
| Uproot a bush or flower (the object panel's action) | Uproot: the bush lifted out with its roots, beside a brass arrow |

`data/ui/order_markers.json` (owned by `UIRegistry`) names each marker's picture and
the tile family; `scripts/ui/OrderMarker.gd` draws it.
The explorer offers Fell tree / Cancel felling. Forestry zones and stump
clearing are planned and have no command yet (tracked in
[00_todo](../00_dev_roadmap/00_todo.md)).
Furniture retains its own status, storage information and actions in the same
window.

**Dwarf inspection (2026-10-05):** visible dwarves now use the same selection
system. Their character sheet shows a portrait of the actual dwarf, live
activity/destination, rest, exact cargo and carry load, plus Locate and Follow. Its
Traits tab gives each trait's name and description and labels trait effects as
inactive; Light Sleeper's authored seven-hour sleep duration is not yet a runtime
modifier. The tab body scrolls at smaller resolutions while actions remain visible.

**Shared Hearth & iron theme (2026-10-05, stage 2):** all current UI surfaces now
use `UITheme`: charcoal panels, copper accents, warm text, the shipped faces and compact
corners. Standard windows, object explorers, dock menus, independent storage/mining/
room/furniture panels, debug windows, tooltips and toasts share these definitions.
Danger actions retain red text; developer actions use warm orange.

**Worker crafting (2026-10-07):** the Craft cabinet presents Worker recipes,
live timber/finished stock and a stable make/maintain order queue. Allowed-wood
checklists default to Pine and can be changed per recipe draft or existing order;
empty choices never mean all wood. The cabinet also opens from the installed
crafting stump's explorer action. Dwarf inspection shows the actual crafting
spot or stump stand, not the scheduler's placeholder coordinates. While a batch's
ingredients are gathered, the activity names the one carried or set down ("Carrying
Rough Stone"); "Crafting log torch" begins once all have arrived. Recipes and
professions are in [44 — Crafting Workshops](../40_economy_colony/44_crafting_workshops.md).

**Grouped navigation (updated 2026-10-12; Hearthblock icons since 259):** eleven pictured
entries with hover names replace the labeled copper line icons. Orders, Zones, Rooms,
Construction, Place, Craft, Colony, Inventory, Events, Menu and Development
sit along the bottom, with the Appeal, X-ray and Slice toggles as the last group.
The Sky Dial shows calendar/weather at the upper right. Menus keep clear of the compact
panel (see "Floating Dock"). All
object inspectors now start on the right; existing saved or dragged positions take
precedence.

**The Place window** (`FurniturePlacePanel.gd`, settlement family) has the crafting
window's shape:
- **Designs.** Every category in `data/ui/place_catalog.json` is open at once as a
  group of the picture grid, headed by its name in the display face. There are no
  category pictures. Each design sits on the settlement tile with how many are ready to
  place; one with none ready is dimmed and shows no count. Ready includes goods that
  storage hauling has reserved, is carrying or is moving between storage areas;
  browsing leaves the haul alone, and confirming a placement takes the item over
  (doc 31, "Placement over storage hauling"). Its name, ready count and
  count on its way show on hover. Only owned designs show until Show all designs (a
  toggle, the family block while on) lists every one.
- **The board.** The chosen design's board, on the pine board, shows:
  - its picture;
  - its facts as stone chips (footprint, wall mounted, seats, planting area);
  - its appeal once installed: the chosen wood's, or the range across its woods;
  - its description and its placement note;
  - its wood as pictures with counts: Any first, the chosen one ringed. A click sets the
    wood to place;
  - three numbers with words: ready to place, on their way (planned placements awaiting
    delivery) and being crafted (the Worker crafting queue).
- **Actions.** Place item (the family block) under the board, with a line on how to get
  the design when none is ready. While placing, the tool bar has the keys, the stock, the
  ghost's hint, Undo and Done (see "The tool bar").
- **Placing.** Clicking an available picture starts its placement preview, and the
  window stays open while placing. Re-clicking the active design keeps its rotation.
  The tool bar's Undo, or Ctrl + Z, takes back unfinished requests, and placing stops when
  stock runs out. Starter
  production lives in Craft; Place shows its real queued count and installs the finished
  items. A design with `placement_anchor: "center"` (the campfire) centres its footprint
  on the cursor's tile, and `show_placement_area` outlines the whole footprint, tinted by
  validity, on the cursor and the queued plan; the saved origin stays the footprint's
  minimum corner (doc 100).
- **Stable browsing.** Stock updates restyle the tiles in place, so their positions,
  focus and scroll hold while goods are hauled. A design that runs out stays shown until
  the window reopens. One that arrives while the window is open waits in a New group at
  the end, and reopening sorts it into its category.
- **Sizes.** They go by screen height, as crafting's do (1510 × 1042 at 7680×2160). The
  window is as tall as the tallest design's board needs, so it never changes size from
  one design to the next, as far as the room above the dock allows. Small screens drop
  the description and the wood names (hover names them), and a board that cannot show
  whole scrolls.

### Dining seat placement

Tables declare their seat slots in JSON under `seating`: a `chair_key`, a
`snap_radius`, a `max_chairs` limit and a list of `slots`, each with a
footprint-local `chair_origin` and an inward quarter-turn `yaw`. The Log Dining
Table has four slots, one against the middle of each side, so table and stools fill
5 × 5 (`max_chairs: 4`); the Board-game Table has two opposite slots
(`max_chairs: 2`). Both use the Log Stool. All four table rotations transform the
whole chair rectangle, so every slot stays on whole grid cells
(`FurnitureSeating.slots_for_layout`).

- Selecting a chair near a placed or planned table shows translucent guides at
  its free slots: green where the chair fits, red where it is blocked. A slot
  that already holds a matching chair shows that chair instead of a guide.
- Within `snap_radius` of a slot the cursor ghost snaps to it and faces inward;
  R still rotates a free-standing chair. Slots are optional, and chairs can still
  be placed anywhere else.
- `max_chairs` counts planned and installed chairs together. A full table stops
  showing its other guides, and aiming at one explains the limit. A chair marked
  for uninstall keeps its slot until it is removed. The same limit applies when a
  table is placed around chairs that already exist.
- A chair's `seating_chair` data supplies its seated head, hair and limb
  clearance regions (a table's `chair_profile` can refine them for its own
  slots) and its approach tiles (`access_cells`). Placement rejects terrain,
  furniture or another seat's clearance inside that space, and needs at least one
  approach tile that is walkable (three air blocks above a floor) and free of
  planned furniture. Other furniture placed later also respects an existing
  chair's head space. Head and hair regions are cylinders (`"shape": "cylinder"`; the
  stool's head radius is 1.375 blocks), so the four stools around a campfire or table,
  two tiles apart diagonally, fit where boxes would overlap, and heads still never do.
- A table's `chair_profile` applies only to a stool standing exactly in one of its
  slots (same origin and facing) of an installed or planned table. Both tables have
  one: it raises the resting hands and the beard region clear of the tabletop, lifts
  the hands for meals (`meal_hand_lift`) and keeps the stool facing the table
  (`face_nearby_fire: false`), where a free-standing stool turns toward a nearby fire.
  It is worked out at runtime (`FurnitureSeating.chair_definition`), never written
  into the shared stool definition or saved, and cached per piece until furniture
  changes (doc 232).
- A table's `seating_obstacles` give its solid parts for testing seat clearance,
  rather than its whole footprint: for the Log Dining Table the central base and the
  slab, the same boxes as its collision (doc 231). Any piece may list them; without them
  a seat tests the piece's whole model bounds. The campfire lists its low stone ring and
  its narrower flames, so stools fit on the four tiles just outside its 3 × 3 area
  (doc 100).
- Before a dwarf consumes the packed item to build a chair, clearance, floor and
  approach are checked again.
- Planned chairs reserve placement space but do not block navigation; only an
  installed piece changes the NavGrid.
- Table-chair links are derived from exact origin, key and facing
  (`FurniturePlacementController.get_dining_seats()`). No cross-object ids are
  saved. Uninstalling a table leaves its chairs in place; uninstalling a chair
  frees only that slot.

Seat spacing must allow for seated heads, not the 1-block logical footprint: a
dwarf head is about 2.125 blocks wide (2.375 with side braids), so occupied
chairs on adjacent cells overlap.

**Plants in Place (2026-10-08):** the Plants category lists whole uprooted
blueberry, elderberry and wild-strawberry bushes with species thumbnails and
real Available/Reserved counts. **Replant shrub** starts the normal ground
preview. Cuttings cannot satisfy it. Individual shrub inspectors offer **Move**
to choose a destination before uprooting, or **Uproot** for storage and later
placement, alongside Harvest/Clear. Cancelling a placed Move request also cancels
unfinished uprooting; an already lifted plant stays intact.

**Cuttings in Place (2026-10-08, 80):** Plants also has three cutting entries with
young-model thumbnails, separate stock counts and **Plant cutting**. The detail
area explains one-cutting cost, growth days and winter dormancy. Young shrub
inspectors show growth percentage/remaining days and **DEV: Grow to maturity**;
Move/Uproot and berries are enabled only at maturity.

**Zone window movement (2026-10-05 follow-up):** Mining Zone and Storage Zone now
register context windows with `UIWindowManager`. Drag their title bars to move them;
positions are remembered in `user://ui_layout.json` across reopening and game
restarts. They stay closed on startup until a zone is selected. Live mining counts
refresh without bringing the panel to the front. Closing clears the inspected zone,
and removing a selected zone also closes its window. With a dock, mining's instructions
are the tool bar's.

**Tool shelves (updated 2026-10-12):** Orders opens its six tools, and Zones opens
Storage beside the planned Farming and Animal pasture (see "Navigation Groups"). Both
are `OrdersShelf`, placed as the dock's menus are (see "Floating Dock"), with an extra
gap before Cancel orders.
Selecting a tool starts it directly and keeps its shelf open; clicking the active tool's
tile again keeps it as it is, brush and size included. Switching groups
ends the active tool; closing its shelf retains the tool and its group highlight. Esc
drops a drag in progress and ends the active tool, and a second Esc closes the shelf.
The tool bar sits above the shelf (or the dock when it is closed), with the live
selection's tag, Done · Esc and Undo; its last order offers View through the existing
inspectors (see "The tool bar"). Cancel orders is a tool like the others, never a close
button or a cancel-all: it cancels the unfinished marked work its click or drag covers
(blocks, trees, stones and plants) and keeps partial progress. Undo cancels the newest
order's remaining work without recreating completed terrain.

**Colony Inventory** (`ColonyInventoryPanel.gd`, settlement family) opens directly
from the dock in the Place window's shape and sizes:
- **Goods.** Every category in `data/ui/inventory_catalog.json` is open at once as a
  group of the picture grid, headed by its name in the display face. There are no
  category pictures. A good joins the first category whose tags it carries, else Other;
  furniture takes its Place label, picture and group (`furniture_categories`). Each good
  sits on the settlement tile with how many the colony holds. A good that runs out is
  dimmed and shows no count. Its name and total show on hover.
- **The board.** The chosen good's board, on the pine board, shows:
  - its picture;
  - two stone chips: how many are in the colony, and its group;
  - its description;
  - what it is made of, as material pictures with counts, when it comes in more than one
    material (furniture of different woods);
  - where it is, each number with its word: stored, loose, carried, equipped; then
    available, reserved and disallowed. The Total is Stored + Loose + Carried + Equipped.
    Reserved is a subset, and Available excludes goods assigned to hauling or placement.
    Furniture is the exception: its Available is Place's ready count
    (`get_catalog_stock()`), so goods on their way to storage stay available.
    Crates count their contents.
- **Actions.** Locate (the family block) and Inspect storage sit under the board. Both
  resolve current owners when clicked. Furniture stays counted here; furnishing happens
  through Place.
- **Stable browsing.** The list holds still while the window is open, as Place's does:
  goods that run out keep their tile until it reopens, and goods that arrive wait in a
  New group at the end.
- **Sizes.** The board's spacing and picture shrink on smaller screens, as it holds more
  than Place's; small screens drop the description and the material names. Developer
  spawn controls live in Development.

**Colony Dwarves (updated 2026-10-06):** Colony → Dwarves opens a wider movable
overview with a compact roster on the right and the shared dwarf details on the
left. Actual portraits, activity/cargo, rest, live workforce filters and name
search remain; rows keep their positions during updates. Selection uses the same
world controller and shows the dwarf on the Details card (see "Colony Dwarves" under
the floating dock). The two columns scroll independently. Escape closes the
combined overview; ordinary world inspection resumes after closing. This pass
initially added no labor controls; milestone 96 adds Work and Profession views. Developer tools remain in Development → DEV: Dwarf
tools.

## Window system

Controllers own what is inside a window; `UIWindowManager` owns the chrome. Three
scripts in `scripts/ui/` share the work:

- `UITheme.gd` is the static owner of the visual language. It is the only script that
  builds a `StyleBoxFlat`; everything else asks it for styles, buttons and fonts.
- `UIWindow.gd` (`extends PanelContainer`) is the standard window: a title bar that is
  the drag surface, a close button and a content slot. Only the manager constructs one.
- `UIWindowManager.gd` (`extends CanvasLayer`, a scene node in `debug_world.tscn`) hosts
  every window. A system builds a plain content `Control`, calls
  `register_window(id, title, emoji, content, opts)` and keeps the returned window to
  update its content. `open` / `close` / `toggle` / `is_open` drive it, and one
  `window_state_changed(id, open)` signal tells the dock what is open.

**The frame (Hearthblock).** Every window is the voxel slab from
`UITheme.window_frame(family)`:
- **Band.** A 12-cell (48 px) title band in the window's family colour, lit along its
  top with a dark seam under it. The title sits on it in the display face (26 px, outlined)
  with a 36 px stone keycap ✕. The title bar is exactly the band, so the body starts under
  the seam.
- **Family.** `register_window()` takes `"family"`: `people` (character sheet, Colony
  Dwarves, Professions, Events, Colony's page, the founding card, Trade), `work` (storage,
  mining zones), `settlement` (rooms,
  crafting, Place, Inventory), `system` (Audio) or `dev` (every DEV window). A window
  registered without one logs an error.
- **Family theme.** The window carries `UITheme.family_theme(family)`, and its contents
  inherit it, so they set no theme of their own: `apply_surface()` inside a window leaves
  the control to inherit, and `make_button()`, `apply_hearth_button()` and
  `hearth_progress()` set none. Surfaces outside the windows keep `shared_theme()`.
- **Body.** The frame keeps content off its outline (4 px at the sides) and its skirt
  (12 px at the bottom), so scrolled content never covers them. `"flush": true` drops the
  body's own margins for content that brings its own.
- **Pieces,** drawn in cell art:
  - buttons are raised blocks;
  - the shown tab (`UITheme.show_tab()`), the main action (`apply_catalog_primary()`) and a
    toggled button are the family block, in the display face; outside the windows the
    main action stays a hay block and a toggle keeps a hay edge;
  - a list row (a dwarf in Colony Dwarves) takes a hay edge when selected;
  - every picture sits on the family tile (`apply_picture_tile()` for a picture button,
    `framed_picture()` for a picture), with a hay rim when selected;
  - recessed insets for content cards, the pale pine board for light cards with dark ink,
    and cell grooves for fields, bars and scroll bars;
  - a slider (the Settings page's, `SettingsPanel.gd`) is the "groove" cell style with the
    "fill" style for its hay, their content margins opened to the track's thickness, and a
    stone keycap knob (`UITheme.cell_slab()`), lighter while hovered or dragged;
  - names and headings use the display face (`apply_heading()`). The HUD's title face
    (`apply_title()`) is for the HUD only: the Sky Dial, the time controls, the dock's
    menus and the Orders shelf (see "Type").
- **Picture grid.** `scripts/ui/PictureGrid.gd` (no `class_name`; preload it) is the one
  grouped picture grid: storage's Filter and Contents, crafting's recipes, the room's
  furniture, Place's designs and woods, and Inventory's goods and materials.
  - `show_groups()` takes plain data: groups with a title and an optional All, Some or
    None state, and items with a picture (or a word, `text`, such as Place's Any wood),
    count, mark (✓ − ! ✕), dim, selected, hidden, tooltip and caption. Headings sit above
    the tiles, beside them (`heading_beside`) or nowhere; `heading_display` sets the ones
    above in the display face, as written (Place). A group whose items are all hidden
    hides with them.
  - Pictures sit on the window's family tile, with a hay ring on the selected one and the
    name on hover. `board` gives captions the pine board's dark ink. `set_tile_size()`,
    `gap`, `caption_size`, `heading_size` and `state_size` size it.
  - An unchanged refresh keeps its nodes. One that changes only looks (counts, marks,
    dimming, the ring, hover text, pictures or hiding) restyles the same tiles, so focus,
    hover and scroll stay put while stock moves. A rebuild (other groups or items) gives
    keyboard focus back to the tile with the same id.
  - `item_pressed`, `group_pressed` and `caption_pressed` arrive once the click is over,
    so an owner may rebuild the grid in answer without the click's release falling
    through to the world. A test that clicks a tile waits a frame before checking what
    the click did.
  - A mark stands above its tile (`MARK_RISE`). A first row with no heading above it
    leaves that room, so a scroll never cuts the mark off.
  - A captioned row lets each name use its tile's gap, so names wrap between words and
    tiles stay square.

Rules:

- Windows are hand-rolled `PanelContainer`s, never Godot native `Window` nodes.
- **Persistent** windows (`"persistent": true`, for example Trade and DEV Time & weather)
  reopen at startup if they were open when the game closed. **Context** windows (the
  default: zones, object explorers, rooms, catalogs) exist for their subject and never
  restore open; they close themselves when that subject disappears.
- Close hides the window and never frees it, so its content and position survive a
  reopen.
- A window is always sized to its contents' minimum: owners set minimum sizes, never
  `size`. Wrapped text measures against no width while a window is hidden, so `open()`
  shrinks the window to its contents again after its first layout.
- Dragging, opening and viewport resizes clamp the window so its title bar never leaves
  the viewport (the whole body when the window sets `keep_body_on_screen`). Windows also
  step aside from the Sky Dial when they fit.
- A mouse-down anywhere in a window brings it to the front: last click wins.
- Placement is the remembered position, else the window's `default_pos`, else a cascade.
- Layout lives in `user://ui_layout.json` (position and open state per window id).
  `UIWindowManager` is its only reader and writer. It is a player preference, kept out
  of the save file, so it survives every save, load and new game. A corrupt file falls
  back to defaults with a warning.
- Windows stop the mouse events they receive, so clicking or dragging a window never
  designates, selects or places anything in the world underneath.
- **A window's panel** (crafting, Place, Inventory, Events, the character sheet, Colony
  Dwarves, storage, the room) is a `MarginContainer` that brings its own margins,
  registered `"flush"`. It keeps its owner's API, so the systems that open it never change
  with its layout:
  - crafting: `bind_controller()`, `select_section()`, `select_recipe()`, `refresh()`,
    `fit_above_dock()` and `place_requested`;
  - Place: `bind_controller()`, `begin_browsing()`, `refresh()`, `fit_above_dock()`,
    `set_all_toggle()`, `selected_key`, `show_all` and `place_requested`;
  - Inventory: `bind_controller()`, `begin_browsing()`, `refresh()`, `fit_above_dock()`,
    `selected_key` and `locate_requested`;
  - the character sheet and Colony Dwarves' Details card: the explorer's host API,
    `show_data()`, `clear_subject()` and `action_requested`;
  - storage: `show_storage()`, `clear_subject()`, `info_label` and `action_requested`;
  - the room: `show_room()`;
  - Events: `begin_viewing()`, `refresh()`, `fit_above_dock()` and `locate_requested`.
- **Sizes** are a `SIZES` table per panel, chosen by screen height: large from 1300 px (the
  approved concept's sizes on the 7680×2160 screen), small below 650 px, and for Colony
  Dwarves short below 900 px. The body keeps one height from tab to tab, as far as the
  room above the dock (`DockUI.dock_top()`) allows, and longer pages scroll.

Layout pitfalls met building these windows:
- Wrapped text and picture rows report their height only after a layout pass.
  `UITheme.lay_out_now()` lays a tree out at once; crafting measures every recipe's board
  this way.
- A label that autowraps inside an `HBoxContainer` wraps letter by letter. Give one-line
  names and headings `AUTOWRAP_OFF`.
- A `clip_text` label has no minimum width, so it can vanish. Give it `SIZE_EXPAND_FILL`
  or a minimum width.
- Freeing a button inside its own `pressed` signal lets the click's release reach the
  world. Answer after the click (`call_deferred`), as the picture grid does.
- `set_anchors_preset()` on a control already in the tree keeps its current rect, so a
  control that starts at zero size stays there. `set_anchors_and_offsets_preset()` resets
  the offsets to the preset (the toast stack).
- A script a test preloads as a constant compiles before the autoloads are global names.
  If it names an autoload, the test loads it at runtime instead (`ToastStack`), or the
  script fetches the autoload from the tree (`DockIconButton`).

Canvas layers: dwarf concern badges 19, dock with the Appeal, X-ray and Slice toggles and
the compact object panel 20, the Sky Dial with the time controls, the slice tower, the
X-ray options and the Appeal view's scale 21, all windows and the Appeal view's room card 22 (ordered by child order within the
layer), dock menus 23, toasts 24, hover tooltips and the compact panel's owner list 30,
loading screen 128. Windows sit above the dock and the status layer;
ordinary windows make room for the dial and the time controls under it.

Three DEV or fixture surfaces still build their own chrome outside the manager: the
block inspector (`scripts/components/BlockInspector.gd`), the World Build overlay
(`DebugLoadingOverlay.gd`), and the compact furniture window in
`scripts/components/FurnitureWindow.gd`, used in art fixtures that have no object
explorer and when a click during active furniture placement lands on an existing piece.

## Stockpile Display Readouts (planned)

Resource counters below are a future design. The Sky Dial shows the live calendar
and weather; pause and speed hang under it, and Appeal, X-ray and Slice end the dock.

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

The bottom-centered **floating dock** is a Hearth & iron bar on a `CanvasLayer`.
Its eleven entries show Hearthblock icons (`assets/ui/icons/`, doc 259), with names
on hover or keyboard focus. Each icon sits on a notched tile in its command family's
colour (`data/ui/icon_families.json`; work, settlement, people, system), drawn by
`UITheme.icon_tile_style`: hover lightens the tile, and planned or disabled entries dim
it. The menus use Hearthblock icons on their dock button's tile too: Orders, Zones and
Construction on the work tile, Crafters on the settlement tile, and Colony's page entries on
the people tile. The family colours are the only family mark. A pattern per family was
drawn and skipped (owner, 2026-10-26, 272): zone pictures on a dotted boundary in their
world colour, and Construction's on a blueprint outline. The colours already group the
commands, and the Orders pictures already match their markers in the world. Development keeps the illustrated atlas art; Menu opens the game menu
directly, and Colony and Events their own pages. Place
and Inventory have no category pictures, as their categories are their group headings. An open group stays highlighted, including while a submenu is
open. Only one action menu opens at a time; a second click or Escape closes it,
and submenus have a Back button. Active tools retain their existing Escape handling.

**Sizes, states and menus** (`DockUI`, `DockIconButton`, `OrdersShelf`):
- **The dock's icons** are square and one size: 72 px from 1200 px across, 56 px below,
  shrinking further only when the row would not fit. A 12 px gap parts the groups:
  before Menu, before Development and before the views.
- **A state never rests on colour alone.** The open or active command has a copper frame
  with a solid notch at its foot; hover and focus draw a thin light frame. A group also
  stays lit while one of its tools is active (Orders, Zones, Construction).
- **Menus** (Construction, Crafters, Development) and the Orders and Zones
  shelf rise 8 px above the dock, starting at their dock button, joined to it by a short
  copper line. Their icons are 64 px, 56 px below 1200 px across, with no title bar; a
  child row (a menu with a `parent`; none at present) has a Back arrow at its left. A menu
  is sized to show all its rows and never scrolls, so it keeps no room for a scrollbar and
  its icons sit evenly inside it. Beside the compact panel they wrap
  into more rows before any icon shrinks and move to its nearer side; the shelf rises
  above it where neither side has room. Choosing a tool closes a menu, while the shelf
  stays open.
- **Availability** has three looks, for the dock, its menus and the shelf:
  - live: full colour, and the entry does its work;
  - planned: dimmed, with a lock badge. It keeps keyboard focus, and hover, focus, a
    click or Enter shows its hover card with the status on its tag. It never starts a
    tool or changes the active one (Farming, Animal pasture). An entry whose destination
    is an informational preview still opens it: Craft's planned catalogs ("Catalog
    preview"), and Trade on Colony's page, marked by a Planned tag;
  - DEV preview: full colour with a flask badge, and the entry works (no entry uses it
    at present).

  The status tells what the destination can do today, not the whole profession: Miner
  is playable though its catalog is a preview.

**Hover cards (2026-10-23; Deepdraft's own style, option C of 259).**
Every icon button shows a hover card on hover or keyboard focus
(`scripts/ui/HoverCard.gd`). That covers the dock, its menus, the Orders shelf, the
time and view controls and the compact panel's tiles; the Sky Dial's details use the
same card. The owner asked for Deepdraft's own Hearthblock style instead of a copy of
Stonehearth's black card, and chose the family tile card.
- **The card** is a dark hearth slab drawn in voxel cells, following doc 64's shape
  rules. The cells are 4 px, or 3 px below 1200 pixels across. It has:
  - notched corners, a dark outline, a lit top and a dark skirt, like the dock tiles;
  - a top in the family colour of the button it explains (work, settlement, people,
    system or DEV), lit along its top edge with a dark seam under it. The Sky Dial's
    card wears the system colour. A card without a family keeps a plain lit top;
  - the name in white with a dark outline, in the names face (see "Type");
  - the keys that trigger the command, each on a pale stone keycap: "Ctrl + ]" shows
    two keycaps joined by a plus;
  - a planned or preview status on a hay tag, or what the button's count counts, on a
    tag in the count's tone (see "Counts");
  - the explanation in light text;
  - a stepped pointer at the button. It sits above the button, below it when there is
    no room above, or left of the Sky Dial.
- **Showing.** A card shows 0.3 s after the pointer or the focus arrives, on the hover
  layer (30); it lets the mouse through, so it never takes a click. A click hides it until
  the pointer comes back
  (a planned entry's click shows it instead), and leaving, losing focus, hiding or a
  resize hide it too (`DockIconButton`).
- **Keys.** A button's data entry names its input action in `key_action`, and the card
  reads the key from the input map, so a rebound key shows correctly. The time, view and
  slice controls carry them (`data/ui/time_slice.json`); see "Keys".
- **Plain tooltips.** Every plain tooltip is the same hearth slab, without a pointer,
  with light text. The shared theme (`UITheme.shared_theme()`) carries it as a nine-slice
  `UITheme.cell_style("card", …)`, so every window matches the dock: rooms, storage,
  DEV tools and the character sheet included.

**Counts (2026-10-26, 272).** Three
dock buttons count what waits on the player. The count is a tag on the tile's top right
corner (`DockIconButton.show_count()`), and its hover card names it on its tag.
- **Colony** counts, in hay, the dwarves Colony Dwarves files under Idle
  (`scripts/ui/DockCounts.gd`).
  - A dwarf counts once it has been idle for five game minutes (five seconds at 1×), so a
    dwarf between two jobs never changes the count.
  - A paused game holds it.
  - Its card says "4 dwarves are idle".
- **Place** counts, in moss, everything Place lists as ready to place: furniture, plants
  and water stones. Designs that share an item count it once. Its card says "6 items are
  ready to place".
- **Events** counts the entries not yet seen (see "The bell").
- **For all three:**
  - Colony refreshes once a second, asking each dwarf only for its group
    (`DwarfInspection.roster_group()`). Place refreshes every five seconds, as its stock
    is costlier to add up. The bell follows the event log.
  - A count shows only when it isn't zero.
  - A count never moves a tile.

**Craft** opens a Crafters submenu of profession icon buttons above the dock,
not a recipe window or profession dropdown. Each button shows its profession's
Hearthblock icon on the settlement tile; Rudimentary shows the Worker's. Selecting Rudimentary, Carpenter,
Stonemason, Blacksmith or another entry opens that profession's titled crafting
menu. Planned entries remain browsable previews without craft/place actions; how they
look and why they still open is under Availability in "Sizes, states and menus"
(owner-approved plan, 2026-10-12).
The submenu uses one desktop row and balanced compact rows; its open state
keeps Craft highlighted. Orders shown belong to the selected section, while
switching menus preserves the actual production queue and chosen Worker recipe.

**The crafting window** is built around the item and its ingredients:
- **Header.** The profession on the people tile ("Rudimentary · Worker") and the
  Crafters row: a tile per profession, lit when it can craft today, the shown one ringed
  in hay. It switches professions without leaving the window.
- **Recipes.** One grouped picture grid with a search field. The groups are the
  recipes' `category` values, so a recipe added anywhere in `worker_crafting.json` joins
  its group. Search matches names and categories, ignoring case; empty groups hide, the
  first match is chosen, and with no match nothing can be queued. A recipe link clears a
  search that would hide it (doc 114). A recipe that could not
  start now is dimmed with a hay "!", and its tooltip says why: no allowed wood in stock,
  a missing material, or no free workbench (`CraftingManager.recipe_waiting_reason()`).
  The chosen recipe is ringed in hay.
- **The board.** The chosen recipe on the pine board:
  - its name, its picture, and badges for the work time (a brass clock), the yield and the
    appeal (a range when the allowed woods differ);
  - its ingredients as pictures: every wood the recipe takes with its stock, ticked when
    allowed (click one to allow or stop it), then fixed materials such as Rough Stone;
  - its description and purpose (`purpose_short` on small screens, where a recipe has
    one), and its flavour line (`flavour` in
    `worker_crafting.json`). A recipe's `purpose` never repeats its description;
    `CraftingBrowserTest` checks every board gives it once;
  - tags for what it needs: the workshop, and Any Worker.
- **Orders.** Make ‹ n › now or Keep ‹ n › in stock, and one Queue button in the family
  block. Place · n ready opens placement for finished furniture; other goods say how many
  the stores hold.
- **Queue.** Always in view beside the board. Each order shows its picture, its count
  ("Log torch ×4", or "= 4" for a stock target), its status on a tag in its tone, its
  wood checklist, and pause, move and cancel. The search never filters it.
- **Sizes.** Large from 1300 px tall (the 7680×2160 screen), small below 650 px. Below
  1200 px across, or on small screens, the queue folds into an Orders tab under the
  recipes, and on small screens Make and Keep drop their trailing words. The window is
  as tall as the tallest recipe's board needs, as far as the room above the dock allows,
  so it keeps one height while browsing and no board scrolls at 1920×1080 and up. On
  shorter screens the board scrolls, and the Queue button never scrolls out of view.

**The character sheet** opens from the compact panel's Character sheet
button, or from Colony Dwarves' Details card. `DwarfInspectorPanel.gd` reads
`DwarfInspection.describe()`.
- **Header.**
  - The live portrait on the people tile, and the name.
  - The profession on its tile with its level, the experience bar and the way to the next
    level. Only the Miner earns experience today; the other professions say their levels
    are planned.
  - The traits as tags: moss for good ones, rust for bad ones, the description on hover.
  - The mood banner at the right: the step's face, its word and the happiness.
- **Tabs:** Overview, Mood, Traits, Equipment, Profession and Tastes (on small screens two
  rows of three).
  - Overview gives what the dwarf is doing and where they are heading, Rest and Food
    with the pictures from over their head, what they carry as pictures with counts, and
    the latest two thoughts. The concept's day's work line is left out on purpose, to
    keep the sheet lean (owner, 2026-10-23).
  - Mood shows each thought as a card with its hours left and value: what weighs on them
    on the left, what lifts their spirits on the right, strongest first. Under the cards
    are the face, word and line, and the five-step scale with a marker.
  - Traits describes each trait. Equipment is the tool view.
  - Profession gives the level and its rewards, and Change profession opens the career
    map.
  - Tastes (2026-10-25, doc 41 "Tastes"):
    - a line on how tastes are found;
    - LOVES, LIKES and DISLIKES (rust) rows of tiles, each with the thing's picture and
      name once found, or "?" and "Not found yet" (the hover says they have not used it);
    - OWN BEDROOM: "Birna's bedroom is Plain 4.5. Birna loves the log bed, so to them it is
      Pleasant 8.5.", over the appeal scale with a hay mark where it feels to them, or
      "No bedroom of their own yet."

    It is worked out only while the tab shows (`DwarfInspection.tastes_sheet`).
- **Footer.** Locate, and Follow as the main action.
- **Mood.** The five steps are Miserable, Unhappy, Content, Happy and Joyful, the `steps`
  in the `mood` section of `task_config.json`. The face over a dwarf's head shows when the
  dwarf is Unhappy or Miserable.
- **Sizes.** The sizes go by screen height, as crafting's do: large from 1300 px (780 px
  across, as the concept) and small below 650 px. The tab body is as tall as its size
  allows, as far as the room above the dock allows. The window keeps one height from tab
  to tab, and longer pages scroll.

**Colony Dwarves (after Stonehearth's Citizens)** is a table of every dwarf, with
the Details card for the selected one at its left (`DwarfRosterPanel.gd`,
`DwarfDetailsCard.gd`).
- **The rows** carry everything live. The Work view swaps the activity, rest and Locate
  for the work checkboxes; the mood stays.
  - The portrait, with the profession's picture on its own tile beside it, at the
    portrait's size (doc 272).
  - The name and the profession. Under the profession, a thin bar shows the way to the
    next level where the profession earns levels, the Miner today. Every row keeps the
    bar's room, so names line up whatever the profession, and the row's hover gives the
    way to the next level.
  - The Mood column: the step's face and word.
  - What the dwarf is doing and carrying, rest, and Locate.
- **The Details card:**
  - who the dwarf is: the portrait, name, profession with its level and bar, and the
    traits as tags;
  - its buttons: Character sheet (the main action), Change profession, Crafting while the
    profession has recipes today, and Follow.
- **The sheet from the card.** Character sheet opens the sheet's window beside Colony
  Dwarves. An open sheet follows the roster's selection, and Escape closes it before
  Colony Dwarves.
- **Sizes** go by screen height:
  - large from 1300 px, up to 1688×1180;
  - short below 900 px, where the card sets the portrait beside the name;
  - small below 650 px.

  Narrow screens trim the card and the name column, and move the Work view's per-row note
  into the row's hover.

**Colony's page** (`SettlementPanel.gd`) is what Colony on the dock opens: the settlement
at a glance, a window in the people family opening where windows open. Colony stays lit
while it is open, and opens no menu. The owner chose this layout, the rows beside the
journal, over one column with the journal under the rows (2026-10-25).
- **The header.**
  - The flag's picture on the people tile, and the settlement's name with Rename.
  - "Founded Autumn, day 1, year 1 · 5 dwarves".
  - A badge for each profession the colony has, in `professions.json`'s order: its icon
    and "3 Workers". Small screens show the count alone, with the words on hover.
  - At the right, the colony's mood: the face for the dwarves' average happiness step, the
    word in its tone (rust for Miserable and Unhappy, hay for Content, moss above), the
    step's line and "Happiness 58 of 100".
- **Colony's entries** (`dock.json`'s `colony`): Dwarves, Labor, Settlement flag, and
  Trade, dimmed with a hay Planned tag. Each closes the page and opens its own window or
  view.
  - **Settlement flag** goes to the flag wherever it is
    (`FurniturePlacementController.get_catalog_location()`, a query that never makes or
    moves anything). An installed flag, or its placement or move order, is located and
    selected, with a toast when it is being moved, packed or awaits installation; one the
    slice hides is located with a toast to change the slice. A packed flag opens Place
    with the flag chosen, and a carried one says it reaches Place after delivery. It never
    founds again or grants a second flag (doc 140).
- **At a glance.** Five rows, each with its picture, what it counts and its value in words.
  The last four fill a meter toward their goal, with the goal beside the value, in the tag
  tones: moss when met, hay below, rust when short.
  - Dwarves: how many, and a tag for each group Colony Dwarves sorts them into (working,
    resting, idle), with the names on hover.
  - Food: days of food at today's appetite, the edible goods' nutrition (Inventory's
    totals) against what the dwarves eat in a day. Goal 10 days: Short (rust) under 3, Low
    (hay) under 10, then Plenty.
  - Beds: dwarves who sleep in their own bedroom (a room with an owner). Goal: one each.
  - Storage: cells used of all storage, and the items stored. Room to spare under 80%,
    then Filling up, then Full. Without storage it reads "No storage yet".
  - Happiness: the step and points, the meter marked where the steps change, and the main
    complaint (the bad thought most dwarves share), with how many and what helps: "Main
    complaint: chilly sleep, 4 dwarves. Warm the sleeping room with a hearth."
  - The goals, where the tones turn and each row's picture live in
    `data/ui/settlement_page.json` (UIRegistry).
- **The journal** stands beside the rows, as tall as they are, and only it scrolls:
  "Journal · What your dwarves said, newest first." It reads `ColonyJournal`.
  - The days, newest first: "Today · Autumn, day 8", "Yesterday · Autumn, day 7", then
    "Autumn, day 6". Ten days are kept.
  - Each day lists its Complaints (rust), then its Praises (moss), the most shared first.
  - A line per thought a day: the speaker's head and shoulders on the people tile, their
    name, the thought ("· Chilly sleep"), how many share it ("4 dwarves", their names on
    hover) and their words: "Woke with frost in my beard. A hearth would not go amiss."
  - A line keeps its speaker's name, so it reads the same after they leave. A dwarf who
    has left keeps their face if the page drew it; otherwise the dwarves' picture stands
    in.
  - Empty, it says what will land in it.
  - **What lands in it** (`ColonyJournal`, doc 13): the thoughts on the character sheet.
    A thought begins when a dwarf comes to have it, or when its memory comes again (a
    second night in the cold, another meal off the knees). The first dwarf whose thought
    begins that day speaks; others whose same thought begins that day join the line. What
    dwarves already think when the journal first sees them is not news, so a load writes
    nothing. Each thought has a few lines in `data/colony/journal_lines.json`, keyed by
    the thought's id; the dwarf, the day and the thought choose one.
- **Before the flag.** "No settlement yet", "Plant the settlement flag to found it. Your
  dwarves arrive with it." and Found the settlement, which closes the page and starts the
  flag tool. There are no entries, rows or mood until then.
- **Rename** turns the name into a field with Suggest another and Done. Done waits for a
  name in the rules, and the founding line says why while it waits. Enter is Done; Esc
  leaves the name as it was. Events keep the name they were written with.
- **Reading.** The page reads the colony each second while it is open and redraws only when
  something changed. It reads what Colony Dwarves and Inventory read:
  `DwarfInspection.roster_state()`, `ColonyInventory.snapshot()`, RoomManager's owned rooms
  and StockpileManager's stores. FlagPlacementController keeps the name and founding day
  and joins the group `settlement`, where SaveManager and the game menu find it; DockUI
  hands it to the page and the founding card.
- **Sizes** go by screen height, as Colony Dwarves': large from 1300 px (1560 px across),
  medium from 900 (1200), short from 650 (1020, clear of the Sky Dial at 1280×720) and
  small below. Short and small screens drop the caption above each value, as the picture
  and the words already say what a row counts. All five rows show above the dock from
  1280×720 up. Small screens, and screens too narrow for the size, set the journal under
  the rows, and the two scroll together.

**Naming the settlement.** Clicking where to plant the flag opens the founding card
(`FoundingCard.gd`, the window `founding`): a people window titled "Found the settlement"
over the world, near the top and clear of the flag waiting where the player clicked
(FlagPlacementController's `naming_started` and `naming_ended`). Another valid click moves
the waiting flag.
- **Chosen by the owner** (2026-10-25) over two other ways that were drawn: a given name
  renamed later in Colony, and the dwarves proposing names after the first day, which
  needs Events entries that ask for a decision.
- The field holds the world's first suggestion, selected, so typing replaces it. Suggest
  another draws the next. The line under it reads "Suggested from the world's seed. You
  can rename it later in Colony."
- Found Brunhald plants the flag, brings the dwarves and posts "Brunhald is founded." to
  Events ("5 dwarves have arrived with the flag."), with its toast; its Locate goes to the
  flag. Cancel, the card's ✕ or Esc keeps the flag tool; Esc again ends it.
- **The rules** (`SettlementName.gd`): 3 to 24 characters of letters, spaces, hyphens and
  apostrophes, beginning with a letter. Spaces at the ends go and a run of spaces becomes
  one. A name outside the rules keeps Found off, and the card says why.
- **Suggestions** join a first and a second word part of one style in
  `data/colony/settlement_names.json` (read by FlagPlacementController): Dwarvish (Brunhald,
  Kolgund) and plain words (Stonehollow, Emberdeep) take turns, as the owner picked neither
  style. The world's seed picks the parts, so the same world suggests the same names. None
  repeats an earlier one or stutters at its join: the same letter either side
  ("Skarrok"), or one part sounding the other again ("Grimrim", "Gungund").
- **Where the name shows:** Colony's header, the founding toast and Events entry, the game
  menu's title in place of "Deepdraft" once the settlement is founded, and the colony's
  slots in Load.
- **Saved** with the flag (`settlement_flag`'s `name` and `founded_day`), and copied beside
  the clock at the top of the save as `colony_name`, so Load reads it without opening the
  colony (doc 13).
- **A flag from stock** placed before any founding (DEV stock) still founds a named
  settlement under the first suggestion, so a founded save always has a name.

### Data-Driven Layout

Dock order, icons, menu labels and action bindings live in `data/ui/dock.json` and are loaded by the
`UIRegistry` autoload (Registry Pattern — no other script reads the file directly). The
data file's scope is **layout only**: order, icon, label, tooltip, disabled state and action bindings.
The action *logic* lives in GDScript — the dock node maps each `action` string to a handler
via a dispatch table — per the JSON-vs-GDScript rule (*JSON = what things are, GDScript =
what things do*). Buildable-entry catalogs (costs, `action_type`, `requires_floor`) are a
separate concern and are **not** part of `dock.json`. When those catalogs are specced they
will be JSON loaded by their owning registry, never `.tres` Resources (see CLAUDE.md).

`data/ui/place_catalog.json`, also owned by UIRegistry, holds furniture categories,
short captions and display order. Physical definitions stay with
FurniturePlacementController; Available and Reserved are derived from actual items
and pending placement requests, not UI data.

```json
{
  "schema_version": 2,
  "items": [
    { "id": "orders", "icon": "res://assets/ui/icons/orders.png", "family": "work", "label": "Orders", "action": "open_panel", "target": "orders" }
  ],
  "menus": {
    "orders": {
      "title": "Give an order",
      "items": [
        { "id": "mine", "label": "Mine blocks", "action": "activate_tool", "target": "mine_precision" }
      ]
    }
  }
}
```

`UIRegistry.get_dock_items()` returns the ordered navigation buttons;
`get_menu(target)` returns a title, optional parent group and validated command
entries, illustrated state, dock anchor and desktop/compact column limits.
Buttons require `id`, `label`, `action` and `target`; `icon`, `icon_region`,
`family`, `tooltip`, `planned`, `preview`, `status_label`, `key_action` and
`separator_before` (a group gap before the button) supply presentation. An
`icon_region` cuts a region of a shared sheet as a runtime `AtlasTexture`
(`UIRegistry.get_dock_icon()`); only Development's painted sheet still uses one.
Malformed entries are skipped with a warning at load. Place and Inventory categories
carry no pictures.

### Action Types

| `action` | Effect |
|---|---|
| `open_panel` | Opens a build/designation panel above the dock. Panels are **mutually exclusive** — opening one closes any other. `target` names the panel. |
| `toggle_window` | Toggles a movable floating window (Colony's page, Events, inventory, trade). `target` names the window. |
| `activate_tool` | Emits the existing `tool_requested` signal. Orders keeps its shelf open; other command menus close. Controllers retain the one-active-tool contract. |
| `panel_action` | Save and developer commands dispatch by stable item `id`; an unknown `id` is ignored with a warning. |
| `open_crafting` | Closes the profession chooser and opens the recipe/preview menu for the section named by `target`. |

### Scene Wiring

DockUI is not a service locator. Each node that talks to the dock holds a
`dock_ui_path` (or `dock_path`) export wired in `debug_world.tscn`. Tool
controllers call the dock's `register_*_controller(self)` and connect to
`tool_requested`. The dock keeps those references only to drive its own UI:
button pressed states, the Orders shelf, the Place, Inventory and Crafting windows,
and the time and Slice HUD. It never hands one controller to another:

- `TreeFellingController` reaches the mining owner through its own `mining_path`.
- `CraftingManager` registers with the dock through `dock_ui_path`.
- `DwarfDirector` drops the active tool through `dock_ui_path` when it inspects a
  dwarf. It also passes the dock to its Professions panel, whose Esc defers to an
  open dock menu.
- `FurniturePlacementController` opens Crafting from a workbench through
  `dock_ui_path`.

The `command_dock` group remains for tests to find the dock. Game scripts do not
look the dock up by group.

### The title screen

The game opens on the title screen (`scenes/main/title_screen.tscn` with `TitleScreen.gd`,
the main scene since 2026-10-25), not in a colony.
- **The art** is the loading screen's painted mountain settlement, cropped as the loading
  screen crops its panoramas, so one follows the other. `data/ui/title_screen.json` names
  the art, the game's name and the line under it. A shade on the left keeps the words
  readable over the art. The owner chose the painted art over a Hearthblock scene or the
  colony as the save left it (2026-10-25).
- **A column at the left of the screen's middle 16:9,** so on a 32:9 screen it stays left of
  the centre. It holds DEEPDRAFT in the HUD's title face, "Dig · Brew · Trade" in hay,
  then the menu:
  - **the newest save on a pine board,** as the Load page shows a slot: the settlement's
    name ("Your colony" before it has one), its date and hour ("Autumn, day 8 · Year 1 ·
    02:14") and "Saved 1 day ago · Quick save", or the name of a named save ("Saved 2 days
    ago · Before the flood"), with **Continue**, the family block, focused so Enter resumes;
  - **New game, Load game…, Settings… and Exit game,** the game menu's own buttons. Without
    a save there is no board: New game is the family block and has focus;
  - "Enter continues", or "Enter starts a new colony" without a save.
- **Nothing asks first,** as no colony runs: New game starts at once, a Load slot loads at
  once, and Exit game and the window's close button quit at once.
- **Load game… and Settings…** are the game menu's own pages, opened on their own
  (`GameMenu.open_page`). Back, ✕ or Esc close them, back to the title. The Load page reads
  "Choose a save to play." Saves can be deleted there too, and back on the title the board
  shows the newest save left, or goes when none is.
- **Continue** loads the newest valid save of any kind, named saves too
  (`SaveManager.request_continue()`), ranked as launch ranked them before the title. A save
  that cannot be read says so under the buttons.
- **The clock is held** while the title shows, which also keeps Esc from opening the game
  menu. The world is made only after a choice, behind the loading screen.
- **Development builds open on the title too** (the owner's pick, 2026-10-25, over DEV
  builds skipping straight to the newest save, or a switch of their own): Enter continues. `debug_world.tscn` run on its own still starts the world and resumes the newest
  save, as launch did before the title. That covers the editor's Run Current Scene (F6),
  the tests and the tools.
- **Sizes** go by the screen's height, as the game menu's.

### The game menu, saving and loading

A world scene started on its own (see "The title screen") resumes the newest valid quick
save or autosave, including backup recovery when needed. If no valid save exists, it opens
a fresh world. Selection happens before world generation and the loading screen remains
until restoration is complete.

**The game menu** (`scripts/ui/GameMenu.gd`, the `GameMenu` autoload; doc 13) is where the
colony is saved, loaded, started anew and left.
- **Opening.** The dock's Menu button (the brass cog) opens it, and so does Esc once
  nothing in the scene used the key.
- **Esc's order.** A drag in progress ends, an open dock menu closes, the active tool
  ends, a window's own Esc closes it, and the selection clears. Each of these handlers
  marks the key used, and only when it acts. Then the game menu's turn comes, last of
  all, because it is an autoload: it closes the front window still open
  (`UIWindowManager.close_front()`), and with none left it opens. Inside the menu, Esc
  steps back: a question, then a page (Load or Settings), then the menu itself.
- **While open.** The world dims, the menu takes every click and every key but its own
  navigation, and the game pauses with a clock hold, as loading does. The player's own
  pause and speed are never touched, and the camera does not pan behind it.
- **The menu page,** titled with the settlement's name once it is founded (else
  "Deepdraft"). The colony's date and time, a tag saying when this colony was last
  saved ("Last saved 3 days ago", moss when just saved, "Not saved yet" for a new
  colony, or once every save of it was deleted: the tag gives its newest save still on
  disk), then Resume (the family block), Save game and Save as… side by side (one row, so
  the menu still fits 1280×720), Load game…, New game…, Settings…, Quit to main menu… and
  Exit game….
  - **Save game** saves and the menu stays; the tag reads "Saving…", then "Last saved
    just now".
- **Save as…** (2026-10-26, doc 274) keeps the colony under a name, beside the quick save
  and the autosave.
  - **Chosen by the owner** over six numbered slots, and over one book of saves per colony
    (as Oxygen Not Included keeps them). Decided with it: Save game still writes the quick
    save in one click, there is one autosave as before, and named saves have no limit.
  - The page's line: "Name this save. It keeps Brunhald as it is now, beside the quick save
    and the autosave."
  - The name field (the founding card's) holds the colony's name and date, "Brunhald, autumn
    day 9", selected so typing replaces it; "Your colony" before the settlement is founded.
    A name already taken gets a number after it ("Brunhald, autumn day 9, 2").
  - Save, or Enter, saves a new name at once and goes back to the menu page, whose tag reads
    "Saving…" as for Save game; the toast says "Saved as "Before the flood"."
  - **Names** (`SaveName.gd`): up to 40 letters, digits, spaces, commas, hyphens and
    apostrophes, beginning with a letter or a digit. Spaces at the ends go and a run of
    spaces becomes one. The line under the field gives the rules; a name outside them keeps
    Save off and the line turns rust.
  - Capitals don't count: a name already in use ("first winter" for "First winter") turns
    the line hay ("…is a save already: Save asks before replacing it."), and Save asks first.
  - Under the field, **Your saves** with how many and the room they take ("Your saves ·
    4 saves · 98 MB"), newest first on compact boards: the name, how long ago, the colony
    and its date, and Replace.
- **The Load page.** Each slot sits on the pine board: the quick save ("Written by Save
  game.") and the autosave ("Written every five minutes while you play."), each with its
  settlement's name and date in the colony ("Brunhald · Autumn, day 8 · Year 1 · 02:14"),
  when it was saved (how long ago, and the local time), Load, and under it Delete while the
  slot holds a save (owner, 2026-10-26: every save can be deleted). A missing slot reads "No
  autosave yet." and cannot be chosen.
  - Under them, Your saves as on the Save as… page, each with Load and Delete. Without any:
    "Your saves · none yet" and "Save as… in the game menu keeps your colony under a name."
  - The list scrolls in the room the screen leaves the page: at 1920×1080 the two slots and
    four of your saves fit.
  - Back, or Esc, returns to the menu. **Open folder** beside it shows the named saves'
    folder, as Blueprints' does.
- **The Settings page** (`SettingsPanel.gd`, built by GameMenu) has its sections as tabs
  across the top, as the dwarf, room and storage windows do: Audio, Interface, Video and
  Controls. The open tab is the family block. Settings opens on the tab last open, Audio the
  first time.
  - **More sections:** past four, tabs crowd small screens, so further sections would move
    to a list down the left, beside the page.
  - **Every setting is a row** in the inset: its name and a line on what it does on the
    left, its control on the right. A control is either choice blocks or a slider (a cell
    groove with a hay fill and a stone knob) with its value in hay. The chosen block is the
    family block, and two choices keep the width of three, so the columns line up.
  - **Audio** ("Your audio preferences apply to every colony."): Ambience (weather,
    woodland, shoreline and cave sounds) and Effects (work, wildlife, water, fires and
    notifications). Each has its slider, percentage and a Mute toggle, the family block
    while on. Under them: "Ambience softens while paused." AmbientAudio keeps them in
    `user://audio.cfg`. Restore defaults sets Ambience to 72% and Effects to 45%, both
    unmuted (`default_volume`, `default_effects_volume` in `data/audio/environment.json`);
    45% is the Work bus's original −7 dB.
  - **Interface** ("The size of the interface. Changes show at once and apply to every
    colony.") is the UI scale (2026-10-25; "The UI scale" below).
    - Its blocks are Auto and the steps the window has room for.
    - Under a rule, a note gives the scale in effect and the room it leaves ("Auto: 150%,
      as Windows sets this screen. The interface lays out at 5120 × 1440."), then "Auto
      follows the display scale Windows sets for this screen."
    - `VideoSettings` keeps it with the video choices, in `user://video.cfg`.
  - **Video** ("Changes show at once and apply to every colony."). `VideoSettings` keeps
    the choices in `user://video.cfg`, and each Video default is what the game does unaided:
    - Display: Borderless (the default), Fullscreen (exclusive) or Windowed. Windowed opens
      at two thirds of the screen, centred, and keeps its size from then on.
    - Render scale: 50–100% in steps of 5, with the world's resolution under the
      percentage. Below 100% the world is drawn smaller and FSR 1 upscales it; the
      interface always draws at full size. There is no list of resolutions: the game draws
      at the screen's own size, and Render scale does that job.
    - Frame rate: the even shares of the screen's refresh rate down to 24 fps (120, 60, 40
      and 30 fps at 120 Hz). The default paces at 60 on a 120 Hz screen (doc 21).
    - VSync: On (the default) or Off.
    - Shadows: High (the default: 4096 shadow maps and the engine's soft filter), Medium
      (2048, a lighter filter) or Low (1024, hard edges).
    - Anti-aliasing: Off (the default), SMAA, MSAA 2× or MSAA 4×.
  - **Controls** ("Every key and mouse control. Choosing your own keys comes later.") is the
    key list (2026-10-25): groups in two columns, Camera, Time and Windows, then Views and
    Tools.
    - Each entry is what the player does, with its keys on the hover cards' stone keycaps
      at its right. A chord's keys are joined by a plus ("Shift + Wheel"); alternatives
      read "or" ("W A S D or Arrow keys"), or "/" when they pair with the entry's "raise /
      lower".
    - The list is data (`data/ui/controls.json`, read through UIRegistry). An entry names
      input actions, whose keys come from the input map, so the list shows the keys the
      game uses; fixed keys and the mouse are named as they are.
    - Lines never break after a number or a slash ("1 level", "1 / 4 levels").
  - **Along the foot:** Back, "Esc goes back to the menu", and Restore defaults, which
    resets the open tab only. Controls has nothing to restore, so it has no Restore
    defaults.
  - **The page follows** AmbientAudio's and VideoSettings' `preferences_changed`, whoever
    changed them.
  - **Sizes.** Every row takes the tallest row's height, and the inset keeps one size on
    every tab, the tallest one's, so switching never resizes the window (1100 × 1037 at
    7680×2160 at 100%, set by the key list). When the settings' rows (Audio, Interface and
    Video) do not fit (1280×720, and every small screen), they drop their lines, which
    become their tooltips. Only a tab that still does not fit scrolls: the key list, on
    screens under about 810 px tall.
  - **Keyboard.** Focus starts on the open tab's first control: the Ambience slider, the
    chosen UI scale, the chosen Display block, or the Controls tab itself. The arrow keys
    move between the controls and move a slider in focus.
- **Questions.** Load, Replace, Delete, New game, Quit to main menu and Exit ask first, in a
  question in front of the menu; Load, New game, Quit and Exit say how long ago this colony
  was last saved. Cancel, ✕ or Esc closes a question, which defaults to Cancel.
  - Load: "Your colony goes back to autumn, day 7, year 1. Anything since your last save,
    3 days ago, is lost." Load · Cancel. A named save's title names it: Load "Before the
    flood"?
  - Replace "First winter"?: "It holds Brunhald on winter, day 2, year 1, saved 2 days ago.
    Brunhald as it is now takes its place." Replace · Cancel.
  - Replacing a save of another colony (another world's seed) says that colony is lost:
    ""Kolgund" holds another colony, Kolgund, on spring, day 4, year 1, saved 5 days ago.
    Brunhald takes its place, and Kolgund is lost." Replace Kolgund (rust ink) · Cancel (the
    family block).
  - Delete "Kolgund"?: "Kolgund on spring, day 4, year 1, saved 5 days ago. Its files go to
    the Recycle Bin, and it leaves this list." Delete (rust ink) · Cancel. From the title,
    where a Load needs no question, Delete still asks.
  - Delete the quick save?: "Brunhald on autumn, day 8, year 1, saved 1 day ago. Its files go
    to the Recycle Bin, and Save game writes the next one." The autosave's ends "and the
    next comes after five minutes of play."
  - New game: "A new world grows from a fresh seed. Your saves stay as they are, but once
    the new colony saves, its quick save and autosave replace the ones you have. Save as…
    first keeps Brunhald under a name." Start a new colony · Save as… first (the Save as…
    page) · Cancel.
  - Exit: Save and exit (the default; it quits once the save is written) · Exit without
    saving · Cancel. Closing the game's window asks the same; while the world is still
    being made or loaded, the window closes at once.
  - Quit to main menu: "Quit to the main menu?" Save and quit (the default; it leaves once
    the save is written) · Quit without saving · Cancel. Leaving clears the world
    (`SaveManager.request_quit_to_title()`, as New game and Load clear it) and shows the
    title screen, whose Continue then offers the newest save.
  - A confirmed load or new game closes the menu first, so SaveManager sees the player's
    own pause, then asks SaveManager.
- **Sizes** go by screen height, as the windows' do (the menu is 640 px wide at
  7680×2160). It sits on its own canvas layer (100), above the dock, windows, toasts and
  hover cards, and below the loading screen.

New game starts a fresh world with the configured starting calendar and a new seed,
discarding unsaved progress without deleting existing saves; normal autosaving continues
after five minutes in the new world. `SaveManager` owns the timer, file I/O and state
serialization.

The manual quick save lives at `user://saves/quicksave.json`; a separate automatic save is
written every five minutes of ready, non-generating world time to
`user://saves/autosave.json`. Named saves live one file each in `user://saves/named/`,
named after the save (`before_the_flood.json`). All use schema version 2, validate a
temporary snapshot before replacement, and retain one matching backup. If a selected
primary is corrupt, Load recovers that slot's backup and repairs its primary automatically.
Autosaving shows a brief **Autosaved.** toast and never replaces the player's manual save.
The quick save and the autosave are shared by every colony, so a new colony's replace the
last one's; a named save is replaced only when the player says so, and any save is deleted
only when the player says so.
The save records the deterministic world seed plus authoritative deltas/state: changed
terrain (the final block of each changed cell) and exploration, mining designations, the
settlement flag (with the settlement's name) and dwarf roster,
the event log and the journal, stockpile zones and
contents, furniture ghosts/installed pieces, loose items,
calendar/weather, finite water and stone identities, item/stack permissions,
wildlife/arrival progress, camera, and slice state. Load regenerates the seed-identical base
world and reapplies those sections in dependency order. Tasks, leases, reservations,
navigation/render caches, and interior-region tables are transient or derived and are
rebuilt. Snapshot creation is observational: it never releases a worker, changes an
assignment, or clears a reservation. Items currently in transit are recorded with their
carrier and materialize loose at that dwarf's saved position on load, where rebuilt work
sources can reclaim them. The dock shows a short success/error toast, including the
no-save-yet and world-still-generating cases. Required owner sections and typed
records are validated before changing the world; an empty scene or malformed
section cannot bypass backup recovery. Older development saves are not migrated.

The save format lives in [`12_world_grid.md` → Save Format](../10_core_foundation/12_world_grid.md);
`SaveManager`'s ownership and restore lifecycle are in
[`13_architecture.md` → SaveManager](../10_core_foundation/13_architecture.md).

Some `toggle_window` targets are intercepted in `DockUI._toggle_window` and routed to a real
system instead of a generic window: `world_info` / `block_inspector` toggle their overlay
CanvasLayers, `slice` toggles the **Slice tool**
(see below), and `rooms` toggles the **Rooms tool** (see below). X-ray now has
dedicated controls beside the slice tower (210); it is not a generic window.

### The UI scale

One scale for everything drawn over the world (2026-10-25, with the owner's picks):
the dock, Sky Dial, time controls, slice tower, compact panel, windows, hover cards, toasts,
the game menu, the title and loading screens, and the marks over dwarves. Settings'
Interface tab sets it.
- **It is the window's content scale** (Godot's `content_scale_factor`).
  - Text is redrawn sharp at the new size, and the world renders at the screen's full
    resolution.
  - The interface lays out in the room the scale leaves: 5120 × 1440 at 150% on
    7680×2160.
  - Changes show at once, with the menu and every window laying out again.
- **The steps** are 100, 125, 150 and 200%, offered only while they leave the interface at
  least 960 × 540, the smallest room the game menu fits.
  - All four are offered at 7680×2160, 2560×1440 and 1920×1080; 100 and 125% at
    1280×720; 100% alone at 960×540, where the note says the window has no room for more.
  - A choice too large for the window waits at the largest step that fits ("200% needs a
    larger window: 150% for now").
  - **No 175%.** It lands just under a size boundary on 1920×1080 (the dock's 1200 px
    wide, the windows' 650 px tall) and on 7680×2160 (the windows' 1300 px), so things
    come out smaller than at 150%.
- **Auto, the default,** is the display scale Windows sets for the screen the game is on,
  as the largest step not above it. Windows at 150% gives 150%, and at 175% it gives 150%.
  - It is read from the screen's DPI over 96; Godot's screen scale says 1.0 on Windows.
  - It is read again on every resize of the window, so it follows the game to another
    screen in full screen.
  - Headless it is 100%.
- **Windows take the sizes for the room left.** Their large, medium and small sizes go by
  the room's height (large from 1300 px, small below 650), so they always fit.
  - At 150% on 7680×2160 they keep the large sizes, 1.5 times larger.
  - At 200% they use the 1920×1080 sizes, twice as large: their text about as large as
    at 150%, in a denser layout, while the dock and cards keep growing.
  - At 125% on 2560×1440 the room is 1152 px tall, so windows switch to their medium sizes
    and come out a little smaller than at 100%. The large sizes cannot come down to fit:
    the Colony roster's large body alone is 1180 px.
- **Implementation notes:**
  - `VideoSettings` is the one owner of the window's content scale: the `ui_scale`
    setting (section `interface` in `data/video/video_settings.json`). It applies the scale
    while the window draws at its own size (content scale mode disabled, as the game
    runs), and keeps it at 1 for a tool that stretches the window for captures.
  - Scripts change the scale with `VideoSettings.set_value("ui_scale", …)`. A factor set
    on the window directly is undone at the next resize.
  - Positions and sizes read from the viewport are in the interface's room, and mouse
    events arrive there too, so picking, hover and the tools need nothing.
  - What needs the screen's real pixels reads the window's size. Render scale's world
    resolution (`VideoSettings.render_size()`) does, and so do the marks over dwarves for
    their own size, so they also grow with the scale.
  - Cell art draws nearest (`UITheme.cell_texture`); pictures keep their own filtering.
  - Portraits render at their shown size times the scale and follow a change
    (`UITheme.follow_ui_scale`). The settlement page crops its faces in proportion.
  - **Pictures of a UI scale at 7680×2160:** a window that size would cover the owner's
    screen, so draw at the room the scale leaves (`content_scale_size` 5120 × 1440 for
    150%, viewport stretch) and save at half size. In a real window, set the preference
    instead.

### Type

Every word is set in fonts shipped with the game, one face per role, at sizes from one type
scale (2026-10-26; the owner's picks: Fredoka for names and titles with Nunito for text, the
HUD's titles in the same face, and today's sizes made even).
- **The fonts** sit in `assets/ui/fonts/`, each with its SIL Open Font License text:
  - Nunito (`nunito_variable.ttf`) and Fredoka (`fredoka_variable.ttf`), variable fonts
    whose `wght` axis gives each role its weight;
  - Noto Sans Symbols 2 (`noto_sans_symbols_2.ttf`), the symbol font.

  They are imported with `tools/voxel_assets/Import.ps1`. The licences must travel with the
  game: the Windows export takes `assets/ui/fonts/*.txt` as non-resource files (an export
  setting the owner adds).
- **Faces by role** (`UITheme.FACES`; `UITheme.font(role)` builds each once):

  | Role | Face | Used for |
  |---|---|---|
  | text | Nunito Medium (500) | most words; every theme's default font and the project's fallback |
  | rows | Nunito Bold (700) | fact rows, status, flavour and tooltips (`body_font()`) |
  | names | Fredoka SemiBold (600) | names, headings, buttons and badges (`display_font()`), outlined on bands; the dwarves' name tags |
  | hud | Fredoka SemiBold (600) | the HUD's titles (`hearth_title_font()`, `apply_title()`): the Sky Dial, the dock's menus, the mining guide's window, the title and loading screens |
  | figures | Nunito ExtraBold (800) | numbers that change while you watch: the Sky Dial's time, the slice tower's level, the mining guide's sizes |

  - Fredoka's digits differ in width, and a game minute lasts a second at 1×. So the clock
    uses the figures face: Nunito's digits share one width, and the time holds still.
  - Windows never use the hud face; `WindowStyleTest` checks.
- **Symbols:** the symbol font is each face's fallback, for what Nunito and Fredoka lack.
  - Godot measures a line by the tallest font behind it, and the symbol font is 1.70 em
    tall. `tools/fit_font_metrics.py` lowered its ascent and descent to 0.95 and 0.23 em,
    inside Fredoka's, so it never makes a line taller. Its glyphs still draw in full.
  - Menu paths in the UI's words use › ("Place › Plants"); the crafting queue moves an
    order with ▴ and ▾.
- **The type scale** (`UITheme.TYPE_LARGE`, `TYPE_MEDIUM`, `TYPE_SMALL`): every text size is
  one of seven steps, sized by tier.

  | Step | Large | Medium | Small | For example |
  |---|---|---|---|---|
  | display | 42 | 34 | 28 | the settlement's name; a dwarf's name on the sheet |
  | name | 34 | 28 | 24 | window titles; hover card names; an item's name on its card |
  | title | 28 | 23 | 20 | big values; crafting's titles; the Load page's slots |
  | heading | 23 | 19 | 16 | headings; tool names; a window's main verb |
  | lead | 19 | 16 | 14 | toasts; hover card lines; a dwarf's role |
  | body | 17 | 14 | 12 | rows; tabs; descriptions; plain buttons |
  | small | 14 | 12 | 10 | labels; keys; tags; small capitals |

  - The tiers are the windows' own: large from 1300 px of room, small below 650. Settings'
    UI scale multiplies everything as before.
  - A window's size table names its text sizes by step for its tier (`"text": MEDIUM.body`,
    through the aliases `LARGE`, `MEDIUM` and `SMALL`). Each tier also carries its scale as
    `"type"`, for a neighbouring step (`s.type.lead`).
  - A window may take a smaller step for one tier where its room is short: the character
    sheet's thought cards take small at the medium tier, where body cut "Slept in my own
    bedroom" short (`DwarfInspectorTest` checks it shows in full at 1280×720).
  - What has no tier uses the medium table: the themes' defaults, a window's title in its
    fixed band, labels a window builds before it sizes them. The hover card uses the medium
    table when wide and the small one below 1200 px.
  - Not on the scale, sized to their art: the title screen's DEEPDRAFT, the Sky Dial's time
    and date, the picture tiles' captions and the Appeal key. The 3D labels keep their own
    sizes.
  - The lint's `type-size` rule fails on a text size typed as a number.
- **Tests:** `TypeTest` (ui area) checks:
  - each role's shipped face, weight and symbol font;
  - that no Windows font is left in the themes, the fallback or any control;
  - the scale, and each window's tables;
  - that the clock holds one width as its minutes change;
  - that every character in the scripts' strings and the data's words is in a shipped face.

### The tool bar

One bar for every tool (2026-10-25, with the owner's picks): the six Orders tools, Storage,
Build, Shapes, Copy, placing a blueprint, Rooms, Place and Move, the
settlement flag and the DEV
stamper. `ToolBar` (preloaded by `DockUI`, on the dock's layer 20) shows the active tool's.
- **Where:** 8 px above the dock, or above the Orders shelf while it is open, centred over
  the dock. It slides aside only as far as it must to clear the slice tower, the X-ray and
  Appeal options and the compact panel. A bar too wide to slide clear (Shapes on a 16:9
  screen) first narrows its status line, trimmed, and drops View, then drops the status
  line; only then does it rise above what it cannot pass.
- **Left to right:**
  - the tool's picture on its family tile, its name, and its keys on the hover cards'
    keycaps ("Click or drag to build · Ctrl + Drag takes plans out");
  - its choices as rows of pictures, the chosen one lit: Shapes' shape (Tab) and Build's
    material (Q and E). Stone's and Wood's pictures open their menus (see "Build");
  - its settings as − value + steppers: Build's Height; a hollow rectangle's Door; Mine
    blocks' Width and Depth, with the 32 × 32 guide's switch; a wall piece's Mount level;
    Shapes' Filled switch. Each keeps its keys (Alt + wheel, Shift + wheel, F), which its
    hover card names;
  - a tool's standing numbers: Place's "2 ready" and "0 on their way";
  - the tool's message ("Raise the slice to build above this face", the ghost's hint), else
    what it last said ("No clear cells to build"), else LAST ORDER: the newest order, with
    View, or "None yet";
  - Undo, and Done · Esc as the family block.
- **The look:** a slab with its family's band along the top, as toasts have. The work family
  is for Orders, Zones and Construction; the settlement family for Rooms and Place; the
  people family for the flag; DEV brown for the stamper. It takes the windows' sizes: large
  from 1300 px of room, small below 650. A screen too narrow for it drops the keys line
  first, then the standing numbers.
- **Steady:** a button that cannot be used dims. A tool that makes orders keeps the LAST
  ORDER place, so the bar keeps its width as orders come.
- **The tag:** while a drag is held, a small slab beside its end says what it would order and
  what that costs, in rust when the stock runs short.
  - Build and Shapes: the drag's size first, so the player sees the dimensions
    (owner, 2026-10-26): "12 × 10 · 3 tall" for a box or a rectangle, "9 across" for a
    circle, "6 steps · 2 wide" for stairs. Then "27 blocks · 27 rough stone · 6 in stock",
    or soil, or the chosen wood's logs. The cost is the definition's `cost` per block of its
    goods (`item_key`, or the chosen wood's log), named by its `good` or the wood's words,
    against `StockpileManager`'s available total.
    While erasing: the box's size, then "takes 12 planned blocks out".
  - Mining: the blocks to mine or unmark. Storage: its cells and size ("9 × 4, 1 blocked");
    this replaced its floating 3D label. Chop and the clearing tools: what they would mark.
    Cancel orders: what it would cancel.
  - Near the screen's right or top edge, or over the slice tower and the panels the bar keeps
    clear of, it turns to the other side of the drag. Why a flight of stairs stops short
    shows on the tag's second line too.
- **Undo:** one list of the last 20 orders, whichever tool made them, newest first.
  - Undo, and Ctrl + Z (`tool_undo`), take back the newest order that still has work left:
    what is left of it is cancelled, and finished work stays.
  - Its hover card names the order, and the tool when another tool made it.
  - Ctrl + Z also works with no tool on, after text fields and the game menu have had the
    keys; a toast then says what it took back. Place's last piece ends the tool, and the
    piece can still be taken back.
  - Orders that join the list: Mine blocks, Chop and the clearing tools, Storage, Build,
    Shapes, a blueprint's placement (its plans together) and floor plans, Place and Move (ladders excepted). Cancel orders, Rooms, the flag
    and the stamper make none.
- **Done** ends the tool as Esc does. Place's and the stamper's windows stay open, as after
  Esc's first press.
- **Views:** while X-ray is on, the bar says "X-ray waits while you work."
- **Implementation notes:**
  - A tool joins with `DockUI._bind_tool`, from its `register_*` call, and answers
    `tool_bar_state()`: `tool` (its id, the dock's target), and optionally `name`, `picture`,
    `family`, `choices` (each with `id`, `label`, `value`, `keys` and `options`, each
    option with `id`, `label`, `picture` and `tooltip`, and optionally `menu`: rows, each
    with `id`, `label`, `value` and `options`, a row's option optionally with `count`,
    `tone` and `note`), `settings`, `toggle` (with its
    `keys`), `standing`, `selection` (`count`, `detail`, `short`, `at`), `message` and
    `undo`. The choices, the steppers and the switch call
    `set_tool_setting(id, value)`; Done calls `deactivate()`.
  - Orders come as `order_created(receipt)`, with `order_is_pending`, `undo_order` and
    `inspect_order` on the tool. `order_feedback(message)` says what a click did otherwise.
  - The keys under each tool's name are data: `data/ui/tool_bar.json`, read through
    `UIRegistry.get_tool_bar()`. The name, picture and family come from the tool's dock
    entry (`UIRegistry.get_tool_entry`) unless the tool gives its own.
  - The Orders shelf (`OrdersShelf`) keeps only its tiles; the bar replaced its banner and
    order toast. Construction's corner box, Place's Done, Undo last and bare hint label,
    and the stamper's Done and hint went with them.

### The item stamper

A DEV tool (2026-10-25; `ItemStamperPanel` and the `ItemStamperController` scene node). It
replaced Spawn Drops, Spawn Furniture and Spawn Bushes. Development → Item stamper opens
its window, "Stamp an item", in the DEV family's colour.
- **The owner's choices** (2026-10-25):
  - the picture grid with the card, over a search window or a command bar;
  - one pile per click, which dwarves carry to storage, over goods stored on a stockpile;
  - furniture packed, over installed;
  - no mixes of the old spawners.
- **The window is laid out as Place:**
  - every item as a picture, in the groups of `data/ui/item_stamper.json` (Materials,
    Furniture, Tools, Food & seeds, Drink, Plants, Other);
  - Recent first: the last eight items stamped, kept between sessions in
    `user://item_stamper.cfg`;
  - a search box that keeps the items whose name or id holds what is typed, and says when
    nothing does. Enter picks the first match;
  - the chosen item on the pine board: its name, id, picture and description, its wood as
    pictures for furniture (Pine first), and the amount (−, +, 5, 10 and 20);
  - Stamp starts stamping. The tool bar then names the item, says what each stamp put down,
    and has Done.
- **Stamping:**
  - each click on a floor puts the amount down as one pile, as crafting drops goods. The
    floor is found under the slice as the other tools find it, and a DEV-coloured square
    marks the floor under the pointer;
  - uprooted bushes come through the flora owner, one to a floor around the click, so each
    keeps its record;
  - Esc, Done, closing the window or another tool ends stamping.
- **Refused, dimmed with the reason:**
  - uprooted wildflowers, whose records would not survive a load;
  - the river's two water stones;
  - the settlement flag, one per colony.
- **No Undo last.** A stamp merges into a matching pile, and bushes keep records, so taking
  one back would not be simple. It was left out on the owner's "keep it simple".
- **Only with DEV tools on:** without them the tool never registers, and Development is
  hidden.

### Developer cave explorer (2026-10-07)

**Development → DEV: Cave explorer** opens a nonpersistent inspection
window. Choose a cave and use **Focus + slice**; **Previous/Next** steps through
the cave catalog. Outlines project through terrain on a CanvasLayer. **Preview
interior with DEV lighting** temporarily exposes the selected cave with enough
light to inspect its walls, floor, veins and soil. Counts distinguish usable
floor area, air volume, exposed resources and soil blocks.

Highlighting or previewing does not discover, excavate or save a cave. Closing
the window restores the prior camera/slice and lighting, while preserving actual
mining and discoveries. Normal play reveals a connected system when mining
breaches its wall; the cavern lands in the event log with a toast (Toasts and the event
log, below). The real cave remains dark until
lit. Cave generation and discovery rules are in
[43 — Cave discovery](../40_economy_colony/43_mining_materials.md#cave-discovery).

### The Slice Tool

The **Slice** button, the dock's last icon (a block of ground with its top lifted),
toggles the slice view.
`SliceController` owns the plane, its keys, its seeding and its saved state, and no UI:
`TimeSliceHUD` presents it, and other systems move the plane through it (the cave
explorer's Focus + slice calls `show_at_height()`). While Slice is on, the
`TimeSliceHUD` tower rises above the button with double up, single up, a level readout,
single down and double down. Single arrows move one level and double arrows move
exactly four, from any height: steps never snap to the four-block mining cells. Steps
and their keys do nothing while Slice is off. Buttons disable at their bounds. Turning
Slice off hides the tower; reactivation restores the last height and the tower returns
in the same place. On
short screens, where the tower would reach the time controls under the Sky Dial, its
steps shrink (to 24 px at least). No movable window or duplicate Menu command remains.
An active plane at the upper limit reads **LEVEL 127**. Updated 2026-10-12 (142).

| Input | Effect |
|---|---|
| `\` | Toggle the slice view |
| `]` / `[` | Step exactly four levels up / down |
| `Ctrl+]` / `Ctrl+[` | Step one block up / down |
| Wheel over tower | Step one level up / down; Ctrl modifies this to four |

The tower takes the wheel, so scrolling over it never zooms the camera.
Clamps: Y4 floor (Bedrock Protocol — one mineable layer always visible) to Y127 (world top).
First activation seeds the plane at the top of the four-block mining cell holding the
camera's surface column (`floor(y / 4) * 4 + 3`); afterwards the height is
fully manual and remembered across toggles. Its active state, current height, seeded flag,
and last manual height persist in the save.
X-ray keeps the slice plane and its controls available; the earlier mutual
exclusion proposal is superseded by 210.

### Underground X-ray and lower-level reference (2026-10-17)

**X-ray** is one dock icon, just before Slice (a cyan see-through block); it toggles
discovered underground inspection, as does its key, X (see "Keys"). Its options rise above the dock, left of the slice
tower, only while it is on (updated 2026-10-23, 259):
- **Full** shows floors and walls, never ceilings; **Flat** keeps floors with three
  blocks of headroom and low wall sections. Flat needs the dwarves' normal clearance, so
  stacked floors never merge onto one height.
- Undiscovered caves and hidden deposits stay concealed.
- Turning X-ray on turns Slice on if it is off, and the first time it pins the current
  level as the guide. **Pin guide here** moves it.
  Raise the slice to see dashed cyan room perimeters and step boundaries projected onto
  the current plane. **Guide** hides or shows that guide.
- The guide follows the highest discovered floor in each column at or below its level,
  and shows only while the slice is above that level. It marks only those perimeters and
  steps, never a grid of voxels. It covers 160 voxels around the view's centre,
  chunk-aligned, and refreshes as the view moves (`reference_radius` in the `xray` section
  of `data/ui/time_slice.json`).
- One line reads **Guide: level N**, **Guide hidden**, or **Normal view while a tool
  works**.

Mining, construction and other placement tools automatically restore normal
terrain and clicks at the selected work level while retaining the reference.
Closing the tool returns to Full/Flat. The guide cannot be selected or mined, and it
cannot make designations; mining and construction permissions, costs, reach and
navigation are unchanged. X-ray clicks follow the faces it shows (doc 24).
These view preferences are transient; existing slice save state is unchanged.

### The Rooms Tool

The dedicated **Rooms** toolbar button toggles the **Rooms tool**, owned by `RoomOverlayController`
(scene node; DockUI only announces `tool_requested("rooms")` — the controller self-toggles
on its own id and every other click-tool deactivates, the standard one-active-tool
contract). While active, every sealed room draws a **volume outline** with a faint
floor tint: **green** for sealed rooms, **icy blue** for Frozen Vaults. Coplanar
interior edges are deduped. The 2026-10-06 follow-up removed filled walls and ceilings:
their stacked, unshaded green faces made unlit rooms appear bright. Floor opacity
is only 0.3%, or 0.8% when selected, so the actual room lighting remains legible.
The 2026-10-17 selection update gives the clicked room a gold volume outline,
a stronger border following its actual floor perimeter and a subtle gold floor
tint. Other rooms keep their normal colours. Clicks and closing the inspector
update those materials immediately; selection does not rebuild all room meshes.
Overlays render with **no depth test** (the mining ghost-layer treatment), so a room
reads through the mountain whether or not the slice is cut down to it; rooms above the
slice plane hide (the flora convention).

Left-click marches the mouse ray through the grid and selects the first room whose
interior air it crosses — clicks are as x-ray as the overlays, so a room visible through
rock is clickable through rock. Selection opens the **room window**
(`RoomInspectorPanel`, settlement family), after Stonehearth's Town Overview:
- **Band:** the room's name, the owner's bedroom ("Birna's bedroom") or the kind and
  number ("Bedroom 6").
- **Header:** the kind with tags (Sealed, Frozen vault, Owner's bonus +10); who sleeps
  there, with the owner's live portrait or the bed's picture ("No one owns the bed",
  "2 beds, shared"); and the appeal banner with its word and number ("Plain", "4.5").
- **Overview:**
  - what makes it its kind, from `room_kinds.json`: Bed, Light, Door and Walls, each with
    its count, need and ✓ or "!";
  - a plain room is measured against the nearest kind and names the missing step ("One
    step from a bedroom: add a light.");
  - Comfort: heating (the warmth added and its sources) and temperature with its goal;
  - In this room: the furniture as pictures with counts, doors included.
- **Appeal** (see "Room appeal"):
  - first, "Appeal 4.5 · Plain" over the word scale, a segment per word in its tint with
    a mark at the room's appeal, and what a stay leaves ("A plain room leaves no thought.
    At 8 it is Pleasant.", or "…a good thought: +8 happiness for a while.");
  - What it holds: each part with its picture, its name and what it adds or takes, largest
    first ("2 × +3" when a part repeats);
  - Its appeal: what it holds together, and the room size ("121 floor tiles · counts 53%")
    with what that leaves.
- **Details:** volume, doors, floor level, heat units and °C, and seasonal influence.

Its sizes follow the screen height (large from 1300 px, small below 650 px). The page
keeps one height between tabs above the dock and scrolls when longer. Readouts refresh
at 2 Hz without raising the window; closing clears selection. ESC
exits the tool; right-mouse stays camera-orbit (`21_camera.md` contract). Overlays and
selection are derived presentation state — never saved, rebuilt from `RoomManager` on
activation and on `room_updated`/`room_removed` (throttled 0.3 s). Selection survives
RoomManager's id churn by re-resolving through the clicked cell. When that cell is no
longer in a sealed room (the seal broke), the window closes and the highlight goes
(doc 202).

### Room appeal

A sealed room's appeal (2026-10-25; RoomManager, worked out by `RoomAppeal`). Rooms
only: the open ground counts for nothing, so a hall needs a door to count.
- **Chosen by the owner** (2026-10-25) from a concept with five questions:
  - rooms only, over adding the open ground by what lies within 4 blocks of each spot, or
    rating every spot by area as Stonehearth does;
  - a thought after sleeping, eating and playing, over an hourly thought for their
    surroundings, or only their own bedroom's;
  - Horrid, Plain, Pleasant and Beautiful, over a dwarf's scale (Squalid, Bare, Cosy, Fine,
    Grand).
- **What adds:** each piece the room holds by its design and wood, as Place and the compact
  panel show it (a log bed 3, a table 1, doors 2 to 4, a torch 0.5; pine +0 up to
  applewood +2). The hearth and the settlement flag add 2. A piece is the room's as "In
  this room" counts it; a door counts in each room it seals.
- **What takes away:** each pile of loose goods lying in the room, 1, and each storage
  cell holding goods, ½. Plans and bare rock take nothing.
- **Size:** up to 64 floor tiles (8 by 8) a room counts all it holds; a bigger room counts
  its share (64 ÷ its tiles), so twice the floor halves it. (A finished floor added 5 until
  the permanent floors were removed on 2026-10-26.)
- **Words:** Horrid below 0, Plain to 8, Pleasant to 16, Beautiful above (`words` in
  `data/rooms/appeal.json`, with each word's thought points and tint).
- **How dwarves feel it** (doc 41): a full sleep, a meal or a board game in a sealed room
  leaves its word's thought: Horrid −6, Pleasant +4, Beautiful +8; Plain and outside rooms
  leave none, and the next of each replaces it. They last 24, 8 and 12 game hours
  (`room_appeal` in the mood section of `task_config.json`). A horrid room's thought says
  what helps: furnish the room and clear loose goods and stores out of it.
- **Where it shows:** the room window's banner and Appeal tab, and the thoughts on the
  character sheet and in the journal. A piece keeps its number ("+3") in Place, crafting
  and the compact panel; only rooms take a word.
- **Worked out when asked, never saved:** `RoomManager.room_appeal(room)` and
  `appeal_at(cell)` add it up on each call, so moving goods or furniture shows at once. A
  dwarf's room memories are saved with their mood.
- **Seen over the world** in the Appeal view (below).
- **Felt through tastes:** a dwarf's found tastes move the appeal they feel (doc 41
  "Tastes"). The Appeal tab tells a personal bedroom's owner's feeling under the note,
  when a taste moves it: "Birna loves the log bed, so to them it is Pleasant 8.5.", with a
  hay mark on the scale.

### Views

Appeal and X-ray are views: they change how the world looks, and other tools work while
they are on. Tools name themselves at the bottom (the tool bar); views name themselves at
the top.

**The view banner (2026-10-26, 272;
`scripts/ui/ViewBanner.gd`, on DockUI's toast layer):**
- **What it shows:** while a view is on, a slab at the top centre gives it one line. The
  line has the view's picture, its name, and what it shows with how to leave: "Appeal
  view · How each room feels to the dwarves · V or its button to leave".
- **With both views on,** each has its line.
- **The words** are each view's `view_name` and `view_line` in
  `data/ui/time_slice.json`, and the key comes from the input map.
- **While a tool works,** X-ray steps aside (the normal view) and its line goes. Appeal
  keeps the world dimmed, so its line stays.
- **The toasts** sit below it, and the mouse passes through.
- **Sizes** follow the screen's height, as the toasts' do.

**Later views** (temperature or light, say) follow the Appeal view's treatment:
- dim the world, and colour what counts (cool for bad, warm for good, grey for neutral);
- give every number a word;
- take a line in the banner.

### The Appeal view

A view toggle (2026-10-25; `AppealViewController`, a scene node), the first of the
dock's view group, before X-ray: the gold appeal star on the system tile, lit while on.
It shows room appeal over the world; it is a view, not a tool, so other tools work while
it is on. Its key is V (see "Keys").
- **Its scale** sits above its button. The owner chose that over a banner holding the
  scale at the top centre (2026-10-25).
- **The view banner** names the view at the top centre (since 2026-10-26; see "Views").
- **The world dims and greys.** A full-screen pass (`appeal_dim.gdshader`) keeps 35% of
  the world's colour at 62% brightness (`appeal` in `data/ui/time_slice.json`).
- **Floors take their room's word:** each sealed room's floor cells carry its word's tint
  (`tint` in `appeal.json`) at 60%: violet Horrid, stone Plain, amber Pleasant, gold
  Beautiful. The open ground stays dim, as only rooms count. A room whose floor is above
  the slice shows no tint, as its floor does not show.
- **What counts glows.** The pieces a room counts glow warm, and its loose goods and
  stocked storage cool, so what to move is plain to see. Turning the view off gives every
  piece its own look back.
- **The scale** rises above the dock while the view is on, as X-ray's options do (left of
  them when both are open): each word with its tint and range, highest first ("Beautiful
  16 and up" to "Horrid below 0"), and "Hover a room for its appeal. Click it for the
  room." It reads at the dock's own size.
- **Hover:** over a room's floor (or wall), a hover card names the room ("Birna's
  bedroom"), gives its word and number ("Plain · 4.5"), its parts as the Appeal tab lists
  them (six, then "and 3 more"), the share a large room counts and
  "Click for the room's appeal." No card over the interface or while a click tool works.
- **Click:** a click on a room's floor opens the room window on its Appeal tab. The object
  explorer offers the view its bare-terrain clicks as it offers zones theirs
  (`try_select_zone_at_screen`); a click on a piece still selects the piece.
- **Refresh:** the view works out every room in one pass (`RoomManager.all_room_appeals()`)
  when rooms change and once a second while on, so moved goods and new pieces show.
- **With X-ray and Slice:** its quads and dim draw on both cameras' layers, and picking
  follows the slice and X-ray's visible faces, so rooms below the surface show once sliced
  or X-rayed.
- **Never saved:** the view starts off in each session.

### Navigation Groups

| Group | Commands |
|---|---|
| Orders | Mine blocks, Chop trees, Clear stones, Harvest plants, Clear plants, Cancel orders |
| Zones | Storage; planned Farming and Animal pasture |
| Rooms | Direct room inspection toggle; active highlight, second click or Escape to exit |
| Construction | Build (stone, dirt, grass or logs: one rough stone, soil or log a block), Shapes (rectangles, circles and stairs in those materials), Copy and Blueprints (blueprint files to place and share) |
| Place | Finished furniture catalog: thumbnails, categories, live availability, repeated placement and Undo |
| Craft | Ten profession entries with Hearthblock icons; working Rudimentary recipes and explicitly marked specialist catalog previews |
| Colony | Its page: the settlement at a glance, with Dwarves, Labor, Settlement flag and planned Trade as entries |
| Inventory | Colony supplies with real thumbnails, live physical counts, Locate and Inspect storage |
| Menu | The game menu (also Esc): Resume, Save game, Load game…, New game…, Settings… and Exit game… |
| Development | Block inspector, World Build, Cave explorer, Dwarf tools, Water tools, Arrival status, Item stamper, Time & weather |

Farming and Animal pasture explain their planned state without dispatching tools.
Labor opens the roster's real Work view; Trade retains a clearly marked preview.
Inventory uses live
supplies. Development is the rightmost dock entry; cycling object locators have
been removed from the game.

### The Sky Dial

The upper right holds the Sky Dial (`scripts/ui/SkyDial.gd`, built by DockUI on its own
status layer). It shows a stone window under a hewn-oak lintel, looking at the sky, over a
plate (the owner's pick, 2026-10-26, 272).
- **The art** is Hearthblock. Its pieces are models in `tools/hearthblock/art/sky.mjs`,
  staged by `tools/voxel_assets/build.py sky` (staged only) and rendered by
  `tools/GenerateUiIcons.gd` to layers in `assets/ui/sky_dial/`.
  - Every layer shares one framing (`picture` in `data/ui/sky_dial.json`), so the dial
    stacks them as they are.
  - The sun, the moon and the clouds are sprites at the same scale, which the dial
    places.
  - Only the frame wears the outline.
- **The layers, back to front:**
  - **The sky:** night, dawn, day and dusk, each in four bands. It crossfades at the world's
    own anchors (`SkyController.current_event_hours()`): night to dawn from sunrise_start
    to sunrise, dawn to day until sunrise_end, day to dusk from sunset_start to sunset,
    and dusk to night until sunset_end. Grey weather swaps the day for a grey sky.
  - **The stars,** fading with the night, in clear weather.
  - **The sun and the moon** on one arc (`arc`). The sun rises on the left at sunrise
    and sets on the right at sunset; the moon crosses the night the same way. Grey weather
    hides the sun by day, except fog. The moon still shows behind a snowy night's clouds.
  - **The clouds** of the weather (`weather`, `clouds`). Storms have darker ones. They
    drift right with game time and come round again.
  - **Rain or snow,** falling through the opening with game time. It stops when the game
    is paused.
  - **The season's land:** far hills, then near hills with a pine and an oak. Spring has
    flowers and blossom, summer green, autumn orange leaves; winter is snow with bare
    branches. On a season's first day the new land comes in by its first sunrise, as the
    world's does (`WorldClock.season_visual_progress()`).
  - **Fog's mist** over the land, then the frame.
- **The plate,** under the window, in the HUD's faces:
  - the time in figures of one width, then the date ("Autumn 8");
  - the season bar: the year's four seasons, seven cells each in their colours
    (`seasons`). The current season is lit, its days still to come a little darker, and
    a copper notch marks today;
  - the days to the next season: "21 days to winter".
  - The narrowest dial (under 1200 px across) leaves the last line to its hover card, so
    the slice tower keeps its room under the clock on short screens.
- **Sizes:** the dial is 224, 204 or 184 px wide, and its height follows: the window's
  framing, then the plate.
- **Live state only:** all state comes from `WorldClock`, `SkyController` and
  `WeatherManager`. The dial keeps no timer, forecast or saved state of its own.

### Live Status HUD

The upper-right Sky Dial (see "The Sky Dial") reads `WorldClock`, `SkyController` and
`WeatherManager`. `SkyController` supplies the same seasonal rise/set times used by world
lighting. Hover or focus shows details; the old Clock window is removed.
Pause, 1× and 2× hang centred under the Sky Dial, so time is read and set in one
place. The view toggles Appeal, X-ray and Slice end the main dock as their own group, after
the usual group gap: plain dock icons with no captions, the same size as the others.
The slice tower rises above Slice, and the X-ray options to its left, only while that
view is on. All are Hearthblock icons (brass glyphs and blocks of ground) on the
system family tile (doc 259):
- Pause toggles pause and resume; play and fast resume at 1× and 2×. Space, 1 and 2 do
  the same (see "Keys").
- Hover and focus supply names, as for every dock icon. A view that is on keeps the
  copper frame and notch of an active dock command.
- Time buttons are 64, 56 or 48 px, following the dial's size. The dock sizes all
  thirteen icons together.
- The time controls, the tower and the X-ray options share the Sky Dial's status
  layer. Windows sit above them; ordinary windows make room for the dial and the time
  controls. Menus clear all of them.
- Only their own panels take the mouse: the space around them passes clicks and the
  wheel to the world (`TimeSliceHUD`, after doc 142).

### Keys

Keys the player may one day choose are input actions in `project.godot`'s `[input]`,
matched by the key's place on the keyboard, so they sit in the same place on every layout
(2026-10-25):

| Key | Action | Effect |
|---|---|---|
| Space | `time_pause` | Pause, or resume at the previous speed |
| 1 / 2 | `time_normal` / `time_fast` | Run at 1× / 2× |
| V | `view_appeal` | The Appeal view on or off |
| X | `view_xray` | X-ray on or off |
| `\`, `]` / `[`, `Ctrl+]` / `Ctrl+[` | `slice_toggle`, `slice_cell_up` / `_down`, `slice_single_up` / `_down` | Slice, and its steps (see "The Slice Tool") |
| Ctrl + Z | `tool_undo` | Take back the newest order, with or without a tool on (see "The tool bar") |

- **Each key does what its button does.** `TimeSliceHUD` handles Space, 1, 2, V and X;
  `SliceController` handles Slice's keys; `ToolBar` handles Ctrl + Z. They match exactly, so Ctrl + X is not X-ray.
- **Space is heard first** (`_input`), before a focused button can take it as a press, so
  it never presses again the last button clicked. A text field keeps it, and it does
  nothing while the clock is held: the game menu, loading.
- **The others come last** (`_unhandled_key_input`): a text field or a window's own keys
  take them first, and the game menu holds every key while it is open.
- **Hover cards name them:** the buttons' `key_action`s in `data/ui/time_slice.json`.
- **Fixed in code:** the camera's keys and mouse (doc 21), Esc's order (the game menu,
  above), R to turn a piece, and the tools' Shift, Alt and Ctrl. The tool bar names them.
- **Settings' Controls tab** lists them all (the Settings page, above).

### Panels (opened by `open_panel`)

| Panel | Contents |
|---|---|
| Place | **28 entries** from `data/ui/place_catalog.json`. Dining: Log Dining Table, Log stool, Log bench. Recreation: Board-game Table. Lighting: Log torch, Campfire. Room furnishings: Settlement flag, Log door (2 wide), Log door (3 wide), Double log door (4 wide), Rudimentary hearth, Log bed. Workshops: Crude workbench. Access: Rough wooden ladder, Log bridge, Log Fence Post, Log Gate. Water: Wet stone, Dry stone. Plants: blueberry, elderberry and wild-strawberry bushes, their three cuttings, and three wildflower shapes. Click an available tile to begin placing immediately; a dwarf fetches the packed item and installs it. Installed pieces retain **📤 Uninstall**. Crafting shows an unavailable dash until production exists. |

Action menus open 8 px above their dock button and keep clear of the compact panel and
the time and view controls (see "Sizes, states and menus" under "Floating Dock"). Place
and Inventory open as windows instead (see "The Place window" and "Colony Inventory"),
and saved or dragged window positions stay the player's.

The log torch takes its mounting height and facing from the selected wall cell.
Alt + wheel adjusts height one block at a time; aiming at the adjoining floor
starts at the design's default height, a low peg that fits a three-block tunnel,
and keeps R rotation available (doc 117). The hint
shows mount level and explains missing support, flame clearance or work access; the mount
level is also a stepper on the tool bar.
Workers install/remove within five blocks above a reachable work floor (doc 32); a
higher mount needs a raised work floor, as ladder rungs don't count. The whole light,
flame included, must fit in air below the visible slice, with wall support and no
overlap. There is no fixed room height, so a lower mount fits a lower ceiling.
When access is lost, the compact panel's status reads **Waiting for reachable work
position** in rust; a pending plan keeps its chosen position and goes on once access
returns. Digging out the floor below leaves a mounted light as it is, but losing the
wall block behind its bracket cancels a plan, or drops an installed light's packed
item at the mount. The mount level stays in the panel's data, off screen (see "No
Details button"). The saved `origin` is a fixed reference cell plus yaw: each
definition's `wall_mount.origin_offset_y` (2.5 for the log torch) puts the model base
above it, so the saved position never depends on the work floor (doc 129).
The hint is text the tool bar shows (`FurnitureGhostVisuals.hint_text`).
Installed torches are selected by visible model bounds, with terrain occlusion and
slices respected (`FurnitureWindow.try_select_at_screen`).

### Symbols and emoji

The UI shows no emoji: pictures are Hearthblock icons. Symbols the faces lack (▴ ▾ ◆ ◇ ✓
✕, and the camera's ✋ and 🗘) come from the symbol font shipped behind every face, so they
look the same on every machine (see "Type"). A new symbol must be in that font; `TypeTest`
checks every character in the UI's words.

## Stockpile Zone System

> **Current implementation.** Ground zones are built from `StockpileZoneComponent` (work
> source posting HAUL leases), `StockpileDesignationController` (marquee tool, per-zone
> overlay, zone window with Remove; zones stay click-selectable with the tool off, as mining
> zones do), the `StockpileManager` autoload (zone registry and aggregates) and the loose-item
> index on `ItemDropManager`. Filters are live (see Storage inspection above). Item
> definitions come from `ContentRegistry`, read through `ItemDropManager.get_item_def()`;
> there is no separate ItemRegistry autoload.
>
> **Capacity:** ground zones store **one item per tile, no stacking**: quantity is what you
> see and capacity is the number of empty cells. Per-item stack limits are reserved for
> future storage containers (barrels, chests, shelves).

A **stockpile zone** is a player-designated rectangular region of floor tiles that dwarves haul items into and workshops draw inputs from. Each zone has a **filter** that combines whole categories with exact item exceptions.

### Zone Designation Flow

1. Player selects **Zones → Storage** and drag-paints floor tiles.
2. A `StockpileZoneComponent` is created covering those tiles. A new zone accepts every
   category (`StockpileZoneComponent.DEFAULT_FILTER_TAGS`).
3. Clicking the zone opens its storage window, whose Filter tab edits the rules.

### Filter model

`StorageComponent` owns the rules as three arrays of stable strings:

| Field | Meaning |
|---|---|
| `filter_tags` | Accepted categories (`material_tags` such as `stockpile_wood`) |
| `filter_items` | Exact item keys accepted outside a selected category |
| `excluded_items` | Exact item keys refused inside a selected category |

`accepts_key(key)` refuses an excluded item, accepts an included item, and otherwise
accepts the item when any of its `material_tags` is in `filter_tags`. Capacity is a
separate check made when a deposit is reserved.

- Categories and exact items combine: All stone + Oak Log is a valid rule. Oak Log
  does not imply Oak Stave, acorns or other wood.
- A selected category also covers future items with its tag, including goods the
  colony has never gathered.
- Exceptions persist. Clicking a category replaces that category's exceptions.
- **All** restores every default category and clears exceptions; **None** empties all
  three arrays.
- Saves store `storage_filter = {tags, items, excluded_items}` on each zone.
  `restore_filter` assigns the arrays as saved, so explicit empty arrays mean
  accept nothing.
- A filter edit cancels HAUL bundles whose deliveries no longer match; a dwarf
  already carrying them drops the goods at its feet. Deliveries that still match
  continue. Goods already stored stay put, marked as awaiting relocation on their
  picture in Contents, and move only when another storage accepts them and has room.

### Filter categories

`data/ui/storage_filters.json` (read only by `UIRegistry`) lists the filter's groups and,
in order, its categories, each with its group and its picture, chosen from the item
pictures:

| Group | UI label | Tag | Picture |
|---|---|---|---|
| Materials | Stone | `stockpile_stone` | rough stone |
| Materials | Wood | `stockpile_wood` | oak log |
| Materials | Ores | `stockpile_ore` | iron ore |
| Materials | Gems | `stockpile_gem` | raw ruby |
| Materials | Soil | `stockpile_soil` | soil |
| Food & farming | Food | `stockpile_food` | apple |
| Food & farming | Drink | `stockpile_drink` | ale |
| Food & farming | Seeds & cuttings | `stockpile_seed` | oak acorn |
| Goods | Furniture | `stockpile_furniture` | bench |
| Goods | Currency | `stockpile_currency` | gold coin |
| Goods | Other goods | `stockpile_misc` | the stocks icon |

### The storage window

The window for a storage zone (`StorageInspectorPanel.gd`), after
Stonehearth's stockpile filter. Its band names the zone ("Storage Zone 2").
- **Filter:**
  - one line on what to do, then a row per group: the group's name with its All, Some
    or None state, and its categories as pictures, marked ✓ (all of it stored) or −
    (some), dimmed when none is;
  - a click on a picture stores the whole category or stops it, replacing its exceptions;
    a click on the group's state does the same for the whole group;
  - a click on a category's name ("Wood ▾") opens its exact goods under the group's row,
    where a click allows or refuses one good: the exceptions both ways.
- **Under the filter:** All and None, "Used 47 / 80 cells · 95 goods" with its bar, a line
  when goods await relocation or nothing is allowed, and Remove zone.
- **Contents:** the same grouped pictures, one per good and material, with their counts
  and a "!" on goods awaiting relocation; the name on hover. A click on a good opens its
  category in the filter.
- **Tabs:** Filter and Contents hang under the window's bottom edge.
- **Sizes** go by screen height: large from 1300 px (860 px across, as the concept),
  small below 650 px. The body keeps one height from tab to tab, as far as the room above
  the dock allows, and longer pages scroll.

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

## Toasts and the event log

**The event log** (`EventLog`, an autoload; doc 13) keeps what happens in the colony:
arrivals, caverns found, colony news and warnings. Each entry has its kind, its words
(and a second line for what to do), its picture, the colony's time, and where Locate
goes: a cell, or the dwarves concerned.
- **What lands:**
  - arrivals, from WorldEventDirector once a group has finished arriving ("3 deer have
    arrived from the east."), with the species' head and the place inland where the
    group heads;
  - caverns the colony mines into ("Cavern discovered. Bring light to explore it."),
    from InteriorTracker's `cavern_found`; the surface caves a new world reveals are
    not news;
  - colony news: the founding ("Brunhald is founded.", how many dwarves arrived with the
    flag, and the flag's picture and place), a finished promotion ("Guntris is now a
    Miner.") with the profession's icon, and each new season ("Winter has come."), but not
    the clock being restored;
  - warnings: dwarves who cannot find reachable food (checked once a second, the words
    following the count), and rising water spilling onto dry ground (WaterManager's
    `flood_warning`, at most once a minute).
- **Warnings stay pinned** by their key until resolved: the food warning once no dwarf
  is short, rising water once it has not spilled for `flood_hold_hours` (3 in-game
  hours). Raising a standing warning again updates its words and place without a new
  toast. A resolved warning stays in its day, in its past words when it was raised with
  them (`past`: "2 dwarves could not find reachable food.", "Rising water spilled onto
  dry ground.").
- **Kept:** `keep_days` (10) of entries, and pinned warnings however old, at most 200. The
  log is saved with the colony (the `events` section) and cleared by New game. Nothing
  lands while a save loads.
- **Not logged:** the player's own actions. Saving…, Game saved., Autosaved., loads, the
  settlement flag's status, slice hints and DEV messages stay toasts
  (`DockUI.show_persistence_status()`).
- `data/events/event_log.json` holds the days kept, the toast limit and times, the
  checks, and each kind's picture. An arrival names its species' picture in
  `arrivals.json`.

**The Events window** (`scripts/ui/EventsPanel.gd`, registered by DockUI as `events`) is
the log as a window with the others: people family, opening where windows open (24, 76)
and remembering its place. The owner chose a window over a column under the Sky Dial,
which fills the right edge, and over a shelf above the dock, which closes on a click in
the world: a window stays open while Locate visits one entry after another.
- **From the bell:** pressing it opens or closes Events. It closes an open dock menu but
  leaves the active tool alone, so the log can be read beside the work.
- The band reads Events, then "Newest first. Warnings stay at the top until they are
  resolved." (hidden on small screens).
- **Needs attention:** each standing warning, newest first, on a card with the rust band
  (`UITheme.warning_frame()`): what is wrong, what to do, "Since 19:23", and Locate.
- **The days**, newest first: "Today · Autumn, day 7", "Yesterday · Autumn, day 6", then
  "Autumn, day 5". Each entry has its picture on the people tile, its words, its time, a
  hay New tag until seen, and Locate where it has a place or dwarves. A resolved warning
  stays in its day, greyed, with a moss "Resolved at 22:35" tag and no Locate.
- **Locate** moves the view and leaves Events open, so the next entry is one click away:
  to the entry's cell, or to its dwarves where they are now, one by one on each press (the
  hungry dwarves). Locate shows only while one of its dwarves is still in the colony or
  the entry has a place.
- **Seen.** Opening Events marks the log seen; what came since the last look keeps its
  New tag while the window stays open, and what lands while it is open counts as seen at
  once.
- **Rebuilding:** the list is rebuilt only when what it shows changes (the entries, what
  counts as new, the day or the size), and keeps its scroll when it is.
- **Sizes** go by screen height, as the other windows': large from 1300 px (900 px wide,
  as the concept), medium 640 and small 480, where Locate is its pin alone. The list is as
  tall as its entries, as far as the room above the dock allows; a longer log scrolls.
- `WorldClock.date_at()` and `time_string_at()` turn an entry's time (elapsed days) back
  into its season, day and clock.

**The bell** is the dock's Events entry, after Inventory, on the people tile
(`DockIconButton.show_count()`):
- a hay count of the entries not yet seen, capped at 99+;
- rust while any warning stands, showing "!" once everything is read;
- nothing when everything is read and no warning stands.

Its hover card names the count on its tag: "3 new events", or "A warning stands" (see
"Counts").

**Toasts** (`scripts/ui/ToastStack.gd`, on DockUI's toast layer 24) show each entry the
moment it lands, and the player's own messages.
- Up to three at the top centre, newest on top; the oldest leaves first. Events stay
  4 s, warnings 6 s and the player's messages 2.5 s (errors 4.5 s), then fade. The mouse
  passes through.
- While a view is on, they sit below the view banner (see "Views").
- Each is the dark slab with a thin band in its tone (`UITheme.toast_frame()`): the
  people family for an event, rust for a warning or an error, moss for the player's own
  message. An event's picture sits on the people tile, then its words and second line.
- Sizes follow the screen height, as the windows' do: large from 1300 px (760 px wide,
  20 px words), small below 650.

## Labor Assignment — live first pass (2026-10-09)

**Colony → Labor** opens the Work view of Colony Dwarves. Haul, Gather, Mine,
Build and Craft checkboxes control each real dwarf; Craft remains Worker-only (its box is
disabled for other professions and keeps its setting for a return to Worker).
Transport inside an allowed job and automatic rest are independent of those
checkboxes. Overview retains its activity/cargo/rest display. **Change profession**
on the character sheet's Profession tab opens a career map with immediate Worker/Miner changes,
Carpenter promotion through physical kit collection, retained experience and
clearly marked future roles. Each career shows its profession's Hearthblock icon,
dimmed while the career is planned. The career map is the Professions window
(`DwarfProfessionPanel`, people family), titled with its dwarf (docs 96, 101):
- **The map.** Tiles from `promotion_screen` in professions.json, each marked Current,
  Available, Planned or Collecting tool. A line shows `promotes_from` ancestry, not who
  makes a tool. The map and the descriptions scroll on their own.
- **The appointment card.** Requirements; for a tool career, the starter tool with its
  available stock and maker (Worker · crude workbench), then the collection message and
  Cancel promotion, or why it waits (no spare tool, the dwarf asleep); the profession's
  next planned tool, pointing to the Equipment tab; retained experience and, for the
  Miner, the level rewards and bar.
- **Acting.** Promote, Resume and Return to Worker work while paused; a tool collection
  starts when the clock runs. A planned career reads "Not yet available".
- **Closing.** The window closes when its dwarf leaves the roster or Colony Dwarves
  closes. Esc closes it unless a dock menu is open, and Back to colony returns to the
  dwarf in Colony Dwarves. The rules behind it are in doc 41, Profession System.

### Equipment and promotion feedback — live (2026-10-09)

The character sheet's **Equipment** tab shows the actual owned tool, picture, tier,
materials and benefit. Carpenter's iron saw and Miner's iron pickaxe are clearly
marked planned/not craftable, with their future maker and assignment flow. Colony
Dwarves' Details card opens the sheet. Completed specialist
promotions play a short chime through the existing Work audio controls, including
immediate Miner promotion while paused, and land in the event log as colony news.
Request/cancel/demotion/load are silent (doc 102).
`DwarfInspection.equipment_details()` builds the tab from the equipped item
(`DwarfEquipment`), that item's `equipment` block (tier, materials, benefit) and the
profession's `equipment_preview` in professions.json; `DwarfEquipmentPanel` draws it.
The tab is read-only: a planned upgrade stays text, never an item id or an equip action,
until its goods and recipe exist. While a promotion is pending it shows the collection
message.

### Historical extended labor proposal (not implemented)

The implemented **Colony → Dwarves** roster shows current work and rest, with
selection and Locate actions. The assignment controls below remain future design.

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
[12:04]  ⛏  Urist mines Stone (Level 7)       ✓ done
[12:05]  📦  Bomrek hauls Stone × 8 to Stockpile  ⟳ in progress
[12:05]  🍺  Dastot brews Longbeard Ale            ⟳ in progress
```

---

*Prev: [22_mouse_input.md](./22_mouse_input.md) | Next: [31_task_system.md](../30_simulation_systems/31_task_system.md)*
