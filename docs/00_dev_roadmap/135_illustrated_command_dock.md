# 135 — Illustrated command dock

Implemented 2026-10-12 after approval of the Hearth & iron icon concept.

## Player experience

The bottom command dock now uses the approved full-color illustrated artwork:
Orders, Zones, Rooms, Construction, Place, Craft, Colony, Inventory, Menu, and
Development. Permanent captions are removed. Hover or keyboard focus reveals
the command name and a short description above the button. Clicking dismisses
the description. Moving away, losing focus, hiding, or resizing also dismisses it.

The centered charcoal rail has square buttons: 72 pixels on desktop widths of
1200 or more, 56 pixels on compact windows, with further fitting for narrower
viewports. Extra gaps separate Menu and Development. The open command has a
copper outline and a solid bottom notch; hover/focus has a lighter thin outline.
Authored colors remain intact instead of tinting the pictures copper.

Existing command dispatch, submenus, tool ownership, and inspector behavior stay
with their existing owners. The broader dwarf character-screen overhaul remains
separate work.

## Art and ownership

- `assets/ui/dock/hearth_iron_atlas.png` is the exact approved concept image,
  generated with the built-in image-generation tool. It is retained intact as the
  source atlas; only the ten framed illustration regions are displayed. Captions,
  title, and example toolbar in the source are never displayed in-game.
- The generation brief was original dwarven **Hearth & iron** command art:
  charcoal, aged copper, warm timber, stone and ivory; hand-painted faceted
  objects with strong silhouettes. Subjects are a pickaxe/work order, surveyed
  ground, cutaway room, masonry/trowel, chair/placement arrow, workbench/tools,
  dwarf portrait, supply chest, cog and development flask. The reference supplied
  the idea of readable illustrated commands, not copied Stonehearth assets.
- `data/ui/dock.json` owns labels, descriptions, ordering, atlas regions and
  `separator_before`. `UIRegistry.get_dock_icon()` constructs runtime
  `AtlasTexture` regions from that data, sharing the source texture.
- `DockIconButton.gd` owns hover/focus information and the drawn selection frame.
  Information sits on a mouse-transparent CanvasLayer above windows.
- `DockUI` owns responsive layout and existing action routing; `UITheme` owns
  the rail/tooltip palette and styles. No `.tres`, hand-edited imports, autoload,
  save schema, or simulation changes are required.

## Verification

`tools/DockArtPreview.gd -- --capture` extends the existing dwarf inspector
fixture and exercises actual GUI clicks for all ten commands. It verifies open,
close and selected states, hover/focus descriptions, square icon sizing,
viewport bounds and menu clearance at 960×540, 1280×720 and 2560×1440.
Native captures were visually reviewed for region alignment and small-size
readability. Player saves and layout preferences are not written by the fixture.

Captures and logs: `tmp/dock_art_20261012/`.

Restart Play to load the new artwork and dock code.

Follow-up: [136 — Illustrated Orders](136_illustrated_orders_plan.md) reuses
`DockIconButton.setup()` for the six Orders commands. Native main-dock and
dwarf-inspector regression checks still pass after the shared setup change.
