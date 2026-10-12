import json,re
from pathlib import Path
p=Path('P:/Deepdraft/data/terrain/block_resources.json')
s=p.read_text(encoding='utf-8')
# Minimum original rock shell, maximum map Y (precious descent), field size/cutoff.
profiles={
'coal':(2,120,.045,.73), 'copper':(2,120,.075,.735),
'tin':(10,100,.08,.755), 'iron':(14,100,.09,.775),
'silver':(24,65,.095,.83), 'gold':(28,32,.10,.85),
'jade':(20,85,None,.83), 'amethyst':(20,75,None,.845),
'ruby':(32,24,None,.88), 'sapphire':(32,24,None,.89),
'emerald':(40,16,None,.90), 'diamond':(40,12,None,.91)}
for name,(burial,max_y,freq,threshold) in profiles.items():
    channel='ore' if freq else 'gem'
    key=f'base:terrain:{channel}:{name}'
    match=re.search('"'+re.escape(key)+'"\\s*:\\s*',s)
    start=match.end()
    d,length=json.JSONDecoder().raw_decode(s[start:])
    d['min_burial']=burial
    d['depth_bias']={'min_y':4,'max_y':max_y}
    d['noise_threshold']=threshold
    if name in ['coal','copper']: d['shallow_noise_threshold']=.80
    if freq:
        d['noise_field']['frequency']=freq
        d['drops'][0]['count']=1
        d['drops'][0]['chance']=.4
    replacement=json.dumps(d,indent=2,ensure_ascii=False).replace('\n','\n  ')
    s=s[:start]+replacement+s[start+length:]
if '"  min_burial' not in s:
    s=s.replace('    "  depth_bias      - optional { min_y, max_y } inclusive generation window",','    "  depth_bias      - optional { min_y, max_y } inclusive generation window",\n    "  min_burial      - original rock shell on all sides, including cliff faces",')
p.write_text(s,encoding='utf-8')
