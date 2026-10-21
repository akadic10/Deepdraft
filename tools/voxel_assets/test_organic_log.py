"""Bounded sculpting preserves seat/work contacts and a single connected solid."""
import unittest
import organic_log
import log_chair
import log_table
import workbench


class OrganicLogTests(unittest.TestCase):
    def test_connected_native_solids_with_real_drying_splits(self):
        for name,roles in [('stool',log_chair.roles()),('table',log_table.role_cells()),
                           ('workbench',workbench.role_cells())]:
            with self.subTest(name=name):
                cells=set(roles);remaining=cells.copy();stack=[remaining.pop()]
                while stack:
                    p=stack.pop()
                    for axis in range(3):
                        for sign in (-1,1):
                            q=list(p);q[axis]+=sign;q=tuple(q)
                            if q in remaining:remaining.remove(q);stack.append(q)
                self.assertFalse(remaining,'detached bark or wood must not float')
                self.assertTrue(all(all(isinstance(v,int) for v in p) for p in cells))
                top=max(y for x,y,z in cells)
                # Central seat and pedestal contact remain solid and level.
                self.assertTrue(all((x,top,z) in cells for x in range(-2,2) for z in range(-2,2)))
        self.assertNotIn((4,13,-3),log_chair.roles())
        self.assertNotIn((17,19,-9),log_table.role_cells())
        self.assertIn((7,17,-6),log_table.role_cells(),'inner split leaves supporting wood below')

    def test_repeatable_bounded_asymmetry(self):
        for source,kind in [(log_table.top_cells(),'large'),(log_table.base_cells(),'pedestal')]:
            result=organic_log.roles(source,kind)
            self.assertEqual(result,organic_log.roles(source,kind))
            self.assertEqual(organic_log.bounds(result),organic_log.bounds(source))
            self.assertNotEqual(set(result),{(-x-1,y,z) for x,y,z in result})


if __name__=='__main__':unittest.main()
