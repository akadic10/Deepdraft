# 159 — Crude workbench stump

**2026-10-13:** The player identified that the converted crude workbench looked
too advanced. Its fitted plank top, legs and diagonal braces contradicted the
existing recipe and furniture descriptions, which call for an axe-hewn stump.

The replacement is one solid trunk section with broad bark planes, an irregular
flared base, a chipped rim, restrained end grain and short split marks. It uses
the shared faceted style and exact `oak_log` material roles so Pine, Oak,
Juniper and Applewood still recolor correctly. The work surface is level at
the existing **0.875-block crafting height**; the previous art reached 1.0.
This brings the visible top into agreement with worker ingredient/axe contacts.

The one-tile footprint, four-sided access, item/recipe identities, build time,
wood requirements, collision, crafting behavior and save schema are unchanged.
Only `assets/models/furniture/crude_workbench.glb` and its catalogue PNG change
among production assets. All other **380 GLBs** and other UI images retain
their exact bytes. The existing packed furniture representation remains valid.

Authoring lives in `tools/generate_furniture_faceted.py::workbench` and the
`crude_workbench` section of `data/art/furniture_catalog.json`. Working height
comes from the existing furniture definition. The closed model has **280
triangles**, down from 668, with one opaque vertex-color surface and unit root.
The thumbnail was rendered through `FurnitureCatalogThumbnails.gd
--only=crude_workbench` from the actual imported model.

Verification:

- Full furniture reproduction and closed-geometry checks pass.
- Furniture art checks cover the imported surface height and all four wood palettes.
- Worker crafting, allowed woods and furniture move/save-restoration fixtures pass.
- Native stump crafting completes 16 batches across all four approaches and
  rotations, including material/axe contact, blocked sides and restored occupancy.
- Native front/back views cover all four woods. The refreshed catalogue icon
  and in-use captures were visually inspected.
- Godot's current import matches the source; importer settings and gameplay
  definitions are byte-identical. Both historical art audits pass using the
  explicit revision fingerprint in `data/art/asset_revisions.json`.

The mesh-contact assertion is added to the existing furniture art fixture so
a future model cannot silently move the working surface above the ingredient.
Historical conversion reports retain their original model hashes and costs;
offline audits resolve this recorded revision while retaining strict checks.

Evidence: [inventory](concepts/159_workbench_stump/inventory.json),
[validation](concepts/159_workbench_stump/validation.json),
[native Pine view](concepts/159_workbench_stump/pine.png), and
[four-sided crafting](concepts/159_workbench_stump/four_sides.png).

Restart Play to refresh cached art and catalogue textures. Existing installed
workbenches load the new model automatically; no new world is needed.
