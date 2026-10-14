"""Measure local Stonehearth QB art and export disposable review meshes.

Reads the supplied source without modifying it. The complete occupied voxel
union, not padded matrix extents, supplies dimensions. JSON mixins resolve the
per-entity render scale; the local modding guide documents the 0.1 fallback.
Only static authored poses are exported, not Stonehearth animation playback.
"""
import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from voxel_glb import Voxels, mesh_from_voxels, write_glb


def read_qb(path):
    data = path.read_bytes()
    cursor = 0

    def unpack(fmt):
        nonlocal cursor
        value = struct.unpack_from('<' + fmt, data, cursor)
        cursor += struct.calcsize('<' + fmt)
        return value

    version, color_format, orientation, compressed, visibility_mask, count = unpack('6I')
    assert version == 257 and color_format in (0, 1) and orientation == 1
    assert compressed in (0, 1) and visibility_mask in (0, 1)
    matrices = []
    for _ in range(count):
        length, = unpack('B')
        name = data[cursor:cursor+length].decode('utf-8')
        cursor += length
        sx, sy, sz, ox, oy, oz = unpack('3I3i')
        cells = {}
        for z in range(sz):
            values = []
            if not compressed:
                values = unpack(str(sx*sy) + 'I')
            else:
                while True:
                    value, = unpack('I')
                    if value == 6:
                        break
                    if value == 2:
                        run, value = unpack('2I')
                        values.extend([value] * run)
                    else:
                        values.append(value)
                    assert len(values) <= sx*sy, 'QB RLE slice overflow'
            assert len(values) == sx*sy, 'QB slice length mismatch'
            for index, color in enumerate(values):
                r, g, b, a = struct.pack('<I', color)
                if not a:
                    continue
                if color_format == 1:
                    r, b = b, r
                cells[(ox+index%sx, oy+index//sx, oz+z)] = (r, g, b)
        matrices.append((name, cells))
    assert cursor == len(data), 'QB trailing bytes'
    return matrices


def bounds(cells):
    minimum = [min(p[i] for p in cells) for i in range(3)]
    maximum = [max(p[i]+1 for p in cells) for i in range(3)]
    return minimum, maximum


def merge(a, b):
    result = dict(a)
    for k, v in b.items():
        result[k] = merge(result[k], v) if isinstance(v, dict) and isinstance(result.get(k), dict) else v
    return result


class Reference:
    def __init__(self, root):
        self.root = root.resolve()
        self.hashes = {}
        self.aliases = self.read_json(self.root / 'manifest.json')['aliases']

    def track(self, path):
        self.hashes[str(path.relative_to(self.root)).replace('\\', '/')] = hashlib.sha256(path.read_bytes()).hexdigest()
        return path

    def read_json(self, path):
        return json.loads(self.track(path).read_text(encoding='utf-8-sig'))

    def resolve(self, value, parent):
        if value.startswith('stonehearth:'):
            return self.resolve(self.aliases[value.split(':', 1)[1]], self.root / 'manifest.json')
        assert value.startswith('file(') and value.endswith(')'), value
        value = value[5:-1]
        path = self.root / value.lstrip('/') if value.startswith('/') else parent.parent / value
        if path.is_dir():
            path = path / (path.name + '.json')
        return path.resolve()

    def entity(self, path):
        raw = self.read_json(path)
        result = {}
        mixins = raw.get('mixins', [])
        for value in ([mixins] if isinstance(mixins, str) else mixins):
            result = merge(result, self.entity(self.resolve(value, path)))
        # Resolve local paths before mixins lose their owning file context.
        raw = dict(raw)
        variants = raw.get('components', {}).get('model_variants', {})
        if 'default' in variants and 'models' in variants['default']:
            raw['_review_models'] = []
            for model in variants['default']['models']:
                if isinstance(model, dict):
                    assert model['type'] == 'one_of'
                    model = model['items'][0]
                raw['_review_models'].append(str(self.resolve(model, path)))
        return merge(result, raw)

    def human_palette(self):
        mapping = {}
        for family, material in [('skin', 'skin_white'), ('hair', 'hair_brown'), ('eyes', 'eye_blue')]:
            color_map = self.read_json(self.resolve('stonehearth:color_map:'+family, self.root / 'manifest.json'))
            materials = self.read_json(self.root / 'data/materials/material_maps' / (material+'_material_map.json'))
            for color, key in color_map.items():
                if key in materials:
                    mapping[color.lower()] = materials[key]['color']
        return mapping


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=Path('P:/stonehearth'))
    parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[2] / 'tmp/stonehearth_scale_20261013/reference')
    args = parser.parse_args()
    ref = Reference(args.source)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / '.gdignore').write_text('')
    (args.output / '.gitignore').write_text('*\n!.gitignore\n')
    guide = ref.track(ref.root / 'docs/modding_guide/modding_guide/basic/adding_items/item_scale/index.html')
    assert "by default it's 0.1" in guide.read_text(encoding='utf-8')
    palette = ref.human_palette()
    specs = {
        'hearthling': 'entities/humans/male/male_1.json',
        'deer': 'entities/critters/deer_horned/deer_horned.json',
        'wolf': 'entities/monsters/forest/wolf/wolf.json',
        'rabbit': 'entities/critters/rabbit/rabbit.json',
        'pine_mature': 'entities/trees/pine_tree/medium_pine_tree/medium_pine_tree.json',
        'pine_ancient': 'entities/trees/pine_tree/large_pine_tree/large_pine_tree.json',
        'pine_sapling': 'entities/trees/pine_tree/sapling_pine_tree/sapling_pine_tree.json',
        'oak_mature': 'entities/trees/oak_tree/medium_oak_tree/medium_oak_tree.json',
    }
    report = {'source_root': str(ref.root), 'units': 'terrain blocks', 'pose': 'occupied QB voxels in authored assembly; no animation applied', 'models': {}}
    for key, relative in specs.items():
        path = ref.root / relative
        entity = ref.entity(path)
        scale = entity.get('components', {}).get('render_info', {}).get('scale', .1)
        models = list(map(Path, entity['_review_models']))
        # A concrete customization with ordinary hair; base entity has no chosen hair.
        if key == 'hearthling':
            models.append(path.parent / 'hair_1.qb')
            job_path = ref.root / 'jobs/worker/worker_description.json'
            job = ref.read_json(job_path)
            outfit = ref.entity(ref.resolve(job['equipment']['torso'], job_path))
            models.extend(map(Path, outfit['_review_models']))
        vox = Voxels()
        parts = {}
        for model in models:
            for name, cells in read_qb(ref.track(model)):
                if not cells:
                    continue
                low, high = bounds(cells)
                parts[model.stem+':'+name] = {'size': [(high[i]-low[i])*scale for i in range(3)], 'min': low, 'max': high}
                for pos, color in cells.items():
                    hex_color = '#%02x%02x%02x' % color
                    if key == 'hearthling' and hex_color in palette:
                        color = tuple(bytes.fromhex(palette[hex_color].lstrip('#')))
                    # QB palette bytes are sRGB; glTF vertex colors are linear.
                    vox.cells[pos] = tuple(v/255/12.92 if v/255<=.04045 else ((v/255+.055)/1.055)**2.4 for v in color)
        low, high = bounds(vox.cells)
        size = [round((high[i]-low[i])*scale, 6) for i in range(3)]
        mesh = mesh_from_voxels(vox)
        # Center horizontal bounds and place soles on zero; never change dimensions.
        shift = [(low[0]+high[0])/2, low[1], (low[2]+high[2])/2]
        mesh = ([(p[0]-shift[0], p[1]-shift[1], -(p[2]-shift[2])) for p in mesh[0]],
                [(n[0], n[1], -n[2]) for n in mesh[1]], mesh[2],
                [mesh[3][i+j] for i in range(0,len(mesh[3]),3) for j in (0,2,1)])
        write_glb(args.output / (key+'.glb'), 'Stonehearth reference '+key, mesh, scale)
        report['models'][key] = {'entity':relative, 'models':[str(p.relative_to(ref.root)).replace('\\','/') for p in models], 'render_scale':scale,
            'width':size[0], 'height':size[1], 'depth':size[2], 'occupied_voxels':len(vox), 'parts':parts}
        print(f'{key}: {size[1]:.3f} high x {size[0]:.3f} wide x {size[2]:.3f} deep; scale {scale}')
    report['sources_sha256'] = ref.hashes
    report['source_unchanged'] = all(hashlib.sha256((ref.root/p).read_bytes()).hexdigest()==h for p,h in ref.hashes.items())
    assert report['source_unchanged']
    (args.output / 'measurements.json').write_text(json.dumps(report, indent=2)+'\n')
    print(f'STONEHEARTH_REFERENCE_OK: {len(specs)} measured models; {len(ref.hashes)} source files unchanged')


if __name__ == '__main__':
    main()
