# 11 — Game Design Overview

**Implementation checkpoint — 2026-10-10:** the current playable foundation
includes seasonal day/night and weather, finite spring-fed rivers/lakes,
waterfalls, flooding, soil moisture, movable wet/dry stones with Allow/Disallow,
and rabbit/deer/wolf/duck wildlife. Ducks swim, visit banks and make short flights.
Gems drop as finished voxel goods; no Jeweller or polishing stage is planned.
Farming, physical brewing-water hauling and the production/trade loop described
below remain design goals. See [112 — Session handoff](../00_dev_roadmap/112_session_handoff_2026_10_10.md)
for the completed work and current limits.

1. Core Vision

**Deepdraft** is a modern, high-performance voxel colony management simulation focused on a subterranean dwarven settlement. The player acts as a high-level overseer, issuing global commands, managing production infrastructure, and orchestrating trade rather than directly controlling a single avatar.

2. Setting & Theme

- **The World**: An unforgiving, dangerous surface wilderness forces a desperate group of dwarven refugees to tunnel deep into a massive mountain in search of prosperity, safety, and shelter.
- **The Vibe**: Industrial, industrious, and cozy. The atmosphere emphasizes mechanical efficiency, heavy stone masonry, underground isolation, and the warm, comforting hum of dynamic brewery taverns.
- **The Contrast**: The title "Deepdraft" evokes both the act of drawing something up from deep underground and the pour of a hard-earned dwarven ale — the reward waiting at the end of every tunnel.

---

3. Core Gameplay Loop: "Dig, Brew, Trade"

The game operates on a continuous, interconnected economic loop that fuels both colony progression and dwarf morale:

```
 [ Mining Surface ] ──> Carve out Tunnels, Hidden Caverns & Precious Ore Veins
         │
         ▼
 [ Infrastructure ] ──> Construct Mushroom Farms, Water Wells & Brewing Vats
         │
         ▼
 [ Production ]     ──> Process Subterranean Crops into Premium Ales & Stouts
         │
         ▼
 [ The Economy ]    ──> Sell Beverages along the Trade Road for Luxuries & Migrants
```

- **Dig**: Tunnel through solid rock layers to expose open caverns, find vital water pockets, and discover rich veins of coal, iron, gold, and rare mithril crystals.
- **Brew**: Cultivate cave wheat and glowing fungi in moist underground soil. Mix crops with fresh water inside constructed brewing vats to ferment various tiers of dwarven alcohol.
- **Trade**: Maintain the mountain's fixed, un-minable trade road threshold. Sell your premium beverages, brilliant mined gems and crafted goods to seasonal caravans in exchange for surface resources, seeds, and new hopeful dwarf recruits.

---

4. Invariant Design Constraints (Non-Negotiable)

To ensure structural focus and guarantee optimal performance targets, the engine strictly enforces four core development boundaries:

1. **RTS Perspective Only**: Gameplay is strictly viewed through a top-down, smooth-orbiting god-view camera rig equipped with vertical layer slicing. Direct keyboard WASD character manipulation or third-person traversal is entirely excluded.
2. **Uniform Data Grid**: The underlying world simulation tracks space via a uniform 0.5m data array matrix. Individual terrain tiles do not utilize separate textures or polygon meshes; they are generated dynamically as flat-shaded, single-color voxel cubes.
3. **Entity Decoupling**: Untouched environment blocks are represented entirely as basic color indices inside a flat 1D data array. Highly detailed, high-density micro-voxel assets imported from MagicaVoxel exist purely as free-floating item drop entities or moving character scenes spawned _after_ a grid tile changes.
4. **Absolute Safety Nets**: The baseline array floor layers (Y = 0..3) consist of un-minable bedrock across the entire 1024 × 1024 plane, preventing physics logic loops or characters clipping into an empty void.

---

5. World Calendar & Seasonal Clock

The game world runs on a unified calendar managed by the `WorldClock` Autoload. All time-sensitive systems — flora growth, caravan scheduling, crop yields, and mood events — read from this single source.

### Time Scale

| Unit | Real time | Notes |
|---|---|---|
| 1 in-game hour | 60 real seconds | Base rate; player can set ×1, ×2, ×3 speed |
| 1 in-game day | 24 in-game hours (24 min real) | Full light/dark cycle on surface (cosmetic only underground) |
| 1 season | 28 in-game days | ~11.2 hours real at ×1 |
| 1 year | 4 seasons = 112 in-game days | ~44.8 hours real at ×1 |

```gdscript
# WorldClock Autoload — public interface
var day:     int       # 1–30 within the current season
var season:  String    # "spring" | "summer" | "autumn" | "winter"
var year:    int       # starts at 1
var hour:    float     # 0.0–23.99

signal season_changed(new_season: String)
signal day_changed(new_day: int)
```

### Season Transition Order

```
spring → summer → autumn → winter → spring → …
```

### Per-Season Effects

| System | Spring | Summer | Autumn | Winter |
|---|---|---|---|---|
| **Flora growth rate** | ×1.2 (thaw boost) | ×1.0 (baseline) | ×0.8 (slowing) | ×0.0 (dormant — no new growth) |
| **Flora model** | Spring variant if defined, else summer | Summer (primary) | Autumn variant if defined, else summer | Winter variant if defined, else summer |
| **Crop yield** | +10% bonus | Baseline | −10% penalty | No growth; existing crops freeze in place |
| **Caravans** | Small Merchant (always) | Travelling Fair (70%) | Trade Expedition (always) | Emergency Supplies (conditional) |
| **Mood thought** | `base:thought:warm_spring` (+0.04, 30 d) | none | `base:thought:harvest_plenty` (+0.03, 30 d) if food > 100 | `base:thought:winter_dark` (−0.04, 30 d) |

### Day/Night Cycle with Seasonal Day Length — Implemented

Day length must vary by season and transition smoothly — no sudden jumps at midnight or season boundaries.

**Day-length range:**
- Summer solstice: ~16 in-game hours of daylight, ~8 of night
- Winter solstice: ~8 in-game hours of daylight, ~16 of night
- Spring / Autumn equinoxes: ~12 / 12 (midpoint between extremes)

**Implementation approach:** Drive daylight duration with a cosine curve keyed to the day-of-year rather than snapping per season. Day-of-year runs 0–111 (112-day year). Summer solstice sits at day 28 (end of spring / start of summer); winter solstice at day 84 (end of autumn / start of winter).

```gdscript
# Returns daylight hours (float) for a given day-of-year (0–111)
func daylight_hours(day_of_year: int) -> float:
    const MEAN   := 12.0   # average daylight hours
    const AMPL   :=  4.0   # amplitude (±4 h gives 8–16 h range)
    const PERIOD := 112.0
    # Shift so day 28 = peak (cosine maximum)
    var angle := (day_of_year - 28.0) / PERIOD * TAU
    return MEAN + AMPL * cos(angle)   # ADD: cos=1 at day 28 (summer solstice) = longest day (16 h)
```

> **Correction (2026-06-02):** an earlier revision of this block used `MEAN - AMPL * cos(angle)`,
> which inverts the seasons (shortest day at the summer solstice). The sign is `+`. This is the
> form implemented in `WorldClock.daylight_hours()` and consumed by the sky day/night system
> (`docs/00_dev_roadmap/08_sky_plan.md`, Phase 3).

Within each in-game day, `SkyController` interpolates sun/moon and sky-gradient curves against `WorldClock.hour`, with one-hour twilight shoulders around sunrise and sunset. Surface ambient light follows the sky. `UndergroundLighting` gates daylight by physical sky access, while local lights illuminate covered interiors.

> **Implemented:** `WorldClock.daylight_hours()` supplies seasonal day length; `SkyController` drives the live sky, sun/moon and surface ambient lighting from `data/sky/sky_settings.json`. See [08 — Sky, Clock & Weather](../00_dev_roadmap/08_sky_plan.md) for the implementation reference.

### Implementation Notes

- Flora growth ticks are driven by `WorldClock.day_changed`. Each tick, every live flora entity reads `WorldClock.season` and applies the growth rate modifier.
- Dormant winter plants do not advance their `next_stage` timer. The timer is paused, not reset.
- Caravan spawning is triggered on `WorldClock.season_changed`. The caravan system in `12_trade_events.md` rolls its probability check immediately on receiving this signal.
- `WorldClock` is authoritative. No other system should track its own day/season counter.

---

*Next: [12_world_grid.md](./12_world_grid.md)*
