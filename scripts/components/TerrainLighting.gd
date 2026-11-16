extends RefCounted

## Terrain blocks both sunlight and local lights. Omitting it from the sun's
## casters lets plants and props project shadows through solid cliffs onto lower
## ground. Keep the reserved layer and normal camera/light illumination masks.
const TERRAIN_LAYER := 1 << 19
## The shadow-only rock above the slice (SliceLightOccluders, doc 287). Local lights cast
## from it; the sun must not, or the sliced-off mountain would shade every cut plate.
const SLICE_OCCLUDER_LAYER := 1 << 17

## Built log walls are not terrain meshes; their shadow meshes carry this layer as well as their
## own, so a light that only the ground and what is built shadow (the Miner's candle, doc 304) is
## stopped by a log wall too.
const BUILT_LAYER := 1 << 16

static func configure_mesh(mesh: MeshInstance3D) -> void:
	mesh.layers = TERRAIN_LAYER
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

static func configure_sun(sun: DirectionalLight3D) -> void:
	sun.shadow_caster_mask |= TERRAIN_LAYER
	sun.shadow_caster_mask &= ~SLICE_OCCLUDER_LAYER

## A light shadowed by rock and built walls only: dwarves, goods and furniture throw no shadow in
## it, so the dwarf that carries it never darkens its own ground.
static func configure_carried_light(light: Light3D) -> void:
	light.shadow_enabled = true
	light.shadow_caster_mask = TERRAIN_LAYER | SLICE_OCCLUDER_LAYER | BUILT_LAYER
