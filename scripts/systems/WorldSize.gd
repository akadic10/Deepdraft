extends RefCounted

## The world's dimensions, in blocks. WorldData re-exports these (use
## WorldData.WORLD_SIZE_X and friends); preload this file only from code that
## must stay free of autoloads, such as world-generation layouts and the save
## validator, which tests and worker threads load before any autoload exists.
const WORLD_SIZE_X: int = 1024
const WORLD_SIZE_Y: int = 128
const WORLD_SIZE_Z: int = 1024
## Highest block row; also the slice "off" value (SliceController.MAX_SLICE_Y).
const MAX_Y: int = WORLD_SIZE_Y - 1
