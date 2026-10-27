"""Lowers a TrueType font's line metrics, so as a fallback it never makes a line taller.

Godot measures a line by the tallest font among a face and its fallbacks (doc 23, "Type").
The symbol font behind the UI's faces (Noto Sans Symbols 2) is 1.70 em tall, which would
raise every line of Nunito (1.38 em) and Fredoka (1.22 em). This rewrites its ascent and
descent in the hhea and OS/2 tables (with the line gap at 0) and fixes the checksums. The
glyphs are untouched and still draw in full. The Open Font License allows this modified
version under the same licence.

    py tools/fit_font_metrics.py <source.ttf> <output.ttf> [ascent_em] [descent_em]

The defaults, 0.95 and 0.23 em, sit inside Fredoka's 0.98 and 0.24 em.
"""
import struct
import sys
from pathlib import Path


def _checksum(data: bytes) -> int:
    data += b"\0" * (-len(data) % 4)
    return sum(struct.unpack(">%dI" % (len(data) // 4), data)) & 0xFFFFFFFF


def fit(source: Path, output: Path, ascent_em: float, descent_em: float) -> None:
    font = bytearray(source.read_bytes())
    tables = {}
    for index in range(struct.unpack_from(">H", font, 4)[0]):
        entry = 12 + 16 * index
        tag, _check, offset, length = struct.unpack_from(">4sIII", font, entry)
        tables[tag.decode("latin-1")] = (entry, offset, length)
    head = tables["head"][1]
    units = struct.unpack_from(">H", font, head + 18)[0]
    ascent, descent = round(ascent_em * units), round(descent_em * units)
    struct.pack_into(">hhh", font, tables["hhea"][1] + 4, ascent, -descent, 0)
    # OS/2: typo ascender, descender and line gap, then the Windows ascent and descent.
    struct.pack_into(">hhhHH", font, tables["OS/2"][1] + 68, ascent, -descent, 0, ascent, descent)
    struct.pack_into(">I", font, head + 8, 0)
    for entry, offset, length in tables.values():
        struct.pack_into(">I", font, entry + 4, _checksum(bytes(font[offset:offset + length])))
    struct.pack_into(">I", font, head + 8, (0xB1B0AFBA - _checksum(bytes(font))) & 0xFFFFFFFF)
    output.write_bytes(bytes(font))
    print("%s: ascent %d, descent %d of %d units per em" % (output, ascent, descent, units))


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    fit(Path(sys.argv[1]), Path(sys.argv[2]), float(sys.argv[3]) if len(sys.argv) > 3 else 0.95,
        float(sys.argv[4]) if len(sys.argv) > 4 else 0.23)
