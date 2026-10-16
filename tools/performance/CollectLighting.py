"""Preserve the October 15 lighting comparison and its validation evidence.

Run after the named benchmarks and checks have finished. No game is launched.
"""
from pathlib import Path
import datetime
import gzip
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/00_dev_roadmap/concepts/lighting_20261015'
TMP = ROOT / 'tmp/lighting_20261015'
RUNS = ['lighting_20261015_before_30', 'lighting_20261015_trace_30',
        'lighting_20261015_after_30', 'lighting_20261015_saved_before',
        'lighting_20261015_saved_after']


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def copy(source, name):
    if source.is_file():
        shutil.copy2(source, OUT / name)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    comparison = {}
    for label in RUNS:
        source = ROOT / 'tmp/performance_20261014' / label
        report = read(source / 'report.json')
        comparison[label] = {'diagnostic_only': 'trace' in label,
                             'counts': report['counts'], 'phases': {}}
        for phase, row in report['phases'].items():
            comparison[label]['phases'][phase] = {
                'frame_ms': row['frame_ms'],
                'lighting_ms': row['process']['DebugWorld/Renderer/UndergroundLighting'],
                **{k: v for k, v in row.items() if k.startswith('work') or k.startswith('assignment') or k.startswith('first_assignment')},
            }
        for path in source.iterdir():
            if path.name.endswith('_frames.json'):
                with gzip.open(OUT / f'{label}_{path.name}.gz', 'wb') as stream:
                    stream.write(path.read_bytes())
            elif path.name in ['report.json', 'run.json', 'run.out', 'run.err', 'colony.png']:
                copy(path, f'{label}_{path.name}')
    (OUT / 'comparison.json').write_text(json.dumps(comparison, indent=2), encoding='utf-8')
    copy(TMP / 'disposal.json', 'disposal.json')
    for folder in ['disposal', 'regressions', 'native_tests', 'packed']:
        for path in (TMP / folder).glob('*'):
            if path.is_file():
                copy(path, f'{folder}_{path.name}')
    native = {
        'underground': ROOT / 'tmp/underground_lighting_review/entrance_fix',
        'door': ROOT / 'tmp/door_lighting_20261011',
        'limb': ROOT / 'tmp/dwarf_limb_lighting_20261013',
        'room': TMP / 'native_tests/RoomLightingTest',
        'bedroom': ROOT / 'tmp/personal_bedroom_20261011',
    }
    # These fixtures write into historic fixed paths. Only retain today's outputs.
    for label, source in native.items():
        for path in source.glob('*'):
            if path.is_file() and path.suffix in ['.json', '.png']:
                if label == 'door' and path.suffix == '.png' and path.name not in {
                    '2_0_indoor.png', '2_0_outdoor.png', '3_1_open_1_90.png',
                    '4_2_indoor.png', 'torchlit_inside.png',
                }:
                    continue
                if datetime.datetime.fromtimestamp(path.stat().st_mtime).date().isoformat() == '2026-10-15':
                    copy(path, f'native_{label}_{path.name}')
    for name in ['InstrumentLighting.py', 'RunTests.ps1', 'RunNativeTests.ps1', 'RunPacked.ps1', 'Export.ps1']:
        copy(TMP / name, name + '.txt')
    copy(TMP / 'export_summary.txt', 'export_summary.txt')
    sources = ['scripts/components/UndergroundLighting.gd',
               'scripts/tests/LightingBufferDisposalTest.gd',
               'tools/performance/CameraBenchmark.gd',
               'tools/performance/SmokeLightingExport.gd']
    audit = {'source_sha256': {name: sha(ROOT / name) for name in sources},
             'frozen_before_sha256': sha(OUT / 'UndergroundLighting.gd.before.txt'),
             'frozen_after_matches_production': sha(OUT / 'UndergroundLighting.gd.after.txt') == sha(ROOT / sources[0]),
             'copied_input_sha256': sha(TMP / 'input_quicksave.json')}
    original = Path('C:/Users/akadi/AppData/Roaming/Godot/app_userdata/Deepdraft/saves/quicksave.json')
    audit['original_save_sha256'] = sha(original)
    audit['original_save_matches_input'] = sha(original) == audit['copied_input_sha256']
    archive = ROOT / 'build/windows/Deepdraft-Windows-Playtest.zip'
    if (TMP / 'packed/release_startup.json').is_file():
        audit['package'] = read(TMP / 'packed/release_startup.json')['package']
        audit['zip_sha256'] = sha(archive)
        audit['zip_bytes'] = archive.stat().st_size
    (OUT / 'audit.json').write_text(json.dumps(audit, indent=2), encoding='utf-8')
    print(json.dumps(audit, indent=2))


if __name__ == '__main__':
    main()
