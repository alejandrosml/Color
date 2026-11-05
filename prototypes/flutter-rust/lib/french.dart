// SPDX-License-Identifier: MIT
// Small rules of written French shared by the panels, and of written
// English when the interface speaks it (Color 1.1).
import 'language.dart';

/// « 0 élément », « 1 élément », « 2 éléments » : in French the plural starts
/// at two; in English, « 0 elements », « 1 element », « 2 elements ».
String elementCount(int count) => inEnglish
    ? '$count element${count == 1 ? '' : 's'}'
    : '$count élément${count > 1 ? 's' : ''}';

const _months = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

/// When a drawing was saved, as a child would say it: « aujourd’hui à
/// 14 h 05 », « hier à 9 h 30 », « le 1er octobre à 8 h 00 », and with its
/// year when that is not the year of [now]. Both moments are taken as given:
/// pass local times. The hour is written with no-break spaces: it is never
/// cut in two at the end of a line.
String savedMoment(DateTime moment, {required DateTime now}) {
  if (inEnglish) return _englishMoment(moment, now: now);
  final hour =
      '${moment.hour}\u00a0h\u00a0${moment.minute.toString().padLeft(2, '0')}';
  final day = DateTime(moment.year, moment.month, moment.day);
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = DateTime(now.year, now.month, now.day - 1);
  if (day == today) return 'aujourd’hui à $hour';
  if (day == yesterday) return 'hier à $hour';
  final number = moment.day == 1 ? '1er' : '${moment.day}';
  final year = moment.year == now.year ? '' : ' ${moment.year}';
  return 'le $number ${_months[moment.month - 1]}$year à $hour';
}

const _englishMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// « today at 14:05 », « yesterday at 9:30 », « on 1 October at 8:00 »,
/// with its year when that is not the year of [now]: British English, as
/// the rest of the interface writes it.
String _englishMoment(DateTime moment, {required DateTime now}) {
  final hour = '${moment.hour}:${moment.minute.toString().padLeft(2, '0')}';
  final day = DateTime(moment.year, moment.month, moment.day);
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = DateTime(now.year, now.month, now.day - 1);
  if (day == today) return 'today at $hour';
  if (day == yesterday) return 'yesterday at $hour';
  final year = moment.year == now.year ? '' : ' ${moment.year}';
  return 'on ${moment.day}\u00a0${_englishMonths[moment.month - 1]}$year '
      'at $hour';
}
