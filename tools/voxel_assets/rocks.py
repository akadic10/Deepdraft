"""Grounded voxel boulders and separated walkable scree from authored dimensions."""
import math
from common import Voxels,Part,linear,read_json


def stone(vox,size,color,tilt,shoulder,at=(0,0),yaw=0):
    cosine,sine=math.cos(yaw),math.sin(yaw)
    rx=(abs(cosine)*size[0]+abs(sine)*size[2])*.5
    rz=(abs(sine)*size[0]+abs(cosine)*size[2])*.5
    height=max(1,math.floor(size[1]*16))
    for x in range(math.floor((at[0]-rx)*16),math.ceil((at[0]+rx)*16)):
        for z in range(math.floor((at[1]-rz)*16),math.ceil((at[1]+rz)*16)):
            dx,dz=(x+.5)/16-at[0],(z+.5)/16-at[1]
            nx=(cosine*dx-sine*dz)/(size[0]*.5)
            nz=(sine*dx+cosine*dz)/(size[2]*.5)
            for y in range(height):
                ny=(y+.5)/height
                edge=min(1,.80+ny*.8,1-shoulder*max(0,ny-.5)*.45)
                if max(abs(nx),abs(nz))>edge or abs(nx)+abs(nz)>edge*1.5: continue
                if ny>min(1,1-tilt[0]*nx-tilt[1]*nz): continue
                # One restrained mineral seam, not per-voxel noise.
                tint=1.04 if .42<ny<.53 and nx>.15 else 1
                vox.cells[x,y,z]=tuple(min(1,v*tint) for v in color)


def assets(only=None):
    profile=read_json('data/art/voxel_rocks.json')
    palette=[linear(c) for c in profile['palette']]
    for i,p in enumerate(profile['boulders']):
        path=f'assets/models/rocks/boulders/boulder_{i+1}.glb'
        if only and only not in path: continue
        vox=Voxels(); stone(vox,p['size'],palette[i],p['top_tilt'],p['shoulder'])
        yield path,{'main':Part(vox)},dict(kind='boulder',variant=i,blocking=True)
    for i,clump in enumerate(profile['scree']):
        path=f'assets/models/rocks/scree/scree_{i+1}.glb'
        if only and only not in path: continue
        vox=Voxels()
        for j,(x,z,width,height,depth,yaw) in enumerate(clump):
            stone(vox,(width,height,depth),palette[(i+j)%3],(.18,-.14),1.2,(x,z),yaw)
        yield path,{'main':Part(vox)},dict(kind='scree',variant=i,blocking=False,stones=len(clump))
