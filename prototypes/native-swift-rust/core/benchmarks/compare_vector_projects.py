#!/usr/bin/env python3
"""Compare old/new C ABI project and SVG bytes, without Flutter or file mutation."""
import ctypes as c
import hashlib
import json
from pathlib import Path
import sys

libs = [c.CDLL(str(Path(path).resolve())) for path in sys.argv[1:3]]
for lib in libs:
    lib.ep_document_from_project.argtypes = [c.c_void_p, c.c_size_t, c.POINTER(c.c_int32)]
    lib.ep_document_from_project.restype = c.c_void_p
    lib.ep_project_size.argtypes = [c.c_void_p]
    lib.ep_project_size.restype = c.c_size_t
    lib.ep_copy_project.argtypes = [c.c_void_p, c.c_void_p, c.c_size_t]
    lib.ep_copy_project.restype = c.c_int32
    lib.ep_export_svg.argtypes = [c.c_void_p]
    lib.ep_export_svg.restype = c.c_void_p
    lib.ep_string_free.argtypes = [c.c_void_p]
    lib.ep_document_free.argtypes = [c.c_void_p]
results = []
for file in sys.argv[3:]:
    data = Path(file).read_bytes()
    source = c.create_string_buffer(data)
    outputs = []
    for lib in libs:
        status = c.c_int32(77)
        doc = lib.ep_document_from_project(source, len(data), c.byref(status))
        assert doc and status.value == 0
        try:
            size = lib.ep_project_size(doc)
            dest = c.create_string_buffer(size)
            assert lib.ep_copy_project(doc, dest, size) == 0
            pointer = lib.ep_export_svg(doc)
            assert pointer
            try:
                svg = c.string_at(pointer)
            finally:
                lib.ep_string_free(pointer)
            outputs.append((dest.raw, svg))
        finally:
            lib.ep_document_free(doc)
    assert outputs[0] == outputs[1]
    version = int.from_bytes(data[8:10], 'little')
    if version == 2:
        assert outputs[1][0] == data
    results.append(dict(fixture=file, source_version=version,
        input_sha256=hashlib.sha256(data).hexdigest(),
        serialized_sha256=hashlib.sha256(outputs[1][0]).hexdigest(),
        svg_sha256=hashlib.sha256(outputs[1][1]).hexdigest(),
        stable_and_candidate_identical=True,
        input_unchanged=Path(file).read_bytes() == data))
print(json.dumps(dict(status='passed', projects=results), indent=2))
