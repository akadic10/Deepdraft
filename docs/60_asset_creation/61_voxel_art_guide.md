# 61 — Voxel art authoring guide

How to build a model in the Hearthblock style. The look is defined in
[64 — Hearthblock art direction](64_hearthblock_art_direction.md). Renderer, pipeline
and acceptance rules are in [63 — Technical art standard](63_shared_art_standard.md).
Dwarf appearance pools and runtime tinting are in
[41b](../40_economy_colony/41b_dwarf_appearance_glb.md).

Every production model is built on the 1:16 grid: one cell is 1/16 of a world block on
each axis (0.0625 Godot units).

## Where things live

| Path | What it holds |
| --- | --- |
| `tools/hearthblock/art/proposal.mjs` | The approved proposal models, verbatim, and the shared `Vox` cell vocabulary and palette |
| `tools/hearthblock/art/tier1.mjs` | Tier 1 · Axe-Hewn furniture, hearth and flag |
| `tools/hearthblock/art/tier2.mjs` | Tier 2 · the Carpenter's plank pieces (doc 308): `plankTable()`, `plankBench()`, `plankGameTable()`, `plankPallet()`, `plankToolRack()`, `plankCrate()`, `plankFoodShelf()`, the frame the two tables share (`plankFrame()`) and the sawn-board helpers every plank piece uses (`board`, `sawnEndX`/`sawnEndZ`, `strokesX`/`strokesZ`, `faceStrokes`, `peg`, `hookPegs`, `binSide`, `binPost`) |
| `tools/voxel_assets/hearthblock_goods.py` | Stockpile goods, drawn in Python: mined goods, logs, planks (`plank()`, doc 308), crates (produce, seeds, cuttings, the log torches' own, `torches()`, and the copper nails' own, `nails()`, doc 62), the copper bar, and the tool goods (`starter()`: the Ranger's kit, the stone hammer and the Blacksmith's copper pick, saw, chisel and hoe, doc 306) |
| `tools/hearthblock/art/dwarves.mjs` | Every dwarf part: heads, eyes, body, mittens and cuffs, boots, hair, beards, brows, scars, trade hats, work tools |
| `tools/hearthblock/art/wildlife.mjs` | Rabbit, deer, wolf and ducks |
| `tools/hearthblock/art/icons.mjs` | UI icon models; the `icons` family in `build.py` is staged only, and `tools/GenerateUiIcons.gd` renders it to PNGs (see UI icons below) |
| `tools/hearthblock/art/sky.mjs` | The Sky Dial's pieces (doc 23, "The Sky Dial"); the `sky` family in `build.py` is staged only, and `tools/GenerateUiIcons.gd` renders it to the dial's layers (see The Sky Dial below) |
| `tools/hearthblock/art/export.mjs`, `write_data.py` | Export the `.mjs` models to `tools/art_data/voxel_hearthblock.json` |
| `tools/voxel_assets/hearthblock.py` | Replays those operations for the Python builders |
| `tools/voxel_assets/build.py` | Stages, checks and installs a family |
| `tools/voxel_assets/<family>.py` | Family builders: `trees`, `plants`, `rocks`, `crops`, `dwarves`, `presentation`, `wildlife`, `furniture`, `items` (+ `hearthblock_goods`), `construction` |
| `tools/voxel_glb.py`, `tools/voxel_shadow.py` | Greedy mesher with opt-in baked occlusion, GLB writer, shadow proxies |
| `tools/art_data/voxel_*.json` | Family profiles and palettes; installed manifests in `tools/art_data/voxel_manifests/` |
| `tools/art_data/studies/hearthblock_furniture_tiers.json` | Tier 1 and Tier 2 furniture study layouts (never delete) |
| `tools/art_data/studies/iron_work_tools.mjs` | The iron felling axe and pickaxe, drawn for the Blacksmith's upgrade (doc 301); nothing builds it |

Art data sits under `tools/` (not `data/`) because no game script reads it; the export preset excludes `tools/*`,
so it does not ship.

## Cell vocabulary

Models are lists of cell operations on integer coordinates, Y up:
- `box(x0,x1, y0,y1, z0,z1, role)` fills a block of cells;
- `cut(..., n, role)` makes a notched box whose vertical edges are clipped by `n`
  cells (`cutX` and `cutZ` clip the edges that run along X or Z);
- `paint` recolours existing cells only;
- `ring` draws growth rings on a cut end;
- `air` (a box with no role) carves cells away;
- `mirror_x` builds one side and mirrors it.

Python builders use the same ideas (`notched`, `paint` and `carve` in
`hearthblock_goods.py`, `square_clump` in `plants.py`, square crowns and `square_pine`
in `trees.py`).

Stone furniture has helpers of its own in `tier1.mjs` ([64](64_hearthblock_art_direction.md),
"Stone is drawn as wood is"):
- `stoneBlock` is a box with its corners cut square (two `box` operations), and `stoneTier` one
  weathered tier of a boulder;
- `workedStone` is one stone with a fresh top inside a ledge of skin, a dark foot or underside;
- `knockOff` carves a piece away and paints the scar fresh.

The file holds operations, not cells, so a helper may only call `box`, `cut`, `paint`,
`ring` and `air`.

Roles are semantic names (`wood`, `bark`, `grain`, `rope`, `hay`, `stone`, `iron`,
`tunic`, `skin` and so on), not colours. The palette maps them to colours:
- Wood roles map to the existing source palettes in
  `data/materials/craft_materials.json` → `source_palettes` (`hand_hewn_timber` and
  `oak_log`; `starter_tool` for the starter tools' hafts), so `CraftMaterials` recolours
  them for pine, oak, juniper and apple.
- Skin, hair and eye roles are tinted per dwarf.
- The tunic and cuffs are recoloured to the dwarf's clothing colour.
- Everything else is a fixed colour.

Keep wood swatches for wood only, or hay and stone would recolour with the wood. Stone
furniture uses the worked-stone roles (`stone_skin`, `stone_skin_top`, `stone_skin_dark`,
`stone_fresh`, `stone_fresh_dark` and `stone_cleft`; doc 301): the mason's bench, the stone
stool and the basic smelter. The stone heads of the dwarves' hand tools use them too (doc
301), and the starter tools on the ground carry the same colours (`hearthblock_goods.STONE`).

The log stool is two models. `log_stool` (`tier1.mjs`) is the furniture and what the Place,
Move and Pack up icons replay. `stool` (`proposal.mjs`) builds no piece: stored logs replay it
on its side (`hearthblock_goods.log_roles`), so changing it changes every log.

A plank (`hearthblock_goods.plank`, doc 308) is one thick squared board, 10 by 4 by 14 cells,
lying the way its log lies and as long: a pale sawn face with three saw strokes across it that
stop short of its edges, square ends that show the log's ring, and no bark, so it is never
taken for a log or for one of the camp's split halves. It is built in each wood's own colours.
`ItemArtTest` keeps it flat inside a log's stockpile slot.

## Workflow

1. **Edit the source.** Edit a `.mjs` file under `tools/hearthblock/art/`, then run
   `python3 tools/hearthblock/art/write_data.py` (it needs Node). Or edit a Python
   builder in `tools/voxel_assets/`.
   Each model's row in `write_data.py` names its palette and may `drop` roles or add
   `extra` operations: the log torch stays verbatim in `proposal.mjs`, and its row drops the
   drawn flame and adds the stick's foot.
2. **Stage.** Run `python3 tools/voxel_assets/build.py FAMILY`. `--only <path substring>`
   stages a quick preview, but a partial family can't be installed.
3. **Review the gallery.** Run `tools/voxel_assets/Gallery.gd` with `--family=FAMILY`
   and `--output=res://tmp/<label>/` through `tools/run_offscreen.py` (see "Running a
   script that draws"), then look at the captures. It writes
   `gallery.json` with the exact hashes it reviewed. The family galleries
   (`FurnitureGallery`, `DwarfGallery`, `WildlifeGallery`, `TreeGallery`, `PlantGallery`,
   `ItemGallery`) show contact sheets.
4. **Install.** Run `build.py FAMILY --install --review <gallery.json>`, then import with
   `python3 tools/import_assets.py`.
5. **Verify.** Run `build.py FAMILY --check` (byte-identical regeneration) and the
   Python tests (`python3 -m unittest` in `tools/voxel_assets`). Then run the family's
   Godot art and gameplay tests: `python3 tools/run_job_reliability.py --area art` runs the art
   tests (`DwarfArtTest`, `WildlifeArtTest`, `ItemArtTest`, `FurnitureArtTest`,
   `FireArtTest`, `GemDropArtTest`, `GroundStoneArtTest`, `SurfaceVegetationArtTest` and
   `VoxelPresentationTest`).
6. **Check in the game.** Run the game and look at the model in the main world, which
   always uses Hearthblock lighting.
7. **Re-render the menu pictures** that show the model with
   `tools/FurnitureCatalogThumbnails.gd` or `tools/InventoryCatalogThumbnails.gd`, through
   `tools/run_offscreen.py`. UI icons
   that replay the model (the dwarf head, the log
   stool, the packed crate) also need `tools/GenerateUiIcons.gd`. The Worker icon replays
   the felling axe and the mining pickaxe.
   Zones' Animal pasture icon replays the fence post and rails. The dock's Build icon draws
   its own peeled log (`logCube` in `icons.mjs`), so change it by hand when built logs change.
   `FurnitureCatalogThumbnails.gd` takes `--only=<names>` (the keys' last part, such as
   `log_bed`) and `--out=<folder>`, so a capture can be checked in `tmp/` before it
   replaces a picture in use (doc 172).

## UI icons

UI icons (doc 259) are Hearthblock models in `tools/hearthblock/art/icons.mjs`. An icon
may replay a real model and may turn toward the camera (`yaw`).

Commands in one family share a tile colour, so look-alike commands differ by subject
(owner-approved Orders plan, 2026-10-12, doc 136): Mine blocks strikes solid rock and
Clear stones shows loose boulders and scree; Harvest plants keeps its plant alive (a
basket by a living sprig), while Clear plants shows cut stalks, never a lifted bush,
which is Uproot's picture.

**The icon spec** (owner, 2026-10-23, "form B"):
- **The render:** the model from the 3/4 camera (10, 8, 12), in the studio light, an
  ambient fill at 0.9 and a warm key light at 0.85.
- **The outline:** blocky and dark (`#1e1712`), about 2.3% of the icon's size.
- **The tile:** none in the picture. `UITheme.icon_tile_style()` draws the notched tile
  in the command family's colour (`data/ui/icon_families.json`), with a lit top band, a
  dark lower band and a dark rim. The icon fills about 89% of the tile.
1. Edit `icons.mjs`, then run `python3 tools/hearthblock/art/write_data.py`.
2. Stage with `python3 tools/voxel_assets/build.py icons`. The family is staged-only: no
   icon GLB is installed or shipped.
3. Render with `python3 tools/run_offscreen.py res://tools/GenerateUiIcons.gd`
   (`--only=name,name` after the script for chosen icons; see "Running a script that draws").
   It writes 144 px PNGs, outlined and without a tile, to `assets/ui/icons/`. The Build
   menu's log pictures (`log_upright_<wood>`, `log_horizontal_<wood>`) are drawn in each
   wood's own hewn colours, so render them again when a wood's colours change.
4. Import new PNGs with Godot's importer (`python3 tools/import_assets.py`).
5. Name the PNG and a `family` in the entry's `data/ui` JSON. `UITheme` draws the tile
   in the family colour from `data/ui/icon_families.json`. The world order markers name
   theirs in `data/ui/order_markers.json`, the badges over dwarves' heads in
   `data/ui/dwarf_indicators.json`, the character sheet's mood faces are named
   by the mood steps in `task_config.json`, and the room window's symbols (the
   thermometer among them) by `room_symbols` in `data/ui/dock.json`, and the dwarf stats'
   pictures (doc 41, "Stats") by `data/dwarves/stats.json`. The event log names
   each kind's picture in `data/events/event_log.json` and each arrival's species in
   `data/world_events/arrivals.json`. `UiIconDataTest` checks that every named picture
   exists.
6. An icon that replays a wildlife model (the arrival heads, Development's Arrival status)
   names its colours `<species>_<role>`. `write_data.py` adds them to the icon palette from
   the wildlife palette (`ICON_SPECIES`), so each icon keeps its animal's own colours.
   Icons that borrow the Sky Dial's storm cloud, rain, snow or pine name those colours as
   the Sky Dial does, added from the sky palette (`ICON_SKY`); water uses the world's water
   colours. Three dwarf tints are baked: ginger and pale (Colony), black and medium
   (`hair2`, `skin2`) and white (`hair3`, an elder for Dwarf tools).

## The Sky Dial

The Sky Dial's pieces (doc 23, "The Sky Dial") are Hearthblock models in
`tools/hearthblock/art/sky.mjs`, seen from the front. The pieces are the frame, the sky for
each part of the day, the stars, the sun and moon, the clouds, the rain and snow, and each
season's land. Each piece names its `framing`:
- **`picture`:** rendered where it sits in the window;
- **`sprite`:** rendered round its own origin, for the dial to place.

`unshaded` pieces give light, and `outline` marks the dial's edge.
1. Edit `sky.mjs` (its own roles are in its `PALETTE`), then run
   `python3 tools/hearthblock/art/write_data.py`.
2. Stage with `python3 tools/voxel_assets/build.py sky`. Like the icons, the family is
   staged only.
3. Render with `python3 tools/run_offscreen.py res://tools/GenerateUiIcons.gd --sky`. A run without
   arguments renders the icons and then the sky. It writes each piece to
   `assets/ui/sky_dial/<piece>.png`:
   - at twice the dial's width;
   - from the front, tilted down by the framing's pitch, with the icons' light;
   - in the framing `picture` in `data/ui/sky_dial.json`, so every layer stacks.
4. Import new PNGs with `python3 tools/import_assets.py`.
5. **The framing's bounds:** if the frame grows past its framing, widen `picture.rect`
   and render every layer again. A new piece the dial moves (another cloud) also needs
   its place in `data/ui/sky_dial.json` and its name in `SkyDial.gd`.

## Running a script that draws

Godot's `--headless` draws nothing, so the galleries, the menu pictures, the icons and any
rendered capture need a real renderer. Run them through the off-screen tool, never by
launching Godot yourself:

```
python3 tools/run_offscreen.py [--save] res://tools/<Script>.gd [the script's arguments]
```

- **No window, no profile.** The tool gives Godot a hidden screen (a private KWin drawing to
  a virtual framebuffer with the real graphics card) and an isolated profile
  (`XDG_DATA_HOME`, `XDG_CONFIG_HOME` and `XDG_CACHE_HOME` in a scratch folder), so nothing
  opens on the owner's desktop and the player's profile and saves are never touched.
  `--save` puts a copy of the owner's quicksave in the profile and checks the original
  afterwards. Several runs can go at once.
- **Same pictures.** A picture comes out byte for byte as it does in a window on the desktop
  (checked on 2026-11-11 for the menu pictures, the icons, studio renders and colony captures).
- **The game's window.** The project starts borderless fullscreen and the hidden screen is
  3840 x 2160, so a capture of the game's window switches it to `WINDOWED` and sets its size
  first. The screen reports no pixel density, so the interface is laid out at 100%; a
  capture that shows the interface sets `VideoSettings.dpi_override` (144 gives 150%).
- **Comparing pictures.** Compare every channel (`a.tobytes() == b.tobytes()` in Pillow).
  `ImageChops.difference(a, b).getbbox()` looks only at alpha when a picture has it, so it
  calls a recoloured picture unchanged.
- **A fresh render of an unchanged picture** can differ from the installed file in a few
  pixels by a few colour steps: files rendered long ago, and the hearth, whose flame's foot
  moves by two pixels with which pieces share the run. Put such files back, and keep a fresh
  file only when its design or its colours changed.

## File conventions

```
res://assets/models/
  animals/        wildlife, grouped by species
  characters/
    dwarves/      modular appearance parts, trade hats and work tools
  flora/
    trees/  bushes/  flowers/  reeds/  crops/
  rocks/
    boulders/  scree/
  construction/   the materials crate
  furniture/      furniture, packed forms and flame animation libraries
  items/          loose goods, crates and inventory tools
  presentation/   eyelids and meal servings
```

`assets/` is grouped by media type (`audio/`, `models/`, `ui/`), and models by subject,
never by art style (docs 157 and 158). Animals stay apart from characters, and trees,
bushes, flowers and reeds are peers under flora. Keep species and part categories, and
add a folder only when real assets need it. The axe and pickaxe a dwarf holds are
joint-local, so they stay with the rig in `characters/dwarves/tools/`; tools that are
dropped and carried are goods in `items/tools/`.

Flora files are named `{species}_{stage}[_{season}][_{variant}].glb`, with stage and
season strings exactly as the registry uses them. The registry builds the path by
concatenation. Examples:
- `oak_mature.glb` (summer, variant 1);
- `oak_mature_autumn_2.glb` (autumn, variant 2);
- `pine_mature_winter.glb` (evergreens have no summer suffix).

Furniture, workshops and world objects are named `{id}.glb`. Paths hold only the leaf
name; the registry adds the `base:flora:`, `base:furniture:` or `base:workshop:`
namespace.

All variants of one species, stage and season share:
- the trunk base position;
- the logical trunk footprint and occupancy height;
- the stage's visual height.

They may differ in crown silhouette, branch layout, a small lean (at most ±5°) and
detail placement. `clearance_height` is trunk occupancy, not visual height. Canopy
overhang never enlarges ground occupancy.

## Checklist

- [ ] Built from boxes, notched boxes and steps; no round geometry.
- [ ] Reads at colony zoom: a clear silhouette, lit tops and dark undersides.
- [ ] One or two deliberate marks; no per-cell noise.
- [ ] Roles, not colours: wood recolours in all four woods; tints and clothing still work.
- [ ] Every state is present: growth, season, picked, packed, fill level, appearance.
- [ ] Gameplay contracts kept: footprint, clearance, seat and sleep heights, grips,
      ground contact (see [64](64_hearthblock_art_direction.md)).
- [ ] Shadow proxy present. Baked occlusion is used where it doesn't multiply triangles.
- [ ] Gallery reviewed, `--check` byte-identical, family tests passing.
- [ ] Seen in the game under Hearthblock lighting; menu pictures re-rendered.

## Material rule

Furniture is woodwork (owner, 2026-07-11): beds, chairs, benches, tables and shelves,
anything dwarves use rather than work at, are wood, warm against the stone. Stone and
iron are for industrial anchors (anvil, trade counter, workshop bodies) and monuments.
One exception (owner, 2026-11-01): the Stonemason's stone stool (doc 293).
Within a tier, Tier 1 pieces stay axe-hewn (split, notched, lashed, no iron). Tier 2 is the
Carpenter's: planks and pegs, sawn but plain (doc 64, "Furniture tiers"; doc 308); the game's
words call its joints nailed since doc 313, and the pegs stand where the nails are. Fine
joinery and blankets wait for later.
