# 97 — Starter profession tools

Follow-up: [101 — Tool promotion](101_tool_based_promotion.md) now connects the
carpentry kit to physical pickup, equipped ownership and Carpenter promotion.
The original milestone scope below predates that follow-up.

Implemented 2026-10-09 after the player requested basic tools at the crude
workbench for Farmer, Hunter, Carpenter and Blacksmith. This resolves the
Carpenter-saw/Blacksmith dependency without requiring forged starter tools.

## Player flow and scope

Place a crude workbench, open **Craft**, scroll to the tool recipes, and queue
batches or a spare-stock target. Every recipe consumes one allowed timber unit
and one Rough Stone, producing exactly one tool. Pine remains the default wood;
the existing per-order allowed-species checklist applies.

| Recipe | Intended profession | Work time |
|---|---|---|
| Stone hoe | Farmer | 10 simulation seconds |
| Hunting spear | Hunter | 10 simulation seconds |
| Crude carpentry kit (wooden mallet and stone adze) | Carpenter | 14 simulation seconds |
| Stone hammer | Blacksmith | 12 simulation seconds |

Times are initial tuning. The hunting spear avoids a new cord/leather dependency;
bows remain later equipment. Carpentry begins with the kit, with a forged saw as
a later upgrade. The Blacksmith will still need starter workshop/recipe gameplay.

Tools are real loose goods: they can be hauled, stored, counted and saved. They
use the existing Miscellaneous storage category, with exact-item filters, and a
new **Inventory → Tools** browsing category. They are not placeable furniture.
The crafting card describes their current limits, including on compact screens.
The profession card shows the intended tool, available stock and Worker/crude
workbench maker. Owning a tool does **not** enable a planned profession.

Equipment assignment, tool pickup for promotion, profession gameplay, upgrades,
durability and repairs remain future work. Worker and Miner availability and
Miner bonuses are unchanged. The first planned equipment upgrade remains the
iron pickaxe; this milestone creates starter goods, not an equipment system.

## Physical materials and ownership

`CraftingManager` owns recipe JSON. Existing recipes keep their single selectable
timber input. Optional `additional_ingredients` lists exact item keys, one unit
per entry; the new recipes each require one Rough Stone.

`WorkerCraftOrder` claims a bench, physically fetches and sets down its additional
material beside the bench, then fetches the allowed log and begins work. Staged
goods are ordinary loose items reserved for that dwarf, not abstract credits.
The bench stays claimed across collection trips. Material count, reservation,
location, wood rule, work position and bench validity are rechecked before work
and final commitment. Only successful completion consumes all inputs and emits
the finished tool. Cancellation, pause, sleep, lost access or workshop removal
release goods and claims; ordinary interruptions retain order progress.

Follow-up [98 — Crafting selection](98_crafting_worker_selection.md) fixes the
initial worker choice: all eligible idle Workers are compared at the first stone
pickup, with proven pickup/workbench routes before any claims. Existing timber
recipes use the same selection. The selected Worker retains the batch's later
ingredient trips; completion returns to the scheduler.

`DwarfAgent` uses the existing fetch and set-down animations for each delivery.
Shaping still uses the Worker axe pose and wood contact sound against the log.
Other fetch sources and existing single-material recipes keep their execution.
The dwarf inspector names the actual carried ingredient (for example, **Carrying
Rough Stone**, then **Carrying Pine Log**). Intermediate set-down is labeled as
ingredient delivery; **Crafting** begins after the materials have arrived.

Staging reservations are transient. `ItemDropManager` saves staged loose goods;
the dwarf saves carried goods; the order saves recipe, allowed wood and progress.
Load restores goods through those existing owners and gathers them again before
resuming. There is no second material ledger or new save section.

## Art and verification

`tools/generate_starter_tools.py` creates four original voxel GLBs: grounded,
eight voxels per block, baked 0.125 scale, linear colors and no colliders. The
models lie flat for carrying/storage and use pegged wood/stone parts without
unpaid metal, leather or cord. `InventoryCatalogThumbnails.gd -- --only=...`
renders their real models for crafting and inventory thumbnails.

`StarterToolsTest` verifies all four recipes, missing material/workshop waits,
physical delivery, stored-stone withdrawal, exact input/output conservation,
pause, independently serialized loose/carried goods and resumed partial work,
cancellation between trips, changed wood rules, workshop removal, maintain-stock
replenishment, storage hauling, Tools browsing and planned promotion state.
Native menu review covers 960×540 and 1280×720.

Existing Worker crafting, wood-selection, stump approach, audio, profession UI,
Miner and colony inventory regressions pass. Full `SaveManagerRoundTripTest`
includes a partial tool order and all four finished tools through autosave,
quicksave and backup scene restoration. Evidence: `tmp/starter_tools_review/`.

Restart play mode. No new autoload or global script class was added.
