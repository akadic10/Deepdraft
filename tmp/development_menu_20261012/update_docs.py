from pathlib import Path
import re

# Keep current playtest instructions usable after retiring the cycling commands.
replacements = {
 'Menu → Development → DEV: Next duck locates one. Start a fresh development world;': 'Click ducks near water to inspect or Follow them. Start a fresh development world;',
 'species; **DEV: Next deer arrival / Next wolf arrival** locates new entrants.': 'species; entered animals use ordinary click inspection and Follow.',
 '**DEV: Arrival status / Next arrival** reviews opportunities and entered rabbits.': '**Development → DEV: Arrival status** reviews opportunities and their outcomes.',
 'shared inspection/Follow and persistence. **Menu → Development → DEV: Next rabbit**\nlocates one. Behavior, native picking/art and full save/backup checks pass.': 'shared inspection/Follow and persistence. Click a rabbit to inspect it.\nBehavior, native picking/art and full save/backup checks pass.',
 'faster escape and quiet selection/eating sounds. **DEV: Next deer** locates one.': 'faster escape and quiet selection/eating sounds. Click deer to inspect them.',
 'are included. **DEV: Next wolf** locates one. Behavior,': 'are included. Click wolves to inspect them. Behavior,',
 'persistent removal. **Menu → Development → DEV: Next boulder** locates one for\nreview. Eight-seed layout, clearing, forestry regression and save/load checks pass.': 'persistent removal. Click a visible boulder for inspection. Eight-seed layout,\nclearing, forestry regression and save/load checks pass.',
 '**DEV: Next scree** locates examples. Worker, eight-seed, Orders and save checks pass.': 'Click loose-stone clumps to inspect them. Worker, eight-seed, Orders and save checks pass.',
 '**DEV: Next blueberry / elderberry / strawberry** locates examples. Worker, native\nOrders, eight-seed and full save/load checks pass.': 'Click shrubs to inspect them. Worker, native Orders, eight-seed and full\nsave/load checks pass.',
 'support loss also remove flowers. **DEV: Next flowers** locates examples.': 'support loss also remove flowers. Click flower clumps to inspect them.',
 'removal and partial work. **DEV: Next reeds** locates examples. Native lake/tarn,': 'removal and partial work. Click reed clumps to inspect them. Native lake/tarn,',
 '**Menu → Development → DEV: Next duck** locates a seeded duck and **DEV: Next\nduck arrival** locates entered members of later flocks. See': 'Click a visible duck to inspect it or use Follow, including birds from later\nflocks. See',
 '**Menu → Development → DEV: Next boulder / DEV: Next scree** cycle through each category,\nrestores full-world view and focuses/selects one without changing work state.': 'Click a visible boulder or loose-stone clump to inspect it without changing\nits work state.',
 'and Follow actions. **Menu → Development → DEV: Next rabbit** cycles the seeded\npopulation. Concealed caves and hidden slice levels never expose rabbit': 'and Follow actions. Concealed caves and hidden slice levels never expose rabbit',
 '  **Menu → Development → DEV: Next deer** cycles the population.\n': '',
 '  **Menu → Development → DEV: Next wolf** locates the sparse population.\n': '',
 'Start a fresh development world and use **Menu → Development → DEV: Next duck**.': 'Start a fresh development world and click a duck near water.',
 'paddle, visit shore or fly; approaching with a dwarf startles it. **DEV: Next\nduck arrival** finds members of later flocks once they have entered.': 'paddle, visit shore or fly; approaching with a dwarf startles it. Later flocks\ncan also be selected once they have entered.',
 '3. Use **DEV: Next duck**, inspect and Follow a bird near water. Watch swimming,': '3. Click and Follow a duck near water. Watch swimming,',
 '   for occasional quacks and waterfall/river ambience. **DEV: Next duck arrival**\n   locates members after a later flock has entered.': '   for occasional quacks and waterfall/river ambience. Later arrivals also\n   support click inspection and Follow.',
 'and removal persist. **DEV: Next flowers** supports review. Data, art, native': 'and removal persist. Click a visible clump to inspect it. Data, art, native',
 'no yield and persistent removal. **DEV: Next reeds** locates generated clumps.': 'no yield and persistent removal. Click visible reeds to inspect them.',
 '2. Choose **Menu → Development → DEV: Next boulder**. This cycles through the\n   generated stones, restores full-world view, focuses the camera and opens\n   Object explorer. It does not designate, remove or reward anything.': '2. Click a visible boulder to open Object explorer. Inspection does not\n   designate, remove or reward anything.',
 '1. Restart the game and choose **Menu → Development → DEV: Next scree**.\n   This cycles through generated clumps and opens **Loose stones** in Object\n   explorer. If a canopy obscures one, cycle again or rotate the camera.': '1. Restart the game and click a visible loose-stone clump to open **Loose stones**\n   in Object explorer. If a canopy obscures it, rotate the camera.',
 '1. Start a world; use **Menu → Development → DEV: Next blueberry**, **Next\n   elderberry**, or **Next strawberry** to locate and inspect a plant.': '1. Start a world and click a visible blueberry, elderberry or strawberry plant\n   to inspect it.',
 'Use **Menu → Development → DEV: Next flowers** to focus and inspect a generated\nclump. It does not clear, reveal terrain or change plant state. Then:': 'Click a visible flower clump to inspect it. Inspection does not clear, reveal\nterrain or change plant state. Then:',
 'Use **Menu → Development → DEV: Next reeds** to focus and inspect a real\ngenerated clump. The locator does not modify terrain, clear reeds or grant items.': 'Click a visible reed clump to inspect it. Inspection does not modify terrain,\nclear reeds or grant items.',
 'For a quick playtest, use **Menu → Development → DEV: Next blueberry**, select\n**Move**, and click nearby open ground.': 'For a quick playtest, click a blueberry bush, select **Move**, and click nearby\nopen ground.',
 'habitats. **DEV: Next flowers** locates clumps; **Clock & weather** can advance\nseasons.': 'habitats. Click flower clumps to inspect them; **Clock & weather** can advance\nseasons.',
 '  Locate/Follow, slice concealment and **DEV: Next rabbit**.': '  Locate/Follow and slice concealment.',
 '1. Start a new play session, then Menu → Development → DEV: Next rabbit.': '1. Start a new play session and click a visible rabbit.',
 '- Explicit selection, including DEV: Next rabbit, plays one short breath/tooth': '- Clicking a rabbit plays one short breath/tooth',
 'To hear it in play, restart the play session and choose **Menu → Development →\nDEV: Next rabbit**, then click it while paused or running.': 'To hear it in play, restart the play session and click a visible rabbit while\npaused or running.',
 'Restart play, then choose **Menu → Development → DEV: Next deer**. Use Follow': 'Restart play, then click a visible deer. Use Follow',
 'Restart play and choose **Menu → Development → DEV: Next wolf**. Follow it to': 'Restart play and click a visible wolf. Follow it to',
 'opportunity and last result. **DEV: Next arrival** locates an entered rabbit,\nincluding one that has settled. Normal opportunities take 2–4 game days and can\nskip at full capacity; these DEV controls do not force a replacement wave.': 'opportunity and last result. Click an entered rabbit to inspect or Follow it,\nincluding one that has settled. Normal opportunities take 2–4 game days and can\nskip at full capacity; the status display does not force a replacement wave.',
 'Restart play and use **Menu → Development → DEV: Next deer arrival** or\n**DEV: Next wolf arrival** to find an entered animal. **DEV: Next arrival** still\ncycles all species, including settled entrants. Full starting populations skip\narrival opportunities until there is room; the controls do not force replacements.': 'Restart play and click an entered deer or wolf to inspect or Follow it.\nDevelopment → DEV: Arrival status reports opportunities and their outcomes.\nFull starting populations skip arrival opportunities until there is room; the\nstatus display does not force replacements.',
}
seen=set()
changed=[]
for path in [Path('AGENT.md'),*Path('docs').rglob('*.md')]:
    original=path.read_text(encoding='utf-8')
    text=original
    for old,new in replacements.items():
        if old in text:
            text=text.replace(old,new)
            seen.add(old)
    text=re.sub(r'Menu → Development', 'Development',text)
    if text!=original:
        path.write_text(text,encoding='utf-8',newline='\n')
        changed.append(str(path))
assert len(seen)==len(replacements),[old for old in replacements if old not in seen]
print(f'Updated {len(changed)} documentation files')
