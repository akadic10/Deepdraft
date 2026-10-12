import json
from pathlib import Path
root = Path('P:/Deepdraft')
def edit(path, fn):
    p=root/path
    obj=json.loads(p.read_text(encoding='utf-8-sig'))
    fn(obj)
    p.write_text(json.dumps(obj,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
edit('data/tasks/task_config.json',lambda d:d['mood'].update(thermal={'minimum_sleep_hours':1.0,'duration_hours':24.0,'cold_penalty':0.20,'chilly_penalty':0.05,'hot_penalty':0.15}))
for key,units in [('hearth',2400),('brazier',3200),('campfire',900),('wooden_torch',75),('wall_torch',100)]:
    def change(d):
        d['heat_source']['heat_units']=units
        if key=='hearth':
            d['display_name']='Stone hearth'
            d['description']='A stone fire bowl filled with burning timber. Warms a small bedroom; larger halls need more heat.'
            d['__comment']=[s.replace('400 units','2400 units') for s in d['__comment']]
    edit('data/furniture/'+key+'.json',change)
def recipes(d):
    d['recipes'].insert(5,{'id':'base:recipe:worker:hearth','name':'Stone hearth','output_plural':'hearths','description':'A stone fire bowl for warm starter bedrooms. Two matching logs and four rough stones.','purpose':'Warms a small sealed bedroom. Always lit when installed; no fuel upkeep yet.','category':'Camp furnishings','ingredient_tag':'timber','default_ingredients':['base:resources:wood:pine_log'],'ingredient_count':2,'additional_ingredients':['base:resources:stone:rough_stone']*4,'work_seconds':18.0,'workshop':'base:furniture:crude_workbench','output':'base:resources:furniture:hearth','output_count':1,'furniture':'base:furniture:hearth'})
edit('data/workshops/worker_crafting.json',recipes)
edit('data/entities/items/resources.json',lambda d:d['base:resources:furniture:hearth'].update(display_name='Stone hearth (packed)',description='A packed stone fire bowl, ready to warm a small bedroom.'))
# Keep developer inspection consistent with the player-facing temperature card.
p=root/'scripts/systems/WorldRenderer.gd'
s=p.read_text(encoding='utf-8').replace('float(heat_units) / float(max(volume, 1))','float(room.get("heat_bonus_c",0))').replace('_room_zone_name(mean_floor_y)','RoomManager.comfort_label(temp_c)')
a=s.index('## Depth-zone label from mean floor Y')
b=s.index('func set_visual_cut_blocks',a)
s=s[:a]+s[b:]
p.write_text(s,encoding='utf-8')
