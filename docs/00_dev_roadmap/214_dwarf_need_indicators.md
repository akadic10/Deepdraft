# 214 — Dwarf need indicators

The first concern badges make serious needs visible without opening every dwarf.
One copper-framed symbol sits above the animated head: an empty plate for food,
a crescent and Z marks for exhaustion, or an unhappy face for low happiness.
These are authored SVG icons, independent of system emoji fonts.

`DwarfConcern` reads existing food, rest and mood state. It does not plan routes,
claim items, change behavior or save new fields. The same concern appears in
the inspector's **Right now** card, with its reason and an action the player can
take. The Colony roster's embedded inspector receives the same information.

## Conditions and priority

1. Famished food level (the existing 15% threshold).
2. Exhaustion at 15% rest, or an unresolved rest search/trip after six seconds.
3. Ordinary hunger with an actual failed food search.
4. Happiness at or below 40%, naming the strongest active negative thought.

Ordinary hunger while seeking a meal is quiet. A reserved portion replaces the
shortage wording with “Collecting food”; a carried meal explains that recovery
comes after eating. Exhaustion clears when settling into actual sleep. Bed
searches do not claim a bed shortage until the rest behavior has fallen back
to ground rest. Existing simulation thresholds, sleep/meal behavior and mood
values are unchanged. Display thresholds and sizing are in
`data/ui/dwarf_indicators.json`, loaded only by UIRegistry.

## Presentation

`DwarfNeedIndicators` is a scene-owned CanvasLayer below ordinary windows and
the HUD. It projects the animated head into screen space each frame, with a
brief gentle pulse when the displayed need or severity changes. Resolved
concerns fade out. Need/occlusion checks run four times per second; the display
remains useful while paused. Badges ignore mouse input, preserving normal dwarf
selection and tool controls.

Sizing uses viewport height, so 16:9, 21:9 and 32:9 retain the same icon size at
the same height. Distant actors fade out before the icons become clutter. Hidden
slices, offscreen actors and opaque terrain suppress badges. Terrain visibility
uses the shared slice-aware picking ray and respects the current underground
inspection view. Loading hides this layer through the existing loading gate.
Removed/reloaded actors release their badges by node identity.

## Validation

`DwarfNeedIndicatorsTest` uses real actors, native picking, the shared inspector,
terrain occlusion and the loading gate. It covers urgent-need priority, truthful
food/bed explanations, mood causes, resolution, saved-need reconstruction,
pause, zoom, slice hiding, actor removal and all three aspect ratios. Rendered
captures were inspected alongside the assertions. Existing inspector, roster,
food and rest regressions also pass: five native scripts in total. The roster
fixture now initializes the waterline map required by final-state terrain reads
from milestone 212.

A copy of the player's quicksave loads successfully. Its two famished dwarves
derive food concerns immediately from saved values; the visible selected dwarf
shows the plate badge and matching inspector advice while paused. The actual
loading gate hides the indicator layer until the world is ready.

Copied-player-save results, logs and screenshots are in
[the validation record](concepts/dwarf_concerns_20261017/summary.json).
No player save is rewritten and no Windows playtest is exported. Restart Play
to load the new scene layer; existing saves derive badges from their saved needs.
