# 101 — Tool-based Carpenter promotion

Implemented 2026-10-09. This is step 1 of the Carpenter milestone: connect the
existing starter kit to promotion. The specialist workshop and recipes are next.

## Player flow

1. Craft a **Crude Carpentry Kit** under Craft → Rudimentary → Starter tools.
2. Open a dwarf's Profession screen, choose Carpenter, and promote.
3. The dwarf leaves their current job, reserves a reachable kit, walks to it and
   picks it up. Their old profession remains active until pickup finishes.
4. The profession card shows collection progress and a Cancel promotion button.
   The inspector shows the equipped kit beside the profession after completion.
5. Returning to Worker or becoming Miner drops that same kit as available loose
   supplies at the dwarf's feet. Retained profession experience is unchanged.

Miner still promotes immediately with its implicit default pickaxe. Carpenter
helps with permitted general work; specialist crafting/experience remain planned.
The starter kit grants no speed bonus. Farmer, Hunter and Blacksmith remain
preview professions even when their starter goods are in stock.

## Ownership and interruption

- `DwarfAssets` reads `promotion_enabled` and `required_tool` from profession JSON.
- `DwarfEquipment` owns one personal appointment and one equipped item per dwarf.
  It uses existing loose/stockpile/container material quotes and incremental
  NavGrid reachability checks. Unreachable nearest goods yield to other goods.
  Only the exact checked item is claimed; competing appointments and hauling
  cannot reserve the same tool.
- Pending appointments leave the scheduler's available pool. Idle notifications,
  capability checks and the agent's assignment guard all honor that exclusion.
- The existing carry pose handles physical pickup. Contact moves the item from
  ItemDropManager into dwarf cargo; completing the motion makes that same node a
  hidden equipped child. It is not cargo after equipping. Specialist work-tool
  presentation belongs to the later workshop milestone.
- Cancellation, explicit movement, sleep, lost reservations and invalid routes
  release pending goods. Goods already lifted drop intact. Sleep never interrupts
  an equipped profession, and a sleeping dwarf cannot begin a tool pickup.
- Inventory derives `equipped` separately from carried/loose/stored goods. It
  contributes to total and reserved stock, never available stock. Maintain-stock
  crafting therefore replenishes spare kits when one is equipped. Locate resolves
  an equipped item to its dwarf instead of its hidden child mesh.

## Current-version saves

Loose goods and pre-contact reserved goods remain ItemDropManager's save data.
Lifted goods remain ordinary dwarf cargo until pickup finishes. Equipped goods
are stored once in the dwarf's `equipment.tool` field. An in-flight appointment
saves `equipment.pending_role` and resumes by finding and claiming a physical
tool after load; reservations and movement paths are rebuilt. DwarfDirector's
existing cargo restoration returns lifted goods to the ground for recollection.
There is no old-save migration or compatibility layer.

## Verification

- `ToolPromotionTest`: real kit crafting, two simultaneous promotion requests,
  contact ownership, pause/speed, cancellation before/after pickup, sleep, lost
  reservation, explicit movement, all-unreachable failure and reachable fallback,
  ground/container storage, equipped and pending JSON restoration, Miner and UI.
- Native 1280×720 and 960×540 profession and inspector captures in
  `tmp/tool_promotion_review/`; the equipped-tool label is visible without scrolling.
- `SaveManagerRoundTripTest`: equipped Carpenter plus pending Worker survive real
  scene replacement, autosave and backup recovery with exact inventory counts.
- Miner, starter tools, profession UI, inspector, camp crafting, Worker crafting
  and hauling-animation regressions pass. Editor import is clean.

The inspector and Colony **Equipment** tab now show the actual kit, materials,
benefit and planned upgrade path. Completed promotions have an original chime;
see [102 — Equipment feedback](102_equipment_view_promotion_feedback.md).

Next: Carpenter workbench and a small useful specialist recipe set. Tool upgrades,
automatic equipment upgrades, durability and farming remain separate milestones.
