// SPDX-License-Identifier: MIT
// Where the device says it is, for the one thing that depends on it: the
// paint pot closes small gaps everywhere but in the United States and their
// territories until 16 July 2028 included, while a patent of Adobe on gap
// detection (US7613341B1) is in force there. The owner's choice, 2 November
// 2026. One sign of the United States is enough; no sign at all, or signs
// not yet read, count as one: the pot then fills without closing a gap.
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

/// What the device says of the country it is used in: country codes (the
/// region of the system, the store's country, the SIM's and the network's)
/// and the time zones it is set to.
class CountrySigns {
  CountrySigns({
    Iterable<String> codes = const [],
    Iterable<String> timeZones = const [],
  }) : codes = Set.unmodifiable({
         for (final code in codes)
           if (code.trim().isNotEmpty) code.trim().toUpperCase(),
       }),
       timeZones = Set.unmodifiable({
         for (final zone in timeZones)
           if (zone.trim().isNotEmpty) zone.trim(),
       });

  final Set<String> codes;
  final Set<String> timeZones;

  /// The United States and their territories, in two letters and three:
  /// Puerto Rico, Guam, the Virgin Islands, American Samoa, the Northern
  /// Mariana Islands and the minor outlying islands.
  static const unitedStatesCodes = {
    'US', 'USA', 'PR', 'PRI', 'GU', 'GUM', 'VI', 'VIR', //
    'AS', 'ASM', 'MP', 'MNP', 'UM', 'UMI',
  };

  /// Whether these signs point to the United States: one of them is
  /// enough, and a device that says nothing at all counts as there.
  bool get pointToUnitedStates =>
      (codes.isEmpty && timeZones.isEmpty) ||
      codes.any(unitedStatesCodes.contains) ||
      timeZones.any(isUnitedStatesTimeZone);
}

/// Time zones of the United States and their territories, by the names of
/// the IANA database, old names included. Those that other countries share
/// are not here (a Canadian zone is America/Toronto, not America/New_York).
const _unitedStatesZones = {
  'America/New_York', 'America/Detroit', 'America/Chicago', //
  'America/Menominee', 'America/Denver', 'America/Boise', 'America/Phoenix',
  'America/Los_Angeles', 'America/Anchorage', 'America/Juneau',
  'America/Sitka', 'America/Metlakatla', 'America/Yakutat', 'America/Nome',
  'America/Adak', 'America/Atka', 'America/Fort_Wayne', 'America/Indianapolis',
  'America/Knox_IN', 'America/Louisville', 'America/Shiprock', 'Navajo',
  'Pacific/Honolulu', 'Pacific/Johnston', 'America/Puerto_Rico',
  'America/St_Thomas', 'America/Virgin', 'Pacific/Guam', 'Pacific/Saipan',
  'Pacific/Pago_Pago', 'Pacific/Samoa', 'Pacific/Midway', 'Pacific/Wake',
  'EST5EDT', 'CST6CDT', 'MST7MDT', 'PST8PDT', 'HST', 'MST',
};

/// The standard times of a rule of POSIX (« EST5EDT,M3.2.0,M11.1.0 »)
/// that only the United States and their territories keep, with their
/// hours behind UTC: those of the mainland are kept by Canada too, which
/// such a rule cannot tell apart — it then counts as a sign.
const _unitedStatesStandardTimes = {
  'EST': 5, 'CST': 6, 'MST': 7, 'PST': 8, 'AKST': 9, 'HST': 10, //
  'SST': 11, 'CHST': -10,
};

/// Whether [zone] is a time zone of the United States or their
/// territories: a name of the IANA database, as such or as a path to its
/// file (« :/usr/share/zoneinfo/America/New_York », its « posix/ » and
/// « right/ » copies too), or a rule of POSIX.
bool isUnitedStatesTimeZone(String zone) {
  final name = zoneName(zone);
  if (_unitedStatesZones.contains(name) ||
      name.startsWith('US/') ||
      name.startsWith('America/Indiana/') ||
      name.startsWith('America/Kentucky/') ||
      name.startsWith('America/North_Dakota/')) {
    return true;
  }
  final rule = RegExp(r'^(?:<([^>]+)>|([A-Za-z]{3,}))([+-]?\d{1,2})(?![0-9])')
      .firstMatch(name);
  if (rule == null) return false;
  final standard = (rule.group(1) ?? rule.group(2))!.toUpperCase();
  return _unitedStatesStandardTimes[standard] == int.parse(rule.group(3)!);
}

/// The name of the IANA database in a value of TZ or a path to a zone file:
/// without the colon POSIX allows in front, the folder of the database and
/// its « posix/ » or « right/ » copies.
@visibleForTesting
String zoneName(String zone) {
  var name = zone.trim();
  if (name.startsWith(':')) name = name.substring(1);
  final at = name.lastIndexOf('zoneinfo/');
  if (at >= 0) name = name.substring(at + 'zoneinfo/'.length);
  for (final copy in ['posix/', 'right/']) {
    if (name.startsWith(copy)) name = name.substring(copy.length);
  }
  return name;
}

/// The first moment the pot closes gaps in the United States too: the end
/// of 16 July 2028 where that day ends last (UTC−12, Baker Island).
final gapsClosedEverywhereFrom = DateTime.utc(2028, 7, 17, 12);

/// Whether the paint pot may close small gaps at [now] with these signs.
bool potClosesGaps(CountrySigns? signs, DateTime now) =>
    !now.toUtc().isBefore(gapsClosedEverywhereFrom) ||
    (signs != null && !signs.pointToUnitedStates);

const _channel = MethodChannel('org.edupaint/country');

/// Whether `flutter test` runs this code: no system side answers there, and
/// a question to it would only leave its two-second wait behind the test.
bool get _inFlutterTest => Platform.environment.containsKey('FLUTTER_TEST');

/// Reads every sign this system gives. Never fails: a sign that cannot be
/// read is left out, and the store's answer, the slowest, waits two seconds
/// at most. [system] (a name of [Platform.operatingSystem]) and
/// [askTheSystem] let a test take another system's way; under `flutter test`
/// the system is not asked, unless [askTheSystem] says so.
Future<CountrySigns> readCountrySigns({
  MethodChannel channel = _channel,
  PlatformDispatcher? dispatcher,
  @visibleForTesting String? system,
  @visibleForTesting bool? askTheSystem,
}) async {
  final os = system ?? Platform.operatingSystem;
  final ask = askTheSystem ?? !_inFlutterTest;
  final codes = <String>[];
  final zones = <String>[];
  // The region of the system's first language: the one it is set in.
  final primary = (dispatcher ?? PlatformDispatcher.instance).locale;
  if (primary.countryCode != null) codes.add(primary.countryCode!);
  // The region Dart reads of the system — but where it reads none, it says
  // « en_US »: always on Android, whose region comes with the other signs,
  // and on Linux without a language set, where LANG is read instead.
  final region = os == 'android'
      ? null
      : os == 'linux'
      ? linuxRegion(Platform.environment)
      : regionOfLocale(Platform.localeName);
  if (region != null) codes.add(region);
  if (os == 'linux') {
    zones.addAll(_linuxTimeZones());
  } else if (os == 'windows') {
    // The time zone of Windows is not read yet: its region is the sign
    // (to be completed with the version of the Microsoft Store).
    final geo = _windowsGeoName();
    if (geo != null) codes.add(geo);
  } else if (ask) {
    // At once: the region of the settings, the SIM's and the network's,
    // the time zone.
    try {
      final answer = await channel
          .invokeMapMethod<String, Object?>('signs')
          .timeout(const Duration(seconds: 2));
      final given = answer?['codes'];
      if (given is List) codes.addAll(given.whereType<String>());
      final zone = answer?['timeZone'];
      if (zone is String) zones.add(zone);
    } catch (_) {
      // No answer is no sign; the others still count.
    }
    // The country of Apple's store, which may be slow: asked apart, it
    // never keeps the others waiting.
    if (os == 'ios' || os == 'macos') {
      try {
        final store = await channel
            .invokeMethod<String>('store')
            .timeout(const Duration(seconds: 2));
        if (store != null) codes.add(store);
      } catch (_) {}
    }
  }
  return CountrySigns(codes: codes, timeZones: zones);
}

/// The two letters of the region of a locale: « fr_FR.UTF-8 », « en-US »,
/// « de_DE@euro », « zh-Hans_US », « en_US_POSIX ».
@visibleForTesting
String? regionOfLocale(String locale) {
  final match = RegExp(
    r'^[A-Za-z]{2,3}(?:[_-][A-Za-z]{4})?[_-]([A-Za-z]{2})(?![A-Za-z0-9])',
  ).firstMatch(locale);
  return match?.group(1);
}

/// The region of the language Linux is set to, if one is: LC_ALL, else
/// LANG, as the C library reads them.
@visibleForTesting
String? linuxRegion(Map<String, String> environment) {
  for (final name in ['LC_ALL', 'LANG']) {
    final value = environment[name];
    if (value != null && value.isNotEmpty) return regionOfLocale(value);
  }
  return null;
}

Iterable<String> _linuxTimeZones() sync* {
  final tz = Platform.environment['TZ'];
  if (tz != null && tz.isNotEmpty) yield tz;
  try {
    final file = File('/etc/timezone');
    if (file.existsSync()) yield file.readAsStringSync().trim();
  } catch (_) {}
  try {
    final localtime = Link('/etc/localtime');
    if (localtime.existsSync()) {
      yield zoneName(localtime.targetSync());
    } else {
      // A copy rather than a link: the rule at the end of its file.
      final rule = ruleOfZoneFile(File('/etc/localtime').readAsBytesSync());
      if (rule != null) yield rule;
    }
  } catch (_) {}
}

/// The rule of POSIX a zone file of version 2 or later ends with, between
/// its last two line feeds (RFC 8536, the footer).
@visibleForTesting
String? ruleOfZoneFile(List<int> bytes) {
  if (bytes.length < 5 ||
      String.fromCharCodes(bytes.take(4)) != 'TZif' ||
      bytes.last != 0x0a) {
    return null;
  }
  final start = bytes.lastIndexOf(0x0a, bytes.length - 2);
  if (start < 0) return null;
  final rule = String.fromCharCodes(bytes.sublist(start + 1, bytes.length - 1));
  return rule.isEmpty || rule.length > 64 ? null : rule;
}

// The country of Windows' Region setting (Windows 10 1709 and later).
String? _windowsGeoName() {
  try {
    final kernel = DynamicLibrary.open('kernel32.dll');
    final geoName = kernel
        .lookupFunction<
          Int32 Function(Pointer<Utf16>, Int32),
          int Function(Pointer<Utf16>, int)
        >('GetUserDefaultGeoName');
    final buffer = calloc<Uint16>(16);
    try {
      final length = geoName(buffer.cast(), 16);
      if (length <= 1) return null;
      return buffer.cast<Utf16>().toDartString(length: length - 1);
    } finally {
      calloc.free(buffer);
    }
  } catch (_) {
    return null;
  }
}
