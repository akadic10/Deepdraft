"""Complete defined crop stages, ground contacts and separated scree contracts."""
import unittest
from collections import deque
from coverage import expected_paths
from rocks import assets as rocks
from crops import assets as crops


def components(cells):
    remaining=set(cells); result=[]
    while remaining:
        first=remaining.pop(); pending=deque([first]); part={first}
        while pending:
            p=pending.popleft()
            for axis in range(3):
                for sign in (-1,1):
                    n=list(p); n[axis]+=sign; n=tuple(n)
                    if n in remaining:
                        remaining.remove(n); part.add(n); pending.append(n)
        result.append(part)
    return result


class GroundCropTests(unittest.TestCase):
    def test_complete_grounded_rocks_and_separated_scree(self):
        rows=list(rocks())
        self.assertEqual({r[0] for r in rows},expected_paths('rocks'))
        for path,parts,meta in rows:
            cells=parts['main'].voxels.cells
            self.assertEqual(min(p[1] for p in cells),0,path)
            pieces=components(cells)
            self.assertTrue(all(min(p[1] for p in piece)==0 for piece in pieces),path)
            if meta['kind']=='scree': self.assertGreaterEqual(len(pieces),3,path)
            else: self.assertEqual(len(pieces),1,path)

    def test_all_crop_references_and_growth(self):
        rows=list(crops()); by_species={}
        self.assertEqual(len(rows),14)
        self.assertEqual({r[0] for r in rows},expected_paths('crops'))
        for path,parts,meta in rows:
            cells=parts['main'].voxels.cells
            self.assertEqual(min(p[1] for p in cells),0,path)
            self.assertEqual(meta['integration'],'art_and_data_only')
            by_species.setdefault(meta['species'],[]).append((meta,max(p[1] for p in cells),len(cells)))
        for species,forms in by_species.items():
            young=[r for r in forms if r[0]['stage'] in ('cutting','seedling','sprouting')]
            older=[r for r in forms if r not in young]
            self.assertEqual(len(young),1,species)
            self.assertTrue(all(r[1]>young[0][1] for r in older),species)
            self.assertTrue(all(r[2]>young[0][2] for r in older),species)


if __name__=='__main__': unittest.main()
