# 08 - Sky, Clock & Weather: Reference, Fog Post-Mortem & Open Items

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = keep / verified</span> |
> <span style="color:#d29922;">Yellow = review / tune</span> |
> <span style="color:#f85149;">Red = failed approach — do not repeat as-is</span>

Status: slimmed 2026-06-06. Originally the 2026-06-02/03 build-session record; the session
shipped and is the accepted baseline, so the recovery log, revert instructions, and
replay-from-scratch steps were removed (recoverable in git). What remains is the standing
reference: the live constraint that caused the blue-grass regression, the Stonehearth research,
the unsolved fog post-mortem, and the genuinely-open items.

---

## 1. <span style="color:#3fb950;">What exists (shipped & verified in-engine, 2026-06-03)</span>

All committed (`88c0a84` "fog", `bc7d86f` "dock update", merge `1c830cf`). Each system owns its
data file (Registry Pattern): JSON = what things are, GDScript = what they do.

| System | Does | Files |
|---|---|---|
| `WorldClock` | Ticking calendar: 1 game-day = 24 real min; hour→day→season→year rollover; `hour_changed`/`day_changed`/`season_changed` signals; `advance_hours()`/`advance_season()` test API | `scripts/systems/WorldClock.gd`, `data/calendar/calendar.json` |
| `SkyController` | Loads `sky_settings.json`; day/night sun+moon colour/pitch and sky-gradient curves keyed to calendar events, evaluated against `WorldClock.hour`; seasonal day length from the solstice cosine | `scripts/systems/SkyController.gd`, `data/sky/sky_settings.json` |
| `WeatherManager` | Per-season weighted pick (seeded from `world_seed`), daily switch, manual cycle; sky darkening + vision blending (~1.5 s) | `scripts/systems/WeatherManager.gd`, `data/calendar/weather_schedule.json`, `data/weather/{clear,foggy,overcast,snow}.json` |
| Clock dock UI | Live Season/Day/Time/Weather window + **+1 Hour** / **+1 Season** / **Weather →** test buttons | `scripts/ui/DockUI.gd`, `data/ui/dock.json` |
| Season recolour | `WorldRenderer._on_season_changed` re-queues overview/region/chunk meshes so palette edits show live | `scripts/systems/WorldRenderer.gd` |

Autoload order: `… WorldClock … UIRegistry, SkyController, WeatherManager` (Sky/Weather bind to
the scene one frame after `_ready`, since autoloads init before the main scene). The seasonal
day-length cosine fix (`+cos`, not `−cos`) lives in `11_overview.md` §5.

## 2. <span style="color:#f85149;">CONSTRAINT — do not transplant Stonehearth light hues into Godot</span>

This caused the original blue-grass regression and is **still an active footgun**:
`SkyController._apply_light()` normalises hue every frame —

```gdscript
light.light_color = Color(c.r / b, c.g / b, c.b / b)   # brightness -> energy; hue stays
```

— so a bluish RGB like Stonehearth's raw `[0.52, 0.52, 0.70]` becomes a **blue directional
light** `(0.74, 0.74, 1.00)` re-applied every frame, dragging all grass toward blue and ignoring
editor edits. Stonehearth's bluish values are tuned for *their* renderer (scattering, water
hacks — their own comments say so) and must not be copied into a Godot light's hue.

**Applied fix (2026-06-03, verified):** sun day `light_color = [0.67, 0.65, 0.62]` → hue
(1.0, 0.97, 0.93) near-white at energy ≈1.0 (the original scene sun); dawn `[0.55,0.45,0.35]` /
dusk `[0.60,0.47,0.36]` for warm-orange light. Max channel sets energy, so keep the max ≲0.7 to
avoid over-brightening. Alternative if ever needed: hardcode a warm-white hue in `_apply_light()`
and take only brightness from the curve.

## 3. <span style="color:#3fb950;">Verified Stonehearth findings (research — keep)</span>

Read from `P:\stonehearth` source; confirmed in code, not inferred:

- **Sky** = a camera-locked sphere sampling **one gradient texture: X = time-of-day, Y =
  horizon→zenith** (`skysphere.shader`). Day/night scrolls X; weather **crossfades** to a second
  gradient. Star layer fades in at night.
- **Calendar-keyed curves** (`sky_renderer_service.lua`): all sky/fog/light values are keyframed
  against named events (`sunrise_start … sunset_end`; sunrise 6, midday 14, sunset 21), lerped
  per frame.
- **Celestials**: sun + moon as directional lights with keyframed colour/angles; a light whose
  colour reaches (0,0,0) switches off (how the sun "sets"). Their bluish hues are renderer-tuned
  — see §2.
- **TWO independent fog systems** (the key discovery, and where fog went wrong):
  1. **Atmosphere** — `fullscreen_quad_height_fog.shader`, `height_fog [height, thickness, noise,
     distance]` (clear midday `[0,0.3,1,500]`, night `[100,0.5,1,100]`, foggy `[70,0.8,5,250]`).
     A mood/scattering layer tinted by `celestialLightColor`.
  2. **Edge dissolve** — `voxel/fog.shader` in the `Fog` stage: redraws geometry in the **far 30%
     of the frustum** (`frustum_start="0.7"`) with `fogFac = clamp(depth²/farPlane²·2−1, 0, 1)`
     and **`fogColor = the rendered sky sampled at that screen pixel`** (`skySampler` ← `SkyTemp`).
     Opaque exactly at the far plane. **This per-pixel sky sampling is why their terrain edge and
     sky are ONE line** (§4).
- **Weather** (`weather_service.lua`): per-season weighted random, plans 3 days ahead, switches
  at 04:30, previous weather lingers a day; each def carries `sky_settings` + `vision_multiplier`
  (foggy 0.4, applied to the gameplay sight radius, separate from fog) + `is_dark_during_daytime`
  + snow accumulation per minute.

## 4. <span style="color:#f85149;">Fog post-mortem — read before ANY new fog attempt</span>

Every fog approach in the session failed. The chain, so it is never repeated blind:

| Attempt | Result | Why it failed |
|---|---|---|
| Environment **depth fog** pinned to far clip | invisible | Godot depth-fog mode produced no effect on this scene |
| Saturate-before-clip (wider band, curve 0.8) | invisible | tuning a mode that wasn't rendering |
| **Red diagnostic** (exponential, density 0.02) | **terrain went red** | ✅ the useful step: proved Environment fog *does* reach terrain; the dead layer was depth *mode* |
| Exponential, sky-horizon colour, density 3.0/view | whole scene washed out | exponential tints *everything*; a flat grey ≠ sky |
| Custom terrain shader (ALBEDO→EMISSION fade) | **two distinct lines** — terrain cutoff + sky horizon | the fundamental issue, below |

**Fundamental issue (Alen identified it):** screenshots showed *two* lines — where blocks end and
where the sky's horizon band starts. Stonehearth has **one** because its fog colour is **the sky
pixel directly behind each fragment**. A **flat** fog colour can never merge the two: terrain fades
to one constant while the sky behind it is a gradient, and the far-clip cutoff doesn't coincide
with the sky's visual horizon.

**Requirements for a correct future attempt (not yet tried):**
1. Fog colour must equal **the sky behind the pixel** — render the sky to a texture and sample it
   in the terrain shader (Stonehearth's method), or compute the ProceduralSky analytic colour for
   the fragment's view direction in-shader (same maths, no texture).
2. Verify the render mechanism with an unmistakable diagnostic **before** tuning values.
3. One variable per change, screenshot per change — in-engine; headless maths can't validate looks.
4. Calibrate the sky to clean blue first; a grey horizon band makes every fade read as murk.

Current state: `SkyController.MANAGE_FOG = false`; `WorldRenderer` uses the original
`StandardMaterial3D`; fog = the scene's authored Environment. Safe.

## 5. <span style="color:#d29922;">Open items / next steps</span>

1. **Sky colours are hand-authored placeholders** — calibrate against Stonehearth screenshots
   (bluer, brighter; midday was kept identical to the pre-session scene). *2026-06-03:* full-360
   diorama sky applied — `ground_bottom` mirrors the horizon keyframes (no dark below-horizon
   band; the world floats in continuous atmosphere). Also eases the §4 "two lines" problem for any
   future fog. Revert by dimming `ground_bottom` toward the old values (noted in the JSON).
2. **Fog** — only per §4, as its own carefully-tested effort. A correct sky-matched fog also
   unlocks a **performance lever** (folded in from `07_performance_tuning.md`): once an honest fog
   dissolves the horizon, the draw/build distance can be capped to the fog distance — fewer far
   tiles built and drawn. Today the scene uses a static Environment fog (`fog_depth_end = 170`)
   under `far_clip = 1200` with no honest cap; a time/weather height fog whose colour matches the
   sky-gradient background would let us tie the built-tile budget to the visible distance.
3. **`vision_multiplier` is visual-only** — coupling it to the streaming radius is deferred
   (startup performance is already solved; see `07_performance_tuning.md`).
4. **Phase 5 polish, unstarted:** starfield, sine rise/set ramp, snow accumulation, weather mood.

---

*Prev: [07_performance_tuning.md](./07_performance_tuning.md)*
