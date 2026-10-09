"""Summarize matched native runs and the real-layout census; never tune live data."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'tmp/surface_review'
SEEDS = (7, 17, 1234, 20261007)


def read(path):
    return json.loads(path.read_text())


def main():
    layout = read(OUT/'layout_report.json')
    assert not layout['failures'], layout['failures']
    pairs = []
    views = []
    seasons = []
    for seed in SEEDS:
        enabled = read(OUT/str(seed)/'details_report.json')
        disabled = read(OUT/str(seed)/'baseline_report.json')
        assert not enabled['failures'] and not disabled['failures']
        assert enabled['census']['targets'] == disabled['census']['targets']
        assert not disabled['diagnostics']['categories']
        assert enabled['saved_changes_after_viewing'] == 0
        for name in list(enabled['views']) + ['pan_zoom']:
            d = enabled['pan_zoom'] if name == 'pan_zoom' else enabled['views'][name]
            b = disabled['pan_zoom'] if name == 'pan_zoom' else disabled['views'][name]
            assert d['process_frames'] == d['frames'] and b['process_frames'] == b['frames']
            assert d['median_render_gpu_ms'] > 0 and b['median_render_gpu_ms'] > 0
            views.append({'seed':seed,'view':name,
                'gpu_off_ms':b['median_render_gpu_ms'],'gpu_on_ms':d['median_render_gpu_ms'],
                'gpu_delta_ms':d['median_render_gpu_ms']-b['median_render_gpu_ms'],
                'calls_off':b['draw_calls'],'calls_on':d['draw_calls'],
                'p95_off_ms':b['p95_frame_ms'],'p95_on_ms':d['p95_frame_ms']})
        d, b = enabled['views']['wide'], disabled['views']['wide']
        pairs.append({'seed':seed,'layout_ms':enabled['diagnostics']['layout_ms'],
            'ready_off_ms':disabled['ready_ms'],'ready_on_ms':enabled['ready_ms'],
            'clumps':enabled['diagnostics']['accepted'],'extra_nodes':d['scene_nodes']-b['scene_nodes'],
            'static_delta_mib':(d['static_memory_bytes']-b['static_memory_bytes'])/1048576,
            'video_delta_mib':(d['video_memory_bytes']-b['video_memory_bytes'])/1048576})
        for season in enabled['season_changes']:
            d,b=enabled['season_changes'][season],disabled['season_changes'][season]
            seasons.append({'seed':seed,'season':season,'settle_off_ms':b['settle_ms'],'settle_on_ms':d['settle_ms'],
                'max_frame_off_ms':b['max_frame_ms'],'max_frame_on_ms':d['max_frame_ms'],
                'sync_off_ms':b['synchronous_ms'],'sync_on_ms':d['synchronous_ms']})
    summary = {'pairs':pairs,'views':views,'seasons':seasons}
    (OUT/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    lines=['| Seed | Boulders | Scree | Shrubs | Flowers | Reeds | Support coverage | Max clumps / 64×64 |',
        '|---|---:|---:|---:|---:|---:|---:|---:|']
    for r in layout['seeds']:
        c=r['categories']; s=r['census']
        shrubs=sum(c.get(k,0) for k in ('blueberry','elderberry','wild_strawberry'))
        lines.append(f"| {r['seed']} | {c['boulder']} | {c['scree']} | {shrubs} | {c['flowers']} | {c.get('reeds',0)} | {s['support_percent_map']:.3f}% | {s['regions64']['max_clumps']} |")
    lines += ['','| Seed | Layout, ms | Ready without / with, s | Extra nodes | Static / renderer memory delta, MiB |',
        '|---|---:|---:|---:|---:|']
    for r in pairs:
        lines.append(f"| {r['seed']} | {r['layout_ms']:.1f} | {r['ready_off_ms']/1000:.2f} / {r['ready_on_ms']/1000:.2f} | {r['extra_nodes']:.0f} | {r['static_delta_mib']:.1f} / {r['video_delta_mib']:.1f} |")
    lines += ['','| Seed / view | GPU median without / with, ms | Draw calls without / with | Frame P95 without / with, ms |',
        '|---|---:|---:|---:|']
    for r in views:
        if r['view'] not in ('dense','wide','pan_zoom'): continue
        lines.append(f"| {r['seed']} / {r['view']} | {r['gpu_off_ms']:.3f} / {r['gpu_on_ms']:.3f} | {r['calls_off']:.1f} / {r['calls_on']:.1f} | {r['p95_off_ms']:.3f} / {r['p95_on_ms']:.3f} |")
    (OUT/'tables.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print(json.dumps({'native_pairs':len(pairs),'camera_pairs':len(views),
        'gpu_delta_ms_range':[min(v['gpu_delta_ms'] for v in views),max(v['gpu_delta_ms'] for v in views)],
        'max_season_frame_without_ms':max(s['max_frame_off_ms'] for s in seasons),
        'max_season_frame_with_ms':max(s['max_frame_on_ms'] for s in seasons)}))


if __name__ == '__main__':
    main()
