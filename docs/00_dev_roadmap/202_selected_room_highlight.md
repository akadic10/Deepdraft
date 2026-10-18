# Selected room highlight

2026-10-17. The player requested a visible highlight linking a clicked room to
its inspector. The existing selection only changed floor opacity from 0.3% to
0.6%, leaving all volume outlines the same colour.

The selected room now has a gold volume outline and a 0.06-block-wide gold
border following its actual floor perimeter. A subtle gold floor tint uses
0.8% opacity, keeping unlit rooms visibly dark. Unselected rooms retain green
outlines, or icy blue for Frozen Vaults. Walls and ceilings remain unfilled.

Selection updates the previous and newly selected rooms' materials immediately;
it does not rebuild every room's geometry. Closing the inspector removes the
highlight immediately. Existing slice visibility and through-rock room picking
remain in effect. Topology updates still re-resolve selection using the clicked
air cell; losing the room seal closes the inspector and removes its highlight.
The overlay is derived presentation state and adds no saved data or autoload.

The native RoomLightingTest now includes an adjacent room and real screen clicks
between them, immediate selection changes, inspector dismissal, slice visibility,
topology rebuilds and seal loss. Its existing dark-room luminance, local lights,
fog, draggable inspector and compact-layout checks also cover this change.
The first review reduced the floor tint from 3.5% to 0.8% after the dark-room
check showed excessive brightening. The click fixture places its inspector away
from the room targets so ordinary GUI input blocking remains respected.

Evidence: [native results and screenshots](concepts/room_selection_20261017/summary.json).
Restart Play. No Windows playtest was created or updated.
