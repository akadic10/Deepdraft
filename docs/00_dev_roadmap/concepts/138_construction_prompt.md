# 138 — Construction artwork prompt

Mode: built-in imagegen. Style reference: `assets/ui/dock/zones_atlas.png`.
Shape references: `assets/ui/construction/plank_floor.png` and
`assets/ui/construction/stone_floor.png`. Final asset:
`assets/ui/dock/construction_atlas.png`. The generated sheet is preserved;
Godot selects atlas regions at runtime.

```text
Use case: stylized-concept.
Asset type: one production sprite atlas for Deepdraft Construction and Floors menus.
Reference 1: Deepdraft Zones atlas, style reference only. References 2 and 3: actual installed plank/stone block thumbnails, pattern and full-block shape references only.
Create exactly FOUR equally sized square illustrated buttons in a precise two-by-two grid on dark charcoal green. Canvas 1536x1024, each frame about 390x390, with spacious margins and clean gaps. No text anywhere, no sample toolbar, no extra icons.
Top left: STONE BLOCK — one large solid cubic gray natural stone block in three-quarter view, subtly chiseled facets but a smooth continuous unbroken top. A few tiny stone chips at its foot. One block, not brickwork or a wall. Clear readable gray cube silhouette.
Top right: FLOORS category — a low-perspective square sample of a laid floor, half staggered warm wooden planks and half orderly gray stone slabs meeting along the middle. The pattern fills the square; no rug, no border trim, no tools covering the sample.
Bottom left: SIMPLE PLANK FLOOR — one full cubic construction block with its broad top made of simple warm honey-brown staggered boards, as in reference 2. Readable parallel planks, understated grain, matte timber sides. No parquet zigzag, no nails, no carpet, no elaborate decoration.
Bottom right: SIMPLE STONE FLOOR — one full cubic construction block with broad top of repeating staggered rectangular gray stone slabs, as in reference 3. Flat even top, subtle narrow darker joints, plain gray stone sides. No cobblestones or paving gravel.
Style: reference 1's richly crafted hand-painted fantasy game icons, chunky simplified silhouettes, faceted shading, warm top-left lighting, dark iron clipped-corner square frames with aged copper bevels. Charcoal #202827, copper #d2a06b, warm ivory highlights, natural timber and cool stone. Original Deepdraft artwork. All full color, equal visual weight, identical frame dimensions and perspective. Objects entirely inside frames, crisp silhouette readable at 56px. No text, labels, arrows, status badges, disabled shading, watermark or extra decoration.
```
