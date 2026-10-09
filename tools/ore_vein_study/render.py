"""Build a self-contained fragment and a static reference from measured voxels."""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'tmp/ore_vein_review'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('fragment', type=Path)
    args = parser.parse_args()
    template = (Path(__file__).parent / 'comparison.template.html').read_text(encoding='utf-8')
    data = (OUT / 'inline_data.json').read_text(encoding='utf-8')
    fragment = template.replace('/*__ORE_DATA__*/null', data)
    assert len(fragment.encode()) < 1_000_000
    args.fragment.parent.mkdir(parents=True, exist_ok=True)
    args.fragment.write_text(fragment, encoding='utf-8')
    summary = json.loads(data)
    seed = next(s for s in summary['seeds'] if s['seed'] == 1234)
    image = Image.new('RGB', (1440, 680), '#11212a')
    draw = ImageDraw.Draw(image)
    font = lambda size: ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf', size)
    draw.text((30, 20), 'Iron deposits — same seed, same Y48 section', font=font(29), fill='#edf3ed')
    draw.text((30, 61), 'Seed 1234 · 64 × 64 block section · 64³ crop measurements · prototype only', font=font(18), fill='#b4c5c9')
    titles = ['Current', 'Finer shared field', 'Separate metal fields']
    for i, variant in enumerate(summary['variants']):
        x = 30 + i * 475
        raw = (OUT / f'1234_{variant}.bin').read_bytes()
        array = np.frombuffer(raw, dtype=np.uint8).reshape(64,64,64)[36]
        colors = np.zeros((64,64,3), dtype=np.uint8)
        colors[:] = (39, 59, 68)
        colors[array == 3] = (218, 167, 82)
        blockmap = Image.fromarray(colors).resize((416,416), resample=Image.Resampling.NEAREST)
        draw.text((x, 104), titles[i], font=font(23), fill='#edf3ed')
        image.paste(blockmap, (x, 147))
        metric = seed['metrics'][variant][2]
        largest = metric['largest']
        draw.text((x, 580), f"{metric['count']:,} iron blocks in crop", font=font(20), fill='#edf3ed')
        draw.text((x, 612), f"Largest body: {'≥ ' if largest['clipped'] else ''}{largest['size']:,} blocks", font=font(18), fill='#b4c5c9')
    draw.text((30, 652), 'Gold marks iron. Other cells omitted. ≥ means the deposit continues beyond the crop.', font=font(16), fill='#b4c5c9')
    image.save(OUT / 'iron_comparison.png')
    print(args.fragment, len(fragment.encode()), 'bytes')


if __name__ == '__main__':
    main()
