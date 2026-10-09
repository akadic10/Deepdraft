from pathlib import Path
import json

ROOT = Path('P:/Deepdraft')
def replace(path, old, new):
    p = ROOT / path
    s = p.read_text(encoding='utf-8')
    assert old in s, (path, old)
    p.write_text(s.replace(old, new), encoding='utf-8')

for path in ['scripts/entities/DwarfAgent.gd', 'scripts/systems/TaskManager.gd']:
    replace(path, 'Task.Type.UPROOT_SHRUB]', 'Task.Type.UPROOT_SHRUB, Task.Type.HARVEST_TREE]')
replace('scripts/systems/Task.gd', 'CLEAR_PLANT, UPROOT_SHRUB }', 'CLEAR_PLANT, UPROOT_SHRUB, HARVEST_TREE }')
replace('scripts/systems/Task.gd', '\treturn "UNKNOWN"', '\t\tType.HARVEST_TREE: return "HARVEST_TREE"\n\treturn "UNKNOWN"')
replace('data/tasks/task_config.json', '"UPROOT_SHRUB": 50', '"UPROOT_SHRUB": 50,\n    "HARVEST_TREE": 50')
replace('scripts/systems/SurfaceFloraSpawner.gd', 'Pick once per autumn; the tree stays standing.', 'Pick once per harvest season; the tree stays standing.')

p = ROOT/'data/entities/flora/juniper_tree.json'
data = json.loads(p.read_text(encoding='utf-8'))
data['__comment'].insert(2, 'Mature/ancient trees yield 2/4 berries once each autumn through non-destructive worker harvesting. Felling yields wood and seeds only.')
for stage, count in [('mature', 2), ('ancient', 4)]:
    d = data['base:flora:juniper_tree']['stages'][stage]
    d['harvest']['yields'] = [y for y in d['harvest']['yields'] if not y['item'].endswith(':juniper_berry')]
    d['fruit_harvest'] = {'harvest_season':'autumn', 'work_seconds':3.0, 'yield_item':'base:resources:flora:juniper_berry', 'yield_count':count, 'post_harvest':'persist'}
    d['picked_models'] = {season:[path.replace('.glb', '_picked.glb') for path in paths] for season, paths in d['models'].items()}
p.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')
