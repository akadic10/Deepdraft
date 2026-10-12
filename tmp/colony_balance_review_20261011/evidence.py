from pathlib import Path
import json
root=Path('P:/Deepdraft')
p=root/'tmp/colony_balance_review_20261011'
save=json.loads((p/'player_quicksave.json').read_text())
(root/'scripts/tests/fixtures/starter_excavation.json').write_text(json.dumps({'seed':save['world_seed'],'cells':save['scene']['mining']['mined_blocks']},separators=(',',':'))+'\n')
report=json.loads((p/'resource_progression.json').read_text())
counts=[0]*4
totals=[0]*4
for seed in report['seeds']:
    for i in range(4):
        totals[i]+=seed['solid_samples_by_stage'][i]
        counts[i]+=sum(seed['resources_by_stage'][i].values())
print(json.dumps({'sampled_solids':sum(totals),'counts':counts,'stage_totals':totals,'saved_excavation':report['seeds'][0]['saved_excavation'],'map_ms':[s['map_ms'] for s in report['seeds']],'starter_tunnels':[s['starter_tunnel']['counts'] for s in report['seeds']]},indent=2))
