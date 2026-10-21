# Deepdraft — Hearthfolk art direction proposal

**Superseded selection, 2026-10-18:** The player subsequently chose the original,
more detailed timber illustration as the ongoing target. The canonical image
and current direction are in [64 — Hand-hewn art direction](../../../60_asset_creation/64_hand_hewn_art_direction.md).
The simplified `02_hand_hewn_timber.png` below is retained as exploration history;
it is not the selected visual authority. The native implementation was accepted
provisionally, with its artistic shortfall explicitly acknowledged.

2026-10-18. Visual exploration requested by the player, using the supplied
Stonehearth screenshots as discussion references. Generated with the built-in
image-generation tool. These PNGs are concept artwork, not exported voxel
models or measured grid diagrams. Production assets and saves are unchanged.

## Recommendation

Use **B — Hearthfolk** as the character proportion target, combined with the
simpler surfaces in the refined timber sheet. Adult dwarves should feel sturdy,
expressive and a little endearing: broad square heads, compact bodies, readable
eyebrows and noses, large mittens and boots, and clear hair/beard silhouettes.
The current dwarf already has a large head. Simply enlarging it again is less
useful than improving the face, silhouette, material separation and pose.

The proposed change is selective simplification. Broad planar shapes should
carry the identity. A few deliberate voxel steps make corners and natural
contours. One split or knot can explain a log better than many high-contrast
growth rings and bark bands. Round forms remain possible, especially in nature,
but perfect cylinders and uniformly dense concentric detailing should become
less common.

## Concepts

- `01_dwarf_proportions.png`: stout, balanced chibi and playful alternatives,
  with adult appearance variations. Prefer B. Use this sheet for proportion
  and personality; simplify its small texture changes and beveled details when
  building native cubic meshes.
- `02_hand_hewn_timber.png`: refined, quieter timber family. The dining and game
  tables share a body; the game board and six counters distinguish the latter.
  Four stools stay close around the table. The workbench remains a solid stump.
- `03_warm_refuge.png`: proposed color, lighting and character-interaction mood.
  Use it to judge visual hierarchy and readability, not to infer new buildings,
  construction systems or exact object dimensions.

## Rules for a native prototype

1. **Keep 1:16 as the modeling grid.** Broad 2–4-cell steps are a design choice
   within that grid. One-cell detail is most valuable around eyes, brows, a knot
   or the edge of a meaningful crack. Avoid random color changes per cell.
2. **Make silhouettes distinct.** Hair and beards use a handful of large clumps.
   Oak crowns use asymmetric grouped masses; pines use clear stacked tiers.
   Stools and timber use a few irregular planes rather than smooth cylinders.
3. **Keep most surfaces quiet.** Aim for roughly three clear values per material.
   Preserve material identity with color and a few structural cues. Avoid
   target-like rings and uniformly outlined surface voxels.
4. **Separate subjects from surroundings.** Honey wood, warm faces and modest
   rust accents contrast with cooler slate stone. Teal and moss clothing make
   dwarves easy to find. Preserve readable shadow midtones; control flame glare.
5. **Build for the colony camera.** Review distant and close views. The face,
   profession/tool, furniture type and tree species should read before small
   detail. Expressions, head turns and comfortable social poses add personality.
6. **Preserve approved gameplay dimensions.** The dining table stays 3×3 with
   four stools within the 5×5 arrangement. Dining/game bodies remain shared.
   Keep the workbench's 16-cell height, stool contacts, character clearance and
   tool/hand anchors while evaluating any visual proportion changes.
7. **Use the existing renderer contracts.** Bake cubic solids into greedy visual
   meshes with separate coarse shadow-only proxies. These concept images do
   not establish rendering cost or prove geometry/performance compliance.

The recommended first native study is one dwarf, one table/stool family and one
oak beside the existing world blocks, viewed with the normal gameplay camera.
Compare the proposed forms under both neutral light and the proposed warm/cool
lighting. This separates model improvements from attractive concept lighting
before deciding on a wider migration.

Exact generation and refinement prompts are recorded in `prompts.json`.
