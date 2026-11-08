// SPDX-License-Identifier: MIT
// The paint pot closes small gaps everywhere but in the United States and
// their territories, until 16 July 2028 included: one sign is enough, and
// no sign at all counts as one.
import 'package:edupaint_flutter_study/country_signs.dart';
import 'package:edupaint_flutter_study/paint_pot.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 2, 15);

  test('one sign of the United States is enough', () {
    expect(potClosesGaps(CountrySigns(codes: ['FR']), now), isTrue);
    expect(potClosesGaps(CountrySigns(codes: ['fr', 'BE']), now), isTrue);
    for (final code in ['US', 'usa', 'PR', 'GU', 'VI', 'AS', 'MP', 'UM']) {
      expect(
        potClosesGaps(CountrySigns(codes: ['FR', code]), now),
        isFalse,
        reason: code,
      );
    }
    for (final zone in [
      'America/New_York',
      'America/Indiana/Knox',
      'America/Kentucky/Louisville',
      'Pacific/Honolulu',
      'America/Puerto_Rico',
      'Pacific/Guam',
      'US/Pacific',
      ':America/Chicago',
    ]) {
      expect(
        potClosesGaps(CountrySigns(codes: ['FR'], timeZones: [zone]), now),
        isFalse,
        reason: zone,
      );
    }
    // Zones of other countries, close as they are, say nothing of it.
    for (final zone in [
      'America/Toronto',
      'America/Mexico_City',
      'Europe/Paris',
    ]) {
      expect(
        potClosesGaps(CountrySigns(codes: ['FR'], timeZones: [zone]), now),
        isTrue,
        reason: zone,
      );
    }
    // Nothing read yet, or nothing said: no gap closed.
    expect(potClosesGaps(null, now), isFalse);
    expect(potClosesGaps(CountrySigns(), now), isFalse);
    expect(potClosesGaps(CountrySigns(codes: [' ']), now), isFalse);
  });

  test('a zone is read as a name, as a path or as a rule', () {
    for (final zone in [
      '/usr/share/zoneinfo/America/New_York',
      ':/usr/share/zoneinfo/America/Chicago',
      '../usr/share/zoneinfo/posix/America/Denver',
      '/usr/share/zoneinfo/right/Pacific/Honolulu',
      'HST',
      'MST',
      'EST5EDT,M3.2.0,M11.1.0',
      'PST8PDT,M3.2.0,M11.1.0',
      'MST7',
      'AKST9AKDT,M3.2.0,M11.1.0',
      'HST10',
      'ChST-10',
      'SST11',
      '<EST>+5',
    ]) {
      expect(isUnitedStatesTimeZone(zone), isTrue, reason: zone);
    }
    for (final zone in [
      '/usr/share/zoneinfo/America/Toronto',
      '/usr/share/zoneinfo/posix/Europe/Paris',
      'CET-1CEST,M3.5.0,M10.5.0/3',
      'CST-8',
      'AST4',
      '<-03>3',
      'GMT+5',
      'Etc/GMT+5',
      'UTC',
      'EST',
    ]) {
      expect(isUnitedStatesTimeZone(zone), isFalse, reason: zone);
    }
    expect(zoneName(':/usr/share/zoneinfo/posix/US/Eastern'), 'US/Eastern');
    // A copy of a zone file: the rule at its end.
    List<int> zoneFile(String rule) => [
      ...'TZif2'.codeUnits,
      ...List.filled(40, 0),
      0x0a,
      ...rule.codeUnits,
      0x0a,
    ];
    expect(
      ruleOfZoneFile(zoneFile('EST5EDT,M3.2.0,M11.1.0')),
      'EST5EDT,M3.2.0,M11.1.0',
    );
    expect(ruleOfZoneFile(zoneFile('')), isNull);
    expect(ruleOfZoneFile('TZif'.codeUnits), isNull);
    expect(ruleOfZoneFile([...'Nope'.codeUnits, 0x0a, 0x41, 0x0a]), isNull);
  });

  test('the region of a locale, and of Linux when it is set', () {
    expect(regionOfLocale('fr_FR.UTF-8'), 'FR');
    expect(regionOfLocale('en-US'), 'US');
    expect(regionOfLocale('de_DE@euro'), 'DE');
    expect(regionOfLocale('zh-Hans_US'), 'US');
    expect(regionOfLocale('sr_Latn_RS'), 'RS');
    expect(regionOfLocale('en_US_POSIX'), 'US');
    expect(regionOfLocale('es-419'), isNull);
    expect(regionOfLocale('C.UTF-8'), isNull);
    expect(regionOfLocale('fr'), isNull);
    // Without a language set, Dart would say « en_US »: Linux says nothing.
    expect(linuxRegion({}), isNull);
    expect(linuxRegion({'LANG': ''}), isNull);
    expect(linuxRegion({'LANG': 'C.UTF-8'}), isNull);
    expect(linuxRegion({'LANG': 'fr_FR.UTF-8'}), 'FR');
    expect(linuxRegion({'LANG': 'fr_FR.UTF-8', 'LC_ALL': 'en_US.UTF-8'}), 'US');
  });

  test('after 16 July 2028 the pot closes gaps everywhere', () {
    final us = CountrySigns(codes: ['US']);
    expect(potClosesGaps(us, DateTime.utc(2028, 7, 16, 23, 59)), isFalse);
    // Still the 16th on Baker Island, twelve hours behind.
    expect(potClosesGaps(us, DateTime.utc(2028, 7, 17, 11, 59)), isFalse);
    expect(potClosesGaps(us, DateTime.utc(2028, 7, 17, 12)), isTrue);
    expect(potClosesGaps(null, DateTime.utc(2029, 1, 1)), isTrue);
  });

  test('the mask of a sheet and the radius of the gaps', () {
    expect(maskSizeFor(1200, 800), (1200, 800));
    final (w, h) = maskSizeFor(4000, 3000);
    expect(w * h, lessThanOrEqualTo(maxMaskPixels + 4000));
    expect(w / h, closeTo(4 / 3, .01));
    final mask = InkMask(Uint8List(0), 1200, 800, 1, 1);
    expect(potRadius(viewScale: 1, mask: mask, closesGaps: true), 8);
    expect(potRadius(viewScale: 2, mask: mask, closesGaps: true), 4);
    expect(potRadius(viewScale: .05, mask: mask, closesGaps: true), 64);
    expect(potRadius(viewScale: 1, mask: mask, closesGaps: false), 0);
    expect(mask.pixelAt(const DocumentPoint(1200, -3)), (1199, 0));
  });

  test('a zone found again is the zone poured before', () {
    final square = [
      const DocumentPoint(10, 10),
      const DocumentPoint(110, 10),
      const DocumentPoint(110, 60),
      const DocumentPoint(10, 60),
    ];
    final hole = [
      const DocumentPoint(40, 20),
      const DocumentPoint(40, 40),
      const DocumentPoint(60, 40),
      const DocumentPoint(60, 20),
    ];
    expect(evenOddArea(square, [4]), 5000);
    expect(evenOddArea([...square, ...hole], [4, 4]), 4600);
    final poured = StrokeData(
      square,
      0,
      .5,
      kind: VectorKind.contour,
      fillRgb: 0,
      look: ObjectLook.pouredZone,
    );
    final nearly = [for (final p in square) DocumentPoint(p.x + .5, p.y - .5)];
    expect(isSameZone(poured, nearly, [4], tolerance: 2), isTrue);
    // A window drawn inside it since: another zone.
    expect(
      isSameZone(poured, [...square, ...hole], [4, 4], tolerance: 2),
      isFalse,
    );
    expect(isSameZone(poured, hole, [4], tolerance: 2), isFalse);
  });

  testWidgets('under flutter test, an Apple system is not asked: no wait is '
      'left behind the test', (tester) async {
    // Asked, a Mac with no answer here left its two-second waits pending
    // when the studio closed: 28 tests of the Mac recipe stopped, 9 November.
    CountrySigns? signs;
    readCountrySigns(system: 'macos').then((read) => signs = read);
    await tester.pump();
    expect(signs, isNotNull);
    expect(signs!.timeZones, isEmpty);
  });

  test('asked, an Apple system gives its signs, the store included', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('test/country');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'signs') {
        return {
          'codes': ['US'],
          'timeZone': 'America/Puerto_Rico',
        };
      }
      return call.method == 'store' ? 'GU' : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final signs = await readCountrySigns(
      channel: channel,
      system: 'ios',
      askTheSystem: true,
    );
    expect(signs.codes, containsAll(['US', 'GU']));
    expect(signs.timeZones, contains('America/Puerto_Rico'));
  });
}
