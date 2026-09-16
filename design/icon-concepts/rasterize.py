"""Turn a concept SVG into the opaque 1024px PNG that tool/generate_app_icons.py expects.

macOS has no SVG rasteriser on the command line, so QuickLook does the drawing and
the alpha channel is stripped here: the platform generators reject icons with alpha.
"""
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

SIZE = 1024


def render(svg: Path, workdir: Path) -> Path:
    subprocess.run(
        ['qlmanage', '-t', '-s', str(SIZE), '-o', str(workdir), str(svg)],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    return workdir / f'{svg.name}.png'


def read_png(path: Path):
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', f'{path} is not a PNG'
    chunks, offset, pixels = {}, 8, b''
    while offset < len(data):
        length, kind = struct.unpack('>I4s', data[offset:offset + 8])
        body = data[offset + 8:offset + 8 + length]
        if kind == b'IDAT':
            pixels += body
        else:
            chunks[kind] = body
        offset += length + 12
    width, height, depth, colour, _, _, interlace = struct.unpack(
        '>IIBBBBB', chunks[b'IHDR']
    )
    assert depth == 8 and colour == 6 and interlace == 0, 'expected 8-bit RGBA, no interlace'
    return width, height, zlib.decompress(pixels)


def unfilter(width: int, height: int, raw: bytes) -> bytearray:
    """Undo the per-scanline PNG filters, leaving flat RGBA rows."""
    stride = width * 4
    out = bytearray(stride * height)
    previous = bytearray(stride)
    position = 0
    for row in range(height):
        method = raw[position]
        line = bytearray(raw[position + 1:position + 1 + stride])
        position += stride + 1
        for i in range(stride):
            left = line[i - 4] if i >= 4 else 0
            up = previous[i]
            upleft = previous[i - 4] if i >= 4 else 0
            if method == 1:
                line[i] = (line[i] + left) & 0xFF
            elif method == 2:
                line[i] = (line[i] + up) & 0xFF
            elif method == 3:
                line[i] = (line[i] + (left + up) // 2) & 0xFF
            elif method == 4:
                estimate = left + up - upleft
                da, db, dc = (abs(estimate - left), abs(estimate - up),
                              abs(estimate - upleft))
                nearest = left if da <= db and da <= dc else (up if db <= dc else upleft)
                line[i] = (line[i] + nearest) & 0xFF
        out[row * stride:(row + 1) * stride] = line
        previous = line
    return out


def write_opaque_png(path: Path, width: int, height: int, rgba: bytearray) -> None:
    """Composite over white and drop the alpha channel."""
    body = bytearray()
    for row in range(height):
        body.append(0)  # No filter; the file is regenerated rarely.
        base = row * width * 4
        for column in range(width):
            r, g, b, a = rgba[base + column * 4:base + column * 4 + 4]
            if a != 255:
                r = (r * a + 255 * (255 - a)) // 255
                g = (g * a + 255 * (255 - a)) // 255
                b = (b * a + 255 * (255 - a)) // 255
            body += bytes((r, g, b))

    def chunk(kind: bytes, payload: bytes) -> bytes:
        return (struct.pack('>I', len(payload)) + kind + payload
                + struct.pack('>I', zlib.crc32(kind + payload) & 0xFFFFFFFF))

    path.write_bytes(
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(bytes(body), 9))
        + chunk(b'IEND', b'')
    )


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit('usage: rasterize.py <concept.svg> <destination.png>')
    svg, destination = Path(sys.argv[1]), Path(sys.argv[2])
    with tempfile.TemporaryDirectory() as workdir:
        width, height, raw = read_png(render(svg, Path(workdir)))
        write_opaque_png(destination, width, height, unfilter(width, height, raw))
    print(f'Wrote {destination} at {width}x{height}, no alpha.')


if __name__ == '__main__':
    main()
