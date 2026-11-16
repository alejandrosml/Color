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

  testWidgets('the studio may go, or change, while they play: no exception, '
      'nothing left, and a press goes through them', (tester) async {
    // A press under the confetti, the splash and the sparkles reaches the
    // button they cover; a dialogue opens over them and closes.
    var pressed = 0;
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (inner) {
            context = inner;
            return Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: () => pressed++,
                child: const Text('Dessous'),
              ),
            );
          },
        ),
      ),
    );
    final under = tester.getCenter(find.text('Dessous'));
    showConfetti(context);
    showSplash(context, under, const Color(0xffe63946));
    showSparkles(context, under);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tapAt(under);
    expect(pressed, 1);
    showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(title: Text('Un dialogue')),
    );
    await tester.pump(const Duration(milliseconds: 100));
    Navigator.of(context, rootNavigator: true).pop();
    await tester.pump(const Duration(milliseconds: 100));
    // The window is destroyed in the middle of them.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
    // And again, to their end, in a studio that is built again meanwhile.
    softEffectLog.clear();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (inner) {
            context = inner;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    int layers() => tester.widgetList(find.byType(IgnorePointer)).length;
    final without = layers();
    showConfetti(context);
    await tester.pump(const Duration(milliseconds: 300));
    expect(layers(), without + 1);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(layers(), without, reason: 'the confetti are gone');
    expect(tester.takeException(), isNull);
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
