# 52 — Combat & Military

## Overview

The colony is not just a brewery — it is a warm light in a dangerous dark. As the colony grows wealthy, it attracts unwanted attention. The Military system gives players the tools to defend their dwarves against invader waves that scale with the colony's `wealth_score` (tracked by `VisitorManager`). Without active defense, a sufficiently prosperous colony will eventually be overwhelmed.

Military dwarves are **reassigned colonists**, not special recruits. Any dwarf can be enlisted, stripping them from the civilian labor pool and slotting them into a combat profession. This is a deliberate tension: every soldier is a brewer, miner, or farmer the colony is giving up.

The core loop is:

```
Wealth grows (from trade) → wealth_score rises → invader waves escalate
→ player enlists dwarves into military professions
→ dwarves arm up at the Armory, then patrol designated routes
→ dwarves engage invaders automatically on patrol
→ surviving invaders reach the colony and cause damage
→ player builds fortifications to shape the fight
```

---

## Military Professions

A dwarf is assigned a military profession through the **Labor Assignment Window** (see `23_user_interface.md`). Enlisting a dwarf replaces their civilian job entirely — they stop accepting economic tasks (`MINE`, `HAUL`, `FARM`, `BREW`, `BUILD`) and their task slot is claimed exclusively by `PATROL` and combat tasks.

Military profession and equipped gear are stored on `DwarfAgent`:

```gdscript
enum MilitaryClass { NONE, WARRIOR, BERSERKER, STONECLAD, MARKSMAN }
var military_class: MilitaryClass = MilitaryClass.NONE

# Equipment slots — item URI strings; empty string = slot unoccupied
var equipment: Dictionary = {
    "slot_helmet":      "",   # base:item:armor:helmet_*
    "slot_chest":       "",   # base:item:armor:chest_*
    "slot_boots":       "",   # base:item:armor:boots_*
    "slot_weapon_main": "",   # primary weapon or crossbow
    "slot_weapon_off":  "",   # shield, second weapon, bolt quiver, or "" (Stoneclad)
}
```

Setting `military_class` to anything other than `NONE` flags the dwarf as enlisted. The Task System will never assign a civilian task to an enlisted dwarf. A dwarf with an empty equipment dictionary is enlisted but **not yet combat-ready** — they must visit the Armory first.

---

## Dwarf Equipment

All enlisted dwarves wear three armour pieces and carry profession-specific weapons. Armour reduces incoming damage; weapons determine damage output and attack style. Equipment is physical — it occupies slots on `Armor Stand` furniture in the Armory room and transfers to the dwarf's `equipment` dictionary when they arm up.

### Armour Slots

All professions share the same three armour slots. The material tier of each piece determines its damage reduction contribution.

| Slot | Key | Effect |
|------|-----|--------|
| Helmet | `slot_helmet` | Minor damage reduction; protects against ranged headshots (future) |
| Chest | `slot_chest` | Primary armour piece; largest damage reduction contribution |
| Boots | `slot_boots` | Minor damage reduction; affects move speed (heavy boots = slight slow) |

### Armour Tiers & Damage Reduction

| Tier | Helmet | Chest | Boots | Total Reduction | Notes |
|------|--------|-------|-------|-----------------|-------|
| Leather | `helmet_leather` | `chest_leather` | `boots_leather` | ~10% | Default for Berserker, Marksman |
| Chainmail | `helmet_chain` | `chest_chain` | `boots_chain` | ~20% | Default for Warrior |
| Plate | `helmet_plate` | `chest_plate` | `boots_plate` | ~35% | Default for Stoneclad |

> **Design note:** "Default" tier is what each profession's Armor Stand is stocked with. Nothing prevents a player from equipping a Berserker in plate — but plate boots impose a −0.1 move speed multiplier, which on a Berserker removes most of their speed advantage. Equipment choices have real trade-offs.

### Weapon Slots by Profession

| Profession | `slot_weapon_main` | `slot_weapon_off` | Notes |
|---|---|---|---|
| Warrior | `weapon_sword_iron` or `weapon_axe_iron` | `shield_iron` | Off-hand shield enables Shield Block passive |
| Berserker | `weapon_axe_iron` | `weapon_axe_iron` (second) | Both slots filled with weapons; no shield possible |
| Stoneclad | `weapon_maul_iron` or `weapon_greataxe_iron` | *(locked empty)* | Two-handed; off-hand slot is permanently unavailable |
| Marksman | `weapon_crossbow_iron` | `quiver_bolts` | Quiver is non-consumable equipment — equip once, fires indefinitely |

All item keys are namespaced under `base:item:weapon:*` and `base:item:armor:*`. Exact base damage values are TBD in the balance pass.

### Gear Drop on Death

When an enlisted dwarf dies, all equipped items are dropped as item entities at the death location. Dwarves will automatically haul dropped gear back to the nearest Armory if a haul task is available — equipment is recoverable, even if the dwarf is not.

---

## The Armory Room

The **Armory** is a sealed room (enclosed walls + one or more doors) that serves as the colony's weapon and equipment store. It is the required infrastructure for military enlistment — a dwarf cannot become combat-ready without one.

### Room Detection

Room detection uses the same flood-fill algorithm as sealed rooms in the temperature system (see `34_temperature.md`). A sealed room becomes an **Armory** if it contains at least one **Wall Display** or one **Armor Stand**. The room designation is emergent — there is no explicit "designate as armory" action. Place the furniture; the room becomes an Armory.

```gdscript
# RoomClassifier — runs after flood-fill completes
func classify_room(room: RoomData) -> StringName:
    for furniture in room.furniture_list:
        if furniture.type in [&"base:furniture:wall_display",
                              &"base:furniture:armor_stand"]:
            return &"armory"
    if room.has_furniture(&"base:furniture:trade_counter"):
        return &"shop"
    # ... other room types
    return &"undesignated"
```

A room cannot simultaneously be an Armory and a Shop. If a Trade Counter and a Wall Display coexist in the same sealed room, the room is classified as a Shop (trade takes precedence). Keep the Armory separate.

### Armory Furniture

#### Wall Display

A wall-mounted rack that holds **one weapon or shield**. Requires an adjacent solid wall block (must be placed against a wall, not freestanding).

```gdscript
class_name WallDisplay extends Node3D
var wall_face:    Vector3i    # the solid wall block this display is mounted on
var stored_item:  String      # item URI, or "" if empty
var display_type: StringName  # &"weapon" or &"shield" — cosmetic only, does not restrict items
```

- Visually renders the stored weapon or shield as a micro-voxel `.glb` model mounted on the wall.
- A Wall Display with `stored_item == ""` is an empty mount bracket — visible in the room but non-functional until stocked.
- Multiple Wall Displays can be placed in a single Armory. Dwarves pull from the nearest available display that holds their required weapon type.
- The player stocks Wall Displays by designating a **haul task**: right-click the display and select *"Stock from stockpile"* — a dwarf hauls the specified weapon item from the nearest compatible stockpile.

#### Armor Stand

A floor-placed carved wooden figure (~2 blocks tall) that holds **one complete set of armour**: helmet, chest piece, and boots simultaneously. Footprint: 1×1 block. The stand visually displays whatever gear it holds, rendering the armour pieces on the wooden form.

```gdscript
class_name ArmorStand extends Node3D
var stored_helmet: String   # item URI or ""
var stored_chest:  String   # item URI or ""
var stored_boots:  String   # item URI or ""
```

- Each slot is independent. A stand with only a chest piece stocked is valid — a dwarf will take the chest and leave the helmet and boot slots empty.
- One Armor Stand is required per enlisted dwarf. If the colony has 3 Warriors but only 2 Armor Stands stocked with chainmail, the third Warrior cannot fully arm up and will be flagged with a WARN toast: *"[Name] cannot arm — no Armor Stand available in the Armory."*
- Like Wall Displays, stands are stocked via haul task.

### Armory Capacity Planning

| Furniture | Stores | Notes |
|-----------|--------|-------|
| 1× Armor Stand | 1 full armour set (3 pieces) | One per enlisted dwarf |
| 1× Wall Display | 1 weapon or shield | Warriors need 2 displays (weapon + shield); Berserkers need 2 (dual weapons); Stoneclads need 1; Marksmen need 2 (crossbow + quiver) |

> **Design note:** A five-dwarf garrison — two Warriors, one Berserker, one Stoneclad, one Marksman — needs 5 Armor Stands, 4 weapon Wall Displays, 2 shield Wall Displays (Warriors), and 1 quiver Wall Display (Marksman). Armory sizing is a real early-game planning decision.

---

## Enlistment & Arming Flow

Enlistment is a two-step process: the player assigns a profession, then the dwarf physically arms up at the Armory before entering active duty.

### Step 1 — Profession Assignment

1. Player opens the **Labor Assignment Window** (right panel).
2. A dwarf row has a new **"Enlist"** dropdown: `— Civilian —`, `Warrior`, `Berserker`, `Stoneclad`, `Marksman`.
3. Selecting a class sets `DwarfAgent.military_class` and immediately cancels any active civilian task.
4. The dwarf's row moves to a **"Military"** section. Their Skills column is replaced with a gear icon showing empty equipment slots.
5. An `ARMING` task (priority 80, above patrol) is automatically queued for the dwarf.

### Step 2 — Arming Task

The `ARMING` task drives the dwarf to the nearest Armory room and equips them:

```
1. Path to Armory room entrance
2. At the nearest Armor Stand with any stored piece:
     a. Take helmet → write to equipment["slot_helmet"], clear stand slot
     b. Take chest  → write to equipment["slot_chest"],  clear stand slot
     c. Take boots  → write to equipment["slot_boots"],  clear stand slot
3. At the nearest Wall Display holding the required weapon type:
     a. Take main weapon → write to equipment["slot_weapon_main"], clear display
     b. Take off-hand item (shield / second weapon / quiver) → write to equipment["slot_weapon_off"]
4. Dwarf is now COMBAT_READY
     → ARMING task completes
     → First PATROL task queues
     → Labor window gear icon updates to show equipped items
```

If **no Armory exists** or the Armory lacks the required gear, the ARMING task is flagged BLOCKED. A WARN toast fires: *"[Name] cannot arm — Armory is unstocked."* The dwarf idles at the Armory entrance (or near the Labor window if no Armory exists) until gear is available.

### De-enlisting

1. Player sets the dwarf back to `— Civilian —`.
2. A `DISARMING` task queues (priority 80) — dwarf returns to the Armory and deposits all equipped items back onto an available Armor Stand and Wall Displays.
3. Once deposited, `military_class` is cleared and the dwarf re-enters the civilian pool with all previous skill ratings intact.

If the Armory is destroyed or sealed off while a dwarf is armed, gear is retained on the dwarf until an accessible Armory is available for return.

---

## Patrol System

Patrol routes are the peacetime behaviour of all enlisted, armed dwarves. A dwarf without a patrol route idles near the Armory — which is better than nothing, but not a defense.

### Route Designation

The player designates patrol routes in the **Military Build tab**:

1. Select **"Patrol Route"** from the Military tab.
2. Click to place **waypoints** (up to 8 per route) at any navigable floor block.
3. Assign one or more dwarves to the route via the Labor window.

Routes are stored as ordered `Array[Vector3i]` waypoints. Dwarves traverse them in sequence, looping endlessly.

```gdscript
class_name PatrolRoute extends Resource
var route_id:   int
var waypoints:  Array[Vector3i]   # ordered patrol stops
var assigned:   Array[int]        # DwarfAgent node IDs assigned to this route
```

### PATROL Task Execution

The `PATROL` task type (priority 60) is generated automatically for each combat-ready dwarf without a current combat task. It is the lowest-priority real military task, interrupted immediately by combat.

```
1. Dwarf reaches waypoint[i]
2. Pause at waypoint for PATROL_DWELL_TIME (default: 2.0 s)
3. Move to waypoint[(i + 1) % waypoints.size()]
4. Repeat
```

If a dwarf detects an enemy within `AGGRO_RADIUS` (default: 10 blocks) during patrol, the patrol task is suspended and a combat engagement begins. On enemy death or retreat, patrol resumes from the nearest waypoint.

### Guard Posts

A **guard post** is a single-waypoint patrol route — the dwarf stands at one fixed position indefinitely. This is the correct assignment for Marksmen on elevated platforms and Stoneclads at tunnel chokepoints.

---

## Invader Waves

Invader waves are triggered by `VisitorManager` based on `wealth_score` and a time-gated chance roll.

### Spawn Conditions

```gdscript
# Checked once per in-game day at midnight
func _roll_invasion_check() -> void:
    if wealth_score < INVASION_WEALTH_THRESHOLD:
        return   # colony too poor to attract raiders

    var base_chance := 0.05
    var wealth_bonus := (wealth_score - INVASION_WEALTH_THRESHOLD) * 0.005
    var roll := randf()

    if roll < base_chance + wealth_bonus:
        _spawn_invasion_wave()
```

`INVASION_WEALTH_THRESHOLD` = 30. Below this score the colony is too obscure to be worth raiding.

### Wave Composition

Invader waves are data-driven, defined in a future `data/visitors/invasion_waves.json`. Waves escalate in three tiers keyed to wealth:

| Tier | Wealth Range | Composition | Threat Level |
|------|-------------|-------------|--------------|
| 1 — Scouting Party | 30–49 | 3–5 light melee raiders | Low |
| 2 — Raiding Band | 50–74 | 6–10 mixed melee + 1–2 archers | Moderate |
| 3 — War Host | 75+ | 12–20 mixed units including an armoured champion | High |

Champions are named, high-health elite enemies. Defeating a champion posts a toast: *"The raider champion [Name] has fallen."* and grants `+10 trade_reputation` (word of the colony's strength spreads).

### Invader Behaviour

All invaders share the same objective: reach the colony's deepest occupied room and destroy infrastructure before being killed or retreating.

```
APPROACHING  → path from world-edge entry node toward colony
ENGAGING     → attack any dwarf within aggro radius
BREACHING    → if no defenders in path, continue inward toward colony rooms
RETREATING   → flee to world edge if < 20% health; surviving retreating units
                report back — next wave of same tier has +1 additional unit
```

Invaders do **not** mine blocks. They path through existing tunnels and can open doors. A fully sealed corridor with no door is impassable to them. Putting a door in it makes it openable.

### Invasion Signal

```gdscript
signal invasion_started(wave: InvasionWave)
```

`invasion_started` triggers:
- A **CRITICAL** toast: *"Raiders approach from the surface — [N] enemies spotted."*
- All patrolling military dwarves have their `AGGRO_RADIUS` doubled for 30 seconds (alarm state).
- Surface ambient audio shifts to the combat track via `AudioManager`.

---

## Combat Resolution

Combat is resolved at the agent level — each dwarf and each invader ticks their own attack cooldown and health independently. There is no separate combat server; it runs on the same simulation tick as needs resolution.

### Attack Cycle

```
1. Attacker checks if target is within attack range (melee: 1.5 blocks; ranged: 8–20 blocks)
2. If in range and off cooldown → apply hit
3. Hit damage = weapon_base_damage × skill_modifier − target_armour_reduction
4. Reset attack cooldown (varies by profession)
5. Target health reduced; if health ≤ 0 → target dies
```

`target_armour_reduction` is computed from the sum of the target's equipped armour pieces. An unarmed dwarf has 0% reduction; a fully plated Stoneclad has ~35%.

### Damage Parameters (High Level)

| Profession | Weapon Damage | Attack Cooldown | Armour Reduction (full kit) |
|---|---|---|---|
| Warrior | Medium | 2.5 s | ~20% chain + 25% Shield Block = effective ~40% |
| Berserker | Medium × 2 hits | 1.5 s per pair | ~10% leather |
| Stoneclad | High | 4.0 s | ~35% plate |
| Marksman | Medium | 3.0 s | ~10% leather |

Exact values are TBD in a future balance pass. These are design-intent ratios.

### Death & Injury

- A dwarf whose `health` reaches `0.0` enters the `DEAD` state. All equipped gear drops as item entities.
- Dwarves reduced below `0.50` health gain `base:thought:injured` and are assigned a forced bed-rest task until health recovers above `0.75`.
- Corpses persist and trigger `base:thought:saw_corpse` for any dwarf passing within 3 tiles.

---

## Fortification (Military Build Tab)

The Military Build tab (currently stubbed in the UI) will expose the following designations. Detailed implementation is deferred to a follow-on doc.

| Designation | Function |
|---|---|
| Patrol Route | Draw ordered waypoint loop for enlisted dwarves |
| Guard Post | Single fixed-point stance (one-waypoint route) |
| Murder Hole | Ceiling tile designation — Marksmen on upper level fire down through it into the tunnel below |
| Barricade | Low constructed block (half-height) — blocks invader movement, does not block Marksman fire lines |
| Gate | Reinforced door variant — takes 5× longer for invaders to breach |

---

## Integration with Existing Systems

| System | Integration Point |
|---|---|
| `TaskManager` | `PATROL` task (priority 60) already defined. This system adds `ARMING` and `DISARMING` (priority 80) and `COMBAT` (priority 85). |
| `DwarfAgent` | `health`, `DEAD`, and `TANTRUM` states already exist. `military_class` and `equipment` dict added by this system. |
| `StockpileManager` | Gear haul tasks use the standard haul pipeline. Quivers are equipment items stored on Wall Displays like weapons — no separate ammo stockpile needed. |
| `VisitorManager` | `wealth_score` and `invasion_started` signal already scaffolded. Wave spawner connects here. |
| `AudioManager` | Combat track registered as `"combat_alert"`. Triggered by `invasion_started`, fades on wave clear. |
| `ToastManager` | CRITICAL and WARN severities already exist and cover all required military notifications. |
| `WorldClock` | Invasion chance roll fires on `day_changed`. No new clock dependency needed. |
| Room system | Armory room classification follows the same flood-fill and furniture-anchor pattern as Shop (`51_visitors.md`) and sealed rooms (`34_temperature.md`). No new room detection code needed — only a new classifier branch. |

---

## Hard Rules

1. **Enlisted dwarves never accept civilian tasks.** The Task System must check `military_class != NONE` before assignment.
2. **Unarmed dwarves cannot patrol or fight.** `equipment["slot_chest"]` must be non-empty before a PATROL task is issued. An enlisted but unarmed dwarf idles at the Armory entrance.
3. **Invaders cannot mine.** They path through existing openings only. Never call `WorldData.set_block()` from invader code.
4. **Marksmen never fire through friendly dwarves.** Line-of-sight must include allied agent positions, not just terrain.
5. **No combat before wealth_score ≥ 30.** Early colonies must be safe enough to establish themselves.
6. **Deaths are permanent.** There is no respawn. A dead dwarf is gone. This must not be softened.
7. **Gear is recoverable, dwarves are not.** Equipment dropped on death must be haul-able back to the Armory by surviving dwarves.

---

## Forward Compatibility Notes

- **Combat skill progression** — enlisted dwarves could gain experience over time, improving damage and speed, making veterans more valuable and their loss more costly.
- **Champion invader AI** — wave champions need a more sophisticated target-selection loop than rank-and-file raiders. Defer to a dedicated invader AI doc.
- **Burial tasks and memorial hall** — morale recovery mechanic for dwarf deaths. Hooks into the thought system via `base:thought:honored_dead`.
- **Armoury crafting** — weapons and armour will eventually be craftable by a Weaponsmith profession at a dedicated workshop. Until then, they are acquired exclusively through trade (buy orders on the Trade Counter).
- **Allied caravans** — high `trade_reputation` could unlock caravan guards who assist during invasion events.
- **Equipment quality tiers** — iron is the baseline. Steel (future) would offer improved damage reduction and weapon damage, providing a clear progression goal for the late game.

---

*Prev: [51_visitors.md](./51_visitors.md)*
