// SPDX-License-Identifier: MIT
// Color — Alejandro San Martin Lamas — https://github.com/alejandrosml

import 'package:edupaint_flutter_study/soft_effects.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    softEffectsMotion = true;
    softEffectLog.clear();
  });

  Future<BuildContext> place(WidgetTester tester, {bool calm = false}) async {
    late BuildContext context;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: const Size(800, 600),
          disableAnimations: calm,
        ),
        child: MaterialApp(
          home: Builder(
            builder: (inner) {
              context = inner;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    return context;
  }

  testWidgets('the effects play, and go, without a trace', (tester) async {
    final context = await place(tester);
    expect(softEffectsHere(context), isTrue);
    showConfetti(context);
    showSplash(context, const Offset(100, 100), const Color(0xffe63946));
    showSparkles(context, const Offset(200, 120));
    await tester.pump();
    expect(find.byType(IgnorePointer), findsWidgets);
    expect(softEffectLog, ['confetti', 'splash', 'sparkles']);
    // Each one is short: the longest, the confetti, a second and a half.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('no effect with less motion, nor with the movement off', (
    tester,
  ) async {
    var context = await place(tester, calm: true);
    expect(softEffectsHere(context), isFalse);
    softEffectsMotion = false;
    context = await place(tester);
    expect(softEffectsHere(context), isFalse);
  });

  testWidgets('a button that bounces still answers its press', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: BounceOnPress(
            child: TextButton(
              onPressed: () => pressed++,
              child: const Text('Appuie'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Appuie'));
    await tester.pumpAndSettle();
    expect(pressed, 1);
  });
}
