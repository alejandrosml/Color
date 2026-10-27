#!/usr/bin/env python3
"""Generate the reproducible 4096x4096 RGBA PNG used by background_cost.rs.

The valid deflate stream uses level 0 to exercise a 64 MiB immutable asset,
without relying on platform image libraries. This is not a photo compression
benchmark. Decoding pixels is deliberately outside the Rust benchmark.
"""
from pathlib import Path
import hashlib
import json
import struct
import sys
import zlib

out = Path(sys.argv[1])
def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
compress = zlib.compressobj(level=0)
encoded = bytearray()
for y in range(4096):
    row = bytearray([0])
    for x in range(4096):
        row.extend(((x * 13 + y * 31) & 255, (x * 7 + y * 3) & 255,
                    (x * 19 + y * 23) & 255, 255))
    encoded.extend(compress.compress(row))
encoded.extend(compress.flush())
png = bytes.fromhex('89504e470d0a1a0a') + chunk(b'IHDR', struct.pack('>IIBBBBB', 4096, 4096, 8, 6, 0, 0, 0)) + chunk(b'IDAT', encoded) + chunk(b'IEND', b'')
out.write_bytes(png)
assert len(zlib.decompress(encoded)) == (4096 * 4 + 1) * 4096
print(json.dumps(dict(path=str(out), width=4096, height=4096, bytes=len(png),
    sha256=hashlib.sha256(png).hexdigest(), decoder='Python zlib; scanline length verified'), indent=2))
