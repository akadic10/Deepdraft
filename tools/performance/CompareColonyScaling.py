"""Summarize all measured scaling cases, retaining hitches and work progress."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/00_dev_roadmap/concepts/colony_scaling_20261014'

def run():
    OUT.mkdir(parents=True,exist_ok=True)
    result={}
    for version in ['before','after']:
        for count in [5,20,50,100]:
            label=f'colony_v2_{version}_{count}'
            folder=ROOT/'tmp/performance_20261014'/label
            if not (folder/'run.json').exists(): continue
            meta=json.loads((folder/'run.json').read_text(encoding='utf-8-sig'))
            if meta['exit_code'] or meta['errors']: continue
            report=json.loads((folder/'report.json').read_text())
            (OUT/(label+'_report.json')).write_text(json.dumps(report,indent=2),encoding='utf-8')
            (OUT/(label+'_run.json')).write_text(json.dumps(meta,indent=2),encoding='utf-8')
            phases={}
            for phase,data in report['phases'].items():
                pro=data['process']
                rows=json.loads((folder/(phase+'_frames.json')).read_text())
                kept=[]
                keys=['Dwarves','TaskManager','DebugWorld/Renderer','DebugWorld/WildlifeManager','WaterManager','DebugWorld/Renderer/UndergroundLighting']
                for row in rows:
                    kept.append(dict(frame_ms=row['frame_ms'],scene_ms=row['scene_ms'],process={k:row['process'].get(k,0) for k in keys}))
                if phase.startswith('active'):
                    (OUT/(label+'_'+phase+'.json')).write_text(json.dumps(kept,separators=(',',':')),encoding='utf-8')
                phases[phase]=dict(frame=data['frame_ms'],gpu=data['gpu_ms'],seconds=data['seconds'],frames=data['frames'],
                    processes={k:pro.get(k) for k in keys},work_before=data['work_before'],work_after=data['work_after'],
                    worker_samples=data['worker_samples'],worker_sample_frames=data['worker_sample_frames'],
                    worst=sorted(kept,key=lambda r:r['frame_ms'],reverse=True)[:3])
                print(label,phase,'frame',round(data['frame_ms']['mean'],2),'P95',round(data['frame_ms']['p95'],2),
                    'dwarves',round(pro['Dwarves']['mean'],3),'tasks',round(pro['TaskManager']['mean'],3),
                    'renderer',round(pro['DebugWorld/Renderer']['mean'],3),'work',data['work_after']['mined'],data['work_after']['built'],data['work_after']['stored'])
            result[label]=phases
    (OUT/'comparison.json').write_text(json.dumps(result,indent=2),encoding='utf-8')

if __name__=='__main__': run()
