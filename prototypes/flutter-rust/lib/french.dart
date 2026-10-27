// SPDX-License-Identifier: MIT
// Small rules of written French shared by the panels.

/// « 0 élément », « 1 élément », « 2 éléments » : in French the plural starts
/// at two.
String elementCount(int count) => '$count élément${count > 1 ? 's' : ''}';

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
