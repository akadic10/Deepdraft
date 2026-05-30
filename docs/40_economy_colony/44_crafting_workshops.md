# 44 — Crafting Workshops

## Overview

The colony's metalworking chain converts raw ore into the tools, weapons, and armour that keep the settlement alive and defended. It operates in two stages: the **Smelter** refines ore into ingots, and the **Forge** turns ingots into finished goods. Both buildings are operated by the **Blacksmith** profession and its two specialisations — **Weaponsmith** and **Armorsmith**.

This system closes the two open placeholders in prior design docs:

- `52_combat_military.md` states military gear is acquired through trade *"until a Weaponsmith exists."* The Weaponsmith profession defined here removes that constraint.
- `51_visitors.md` lists *"Crafted goods (future: jewellery, furniture)"* as merchant buy priority 5. Forged items are now the first entries in that tier.

---

## Professions

### Blacksmith — `base:profession:blacksmith`

The Blacksmith is a permanent, long-term colony role — not a stepping stone. They are the only profession that operates the Smelter, and they produce the basic metal goods the colony consumes continuously: pickaxe heads, torch brackets, door hardware, and nails. Every colony that wants to expand militarily needs at least one Blacksmith keeping the Smelter running even after specialists take over the Forge.

**Primary task types:** `SMELT`, `FORGE`
**Work speed bonus per level:** `0.05` (matches Brewer — 5% per level, 25% total at level 5)

### Weaponsmith — `base:profession:weaponsmith`

A Blacksmith who has been promoted by the player into dedicated weapons production. Weaponsmiths do not operate the Smelter — they work exclusively at the Forge, crafting the weapons and crossbows used by the colony's military. They accept `FORGE` tasks for weapon recipes only; `SMELT` tasks are ignored.

**Primary task types:** `FORGE` (weapon recipes only)
**Work speed bonus per level:** `0.05`

### Armorsmith — `base:profession:armorsmith`

A Blacksmith promoted into armour and shield production. Like the Weaponsmith, the Armorsmith works at the Forge only and ignores `SMELT` tasks. They produce every piece of armour and every shield used by enlisted dwarves.

**Primary task types:** `FORGE` (armour and shield recipes only)
**Work speed bonus per level:** `0.05`

---

## Specialisation

### Requirements

A dwarf can be promoted to Weaponsmith or Armorsmith only if **all three conditions** are met:

1. Their current profession is `base:profession:blacksmith`.
2. Their Blacksmith experience level is **≥ 3** (100 cumulative tasks — see `41_dwarf_agents.md`).
3. An operational Forge exists in the colony (reachable by the dwarf).

### How to Promote

In the **Labour Assignment Window**, a Blacksmith's profession dropdown gains two additional entries once the above conditions are met:

```
— Blacksmith —      ← current
  Weaponsmith       ← unlocked at level 3
  Armorsmith        ← unlocked at level 3
```

If the level requirement is not yet met, both entries appear **greyed out** with the tooltip: *"Requires Blacksmith Level 3 (100 tasks)."*

### Experience Carry-Over

Specialisation shares the Blacksmith's accumulated task count. On promotion, the target profession's experience entry is set to equal the current Blacksmith count:

```gdscript
# On promotion — called by the Labour window when player selects a specialisation
func _promote_blacksmith(dwarf: DwarfAgent, target: String) -> void:
    # target is "base:profession:weaponsmith" or "base:profession:armorsmith"
    var bs_xp := dwarf.profession_experience.get("base:profession:blacksmith", 0)
    dwarf.profession_experience[target] = bs_xp
    dwarf.profession = target
    # Cancel any active SMELT or FORGE task — dwarf re-queues from the new role
    TaskManager.cancel_active_task(dwarf.id)
```

A level 4 Blacksmith promoted to Weaponsmith begins as a level 4 Weaponsmith immediately. The Blacksmith entry in `profession_experience` is retained unchanged — if the dwarf is ever reassigned back to Blacksmith, their original count is intact.

### De-specialisation

The player can reassign a Weaponsmith or Armorsmith back to `base:profession:blacksmith` at any time via the Labour window. No experience is lost from any entry. The dwarf re-enters the full Blacksmith task pool (`SMELT` + `FORGE` general recipes).

> **Agent note:** De-specialisation to Weaponsmith/Armorsmith from Civilian (skipping Blacksmith) is not permitted. The UI must enforce `base:profession:blacksmith` as the required intermediate step — it is not possible to jump directly from `base:profession:worker` to `base:profession:weaponsmith`.

---

## The Smelter

`base:workshop:smelter`

The Smelter converts raw ore into metal ingots. It is a standalone workshop block — no sealed room required. Place it underground or on the surface; it functions identically in both locations. Only **Blacksmiths** operate the Smelter. Weaponsmiths and Armorsmiths ignore `SMELT` tasks entirely.

Full schema: `data/workshops/smelter.json` *(to be created)*.

### Placement

- Footprint: **2×1×2 blocks** (the largest workshop in the game — it is a substantial structure).
- Requires **no ceiling constraint** — it can be placed in low tunnels as long as there are 3 clear air blocks above the operator's standing position adjacent to the block (standard dwarf clearance, see `32_navigation_3d.md`).
- Produces heat: a Smelter in operation counts as **800 heat units** for the temperature system in its enclosing room (see `34_temperature.md`). A Smelter left running in a shallow aging cellar will ruin the temperature balance — keep it in a dedicated room.

### Smelting Recipes

Coal is consumed as fuel in every smelting recipe. It is never a product and cannot be smelted itself.

| Recipe ID | Inputs | Output | Work Time | Min Skill |
|---|---|---|---|---|
| `base:recipe:smelt:iron_ingot`   | 2× iron ore + 1× coal   | 2× iron ingot   | 1 h | 1 |
| `base:recipe:smelt:copper_ingot` | 2× copper ore + 1× coal | 2× copper ingot | 1 h | 1 |
| `base:recipe:smelt:tin_ingot`    | 2× tin ore + 1× coal    | 2× tin ingot    | 1 h | 1 |
| `base:recipe:smelt:silver_ingot` | 2× silver ore + 1× coal | 1× silver ingot | 1 h | 2 |
| `base:recipe:smelt:gold_ingot`   | 2× gold ore + 1× coal   | 1× gold ingot   | 2 h | 3 |

> **Design note:** Gold and silver ingots have no combat application — they are luxury goods. Gold ingots are the highest-value item a merchant will buy (above gems, by unit weight). The Blacksmith who can smelt gold is a direct economic asset.

Silver and gold ingots carry `base_trade_value` entries in `data/entities/items/resources.json`. Exact values TBD in the trade balance pass.

---

## The Forge

`base:workshop:forge`

The Forge turns ingots and other materials into finished goods. All three metalworking professions work at the Forge, but each accepts only the recipes appropriate to their role. A single Forge serves the whole colony — build additional Forges only when throughput is a bottleneck.

Full schema: `data/workshops/forge.json` *(to be created)*.

### Placement

- Footprint: **1×1×2 blocks** (floor block + anvil block above).
- No sealed room required.
- Does **not** produce heat units — unlike the Smelter, the Forge is cold-worked for game design purposes (simplicity; the Smelter is the heat-producing step).

---

## Forge Recipes — Blacksmith

General metal goods. Any Blacksmith accepts these tasks. Weaponsmiths and Armorsmiths do **not** take general Blacksmith recipes — they are specialists.

| Recipe ID | Inputs | Output | Work Time | Min Skill | Notes |
|---|---|---|---|---|---|
| `base:recipe:forge:pickaxe_head`    | 1× iron ingot   | 2× pickaxe head    | 1 h   | 1 | Used in mining tool construction (future) |
| `base:recipe:forge:torch_bracket`   | 1× iron ingot   | 4× torch bracket   | 0.5 h | 1 | Required to place wall torches |
| `base:recipe:forge:door_hinge`      | 1× iron ingot   | 4× door hinge      | 0.5 h | 1 | Required to place constructed doors |
| `base:recipe:forge:iron_nail_bundle`| 1× iron ingot   | 6× iron nail       | 0.5 h | 1 | Used in BUILD tasks for wood construction |
| `base:recipe:forge:copper_fitting`  | 1× copper ingot | 4× copper fitting  | 0.5 h | 1 | Used in brewery/aging cellar construction |

---

## Forge Recipes — Weaponsmith

Only Weaponsmiths accept `FORGE` tasks for these recipes. If no Weaponsmith exists, these recipes are never queued.

### Melee Weapons

| Recipe ID | Inputs | Output | Work Time | Min Skill |
|---|---|---|---|---|
| `base:recipe:forge:sword_iron`     | 2× iron ingot | 1× iron sword     | 2 h | 2 |
| `base:recipe:forge:axe_iron`       | 2× iron ingot | 1× iron axe       | 2 h | 2 |
| `base:recipe:forge:maul_iron`      | 3× iron ingot | 1× iron maul      | 3 h | 3 |
| `base:recipe:forge:greataxe_iron`  | 3× iron ingot | 1× iron greataxe  | 3 h | 3 |

### Ranged Weapons

| Recipe ID | Inputs | Output | Work Time | Min Skill |
|---|---|---|---|---|
| `base:recipe:forge:crossbow_iron` | 2× iron ingot + 1× cloth | 1× iron crossbow | 3 h | 3 |

> **Cloth requirement:** Crossbow limbs require a cloth-wrapped grip. Cloth is produced from pig tail at the Brewery (`base:recipe:brew:pig_tail_cloth`). This creates a soft dependency between the farming/brewing chain and military production.

---

## Forge Recipes — Armorsmith

Only Armorsmiths accept `FORGE` tasks for these recipes.

### Leather Armour

Leather armour uses **leather strips** as its primary input. Leather strips are not produced in the colony — they must be acquired through merchant buy orders at the Trade Counter. This makes leather armour the early-game, trade-dependent tier; chainmail and plate are the self-sufficient tiers.

| Recipe ID | Inputs | Output | Work Time | Min Skill |
|---|---|---|---|---|
| `base:recipe:forge:helmet_leather` | 2× leather strip | 1× leather helmet | 1 h | 1 |
| `base:recipe:forge:chest_leather`  | 4× leather strip | 1× leather chest  | 1.5 h | 1 |
| `base:recipe:forge:boots_leather`  | 2× leather strip | 1× leather boots  | 1 h | 1 |

### Chainmail

| Recipe ID | Inputs | Output | Work Time | Min Skill |
|---|---|---|---|---|
| `base:recipe:forge:helmet_chain` | 2× iron ingot | 1× chainmail helmet | 2 h | 2 |
| `base:recipe:forge:chest_chain`  | 4× iron ingot | 1× chainmail chest  | 3 h | 2 |
| `base:recipe:forge:boots_chain`  | 2× iron ingot | 1× chainmail boots  | 2 h | 2 |
| `base:recipe:forge:shield_iron`  | 3× iron ingot | 1× iron shield      | 2 h | 2 |

### Plate Armour

| Recipe ID | Inputs | Output | Work Time | Min Skill |
|---|---|---|---|---|
| `base:recipe:forge:helmet_plate` | 4× iron ingot | 1× plate helmet | 3 h | 4 |
| `base:recipe:forge:chest_plate`  | 8× iron ingot | 1× plate chest  | 5 h | 4 |
| `base:recipe:forge:boots_plate`  | 4× iron ingot | 1× plate boots  | 3 h | 4 |

> **Plate cost:** A fully equipped Stoneclad costs 16 iron ingots in armour alone (8 chest + 4 helmet + 4 boots), plus 3 for the maul or greataxe — 19 ingots total per soldier, requiring 38 iron ore and 10 coal. Plate is a meaningful late-game investment that makes iron ore veins strategically valuable.

---

## Task Types

Two new task types are added to `Task.Type` in `31_task_system.md`:

```gdscript
enum Type { MINE, HAUL, FARM, BREW, BUILD, IDLE, PATROL, SMELT, FORGE }
```

### Default Priorities

| Task Type | Default Priority | Rationale |
|---|---|---|
| `SMELT` | 45 | On par with BUILD — ingots must stay ahead of Forge demand |
| `FORGE` | 40 | Same as HAUL — keeps military stocked without pre-empting core production |

Priority bonuses:

```
+20  if bolt stockpile < 20 and task type == FORGE and recipe == bolt_bundle
+15  if no iron ingots in any stockpile and task type == SMELT
```

### Skill Compatibility

| Task Type | Preferred Skill |
|---|---|
| `SMELT` | `base:profession:blacksmith` |
| `FORGE` | `base:profession:blacksmith` / `weaponsmith` / `armorsmith` (matched by recipe type) |

A dwarf without the preferred profession can attempt a `SMELT` or `FORGE` task at ×0.7 speed — but only plain Blacksmith recipes. Weapon and armour recipes are hard-gated by profession: a Farmer cannot forge a sword regardless of speed penalty.

---

## Stockpile Integration

### New Stockpile Filter Tags

The Stockpile filter panel (see `23_user_interface.md`) gains two new filter categories:

| Filter Tag | Covers |
|---|---|
| `stockpile_ingots` | All metal ingots (iron, copper, tin, silver, gold) |
| `stockpile_metalwork` | All forged items (tools, weapon components, armour pieces, weapons) |

Leather strips use the existing `stockpile_general` category until a dedicated tag is warranted.

---

## Integration with Existing Systems

| System | Integration Point |
|---|---|
| `TaskManager` | `SMELT` and `FORGE` added to `Task.Type`. Priority table in `31_task_system.md` updated. |
| `DwarfAgent` | Three new profession keys added to `profession_experience` dict (see `41_dwarf_agents.md`). Specialisation logic runs in the Labour window on player action. |
| `StockpileManager` | New filter tags `stockpile_ingots` and `stockpile_metalwork`. Bolt stockpile tag `stockpile_ammo` already scaffolded in `52_combat_military.md`. |
| `RoomData` / temperature | Smelter emits 800 heat units into its enclosing sealed room while active. Handled the same way as torches — see `34_temperature.md`. |
| `VisitorManager` / trade | Gold and silver ingots, forged weapons (if surplus), and armour pieces carry `base_trade_value` and appear in the merchant buy priority 5 tier. |
| `52_combat_military.md` | The `ARMING` task now resolves via Forge output — military gear no longer depends exclusively on trade. The placeholder note in that doc is satisfied by this system. |

---

## Hard Rules

1. **Only Blacksmiths operate the Smelter.** Weaponsmiths and Armorsmiths never receive `SMELT` tasks. If no Blacksmith exists, the Smelter idles regardless of ore supply.
2. **Weapon and armour recipes are profession-gated.** The Task System must check the assigned dwarf's profession before issuing a `FORGE` task. A plain Blacksmith cannot forge a plate chest; an Armorsmith cannot forge a sword.
3. **Specialisation requires Blacksmith Level 3.** The Labour window must enforce this. Do not expose the specialisation options until the threshold is reached.
4. **The Smelter heat output applies at all times while a batch is in progress.** It does not matter whether a dwarf is currently standing at the Smelter — a running batch heats the room.
5. **Leather strips are never produced in the colony.** They are a trade-only input. Do not add a tanning or hide-processing recipe without a new design doc covering that system.
6. **Experience carry-over is one-way at promotion.** The Weaponsmith or Armorsmith counter is set to the Blacksmith count at the moment of promotion. Subsequent Weaponsmith task counts do not flow back to the Blacksmith entry.

---

## Forward Compatibility Notes

- **Jeweller workshop** — raw gems (ruby, sapphire, emerald, diamond) have no production use today. A Jeweller workshop and `base:profession:jeweller` specialisation (parallel to Weaponsmith/Armorsmith) is the intended path for merchant tier 5 crafted goods. Design deferred to a follow-on doc.
- **Steel tier** — `52_combat_military.md` notes steel as a future equipment quality tier above iron. When steel ore or a steel-making recipe is added, it slots into the existing smelting/forging pipeline with higher `min_skill` requirements and better damage/reduction values. No structural changes to this system are needed.
- **Weaponsmith crafting for champions** — the champion invader AI (`52_combat_military.md` Forward Compatibility) may loot forged weapons on colony breach. The item drop pipeline already handles this; no new code needed.
- **Copper and tin uses** — copper and tin ingots have no forge recipes yet. They are placeholder outputs for future systems: copper fittings for water/brewing infrastructure upgrades, tin for food preservation vessels. Do not delete them from the smelting table.
- **Support pillars** — `43_mining_materials.md` notes a future support pillar mechanic. Iron or copper ingots are the likely material input when that system is designed.

---

*Prev: [43_mining_materials.md](./43_mining_materials.md) | Next: [51_visitors.md](../50_world_events/51_visitors.md)*
