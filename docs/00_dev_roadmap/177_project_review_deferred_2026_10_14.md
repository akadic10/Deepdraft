# 177 — Deferred project review findings · 2026-10-14

**Status: PARKED — deferred by the user on 2026-10-14.** Keep these findings
for a later session. No fixes or further investigation are scheduled or
authorized by this note. Resume only when the user chooses to revisit them.

The project review covered source, scenes, data, asset references, tooling and
documentation. The three issues below were reproduced in isolated headless
fixtures. No production code was changed, and the user's existing
`project.godot` edit was left intact. These findings do not reopen historical
issues 001/002 in [00 — Open issues](00_open_issues.md).

## Deferred issue 1 — Unknown furniture IDs bypass save recovery

**Priority:** P2. **Status:** Reproduced; unfixed; deferred.

- **Trigger:** A structurally valid primary save contains an unknown furniture
  key, for example after an ID becomes obsolete or a save is edited/corrupted.
- **Observed:** Loading reports success, skips the furniture and its contents,
  and does not fall back to an available valid backup.
- **Cause:** The `key` rule in
  [SaveSnapshotValidator.gd](../../scripts/components/SaveSnapshotValidator.gd)
  (line 333 at review time) checks only for a nonempty string.
  [FurniturePlacementController.gd](../../scripts/systems/FurniturePlacementController.gd)
  (line 1400) silently skips an installed entry when its key is absent from
  `_defs`. The failure is not propagated to the save manager.
- **Reproduction:** Create a barrel holding two rough stones; save twice so
  the backup is valid; change only the primary's barrel key to
  `base:furniture:unknown_barrel`; load through the normal save manager.
- **Recorded result:** `reported_success=true`, `used_backup=false`,
  `installed_after=0`, `stone_total_after=0`.
- **Later fix direction:** Validate referenced content IDs before replacing
  the live scene, or propagate restoration failure into recovery. Add a
  regression covering an unknown ID with a valid backup and conservation of
  the container's contents.

This reproducer does not establish a failure for an unchanged, valid save.

## Deferred issue 2 — Floor furniture removal ignores reachable alternatives

**Priority:** P2. **Status:** Reproduced; unfixed; deferred.

- **Trigger:** The geometrically nearest standing position beside installed
  floor furniture is enclosed, but another side remains reachable.
- **Observed:** The uninstall order backs off with `No route for eligible
  workers`, despite a valid path to another standing position. Moves depend
  on this same uninstall stage.
- **Cause:**
  [InstalledFurnitureComponent.gd](../../scripts/components/InstalledFurnitureComponent.gd)
  (line 92) chooses a single nearest walkable stand without checking its route.
  [TaskManager.gd](../../scripts/systems/TaskManager.gd) (lines 608–612) probes
  that target; the multiple-goal special case applies only to wall furniture.
- **Reproduction:** On a flat floor at Y=20, place a barrel at `(45,20,40)`
  and a worker at world position `(40.5,21,40.5)`. Add walls at X/Z
  `(43,40)`, `(44,39)` and `(44,41)` from Y=21 through Y=24. The barrel
  completes the enclosure around stand `(44,20,40)`. Mark it for uninstall.
- **Recorded result:** The chosen stand has no path; stand `(45,20,39)` has
  a seven-cell path; `assigned_worker=-1`, `blocked_count=1`.
- **Later fix direction:** Search all eligible stands and preserve the selected
  reachable stand through execution. Cover both uninstall and relocation.

## Deferred issue 3 — Ordinary furniture can install after losing its floor

**Priority:** P2. **Status:** Reproduced; unfixed; deferred.

- **Trigger:** Remove the floor beneath an ordinary furniture placement while
  the worker is setting down its packed item.
- **Observed:** Placement remains valid, consumes the packed item, and leaves
  the installed furniture suspended over the missing floor.
- **Cause:** `_can_build_ghost()` in
  [FurniturePlacementController.gd](../../scripts/systems/FurniturePlacementController.gd)
  (lines 1145–1154) rechecks walkability for moves and chairs, but ordinary
  floor pieces can return true without that check.
- **Reproduction:** Start a normal barrel installation at `(52,20,46)`.
  Once the worker reaches `FETCH_DEPOSIT`, remove block `(52,20,46)`, allow
  three frames, then finish the set-down animation.
- **Recorded result:** `build_allowed_without_floor=true`, `floor_block=0`,
  `installed=1`, with no remaining ghost, carried item or loose item.
- **Later fix direction:** Revalidate support, clearance and occupancy for
  every floor footprint before consuming the item. Failed placement should
  preserve the exact packed item.

## Deferred test-fixture maintenance

These are validation issues, not additional confirmed gameplay defects.

- **ColonyInventoryTest:** Its inventory assertions passed, but the fixture
  emitted repeated out-of-bounds errors in `WorldGenerator._generate_block_id`
  via camera/audio terrain queries. The fixture marks maps ready and fills
  `heightmap` without initializing the corresponding `waterline_map`.
  Complete the fixture's world setup before treating the test as clean.
- **OrdersShelfTest:** Two overlap assertions failed at 960×540 shortly after
  the inspector resized. A temporary copy allowing 250 ms before those
  assertions passed. Review synchronization with layout completion; a
  persistent production overlap was not established.

## Review validation and evidence

- Standard job suite: **32/32 passed**.
- Extended suite: **43/46 initially passed**. `WaterStabilityTest` exceeded
  the runner's 180-second limit, then passed all four seeds with a longer
  allowance, bringing the unmodified checks to **44/46 passed**. The two
  remaining fixture issues are recorded above.
- Godot editor import passed. JSON parsing and syntax checks for 106 Python
  files and 19 PowerShell files passed.
- Fourteen missing crop-model references match documented deferred crop art;
  they were not classified as new defects.
- Native rendering and audio were not visually or audibly assessed.

Local scratch evidence is under
[`tmp/project_review_20261014/`](../../tmp/project_review_20261014/):
`SaveSemanticProbe.gd` / `semantic.out`, `UninstallAccessProbe.gd` /
`uninstall.out`, `FurnitureSupportProbe.gd` / `support.out`,
`job_gate/results.json`, `extended_gate/results.json`, `water_retry.out`,
and `orders_settled.out`. This directory is ignored scratch output and may
be removed later; the reproduction details above preserve the findings.
