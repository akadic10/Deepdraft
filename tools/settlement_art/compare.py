"""Summarize sequential native runs without confusing art cost with simulation drift."""
import argparse
import json
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def summarize(labels):
    reports = []
    for label in labels:
        folder = ROOT / 'tmp/settlement_art_20261013' / label
        report = json.loads((folder / 'report.json').read_text())
        errors = (folder / 'run.err').read_text()
        assert not report['failures'], (label, report['failures'])
        assert 'SCRIPT ERROR:' not in errors and 'ERROR:' not in errors, label
        assert not report['quick'], 'Setup probes are not full measurements'
        report['label'] = label
        reports.append(report)
    current = [r for r in reports if not r['pilot']]
    pilot = [r for r in reports if r['pilot']]
    assert current and pilot
    baseline = current[0]
    for report in reports:
        for key in ['resolution', 'world_fingerprints', 'detail_identity_sha256', 'fixture_sha256',
                    'shader_uniform_buffer_slots', 'fixed_simulation_fps']:
            assert report[key] == baseline[key], (report['label'], 'mismatched '+key)
        for name in baseline['captures']:
            for key in ['camera_position', 'camera_rotation', 'camera_size', 'slice_y', 'sample_frames', 'warmup_frames']:
                assert report['captures'][name][key] == baseline['captures'][name][key], (report['label'], name, key)
            if not baseline['captures'][name]['active']:
                assert report['captures'][name]['draws'] == baseline['captures'][name]['draws'], (report['label'], name, 'draws')

    views = {}
    for name in baseline['captures']:
        row = {'active': baseline['captures'][name]['active']}
        for field in ['frame_ms', 'gpu_ms', 'render_cpu_ms', 'scene_process_ms']:
            row[field] = {}
            for pct in ['p50', 'p95', 'p99', 'max']:
                old = [r['captures'][name][field][pct] for r in current]
                new = [r['captures'][name][field][pct] for r in pilot]
                row[field][pct] = {
                    'current': statistics.median(old), 'pilot': statistics.median(new),
                    'delta': statistics.median(new)-statistics.median(old),
                    'current_runs': old, 'pilot_runs': new}
        for field in ['draws', 'primitives', 'static_memory_bytes', 'video_memory_bytes']:
            old = [r['captures'][name][field] for r in current]
            new = [r['captures'][name][field] for r in pilot]
            row[field] = {'current': statistics.median(old), 'pilot': statistics.median(new),
                          'delta': statistics.median(new)-statistics.median(old)}
        views[name] = row

    return {
        'conditions': {k: baseline[k] for k in ['seed', 'resolution', 'cpu', 'adapter',
                      'shader_uniform_buffer_slots', 'fixed_simulation_fps', 'fixture_sha256',
                      'world_fingerprints', 'detail_identity_sha256']},
        'counts': baseline['fixture']['counts'],
        'labels': labels, 'views': views,
        'runs': [{k: r.get(k) for k in ['label', 'pilot', 'completed_tasks', 'stored_stacks',
                 'behavior_observations', 'final_counts', 'slice_transitions', 'terrain_edits',
                 'save_written', 'save_reload']} for r in reports],
        'limits': [
            'Fixed simulation delta at 60 Hz; rendering is uncapped. Frame values are measured wall time, not 60 FPS assertions.',
            'Samples use the full production scene and unchanged scheduler/AI. Wall-clock budgets and asynchronous jobs can diverge after identical starting states.',
            'Paused comparisons isolate model/rendering cost; active draws and primitive counts can differ with actor motion.',
            'All variants use the corrected shader uniform capacity. The failing default-capacity probe is excluded.',
            'Medians summarize per-run percentiles, not pooled frame samples. Original sample arrays are retained.',
            'One CPU/GPU configuration; no minimum hardware or shipping performance target is established.'
        ]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('labels', nargs='+')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = summarize(args.labels)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2)+'\n')
    for name, row in result['views'].items():
        gpu = row['gpu_ms']['p50']
        frame = row['frame_ms']['p95']
        print(f"{name:22} GPU {gpu['current']:.3f} -> {gpu['pilot']:.3f} ms; "
              f"frame p95 {frame['current']:.3f} -> {frame['pilot']:.3f} ms")
    print('Matched starting state, terrain, camera routes and sample settings verified.')


if __name__ == '__main__':
    main()
