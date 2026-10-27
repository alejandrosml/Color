// SPDX-License-Identifier: MIT
// How the studio shares its room between the sheet and what surrounds it.
//
// The sheet comes first. The controls under it take their spacious form only
// when the sheet then keeps a comfortable height, and whatever they need,
// they never push the sheet below its floor: they scroll instead.
import 'dart:math' as math;

import 'tool_bar.dart';

abstract final class StudioLayout {
  /// The spacious controls are kept only when the sheet's area then measures
  /// at least this height. Below it the compact controls give their room to
  /// the sheet: on a laptop screen the paper is then drawn half as large
  /// again. Nothing is lost with them: the recent colours stay one press
  /// away, in « Autres couleurs ».
  static const comfortableSheet = 400.0;

  /// Width of the inspector beside the sheet, with its margin.
  static const inspectorWidth = 204.0 + 18.0;

  /// Whether the tools stand in a row above the sheet instead of a column
  /// beside it: in a narrow window, and in one a little wider whose height
  /// would need two columns of tools. Two columns there would leave the
  /// sheet and the colours a column too narrow for either.
  static bool toolsAbove({
    required double width,
    required double height,
    required double textScale,
    int? toolCount,
    bool largeTools = false,
  }) =>
      width < 750 ||
      (width < 820 &&
          StudioToolBar.columnsFor(
                height - 24,
                textScale,
                count: toolCount,
                large: largeTools,
              ) >
              1);

  /// Height of the toolbar above the sheet at the given size of text.
  static double documentToolbarHeight(double textScale) =>
      48 + 40 * (math.max(1.0, textScale) - 1);

  /// An upper estimate of the height of the spacious controls in a column of
  /// the given width. Measured with the interface's own letters; enlarged
  /// text wraps as a narrower column does, and grows what it writes.
  static double spaciousControlsHeight(double columnWidth, double textScale) {
    final scale = math.max(1.0, textScale);
    final effective = columnWidth / scale;
    final base = effective >= 640
        ? 290.0
        : effective >= 560
        ? 345.0
        : 400.0;
    return base * (0.7 + 0.3 * scale);
  }

  /// Whether the controls under the sheet may take their spacious form in a
  /// studio body of the given size. [narrow] puts the tools in a row above
  /// the sheet; [inspector] shows the panel beside it.
  static bool spaciousControls({
    required double width,
    required double height,
    required bool narrow,
    required bool inspector,
    required double textScale,
    int? toolCount,
    bool largeTools = false,
  }) {
    // Margins of the spacious form: 20 around, 12 in a narrow window.
    final margin = narrow ? 12.0 : 20.0;
    final columnHeight = height - 2 * margin;
    final tools = narrow
        ? 0.0
        : StudioToolBar.widthFor(
                columnHeight,
                textScale,
                count: toolCount,
                large: largeTools,
              ) +
              18;
    final columnWidth =
        width - 2 * margin - tools - (inspector ? inspectorWidth : 0);
    // The row of tools of a narrow window, the toolbar and the two gaps.
    final above = (narrow ? 56.0 : 0.0) + documentToolbarHeight(textScale) + 24;
    final sheet =
        columnHeight - above - spaciousControlsHeight(columnWidth, textScale);
    return sheet >= comfortableSheet;
  }

  /// The height the sheet keeps out of [room], the height that it shares
  /// with the controls under it. The controls scroll rather than take it.
  /// This is a safety net, not a target: letters wider than those the
  /// estimate above was measured with cost the sheet a little height before
  /// they cost the controls a scrollbar.
  static double sheetFloor(double room) =>
      math.min(room, (room * 0.3).clamp(96.0, 240.0));
}
