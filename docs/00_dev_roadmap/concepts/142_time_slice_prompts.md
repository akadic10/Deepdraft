# 142 — Time and Slice production art prompts

Generated with the built-in `image_gen` tool on 2026-10-12. No CLI/API fallback.

Approved style reference: `C:/Users/akadi/.codex/generated_images/01a13068-1a8f-7622-9da5-15524d87a06c/exec-3beb0e34-8f8e-4564-b6cc-3d771ab72449.png`.

Final project asset: `assets/ui/time_slice/controls_atlas.png` (1536 × 1024).
UIRegistry regions are in `data/ui/time_slice.json`. The generated file retained
an opaque backdrop despite the transparency request; TimeSliceButton displays
the eight framed regions through their beveled polygon apertures. No backdrop
is shown in the game. The source image is preserved without raster processing.
Selection, disabled state and level text are rendered by Godot.

## Atlas generation

```text
Use case: ui-mockup. Asset type: production sprite atlas for Deepdraft's approved fixed time-and-slice HUD.
Input image 1 is the approved visual STYLE reference only; generate isolated components, not a concept board.
Create a transparent-background atlas, 1536 x 1024, organized precisely as 4 equal columns and 2 equal rows. Eight isolated UI button sprites, generous transparent gaps, no text, no labels, no numbers, no surrounding game or board.
Style: same rich illustrated copper bevels and dark forest-green iron in the reference. Crisp chunky warm copper symbols, readable at 48px. Front orthographic UI view. Frame highlights from upper-left. Every button unselected, no glow, no active notch (runtime draws selection).
Top row: FOUR SQUARE buttons of equal size, centered in their cells: (1) pause two vertical copper bars, (2) play one right-pointing copper triangle, (3) fast two right-pointing copper triangles, (4) illustrated mountain with a visible glowing horizontal cut through rock. Top row cell dimensions 384 x 512; buttons around 330 x 330 and centers (192,256),(576,256),(960,256),(1344,256).
Bottom row: FOUR WIDE SHORT buttons with same style frames, aspect ratio 2:1, around 330 x 165, centered at (192,768),(576,768),(960,768),(1344,768): (1) two UP triangles stacked vertically, (2) one UP triangle, (3) one DOWN triangle, (4) two DOWN triangles stacked vertically. Each double arrow contains exactly TWO triangles. Make these direction symbols bold and large.
Dark green recessed interiors, clipped corners and beveled copper edges as in reference. Preserve real alpha transparency outside each frame. No text anywhere. No watermark.
```

## Background-removal pass

```text
Edit this exact eight-button UI atlas. Remove ONLY the brown/black backdrop and every halo outside the eight copper button frames. Make all space outside the button silhouettes fully transparent (alpha 0). Preserve the exact canvas size, all eight button positions, geometry, copper frames, internal dark green backgrounds and all symbols and mountain exactly. Transparent clipped corners outside each frame. No added shadows or glow outside frames. This is a production sprite sheet requiring real alpha transparency, not a checkerboard or flat background.
```
