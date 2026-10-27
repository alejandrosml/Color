// SPDX-License-Identifier: MIT
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:edupaint_flutter_study/brush_width_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const semanticsKey = Key('brushWidthSemantics');

  testWidgets('click, drag and keyboard change document units', (tester) async {
    double value = 12;
    await tester.pumpWidget(MaterialApp(home: StatefulBuilder(builder: (context, setState) =>
      Center(child: SizedBox(width: 140, child: BrushWidthControl(
        value: value, onChanged: (next) => setState(() => value = next),
      ))))));
    final control = find.byKey(semanticsKey);
    expect(tester.getSize(control), const Size(140, 48));
    await tester.tapAt(tester.getCenter(control));
    await tester.pumpAndSettle();
    expect(value, 25);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(value, 26);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(value, 25);
    await tester.dragFrom(tester.getCenter(control), const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(value, greaterThan(25));
    expect(value, lessThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('accessible slider exposes units and bounded adjustment actions', (tester) async {
    final handle = tester.ensureSemantics();
    try {
    double value = 47;
    await tester.pumpWidget(MaterialApp(home: StatefulBuilder(builder: (context, setState) =>
      Center(child: SizedBox(width: 140, child: BrushWidthControl(
        value: value, onChanged: (next) => setState(() => value = next),
      ))))));
    var node = tester.getSemantics(find.byKey(semanticsKey));
    var data = node.getSemanticsData();
    expect(data.flagsCollection.isSlider, isTrue);
    expect(data.label, 'Épaisseur du pinceau');
    expect(data.value, '47 unités de document');
    expect(data.increasedValue, '48 unités de document');
    expect(data.decreasedValue, '46 unités de document');
    expect(data.hasAction(SemanticsAction.increase), isTrue);
    node.owner!.performAction(node.id, SemanticsAction.increase);
    await tester.pumpAndSettle();
    expect(value, 48);
    node = tester.getSemantics(find.byKey(semanticsKey));
    data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.increase), isFalse);
    node.owner!.performAction(node.id, SemanticsAction.focus);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(value, 48);
    for (var i = 0; i < 50; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
    }
    expect(value, 2);
    data = tester.getSemantics(find.byKey(semanticsKey)).getSemanticsData();
    expect(data.value, '2 unités de document');
    expect(data.hasAction(SemanticsAction.decrease), isFalse);
    expect(data.hasAction(SemanticsAction.increase), isTrue);
    } finally { handle.dispose(); }
  });

  testWidgets('disabled control cannot change by pointer, keyboard or semantics', (tester) async {
    final handle = tester.ensureSemantics();
    try {
    await tester.pumpWidget(const MaterialApp(home: Center(child: SizedBox(
      width: 90, child: BrushWidthControl(value: 12, onChanged: null),
    ))));
    final control = find.byKey(semanticsKey);
    await tester.tap(control);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final data = tester.getSemantics(control).getSemanticsData();
    expect(data.value, '12 unités de document');
    expect(data.flagsCollection.isEnabled, Tristate.isFalse);
    expect(data.hasAction(SemanticsAction.increase), isFalse);
    expect(data.hasAction(SemanticsAction.decrease), isFalse);
    expect(data.hasAction(SemanticsAction.focus), isFalse);
    expect(tester.takeException(), isNull);
    } finally { handle.dispose(); }
  });
}
