# 139 — Remaining menu artwork and navigation plan

Status: **approved and implemented** — 2026-10-12. The plan below records the
approved direction; [140 — Delivery](140_remaining_illustrated_menus.md) records
the completed work, native verification and the browser-search clarification.

## Direction

Continue the approved Hearth & iron language: full-color, hand-painted objects,
clear silhouettes, charcoal iron frames, aged copper edges, timber, stone and
warm ivory. Navigation uses artwork with names and explanations on hover or
keyboard focus. Actual information—item names, counts, costs, work status and
descriptions—remains readable in the destination panels.

The main dock and the Orders, Zones and Construction menus are already done.
The remaining dock entries are Rooms, Place, Craft, Colony, Inventory, Menu and
Development. They do not all need an extra popup: Place and Inventory already
open browsers directly, while Rooms starts room inspection. Keep those flows.

## Shared interaction rules

- Illustrated submenus attach to the parent dock icon. Use 64 px desktop / 56 px
  compact buttons, wrapping before reducing legibility. Ten profession buttons
  fit one row when space allows and two balanced rows otherwise.
- Reuse the current ivory hover/focus border and copper active frame/notch.
  Hover panels stay inside the viewport and disappear on close or navigation.
- Keyboard navigation reaches every entry and its explanation. Back and Escape
  behave consistently, with active world tools handled before panel dismissal.
- Preserve valid selection, scroll and keyboard focus during live stock updates.
- Do not turn a selected catalog filter into a new world action. Category art
  filters the existing browser; item actions keep their current behavior.
- Reuse category art when the meaning is the same. Distinguish similar commands
  through the subject: Storage zone = marked ground with supplies; placeable
  Storage = container; Inventory = supply chest; Craft = tools/workbench.

Availability needs three distinct presentations:

| State | Presentation | Interaction |
|---|---|---|
| Live | Full-color icon | Existing action or browser |
| Planned | Muted art and lock; explicit hover explanation | Explain the future feature; preserve an existing informational preview when one exists; never dispatch unavailable gameplay |
| DEV preview | Full-color icon and flask; explicit hover explanation | Existing usable preview, such as floor designation and DEV Build |

Craft's planned profession pages are already browsable. Do not copy Zones'
no-dispatch behavior onto those entries and make their pages inaccessible.
The Miner is playable even though its crafting catalog is a preview. Carpenter
promotion exists even though specialist production is not enabled. The badge
and explanation describe the destination's capability, not the whole profession.

## 1. Craft — next implementation

Replace the ten labeled profession tiles with a compact illustrated chooser.
Keep their current order and existing recipe-browser destinations.

| Entry | Proposed subject |
|---|---|
| Rudimentary | Bark-covered stump, simple stone hammer and bound starter tools |
| Carpenter | Wooden hand plane and pale curled shaving |
| Stonemason | Mason's mallet, chisel and dressed stone corner |
| Blacksmith | Tongs holding a glowing ingot above an anvil |
| Weaponsmith | Unadorned sword blade and forging hammer |
| Armorsmith | Riveted helmet and steel breastplate |
| Farmer | Stone hoe with leafy crop and earth |
| Hunter | Stone-tipped spear and animal track |
| Miner | Pickaxe beside an ore-bearing rock sample |
| Brewer | Wooden brewing tub, stirring paddle and grain |

Rudimentary still opens the working Worker recipes. Specialist entries retain
their real preview/live status. Do not imply that new tools, recipes, workshops
or profession abilities have been implemented by replacing their icons.

Keep the recent recipe browser: search, grouped recipe thumbnails, Recipes /
Orders, selected-item details, quantity/stock modes, material choices, Queue and
Place. Preserve its existing actual-item thumbnails rather than repainting every
craftable item in this pass. Crafters returns to the illustrated chooser.

## 2. Place — illustrated categories in the existing browser

Keep one click on Place opening the catalog. Replace its category navigation
with a compact illustrated strip; the item grid remains the next interaction.

| Current category | Proposed subject |
|---|---|
| All | Open sample tray containing several different objects |
| Dining | Small wooden table with a stool and bowl |
| Storage | Timber shelf with a barrel and crate |
| Lighting | Wall torch in a simple bracket |
| Rooms | Bed, door and small hearth; rename the visible category **Room furnishings** to distinguish it from room inspection |
| Workshops | Crude workbench with a tool laid on top |
| Plants | Root-wrapped shrub with a small cutting |
| Access | Short ladder beside a timber bridge segment |
| Water | Existing wet/dry stone pair with a small water motif |

Show the current category name in the browser heading and on hover, while
keeping the category buttons free of permanent captions. Keep search, stock
badges, availability filtering and selected-item information. Preserve direct
tile-to-placement, rotation, repeat placement, Move and Undo behavior.

At compact sizes, wrap the strip or use the existing labeled category dropdown;
decide from native layout checks, preserving useful item-grid space. Do not add
another mandatory click through a dock popup just to reach the same categories.

## 3. Colony — four illustrated entry points

| Entry | Proposed subject | Destination |
|---|---|---|
| Dwarves | Two distinct dwarf portraits | Existing colony roster |
| Settlement flag | Deepdraft's cloth banner and pole | Settlement founding before establishment; locate/inspect the existing flag afterward |
| Labor | Work ledger with a pickaxe and small assignment markers | Existing roster Work view |
| Trade | Balance scales, pouch and traded goods | Clearly marked planned trade preview |

The flag entry should give useful feedback after founding. Installed flags can
be located/inspected and moved through their normal furniture actions. A packed
or moving flag should explain its actual state and direct the player to its
existing recovery/placement flow; never grant a second founding flag.

The larger dwarf-screen redesign remains a separate milestone under
[131 — Stage 3](131_dwarf_food_and_dining.md). This pass supplies coherent entry
points, not invented attributes or new tab contents. Keep the eventual shared
identity header and Overview / Morale / Traits / Equipment / Profession plan.

## 4. Menu and Development — finish separating player and test controls

### Player Menu

Use three illustrated entries:

| Entry | Proposed subject |
|---|---|
| Save / Load | Bound settlement ledger with metal clasp |
| Clock & weather | Sundial with sun and small cloud |
| Slice view | Mountain cutaway with one highlighted horizontal layer |

Save / Load opens a small child row for Save Game, Load Game and Load Autosave.
Use the same ledger silhouette with clearly different directional/history
motifs: into the ledger, out of the ledger, and ledger plus clock. Hover text
must state the action explicitly. Preserve the real save/load callbacks and
success/failure feedback; artwork must not introduce a new persistence policy.

Move the current World Build diagnostics entry to Development. The player
clock panel keeps time, season and weather information. Move its +1 Hour,
+1 Season and weather-cycling test actions into Development's Time & weather
panel; keep normal pause/speed controls where they already are.

### Development

Keep it at the far right, visually separated from player commands. Arrange nine
icons in small groups, wrapping as necessary:

| Group | Entry | Proposed subject |
|---|---|---|
| Inspect | Block inspector | Magnifying lens over a small voxel cube |
| Inspect | World Build | Mountain map with measuring calipers |
| Inspect | Cave explorer | Rock cross-section with a lantern-lit hollow |
| Simulation | Dwarf tools | Dwarf bust beside a small gear |
| Simulation | Water tools | Channel cross-section, water and gauge |
| Simulation | Arrival status | Trail entering a marked boundary |
| Test actions | Spawn Drops | Open supply crate with a small plus marker |
| Test actions | Spawn Furniture | Packed furniture crate with a small plus marker |
| Test actions | Time & weather | Hourglass, cloud and adjustment cog |

Use illustrations for navigation; retain precise text and values inside the
development panels. Preserve existing operations and do not restore any of the
removed DEV: Next buttons. Convert touched save/development routing to stable
action IDs where it currently depends on visible label strings, so caption and
tooltip changes cannot break actions.

## 5. Inventory — a matching category family

Continue opening the inventory browser directly. Keep actual item thumbnails,
search, quantities, reservation/availability breakdowns, Locate and Inspect
storage. Adapt the category navigation after the Place strip has been checked.

Reuse All, Storage and Lighting art where appropriate. Add Materials (log,
stone and ingot), Furniture (chair and bed), Tools (tool roll), Food & seeds
(fruit with a seed pouch), Drink (mug and stoppered jug), and Other (mixed-goods
pouch). These illustrate existing categories; they do not add new edible food
or production systems. Keep empty-category behavior and ownership accounting.

## 6. Rooms — focused polish, no extra designation menu

Keep the dock command's direct room-selection behavior. Rooms are identified
from actual enclosures and contents; do not add pretend bedroom/tavern/warehouse
designation buttons as part of an art pass.

Polish the existing inspector with small consistent symbols alongside the real
bed, flooring, appeal, temperature and lighting information. Keep Overview and
Details readable, including numeric values and explanations. Reuse suitable
furnishing/light art and the established small UI symbols before commissioning
more large illustrations. This is the final, lightest phase.

## Delivery order and checks

Recommended sequence: **Craft → Place → Colony → Menu + Development →
Inventory → Rooms**. Each phase is a separate reviewable change: art/contact
sheet, integration into existing controls, native preview, then documentation.
The delivered assets and implementation are recorded in milestone 140.

For each phase, check the actual mouse/keyboard flow and hover readability at
960×540, 1280×720 and 2560×1440. Verify active indicators, Back/Escape, inspector
overlap, hidden-tooltip cleanup and that icons do not leak clicks into the world.
Category-browser changes must preserve stock updates, selection, focus, scroll
and existing action availability. Use relevant existing fixtures, rather than
adding tests that merely repeat art coordinates.

Continue using JSON definitions through UIRegistry, shared DockIconButton /
UITheme presentation and existing simulation owners. Keep generated source
sheets in the project, record their prompts, and use runtime atlas regions.

## Inspection sources

Current `data/ui/dock.json`, `place_catalog.json`, `inventory_catalog.json`,
`DockUI`, `RoomInspectorPanel`, the recent Craft/Place/Inventory docs and
milestones 131, 135–138 informed this plan. Read-only inspection identified the
remaining World Build and clock test controls in player-facing menus. No
external game assets, new runtime values or simulation behavior were introduced.
