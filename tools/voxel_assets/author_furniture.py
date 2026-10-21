"""Author the complete native-solid furniture catalogue into its JSON source.

This is an explicit layout authoring tool, not a triangle-to-voxel converter.
Run intentionally when revising the catalogue; build.py reads the saved JSON.
"""
import copy
import json
import math
from common import ROOT,read_json

palette=read_json('data/art/furniture_catalog.json')['palette'].copy()
palette.update({'w:'+k:v for k,v in read_json('data/materials/craft_materials.json')['source_palettes']['oak_log']['colors'].items()})
pilot=read_json('data/art/micro_voxel_study.json')
palette.update(pilot['palette'])
for name in ['camp_log','oak_log']:
    palette.update({name+':'+k:v for k,v in read_json('data/materials/craft_materials.json')['source_palettes'][name]['colors'].items()})
for i,c in enumerate(read_json('data/art/furniture_pilot.json')['hay']): palette['hay'+str(i)]=c
palette['wet']='56615e'


class Shapes(list):
    def box(self,center,size,color='w:wood',cut=0,**kw):
        self.append(dict(op='box',center=center,size=size,color=color,cut=cut,**kw))
    def beam(self,a,b,radius=(.1,.1),color='w:wood',round=True,wood=False):
        extras=dict(colors=['w:bark','w:wood_dark','w:bark','w:bark_dark','w:wood','w:bark'],cap='w:cut') if wood else {}
        self.append(dict(op='beam',a=a,b=b,radius=radius,color=color,round=round,**extras))
    def profile(self,rings,color='w:wood',**kw):
        self.append(dict(op='profile',rings=rings,color=color,**kw))
    def ring(self,y0,y1,radius,color,inner=0,center=(0,0)):
        self.profile([[y0,radius,radius,*center],[y1,radius,radius,*center]],color,inner=inner)
    def ell(self,center,radius,color,power=3):
        self.append(dict(op='ellipsoid',center=center,radius=radius,color=color,power=power))
    def hewn(self,a,b,radius=(.125,.125),seed=0):
        self.beam(a,b,radius,wood=True)
        self[-1]['hewn']=seed
    def cells(self,lo,hi,color='w:wood',cut=0,**kw):
        self.box(tuple((lo[i]+hi[i])/32 for i in range(3)),
                 tuple((hi[i]-lo[i])/16 for i in range(3)),color,cut/16,**kw)


def planks(m,width,depth,top,thick,count):
    for i in range(count): m.box((0,top-thick/2,-depth/2+depth*(i+.5)/count),(width,thick,depth/count),['w:wood','w:wood_light'][i%2])


def table(w,d):
    m=Shapes()
    for x in (-w/2+.375,w/2-.375):
        m.box((x,.125,0),(.375,.25,d-.25),'w:wood_dark')
        m.box((x,.875,0),(.3125,1.5,.4375))
        m.box((x,1.375,0),(.375,.25,d-.125),'w:wood_dark')
        for s in [-1,1]: m.beam((x,.75,0),(x,1.5,s*(d/2-.25)),(.09375,.09375),round=False)
    m.box((0,.5,0),(w-.375,.1875,.25),'w:wood_dark')
    planks(m,w,d,1.75,.25,max(4,round(d/.4375)))
    return m


def chair(legacy=False):
    m=Shapes(); half=.5 if legacy else 1.; seat=.75 if legacy else .875; top=2 if legacy else 1.375
    for x in (-half+.125,half-.125):
        for z in (-half+.125,half-.125):
            m.box((x,seat/2,z),(.1875,seat,.1875))
            m.box((x,.0625,z),(.1875,.125,.1875),'iron_dark')
        m.box((x,.4375,0),(.125,.125,half*1.75),'w:wood_dark')
        m.box((x,(top+seat)/2,-half+.125),(.1875,top-seat,.1875))
    planks(m,half*2,half*2,seat,.1875,4)
    m.box((0,top-.125,-half+.125),(half*2,.25,.1875),'w:wood_light')
    if legacy:
        for x in (-.25,.25): m.box((x,1.375,-.375),(.125,1.0,.125))
    else: m.box((0,1.0625,-.875),(.3125,.375,.1875),'w:wood_dark')
    return m


def bed(rough=False):
    m=Shapes()
    if rough:
        for i,x in enumerate([-1.4375,1.4375]): m.hewn((x,.1875,-1.5),(x,.1875,1.5),(.1875,.1875),i+1)
        for i,z in enumerate([-1.1875,1.1875]): m.hewn((-2,.4375,z),(2,.4375,z),(.25,.25),i+4)
        # Full, compressed bedding at the established twelve-cell sleep plane.
        m.cells((-28,8,-17),(28,12,17),'hay1',3)
        for lo,hi,c in [((-26,11,-15),(-6,12,6),'hay2'),((-14,11,-6),(16,12,14),'hay3'),((8,11,-14),(26,12,3),'hay2')]:
            m.cells(lo,hi,c,2,mode='paint')
        # One broad head bolster; stepped shoulders replace the repeated bumps.
        m.cells((-27,12,-13),(-10,14,13),'hay2',3)
        m.cells((-25,14,-10),(-12,15,9),'hay3',2)
        # Sparse bent bundles, not a uniform fabric stripe or per-cell noise.
        for x,z,y in [(-23,-6,14),(-21,3,14),(-6,-10,11),(7,7,11),(16,-6,11),(1,1,11)]:
            for i,(dx,dz,length) in enumerate([(0,0,6),(2,2,5),(1,4,4)]):
                m.cells((x+dx,y,z+dz),(x+dx+length,y+1,z+dz+1),'hay4' if i==1 else 'hay1',mode='paint')
        for lo,hi in [((-26,9,-17),(-20,11,-14)),((11,10,-17),(17,12,-14)),((19,9,13),(28,11,17)),((-15,9,14),(-7,11,17))]:
            m.cells(lo,hi,'hay2',1)
        for lo,hi in [((-28,11,-7),(-25,12,-3)),((24,11,5),(28,12,8)),((-4,11,14),(1,12,17))]:
            m.cells(lo,hi,mode='subtract')
        # Four bindings grip the existing timber joints without raising the bed.
        for x in [-23,23]:
            for z in [-19,19]:
                m.cells((x-1,3,z-4),(x+1,11,z+4),'rope',mode='paint')
        m.cells((29,8,-22),(32,10,-20),mode='subtract')
        m.cells((-32,8,20),(-30,11,22),mode='subtract')
        return m
    for x in (-1.8125,1.8125):
        for z in (-.8125,.8125):
            m.box((x,.375,z),(.375,.75,.375)); m.box((x,.0625,z),(.375,.125,.375),'iron_dark')
    for z in (-.875,.875): m.box((0,.5625,z),(4,.25,.25),'w:wood_light')
    for x in (-1.8125,1.8125): m.box((x,.5625,0),(.25,.25,1.75),'w:wood_dark')
    m.box((0,.84375,0),(3.625,.3125,1.75),'linen',.125)
    m.box((-1.0625,1.125,0),(1.125,.25,1.625),'linen',.125)
    m.box((1.3125,1.125,0),(.75,.25,1.75),'blanket',.0625)
    m.box((1.03125,1.21875,0),(.0625,.0625,1.5),'linen_shadow',mode='paint')
    m.box((-1.90625,1,0),(.1875,2,2)); m.box((-1.90625,1.875,0),(.1875,.25,2),'w:wood_light')
    return m


def bench():
    return Shapes([dict(op='log_bench_vox')])


def chest():
    m=Shapes(); m.box((0,.46875,0),(1,.9375,1),'w:wood',.0625)
    for y in (.125,.8125): m.box((0,y,0),(1,.125,1),'w:wood_dark')
    m.box((0,.9375,0),(.875,.125,.875),'w:wood_light',.0625)
    for x in (-.3125,.3125):
        for z in (-.46875,.46875): m.box((x,.5,z),(.125,.875,.0625),'iron_dark')
        m.box((x,.96875,0),(.125,.0625,.875),'iron_dark')
    m.box((0,.65625,.46875),(.1875,.25,.0625),'iron')
    m.box((0,.6875,.46875),(.0625,.0625,.0625),'iron_dark',mode='paint')
    return m


def shelf():
    m=Shapes()
    for x in (-.4375,.4375):
        for z in (-.4375,.4375): m.box((x,1,z),(.125,2,.125))
    for y in [.0625,.5625,1.0625,1.5625,1.9375]: m.box((0,y,0),(1,.125,1),'w:wood_light')
    m.box((0,1,0),(.0625,1.875,.875),'w:wood_dark')
    for side in [-1,1]: m.beam((-.375,.1875,.4375),(side*.375,1.875,.4375),(.047,.047),'w:wood_dark',round=False)
    return m


def counter(stone=False):
    m=Shapes(); body='stone' if stone else 'w:wood'; trim='stone_light' if stone else 'w:wood_light'
    m.box((0,.125,0),(2,.25,1),'stone_dark' if stone else 'w:wood_dark',.0625)
    for x in (-.8125,.8125): m.box((x,1,0),(.375,1.75,.875),body)
    m.box((0,1,.34375),(1.5,1.5,.1875),body)
    for y in (.375,1.125): m.box((0,y,-.0625),(1.625,.125,.75),trim)
    m.box((0,1.875,0),(2,.25,1),trim)
    for x in (-.5,0,.5): m.box((x,1,.46875),(.0625,1.375,.0625),'iron' if stone else 'w:wood_dark')
    return m


def stump(game=False):
    return Shapes([dict(op='hand_hewn_vox',kind='game_table' if game else 'workbench')])


def door(width):
    parts={}
    for index in range(2 if width==4 else 1):
        m=Shapes(); w=2 if width==4 else width; center=(-1 if index==0 else 1) if width==4 else 0
        m.box((center,1.8125,0),(w,3.625,.125),'w:bark_dark')
        for i in range(w*2):
            x=center-w*.5+.25+i*.5; height=[3.75,3.875,3.8125][(i+index)%3]
            m.hewn((x,0,0),(x,height,0),(.25,.1875),i+index*5)
        for sign in [-1,1]:
            for y in [.75,3.0]:
                m.box((center,y,sign*.25),(w,.3125,.125),'w:wood_dark',.0625)
                m.box((center,y+.0625,sign*.3125),(w-.25,.0625,.0625),'w:wood_light',.0625)
                for x in [center-w/2+.25,center+w/2-.25]: m.hewn((x,y,sign*.25),(x,y,sign*.375),(.0625,.0625),index+3)
            pull=center+(w/2-.375)*(1 if index==0 else -1)
            for y in [1.5,1.875]: m.beam((pull,y,sign*.1875),(pull,y,sign*.375),(.047,.047),wood=True)
            m.box((pull,1.6875,sign*.375),(.1875,.5,.125),'w:wood_light',.0625)
        m.hewn((center-w/2+.1875,.9375,-.25),(center+w/2-.1875,2.8125,-.25),(.09375,.09375),index+2)
        # Bounded shoulder chips and a split in a single cut end.
        m.box((center-w/2+.0625,3.6875,0),(.125,.25,.375),mode='subtract')
        m.box((center+.0625,3.8125,.0625),(.0625,.25,.1875),mode='subtract')
        parts['leaf_left' if index==0 else 'leaf_right']=m
    return parts


def ladder(height):
    m=Shapes()
    for x in [-.3125,.3125]: m.beam((x,0,-.1875),(x,height,-.1875),(.0625,.125),wood=True)
    for i in range(height*2): m.beam((-.375,.3125+i*.5,-.125),(.375,.3125+i*.5,-.125),(.0625,.09375),wood=True)
    return m


def bridge(span):
    m=Shapes()
    for i,x in enumerate([-.25,.25,.75,1.25]):
        m.hewn((x,-.25,.375-(i%2)*.0625),(x,-.25,-span-1.375+(i%3)*.0625),(.25,.25),i*2+span)
        m[-1]['bank_span']=span
    for z in [0,-span-1]: m.hewn((-.5,-.46875,z),(1.5,-.46875,z),(.15625,.15625),span+3)
    # Cut patches suggest adze-flattened walking faces. Never cut the deck plane.
    for i,x in enumerate([-.25,.25,.75,1.25]):
        for z in [-.625,-span+.125]:
            m.box((x,-.03125,z),(.25,.0625,.4375),'w:wood_dark' if i%2 else 'w:wood',mode='paint')
    return m


def vat():
    m=Shapes()
    m.profile([[.125,.8125,.8125,0,-.0625],[.75,.9375,.9375,0,-.0625],[2,.875,.875,0,-.0625]],'w:wood',inner=.80,colors=['w:wood','w:wood_light']*8)
    for y,r in [(.3125,.875),(1.5,.9375)]: m.ring(y,y+.125,r,'iron_dark',inner=.87,center=(0,-.0625))
    m.box((0,.125,0),(1.5,.25,1.5),'w:wood_dark',.1875)
    m.ring(1.4375,1.5,.75,'liquid',center=(0,-.0625))
    m.beam((0,.4375,.6875),(0,.4375,.9375),(.0625,.0625),'copper')
    m.beam((0,.4375,.9375),(0,.25,.9375),(.0625,.0625),'copper')
    m.box((0,.5,.875),(.25,.0625,.125),'iron')
    return m


def aging_rack():
    m=Shapes()
    for x in [-.8125,.8125]:
        m.box((x,.125,0),(.25,.25,2),'w:wood_dark')
        for z in [-.5625,.5625]: m.box((x,.625,z),(.25,1,.25))
    for z in [-.5,.5]: m.box((0,1.0625,z),(2,.1875,.25),'w:wood_light')
    # Two horizontal, closed casks with contrasting end grain and hoops.
    for x in [-.5,.5]:
        m.beam((x,1.5625,-.6875),(x,1.5625,.6875),(.375,.375),wood=True)
        for z in [-.5,.5]: m.beam((x,1.5625,z-.0625),(x,1.5625,z+.0625),(.4375,.4375),'iron_dark')
    return m


def anvil():
    m=Shapes(); m.box((.0625,.125,0),(1.375,.25,1),'stone_dark',.0625); m.box((.125,.4375,0),(1,.625,.75),'stone',.0625)
    m.profile([[.6875,.5,.3125,.125,0],[1.0625,.25,.1875,.125,0],[1.25,.5,.3125,.125,0]],'iron')
    m.box((.25,1.375,0),(1.5,.25,.625),'iron_light',.0625)
    for i in range(5): m.box((-.9375+i*.125,1.3125,0),(.125,.125+i*.03125,.125+i*.0625),'iron_light')
    for x in [-.25,.5]:
        for z in [-.375,.375]: m.box((x,.75,z),(.125,.25,.125),'iron_dark')
    return m


def fire_body(name):
    m=Shapes()
    if name=='campfire':
        # Unequal fieldstones form a low, substantial rim around the fixed fire.
        stones=[((-7,0,-16),(5,6,-8),2),((6,0,-13),(14,5,-5),2),
                ((9,0,-4),(16,7,6),1),((5,0,7),(13,6,14),2),
                ((-6,0,9),(5,5,16),2),((-14,0,5),(-5,7,13),2),
                ((-16,0,-6),(-9,6,5),1),((-14,0,-14),(-6,5,-6),2)]
        for i,(lo,hi,cut) in enumerate(stones):
            m.cells(lo,hi,'stone_light' if i in (1,4,6) else 'stone',cut)
            m.cells((lo[0]+1,hi[1]-1,lo[2]+1),(lo[0]+4,hi[1],hi[2]-2),'stone_light',1,mode='paint')
            if i%2==0: m.cells((hi[0]-3,hi[1]-2,lo[2]),(hi[0],hi[1],lo[2]+3),mode='subtract')
        m.cells((-8,1,-10),(8,4,10),'stone_dark',mode='paint')
        m.cells((-7,0,-7),(7,2,7),'soot',2)
        for i,a in enumerate([-.4,1.0]):
            m.hewn((-.6*math.cos(a),.1875,-.6*math.sin(a)),(.6*math.cos(a),.1875,.6*math.sin(a)),(.15625,.15625),i+4)
        m.cells((-4,3,-4),(4,6,4),'soot',1,mode='paint')
    elif name=='hearth':
        m.cells((-16,0,-16),(16,3,16),'stone_dark',2)
        for row,cuts in enumerate([[-15,-5,4,15],[-15,-8,2,15],[-15,-4,7,15]]):
            for i,(lo,hi) in enumerate(zip(cuts,cuts[1:])):
                m.cells((lo,3+row*8,-15),(hi,11+row*8,-9),'stone_light' if (i+row)%4==0 else 'stone',1)
        for side in [-1,1]:
            lo,hi=(-15,-9) if side<0 else (9,15)
            for row,ends in enumerate([[-9,1,11],[-9,-1,11],[-9,3,11]]):
                for i,(a,b) in enumerate(zip(ends,ends[1:])):
                    m.cells((lo,3+row*6,a),(hi,9+row*6,b),'stone_light' if (row+i)%3==0 else 'stone',1)
            m.cells((lo,20,-8),(hi,22,10),'stone_light',1)
        for lo,hi in [((-15,25,-15),(-12,27,-12)),((6,26,-15),(8,27,-12)),((12,25,-12),(15,27,-9)),((-15,21,6),(-12,22,10)),((12,20,8),(15,22,11))]:
            m.cells(lo,hi,mode='subtract')
        # Smoke stains occupy inner faces; the open firebox remains unobstructed.
        m.cells((-7,3,-8),(7,5,10),'soot',1)
        m.cells((-5,8,-10),(5,20,-9),'stone_dark',1,mode='paint')
        for i,z in enumerate([-.125,.3125]): m.hewn((-.5625,.34375,z),(.5625,.34375,z),(.125,.125),i+1)
        m.cells((-4,5,-4),(4,7,7),'soot',1,mode='paint')
    elif name=='brazier':
        m.profile([[0,.3125,.3125,0,0],[.125,.375,.375,0,0],[.25,.25,.25,0,0]],'iron_dark')
        m.profile([[.1875,.125,.125,0,0],[.8125,.1875,.1875,0,0]],'iron')
        m.ring(.8125,.9375,.4375,'iron_dark',inner=.65)
        for i in range(8):
            a=i*math.tau/8; c,s=math.cos(a),math.sin(a)
            m.beam((c*.3125,.8125,s*.3125),(c*.4375,1.25,s*.4375),(.047,.047),'iron',round=False)
        m.ring(1.125,1.25,.5,'iron',inner=.80); m.ring(.8125,.9375,.3125,'soot')
    elif name=='smelter':
        m.box((0,.125,0),(2,.25,2),'stone_dark',.125)
        m.box((0,.875,-.625),(1.75,1.5,.5),'stone',.0625)
        for x in [-.6875,.6875]: m.box((x,.875,.1875),(.375,1.5,1.125),'stone',.0625)
        m.box((0,1.625,.125),(1.75,.25,1.375),'stone_light',.0625)
        m.box((0,.875,-.34375),(1,1.125,.0625),'soot')
        for x in [-.375,-.125,.125,.375]: m.box((x,.3125,.4375),(.0625,.125,.75),'iron_dark')
        m.profile([[1.75,.8125,.6875,0,0],[2.125,.4375,.375,0,-.25]],'iron')
        for x in [-.3125,.3125]: m.box((x,2.5625,-.3125),(.1875,.875,.75),'stone')
        for z in [-.625,0]: m.box((0,2.5625,z),(.5,.875,.125),'stone')
    else:
        if name=='wooden_torch':
            m.hewn((0,0,.5),(0,1,.5),(.1875,.1875),2)
            m.hewn((0,.375,0),(0,.375,.5),(.09375,.09375),5)
            m.cells((-3,10,5),(3,12,11),'rope')
            m.cells((-3,12,5),(3,13,11),'w:bark_dark',mode='paint')
            m.cells((-1,10,10),(1,12,11),'hay1',mode='paint')
        else:
            m.box((0,.4375,.0625),(.375,.875,.125),'iron',.0625)
            m.beam((0,.25,.125),(0,.375,.5),(.0625,.0625),'iron_dark',round=False)
            m.beam((0,.25,.5),(0,1,.5),(.125,.125),wood=True)
            for y in [.4375,.8125]: m.box((0,y,.5),(.4375,.125,.375),'iron_dark',.0625)
        m.box((0,.9375,.5),(.375 if name=='wooden_torch' else .1875,.125,.375 if name=='wooden_torch' else .1875),'soot',.0625)
    return m


def packed(name):
    m=Shapes()
    if name=='packed_furniture':
        m.box((0,.5,0),(1,1,1),'w:wood')
        for x in [-.4375,.4375]:
            for z in [-.4375,.4375]: m.box((x,.5,z),(.125,1,.125),'w:wood_light')
        for y in [.125,.875]:
            for z in [-.46875,.46875]: m.box((0,y,z),(.875,.125,.0625),'w:wood_dark')
        for z in [-.46875,.46875]: m.beam((-.375,.1875,z),(.375,.8125,z),(.0625,.03125),'w:wood_light',round=False)
    else:
        width=1.5 if name=='bridge_kit' else 1.25
        for i in range(3):
            for z in [-.25,.25]:
                if name=='bridge_kit': m.hewn((-width/2,.09375+i*.1875,z),(width/2,.09375+i*.1875,z),(.09375,.09375),i+2)
                else: m.beam((-width/2,.09375+i*.1875,z),(width/2,.09375+i*.1875,z),(.09375,.09375),wood=True)
        for x in [-.375,.375]: m.box((x,.5,0),(.0625,.125,.6875),'rope')
    return m


def flag():
    m=Shapes(); m.box((0,.15625,0),(.875,.3125,.75),'stone',.0625)
    m.beam((-.375,.25,0),(-.375,3,0),(.09375,.09375),wood=True)
    m.beam((-.5,2.6875,0),(.5,2.6875,0),(.0625,.0625),wood=True)
    for i in range(4): m.box((-.1875+i*.1875,1.875,0 if i%2 else .0625),(.1875,1.5-(i%2)*.125,.125),'flag_light' if i in [1,2] else 'flag')
    for y,w in [(1.625,.1875),(1.8125,.375),(2,.1875)]: m.box((.0625,y,.09375),(w,.1875,.0625),'flag_mark',mode='paint')
    return m


def fence(gate=False):
    if not gate:
        m=Shapes(); m.hewn((0,0,0),(0,1.3125,0),(.125,.125),2)
        m.cells((-2,20,-2),(-1,21,0),mode='subtract')
        return {'post':m}
    parts={}
    for side,label in [(-1,'post_left'),(1,'post_right')]:
        # Match the derived standalone post exactly, including its cut shoulder.
        m=Shapes(); m.hewn((side,0,0),(side,1.3125,0),(.125,.125),2)
        m.cells((side*16-2,20,-2),(side*16-1,21,0),mode='subtract'); parts[label]=m
    m=Shapes()
    for i,y in enumerate([.4375,1]): m.hewn((-.875,y,0),(.875,y,0),(.09375,.09375),i+2)
    for i,x in enumerate([-.8125,.8125]): m.hewn((x,.25,0),(x,1.125,0),(.09375,.09375),i)
    m.hewn((-.8125,.375,0),(.8125,1.0625,0),(.09375,.09375),3)
    for x in [-13,12]:
        for y in [7,16]: m.cells((x,y-1,-2),(x+1,y+1,2),'rope',mode='paint')
    parts['leaf_left']=m
    return parts


def main():
    pieces={name:{'main':fn()} for name,fn in {
        'log_bed':lambda:bed(True),'bench':bench,
        'crude_workbench':stump,'board_game_table':lambda:stump(True),
        'settlement_flag':flag,
        **{name:lambda n=name:packed(n) for name in ['packed_furniture','ladder_kit','bridge_kit']},
        **{'crude_ladder_'+str(h):lambda h=h:ladder(h) for h in range(1,5)},
        **{'log_bridge_'+str(s):lambda s=s:bridge(s) for s in range(1,6)}
    }.items()}
    pieces['log_chair']={'main':[dict(op='hand_hewn_vox',kind='log_stool')]}
    pieces['log_table']={'main':[dict(op='hand_hewn_vox',kind='dining_table')]}
    pieces['crude_workbench']={'main':[dict(op='hand_hewn_vox',kind='workbench')]}
    for w,name in [(2,'door'),(3,'log_door_3'),(4,'log_door_4')]: pieces[name]=door(w)
    for name in ['campfire','hearth','wooden_torch']:
        pieces[name]={('torch_body' if 'torch' in name else name+'_body'):fire_body(name)}
    for wet in [False,True]:
        m=Shapes(); m.profile([[0,.4375,.4375,0,0],[.1875,.5,.5,0,0],[.75,.4375,.5,0,0],[1,.375,.375,0,0]],'wet' if wet else 'stone')
        pieces['wet_stone' if wet else 'dry_stone']={'main':m}
    pieces['log_fence']=fence(); pieces['log_gate']=fence(True)
    m=Shapes()
    for i,y in enumerate([.4375,1]): m.hewn((-.5,y,0),(.5,y,0),(.09375,.09375),i+2)
    pieces['parts/log_fence_rails']={'rails':m}
    profile={'description':'Native 1:16 solid furniture authoring. Exact semantic palettes, preserved functional contact planes and named rigid parts. Flame libraries are built from voxel_fire_effects.json.', 'palette':palette,'pieces':pieces}
    (ROOT/'data/art/voxel_furniture.json').write_text(json.dumps(profile,indent=2)+'\n')
    print('VOXEL_FURNITURE_AUTHORED',len(pieces))


if __name__=='__main__': main()
