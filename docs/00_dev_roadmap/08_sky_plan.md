# 08 - Sky, Clock & Weather: Session Record and Replay Guide

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = keep / verified</span> |
> <span style="color:#d29922;">Yellow = review / tune</span> |
> <span style="color:#f85149;">Red = failed approach — do not repeat as-is</span>

Status: rewritten 2026-06-03 as the **session record** after the 2026-06-02 build session ended
with a blue-grass regression. This doc explains exactly what was built, where it lives in git,
what broke and why, and how to replay or discard each piece.

---

## 0. <span style="color:#3fb950;">Where the work lives — nothing is lost</span>

The entire session is **committed**:

| Commit | Contents |
|---|---|
| `88c0a84` "fog" | All systems + data: `WorldClock` (ticking), `SkyController`, `WeatherManager`, `data/calendar/*`, `data/sky/*`, `data/weather/*`, autoload registrations, `11_overview.md` formula fix, camera `far_clip` 512 |
| `bc7d86f` "dock update" | `DockUI` (clock window, +1 Hour / +1 Season / Weather buttons), `dock.json` icons |
| `1c830cf` | Merge of the two |

**To discard everything from the session:** `git revert 1c830cf` (or reset to `6bf72ae` "June2nd start").
**To keep it and fix the blue grass:** apply §1 below — it is a small fix, not a rebuild.

> **RECOVERY COMPLETED 2026-06-03** via staged re-enable, each step verified in-engine by Alen:
> 1. clock-only (Sky/Weather autoloads off) ✅ → 2. warm-white sun data (§1a) ✅ →
> 3. `SkyController` re-enabled — green grass at midday, warm dusk, night fade ✅ →
> 4. `WeatherManager` re-enabled — weather names + cycling + darkening ✅.
> Also fixed a merge artifact: `SkyController` line 140 called `_find_node_with_method()` (renamed
> in the external merge) instead of the defined `_find_by_method()` — a parse error that made the
> whole autoload `<null>`. Cross-checked both systems for further undefined calls: none.
> **Current state: everything from the session works except fog (off by design, §5).**

---

## 1. <span style="color:#f85149;">THE BLUE GRASS — root cause and fix</span>

This is what ended the session, and it has a precise cause. Two contributors:

### 1a. The sun light is blue (primary — persists at all times, looks "unfixable")

`data/sky/sky_settings.json` seeds the sun's daytime `light_color` with Stonehearth's raw value
`[0.52, 0.52, 0.70]`. `SkyController._apply_light()` then **normalises the hue**:

```gdscript
light.light_color  = Color(c.r / b, c.g / b, c.b / b)   # [0.52,0.52,0.70] -> (0.74, 0.74, 1.00) = BLUE
light.light_energy = b * energy_scale
```

Result: the entire world is lit by a **blue directional light** (plus blue sky-sourced ambient),
shifting green grass toward blue. Because `SkyController` re-applies this **every frame**, editing
the light or Environment in the editor appears to do nothing — hence "unfixable." Stonehearth's
bluish light values work in *their* renderer (different lighting model, scattering, water hacks —
their own comments say so); they must **not** be transplanted into a Godot light's hue.

**Fix (choose one):**
- *Data fix — APPLIED 2026-06-03:* in `sky_settings.json`, sun day `light_color` is now
  `[0.67, 0.65, 0.62]` → hue (1.0, 0.97, 0.93) near-white, energy 0.67×1.5 ≈ **1.0 — the original
  scene's sun**. Dawn `[0.55, 0.45, 0.35]` / dusk `[0.60, 0.47, 0.36]` give warm-orange light at
  ~0.83/0.90 energy. (Note: values like `[1.0, 0.97, 0.92]` would over-brighten — max channel sets
  energy, so 1.0 → energy 1.5.)
- *Code fix:* in `_apply_light()`, use a fixed warm-white hue and take only **brightness** from the
  curve: `light.light_color = Color(1.0, 0.98, 0.94)` and keep `light_energy = b * energy_scale`.
- *Off switch:* remove the `SkyController` autoload from `project.godot` (sky/lights revert to the
  scene; the clock and weather still run harmlessly).

### 1b. Winter grass palette is icy blue-white (secondary — after "+1 Season")

`data/terrain/surface_palettes.json` (authored **before** this session) defines winter grass such
as `grass_05 = #D8E3EA` — icy blue-white, by design. `ChunkMesher` bakes the **current season's**
palette into vertex colours at mesh-build time. Pressing the Clock window's **+1 Season** into
winter makes newly-rebuilt chunks bake the icy palette (and mixes with older summer-baked meshes).
A restart returns to summer (`calendar.json` start) — this one fixes itself; it is listed so the
"+1 Season" test button is not mistaken for a bug. Known follow-up: rebuild surface meshes on
`season_changed` so seasons recolour consistently.

---

## 2. <span style="color:#3fb950;">What was built and verified (keep)</span>

| Phase | Deliverable | Files | Status |
|---|---|---|---|
| 0 — Ticking clock | 1 in-game day = 24 real min; rolls hour→day→season→year; signals `hour_changed`/`day_changed`/`season_changed`; speed/pause; 24h `time_string()`; `advance_hours()`/`advance_season()` test API | `scripts/systems/WorldClock.gd`, `data/calendar/calendar.json` | ✅ worked in-engine |
| UI | Live Clock dock window (Season/Day/Time/Weather) + **+1 Hour**, **+1 Season**, **Weather →** test buttons | `scripts/ui/DockUI.gd`, `data/ui/dock.json` | ✅ worked in-engine |
| 1 — Data-driven sky | `SkyController` autoload loads `sky_settings.json`, applies the static look (data → Environment pipeline) | `scripts/systems/SkyController.gd`, `data/sky/sky_settings.json` | ✅ worked in-engine |
| 2 — Day/night | Keyframed sun/moon colour+pitch, sky gradient colours, evaluated against `WorldClock.hour` (~20 Hz), runtime Moon light, 24h wraparound interpolation | same files | ✅ motion confirmed in-engine — but see §1a (blue sun) |
| 3 — Seasonal day length | Sunrise/sunset event hours recomputed daily from the solstice cosine (summer ~16 h lit, winter ~8 h); **fixed the inverted sign in `11_overview.md` §5** (`+cos`, not `−cos`) | same + `docs/10_core_foundation/11_overview.md` | ✅ verified by user |
| 4 — Weather | `WeatherManager` autoload: per-season weighted pick (seeded), daily switch, manual cycle; sky darkening + vision blending | `scripts/systems/WeatherManager.gd`, `data/calendar/weather_schedule.json`, `data/weather/{clear,foggy,overcast,snow}.json` | ✅ switching confirmed in-engine |
| Fog | — | — | ❌ all approaches failed; full post-mortem in §5. Fog driving is OFF (`MANAGE_FOG = false`); fog = scene Environment |

All rollover/interpolation/weighted-pick math was validated headlessly (Python ports) before
shipping; the items marked ✅ were additionally confirmed running by Alen.

**Architecture (per AGENT.md rules):** JSON = what things are, GDScript = what things do. Each
system owns its data file (Registry Pattern): `WorldClock` ← `calendar.json`; `SkyController` ←
`sky_settings.json`; `WeatherManager` ← `weather_schedule.json` + `weather/*.json`. Autoload order:
`… WorldClock … UIRegistry, SkyController, WeatherManager` (Sky/Weather bind to the scene one frame
after `_ready` because autoloads initialise before the main scene).

---

## 3. <span style="color:#3fb950;">Replay steps (in session order)</span>

If rebuilding from scratch (e.g. after a revert), this is the order that worked:

1. **Master data files first.** `data/calendar/calendar.json` (time scale 60 s/game-hour, 24 h/day,
   28 d/season, season order, start date, the 8 named `event_times`, `day_length_curve`),
   `data/calendar/weather_schedule.json` (per-season weighted table),
   `data/sky/sky_settings.json` (environment base + keyframed sun/moon/sky-gradient curves, keyed
   by event *names*), `data/weather/*.json` (base+override model: `vision_multiplier`,
   `is_dark_during_daytime`, `sky_overrides`). All current files validate and cross-reference.
2. **Phase 0 — make `WorldClock` tick.** `_process` advances `hour += delta×speed/real_s_per_hour`;
   `while hour >= 24` roll a day; day > 28 rolls season (emit `season_changed` *before*
   `day_changed`); season wrap rolls year. Emit `hour_changed` only on whole-hour boundaries.
   Test: 1440 s at ×1 = exactly +1 day and 24 hour-ticks; 112 days = +1 year, seasons cycle.
3. **Clock window + test buttons** in `DockUI` (`toggle_window` target `"clock"`): live labels
   (throttled `_process` ~10 Hz, only while open) + buttons calling `WorldClock.advance_hours(1)`,
   `advance_season()`, `WeatherManager.cycle_weather()`. These made every later phase testable.
4. **Phase 1 — `SkyController` static.** Autoload; `await get_tree().process_frame`; find
   `WorldEnvironment`/`DirectionalLight3D`/`Camera3D` by class; apply the `environment` block.
   No visual change = pipeline proven.
5. **Phase 2 — day/night.** Build curves as sorted `[hour, value]` arrays (event name → hour via
   the calendar), evaluate at `WorldClock.hour` with 24 h wraparound, lerp; drive sky gradient
   colours, fog-independent ambient (sky-sourced, darkens free), sun/moon colour+pitch (create the
   Moon at runtime, shadows off). **Apply §1a here: warm-white sun hue, curve = brightness only.**
6. **Phase 3 — seasonal day length.** Recompute the rise/set event hours each day/season change:
   `daylight = mean + ampl·cos((doy − summer_solstice)/total·TAU)` (**+cos** — the doc had it
   inverted), `sunrise = midday − daylight/2`, `sunset = midday + daylight/2`, ±1 h twilight
   shoulders; rebuild curves on `day_changed`/`season_changed`. Summer ≈ 05–23 lit, winter ≈ 10–18.
7. **Phase 4 — weather.** `WeatherManager`: load defs + schedule, seed RNG from
   `WorldGenerator.world_seed`, pick per season (weighted), switch on `day_changed`, hand the dict
   to `SkyController.apply_weather()` which smooths darken/vision targets (~1.5 s blend).
8. **Fog — do NOT replay any of the session's fog attempts.** Read §5 first.

---

## 4. <span style="color:#3fb950;">Verified Stonehearth findings (the research — keep)</span>

Read from `P:\stonehearth` source; all confirmed in code, not inferred:

- **Sky** = a camera-locked sphere sampling **one gradient texture: X = time-of-day, Y =
  horizon→zenith** (`skysphere.shader`). Day/night scrolls X; weather **crossfades** to a second
  gradient (`transition factor`). Star layer fades in at night.
- **Calendar-keyed curves** (`sky_settings.json` + `sky_renderer_service.lua`): all sky/fog/light
  values are keyframed against named events (`sunrise_start … sunset_end`, from
  `calendar_constants.json`: sunrise 6, midday 14, sunset 21), linearly interpolated per frame.
- **Celestials**: sun + moon as directional lights with keyframed colour/ambient/angles; a light
  whose colour reaches (0,0,0) switches off (how the sun "sets"). **Their bluish light values are
  tuned for their renderer — do not transplant the hues into Godot lights (§1a).**
- **TWO independent fog systems** (the session's key discovery, and where it went wrong):
  1. **Atmosphere** — `fullscreen_quad_height_fog.shader`, the `height_fog [fog_height, thickness,
     noise, distance]` params (clear midday `[0, 0.3, 1, 500]`, night `[100, 0.5, 1, 100]`, foggy
     `[70, 0.8, 5, 250]`). A mood/scattering layer tinted by `celestialLightColor`.
  2. **Edge dissolve** — `voxel/fog.shader` in the `Fog` pipeline stage: redraws geometry in the
     **far 30% of the frustum** (`frustum_start="0.7"`) with
     `fogFac = clamp(depth²/farPlane²·2−1, 0, 1)` and **`fogColor = the rendered sky sampled at
     that screen pixel`** (`skySampler` ← `SkyTemp` buffer). Opaque exactly at the camera far
     plane. **This per-pixel sky sampling is why their terrain edge and sky are ONE line** (§5).
- **Weather** (`weather_service.lua`): per-season weighted random, plans 3 days ahead, switches at
  04:30, previous weather lingers a day; each weather def carries `sky_settings` +
  `vision_multiplier` (foggy 0.4 — applied to the gameplay *sight radius*, separate from fog) +
  `is_dark_during_daytime` + snow accumulation per minute.

---

## 5. <span style="color:#f85149;">Fog post-mortem — read before any new fog attempt</span>

Every fog approach failed. The chain, so it is never repeated blind:

| Attempt | Result | Why it failed |
|---|---|---|
| Godot Environment **depth fog** pinned to far clip (begin 0.7×far, end = far) | invisible | Godot's depth-fog mode produced no visible effect on this scene (confirmed later by diagnostic) |
| Saturate-before-clip (end 0.9×far, wider band, curve 0.8) | invisible | same — tuning values on a mode that wasn't rendering |
| **Red diagnostic** (exponential mode, red, density 0.02) | **terrain went fully red** | ✅ the only useful step: proved Environment fog *does* reach the terrain; the dead layer was depth *mode*, not the material/render path |
| Exponential fog, sky-horizon colour, density 3.0/view | whole scene washed out | exponential tints *everything* (18 %+ even in the foreground); flat grey fog colour ≠ sky |
| Custom terrain shader (faithful `calcFogFac`, ALBEDO→EMISSION fade) | **two distinct lines** — terrain cutoff and sky horizon | the fundamental issue, below |

**The fundamental issue (Alen identified it):** the screenshots showed *two* lines — one where the
blocks end, one where the sky's horizon band starts. In Stonehearth there is **one** line, because
their fog colour is **the sky pixel directly behind each fragment** — terrain provably converges to
whatever the sky shows there. A **flat** fog colour (everything the session tried) can never merge
the two lines: the terrain fades to one constant colour while the sky behind it is a *gradient*,
and the terrain cutoff (far clip) does not coincide with the sky's visual horizon.

**Requirements for a correct future attempt (not tried this session):**
1. Fog colour must equal **the sky behind the pixel** — either render the sky to a texture and
   sample it in the terrain shader (Stonehearth's actual method), or compute the ProceduralSky's
   analytic colour for the fragment's view direction inside the terrain shader (same gradient
   maths, no texture needed).
2. Verify the render mechanism with an unmistakable diagnostic **before** tuning any values.
3. One variable per change, screenshot per change — in-engine; headless maths cannot validate looks.
4. Calibrate the sky to a clean blue first; a grey horizon band makes every fade read as murk.

Current state: `SkyController.MANAGE_FOG = false` (no fog driving); `WorldRenderer` uses the
original `StandardMaterial3D`; fog = the scene's authored Environment. Safe.

---

## 6. <span style="color:#d29922;">Open items / next steps</span>

1. ~~Fix the blue sun~~ — **DONE and verified in-engine 2026-06-03** (§1a).
2. Surface meshes don't recolour on `season_changed` (winter palette bakes only into rebuilt
   chunks) — wire a surface-mesh refresh to the signal.
3. Sky colours are hand-authored placeholders — calibrate against Stonehearth screenshots
   (bluer, brighter; midday was kept identical to the pre-session scene).
4. Fog — only per §5, as its own carefully-tested effort.
5. `vision_multiplier` is visual-only; coupling to the streaming radius (doc 06 budget) deferred.
6. Starfield, sine rise/set ramp, snow accumulation, weather mood thoughts — Phase 5 polish, unstarted.

---

*Prev: [07_performance_tuning.md](./07_performance_tuning.md)*
