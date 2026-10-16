"""Collect the autosave experiment without copying disposable player profiles."""
import hashlib, json, pathlib, shutil
ROOT=pathlib.Path(__file__).resolve().parents[2]
DEST=ROOT/'docs/00_dev_roadmap/concepts/autosave_20261015'
SCRATCH=ROOT/'tmp/autosave_20261015'
DEST.mkdir(parents=True,exist_ok=True)
labels=['autosave_before_5','autosave_before_20','autosave_profile_before_30',
        'autosave_after_trial_30','autosave_after_5','autosave_after_20','autosave_after_30',
        'autosave_before_repeat_30','autosave_after_repeat_30']
summary=[]
def copy(src,dst):
    if src.is_file():
        dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,dst)
for label in labels:
    src=ROOT/'tmp/performance_20261014'/label
    for name in ['autosave.json','autosave_frames.json','report.json','run.json','run.out','run.err']:
        copy(src/name,DEST/label/name)
    d=json.loads((src/'autosave.json').read_text(encoding='utf-8'))
    summary.append(dict(label=label,population=d['population'],frames=d['frames'],
        requests_ms=[s['request_ms'] for s in d['saves']],completions=d['completions'],
        progress={k:d['final'][k]-d['initial'][k] for k in ['mined','built','stored']},
        save_manager_sha256=d['save_manager_sha256'],validator_sha256=d['validator_sha256']))
(DEST/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
for label in ['initial_round_trip','worker_regression','worker_regression_v2','final_regressions','shutdown','packed']:
    for src in (SCRATCH/label).glob('*'):
        if src.suffix in ['.out','.err','.json','.png']: copy(src,DEST/label/src.name)
for name in ['RunTests.ps1','RunShutdown.ps1','RunPacked.ps1','Export.ps1','Repeat30.ps1','export_summary.txt','package_audit.json']:
    copy(SCRATCH/name,DEST/name)
paths=['scripts/systems/SaveManager.gd','scripts/components/SaveFileStore.gd',
       'scripts/components/SaveSnapshotPreparation.gd','scripts/components/SaveSnapshotValidator.gd',
       'scripts/systems/WaterManager.gd','scripts/systems/MiningDesignationController.gd',
       'scripts/systems/ItemDropManager.gd','scripts/tests/SaveWorkerChecks.gd',
       'scripts/tests/SaveWorkerShutdownTest.gd','tools/performance/AutosaveBenchmark.gd',
       'tools/performance/ProfileSaveManager.gd','tools/performance/SmokeAutosaveExport.gd',
       'scripts/components/UndergroundLighting.gd','scripts/components/WorkDustBurst.gd',
       'scripts/systems/WorkFeedback.gd']
manifest={}
for path in paths:
    src=ROOT/path; manifest[path]=hashlib.sha256(src.read_bytes()).hexdigest()
    copy(src,DEST/'final_sources'/(src.name+'.txt'))
(DEST/'source_hashes.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('Collected',len(summary),'runs at',DEST)
