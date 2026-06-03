# 09 - Grass Colour Tuning (Seasonal Palettes)

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = keep / verified</span> |
> <span style="color:#d29922;">Yellow = observation / to tune</span> |
> <span style="color:#f85149;">Red = candidate values, NOT yet applied</span>

Status: created 2026-06-03 from Alen's in-engine review of all four seasons, right after the
season-recolour wiring landed (`08_sky_plan.md` step 5). This is a **data-only tuning task** —
no code changes are needed for anything in this document.

---

## 1. <span style="color:#3fb950;">How grass colour works (verified)</span>

1. `data/terrain/surface_palettes.json` defines a hex colour per variant per season
   (`grass_01…grass_08`, `dirt_01…dirt_04` × spring/summer/autumn/winter).
2. `BlockRegistry.get_color(id, season)` resolves it; the renderer **bakes it into mesh vertex
   colours at build time** (ChunkMesher / regions / overview tiles).
3. Since 2026-06-03, `WorldRenderer._on_season_changed` re-queues all built meshes on
   `WorldClock.season_changed`, so palette edits are testable live: **run → Clock window →
   +1 Season → watch the ~few-second sweep.** One season per look; screenshots for comparison.
4. **Runtime lighting tints the baked colours.** The sun is warm-white (08 §1a), but ambient is
   *sky-sourced* — the blue-grey summer sky adds a cool cast on top of the palette. So "summer
   looks blueish" can be addressed in the palette, the sky colours (`sky_settings.json`
   `sky_gradient_colors`), or both. Tune the palette first; revisit sky if a cast remains.

**Variant → domain mapping** (from `43_mining_materials.md` / the palette comments):
`grass_01–04` = lower plains / settlement (01 = outer edge ring → 04 = base interior);
`grass_05–08` = valley / highland / foothill (edge pairs likewise).

## 2. Current palette (as committed)

| Variant | Spring | Summer | Autumn | Winter |
|---|---|---|---|---|
| grass_01 | `#9CCD83` | `#AFCC7C` | `#AACE65` | `#C8C773` |
| grass_02 | `#8FC880` | `#9DBF76` | `#A7C35E` | `#C1C26D` |
| grass_03 | `#86C37C` | `#94B873` | `#A6BD5B` | `#BCBD6A` |
| grass_04 | `#7EBB78` | `#8BB270` | `#A5BA59` | `#B7B867` |
| grass_05 | `#89BC7D` | `#82A979` | `#999456` | `#D8E3EA` |
| grass_06 | `#7FB274` | `#789C72` | `#8E894F` | `#D1DEE7` |
| grass_07 | `#6EA66F` | `#668A6A` | `#827A48` | `#CAD8E1` |
| grass_08 | `#5D9565` | `#587C64` | `#6E6940` | `#BFCDD8` |

(Dirt variants exist too — `dirt_01–04` — no observations recorded yet.)

## 3. <span style="color:#d29922;">Observations — Alen, 2026-06-03 (in-engine, clear weather, afternoon)</span>

| Season | Verdict | Affected entries | Notes |
|---|---|---|---|
| **Spring** | ✅ looks great | — | keep as-is; reference point for the others |
| **Summer** | blueish | likely `grass_05–08` summer (cool, blue-leaning greens: `#82A979→#587C64`), possibly + sky ambient | wants warmer / more yellow-green; check whether part of the cast is the blue sky-sourced ambient (§1.4) |
| **Autumn** | `05–08` good (olive/gold); **`01–04` too bright green** | `grass_01–04` autumn (`#AACE65`, `#A7C35E`, `#A6BD5B`, `#A5BA59`) | the lowland set stays lime while the highlands turn — shift toward warm gold/olive to match |
| **Winter** | bright | `grass_05–08` winter near-white (`#D8E3EA→#BFCDD8`); `01–04` pale khaki | reduce lightness so winter reads frosted, not glowing; keep the cool tint (it's the design) |

## 4. <span style="color:#f85149;">Candidate values — proposals only, NOT applied</span>

Eyeballed starting points honouring the observations; apply one season at a time and judge
in-engine. Edge→interior ordering (01→04, 05→08) is preserved.

**Summer `grass_05–08` (warmer, less blue):**
`#82A979 → #85A96B` · `#789C72 → #7A9C64` · `#668A6A → #6B8A59` · `#587C64 → #5E7C50`

**Autumn `grass_01–04` (lime → warm gold-olive):**
`#AACE65 → #B5B45C` · `#A7C35E → #ADA855` · `#A6BD5B → #A6A050` · `#A5BA59 → #9E984B`

**Winter, all (dim ~10–15%, keep the cool/khaki hues):**
`05–08`: `#D8E3EA → #C2CDD6` · `#D1DEE7 → #BCC8D3` · `#CAD8E1 → #B5C3CE` · `#BFCDD8 → #AABAC6`
`01–04`: `#C8C773 → #B3B268` · `#C1C26D → #ADAE63` · `#BCBD6A → #A8A95F` · `#B7B867 → #A3A45C`

## 5. Tuning workflow

1. Edit `data/terrain/surface_palettes.json` (one season's row-set per pass).
2. Run, open the Clock window, **+1 Season** to the season under review; let the sweep finish.
3. Screenshot at a consistent time of day (~14:00, Clear weather) for fair comparison —
   time of day and weather darkening change the perceived colour.
4. If summer still reads blue after palette tuning, the remaining cast is the sky-sourced
   ambient → tune `sky_gradient_colors` day values in `data/sky/sky_settings.json` next.
5. Commit per accepted season.

---

*Prev: [08_sky_plan.md](./08_sky_plan.md)*
