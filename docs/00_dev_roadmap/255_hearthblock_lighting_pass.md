# 255 — Hearthblock lighting pass

Implemented 2026-10-20 as step 1 of the Hearthblock art proposal
(artifact "Deepdraft Hearthblock Style"). Presentation only: no models,
gameplay, save data or furniture definitions change.

## Why

The underground shader gives sealed surfaces no ambient light at all: only
torches and an emission "readability floor" of 0.8% of albedo. The world uses
linear tone mapping, so torch pools clip to flat orange and the gaps between
torches fall to near black. Slice caps are lit as open sky and read as bright
slate-blue bands, and confirmed stockpiles are the most saturated blue on screen.
In the proposal's side-by-side renders, today's models under better light
already gained most of the intended warmth, so light comes before model work.

## What changes (switch on)

| Area | Before | Hearthblock lighting |
|---|---|---|
| Tone mapping | Linear | ACES, exposure 1.1, white 6.0 |
| Glow | Off | On: intensity 0.5, HDR threshold 1.0, screen blend, mid levels only |
| Sealed-air floor | 0.8% of albedo, neutral | 3.5% of albedo, cool slate tint |
| Actor/prop faces | Black when turned away from torches | A camera-facing fill (6% of albedo) on closed actor/prop materials, underground only |
| Fire lights | `#FFC078` | Torch `#FFB266`, campfire `#FFA85A`, hearth `#FFAA5E`; energy, range, attenuation and shadows unchanged |
| Flames | Albedo 1.0 | Albedo gain 1.4, so only fire passes the glow threshold |
| Slice caps | Lit as sky, full rock colour | Rock colour × (0.72, 0.63, 0.55): darker, warmer cut rock |
| Stockpile zones | Blue fill and edge | Dark burlap fill at 30% opacity (it slightly darkens the floor) with a tan rope edge |

All values live in `data/sky/sky_settings.json` → `hearthblock_lighting`.
Designation previews keep their own valid/invalid colours. The X-ray inspection
shell keeps its neutral look.

## Switch

**Development → Hearthblock lighting** flips the look at runtime for A/B review;
a toast confirms on/off. `enabled` in the data is the startup default (on). The
choice lasts until the game closes.

The look applies only when the current scene is `res://scenes/main/debug_world.tscn`.
Galleries, study viewers, thumbnails and isolated test scenes keep their authored
look. Switching off restores the scene Environment's authored tone mapping and
glow values (kept as metadata on the resource), every cached material's previous
parameters, each fire light's definition colour and the flame albedo.

## Ownership

- `SkyController` owns the switch (`is_hearthblock_enabled`, `hearthblock_active`,
  `set_hearthblock_lighting`, signal `hearthblock_lighting_changed`) and the
  Environment's tone mapping and glow. It emits after every scene bind.
- `UndergroundLighting` applies floor, tint, view fill and cap tint to every
  material it creates and re-applies them on change.
- `FurnitureLighting` records each light's definition colour and flame material,
  warms colours by furniture key and sets the flame gain.
- `StockpileDesignationController` redraws confirmed zone overlays on change.
- Shader: `readability_tint`, `view_fill` (underground_lighting_common) and
  `slice_cap_tint` (terrain_appearance). Their defaults equal the previous shader.

Torches already avoid shadowing their own light: `FurnitureLighting` disables
body shadow casting unless a definition sets `body_shadows`. The proposal's
"torch self-shadow" item was a mistake in its browser mock-up and needed no change.

## Verification

`tools/hearthblock/HearthblockLightingReview.gd`, run by
`tools/hearthblock/RunLightingReview.ps1`, loads a recovery copy of the player's
quick save (SHA-256 `454aa0b6…62d0c0`, identical to the original) into the real
world scene in a throwaway profile, in a 3840×1080 window. The original save
and profile were hashed before and after; both are unchanged.

- **Contract:** with the switch off the Environment is linear with glow off, all
  1,156 cached materials carry the previous floor (0.008) and no view fill, all 55
  fire lights use their definition colours and every flame albedo is white. On:
  ACES, glow, the new floor/tint/cap values, view fill on closed materials only,
  all 55 lights warmed and burlap zone colours. Switching back off reproduces the
  first off state exactly (Environment, every material parameter, light colours,
  flame albedo and all three stockpile overlays). `HEARTHBLOCK_LIGHTING_PASS`,
  no errors.
- **Captures:** colony (the save's zoom 83.5, pitch −45.8°), gameplay (zoom 40) and
  close (zoom 15) views of the main hall around the dining table, plus the
  unsliced surface at 14:44, each off and on, in `tmp/hearthblock_lighting_20261020/final/`.
- **Cost** (RX 9070 XT, D3D12 Forward+, 3840×1080, two interleaved 180-frame samples
  each): GPU median 4.97–5.01 ms off, 5.41–5.42 ms on (+0.43 ms, mostly glow);
  p95 5.12–5.15 → 5.55–5.57 ms. Render CPU 2.96–3.02 ms off, 3.01–3.47 ms on (noisy).
  One fast GPU does not establish low-end cost.
- **Tuning:** the first pass used a linen stockpile fill and flame gain 1.6. The fill
  was brighter than the dark floor and read as a pale sheet; it is now a darker
  burlap at 30% that slightly darkens the floor, authored in sRGB and converted for
  the linear vertex overlay. Flame gain fell to 1.4 and glow intensity to 0.5 so
  flame cores no longer burn white. Caps were lightened slightly toward warm rock.

- **Regressions (headless):** `FireFacetedArtTest`, `FurnitureFacetedArtTest`,
  `RemainingMenusTest` and `DioramaSkyTest` pass. `TerrainAppearanceTest` fails
  its cavity-shell mineral-tag check identically on the committed code without
  this pass, so that failure predates it. The native lighting fixtures
  (`BedroomLightingTest`, `RoomLightingTest`, `XrayViewTest`,
  `AtmosphereSharingTest`) were not rerun; the owner accepted the result in game.

## Notes and limits

- The view fill and the tinted floor are deliberately subtle; they lift faces and
  shadows rather than flattening the torch pools. Tune them in the data block.
- Daytime surface views change little: slightly more saturation and contrast.
- The X-ray inspection view, portraits, galleries and thumbnails keep their own
  environments and are unchanged.
- Not part of this step: baked voxel ambient occlusion and contact shadows (they
  need regenerated meshes), per-room bounce light, and any model changes.
- `tools/voxel_assets/CopiedSaveReview.gd` predates startup resume (240). A copy
  placed in its storage is resumed automatically, so its explicit load can be
  rejected as busy; the new review sets `_startup_checked` first. Not changed here.
