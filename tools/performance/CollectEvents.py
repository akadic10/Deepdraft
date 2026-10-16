"""Collect completed event-hitch experiments; never launches or changes a game."""
from pathlib import Path
import gzip
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/00_dev_roadmap/concepts/events_20261015'
TMP = ROOT / 'tmp/events_20261015'
LABELS = ['events_pipeline_trace_30', 'events_pipeline_after_30',
          'events_before_30', 'events_after_30',
          'events_long_5', 'events_long_20', 'events_long_30']


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def copy(path, name):
    if path.is_file():
        shutil.copy2(path, OUT / name)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    comparisons = {}
    for label in LABELS:
        source = ROOT / 'tmp/performance_20261014' / label
        if not (source / 'report.json').exists():
            continue
        report = read(source / 'report.json')
        comparisons[label] = report.get('long_session', report['phases'])
        for path in source.iterdir():
            if not path.is_file():
                continue
            if path.name.endswith('_frames.json') or path.name in ['lifecycle.json', 'session.json']:
                with gzip.open(OUT / f'{label}_{path.name}.gz', 'wb') as stream:
                    stream.write(path.read_bytes())
            elif path.name in ['report.json', 'run.json', 'run.out', 'run.err', 'colony.png']:
                copy(path, f'{label}_{path.name}')
    (OUT / 'comparison.json').write_text(json.dumps(comparisons, indent=2), encoding='utf-8')
    for folder in ['regressions', 'native_tests', 'packed']:
        for path in (TMP / folder).glob('*'):
            if path.is_file():
                copy(path, f'{folder}_{path.name}')
    for path in TMP.glob('*.ps1'):
        copy(path, path.name + '.txt')
    copy(TMP / 'export_summary.txt', 'export_summary.txt')
    sources = ['scripts/components/WorkDustBurst.gd', 'scripts/systems/WorkFeedback.gd',
               'scripts/components/UndergroundLighting.gd', 'scripts/tests/WorkDustReuseTest.gd',
               'tools/performance/FrameLifecycleProbe.gd', 'tools/performance/EventSpikeBenchmark.gd',
               'tools/performance/LongSessionBenchmark.gd', 'tools/performance/CameraBenchmark.gd']
    audit = {'source_sha256': {name: sha(ROOT / name) for name in sources},
             'input_save_sha256': sha(TMP / 'input_quicksave.json'),
             'original_save_sha256': sha(Path('C:/Users/akadi/AppData/Roaming/Godot/app_userdata/Deepdraft/saves/quicksave.json'))}
    if (TMP / 'packed/release_startup.json').exists():
        audit['package'] = read(TMP / 'packed/release_startup.json')['package']
        archive = ROOT / 'build/windows/Deepdraft-Windows-Playtest.zip'
        audit['zip_sha256'] = sha(archive)
        audit['zip_bytes'] = archive.stat().st_size
    (OUT / 'audit.json').write_text(json.dumps(audit, indent=2), encoding='utf-8')
    print(json.dumps(audit, indent=2))


if __name__ == '__main__':
    main()
