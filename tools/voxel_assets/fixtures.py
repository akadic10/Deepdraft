"""Small repeatable import fixtures for the production consumer contracts."""
from common import ROOT, Voxels, Part, box, export_asset


def main():
    directory=ROOT/'assets/models/studies/voxel_pipeline'
    floor=Voxels(); box(floor,(.5,.5,.5),(1,1,1),(.4,.25,.1))
    export_asset(directory/'floor.glb',{'main':Part(floor)})
    parts={}
    for name,x in [('leaf_left',-.5),('leaf_right',.5)]:
        leaf=Voxels(); box(leaf,(x,2,0),(1,4,.25),(.4,.25,.1))
        parts[name]=Part(leaf)
    export_asset(directory/'door.glb',parts)
    print('VOXEL_FIXTURES_OK')


if __name__=='__main__': main()
