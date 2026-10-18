# Large-save terrain restore crash

2026-10-17. New games loaded successfully, while the player's saved settlement
closed the game without an in-game error.

## Diagnosis

The existing player log and Windows Application Error recorded a native Godot
4.7.2 access violation (`0xc0000005`). The script stack ended at
`WorldData.mark_chunk_dirty` → `set_block` → `WaterManager.restore_state` →
`SaveManager._restore_pending_snapshot`.

Two isolated source runs reproduced the crash with a copy of the quicksave,
both exiting `-1073741819` after about 65 seconds. That save contains 56,777 mined
cells and 16,615 constructed cells. The autosave contains the same mined history
and 16,565 constructed cells. Smaller generated-world round trips had passed.

Terrain restoration emitted repeated chunk signals for every voxel, reaching
several deferred listeners before the main thread could drain them. The crash
occurred in signal emission after the large mining restore, during solid terrain
restoration. Coalescing these notifications fixes the reproduced failure. The
exact engine-internal reason for the access violation was not determined.

## Change

- `WorldData.begin_edit_batch` / `end_edit_batch` coalesce dirty notifications
  by chunk across a synchronous main-thread edit burst, including nested callers.
- Block contents, saved deltas and chunk dirty flags update immediately. Exact
  `block_changed` events remain intact for water and discovered interior tracking.
- `SaveManager` wraps the scene-owner restore loop, flushing after all owners
  finish in their established priority order. No frame is yielded in the batch.
- Normal gameplay edits and generator submission retain their existing behavior.
  World reset clears any pending batch state.

No save schema, resource identity, construction history or discovery data is
removed or migrated. This is a stability fix: large restores still take time,
covered by the existing loading screen until the world is ready.

## Verification

Native Godot 4.7.2 / Forward+ / D3D12 source checks:

- Copied quicksave and autosave load through the normal SaveManager reload path
  and finish the loading screen. Both runs verify every mined-cell record and
  every constructed block against the source snapshot, then enable Full X-ray,
  wait for its build, capture the view and disable it again.
- `TerrainEditBatchTest`: 65,536 actual edits preserve all exact events while
  issuing only 16 chunk notifications. Checks nested boundaries, immediate world
  truth/dirty flags, deferred consumers, ordinary edits and reset cleanup.
- `SaveManagerRoundTripTest`: save/load ownership, scene reload, validation,
  backup recovery and asynchronous save worker behavior pass.
- `XrayViewTest`: discovered interiors, construction updates, lower-level
  references, real tool input, selection and display layouts pass.

Tests use isolated application-data directories and copies of the player's saves.
SHA-256 checks verify the four original primary/backup save files are unchanged.
Logs, result records, diagnostic source and reviewed captures are recorded in
[the evidence folder](concepts/save_crash_20261017/summary.json); actual player
save JSON remains in ignored local scratch space.

Restart Play before loading the save. No Windows playtest was created or updated.
