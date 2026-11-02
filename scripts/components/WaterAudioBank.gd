extends RefCounted

## Recorded mono water loops, shared across scene-owned spatial voices.
## Paths come from WorldGenerator's water profile; no simulation state is read.
static var _cache: Dictionary = {}

static func stream(path: String) -> AudioStreamWAV:
	if _cache.has(path): return _cache[path]
	var sound := (load(path) as AudioStreamWAV).duplicate() as AudioStreamWAV
	sound.loop_mode = AudioStreamWAV.LOOP_FORWARD
	sound.loop_begin = 0
	sound.loop_end = roundi(sound.get_length()*sound.mix_rate)
	_cache[path] = sound
	return sound
