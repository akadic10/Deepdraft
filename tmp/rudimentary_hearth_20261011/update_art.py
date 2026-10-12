from pathlib import Path

root = Path(__file__).resolve().parents[2]
path = root / 'tools/generate_hearth_redesign.py'
source = path.read_text(encoding='utf-8')
start = source.index('def hearth(phase=None):')
end = source.index('\n\ndef hearth_parts', start)
source = source[:start] + '''def hearth(phase=None):
    """A low open-front fire bed, banked with rough dry-stacked fieldstones."""
    v = Voxels()
    # Soot and packed earth join the grounded stones, with a broken outline.
    # There is no cut plinth, dressed rim, grate or metal fitting.
    for x in range(-7, 7):
        for z in range(-7, 7):
            if abs(x + .5) + abs(z + .5) <= 10:
                v.cells[x, 0, z] = COAL if abs(x) < 4 and abs(z) < 4 else STONE[0]

    def rock(x0, z0, width, depth, height, shade):
        for y in range(height):
            for dx in range(width):
                for dz in range(depth):
                    # Broad chipped shoulders, not a rounded or bevelled mesh.
                    corner = dx in (0, width - 1) and dz in (0, depth - 1)
                    if corner and y != 1:
                        continue
                    if y == height - 1 and (dx == 0 or dz == depth - 1):
                        continue
                    color = STONE[shade]
                    if y == height - 1:
                        color = STONE[min(shade + 1, 4)]
                    elif y == 0:
                        color = STONE[max(shade - 1, 0)]
                    v.cells[x0 + dx, y, z0 + dz] = color

    # Taller uneven back bank, squat side stones and a low open mouth.
    # Different widths/heights and staggered shoulders avoid masonry courses.
    for stone in [(-7,-7,5,4,5,2), (-2,-8,5,4,6,2), (3,-7,5,4,5,3),
                  (-8,-3,4,5,4,3), (4,-3,4,4,5,2),
                  (-7,2,4,4,3,2), (4,1,4,5,4,3),
                  (-5,5,4,3,2,3), (2,5,4,3,2,2)]:
        rock(*stone)
    # Low ash bed: the fire sits on the ground rather than in a tall bowl.
    for x in range(-4, 4):
        for z in range(-4, 5):
            if abs(x) + abs(z) < 7:
                v.cells[x, 1, z] = EMBER if (x + 2*z) % 5 == 0 else COAL
    # Two chunky unsawn logs point out of the mouth. Brown end grain and
    # charred tops stay visible around the flame; neither log is an iron rail.
    bark = tuple(map(rgb, ('493020', '68452B', '886038', 'AE8450')))
    for x0, front in ((-4, 5), (1, 6)):
        for z in range(-3, front):
            for dx in range(3):
                for y in range(1, 4):
                    if y == 3 and dx != 1:
                        continue
                    color = bark[1 if dx == 0 else 2]
                    if z == front - 1:
                        color = bark[3] if dx == 1 and y == 2 else bark[1]
                    elif z < 2 and y >= 2:
                        color = COAL if (z + dx) % 3 else EMBER
                    v.cells[x0 + dx, y, z] = color
    # A fixed ember/flame base leaves the body identical in every frame.
    for x in range(-3, 3):
        for z in range(-2, 3):
            v.cells[x, 4, z] = FIRE[0] if abs(x) > 1 else FIRE[1]
    # Three simple stepped tongues rise directly from that base. Their tips
    # change by single voxels, preserving the game's chunky early-camp style.
    t = 0.0 if phase is None else phase
    for group, (cx, cz, height, offset) in enumerate(((-1,-1,8,0), (-2,1,5,2.1), (1,1,6,4.2))):
        top = 4 + height + round(math.sin(t + offset))
        for y in range(5, top + 1):
            progress = (y - 5) / max(1, top - 5)
            bend = round(progress * math.sin(t + offset))
            width = 3 if progress < .4 else 2 if progress < .8 else 1
            x0 = cx - 1 + bend
            z0 = cz - (1 if width > 1 else 0)
            for x in range(x0, x0 + width):
                for z in range(z0, z0 + width):
                    color = FIRE[1 if group == 0 else 2]
                    if y <= 7 and x >= -1 and z >= 0:
                        color = FIRE[3]
                    elif progress > .8:
                        color = FIRE[2]
                    v.cells[x, y, z] = color
    return v
''' + source[end:]
source = source.replace('Animation changed the bowl or grate', 'Animation changed the fieldstones or logs')
# Keep the standalone project using the same dependency layout as production.
source = source.replace("shutil.copyfile(ROOT/'scripts/components'/name,out/name)", "destination = out/'scripts/components'/name\n        destination.parent.mkdir(parents=True,exist_ok=True)\n        shutil.copyfile(ROOT/'scripts/components'/name,destination)")
source = source.replace("'stone_rim_height':1.0,'heat_units':400", "'stone_rim_height':.75,'heat_units':definition['heat_source']['heat_units']")
source = source.replace("default=ROOT/'tmp/hearth_animation_preview'", "default=ROOT/'tmp/rudimentary_hearth_20261011'")
source = source.replace('Exports a review under tmp/hearth_animation_preview.', 'Exports a review under tmp/rudimentary_hearth_20261011.')
path.write_text(source, encoding='utf-8', newline='\n')
