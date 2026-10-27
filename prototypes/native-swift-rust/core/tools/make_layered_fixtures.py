#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Independent encoder of project version 4 and version 5 fixtures.

Written from the format description in include/edupaint_core.h with the Python
standard library only (struct, zlib): it shares no code with the Rust core, so
the core's acceptance and byte-exact re-serialization of these files check the
format rather than one implementation against itself.

Every file, of version 4 or version 5 (locked layers, closed contours), goes
into the core fixtures and into the Flutter test fixtures, with its description
in both manifests: since 0.7.5 the interface reads version 5 as the core does,
and both sets stay the same, byte for byte. A file or a manifest whose content
would not change is not written again, so that a run touches nothing it does
not change.
"""
import hashlib
import json
import pathlib
import struct
import zlib

CORE = pathlib.Path(__file__).resolve().parent.parent
TARGETS = [
    CORE / "test-fixtures/import-project",
    CORE.parent.parent / "flutter-rust/test/fixtures/project-open",
]
FREEHAND, LINE, RECTANGLE, ELLIPSE, TEXT, STAMP, CONTOUR = range(7)
# Flags of a layer in version 5; version 4 knows the visibility bit only.
VISIBLE, LOCKED = 1, 2
GENERATOR = "tools/make_layered_fixtures.py, independent of the Rust core"


def record(rgb, width, kind, points, layer, fill=None, param=0, text=b""):
    body = struct.pack("<IfIIIIIII", rgb, width, len(points), kind,
                       0 if fill is None else 1, fill or 0, layer, param, len(text))
    for x, y in points:
        body += struct.pack("<ff", x, y)
    return body + text


def project(width, height, layers, active, objects, background=b"", version=4):
    # A layer is (identifier, flags); True and False are the flags 1 and 0.
    table = b"".join(struct.pack("<II", ident, int(flags)) for ident, flags in layers)
    body = b"".join(objects)
    points = sum(struct.unpack_from("<I", o, 8)[0] for o in objects)
    text = sum(struct.unpack_from("<I", o, 32)[0] for o in objects)
    total = 56 + len(table) + len(body) + len(background) + 4
    header = b"EDUPAINT" + struct.pack("<HH", version, 0) + struct.pack(
        "<11I", total, width, height, len(objects), points, len(background),
        len(layers), text, active, 0, 0)
    payload = header + table + body + background
    return payload + struct.pack("<I", zlib.crc32(payload) & 0xFFFFFFFF)


def announced(data, version):
    """The same bytes announcing another version, checksum repaired."""
    changed = bytearray(data)
    struct.pack_into("<H", changed, 8, version)
    struct.pack_into("<I", changed, len(changed) - 4, zlib.crc32(bytes(changed[:-4])) & 0xFFFFFFFF)
    return bytes(changed)


def version_4_cases(source):
    png = (source / "rgb.png").read_bytes()
    words = "Été 🎨\n2 < 3 & 4".encode("utf-8")
    layered = project(800, 1200, [(0, True), (2, False), (1, True)], 1, [
        record(0x112233, 2.0, FREEHAND, [(10, 20), (30.5, 40.25), (800, 1200)], 0),
        record(0x445566, 4.0, RECTANGLE, [(100, 120), (20, 30)], 2, fill=0xAABBCC),
        record(0x336699, 40.0, TEXT, [(100, 200), (500, 296)], 1, text=words),
        record(0x477FB2, 1.0, STAMP, [(300, 600), (500, 800)], 1, param=8),
        record(0x778899, 5.0, ELLIPSE, [(700, 100), (600, 300)], 0),
    ])
    on_image = project(32, 24, [(0, True)], 0, [
        record(0xD75E56, 8.0, TEXT, [(2, 2), (20, 11.5)], 0, text=b"ok"),
    ], background=png)
    unknown_stamp = project(800, 1200, [(0, True)], 0, [
        record(0x477FB2, 1.0, STAMP, [(300, 600), (500, 800)], 0, param=60000),
    ])
    duplicate_layers = project(800, 1200, [(0, True), (0, True)], 0, [
        record(0x112233, 2.0, FREEHAND, [(10, 20)], 0),
    ])
    control_text = project(800, 1200, [(0, True)], 0, [
        record(0x336699, 40.0, TEXT, [(100, 200), (500, 296)], 0, text=b"tab\there"),
    ])
    # The same body as the historic version 2 portrait, announced as version 5.
    portrait = announced((source / "portrait-v2.edupaint").read_bytes(), 5)
    return [
        ("layers-text-stamp-v4.edupaint", layered, True,
         "Three layers in stack order 0, 2 (hidden), 1; active layer 1; freehand, filled rectangle, "
         "two-line text with escapes and an emoji, stamp 8, ellipse."),
        ("text-on-image-v4.edupaint", on_image, True, "One text over the rgb.png background."),
        ("unknown-stamp-v4.edupaint", unknown_stamp, False, "Stamp identifier 60000 is not in any catalogue."),
        ("duplicate-layers-v4.edupaint", duplicate_layers, False, "The layer table names identifier 0 twice."),
        ("control-text-v4.edupaint", control_text, False, "A tabulation inside the characters of a text."),
        ("unknown-version-5.edupaint", portrait, False,
         "Valid checksum and version 2 body announced as version 5. The historic unknown-version file "
         "announces version 4, which now exists and rejects it as a malformed version 4 file."),
    ]


def version_5_cases(source):
    ink, white = 0x2F3D4A, 0xFFFFFF
    pentagon = [(200, 100), (300, 170), (260, 290), (140, 290), (100, 170)]
    house = [(400, 100), (600, 300)]
    # A colouring page with something drawn on it: zones under the drawing,
    # lines over it, both locked; a hidden layer and a hidden locked one.
    stack = [(1, VISIBLE | LOCKED), (0, VISIBLE), (3, 0), (4, LOCKED), (2, VISIBLE | LOCKED)]
    objects = [
        record(white, 0.1, CONTOUR, pentagon, 1, fill=white),
        record(white, 0.1, RECTANGLE, house, 1, fill=white),
        record(0xD75E56, 12.0, FREEHAND, [(150, 150), (250, 250), (180, 260)], 0),
        record(0x336699, 4.0, CONTOUR, [(700, 400), (900, 420.5), (820, 600), (690, 560)], 0,
               fill=0xAABBCC),
        record(0x477FB2, 1.0, STAMP, [(800, 100), (900, 200)], 3, param=3),
        record(0x112233, 2.0, ELLIPSE, [(1000, 600), (1100, 700)], 4),
        record(ink, 6.0, CONTOUR, pentagon, 2),
        record(ink, 6.0, RECTANGLE, house, 2),
        record(ink, 6.0, FREEHAND, [(450, 250), (500, 220), (550, 250)], 2),
    ]
    page = project(1200, 800, stack, 0, objects, version=5)
    locked_active = project(1200, 800, stack, 1, objects, version=5)
    unknown_flag = project(1200, 800, [(0, VISIBLE), (1, VISIBLE | 4)], 0, [
        record(0x112233, 2.0, FREEHAND, [(10, 20)], 0),
    ], version=5)
    flat = project(1200, 800, [(0, VISIBLE)], 0, [
        record(ink, 6.0, CONTOUR, [(100, 100), (200, 100), (300, 100)], 0),
    ], version=5)
    short = project(1200, 800, [(0, VISIBLE)], 0, [
        record(ink, 6.0, CONTOUR, [(100, 100), (200, 200)], 0),
    ], version=5)
    contour_in_v4 = project(1200, 800, [(0, VISIBLE), (1, VISIBLE)], 0, [
        record(ink, 6.0, CONTOUR, pentagon, 1, fill=white),
    ])
    locked_in_v4 = project(1200, 800, [(0, VISIBLE), (1, VISIBLE | LOCKED)], 0, [
        record(ink, 6.0, RECTANGLE, house, 1),
    ])
    # Version 5 that needs nothing of it: read, and written back as version 4.
    plain_objects = [
        record(0x112233, 2.0, FREEHAND, [(10, 20), (30, 40)], 0),
        record(0x336699, 40.0, TEXT, [(100, 200), (500, 296)], 1, text=b"cinq"),
    ]
    plain_stack = [(0, VISIBLE), (1, 0)]
    layers_only = project(1200, 800, plain_stack, 1, plain_objects, version=5)
    layers_only_v4 = project(1200, 800, plain_stack, 1, plain_objects, version=4)
    portrait = announced((source / "portrait-v2.edupaint").read_bytes(), 6)
    return [
        ("locked-page-v5.edupaint", page, True,
         "A colouring page with a drawing: layers 1 (zones, locked), 0 (active), 3 (hidden), "
         "4 (hidden and locked), 2 (lines, locked); a filled contour and a rectangle as zones, "
         "a freehand stroke and a filled contour drawn on layer 0, a stamp, an ellipse, the "
         "contour and the rectangle again as lines, a freehand detail.", None),
        ("layers-only-v5.edupaint", layers_only, True,
         "Version 5 without a locked layer or a contour: accepted and written back as version 4.",
         layers_only_v4),
        ("locked-active-v5.edupaint", locked_active, False,
         "The page of locked-page-v5 with the locked layer 1 as active layer.", None),
        ("layer-flags-v5.edupaint", unknown_flag, False, "Layer flags 5: bit 2 is unknown.", None),
        ("flat-contour-v5.edupaint", flat, False,
         "A contour whose three points lie on one horizontal line.", None),
        ("short-contour-v5.edupaint", short, False, "A contour of two points.", None),
        ("contour-in-v4.edupaint", contour_in_v4, False,
         "A valid filled contour in a version 4 file, which knows no contour.", None),
        ("locked-in-v4.edupaint", locked_in_v4, False,
         "Layer flags 3 (visible, locked) in a version 4 file, which knows the visibility bit only.",
         None),
        ("unknown-version-6.edupaint", portrait, False,
         "Valid checksum and version 2 body announced as version 6. Version 5 exists now: "
         "unknown-version-5 is rejected as a malformed version 5 file.", None),
    ]


def write_if_changed(path, data):
    if not path.exists() or path.read_bytes() != data:
        path.write_bytes(data)


def update(target, cases):
    manifest_path = target / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    known = {case["file"] for case in manifest["cases"]}
    for name, data, accepted, note, normalized in cases:
        write_if_changed(target / name, data)
        entry = {"file": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
                 "native_accept": accepted, "note": note, "generator": GENERATOR}
        if accepted:
            # Canonical output is these exact bytes, unless an older version suffices.
            expected = data if normalized is None else normalized
            write_if_changed(target / (name + ".normalized"), expected)
            entry.update(expected_project=name + ".normalized", expected_bytes=len(expected),
                         expected_sha256=hashlib.sha256(expected).hexdigest())
        if name in known:
            manifest["cases"] = [entry if case["file"] == name else case for case in manifest["cases"]]
        else:
            manifest["cases"].append(entry)
    manifest["native_accept_count"] = sum(1 for case in manifest["cases"] if case["native_accept"])
    manifest["native_reject_count"] = sum(1 for case in manifest["cases"] if not case["native_accept"])
    manifest["total_case_bytes"] = sum(case["bytes"] for case in manifest["cases"])
    text = json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    if manifest_path.read_text() != text:
        manifest_path.write_text(text)


def main():
    source = TARGETS[0]
    cases = [case + (None,) for case in version_4_cases(source)] + version_5_cases(source)
    for target in TARGETS:
        update(target, cases)
    for name, data, accepted, _, _ in cases:
        print(f"{name}: {len(data)} bytes, accept={accepted}")


if __name__ == "__main__":
    main()
