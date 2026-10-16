"""Summarize the recorded frame intervals, event windows and colony progress."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/00_dev_roadmap/concepts/events_20261015'


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def stats(values):
    values = sorted(values)
    if not values:
        return {}
    n = len(values)
    return {'frames': n, 'mean': sum(values) / n, 'p95': values[int((n-1)*.95)],
            'p99': values[int((n-1)*.99)], 'max': values[-1],
            'over_33': sum(x > 1000/30 for x in values),
            'over_50': sum(x > 50 for x in values),
            'over_100': sum(x > 100 for x in values)}


def main():
    result = {}
    for population in [5, 20, 30]:
        folder = ROOT / f'tmp/performance_20261014/events_long_{population}'
        if not (folder / 'session.json').exists():
            continue
        session = read(folder / 'session.json')
        flat = read(folder / 'session_frames.json')
        rows = [flat[i:i+7] for i in range(0, len(flat), 7)]
        initial, final = session['initial'], session['final']
        intervals = {}
        for name, start, end in [('first_30_seconds', 0, 30), ('explicit_save', 30, 33),
                                 ('day_boundary', 60, 65), ('arrivals', 90, 100),
                                 ('season_change', 150, 180), ('later_steady', 180, 210),
                                 ('natural_autosave', 300, 330)]:
            intervals[name] = stats([x[1] for x in rows if start <= x[0] < end])
        result[str(population)] = {
            'duration_seconds': session['duration_seconds'], 'frame_ms': stats([x[1] for x in rows]),
            'intervals': intervals, 'events': session['events'],
            'progress': {key: final[key]-initial[key] for key in ['mined', 'built', 'stored', 'loose', 'wildlife']},
            'initial': initial, 'final': final,
            'window_frame_means': [w['frames']['mean'] for w in session['windows']],
            'window_frame_p95': [w['frames']['p95'] for w in session['windows']],
            'window_nodes': [w['state']['nodes'] for w in session['windows']],
            'window_resources': [w['state']['resources'] for w in session['windows']],
            'window_memory_mb': [w['state']['static_memory_mb'] for w in session['windows']],
            'auto_count': session['auto_count'], 'failures': session['failures'],
            'lifecycle_errors': session['lifecycle_errors'],
        }
        print(population, 'frames', result[str(population)]['frame_ms'],
              'progress', result[str(population)]['progress'])
        print('event peaks', {k: round(v.get('max', 0), 3) for k, v in intervals.items()})
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'long_session_summary.json').write_text(json.dumps(result, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
