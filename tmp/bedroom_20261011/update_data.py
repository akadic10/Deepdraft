import json
from pathlib import Path

def update(path, apply):
    p=Path(path)
    data=json.loads(p.read_text(encoding='utf-8'))
    apply(data)
    p.write_text(json.dumps(data,ensure_ascii=True,indent=2)+'\n',encoding='utf-8')

def resources(data):
    data['base:resources:furniture:log_bed']={
        'display_name':'Log bed (packed)', 'description':'Pegged bed logs, straw ticking and a sack pillow packed in a carrying crate.',
        'model':'res://assets/models/items/furniture/packed_furniture.glb','stack_max':5,'carry_cost':4,
        'weight_class':'heavy','base_trade_value':12,'material_tags':['wood','furniture','stockpile_furniture'],
        'material_group':'wood','appeal':{'design':3,'material_factor':1}}

def recipes(data):
    data['recipes'].append({'id':'base:recipe:worker:log_bed','name':'Log bed','output_plural':'log beds',
        'description':'Peg rough logs into a bed with bundled straw bedding. A simple place for one dwarf to sleep.',
        'purpose':'Dwarves prefer a free bed over the ground. A bed, door, light and sealed enclosure make a bedroom.',
        'category':'Camp furnishings','ingredient_tag':'timber','default_ingredients':['base:resources:wood:pine_log'],
        'ingredient_count':1,'work_seconds':16.0,'workshop':'base:furniture:crude_workbench',
        'output':'base:resources:furniture:log_bed','output_count':1,'furniture':'base:furniture:log_bed','material_group':'wood'})

update('data/entities/items/resources.json',resources)
update('data/workshops/worker_crafting.json',recipes)
update('data/ui/place_catalog.json',lambda d:d['items'].append({'key':'base:furniture:log_bed','category':'rooms','label':'Log bed'}))
update('data/furniture/dwarf_bunk.json',lambda d:d.update(sleep_surface={'height':1.0,'facing_steps':1,'forward_offset':-.15}))
for name in ['wooden_torch','wall_torch','campfire']:
    update(f'data/furniture/{name}.json',lambda d:d['light_source'].update(energy=d['light_source']['energy']*2))
update('data/tasks/task_config.json',lambda d:d['rest'].update(bed_search_radius=48,bed_path_attempts_per_tick=1))
