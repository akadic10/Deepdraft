# 175 — Dwarf limb lighting

The player reported mismatched left/right hands and shoes, then supplied a
screenshot of Ulvrek with a blue-grey right hand and nearly black right boot.
Both sides already received the same skin tint or baked leather palette.

A native comparison reproduced the difference with symmetric illumination,
both with `StandardMaterial3D` and the production underground-lighting shader.
The right parts used a negative X scale to mirror the shared left-part models;
those reflected, double-sided surfaces were receiving reversed lighting.
The mismatch was a rendering defect, not saved appearance variation.

`DwarfAssets` now caches one reflected triangle mesh per source limb. It reflects
positions/normals/tangents and reverses winding while retaining vertex colors.
`DwarfAgent` applies a counter-reflection at the inner mesh node. The existing
right-part animation frame stays mirrored, with unchanged palm coordinates,
boot pivots, work-tool attachment, poses and silhouettes. The final rendered
mesh transform has a positive determinant. Imported assets remain immutable;
all dwarves share the two derived production meshes rather than cloning them
for each actor. No source GLBs or import files changed.

## Verification

- `DwarfLimbLightingTest` is a native render regression. Before the fix,
  corresponding hand samples differed by up to 0.447 and boots by 0.259 in
  normalized output color channels. The initial matching-light comparison
  reaches zero difference after the correction. The expanded test passes
  32 paired samples across all four skin tones, daylight/torchlight, and both
  standard and world materials.
- [Before](concepts/175_dwarf_limb_lighting/before.png),
  [corrected daylight](concepts/175_dwarf_limb_lighting/after.png), and
  [corrected torchlight](concepts/175_dwarf_limb_lighting/after_torch.png)
  show ordinary materials on the left actor and world materials on the right.
  [Before samples](concepts/175_dwarf_limb_lighting/before.json) and
  [expanded final samples](concepts/175_dwarf_limb_lighting/after.json) retain
  the measured results. Symmetric test illumination is intentional; real
  directional lights and nearby torches can still shade opposite sides differently.
- `DwarfFacetedArtTest`: 6,828 checks, all 41 parts, 800 appearances and 22 pose
  cases. Added checks verify shared cached geometry, untouched left meshes,
  matching vertex colors, positive rendered transforms and exactly mirrored
  world positions. Existing grip/ground-clearance checks pass.
- `ProportionIntegrationTest`: 205 checks, including approved widths/heights.
- `MiningAnimationTest`, `TreeFellingTest`, `HaulingAnimationTest` and
  `DwarfRestTest` pass. Signed rig scales, contact/grips, gait, carrying, rest,
  interruption and save behavior remain intact.
- `tools/windows_playtest/ReviewDwarfLimbs.gd` loads a copied quicksave through
  the real dock and finds Ulvrek by name. The saved appearance and world position
  are retained; only the review camera and his facing change for the close-up.
  All four limb meshes have positive rendered transforms and paired material
  tints match. [Ulvrek after loading](concepts/175_dwarf_limb_lighting/ulvrek.png)
  and [runtime results](concepts/175_dwarf_limb_lighting/copied_save_review.json)
  record the check.

All runs use isolated APPDATA. Player saves are read only. Restart to rebuild
existing actors with the corrected meshes; no migration or new colony is needed.

## Windows playtest

Release: `build/windows/releases/20261013-212541-918-28808c06/Deepdraft/`.
Share `build/windows/Deepdraft-Windows-Playtest.zip`, SHA256
`93B8DA4F6FB792A11A36F3761227515E143D9CB8F12E4DDB63D3835DD15650E8`.
Previous release directories are retained so running games keep their own PCK.
The exported game completed native startup/world generation and exited with
code 0 and no errors in the captured output. The documentation closeout and
remaining player-review items are recorded in
[176 — Session handoff](176_session_handoff_2026_10_13.md).
