"""Read an explicitly selected MagicaVoxel model, without merging scene frames.

Chunk layout: https://github.com/ephtracy/voxel-model/blob/master/MagicaVoxel-file-format-vox.txt
The source may contain unreferenced models and animation frames. Model selection
is an authoring decision saved in JSON, never inferred from scene visibility.
"""
from pathlib import Path
import struct


def read_models(path):
    raw=Path(path).read_bytes()
    if len(raw)<20 or raw[:4]!=b'VOX ': raise ValueError('Not a VOX file')
    if struct.unpack_from('<I',raw,4)[0] not in (150,200): raise ValueError('Unsupported VOX version')
    if raw[8:12]!=b'MAIN': raise ValueError('Missing MAIN chunk')
    models=[]; size=None; palette=None

    def chunks(start,end):
        nonlocal size,palette
        while start<end:
            if start+12>end: raise ValueError('Truncated VOX chunk')
            name,n,children=struct.unpack_from('<4sII',raw,start)
            data=start+12; stop=data+n; next_chunk=stop+children
            if next_chunk>end: raise ValueError('VOX chunk exceeds parent')
            if name==b'SIZE':
                if n!=12: raise ValueError('Invalid SIZE chunk')
                size=struct.unpack_from('<3I',raw,data)
                if not all(0<v<=256 for v in size): raise ValueError('Invalid model dimensions')
            elif name==b'XYZI':
                if size is None or n<4: raise ValueError('XYZI without SIZE')
                count=struct.unpack_from('<I',raw,data)[0]
                if n!=4+count*4: raise ValueError('Invalid XYZI length')
                cells={}
                for x,y,z,color in struct.iter_unpack('4B',raw[data+4:stop]):
                    if color==0 or any(v>=limit for v,limit in zip((x,y,z),size)):
                        raise ValueError('Invalid voxel coordinate or palette index')
                    if (x,y,z) in cells: raise ValueError('Duplicate voxel')
                    cells[x,y,z]=color
                models.append({'size':size,'cells':cells}); size=None
            elif name==b'RGBA':
                if n!=1024: raise ValueError('Invalid palette length')
                palette=[tuple(raw[i:i+4]) for i in range(data,stop,4)]
            if children: chunks(stop,next_chunk)
            start=next_chunk

    chunks(8,len(raw))
    if not models: raise ValueError('No voxel models')
    return models,palette


def grounded_cells(model):
    """Z-up to Y-up, preserving handedness, integer cells and source scale."""
    sx,sy,_=model['size']
    bottom=min(p[2] for p in model['cells'])
    return {(x-sx//2,z-bottom,sy//2-1-y):color
            for (x,y,z),color in model['cells'].items()}


def write_model(path,size,cells,palette):
    """Save a clean, single-model editable VOX with 1-based palette indices."""
    def chunk(name,data): return struct.pack('<4sII',name,len(data),0)+data
    if len(palette)>255: raise ValueError('Too many palette entries')
    colors=b''.join(bytes(c) for c in palette)+bytes((256-len(palette))*4)
    xyz=b''.join(bytes((*p,c)) for p,c in sorted(cells.items()))
    children=chunk(b'SIZE',struct.pack('<3I',*size))+chunk(b'XYZI',struct.pack('<I',len(cells))+xyz)+chunk(b'RGBA',colors)
    path=Path(path); path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(b'VOX '+struct.pack('<I',150)+struct.pack('<4sII',b'MAIN',0,len(children))+children)
