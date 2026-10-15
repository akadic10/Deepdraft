"""Compare periodic moisture stalls and complete native camera-pan frames."""
import argparse
import json
import shutil
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    for key in ('fresh_before', 'fresh_after', 'saved_before', 'saved_after', 'output'):
        parser.add_argument(key, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    results = {}
    for key in ('fresh_before', 'fresh_after', 'saved_before', 'saved_after'):
        folder = getattr(args, key)
        report = json.loads((folder / 'report.json').read_text())
        for name in ('report.json', 'run.json'):
            shutil.copyfile(folder / name, args.output / f'{folder.name}_{name}')
        results[key] = {}
        for phase in ('active_pan', 'active_pan_repeat'):
            data = report['phases'][phase]
            result = {field: data[field] for field in ('frames', 'seconds', 'frame_ms', 'process', 'draw_calls')}
            if key.startswith('fresh'):
                rows = json.loads((folder / f'{phase}_frames.json').read_text())
                ms = [r['process'].get('MoistureRenderer', 0) for r in rows]
                result['moisture_cpu_ms_per_second'] = sum(ms) / data['seconds']
                result['moisture_frames_over_16_7'] = sum(v > 1000/60 for v in ms)
                result['moisture_frames_over_33_3'] = sum(v > 1000/30 for v in ms)
                if 'moisture_mesh' in rows[-1]: result['moisture_mesh_end'] = rows[-1]['moisture_mesh']
            results[key][phase] = result
    (args.output / 'comparison.json').write_text(json.dumps(results, indent=2)+'\n')

    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    import numpy as np
    fig, axes = plt.subplots(1, 2, figsize=(11, 5.2))
    fig.suptitle('Damp ground no longer rebuilds in one burst', x=.07, ha='left', fontsize=16, weight='bold')
    fig.text(.07, .89, 'Native Godot · 2560×1440 · same moisture simulation and terrain appearance', color='#475569')
    for i, (suffix, color) in enumerate((('before', '#9b4a41'), ('after', '#247c9a'))):
        values = [results['fresh_'+suffix][p]['process']['MoistureRenderer']['max'] for p in ('active_pan', 'active_pan_repeat')]
        bars = axes[0].bar(np.arange(2)+(i-.5)*.34, values, .34, label=suffix.capitalize(), color=color)
        axes[0].bar_label(bars, fmt='%.1f', padding=3)
        values = [results[world+'_'+suffix][p]['frame_ms']['over_50'] for world in ('fresh', 'saved') for p in ('active_pan', 'active_pan_repeat')]
        bars = axes[1].bar(np.arange(4)+(i-.5)*.34, values, .34, label=suffix.capitalize(), color=color)
        axes[1].bar_label(bars, fmt='%.0f', padding=3)
    axes[0].set(xticks=[0, 1], xticklabels=['First pan', 'Later pan'], title='Worst moisture-rendering frame', ylabel='Time (ms)')
    axes[1].set(xticks=range(4), xticklabels=['Fresh\nfirst', 'Fresh\nlater', 'Saved\nfirst', 'Saved\nlater'], title='Frames above 50 ms during camera pan', ylabel='Frames per eight-second sample')
    axes[0].axhline(1000/60, color='#475569', linestyle='--', linewidth=1, label='60 FPS budget')
    for ax in axes:
        ax.grid(axis='y', alpha=.2)
        ax.set_axisbelow(True)
        ax.spines[['top', 'right']].set_visible(False)
        ax.set_ylim(0, ax.get_ylim()[1]*1.4)
        ax.legend(fontsize=9)
    fig.text(.07, .035, 'Eight-second samples; phases evolve the world. Fresh runs include process timers; saved runs do not.\nThe 1 ms moisture budget is soft: one small work batch or mesh upload can exceed it.', fontsize=9, color='#475569')
    fig.subplots_adjust(left=.07, right=.98, top=.79, bottom=.21, wspace=.24)
    for ext in ('png', 'svg'): fig.savefig(args.output / f'moisture_performance.{ext}', dpi=160)
    print(json.dumps({'output':str(args.output)}))


if __name__ == '__main__':
    main()
