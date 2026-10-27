// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:edupaint_flutter_study/main.dart';
import 'package:flutter/cupertino.dart' show CupertinoLocalizations;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  for (final deviceLocale in const [Locale('en', 'US'), Locale('fr', 'CA')]) {
    testWidgets(
      'French controls and modal semantics with device locale $deviceLocale',
      (tester) async {
        tester.platformDispatcher.localeTestValue = deviceLocale;
        addTearDown(tester.platformDispatcher.clearLocaleTestValue);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1100, 760);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          EduPaintApp(files: MemoryFiles(), recoveryStorage: MemoryRecovery()),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final context = tester.element(find.byType(DrawingStudio));
        expect(Localizations.localeOf(context), const Locale('fr'));
        expect(MaterialLocalizations.of(context).cancelButtonLabel, 'Annuler');
        expect(
          MaterialLocalizations.of(context).selectAllButtonLabel,
          'Tout sélectionner',
        );
        expect(CupertinoLocalizations.of(context).cancelButtonLabel, 'Annuler');
        expect(Directionality.of(context), TextDirection.ltr);

        // Exercise a real Material modal: its default accessibility barrier and
        // control labels must use the same language as the drawing interface.
        final dialog = showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Essai de langue'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(
                  MaterialLocalizations.of(dialogContext).cancelButtonLabel,
                ),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Annuler'), findsWidgets);
        expect(
          tester
              .widgetList<ModalBarrier>(find.byType(ModalBarrier))
              .any((barrier) => barrier.semanticsLabel == 'Ignorer'),
          isTrue,
        );

        // An unsupported language must not switch standard controls to a
        // language or direction that the app's French content does not support.
        tester.platformDispatcher.localeTestValue = const Locale('ar');
        await tester.pumpAndSettle();
        final dialogContext = tester.element(find.byType(AlertDialog));
        expect(Localizations.localeOf(dialogContext), const Locale('fr'));
        expect(Directionality.of(dialogContext), TextDirection.ltr);
        expect(
          MaterialLocalizations.of(dialogContext).cancelButtonLabel,
          'Annuler',
        );
        await tester.tap(find.widgetWithText(TextButton, 'Annuler').last);
        await tester.pumpAndSettle();
        await dialog;
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      skip: !available,
    );
  }
}
