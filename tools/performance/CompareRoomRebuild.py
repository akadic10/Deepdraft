"""Summarize sequential CameraBenchmark captures without dropping outliers."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'docs/00_dev_roadmap/concepts/room_rebuild_20261014'
LABELS = ['room_before_saved', 'room_after_saved', 'room_before_natural', 'room_after_natural']

def stats(values):
    values = sorted(values)
    return dict(mean=sum(values)/len(values), p95=values[int((len(values)-1)*.95)],
                p99=values[int((len(values)-1)*.99)], max=values[-1])

def run():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    comparison = {}
    for label in LABELS:
        source = ROOT / 'tmp/performance_20261014' / label
        if not (source / 'report.json').exists(): continue
        report = json.loads((source / 'report.json').read_text(encoding='utf-8-sig'))
        (OUTPUT / (label + '_report.json')).write_text(json.dumps(report, indent=2), encoding='utf-8')
        (OUTPUT / (label + '_run.json')).write_bytes((source / 'run.json').read_bytes())
        comparison[label] = {}
        for phase in ['paused_pan', 'active_pan', 'active_pan_repeat']:
            rows = json.loads((source / (phase + '_frames.json')).read_text(encoding='utf-8-sig'))
            times = [r['process'].get('RoomManager', 0) for r in rows]
            worst = max(rows, key=lambda r:r['frame_ms'])
            summary = dict(room_process=stats(times), room_cpu_total_ms=sum(times),
                frame=report['phases'][phase]['frame_ms'],
                scheduled=report['phases'][phase]['scheduled_room_rebuilds'],
                worst_frame=dict(frame_ms=worst['frame_ms'], scene_ms=worst['scene_ms'],
                    stages=sorted(worst['process'].items(), key=lambda kv:kv[1], reverse=True)[:8]))
            jobs = []
            previous = -1
            for row in rows:
                state = row.get('rooms', {})
                if state.get('completed', 0) != previous:
                    previous = state.get('completed', 0)
                    if state: jobs.append(state)
            summary['completed_jobs'] = jobs
            comparison[label][phase] = summary
            keep = {'RoomManager','WaterManager','DebugWorld/Renderer','DebugWorld/WildlifeManager',
                    'DebugWorld/RoomOverlayController','MoistureRenderer',
                    'water_sim/total','water_sim/flow','water_render/total'}
            compact = []
            for row in rows:
                entry = {k:row[k] for k in ['frame_ms','scene_ms','gpu_ms','rooms'] if k in row}
                entry['process'] = {k:v for k,v in row['process'].items() if k in keep}
                compact.append(entry)
            (OUTPUT / (label + '_' + phase + '.json')).write_text(json.dumps(compact,separators=(',',':')), encoding='utf-8')
            print(label, phase, 'room max', round(max(times),3), 'frame', summary['frame'])
    (OUTPUT / 'comparison.json').write_text(json.dumps(comparison, indent=2), encoding='utf-8')

if __name__ == '__main__': run()
