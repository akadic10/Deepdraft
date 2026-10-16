"""Retain arrival performance evidence without player profiles."""
import pathlib,json,hashlib,shutil
ROOT=pathlib.Path(__file__).resolve().parents[2]
DEST=ROOT/'docs/00_dev_roadmap/concepts/arrivals_20261015'
SCRATCH=ROOT/'tmp/arrivals_20261015'
def copy(src,dst):
    if src.is_file(): dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,dst)
labels=[f'arrivals_profile_before_{n}' for n in [5,20,30]]+['arrivals_after_trial_30']+[f'arrivals_after_{n}' for n in [5,20,30]]
summary=[]
for label in labels:
    src=ROOT/'tmp/performance_20261014'/label
    for name in ['arrivals.json','arrival_frames.json','report.json','run.out','run.err','run.json']: copy(src/name,DEST/label/name)
    if not (src/'arrivals.json').exists(): continue
    d=json.loads((src/'arrivals.json').read_text(encoding='utf-8'))
    summary.append({k:d[k] for k in ['population','seconds','frames','event_cpu','events']}|{'label':label,'progress':{k:d['final'][k]-d['initial'][k] for k in ['mined','built','stored','wildlife']}})
(DEST/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
for label in ['initial','differential','differential_v2','differential_v3','final_regressions','packed']:
    for src in (SCRATCH/label).glob('*'):
        if src.suffix in ['.out','.err','.json','.png']: copy(src,DEST/label/src.name)
for name in ['RunTests.ps1','RunPacked.ps1','Export.ps1','export_summary.txt','package_audit.json','before_hashes.json']: copy(SCRATCH/name,DEST/name)
paths=['scripts/systems/WorldEventDirector.gd','scripts/systems/WildlifeManager.gd','scripts/components/DuckPopulation.gd','scripts/components/DuckNavigation.gd','scripts/components/DuckArrivalPreparation.gd','scripts/components/EdgeArrivalPlanner.gd','scripts/tests/ArrivalPreparationTest.gd','tools/performance/ArrivalBenchmark.gd','tools/performance/SmokeArrivalExport.gd','scripts/systems/SaveManager.gd','scripts/components/UndergroundLighting.gd','scripts/components/WorkDustBurst.gd','scripts/systems/WorkFeedback.gd']
manifest={}
for name in paths:
    src=ROOT/name; manifest[name]=hashlib.sha256(src.read_bytes()).hexdigest()
    copy(src,DEST/'final_sources'/(src.name+'.txt'))
(DEST/'source_hashes.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('Collected',len(summary),'arrival runs')
