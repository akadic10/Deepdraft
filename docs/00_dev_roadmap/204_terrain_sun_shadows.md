# Terrain sun shadows

2026-10-17. The player reported a strawberry plant on a plateau casting an
isolated shadow onto the ground below the cliff. Terrain was enabled for local
light shadows but explicitly excluded from the sun's shadow-caster mask. The
sun therefore treated the plant as a caster without the solid cliff occluding it.

`TerrainLighting.configure_sun` now includes the existing terrain layer 20.
All terrain paths already use that layer and already cast shadows. Plants keep
normal shadow casting; cliffs and walls now cast their own sunlight shadows.
Other mask bits, light intensity, materials and geometry are unchanged. Slice
visibility controls rendered casters as before; the world-data roof/door skylight
field still controls underground exposure independently of the camera slice.
No save schema, new autoload, art change or Windows export is involved.

The new native `TerrainSunShadowTest` reproduces the bug using an actual imported
strawberry, an upper plateau and a lower terrace. With terrain excluded, hiding
the plant changes 100/44 sampled lower-ground points at two sun pitches. With
the fix, both comparisons have zero changed points and zero luminance difference:
the cliff occludes the plant. The test also checks the cliff's shadow, unchanged
exposed plateau lighting, slice removal and restoration, retained plant shadows,
and idempotent mask configuration. Before/after images were inspected.

Four native source fixtures pass with zero script/runtime errors:
TerrainSunShadowTest, RoomLightingTest, SkySceneLifecycleTest and
WorldTerrainStartupTest. These cover local torchlight and dark rooms, sky rebinding,
all 1,024 terrain tiles, local edits, slicing, save/reload and global invalidation.

A copied five-dwarf save was also inspected at 2560×1440, paused at 18:39, with
two alternating old/fixed rendering samples. Mean GPU time was 0.810/0.820 ms
before and 0.847/0.823 ms after; frame means were 1.319/1.369 ms and 1.400/1.391 ms.
This short static view is a check for an obvious rendering regression, not a
whole-colony performance claim. The player's original save was only read for
the isolated copy.

Evidence: [results, screenshots and compressed logs](concepts/plant_shadow_20261017/summary.json).
Restart Play to apply the corrected sun mask.
