"""Known binary fixtures catch layout, RLE, color and padded-bound mistakes."""
import struct
import tempfile
import unittest
from pathlib import Path
from stonehearth_reference import read_qb, bounds


class QBReadTest(unittest.TestCase):
    def fixture(self, compressed=False, bgra=False):
        # A padded 3x2x1 matrix at a signed origin; two occupied cells only.
        first = struct.unpack('<I', bytes([30, 20, 10, 63] if bgra else [10, 20, 30, 63]))[0]
        second = struct.unpack('<I', bytes([90, 80, 70, 1] if bgra else [70, 80, 90, 1]))[0]
        header = struct.pack('<6I', 257, int(bgra), 1, int(compressed), 1, 1)
        matrix = b'\x04test' + struct.pack('<3I3i', 3, 2, 1, -5, 8, -3)
        payload = [0, first, 0, 0, second, 0]
        if compressed:
            payload = [0, first, 2, 2, 0, second, 0, 6]
        return header + matrix + struct.pack('<' + str(len(payload)) + 'I', *payload)

    def read(self, data):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'fixture.qb'
            path.write_bytes(data)
            return read_qb(path)

    def test_uncompressed_positions_and_occupied_bounds(self):
        name, cells = self.read(self.fixture())[0]
        self.assertEqual(name, 'test')
        self.assertEqual(cells, {(-4, 8, -3):(10,20,30), (-4,9,-3):(70,80,90)})
        self.assertEqual(bounds(cells), ([-4,8,-3], [-3,10,-2]))

    def test_compressed_slice_equals_uncompressed(self):
        self.assertEqual(self.read(self.fixture(True)), self.read(self.fixture()))

    def test_bgra_palette(self):
        self.assertEqual(self.read(self.fixture(bgra=True)), self.read(self.fixture()))

    def test_trailing_data_rejected(self):
        with self.assertRaises(AssertionError):
            self.read(self.fixture()+b'bad')


if __name__ == '__main__':
    unittest.main()
