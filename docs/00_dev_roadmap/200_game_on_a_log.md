# Game on a log

2026-10-16. The player found the fitted Board-game Table too refined for the
rudimentary tier and requested a 3×3 space with a game on a log.

## Appearance and placement

The table is now one squat section of trunk, with broad bark faces, a slightly
flared base, chipped cut edges and narrow end-grain rings. An uneven charcoal
grid sits directly on the cut surface; six unequal light/dark stone counters
make the game readable. There are no legs, fitted planks or metal fittings.
The model has 968 triangles, one named mesh and one opaque vertex-colour surface.
Wood uses the existing oak semantic palette so all four timber variants work;
the stones and charcoal keep their own colours.

The game itself reserves **3×3 tiles**. Its playing surface is 0.78 blocks high,
with stone counters reaching 0.85. Two independently built 1×1 log stools snap
immediately outside opposite sides, giving a 3×5 rectangle of furniture tiles.
Seated dwarf clearance and reachable adjacent ground remain necessary. The
lower surface allows this closer seating without changing dwarf proportions,
navigation or stool clearance. The preview outlines the game area, and the
Place card explains that the stools go outside it.

The name remains **Board-game Table** under Rudimentary crafting → Recreation
and Place → Recreation. It still costs two timber and one rough stone and takes
18 seconds to craft. The two-player game and +8 happiness for 12 game hours
remain as described in [198](198_rudimentary_recreation.md).

## Runtime and saves

Playing hands now reach toward the log's surface from either seat, replacing
the fixed upward offset intended for the taller table. Idle hands, bodies and
boots keep the existing log-stool pose. The happiness inspector also uses a
supported numeric format, so its reward text displays correctly.

Current games, stools, orientations and materials survive save/reload. Under
the project's development-save policy, existing tables adopt the new 3×3
definition when reloaded. Old stool placements may need moving onto the new
guides; an older crowded layout may need adjusting. No obsolete model or
compatibility layout is retained. Restart Play to load the model and definitions.

## Validation

Native source-project fixtures cover real crafting/installation, full 3×3
navigation blocking, stool clearance and snapping in all four rotations,
current save/restore, two-player completion, needs and movement interruptions,
pause/speed, happiness and cargo conservation. Native art checks cover the
imported footprint, surface height, all four wood palettes and unchanged stone
colours. Placement, furniture movement and the crafting browser are checked
alongside the updated thumbnail and Place card. The generator's `--check`
verifies reproducible closed geometry.

Evidence is kept in [log_game_20261016](concepts/log_game_20261016/summary.json),
including [the log and stools](concepts/log_game_20261016/log_game.png),
[two players](concepts/log_game_20261016/playing_1.png), the opposite player's
reach, placement UI and compressed fixture logs. No Windows playtest was created
or updated.
