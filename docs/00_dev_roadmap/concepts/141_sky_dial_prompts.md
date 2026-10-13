# 141 — Sky Dial artwork prompts

Generated with the built-in image generation tool on 2026-10-12. The approved concept board was the frame reference; landscape and symbol atlases were new images. Original PNGs were copied into the project without raster edits. Godot handles masking, atlas regions, live text and cycle geometry.

## Frame — transparent

Use case: precise-object-edit. Asset type: production game HUD transparent frame.
Input image is the approved Deepdraft Sky Dial design board. Extract and adapt ONLY the copper-and-dark-iron frame of the FIRST sky dial as ONE large isolated UI frame on a square 1024x1024 transparent canvas. Match its original hand-painted Hearth & iron style, warm worn copper bevels, clipped octagonal shoulders and charcoal-green inset plaques. Face-on, no perspective.
Remove ALL landscape, sky, clock numerals, lettering, season emblems, weather icons, sun/moon markers and all gold/navy day track fills. The large sky opening must be genuinely TRANSPARENT. Exterior is transparent. Keep two solid BLANK dark-green plaques below the opening for runtime time text and season text. Keep a small blank round copper weather badge attached at the right lower edge of the sky opening with a solid dark interior. No left protruding badge. Maintain a clean symmetrical compact silhouette and little copper diamond at top and bottom.
Precise intended layout in 1024 square: outer frame roughly x80..944 y48..974. Sky opening circular upper dome with top around y145, left x160, right x860, bottom at y650, and horizontal bottom. Preserve a 35px-wide blank dark track immediately inside the upper curved bezel, for runtime day/night segments. Time plaque x140..885 y665..802. Footer plaque x180..845 y818..930. Weather badge centered approximately x865 y614 radius88. Broad open interiors so live text is readable. Leave margins around entire frame. No text anywhere, no scene or stars, no clock marks. Real alpha transparency in opening and around exterior, not painted checkerboard. This will be overlaid on live sky graphics in Godot.

## Landscapes — opaque

Use case: stylized-concept. Asset type: production game UI landscape atlas. Create one image containing EXACTLY eight equally sized rectangular fantasy mountain landscape tiles in a seamless strict TWO COLUMN by FOUR ROW grid. Edge to edge tiles, absolutely NO borders, gutters, captions, lettering, frames, icons or watermark. Portrait canvas 1024x1536 so each tile is 512x384. These will be used behind the copper Sky Dial frame of Deepdraft.
Each tile shows the SAME recognizable angular dwarven mountain and pine valley composition, simplified painterly facets, broad clear silhouettes, beautifully crafted Hearth & iron game illustration, detailed enough for a 200px HUD, quiet uncluttered scene. Mountains occupy bottom 60%, plain clear sky top40%. No buildings, no people. No sun or moon discs, no clouds, no precipitation; these are added dynamically. Night tiles may have a few quiet stars.
ROW1 spring: LEFT fresh light green valley under pale blue daylight; RIGHT same spring view under deep blue night.
ROW2 summer: LEFT rich forest green valley and gray mountain in warm golden daylight; RIGHT same summer view in clear indigo night.
ROW3 autumn: LEFT amber/copper deciduous trees among pines in warm daylight; RIGHT same autumn view in clear blue night.
ROW4 winter: LEFT snowy mountain and white frosted valley in pale cold daylight; RIGHT same snowy view under clear midnight blue.
Keep mountain location and scale IDENTICAL across all eight tiles, highest peak slightly right of center. Light from upper left in day tiles, gentle cool moonlight at night. Original hand-painted game art with confident brushwork and faceted shapes, not photograph or generic gradient. Exact regular grid is essential for atlas slicing. No text anywhere.

## Symbols — transparent

Use case: stylized-concept. Asset type: production transparent UI symbol atlas for Deepdraft's Hearth & iron Sky Dial.
Create exactly NINE isolated beautifully hand-painted fantasy game symbols in a strict regular THREE BY THREE grid on a square transparent canvas, equal cells. One symbol centered in each cell, consistent visual weight, wide transparent gutters (each symbol occupies only central 65% of its cell), no touching, no borders or backgrounds. Chunky recognizable shapes, faceted highlights, warm rich materials, readable at 24px, refined painted RPG icon style.
ROW1 left: warm golden SUN disc with eight large pointed rays. Center: pale ivory silver CRESCENT MOON, opening right, no face, no stars. Right: plump blue-gray OVERCAST CLOUD with shadowed underside, no rain.
ROW2 left: FOG symbol, three soft layered pale horizontal mist ribbons with one little cloud behind. Center: SNOW weather symbol, a blue-gray cloud over three large white snowflakes. Right: SPRING emblem, fresh green sprig with a single pink blossom.
ROW3 left: SUMMER emblem, rich green leafy sprig with three leaves. Center: AUTUMN emblem, a single warm copper-orange maple leaf. Right: WINTER emblem, one large icy blue six-armed snowflake.
No text, labels, numerals, circles, badges, checkerboard, scenery, or frames. Genuine alpha transparency everywhere outside the nine symbols. Keep all nine exact grid centers and equal scale.
