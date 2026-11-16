// SPDX-License-Identifier: MIT
// Color — Alejandro San Martin Lamas — https://github.com/alejandrosml
import 'package:edupaint_flutter_study/french.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a mark of French punctuation stays with its word', () {
    expect(
      keptTogether('Le savais-tu ? Elle mange : des feuilles ! « Oui » ; non'),
      'Le savais-tu ? Elle mange : des feuilles ! '
      '« Oui » ; non',
    );
    expect(
      keptTogether('Did you know? It eats: leaves!'),
      'Did you know? It eats: leaves!',
    );
    expect(keptTogether('déjà : rien'), 'déjà : rien');
  });
}
