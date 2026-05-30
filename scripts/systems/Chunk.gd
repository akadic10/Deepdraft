class_name Chunk

## Flat 1D block storage for a 16 × 16 × 16 voxel chunk.
##
## Index formula (from 12_world_grid.md):
##   local_index = x + (z * 16) + (y * 256)
##
## Values are runtime integer block IDs (0–255). ID 0 is always
## base:terrain:void — it is the first non-comment entry in
## terrain_blocks.json, and BlockRegistry assigns IDs in file order.
##
## IMPORTANT: These integers must NEVER be written to save files.
## Save files always convert back to namespaced StringName keys via
## BlockRegistry.get_key() before serialising.
##
## PackedByteArray caps IDs at 255. If the block registry ever exceeds
## 255 entries, upgrade to PackedInt32Array and adjust set/get logic.

var blocks:   PackedByteArray
var is_dirty: bool = false

## True if this chunk contains at least one void (air) block. A freshly
## created chunk is all void, so this starts true. WorldGenerator sets it to
## false for fully-solid chunks; WorldRenderer uses it (plus neighbours) to
## skip meshing fully-buried interior chunks that can produce no visible faces.
var has_void: bool = true


func _init() -> void:
	blocks.resize(4096)
	blocks.fill(0)   # 0 = base:terrain:void


## Converts local voxel coordinates (each 0–15) to a flat array index.
static func local_index(lx: int, ly: int, lz: int) -> int:
	return lx + (lz * 16) + (ly * 256)
