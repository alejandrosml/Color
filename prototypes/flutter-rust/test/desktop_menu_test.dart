// SPDX-License-Identifier: MIT
// The menus that Color gives to the menu bar of the Mac: the same commands
// as the buttons of the studio, with the keys that a Mac expects.
import 'package:edupaint_flutter_study/desktop_menu.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The entries of one menu, the members of its groups included, in order.
  List<PlatformMenuItem> entries(PlatformMenu menu) => [
    for (final item in menu.menus)
      if (item is PlatformMenuItemGroup) ...item.members else item,
  ];

  PlatformMenu menuNamed(WidgetTester tester, String label) => tester
      .widget<PlatformMenuBar>(find.byType(PlatformMenuBar))
      .menus
      .whereType<PlatformMenu>()
      .singleWhere((menu) => menu.label == label);

  testWidgets('on the Mac the Fichier menu ends with Imprimer…, on ⌘P', (
    tester,
  ) async {
    var printed = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: EduPaintDesktopMenu(
          onPrint: () => printed++,
          onNew: () {},
          hasGallery: true,
          child: const SizedBox.shrink(),
        ),
      ),
    );
    final file = entries(menuNamed(tester, 'Fichier'));
    expect(file.map((item) => item.label), [
      'Nouveau',
      'Ouvrir…',
      'Mes dessins…',
      'Enregistrer',
      'Dessiner sur une image…',
      'Enregistrer sous…',
      'Exporter PNG…',
      'Exporter SVG…',
      'Imprimer…',
    ]);
    final print = file.last;
    expect(
      print.shortcut,
      isA<SingleActivator>()
          .having((keys) => keys.trigger, 'key', LogicalKeyboardKey.keyP)
          .having((keys) => keys.meta, 'meta', isTrue)
          .having((keys) => keys.shift, 'shift', isFalse)
          .having((keys) => keys.control, 'control', isFalse),
    );
    // It stands apart from the exports, under its own separator.
    expect(
      menuNamed(tester, 'Fichier').menus.last,
      isA<PlatformMenuItemGroup>(),
    );
    print.onSelected!();
    expect(printed, 1);
    // No two commands of the menus share their keys.
    final keys = <String>{};
    for (final menu
        in tester
            .widget<PlatformMenuBar>(find.byType(PlatformMenuBar))
            .menus
            .whereType<PlatformMenu>()) {
      for (final item in entries(menu)) {
        final shortcut = item.shortcut;
        if (shortcut is SingleActivator) {
          final name =
              '${shortcut.meta}/${shortcut.shift}/${shortcut.control}/${shortcut.alt}/${shortcut.trigger.keyId}';
          expect(keys.add(name), isTrue, reason: item.label);
        }
      }
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a studio that cannot print now greys the entry', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: EduPaintDesktopMenu(child: SizedBox.shrink()),
      ),
    );
    final print = entries(menuNamed(tester, 'Fichier'))
        .singleWhere((item) => item.label == 'Imprimer…');
    expect(print.onSelected, isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'elsewhere there is no menu bar: the buttons and the keys do it',
    (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: EduPaintDesktopMenu(
            onPrint: () {},
            child: const SizedBox.shrink(),
          ),
        ),
      );
      expect(find.byType(PlatformMenuBar), findsNothing);
      expect(defaultTargetPlatform, isNot(TargetPlatform.macOS));
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.linux,
      TargetPlatform.windows,
    }),
  );
}
