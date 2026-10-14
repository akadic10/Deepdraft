// One continuous, full-sphere gradient for both the backdrop and roof-aware fog.
// The lower hemisphere is atmosphere too: the colony is a floating diorama.
vec3 diorama_atmosphere(vec3 direction, vec3 top, vec3 horizon, vec3 bottom, vec2 curves) {
    float elevation = clamp(direction.y, -1.0, 1.0);
    if (elevation >= 0.0) {
        return mix(top, horizon, pow(1.0 - elevation, curves.x));
    }
    return mix(bottom, horizon, pow(1.0 + elevation, curves.y));
}
