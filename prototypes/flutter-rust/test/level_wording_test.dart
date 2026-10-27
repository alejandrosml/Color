// SPDX-License-Identifier: MIT
// What Color says does not send the child to a function that the chosen
// interface does not show.
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/studio_questions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<BuildContext> page(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (inner) {
            context = inner;
            return const Scaffold();
          },
        ),
      ),
    );
    return context;
  }

  String shown(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data ?? '')
      .join('\n');

  testWidgets(
    '« Garder les modifications ? » speaks of exports where they are',
    (tester) async {
      final context = await page(tester);
      showKeepChangesDialog(context);
      await tester.pumpAndSettle();
      expect(shown(tester), contains('Une image exportée'));
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
      showKeepChangesDialog(context, exports: false);
      await tester.pumpAndSettle();
      expect(shown(tester), contains('Enregistre un projet Color'));
      expect(shown(tester), isNot(contains('export')));
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('« À propos » speaks only of what the interface offers', (
    tester,
  ) async {
    final context = await page(tester);
    for (final level in InterfaceLevel.values) {
      final options = StudioOptions(level: level);
      showAboutColorDialog(
        context,
        hasGallery: true,
        version: '',
        exports: options.exports,
        layers: options.layers,
        images: options.opensFiles,
      );
      await tester.pumpAndSettle();
      final text = shown(tester);
      final where = level.code;
      expect(text, contains('Enregistrer permet de reprendre'), reason: where);
      expect(text, contains('Mes dessins range'), reason: where);
      expect(text.contains('Exporter crée'), options.exports, reason: where);
      expect(text.contains('calque caché'), options.layers, reason: where);
      expect(
        text.contains('dessiner sur une image'),
        options.opensFiles,
        reason: where,
      );
      // Sentences keep their spaces whatever is left out.
      expect(text, isNot(contains('  ')), reason: where);
      expect(text, isNot(contains(' .')), reason: where);
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
    }
  });

  test('the three levels are named for the adult who chooses', () {
    expect(InterfaceLevel.values.map((level) => level.label), [
      'Très simplifiée',
      'Moyenne',
      'Complète',
    ]);
    expect(
      InterfaceLevel.toddler.description,
      startsWith('Pour les tout-petits'),
    );
    expect(InterfaceLevel.child.description, startsWith('Pour les enfants'));
    expect(InterfaceLevel.full.description, startsWith('Pour les plus grands'));
  });
}
