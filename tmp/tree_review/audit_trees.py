import sys, json, importlib, hashlib
from pathlib import Path
from collections import deque
import numpy as np
from PIL import Image, ImageDraw, ImageFont
sys.dont_write_bytecode=True
ROOT=Path.cwd(); sys.path.insert(0,str(ROOT/'tools'))
from voxel_glb import mesh_from_voxels
from render_dwarf_redesign import glb
from render_dwarf_roster import assemble
OUT=ROOT/'tmp/tree_review'; OUT.mkdir(exist_ok=True)
D6=[(1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)]
D26=[(x,y,z) for x in (-1,0,1) for y in (-1,0,1) for z in (-1,0,1) if (x,y,z)!=(0,0,0)]

def components(cells, dirs):
    rest=set(cells); sizes=[]
    while rest:
        todo=[rest.pop()]; size=0
        while todo:
            x,y,z=todo.pop();size+=1
            for dx,dy,dz in dirs:
                q=x+dx,y+dy,z+dz
                if q in rest: rest.remove(q);todo.append(q)
        sizes.append(size)
    return sorted(sizes,reverse=True)

def hidden_faces(cells):
    lo=tuple(min(p[i] for p in cells)-1 for i in range(3));hi=tuple(max(p[i] for p in cells)+1 for i in range(3))
    air={lo};todo=[lo]
    while todo:
        x,y,z=todo.pop()
        for dx,dy,dz in D6:
            q=(x+dx,y+dy,z+dz)
            if any(q[i]<lo[i] or q[i]>hi[i] for i in range(3)) or q in cells or q in air: continue
            air.add(q);todo.append(q)
    faces=0; hidden=0
    for x,y,z in cells:
        for dx,dy,dz in D6:
            q=x+dx,y+dy,z+dz
            if q in cells: continue
            faces+=1
            if q not in air:hidden+=1
    return faces,hidden

report={};allvox={};renderparts={}
for species in ('pine','oak','apple','juniper'):
    mod=importlib.import_module('generate_'+species+'_glbs')
    for name,stage,season,variant in mod.manifest():
        vox=getattr(mod,'build_'+species)(stage,season,variant)
        path=ROOT/'assets/models/flora/trees'/species/(name+'.glb')
        p,n,c=glb(path); mp,mn,mc,mi=mesh_from_voxels(vox)
        assert np.array_equal(p,np.array(mp,dtype=np.float32)),name
        assert np.array_equal(c,np.array(mc,dtype=np.float32)[:,:3]),name
        faces,hidden=hidden_faces(vox.cells)
        s6=components(vox.cells,D6);s26=components(vox.cells,D26)
        dims=(p.max(0)-p.min(0)).tolist()
        report[name]={'species':species,'stage':stage,'season':season,'variant':variant,'dims_xyz':dims,'voxels':len(vox),'triangles':len(mi)//3,'hidden_cavity_triangles':hidden*2,'components_6':len(s6),'components_26':len(s26),'detached_voxels_26':sum(s26[1:]),'colors':len(set(vox.cells.values())),'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
        allvox[name]=vox;renderparts[name]=[(p,n,c)]
        if variant==1: print(name, 'size',dims,'tris',len(mi)//3,'hidden',round(100*hidden/faces,1),'%','detached',sum(s26[1:]))
season_changes={}
for species in ('pine','oak','apple','juniper'):
    summer=set(allvox[species+'_mature'].cells)
    others=['winter'] if species in ('pine','juniper') else ['spring','autumn','winter']
    if species=='apple':others+=['autumn_fruiting']
    for season in others:
        other=set(allvox[species+'_mature_'+season].cells)
        season_changes[species+' summer/'+season]={'changed_cells':len(summer^other),'intersection_over_union':round(len(summer&other)/len(summer|other),3)}
(OUT/'audit.json').write_text(json.dumps({'models':report,'season_changes':season_changes},indent=2))
print('TOTAL',len(report),'GLBs','triangles',sum(d['triangles'] for d in report.values()),'bytes',sum(d['bytes'] for d in report.values()))
print('SEASON_CHANGES',season_changes)

font=ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',20); small=ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',15)

def render(parts,size=(400,420),zoom=12,yaw=35,elev=35,center=(0,12,0)):
    yaw,elev=np.deg2rad([yaw,elev]); view=np.array([np.sin(yaw)*np.cos(elev),np.sin(elev),np.cos(yaw)*np.cos(elev)])
    right=np.array([np.cos(yaw),0,-np.sin(yaw)]);up=np.cross(view,right);light=np.array([-.3,.8,.55]);light/=np.linalg.norm(light)
    image=Image.new('RGB',(size[0]*2,size[1]*2),(229,228,218)); draw=ImageDraw.Draw(image); polys=[]
    for p,n,c in parts:
        faces=p.reshape(-1,4,3); norms=n[::4]; colors=c[::4]; mask=norms@view>0
        faces=faces[mask]; norms=norms[mask]; colors=colors[mask]
        rel=faces-np.array(center)
        xy=np.stack((rel@right,-(rel@up)),axis=2)*zoom*2+np.array(size)
        rgb=np.clip(colors*255*(.68+.32*np.maximum(0,norms@light))[:,None],0,255).astype(int)
        polys.extend(zip(faces.mean(1)@view,xy,rgb))
    for depth,xy,c in sorted(polys,key=lambda a:a[0]):draw.polygon([tuple(v) for v in xy],fill=tuple(c))
    return image.resize(size,Image.Resampling.LANCZOS)

for species in ('pine','oak','apple','juniper'):
    names=[n for n,d in report.items() if d['species']==species]
    w,h=370,360;cols=4;rowh=405
    sheet=Image.new('RGB',(w*cols,65+rowh*((len(names)+cols-1)//cols)),(245,243,236));d=ImageDraw.Draw(sheet)
    d.text((18,16),species.capitalize()+' | CURRENT exported models | each tile fitted independently',font=font,fill=(35,39,40))
    for i,name in enumerate(names):
        p=renderparts[name][0][0];dims=p.max(0)-p.min(0)
        zoom=min(18,285/max(float(dims[1]),float(dims[0]),float(dims[2])))
        x=(i%cols)*w;y=65+(i//cols)*rowh
        sheet.paste(render(renderparts[name],(w,h),zoom=zoom,center=(0,float(dims[1])*.5,0)),(x,y))
        d.text((x+8,y+h+3),name.replace(species+'_',''),font=small,fill=(35,39,40))
        d.text((x+8,y+h+23),f'{dims[1]:g} high | {dims[0]:g} wide | {report[name]["triangles"]:,} tris',font=small,fill=(85,88,89))
    sheet.save(OUT/(species+'_current.png'))

# Equal world scale; the approved adult dwarf is shown beside each tree.
sheet=Image.new('RGB',(1600,970),(245,243,236));d=ImageDraw.Draw(sheet)
d.text((20,15),'CURRENT trees with the new dwarf | same world scale in all panels | 1 voxel = 1 block',font=font,fill=(35,39,40))
for row,stage in enumerate(('mature','ancient')):
    for col,species in enumerate(('pine','oak','apple','juniper')):
        name=species+'_'+stage;parts=list(renderparts[name]);extent=report[name]['dims_xyz'][0]/2
        dwarf=assemble(ROOT/'assets/dwarves',beard='short_trimmed')
        for p,n,c in dwarf:
            p=p.copy();p[:,0]+=extent+2;p[:,2]+=2
            parts.append((p,n,c))
        x=col*400;y=60+row*450
        sheet.paste(render(parts,zoom=11.5,center=(1.5,11,0)),(x,y))
        dims=report[name]['dims_xyz'];d.text((x+10,y+418),f'{species.capitalize()} {stage} | {dims[1]:g} high / {dims[0]:g} wide',font=small,fill=(35,39,40))
sheet.save(OUT/'scale_lineup.png')
print(OUT)
