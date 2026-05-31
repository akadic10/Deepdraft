# 12 — World Grid

## Map Dimensions


| Axis  | Size        | Notes                                             |
| :---- | :---------- | :------------------------------------------------ |
| **X** | 1024 blocks | East–West wilderness profile                      |
| **Z** | 1024 blocks | North–South wilderness profile                    |
| **Y** | 128 blocks  | Vertical (0..3 = bedrock floor, 127 = mountain peak) |

*   **Voxel Physical Dimension**: 1 engine block = $0.5\text{m} \times 0.5\text{m} \times 0.5\text{m}$.
*   **Total Playable Boundary**: $512\text{m} \times 512\text{m} \times 64\text{m}$ (Quarter Square Kilometer).
*   **Total Master Block Count**: $1024 \times 1024 \times 128 = 134,217,728$ blocks.

---

## Chunk System

The world is subdivided into uniform **16 × 16 × 16 block chunks** for memory management, mesh optimization (`ArrayMesh`), and rendering dirty-flags.
*   **Chunk Count Grid**: $64 \times 64 \times 8 = 32,768$ total chunks.
*   **Total Voxels Per Chunk**: $16 \times 16 \times 16 = 4,096$ voxels.
*   **Frustum & Wilderness Fog Occlusion**: Only chunks exposed to empty air or intersected by the active horizontal camera slice plane generate visual geometry. Chunks completely buried in solid rock or completely hidden inside the background distance fog contain data but skip rendering pipelines to protect framerates.

---

## Flat 1D Data Array Mapping

Each individual chunk stores its 4,096 blocks inside a single flat `PackedByteArray`. To avoid index leaks, the local mapping formula inside a chunk must strictly limit dimensions to the chunk size ($16$):

```gdscript
# Local Chunk Indexing (x, y, z are local values from 0 to 15)
var local_index = x + (z * 16) + (y * 16 * 16)
```

To translate global coordinate positions across the master world matrix into specific chunk data arrays, use this dual-step formula:

```gdscript
# 1. Find target chunk coordinates
var chunk_coord = Vector3i(global_pos.x / 16, global_pos.y / 16, global_pos.z / 16)

# 2. Find local voxel coordinates inside that chunk
var local_x = global_pos.x % 16
var local_y = global_pos.y % 16
var local_z = global_pos.z % 16
```

> **Agent Note**: Never store block configurations or entity coordinates in a nested 3D array (`[[[]]]`). Always utilize flat 1D data arrays coupled with integer indexing for instant $O(1)$ lookups.

---

## Block Registry — Namespaced JSON String System

Blocks are declared inside a structured data file using a nested **Namespaced String Key** architecture (`"mod/game:category:subcategory:item"`). At runtime, these strings are parsed once and mapped to dynamic integers inside a cache.

### Why Namespaced Strings?
*   **No Data Holes**: Reordering, adding, or deleting blocks from the JSON file does not shift hardcoded indices. It prevents corrupting or destroying old save files.
*   **Session-Local IDs**: Integer IDs (`0`, `1`, `2`) are strictly temporary and runtime-only.

### Registry JSON Format (`res://data/terrain/terrain_blocks.json`)
```json
{
  "block_types": {
    "dwarf:air": {
      "kind": "air",
      "hex_color": "#00000000"
    },
    "dwarf:bedrock": {
      "kind": "bedrock",
      "hex_color": "#111116"
    },
    "dwarf:stone_layer_1": {
      "kind": "rock",
      "hex_color": "#4b5358"
    },
    "dwarf:ore_gold": {
      "kind": "gold",
      "hex_color": "#ffd700",
      "drops_item_entity": "res://scenes/entities/items/gold_nugget.tscn"
    }
  },
  "selectable_kinds": {
    "gold": "dwarf:ui:blocks:gold_vein_panel"
  }
}
```

### Save File Serialization
*   When saving a game state, the grid matrix translates runtime integers back into their permanent namespaced text strings. Save configurations remain forward and backward compatible.

---

## Terrain Style vs Floating Items (The Stonehearth Standard)

To achieve maximum performance over a 134-million-voxel grid, the game cleanly decouples world environment geometry from interactive item resources:

### 1. Solid Flat Terrain Walls
*   All untouched terrain blocks inside a mountain wall are rendered strictly as flat-shaded, single-color cubes. 
*   The chunk rendering script reads the `hex_color` code from the JSON registry and applies it instantly to the cube vertices via a fast vertex-color color map. No complex textures or high-density voxel files are processed inside solid terrain walls.

### 2. Micro-Voxel Floating Items
*   The moment a dwarf mines an ore or stone block, that grid position is overwritten to `dwarf:air`.
*   The engine reads the `"drops_item_entity"` flag and instantly spawns a floating 3D item entity scene (`.tscn`) at those coordinates. 
*   These standalone item drops host the high-density micro-voxel `.glb` model files imported from MagicaVoxel, allowing loose cargo on the floor to look beautifully detailed without lagging the engine environment.

### 3. Entity Space Clearance Rules
*   **Clearance Bounds**: A standard dwarf agent stands **3.3 blocks tall visual profile**, but occupies a strict $1 \times 1 \times 3$ grid space on the pathfinding matrix. Tunnels require at least 3 empty air layers above a floor tile for passage.

---

## Placed World Entities

Not everything in the world is a terrain block. **Placed entities** are objects that occupy physical grid space but live entirely outside the terrain grid. Examples:

| Category | Examples |
|---|---|
| World-generated flora | Trees, giant mushrooms, cave plants, crystal formations, boulders |
| Player-constructed | Workshops, beehives, furniture, stockpile zones |
| Dropped items | Harvested resources waiting for pickup |

**The terrain grid never knows about placed entities.** There are no sentinel block IDs (like `"entity_reserved"`) written into the grid to mark where a tree or workshop stands. The grid stores only block IDs. Pathfinding and interaction systems query the `PlacedEntityRegistry` separately when they need to know about entity presence.

> **Verified against Stonehearth source:** Trees inherit `placed_object.json` which declares `"navgrid": { "has_physics": true }`. When a tree dies, `kill_entity()` is called — nothing in the terrain grid is touched. The mining selection filter queries `region_collision_shape` on entities directly, not the terrain grid.

### Entity Data Definition

Each placed entity type is defined in `data/entities/`. Definitions must include a `footprint` field — a list of grid offsets the entity occupies relative to its origin. Other systems use this for collision and interaction queries without needing a full physics raycast.

```json
{
  "id": "deepdraft:tree:oak",
  "stages": ["small", "medium", "large"],
  "health": 6,
  "footprint": [[0,0,0], [0,1,0], [0,2,0], [0,3,0]],
  "loot_table": "deepdraft:loot:oak_log",
  "mesh": {
    "small":  "res://assets/entities/trees/oak_small.glb",
    "medium": "res://assets/entities/trees/oak_medium.glb",
    "large":  "res://assets/entities/trees/oak_large.glb"
  }
}
```

### Mesh Scale

Entity meshes are authored at **1 unit = 1 block** (same as the terrain block size). A tree 4 blocks tall should be 4 units tall in the `.glb`. This means entity voxels are visually indistinguishable in size from terrain blocks — the difference is purely in how they are stored and rendered.

### Lifecycle

- **Spawn**: `PlacedEntityRegistry.spawn(type_id, grid_pos)` — instantiates a `MeshInstance3D` node, positions it at grid-aligned world coordinates, registers its footprint.
- **Damage**: `entity.take_damage(amount)` — reduces the entity's health value.
- **Death**: When health reaches 0: (1) loot items spawn at the entity's grid position, (2) the node is freed, (3) PlacedEntityRegistry removes the entry. **Nothing in the terrain grid is modified.**

### Save Format

The save file has two independent top-level sections:

```json
{
  "chunks": {
    "0,0,0": { "blocks": [...] }
  },
  "placed_entities": [
    { "type": "deepdraft:tree:oak",       "pos": [10, 5, 3], "stage": "medium", "health": 4 },
    { "type": "deepdraft:workshop:brewery","pos": [20, 5, 8], "state": {} }
  ]
}
```

`chunks` contains only block IDs. `placed_entities` contains only entity instances. They load independently. Entity positions are stored as integer grid coordinates, not world-space floats.

### Walkability Interaction

The custom A* nav grid (see `32_navigation_3d.md`) checks walkability against both the terrain grid and the `PlacedEntityRegistry`. A cell is treated as impassable if it is either a solid block **or** occupied by a placed entity's footprint. The terrain grid itself is never written to mark entity presence.

---

## Surface Elevation Ranges

The world heightmap is not uniform. Terrain domain determines the elevation range for each column:

| Domain | Surface Y range | Notes |
|---|---|---|
| Mountain | 44-115 | Ridge shelves and primary dwarf dig-in faces |
| Valley / Foothills | 20-43 | Flat farmland, trade road corridor, and stepped foothill shelves |
| Lowland | 12-19 | Open wilderness floor; lake and river mouth |
| River channel | <= 61 | Carved 1-3 blocks below surrounding surface |
| Lake basin floor | >= 11 | Bowl-shaped depression; water fills to Y 18 |

Domain boundaries are resolved on the 32x32 macro grid before heights are assigned. Lowland macro cells require a true lowland majority and isolated non-anchor lowland cells are promoted to valley, which prevents single lowland plates from appearing inside foothills. The fixed lowland lake waterline is `Y = 18`. Underground systems (ore depth, cave generation, soil bands) are unaffected by surface domain; they read only absolute Y position.

After lake carving and shelf cleanup, a final edge-detail pass adds shallow blocky ledges only along foothill and mountain shelf edges. It does not apply to lowland, settlement/plain, lake, tarn, or water-bank columns, and it keeps pushed heights inside the source shelf band so visible materials still match the terrain strata rules.

---

## Inviolate Bedrock Protocol

> **HARD ENGINE RULE — never bypass in any script or task processing thread.**

*   The baseline matrix layers **`Y = 0..3`** are occupied entirely by un-minable bedrock (`"base:terrain:bedrock"`).
*   Any player click or raycast selector seeking to remove a block must execute a safety validator (`target_global_y > 3`) before resolving.
*   The `TaskServer` manager must automatically throw out and reject any queued mining assignments pointing at `Y = 0..3`.
*   The procedural `WorldGen` algorithm must write bedrock down across the entire $1024 \times 1024$ floor slab at `Y = 0..3` unconditionally.

---

*Prev: [11_overview.md](./11_overview.md) | Next: [13_architecture.md](./13_architecture.md)*
