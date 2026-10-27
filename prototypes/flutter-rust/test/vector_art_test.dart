// SPDX-License-Identifier: MIT
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/vector_art.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// The pixels of [picture] painted into a square of [side] pixels, four
/// bytes each: red, green, blue, alpha.
Future<Uint8List> _render(VectorPicture picture, int side) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  picture.paint(canvas, Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()));
  final image = await recorder.endRecording().toImage(side, side);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

List<int> _pixel(Uint8List bytes, int side, int x, int y) =>
    bytes.sublist((y * side + x) * 4, (y * side + x) * 4 + 4);

String _svg(String body, {String box = '0 0 100 100'}) =>
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="$box">$body</svg>';

VectorPicture _picture(String body, {String box = '0 0 100 100'}) =>
    VectorPicture.fromSvg(_svg(body, box: box))!;

void main() {
  test('the catalogue of the core gives the pictures of the interface', () {
    final catalog = VectorArtCatalog.parse(RustDocument.readArtCatalog());
    expect(catalog.keys, containsAll(['options', 'film', 'logo', 'mascotte']));
    // The small pictures on a grid of 64; the logo and the companion of the
    // window on their own of 512.
    for (final key in catalog.keys) {
      final side = key == 'logo' || key == 'mascotte' ? 512 : 64;
      expect(catalog[key]!.width, side, reason: key);
      expect(catalog[key]!.height, side, reason: key);
    }
    expect(catalog['inconnu'], isNull);
    expect(VectorArtCatalog.instance, isNotNull);
  });

  test('fills, strokes and their order are painted', () async {
    final bytes = await _render(
      _picture(
        '<rect x="20" y="20" width="60" height="60" fill="#ff0000" '
        'stroke="#0000ff" stroke-width="10"/>',
      ),
      100,
    );
    expect(_pixel(bytes, 100, 50, 50), [255, 0, 0, 255]);
    // The stroke lies over the edge of the inside, five units each side.
    expect(_pixel(bytes, 100, 22, 50), [0, 0, 255, 255]);
    expect(_pixel(bytes, 100, 17, 50), [0, 0, 255, 255]);
    expect(_pixel(bytes, 100, 10, 50), [0, 0, 0, 0]);
    final under = await _render(
      _picture(
        '<rect x="20" y="20" width="60" height="60" fill="#ff0000" '
        'stroke="#0000ff" stroke-width="10" paint-order="stroke"/>',
      ),
      100,
    );
    // Painted first, the stroke keeps only its outer half.
    expect(_pixel(under, 100, 22, 50), [255, 0, 0, 255]);
    expect(_pixel(under, 100, 17, 50), [0, 0, 255, 255]);
  });

  test('the rule of the inside is kept', () async {
    const outline = 'M10 10H90V90H10Z M30 30H70V70H30Z';
    final nonZero = await _render(_picture('<path d="$outline"/>'), 100);
    final evenOdd = await _render(
      _picture('<path d="$outline" fill-rule="evenodd"/>'),
      100,
    );
    expect(_pixel(nonZero, 100, 50, 50)[3], 255);
    expect(_pixel(evenOdd, 100, 50, 50)[3], 0);
    expect(_pixel(evenOdd, 100, 20, 50)[3], 255);
  });

  test(
    'a group is placed, and painted as a whole when it is not opaque',
    () async {
      final bytes = await _render(
        _picture(
          '<g transform="translate(50 50)" opacity="0.5">'
          '<rect width="40" height="40" fill="#ff0000"/>'
          '<rect x="20" width="20" height="40" fill="#ff0000"/></g>',
        ),
        100,
      );
      expect(_pixel(bytes, 100, 25, 25)[3], 0);
      // Where the two shapes overlap the group is not darker: one layer.
      final once = _pixel(bytes, 100, 60, 70);
      final twice = _pixel(bytes, 100, 80, 70);
      expect(once[3], closeTo(128, 2));
      expect(twice, once);
    },
  );

  test('clips narrow what their group shows', () async {
    final bytes = await _render(
      _picture(
        '<defs><clipPath id="c"><rect width="50" height="100"/>'
        '<rect x="80" width="20" height="100"/></clipPath></defs>'
        '<rect width="100" height="100" fill="#00ff00" clip-path="url(#c)"/>',
      ),
      100,
    );
    expect(_pixel(bytes, 100, 25, 50), [0, 255, 0, 255]);
    expect(_pixel(bytes, 100, 65, 50)[3], 0);
    expect(_pixel(bytes, 100, 90, 50), [0, 255, 0, 255]);
    final nested = await _render(
      _picture(
        '<defs><clipPath id="a"><rect width="50" height="100"/></clipPath>'
        '<clipPath id="b" clip-path="url(#a)"><rect x="25" width="50" '
        'height="100"/></clipPath></defs>'
        '<rect width="100" height="100" clip-path="url(#b)"/>',
      ),
      100,
    );
    expect(_pixel(nested, 100, 12, 50)[3], 0);
    expect(_pixel(nested, 100, 37, 50)[3], 255);
    expect(_pixel(nested, 100, 62, 50)[3], 0);
  });

  test('gradients run where the file says', () async {
    final linear = await _render(
      _picture(
        '<defs><linearGradient id="g"><stop offset="0" stop-color="#ff0000"/>'
        '<stop offset="1" stop-color="#0000ff"/></linearGradient></defs>'
        '<rect width="100" height="100" fill="url(#g)"/>',
      ),
      100,
    );
    final left = _pixel(linear, 100, 5, 50);
    final right = _pixel(linear, 100, 95, 50);
    expect(left[0], greaterThan(220));
    expect(left[2], lessThan(35));
    expect(right[2], greaterThan(220));
    expect(right[0], lessThan(35));
    // The same colour all the way down a column.
    expect(_pixel(linear, 100, 50, 10), _pixel(linear, 100, 50, 90));
    final radial = await _render(
      _picture(
        '<defs><radialGradient id="g" gradientUnits="userSpaceOnUse" cx="50" '
        'cy="50" r="50"><stop offset="0" stop-color="#ffffff"/>'
        '<stop offset="1" stop-color="#000000"/></radialGradient></defs>'
        '<rect width="100" height="100" fill="url(#g)"/>',
      ),
      100,
    );
    expect(_pixel(radial, 100, 50, 50)[0], greaterThan(240));
    expect(_pixel(radial, 100, 50, 2)[0], lessThan(25));
    expect(_pixel(radial, 100, 2, 50)[0], lessThan(25));
  });

  test('a picture keeps its proportions in the middle of its box', () async {
    final picture = _picture(
      '<rect width="200" height="100" fill="#ff0000"/>',
      box: '0 0 200 100',
    );
    expect(picture.width, 200);
    expect(picture.height, 100);
    final bytes = await _render(picture, 100);
    // Half as high as wide: a band across the middle of the square.
    expect(_pixel(bytes, 100, 50, 50), [255, 0, 0, 255]);
    expect(_pixel(bytes, 100, 2, 50), [255, 0, 0, 255]);
    expect(_pixel(bytes, 100, 50, 10)[3], 0);
    expect(_pixel(bytes, 100, 50, 90)[3], 0);
  });

  test('what the core refuses gives no picture', () {
    expect(VectorPicture.fromSvg('bonjour'), isNull);
    expect(VectorPicture.fromSvg(_svg('<text>a</text>')), isNull);
    expect(
      VectorPicture.fromSvg(
        _svg(
          '<defs><filter id="f"><feGaussianBlur stdDeviation="2"/></filter>'
          '</defs><rect width="10" height="10" filter="url(#f)"/>',
        ),
      ),
      isNull,
    );
    expect(RustDocument.describeSvg(''), isNull);
  });

  test('a description that is not one is refused, never half read', () {
    for (final text in [
      'D f #000000ff,n - M 0 0 L 1 1\nX\n',
      'P a 10 10\nD f #000000ff,n - M 0 0 L 1 1\n',
      'P a 10 10\nG 1 -\nX\n',
      'P a 10 10\nE\nX\n',
      'P a 0 10\nX\n',
      'P a 10 10\nD f - - M 0 0 L 1 1\nX\n',
      'P a 10 10\nD f #12345,n - M 0 0\nX\n',
      'P a 10 10\nD f #000000ff,n - M 0 zero\nX\n',
      'P a 10 10\nD f #000000ff,x - M 0 0\nX\n',
      'P a 10 10\nC\nX\n',
      'P a 10 10\nK n M 0 0\nX\n',
      'P a 10 10\nD f L:0:0:1:0:p:-:0=#000000ff/0.5,n - M 0 0\nX\n',
      'P a 10 10\nZ\nX\n',
    ]) {
      expect(
        () => VectorPicture.parseAll(text),
        throwsFormatException,
        reason: text,
      );
    }
    expect(VectorPicture.parseAll(''), isEmpty);
  });

  test('a picture ends at its own edges', () async {
    // A rectangle far wider than the picture, painted into the middle of a
    // larger canvas: nothing of it shows beside the picture.
    final picture = _picture(
      '<rect x="-500" y="-500" width="1200" height="1200" fill="#ff0000"/>',
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    picture.paint(canvas, const Rect.fromLTWH(100, 100, 100, 100));
    final image = await recorder.endRecording().toImage(300, 300);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    image.dispose();
    expect(_pixel(bytes, 300, 150, 150), [255, 0, 0, 255]);
    expect(_pixel(bytes, 300, 105, 195), [255, 0, 0, 255]);
    for (final (x, y) in [
      (50, 150),
      (250, 150),
      (150, 50),
      (150, 250),
      (95, 95),
    ]) {
      expect(_pixel(bytes, 300, x, y), [0, 0, 0, 0], reason: '$x, $y');
    }
  });

  test('a gradient of two circles at the origin is painted', () async {
    // As the core describes a radial gradient placed by its matrix alone:
    // both circles at the origin. The engine refuses that as it stands.
    final pictures = VectorPicture.parseAll(
      'P a 100 100\n'
      'D f R:0:0:50:0:0:10:p:1;0;0;1;50;50:0=#ff0000ff/1=#0000ffff,n - '
      'M 0 0 L 100 0 L 100 100 L 0 100 Z\n'
      'X\n',
    );
    final bytes = await _render(pictures.single, 100);
    // Red inside the small circle, around the middle of the picture; blue
    // at the edge of the large one and beyond.
    expect(_pixel(bytes, 100, 50, 50), [255, 0, 0, 255]);
    expect(_pixel(bytes, 100, 55, 50), [255, 0, 0, 255]);
    final outer = _pixel(bytes, 100, 98, 50);
    expect(outer[2], greaterThan(240));
    expect(outer[0], lessThan(15));
    // Half way between the two circles, half way between the two colours.
    final middle = _pixel(bytes, 100, 80, 50);
    expect(middle[0], inInclusiveRange(100, 155));
    expect(middle[2], inInclusiveRange(100, 155));
    // The same gradient from the SVG itself goes the same way.
    final viaCore = await _render(
      _picture(
        '<defs><radialGradient id="g" cx="0" cy="0" r="50" fx="0" fy="0" fr="10" '
        'gradientUnits="userSpaceOnUse" gradientTransform="translate(50 50)">'
        '<stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff"/>'
        '</radialGradient></defs><rect width="100" height="100" fill="url(#g)"/>',
      ),
      100,
    );
    expect(_pixel(viaCore, 100, 50, 50), [255, 0, 0, 255]);
    expect(_pixel(viaCore, 100, 98, 50)[2], greaterThan(240));
  });

  test('one picture that cannot be read does not lose the others', () {
    const good = 'D f #000000ff,n - M 0 0 L 1 0 L 1 1 Z\nX\n';
    final text =
        'P one 10 10\n$good'
        'P broken 10 10\nD f #12345,n - M 0 0\nX\n'
        'P two 10 10\n$good'
        'P cut 10 10\nD f #000000ff,n - M 0 0 L 1 0';
    expect(() => VectorPicture.parseAll(text), throwsFormatException);
    expect(VectorPicture.parseEach(text).map((picture) => picture.key), [
      'one',
      'two',
    ]);
    final catalog = VectorArtCatalog.parse(text);
    expect(catalog.keys, ['one', 'two']);
    expect(VectorPicture.parseEach(''), isEmpty);
  });

  test('a line has no inside, whatever its fill says', () async {
    // Dashes with gaps: nothing is painted in the gaps.
    final bytes = await _render(
      _picture(
        '<line x1="10" y1="50" x2="90" y2="50" stroke="#ff0000" stroke-width="10" '
        'stroke-dasharray="20 20" fill="#000000"/>',
      ),
      100,
    );
    expect(_pixel(bytes, 100, 20, 50), [255, 0, 0, 255]);
    expect(_pixel(bytes, 100, 40, 50), [0, 0, 0, 0]);
    expect(_pixel(bytes, 100, 60, 50), [255, 0, 0, 255]);
  });
}
