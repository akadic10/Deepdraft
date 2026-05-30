# 51 — Visitors & World Events

## Overview

The colony is not isolated. Three categories of visitor enter the map from the world edge along the surface trade road: **Merchants** who buy and sell goods, **Travelers** who seek rest and drink, and **Invaders** who attack. Each type has distinct spawn conditions, infrastructure requirements, and AI behaviour.

All visitors share the same entry point — the surface trade road — and are managed by the `VisitorManager` Autoload.

```gdscript
# VisitorManager Autoload
var active_visitors: Array[VisitorAgent]

signal visitor_arrived(visitor: VisitorAgent)
signal visitor_departed(visitor: VisitorAgent)
signal invasion_started(wave: InvasionWave)
```

Visitors enter from a fixed **world-edge entry node** placed by the world generator at the mountain's lowest accessible surface point. They must be able to pathfind from that node to their destination or they abort and turn back.

---

## Merchants

Trade is the third pillar of the core loop. Merchant caravans arrive periodically and conduct fully automated transactions with the colony's **Shop** room.

### The Shop Room

A **Shop** is a sealed room (enclosed walls + one or more doors) containing a `base:furniture:trade_counter` (Trade Counter). The room designation is emergent — place a Trade Counter and the room becomes a Shop; remove it or add an incompatible furniture item and it reverts to an undesignated room.

Full Trade Counter schema: `data/furniture/trade_counter.json`.

**Visit condition:** A caravan will only stop if the colony has an active Shop with at least one item in storage OR at least one active buy order on the Trade Counter. A shop with no stock and no buy orders is treated as closed — the caravan passes without stopping.

**Route requirement:** There must be a navigable surface path from the world-edge entry node to the Shop room entrance.

### Caravan Schedule

Caravans arrive on a seasonal cadence (28 in-game days per season):

| Season | Caravan Type | Frequency |
|---|---|---|
| Spring | Small Merchant (3 traders) | Always |
| Summer | Travelling Fair (luxury focus) | 70% chance |
| Autumn | Trade Expedition (bulk goods) | Always |
| Winter | Emergency Supplies (if colony starving) | Conditional |

Caravans depart after **5 in-game days** if they arrive and the shop is inactive, or immediately after the automated trade resolves.

### How Trade Works

Trade is fully automated. When a caravan reaches the Trade Counter, both sides of the transaction resolve without player intervention:

**Sell side** — the merchant checks every item in the shop room's storage against their want list. For each matching item, the merchant buys as much stock as available. The colony receives gold coins equal to units sold × price.

**Buy side** — the colony's active buy orders are checked against the merchant's catalog. For each matching item the merchant carries, the colony buys up to `max_count` units at or below `max_price_per_unit`. If the colony's coin balance is insufficient for the full order, **partial fill** applies: the colony buys as many units as coins allow. Purchased goods are placed in available shop room storage first; if storage is full, goods are dropped on the shop floor and dwarves haul them to appropriate colony stockpiles.

**Net coin transfer** — coins received from sales and coins spent on buy orders are settled in a single transaction. Gold coins are deposited into the nearest `stockpile_currency` stockpile, or dropped at the Trade Counter if none exists.

**Trade notification** — on completion a toast is posted: *"Trade complete — sold X items, bought Y items, net +Z coins."* The full transaction log is accessible from the Trade Counter inspect panel.

### What Merchants Buy

Merchants prioritise goods in this order:

| Priority | Item category | Example items |
|---|---|---|
| 1 | Dwarven alcohol | Ale, stout, mead, wine, gin, aged variants |
| 2 | Precious gems | Raw ruby, sapphire, diamond |
| 3 | Luxury stone | Marble blocks |
| 4 | Precious metals | Gold nuggets, silver ore |
| 5 | Crafted goods | *(future: jewellery, furniture)* |

Merchants will not buy raw stone, soil, or basic ore — only processed or high-value goods.

### Pricing

All items carry a `base_trade_value` in `data/entities/items/resources.json`. Actual trade prices fluctuate ±20% based on caravan type and recent transaction history. No separate price table is maintained here — the source of truth is the resource file.

### Demand Decay

If the colony sells the same item in 3 consecutive trade sessions, a demand modifier applies:

```
demand_modifier = max(0.5, 1.0 - (consecutive_sells × 0.15))
```

This encourages product diversification. The modifier resets when a different item is sold in its place.

### Buy Orders

The player configures buy orders on the Trade Counter via the UI. Each order specifies:

```
item_id            — namespaced item key, e.g. 'base:resources:ore:iron'
max_count          — maximum units to buy per visit
max_price_per_unit — colony will not pay above this price in gold coins
```

Buy orders are persistent standing orders — they re-evaluate on every merchant visit. What merchants can potentially sell is defined in `data/visitors/merchant_catalog.json`.

### Trade Reputation

A hidden `trade_reputation` score (0–100) accumulates across all merchant interactions:

```
+5   per completed trade session (at least one item sold or bought)
+10  if net coins gained > 50 in a single session
−5   if a caravan visits but the shop is inactive (no stock, no buy orders)
−10  if a caravan departs without trading due to no matching inventory
−20  if a caravan is attacked (future)
```

Reputation unlocks new caravan types and better prices at thresholds 25, 50, and 75.

### Caravan Special Events

Beyond standard trade, caravans may trigger special events:

| Event | Trigger Condition | Effect |
|---|---|---|
| Migrant Wave | Colony population < 10 AND trade_reputation > 50 | 2–6 new dwarves join |
| Diplomatic Message | Random, weighted by trade activity | Lore message, optional quest hook |
| Hostile Raid | Low colony defence rating (future) | Caravan is attacked en route |
| Supply Crisis | Colony has zero food for > 3 days | Emergency caravan with food only |
| Luxury Craving | Random in Summer | Merchant pays 2× price for a specific luxury item that visit |

### Merchant Signals

```gdscript
signal caravan_arrived(caravan: CaravanData)
signal caravan_departed(caravan: CaravanData, traded: bool)
signal trade_completed(sold: Dictionary, bought: Dictionary, net_coins: int)
signal caravan_attacked(caravan: CaravanData)   # future
```

### Merchant AI States

```
APPROACHING  → pathing to shop room entrance from world edge
TRADING      → at Trade Counter; automated transaction resolves (no player input)
DEPARTING    → pathing back to world edge after transaction or timeout
```

### Colony Wealth Score

`VisitorManager` maintains a hidden `wealth_score` (0–100) that also gates invader spawns. A colony that trades heavily and hoards gems will attract increasingly dangerous visitors — prosperity has a cost.

```
+1   per completed trade session
+2   per gem deposited into any stockpile
+3   per 10 gold coins net gain in a single trade session
−5   per successful invader raid (wealth was taken)
```

---

## Travelers

Travelers are individual wanderers passing through the mountain region. They carry little coin but provide passive income through the **Tavern** and **lodging** system.

### Infrastructure Requirements

| Feature | Required | Effect if absent |
|---|---|---|
| Tavern | `base:furniture:tavern_bar` in a sealed room | Traveler turns around and leaves |
| Traveler bed | Any bed flagged `traveler_bed = true` | Traveler drinks but does not stay overnight |

> **Note:** `base:furniture:tavern_bar` is not yet implemented. It will function as the room anchor for a Tavern room, where dwarves serve drinks to paying visitors.

### Traveler Behaviour

```
APPROACHING  → pathing to tavern room entrance from world edge
DRINKING     → seated at tavern, consuming 1 ale or mead per in-game hour
               pays base_trade_value × 0.6 gold coins per drink (below market rate)
LODGING      → claims an available traveler bed, sleeps 6 in-game hours
               pays flat 5 gold coins lodging fee on waking
DEPARTING    → pathing back to world edge
```

Travelers stay for **1–3 in-game days** depending on tavern stock and bed availability. A traveler who cannot find a drink within 2 in-game hours of arriving departs immediately, applying a small reputation penalty.

### Traveler Bed Designation

Any bed placed in the world can be toggled as a traveler bed via the UI. Traveler beds are never claimed by dwarves; dwarf beds are never claimed by travelers. A bed cannot be both simultaneously.

### Spawn Cadence

```
base_chance      = 0.15 per day
+0.10  if trade_reputation > 50
+0.10  if tavern room exists and ale stock > 5
+0.05  if at least 1 traveler bed is available
−0.10  if the last caravan was attacked (word spreads)
```

---

## Invaders

Invaders are hostile groups that attack the colony. They arrive without warning and must be repelled by the colony's defences.

> **Combat system is not yet implemented.** This section documents intent and data only. No combat code should be written until a dedicated combat design doc exists.

### Goblins

The most common threat. Fast, numerous, individually weak. Arrive in skirmishing groups.

| Property | Value |
|---|---|
| Group size | 3–8 |
| Health | Low |
| Speed | Fast |
| Attack damage | Low |
| Loot on defeat | Small coin, crude weapons *(future item)* |
| Trigger | `wealth_score > 30` OR `trade_reputation > 25` |
| Frequency | Every 15–30 in-game days once triggered |

### Orcs

Mid-tier threat. Tougher and fewer. Target workshops and stockpiles directly.

| Property | Value |
|---|---|
| Group size | 2–5 |
| Health | High |
| Speed | Medium |
| Attack damage | Medium–High |
| Loot on defeat | Iron ore, rations *(future item)* |
| Trigger | `wealth_score > 60` OR a gem stockpile exists |
| Frequency | Every 30–50 in-game days once triggered |

### Skeleton Warriors

Undead. Do not eat, drink, or sleep. Immune to morale effects. Active only at night.

| Property | Value |
|---|---|
| Group size | 2–6 |
| Health | Medium |
| Speed | Slow |
| Attack damage | Medium |
| Special | Active only between dusk and dawn; retreat when sun rises |
| Loot on defeat | Bone fragments, rusted sword *(future items)* |
| Trigger | Year ≥ 2 AND colony has at least one crypt/tomb block *(future)* |
| Frequency | 10% chance per winter night once triggered |

> **Agent note:** Skeleton retreat-at-dawn requires a dusk/dawn hook into `WorldClock`. Do not implement this until the day/night cycle (documented in `10_overview.md`) is complete.

### Invader AI States

```
APPROACHING  → pathing from world edge toward nearest colonist or workshop
ATTACKING    → engaging target in melee (future: combat system)
LOOTING      → stealing from nearest accessible stockpile if no dwarves nearby
RETREATING   → pathing back to world edge on heavy losses, or at dawn for skeletons
```

---

## Infrastructure Summary

| Visitor type | Required | Optional |
|---|---|---|
| Merchant | Shop room with `base:furniture:trade_counter` | High `trade_reputation`, active buy orders |
| Traveler | Tavern room with `base:furniture:tavern_bar` | Traveler beds, ale stock |
| Invader | *(none — they come regardless)* | Guard posts, walls *(future)* |

---

*Prev: [43_mining_materials.md](../40_economy_colony/43_mining_materials.md)*
