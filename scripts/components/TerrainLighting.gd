extends RefCounted

## Terrain receives the same lighting, but casts shadows only for local lights.
## Reserve render layer 20 so the sun can omit terrain casters without affecting
## its illumination. Camera/light cull masks retain their normal all-layer defaults.
const TERRAIN_LAYER := 1 << 19

static func configure_mesh(mesh: MeshInstance3D) -> void:
	mesh.layers = TERRAIN_LAYER
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

static func configure_sun(sun: DirectionalLight3D) -> void:
	sun.shadow_caster_mask &= ~TERRAIN_LAYER
