# 51 — Hearth & iron: dwarf inspection

Implemented 2026-10-05 as the first step of the approved UI concept. The player
chose Hearth & iron and asked to begin with dwarf selection and inspection.

## Player experience

- Click a visible dwarf to open the shared context inspector. Its portrait uses
  that dwarf's head, hair, beard, skin and clothing. Name and profession are live
  identity fields, not sample values.
- **Overview** shows current activity, destination, rest, carried goods and carry
  load. Pickup, delivery, set-down, installation, removal, mining, chopping,
  walking, idle and sleep have distinct descriptions. Rest is the existing sleep
  stat; sleeping also reports remaining game hours under **Details**.
- Produce displays both quantity and physical crate count. Carry load uses the
  existing JSON capacity/cost rules: a crate pays its cost once regardless of fill.
- **Details** shows current location, an explanation of the current activity and
  each generated trait's name and description. A visible note states that trait
  effects are not active yet. Unimplemented needs and activity history are not
  presented as live systems.
- **Locate** centers the RTS camera while retaining zoom and orbit. **Follow**
  tracks the dwarf and becomes **Stop following**. Keyboard/edge pan, middle-mouse
  pan, an engaged right-mouse orbit, or world zoom stops following. Scrolling the
  panel does not zoom the world or stop following.
- Empty ground, Escape, closing, another selection, slice concealment, or removal
  clears selection and ends follow. Active designation/placement tools retain
  their click and Escape behavior.
- The inspector remains draggable and remembers the shared explorer's position.
  Without a remembered position it first opens on the right. At smaller window
  heights the middle content scrolls while identity and action buttons remain
  visible. Overview's key fields fit together at 1280×720.

## Ownership

`DwarfDirector` joins `object_explorer_provider`; actor **node identity** is the
selection key so a loaded roster member with a reused numeric ID cannot silently
replace a selected dwarf. Picking uses visible mesh triangles and the existing
terrain/slice limits. Visual bounds exclude hidden work tools. Logical collision
and navigation remain 1×1×3.

`DwarfInspection` is a read-only adapter for the existing actor, TaskManager,
storage and item definitions. It neither assigns nor cancels work, consumes goods,
nor changes reservations. The selected snapshot refreshes every 0.15 seconds.
The outline tracks actor translation each frame, with its shape refreshed alongside
the snapshot.

`DwarfInspectorPanel` supplies the new content. Its portrait is a static copy of
visual parts in an isolated SubViewport on the existing UI CanvasLayer. It is
rendered once per selection, never registered as a second actor, and released
when selection ends.

The [Colony roster](57_colony_dwarf_roster.md) now uses the same `DwarfPortrait`
helper for its smaller static portraits and opens this inspector on row selection.
Overview and personal details retain a single selection and data source.

Details now shows each trait's name and wrapped description from DwarfAssets,
with an explicit note that trait effects are not active yet. The current
sleep-lite executor still uses six hours for every dwarf; Light Sleeper's
authored seven-hour duration is a future effect, not a live modifier. Trait
controls are reused across activity refreshes, with an empty-state message for
dwarves without traits and a description fallback for missing definitions.

`UITheme` owns the copper, charcoal and warm text palette and all styleboxes.
Stage 1 initially applied this style only to dwarf inspection. The approved
[stage 2](52_hearth_iron_shared_theme.md) now shares it across all existing windows
and the dock. `UIWindow.keep_body_on_screen` independently preserves the dwarf
inspector's responsive placement without changing other windows' drag behavior.

Camera follow is transient. No scene wiring, autoload, global script class,
JSON schema or save schema was added.

## Validation

- `DwarfInspectorTest.gd`: actual viewport clicks, overlapping actors, terrain
  occlusion, tool/slice exclusion, UI click isolation, portrait reuse, live crate
  pickup/haul/deposit and packed furniture fetch/installation, unchanged inventory
  and reservations, sleep, Locate/Follow/manual navigation and cleanup.
- Native Godot layout checks at 960×540, 1280×720 and 1920×1080. Small layouts
  retain action controls and scroll their contents.
- `ObjectExplorerTest.gd`: existing tree rows, furniture/item actions, picking,
  seasonal replacement and input behavior.
- `SaveManagerRoundTripTest.gd`: full main scene and nonempty colony round trips,
  independent autosave and backup recovery, with isolated test storage.
- Native review captures: `tmp/dwarf_inspector_review/dwarf_inspector_1280.png`,
  `dwarf_inspector_960.png`, and `dwarf_details_960.png`.

## Next stages

The player approved the inspector and shared-theme stage.
[Stage 3 navigation and layout](53_hearth_iron_navigation.md) is implemented.
Tool feedback and shortcuts follow. Bed use and dining AI remain deferred as requested.
