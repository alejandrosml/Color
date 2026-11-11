// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/services.dart';

import 'rust_document.dart';

/// What became of a request to print.
enum PrintOutcome {
  /// The person confirmed the system's panel: the page went to the printer,
  /// or to the file that the panel was asked for.
  sent,

  /// The person closed the panel without printing.
  cancelled,

  /// This computer has no printer that the system knows of.
  noPrinter,

  /// This build of Color has no way to reach the system's printing.
  unavailable,
}

/// Asks the system to print one image on one page. The system's own panel
/// opens: the person chooses the printer there, or cancels. Nothing is ever
/// printed without that panel being confirmed.
///
/// [rgba] holds [width] × [height] opaque pixels, four bytes each, rows from
/// the top. [jobName] is what the system's print queue shows.
typedef StudioPrinter = Future<PrintOutcome> Function({
  required Uint8List rgba,
  required int width,
  required int height,
  required String jobName,
});

const _printChannel = MethodChannel('org.edupaint/print');

/// The code that every runner answers with when the system has no printer.
const noPrinterCode = 'NO_PRINTER';

/// The request as this system answers it: on Windows the core opens the
/// print dialog itself ([printWithCore]); the macOS and Linux runners listen
/// on a channel ([printWithChannel]). A failure of the system is thrown as a
/// [PlatformException] that describes it. Under `flutter test` the core is
/// never asked: a test that injects no printer must not open the print
/// dialog of the machine that plays it.
Future<PrintOutcome> printWithSystemPanel({
  required Uint8List rgba,
  required int width,
  required int height,
  required String jobName,
}) => Platform.isWindows && !Platform.environment.containsKey('FLUTTER_TEST')
    ? printWithCore(rgba: rgba, width: width, height: height, jobName: jobName)
    : printWithChannel(
        rgba: rgba,
        width: width,
        height: height,
        jobName: jobName,
      );

/// How [printWithCore] asks the core: [RustDocument.printStart] and
/// [RustDocument.printResult], which a test replaces.
typedef CorePrintStart =
    int Function(Uint8List rgba, int width, int height, String jobName);
typedef CorePrintResult = (int, int) Function();

/// The request as the core answers it on Windows: it opens the print dialog
/// of the system on a thread of its own, over the window of Color, and is
/// asked [every] so often what became of it. The studio goes on drawing its
/// frames meanwhile; Windows keeps the window under the dialog from being
/// touched.
Future<PrintOutcome> printWithCore({
  required Uint8List rgba,
  required int width,
  required int height,
  required String jobName,
  CorePrintStart? start,
  CorePrintResult? result,
  Duration every = const Duration(milliseconds: 80),
}) async {
  if (width < 1 || height < 1 || rgba.length != width * height * 4) {
    throw ArgumentError('L’image à imprimer n’a pas la taille annoncée.');
  }
  final started = (start ?? RustDocument.printStart)(
    rgba,
    width,
    height,
    jobName,
  );
  switch (started) {
    case 0:
      break;
    case 1:
      throw PlatformException(
        code: 'PRINT_BUSY',
        message: 'Une impression est en cours.',
      );
    case 3:
      return PrintOutcome.unavailable;
    default:
      throw PlatformException(
        code: 'INVALID_ARGUMENT',
        message: 'Image de taille inattendue.',
      );
  }
  while (true) {
    await Future<void>.delayed(every);
    final (state, code) = (result ?? RustDocument.printResult)();
    switch (state) {
      case 1:
        continue;
      case 2:
        return PrintOutcome.sent;
      case 3:
        return PrintOutcome.cancelled;
      case 4:
        return PrintOutcome.noPrinter;
      case 5:
        throw PlatformException(
          code: 'PRINT_FAILED',
          message: 'Windows ne peut pas imprimer (code $code).',
        );
      default:
        throw PlatformException(
          code: 'PRINT_FAILED',
          message: 'Réponse inattendue du cœur : $state',
        );
    }
  }
}

/// The request as the macOS and Linux runners answer it, on their channel.
Future<PrintOutcome> printWithChannel({
  required Uint8List rgba,
  required int width,
  required int height,
  required String jobName,
}) async {
  if (width < 1 || height < 1 || rgba.length != width * height * 4) {
    throw ArgumentError('L’image à imprimer n’a pas la taille annoncée.');
  }
  try {
    // The pixels come last: the message then grows once to their size, not
    // twice.
    final answer = await _printChannel.invokeMethod<Object?>('printImage', {
      'width': width,
      'height': height,
      'name': jobName,
      'rgba': rgba,
    });
    return switch (answer) {
      'printed' => PrintOutcome.sent,
      'cancelled' => PrintOutcome.cancelled,
      _ => throw PlatformException(
        code: 'PRINT_FAILED',
        message: 'Réponse inattendue du système : $answer',
      ),
    };
  } on MissingPluginException {
    return PrintOutcome.unavailable;
  } on PlatformException catch (error) {
    if (error.code == noPrinterCode) return PrintOutcome.noPrinter;
    rethrow;
  }
}
