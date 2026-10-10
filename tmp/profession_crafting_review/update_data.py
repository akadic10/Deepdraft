import json
from pathlib import Path
root = Path('P:/Deepdraft')
def read(name): return json.loads((root/name).read_text(encoding='utf-8-sig'))
def save(name, value): (root/name).write_text(json.dumps(value,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
data=read('data/workshops/worker_crafting.json')
sections=[dict(id='rudimentary',name='Rudimentary',planned=False,hint='Simple goods and starter tools, made by Workers at the crude workbench.')]
for key,name,desc,preview,req,hint in [
 ('carpenter','Carpenter','Refined wooden furniture, storage and workshop fittings.',['Furniture','Storage','Workshop fittings'],'Entry tool: crude carpentry kit. A forged saw comes later.','The crude carpentry kit is available under Rudimentary → Starter tools.'),
 ('stonemason','Stonemason',"Shaped stone furnishings and the colony's first substantial stonework.",['Stone furnishings','Building materials','Workshop stonework'],'Specialist recipes, workshop and promotion requirements are still being designed.','Stonemason production is planned.'),
 ('blacksmith','Blacksmith','Refine metal and forge better tools, fittings and workshop equipment.',['Metal refining','Tool upgrades','Metal fittings'],'Entry tool: stone hammer. Iron pickaxes and carpenter saws are future upgrades.','The stone hammer is available under Rudimentary → Starter tools.'),
 ('weaponsmith','Weaponsmith','A later Blacksmith specialization for military weapons.',['Melee weapons','Ranged weapons'],'Planned progression: experienced Blacksmith and a working forge.','Weapon recipes and crafting are planned.'),
 ('armorsmith','Armorsmith','A later Blacksmith specialization for protective equipment.',['Armor','Shields'],'Planned progression: experienced Blacksmith and a working forge.','Armor recipes and crafting are planned.'),
 ('farmer','Farmer','Grow and harvest crops to supply food, drink and other professions.',['Fields and crops','Harvest supplies'],'Entry tool: stone hoe. Farming will use field work; its production controls are still planned.','The stone hoe is available under Rudimentary → Starter tools.'),
 ('hunter','Hunter','Hunt wildlife and supply the colony with food and animal materials.',['Hunting supplies','Animal materials'],'Entry weapon: hunting spear. Player hunting and processing are planned.','The hunting spear is available under Rudimentary → Starter tools.'),
 ('miner','Miner','Miners already specialize in excavation. Their equipment progression will be supplied by other crafts.',['Pickaxe progression','Mining equipment'],'Miner promotion uses the default pickaxe today. Iron and later metal upgrades will be made by smiths.','Miner is playable; this equipment section is a preview, with no Miner crafting recipes yet.'),
 ('brewer','Brewer','Turn farm harvests into drinks for the colony.',['Brewing','Aging'],'Brewing recipes, ingredients and production controls are planned.','Farming and brewing production will be added in later milestones.')]:
 sections.append(dict(id=key,name=name,planned=True,description=desc,preview=preview,requirements=req,hint=hint))
data['sections']=sections
new=[]
for kind,name,desc,purpose,seconds in [
 ('campfire','Campfire','A low ring of rough stones around split timber. Gives warm, flickering light once placed.','Always lit when installed. No fuel upkeep yet.',10),
 ('log_chair','Log chair','A broad tree trunk hewn into a seat with a low back and rough arms. A simple place to rest between jobs.','Idle dwarves can sit here and return to work when needed.',8)]:
 recipe=dict(id='base:recipe:worker:'+kind,name=name,output_plural=name.lower()+'s',description=desc,purpose=purpose,category='Camp furnishings',ingredient_tag='timber',default_ingredients=['base:resources:wood:pine_log'],ingredient_count=1,work_seconds=seconds,workshop='base:furniture:crude_workbench',output='base:resources:furniture:'+kind,output_count=1,furniture='base:furniture:'+kind)
 if kind=='campfire': recipe['additional_ingredients']=['base:resources:stone:rough_stone']
 new.append(recipe)
data['recipes']=data['recipes'][:3]+new+data['recipes'][3:]
save('data/workshops/worker_crafting.json',data)
seat=read('data/furniture/wooden_chair.json')
for key in ['legacy_layouts','layout_version','__comment']: seat.pop(key,None)
seat.update(furniture_key='base:furniture:log_chair',item_key='base:resources:furniture:log_chair',display_name='Log Chair',description='A broad bark-covered log hewn into a low-backed chair. Idle dwarves can sit here between jobs.',model='res://assets/models/furniture/log_chair.glb')
save('data/furniture/log_chair.json',seat)
light=read('data/furniture/wooden_torch.json')['light_source']
light.update(position=[0,1.2,0],range=8.0,energy=1.6,emissive_mesh='campfire_flame')
light['flame_animation']['model']='res://assets/models/furniture/animations/campfire_flame.glb'
camp=dict(furniture_key='base:furniture:campfire',furniture_category='lighting',display_name='Campfire',description='A rough stone ring and split logs. Warm, animated light for the first camp; always lit while installed.',model='res://assets/models/furniture/campfire.glb',item_key='base:resources:furniture:campfire',placement='floor',yaw_steps=4,footprint=dict(width=2,depth=2),blocks_movement=True,collision_regions=[dict(min=[0,0,0],max=[2,1.5,2])],room_anchor=False,light_source=light,heat_source=dict(heat_units=200))
save('data/furniture/campfire.json',camp)
path=root/'data/entities/items/resources.json'
text=path.read_text(encoding='utf-8-sig')
entries={}
for kind,name,desc in [('campfire','Campfire','Unlit logs and rough stones packed for a campfire.'),('log_chair','Log Chair','One hewn log chair packed for installation.')]:
 entries['base:resources:furniture:'+kind]=dict(display_name=name+' (packed)',description=desc,model='res://assets/models/items/furniture/packed_furniture.glb',stack_max=5,carry_cost=4,weight_class='heavy',base_trade_value=4,material_tags=['wood','furniture','stockpile_furniture'])
at=text.rfind('}')
text=text[:at].rstrip()+',\n'+json.dumps(entries,indent=2)[2:-2]+'\n}\n'
json.loads(text)
path.write_text(text,encoding='utf-8')
