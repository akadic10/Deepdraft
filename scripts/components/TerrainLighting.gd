extends RefCounted

## Terrain blocks both sunlight and local lights. Omitting it from the sun's
## casters lets plants and props project shadows through solid cliffs onto lower
## ground. Keep the reserved layer and normal camera/light illumination masks.
const TERRAIN_LAYER := 1 << 19

static func configure_mesh(mesh: MeshInstance3D) -> void:
	mesh.layers = TERRAIN_LAYER
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

static func configure_sun(sun: DirectionalLight3D) -> void:
	sun.shadow_caster_mask |= TERRAIN_LAYER
