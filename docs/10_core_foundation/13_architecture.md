# 13 — Architecture

## Global Autoload Singletons

The following Autoloads are registered in **Project Settings → Autoload** and are available globally via their node names. They must be loaded in the exact order listed below to prevent dependency resolution issues.

> **Registration:** The agent may register these autoloads directly by editing the `[autoload]` section of `project.godot` (see File Ownership Rules in `AGENT.md`). Preserve the load order exactly as listed.

### `BlockRegistry`
Parses and holds the data-driven block definitions. Provides ultra-fast string ↔ ID translation.
```gdscript
func get_id(namespace_key: String) -> int # "dwarf:stone_granite" → runtime int
func get_key(id: int) -> String           # runtime int → "dwarf:stone_granite"
func get_def(namespace_key: String) -> Dictionary # full block definition dict
func is_solid(id: int) -> bool
func is_transparent(id: int) -> bool
```

### `WorldData`
Owns the massive 1D master chunk data matrix and exposes thread-safe block read/write APIs.
```gdscript
func get_block(world_x: int, world_y: int, world_z: int) -> int # returns runtime block ID
func set_block(world_x: int, world_y: int, world_z: int, id: int) -> void
func get_chunk(cx: int, cy: int, cz: int) -> Chunk # lazy-loads if needed
func mark_chunk_dirty(cx: int, cy: int, cz: int) -> void
```

### `AudioManager`
Central procedural audio manager. Handles spatial cave reverb scaling, ambient loops, and real-time code-generated synthesis.
```gdscript
func play_sfx(key: String, position: Vector3) -> void
func set_ambient(track_key: String, fade_time: float) -> void
```

---

## Boot Sequence — JSON Parsing

On application startup, before any scene or gameplay layer is loaded, the following sequence runs synchronously inside the `_ready()` function of the first Autoload (`BlockRegistry`):

