# 08 - Sky, Fog & World Edge Plan

Status: Stonehearth source review complete, 2026-06-02.

This plan replaces the earlier sky draft. It is based on direct review of Stonehearth's sky,
weather, atmosphere, and fog files in `P:\stonehearth`.

## Core Finding

Stonehearth's sky appears to go completely around the map, but it is **not** a fixed shell around
the terrain. It is a camera-centered sky backdrop:

- The sky geometry follows the camera.
- It renders behind everything with depth disabled.
- The shader samples a vertical sky gradient by time of day and height.
- Terrain edges disappear because fog blends distant world pixels into sky-colored haze before the
  edge becomes visually important.

So the important lesson is not "build a huge sky around the map." The lesson is:

> Render an always-distant sky, then make distant terrain fade into a matching sky/fog color.

## Stonehearth Files Reviewed

Key files:

- `services/client/sky_renderer/sky_renderer_service.lua`
- `services/client/weather_render/weather_render_service.lua`
- `services/server/weather/weather_service.lua`
- `services/server/weather/weather_state.lua`
- `data/calendar/sky_settings.json`
- `data/calendar/calendar_constants.json`
- `data/weather/*/*_sky_settings.json`
- `data/horde/shaders/skysphere.shader`
- `data/horde/shaders/fullscreen_quad_height_fog.shader`
- `data/horde/shaders/utilityLib/atmosphere.glsl`
- `data/horde/shaders/utilityLib/fog.glsl`
- `data/horde/shaders/voxel/deferred_attributes.shader`
- `data/horde/materials/skysphere.material.json`

## What Stonehearth Does

### Camera-Centered Sky

`skysphere.shader` offsets sky vertices by `camViewerPos`:

```glsl
worldPos += vec4(camViewerPos, 1.0);
```

The sky material uses no depth test/write. This makes the sky effectively infinite from the
player's perspective. The player can never pan to the sky geometry or reveal where it begins.

The fragment shader samples:

```glsl
vec2 uv = vec2(parameters.x, gradient);
```

`parameters.x` is normalized time of day. `gradient` is vertical position on the sky. This means
Stonehearth's sky is a **time by height gradient texture**, not a panoramic image.

### Time-Keyed Sky Data

`calendar_constants.json` defines named events:

| Event | Hour |
|---|---:|
| midnight | 0 |
| sunrise_start | 5 |
| sunrise | 6 |
| sunrise_end | 7 |
| midday | 14 |
| sunset_start | 20 |
| sunset | 21 |
| sunset_end | 22 |

`sky_renderer_service.lua` expands these into softer rise/set sub-events:

- `sunrise_peak_start`
- `sunrise_peak_mid`
- `sunrise_peak_end`
- `sunset_peak_start`
- `sunset_peak_mid`
- `sunset_peak_end`

Sky colors, sun colors, moon colors, fog values, and scattering are all interpolated through these
named events.

### Sun and Moon Drive Lighting

Stonehearth creates directional lights for sun and moon. Each has keyframed:

- `light_colors`
- `ambient_colors`
- `angles`
- `depth_offset_values`

The renderer picks the brightest active celestial as the important light and pushes its color and
position into global uniforms:

- `celestialLightPos`
- `celestialLightColor`

When a celestial's color becomes black, the light is disabled. That is how the sun sets and moon
rises.

### Fog Color Is Coupled to Sky Lighting

The fullscreen height fog pass computes:

```glsl
gl_FragColor = (celestialLightColor * heightFogColorMult) * foggyness;
```

So fog is not an unrelated grey overlay. It is tinted by the active sun or moon color, with a
weather/time multiplier.

This is the main reason Stonehearth's horizon looks coherent: sky, lighting, and fog are authored
from the same time/weather data.

### Height Fog Values

Default sunny `height_fog` values from `data/calendar/sky_settings.json`:

| Time | Fog height | Thickness | Noise | Distance |
|---|---:|---:|---:|---:|
| midnight | 100 | 0.5 | 1 | 100 |
| sunrise_end | 50 | 0.4 | 1 | 150 |
| midday | 0 | 0.3 | 1 | 500 |
| sunset_end | 50 | 0.4 | 1 | 150 |
| day_length | 100 | 0.5 | 1 | 100 |

Decoded:

- `fog_height`: vertical height below which ground fog accumulates.
- `thickness`: fog opacity/density.
- `noise`: animated breakup strength. Stonehearth has parts of this disabled/commented because it
  was visually unstable.
- `distance`: effective view distance. Larger means farther visibility.

### Weather Swaps Sky Settings

Weather JSON points to a sky settings file:

```json
{
  "sky_settings": "stonehearth:sky_settings:foggy",
  "vision_multiplier": 0.4,
  "hide_cloud_shadows": true,
  "is_dark_during_daytime": true
}
```

When weather changes, `weather_render_service.lua` calls:

```lua
stonehearth.sky_renderer:transition_sky(sky_settings, 2500)
```

That crossfades:

- sky gradient texture
- sun and moon colors
- light angles
- ambient colors
- height fog
- scattering
- starfield brightness

Weather also applies a gameplay `vision_multiplier` through the terrain service. Foggy weather, for
example, both looks foggier and reduces sight radius.

### World Edge Treatment

Stonehearth does not use a special map-edge shader or boundary wall.

The edge treatment is a combination of:

- camera-centered sky behind everything
- terrain fog/atmosphere data written by terrain shaders
- fullscreen fog blending distant pixels into sky-colored haze
- far terrain being visually obscured before the camera reaches a harsh edge
- dense edge foliage helping hide low-angle boundaries

The important practical result:

> The visible map edge dissolves into sky-colored fog. The sky itself is always available behind
> the terrain because it follows the camera.

## What Deepdraft Should Copy

Deepdraft should copy the behavior, not the Horde3D implementation.

### 1. Keep the Sky Camera-Infinite

Use Godot's `WorldEnvironment` sky or a custom `Sky` shader as an always-distant background. Do not
build a physical sky cylinder or wall around the `1024 x 1024` map.

For a faithful Stonehearth-like version, use a custom sky shader with:

- gradient texture sampled by time of day and vertical sky direction
- optional target gradient for weather crossfade
- no visible horizon geometry

For the simpler version, continue using `ProceduralSkyMaterial` and drive:

- `sky_top_color`
- `sky_horizon_color`
- `ground_bottom_color`
- `ground_horizon_color`

### 2. Match Fog to the Sky Horizon

The fog color should be nearly identical to the current sky horizon color.

For Godot:

- `Environment.fog_light_color` should track sky horizon color or active sun/moon color.
- `fog_aerial_perspective` should stay enabled when it helps distant terrain blend toward the sky.
- Fog should hide the far clip before terrain visibly cuts off.

### 3. Separate Mood Fog From Edge-Hiding Fog

Stonehearth has two useful ideas:

- atmospheric fog for mood and time/weather
- distance/edge fog that prevents far terrain cuts from showing

Deepdraft can approximate both with Godot environment fog:

- Mood: density, color, and optional volumetric/height fog.
- Edge hiding: ensure fog reaches near-full opacity before the camera far clip.

The edge hiding goal is the non-negotiable one. The player should not see a hard far clip line.

### 4. Keep Weather Data-Driven

Weather should own:

- display name
- fog override
- sky color/gradient override
- `vision_multiplier`
- snow accumulation
- dark-during-day flag
- future mood thoughts

Weather should not directly modify terrain identity.

### 5. Keep the Underground Slice Void Dark

The sky system is for above-ground and world-edge presentation. It must not brighten the black slice
void above underground rooms. That black void is part of the slice-view language and should continue
to read as solid mountain overhead.

## Deepdraft Target Architecture

### Existing Files

Current relevant Deepdraft files:

- `scenes/main/debug_world.tscn`
- `scripts/systems/SkyController.gd`
- `scripts/systems/WeatherManager.gd`
- `scripts/systems/WorldClock.gd`
- `data/sky/sky_settings.json`
- `data/weather/*.json`
- `data/calendar/calendar.json`
- `data/calendar/weather_schedule.json`

### Owner Responsibilities

`WorldClock`:

- owns calendar time
- emits hour/day/season signals
- computes day-of-year and seasonal daylight length

`SkyController`:

- owns `data/sky/sky_settings.json`
- binds to `WorldEnvironment`, sun, moon, and camera
- applies current sky colors
- applies current fog color/density/distance
- interpolates time-of-day curves
- receives weather overrides

`WeatherManager`:

- owns `data/weather/*.json`
- owns `data/calendar/weather_schedule.json`
- chooses current weather by season
- applies weather to `SkyController`
- exposes current weather to UI/debug

`WorldRenderer` / camera:

- should eventually respect weather `vision_multiplier`
- should avoid rendering terrain beyond fog-hidden distance where possible

## Implementation Plan

### Phase 1 - Clean Stonehearth-Style Baseline

Goal: make the current static sky/fog clearly match Stonehearth's edge behavior.

- Keep or create a `WorldEnvironment`.
- Set a calm daytime sky with horizon color matched to fog.
- Use exponential or depth fog so terrain fades out before the far clip.
- Verify at high camera zoom and map edge that no hard terrain cutoff is visible.

Acceptance:

- From a surface overview, the map edge dissolves into haze.
- The sky appears in every direction.
- No visible sky wall, cylinder, or boundary plane.

### Phase 2 - Time-of-Day Curves

Goal: drive sky, sun, moon, and fog from `WorldClock`.

- Interpolate sky top/horizon colors by hour.
- Move sun and moon directional lights through keyed angles.
- Switch sun/moon off when color reaches black.
- Tie fog color to sky horizon or active celestial color.
- Keep sunrise/sunset soft.

Acceptance:

- Sunrise and sunset change sky and fog together.
- Night fog becomes darker and closer.
- Daytime returns to an open, airy view.

### Phase 3 - Seasonal Day Length

Goal: Deepdraft's season system should exceed Stonehearth's static day length.

Use the existing design:

- summer solstice around day-of-year 28
- winter solstice around day-of-year 84
- daylight range roughly 8 to 16 in-game hours
- smooth cosine curve, no season-boundary snap

Acceptance:

- Summer days are visibly longer.
- Winter days are visibly shorter.
- Sunrise/sunset event times update smoothly across the year.

### Phase 4 - Weather Crossfade

Goal: weather changes sky and fog as one coherent system.

- Weather picks a sky/fog profile.
- Crossfade active sky/fog values over a short transition.
- Clear, overcast, foggy, and snow should each have distinct visibility and color.
- Weather `vision_multiplier` should eventually affect render radius and camera far clip, not just
  visual fog.

Acceptance:

- Foggy weather visibly shortens the view and softens the horizon.
- Snow/overcast darken the day without making the sky/fog mismatch.
- Manual weather cycling is available for testing.

### Phase 5 - Polish

Deferred polish:

- custom time-by-height sky gradient shader
- weather gradient textures
- starfield
- cloud shadow toggle
- volumetric height fog
- animated fog noise
- snow accumulation visuals

## Practical Godot Guidance

Recommended near-term Godot settings:

- Use `ProceduralSkyMaterial` first.
- Keep horizon and fog color nearly identical.
- Prefer exponential fog if depth fog does not fully obscure the far clip.
- Tune fog so clear daytime is open, not claustrophobic.
- Lower visibility for overcast/fog/snow through both fog and renderer distance when possible.

Stonehearth's sunny midday target is a good starting point:

- low or zero ground fog
- moderate haze
- long view distance
- sky and fog color match

Deepdraft should be slightly heavier and more ominous than Stonehearth:

- clear surface fog can be a little denser
- winter/night/fog should close in faster
- underground slice view should remain dark above the cut

## Hard Rules

1. Do not create a physical sky wall or boundary shell around the map.
2. Do not use fog or sky to fake block identity.
3. Do not brighten the underground slice void as part of the sky system.
4. Do not hand-edit `.tres` or `.import` resources.
5. Keep sky/weather values data-driven where practical.
6. Weather may change visibility and presentation; it must not rewrite terrain data.

## Answer to the Original Question

Does the Stonehearth sky go completely around the map?

**Visually, yes. Physically, not as a map-wrapping object.** Stonehearth renders a camera-centered
sky backdrop that is always behind the world, then blends distant terrain into matched sky-colored
fog. The player experiences it as an all-around sky because it follows the camera and cannot be
approached.

For Deepdraft, the correct target is a camera-infinite sky plus sky-matched fog, not a giant
skybox boundary around the playable slab.

---

*Prev: [07_performance_tuning.md](./07_performance_tuning.md)*
