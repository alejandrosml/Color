// SPDX-License-Identifier: MIT
import 'package:flutter/services.dart';

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

/// The request as each runner of Color answers it: the macOS, Linux and
/// Windows runners all listen on the same channel. A failure of the system
/// is thrown as the [PlatformException] that the runner describes.
Future<PrintOutcome> printWithSystemPanel({
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
