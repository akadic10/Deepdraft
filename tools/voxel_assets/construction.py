"""Construction models (Hearthblock, doc 256): the materials crate, which shares item joinery,
and the built log pieces (doc 275), one model in the hand-hewn source palette holding every
piece as a named part; CraftMaterials recolours it for each wood."""
from common import Part
from hearthblock_goods import shell
import built_logs
import hearthblock


def assets(only=None):
    path='assets/models/construction/materials_crate.glb'
    if not only or only in path:
        yield path,{'main':Part(shell())},{}
    path='assets/models/construction/logs.glb'
    if not only or only in path:
        occlusion=hearthblock.occlusion()
        parts={name:Part(built_logs.voxels(roles),occlusion=occlusion) for name,roles in built_logs.pieces().items()}
        yield path,parts,{'source':'tools/voxel_assets/built_logs.py','palette':'hand_hewn_timber','pieces':len(parts)}
