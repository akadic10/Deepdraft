# 00 — Colony checks

A colony check plays recent changes in a copy of the owner's latest save. It runs the colony's
own dwarves, terrain and crowd: dwarves using the new furniture, work and goods. Pictures of
each check go in `tmp/` for the owner to look at.

From the owner, 2026-11-02: "I think the checks are good but probably overkill to run them every
time we change something". So a colony check runs **once a week**, not after each change:
- **The reminder.** CLAUDE.md ("Colony checks: weekly") keeps the date Claude last asked the
  owner about a check. When that date is a week old or more and the changelog has entries since
  the last check below, Claude asks once at the start of a session and sets the date to today,
  whatever the answer. It only asks: a check runs when the owner says so.
- **Between times,** a check runs only when the owner asks for one.

## Running one

1. **What to cover:** every `00_changelog.md` entry after the last row of the log below.
2. **The save:** copy the owner's latest quicksave
   (`~/.local/share/godot/app_userdata/Deepdraft/saves/quicksave.json`) into an isolated
   profile, never their own. `python3 tools/run_offscreen.py --save res://tmp/<folder>/<Check>.gd`
   does both: it copies the save in as `quicksave.json`, runs the script on a hidden screen (no
   window opens on the owner's desktop) and checks the original afterwards.
3. **The script:** one check script for the week's changes, writing only to
   `tmp/colony_check_YYYYMMDD/`. Cap every wait loop at about 30 game seconds and fail fast,
   so a missed event never stalls a run.
4. **Log it:** add a row at the top of the log, even when nothing was found.

## Log (newest first)

| Date | Covered | Findings | Pictures |
|---|---|---|---|
| 2026-11-16 | The changelog from the boulder smelter (11-09) to the flat data folders (11-15), in the owner's 11-15 colony, Balstad: day 1, five Workers and the flag. Raw goods were stamped beside the flag; the dwarves did the rest over two days at triple speed. A Worker made the crude workbench, a stone hammer and four torches; Valsha collected the hammer and, as Blacksmith, made the basic smelter and the anvil stone; copper melted while the pick, the saw and the hoe were hammered, and the cast bar became the chisel; three Workers collected their tools (Carpenter, Farmer, Miner) and all four wore their hats; the Carpenter made its bench, sawed three logs into six planks and made the plank dining table and bench; the Farmer hoed and sowed a field of six tiles, which was ripened by hand and pulled; the Miner's zone was dug; the colony saved, and a second run loaded that save. Every dwarf was watched each frame for doc 298's faults. The crafting screen was pictured in the untouched colony and after the two days | **Worked.** Every order was made and every piece installed by the dwarves, none by hand. The four torches landed as one crate. A pick ordered with no anvil stone said "Needs an anvil stone". A tool came off the anvil stone while copper still melted. The field took the starter plan, was sown with the summer's carrots, was pulled (all six tiles; 15 carrots in stock afterwards of the 18 six tiles give, the other three taken as eaten by a hungry colony, not watched) and was sown again. No faults in 472 s (worst foot 1.82 lying asleep on the ground, frame 4.68, jump 1.33 blocks). The save loaded with the trades, hats, experience, the seven pieces, the stock, the field's six sown tiles and the dug blocks as they were. The crafting screen lit only Rudimentary at the start, and the Carpenter and the Blacksmith with it afterwards. **One line to look at:** the field's window said "No one is working here now. Farmers need Farm allowed in Labor." while its Farmer slept and nothing was due; it says so whenever a colony's Farmers are elsewhere. Not exercised: hanging a torch from its crate (Balstad has no wall by the camp), rooms and their types, the pallet (planks, copper bars), storage, the Stonemason, the copper pick's speed, and every sound (not heard) | `tmp/colony_check_20261116/` (six sheets and `shots/`) |
| 2026-11-09 | The changelog from the Blacksmith's smelter (11-02) to the food shelf (11-06), in the owner's 11-06 colony: Tekdun charged the smelter, Durrek fished (the trait line in his window, the quiet hour after a catch), the food shelves, two log tables placed from the pallet, a log chair's Move cancelled once packed, the floor mined under another chair, Tekdun made hungry on his way to the bench, and every dwarf watched each frame for doc 298's faults (feet, selection frame, jumps) | **Saves failed** once the cancelled Move's packed chair was stored on the pallet: the save check skips goods in storage furniture (project review 2026-11-09, §1.1). In a second run a loose ladder took the free quarter first and every save worked, which rules out the tables as the cause. Placing the packed chair from Place cleared its Move record. Everything else worked: no faults in 75 s at triple speed (worst foot 1.34, frame 3.76, jump 1.44 blocks), the chair dropped packed into the mined hole, and Tekdun went to eat within a second. Not exercised: building, mining swings, ladder changes, builders walking out, plan rechecks; Tekdun also reached his bench before the stale arrival spot (review §1.4) could show | `tmp/colony_check_20261109/shots/` |
| 2026-11-02 | The tool rack (doc 294, step 3): a dwarf hung it on a rock wall by the camp, haulers filled it with three tools ahead of the colony's zone, its windows, and a dwarf took off the hoe once it was no longer kept | Worked. Fixed in the check script, not the game: the reach shot's distance limit was too tight | `tmp/storage_build_20261102/colony/` |
| 2026-11-01 | The stone stool (doc 293, step 3): Ingvin made one at the mason's bench, and it was put at the colony's dining table | The stool worked. Ralin ate elsewhere, because the dining search ran out of time at triple speed; not a stool bug | `tmp/mason_carpenter_build_20261101/stool/` |
| 2026-11-01 | The carpenter's and mason's benches (doc 293, step 2): both at work, the Stonemason's career page, the Carpenter's crafting page | Worked | `tmp/mason_carpenter_build_20261101/colony/` |
