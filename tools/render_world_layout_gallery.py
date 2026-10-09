"""Render actual Godot macro-map exports for doc 66; requires Pillow.

Run WorldLayoutTest.gd first. baseline.json is the captured pre-integration reference. Images are geography
diagrams, not screenshots or claims about the final terrain materials.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
BG = "#101c23"
PANEL = "#1b2b32"
TEXT = "#e6ede9"
MUTED = "#9cafa9"
SHELVES = [19, 27, 35, 43, 55, 67, 79, 91, 103, 115]
COLORS = ["#477865", "#679378", "#92a580", "#bbb38b", "#a89876",
          "#b3a48d", "#b9b3a4", "#c9c8bd", "#deded2", "#ffffee"]
WATER = "#339fcd"
TARN = "#85d9f2"


def font(size, bold=False):
    fonts = Path("C:/Windows/Fonts")
    return ImageFont.truetype(str(fonts / ("segoeuib.ttf" if bold else "segoeui.ttf")), size)


def rgb(color):
    return tuple(int(color[i:i + 2], 16) for i in (1, 3, 5))


def tint(color, factor):
    return tuple(round(c * factor) for c in rgb(color))


def cell_color(layout, index):
    water = layout["water_index"][index]
    if water >= 0:
        return WATER if water == 0 else TARN
    y = layout["heights"][index]
    rank = min(range(len(SHELVES)), key=lambda i: abs(y - SHELVES[i]))
    return COLORS[rank]


def topdown(layout, side=384):
    image = Image.new("RGB", (side, side), BG)
    draw = ImageDraw.Draw(image)
    cell = side / 32
    for x in range(32):
        for z in range(32):
            draw.rectangle((round(x * cell), round(z * cell), round((x + 1) * cell) - 1,
                            round((z + 1) * cell) - 1), fill=cell_color(layout, x * 32 + z))
    for k in range(0, 33, 4):
        coord = min(side - 1, round(k * cell))
        draw.line((coord, 0, coord, side - 1), fill="#354d4850", width=1)
        draw.line((0, coord, side - 1, coord), fill="#354d4850", width=1)
    return image


def isometric(layout, width=620, height=440):
    image = Image.new("RGB", (width, height), PANEL)
    draw = ImageDraw.Draw(image)
    sx, sz, sy = 8.5, 4.25, 1.15

    def point(x, z, y):
        return (width / 2 + (x - z) * sx, 148 + (x + z) * sz - y * sy)

    def surface(index):
        if layout["water_index"][index] == 0:
            return 18
        if layout["water_index"][index] == 1:
            return 54
        return layout["heights"][index]

    for diagonal in range(63):
        for x in range(32):
            z = diagonal - x
            if not 0 <= z < 32:
                continue
            index = x * 32 + z
            y = surface(index)
            color = cell_color(layout, index)
            next_x = surface((x + 1) * 32 + z) if x < 31 else 0
            next_z = surface(x * 32 + z + 1) if z < 31 else 0
            if next_x < y:
                draw.polygon([point(x + 1, z, y), point(x + 1, z + 1, y),
                              point(x + 1, z + 1, next_x), point(x + 1, z, next_x)], fill=tint(color, .60))
            if next_z < y:
                draw.polygon([point(x, z + 1, y), point(x + 1, z + 1, y),
                              point(x + 1, z + 1, next_z), point(x, z + 1, next_z)], fill=tint(color, .78))
            draw.polygon([point(x, z, y), point(x + 1, z, y),
                          point(x + 1, z + 1, y), point(x, z + 1, y)], fill=color)
    draw.text((25, height - 28), "Relief diagram · height exaggerated", font=font(15), fill=MUTED)
    return image


def legend(draw, x, y, compact=False):
    step = 69 if compact else 79
    for i, level in enumerate(SHELVES):
        draw.rectangle((x + i * step, y, x + i * step + 15, y + 15), fill=COLORS[i])
        draw.text((x + i * step + 21, y - 5), str(level), font=font(18), fill=TEXT)
    draw.text((x, y + 30), "Y height    •    Blue: lake / pale blue: tarn    •    No reserved starting area", font=font(18), fill=MUTED)


def render(output):
    gallery = json.loads((output / "gallery.json").read_text())
    report = json.loads((output / "report.json").read_text())
    layouts = gallery["layouts"]
    image = Image.new("RGB", (1760, 2200), BG)
    draw = ImageDraw.Draw(image)
    draw.text((40, 24), "DEEPDRAFT  /  SEEDED GEOGRAPHY", font=font(36, True), fill=TEXT)
    draw.text((40, 80), "Seeded macro layout • 16 fixed seeds • 1024×1024 blocks per map • north up", font=font(22), fill=MUTED)
    draw.text((40, 121), "Y115 summit on every seed · terrain-derived lakes · no fixed compass layout", font=font(22), fill=TEXT)
    for i, layout in enumerate(layouts):
        x, y = 40 + (i % 4) * 430, 186 + (i // 4) * 470
        draw.rounded_rectangle((x - 12, y - 8, x + 408, y + 450), radius=12, fill=PANEL)
        draw.text((x, y), f"Seed {layout['seed']}", font=font(23, True), fill=TEXT)
        image.paste(topdown(layout, 384), (x + 6, y + 40))
        m = layout["metrics"]
        detail = f"Mountain {m['connected_summit_mountain_cells'] / 10.24:.1f}%"
        detail += "  ·  tarn" if m["has_tarn"] else "  ·  no tarn"
        detail += "  ·  coastal" if m["lake_coastal"] else "  ·  inland"
        draw.text((x, y + 429), detail, font=font(17), fill=MUTED)
    legend(draw, 42, 2090)
    draw.text((42, 2170), "Shape and elevation only. Edge detail, materials, flora and navigation are not part of this preview.", font=font(18), fill=MUTED)
    image.save(output / "seed_gallery.png")
    for layout in layouts:
        detail = Image.new("RGB", (1160, 750), BG)
        d = ImageDraw.Draw(detail)
        d.text((32, 20), f"SEED {layout['seed']}  /  MACRO GEOGRAPHY", font=font(32, True), fill=TEXT)
        d.text((32, 75), "Top view • north up", font=font(20), fill=MUTED)
        detail.paste(topdown(layout, 480), (32, 113))
        detail.paste(isometric(layout), (525, 136))
        m = layout["metrics"]
        d.text((540, 105), f"Y115 summit: {m['summit_cells']} × 32×32 cells", font=font(23), fill=TEXT)
        d.text((540, 590), f"Connected mountain: {m['connected_summit_mountain_cells'] / 10.24:.1f}% of map", font=font(21), fill=TEXT)
        legend(d, 34, 655)
        detail.save(output / f"seed_{layout['seed']}.png")
    baseline_path = output / "baseline.json"
    if baseline_path.exists():
        baselines = json.loads(baseline_path.read_text())["layouts"]
        comparison = Image.new("RGB", (1150, 1610), BG)
        d = ImageDraw.Draw(comparison)
        d.text((35, 20), "PREVIOUS GEOGRAPHY  →  SEEDED LAYOUT", font=font(32, True), fill=TEXT)
        d.text((35, 75), "Same three seeds · same colors and scale · north up", font=font(22), fill=MUTED)
        d.text((35, 113), "Previous maps sample macro-cell centers; seeded layout shows exact macro footprints.", font=font(19), fill=MUTED)
        for i, old in enumerate(baselines):
            new = next(layout for layout in layouts if layout["seed"] == old["seed"])
            y = 163 + i * 460
            d.text((35, y), f"Seed {old['seed']} · previous", font=font(23, True), fill=TEXT)
            d.text((595, y), "Seeded layout", font=font(23, True), fill=TEXT)
            comparison.paste(topdown(old), (35, y + 38))
            comparison.paste(topdown(new), (595, y + 38))
            d.text((440, y + 215), "→", font=font(50), fill=MUTED)
        legend(d, 35, 1545)
        comparison.save(output / "baseline_comparison.png")
    cards = "\n".join(f'<a href="seed_{l["seed"]}.png"><img loading="lazy" src="seed_{l["seed"]}.png" alt="Seed {l["seed"]}"></a>' for l in layouts)
    comparison_link = '<p><a href="baseline_comparison.png">Open the three-seed baseline comparison</a></p>' if baseline_path.exists() else ""
    live_cards = "\n".join(
        f'<a href="{path.name}"><img loading="lazy" src="{path.name}" alt="{path.stem.replace("_", " ")}"></a>'
        for path in sorted(output.glob("live_*_*.png")))
    live_section = (f'<h2>Live game captures</h2><p>Normal initial views, natural terrain and wide mountain views for two seeds. '
                    f'Close-ups inspect cliffs and water banks. Inspection views disable distance fog; wide mountains also use extended zoom.</p>'
                    f'<div class="grid">{live_cards}</div><h2>Macro layouts</h2>') if live_cards else ""
    document = f'''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Deepdraft · Seeded geography review</title><style>body{{margin:32px;background:{BG};color:{TEXT};font:18px/1.6 system-ui;max-width:1500px}}h1{{font-size:36px}}a{{color:{TARN}}}.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(460px,1fr));gap:20px}}img{{width:100%;border-radius:10px}}p{{max-width:1000px}}small{{color:{MUTED}}}</style>
<h1>Deepdraft · Seeded geography review</h1><p>Every map reaches Y115 with a summit at least 32×32 blocks, a substantial connected mountain region, one lowland lake and an optional mountain tarn. Terrain and trees generate naturally throughout the world. Players choose and clear their own settlement location.</p>
<p><b>{report['sample_count']:,} seeds passed.</b> Connected mountain area: {report['connected_mountain_cells']['min'] / 10.24:.1f}–{report['connected_mountain_cells']['max'] / 10.24:.1f}%. {report['tarn_count']} seeds include a tarn. {report['coastal_lake_count']} lakes meet an edge; {report['inland_lake_count']} are inland.</p>
<p><small>Macro geography only, before edge detail, terrain materials, flora or navigation. The normal game uses this layout with protected edge detailing. Relief diagrams exaggerate height. Click an image to inspect it.</small></p>
<p><a href="seed_gallery.png">Open the 16-seed overview</a> · <a href="report.json">Validation report</a></p>{comparison_link}{live_section}<div class="grid">{cards}</div></html>'''
    (output / "index.html").write_text(document, encoding="utf-8")
    print(f"Rendered {len(layouts)} seed panels, overview and review page in {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "tmp/world_layout_review")
    render(parser.parse_args().output)
