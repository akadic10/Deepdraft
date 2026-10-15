"""Preserve sequential native wildlife timings, including all captured outliers."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'docs/00_dev_roadmap/concepts/duck_performance_20261014'
LABELS = ['duck_before_saved', 'duck_after_saved']

def run():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    comparison = {}
    for label in LABELS:
        source = ROOT / 'tmp/performance_20261014' / label
        report = json.loads((source / 'report.json').read_text(encoding='utf-8-sig'))
        (OUTPUT / (label + '_report.json')).write_text(json.dumps(report, indent=2), encoding='utf-8')
        (OUTPUT / (label + '_run.json')).write_bytes((source / 'run.json').read_bytes())
        comparison[label] = {}
        for phase, data in report['phases'].items():
            rows = json.loads((source / (phase + '_frames.json')).read_text(encoding='utf-8-sig'))
            worst = max(rows, key=lambda row: row['frame_ms'])
            processes = data['process']
            summary = dict(frame=data['frame_ms'],
                wildlife=processes.get('DebugWorld/WildlifeManager'),
                duck=processes.get('wildlife/base:animal:duck'),
                worst_frame=dict(frame_ms=worst['frame_ms'], scene_ms=worst['scene_ms'],
                    stages=sorted(worst['process'].items(), key=lambda kv: kv[1], reverse=True)[:8]))
            comparison[label][phase] = summary
            keep = {'DebugWorld/WildlifeManager', 'wildlife/base:animal:duck', 'wildlife/base:animal:deer', 'wildlife/base:animal:rabbit', 'wildlife/base:animal:wolf',
                    'WaterManager', 'DebugWorld/Renderer', 'RoomManager'}
            if phase.startswith('active'):
                compact = [dict(frame_ms=row['frame_ms'], scene_ms=row['scene_ms'],
                    process={k:v for k,v in row['process'].items() if k in keep}) for row in rows]
                (OUTPUT / (label + '_' + phase + '.json')).write_text(json.dumps(compact, separators=(',',':')), encoding='utf-8')
            print(label, phase, json.dumps(summary, separators=(',',':')))
    (OUTPUT / 'comparison.json').write_text(json.dumps(comparison, indent=2), encoding='utf-8')

if __name__ == '__main__':
    run()
