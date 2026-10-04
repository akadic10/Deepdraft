#!/usr/bin/env python3
"""Fast GLB geometry contact sheets for the isolated dwarf redesign.
Neutral orthographic studio approximation; Godot screenshots are separate.
Requires numpy and Pillow. Does not modify any GLB or live asset.
"""
import argparse
import json
import math
from pathlib import Path
import struct
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[1]
SKIN={'pale':(.96,.84,.77),'medium':(.85,.65,.50),'tan':(.71,.50,.35),'dark':(.42,.28,.18)}
HAIR={'brown':(.42,.26,.14),'black':(.10,.08,.08),'red':(.78,.22,.08),'blonde':(.88,.76,.44),'white':(.92,.92,.92)}
FONT_PATH='C:/Windows/Fonts/segoeui.ttf'
FONT=ImageFont.truetype(FONT_PATH,16)
SMALL=ImageFont.truetype(FONT_PATH,13)


def glb(path,tint=(1,1,1),mirror=False):
    raw=path.read_bytes(); length=struct.unpack_from('<I',raw,12)[0]
    doc=json.loads(raw[20:20+length]); buf=raw[28+length:]
    def acc(i):
        a=doc['accessors'][i]; v=doc['bufferViews'][a['bufferView']]
        n={'VEC3':3,'VEC4':4,'SCALAR':1}[a['type']]
        dt={5126:'<f4',5125:'<u4',5123:'<u2'}[a['componentType']]
        return np.frombuffer(buf,dtype=dt,count=a['count']*n,offset=v.get('byteOffset',0)+a.get('byteOffset',0)).reshape(-1,n).copy()
    prim=doc['meshes'][0]['primitives'][0]
    p=acc(prim['attributes']['POSITION']); n=acc(prim['attributes']['NORMAL']); c=acc(prim['attributes']['COLOR_0'])[:,:3]*tint
    if mirror: p[:,0]*=-1; n[:,0]*=-1
    return p,n,c


def assemble(folder,hairstyle='cropped',bearded=False,skin='medium',haircolor='brown',reference=False):
    s=SKIN[skin]; h=HAIR[haircolor]
    def part(name,t=(1,1,1),mir=False): return glb(folder/(name+'.glb'),t,mir)
    parts=[part('head_adult',s),part('body_base'),part('eyes',(.25,.55,.85))]
    for mir in (False,True): parts += [part('hand',s,mir),part('foot',mir=mir)]
    if reference:
        parts += [part('hair_m_short_back',h),part('brows_m_bushy',h)]
        if bearded: parts.append(part('beard_full_long',h))
    else:
        parts += [part('brows',h),part('hair_'+hairstyle,h)]
        if bearded: parts.append(part('beard_short',h))
    return parts


def render(parts,yaw=35,elev=30,size=(260,330),zoom=77):
    yaw,elev=math.radians(yaw),math.radians(elev)
    view=np.array([math.sin(yaw)*math.cos(elev),math.sin(elev),math.cos(yaw)*math.cos(elev)])
    right=np.array([math.cos(yaw),0,-math.sin(yaw)]); up=np.cross(view,right)
    light=np.array([-.3,.8,.55]); light/=np.linalg.norm(light)
    center=np.array([0,1.85,0]); factor=2
    img=Image.new('RGB',(size[0]*factor,size[1]*factor),(232,229,222)); draw=ImageDraw.Draw(img)
    polys=[]
    for p,n,c in parts:
        for j in range(0,len(p),4):
            if np.dot(n[j],view)<=0: continue
            face=p[j:j+4]; rel=face-center
            xy=np.column_stack((rel@right,-(rel@up)))*zoom*factor+np.array([size[0]*factor/2,size[1]*factor/2])
            color=tuple(np.clip(c[j]*255*(.68+.32*max(0,np.dot(n[j],light))),0,255).astype(int))
            polys.append((float(face.mean(0)@view),xy,color))
    for _,xy,color in sorted(polys,key=lambda q:q[0]): draw.polygon([tuple(v) for v in xy],fill=color)
    return img.resize(size,Image.Resampling.LANCZOS)


def sheet(path,title,cells,cols=4,size=(280,330)):
    w,h=size; pad=18; header=48; rowh=h+34
    image=Image.new('RGB',(w*cols+pad*2,header+((len(cells)+cols-1)//cols)*rowh+pad),(247,245,240));d=ImageDraw.Draw(image)
    d.text((pad,12),title,font=FONT,fill=(38,40,42))
    for idx,(label,parts,yaw,elev) in enumerate(cells):
        x=pad+(idx%cols)*w; y=header+(idx//cols)*rowh
        image.paste(render(parts,yaw,elev,size),(x,y));d.text((x+8,y+h+6),label,font=SMALL,fill=(38,40,42))
    image.save(path)


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--dir',type=Path,default=ROOT/'tmp/dwarf_redesign_preview');args=ap.parse_args()
    dest=args.dir/'renders';dest.mkdir(exist_ok=True)
    folder=args.dir/'models'
    roster=[('Cropped / bare',assemble(folder)),('Cropped / short beard',assemble(folder,bearded=True)),
            ('Swept braid / bare',assemble(folder,'swept_braid',False,'pale','red')),
            ('Swept braid / beard',assemble(folder,'swept_braid',True,'dark','white'))]
    rows=[]
    for yaw,elev,label in [(0,0,'front'),(35,30,'three-quarter'),(35,50,'RTS'),(130,30,'back')]:
        rows.extend([(name+' / '+label,parts,yaw,elev) for name,parts in roster])
    sheet(dest/'contact_sheet.png','Dwarf redesign prototype | 8 voxels per block | neutral geometry preview',rows)
    sheet(dest/'comparison.png','Current and prototype | identical world scale and lighting',[
        ('Current / bare',assemble(args.dir/'reference',reference=True),35,35),
        ('Prototype / bare',roster[0][1],35,35),
        ('Current / long beard',assemble(args.dir/'reference',reference=True,bearded=True),35,35),
        ('Prototype / short beard',roster[1][1],35,35),
    ])
    print(dest)


if __name__=='__main__': main()
