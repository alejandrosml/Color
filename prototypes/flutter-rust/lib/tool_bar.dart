// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import 'child_art.dart';
import 'studio_colors.dart';
import 'studio_tool.dart';

/// The tools, as a column beside the sheet or as a row above it in a narrow
/// window. Every tool keeps a full-size target: the bar scrolls rather than
/// shrinking its buttons below a comfortable size.
class StudioToolBar extends StatelessWidget {
  const StudioToolBar({
    super.key,
    required this.selected,
    required this.onSelected,
    this.horizontal = false,
    this.rail = false,
    this.leading,
    this.tools = StudioTool.values,
    this.large = false,
  });

  final StudioTool selected;

  /// The tools shown, in their order: the simplest interface has four.
  final List<StudioTool> tools;

  /// Larger buttons, for the few tools of the simplest interface.
  final bool large;

  /// Null while the studio is busy: the buttons are then disabled.
  final ValueChanged<StudioTool>? onSelected;
  final bool horizontal;

  /// The narrow rail of a telephone, beside the sheet: the pictures of the
  /// tools without their names, in one column or two, under [leading].
  final bool rail;

  /// What the rail holds above the tools: the button of the menu.
  final Widget? leading;

  /// The side of a button of the rail.
  static double railButton(bool large) => large ? 60.0 : 48.0;
  static const railGap = 6.0;
  static const railPadding = 6.0;

  /// How many columns the rail needs to show every tool, under a [leading]
  /// of the given height, in a rail of the given height.
  static int railColumns(
    double maxHeight, {
    required int count,
    required bool large,
    double leadingHeight = 48,
  }) {
    final side = railButton(large);
    final room = maxHeight - 2 * railPadding - leadingHeight - 10;
    return room >= count * side + (count - 1) * railGap ? 1 : 2;
  }

  /// The width of the rail with that many columns.
  static double railWidth(int columns, {required bool large}) =>
      2 * railPadding + columns * railButton(large) + (columns - 1) * railGap;

  // The column beside the sheet. Tall windows keep one column of large
  // buttons; shorter ones tighten them down to a comfortable target, then
  // stand the tools in two columns, so that every tool stays in view.
  static const _title = 46.0;
  static const _padding = 22.0;
  static double _columnWidth(bool large) => large ? 100.0 : 76.0;

  static ({int columns, int rows, double gap, double height}) _columnLayout(
    double maxHeight,
    double textScale, {
    required int count,
    required bool large,
  }) {
    // The height a button takes when the window leaves it all the room.
    final best = large ? 104.0 : 80.0;
    final room = maxHeight - _title * textScale - _padding;
    final roomy = room >= count * best + (count - 1) * 10;
    final columns = room >= count * 60 + (count - 1) * 6 ? 1 : 2;
    final rows = (count + columns - 1) ~/ columns;
    final gap = roomy ? 10.0 : 6.0;
    final height = roomy
        ? best
        : ((room - (rows - 1) * gap) / rows).clamp(60.0, best);
    return (columns: columns, rows: rows, gap: gap, height: height);
  }

  /// One column of tools beside a sheet of the given height, or two.
  static int columnsFor(
    double maxHeight,
    double textScale, {
    int? count,
    bool large = false,
  }) => _columnLayout(
    maxHeight,
    textScale,
    count: count ?? StudioTool.values.length,
    large: large,
  ).columns;

  /// The width the column of tools takes beside a sheet of the given
  /// height: the studio shares the rest between the sheet and its panels.
  static double widthFor(
    double maxHeight,
    double textScale, {
    int? count,
    bool large = false,
  }) {
    final layout = _columnLayout(
      maxHeight,
      textScale,
      count: count ?? StudioTool.values.length,
      large: large,
    );
    return _padding +
        layout.columns * _columnWidth(large) +
        (layout.columns - 1) * layout.gap;
  }

  // In the row of a narrow window a button may keep only its picture: its
  // name is then a tooltip and stays the name read by a screen reader.
  Widget _button(StudioTool tool, {double height = 80, bool label = true}) {
    final isSelected = tool == selected;
    final side = railButton(large);
    final button = OutlinedButton(
      key: Key(tool.keyName),
      onPressed: onSelected == null ? null : () => onSelected!(tool),
      style: OutlinedButton.styleFrom(
        backgroundColor: isSelected ? studioSelected : studioSurface,
        foregroundColor: isSelected ? studioGreen : studioInk,
        minimumSize: rail
            ? Size.square(side)
            : Size(
                horizontal ? 48 : _columnWidth(large),
                horizontal ? 48 : height,
              ),
        maximumSize: rail ? Size.square(side) : Size.infinite,
        padding: rail
            ? EdgeInsets.zero
            : EdgeInsets.symmetric(
                horizontal: horizontal ? (label ? 6 : 2) : 4,
                vertical: horizontal || height >= 76 ? 8 : 4,
              ),
        side: BorderSide(
          color: isSelected ? studioGreen : studioLine,
          width: isSelected ? 2 : 1,
        ),
      ),
      // The chosen state is announced on the button itself, with its name
      // and its action: a screen reader meets one control, not two.
      child: Semantics(
        selected: isSelected,
        label: label ? null : tool.label,
        child: rail
            ? EduIllustration(art: tool.art, size: large ? 40 : 30)
            : horizontal
            ? label
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        EduIllustration(art: tool.art, size: 23),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            tool.label,
                            maxLines: 1,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    )
                  : EduIllustration(art: tool.art, size: 28)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  EduIllustration(
                    art: tool.art,
                    size: height >= 96
                        ? 54
                        : height >= 76
                        ? 39
                        : 28,
                  ),
                  SizedBox(height: height >= 76 ? 5 : 2),
                  // Enlarged text shrinks a long name to the button's width
                  // instead of breaking it in the middle of a word.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      tool.label,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: large ? 12 : 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
    return label
        ? button
        : Tooltip(
            message: tool.label,
            excludeFromSemantics: true,
            child: button,
          );
  }

  @override
  Widget build(BuildContext context) {
    if (rail) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final columns = railColumns(
            constraints.maxHeight,
            count: tools.length,
            large: large,
          );
          final side = railButton(large);
          final rows = (tools.length + columns - 1) ~/ columns;
          return SizedBox(
            width: railWidth(columns, large: large),
            // A screen too short even for two columns makes the rail scroll.
            child: SingleChildScrollView(
              key: const Key('toolsRail'),
              primary: false,
              padding: const EdgeInsets.all(railPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(height: 10),
                  ],
                  for (var row = 0; row < rows; row++) ...[
                    if (row != 0) const SizedBox(height: railGap),
                    Row(
                      children: [
                        for (
                          var index = row * columns;
                          index < (row + 1) * columns;
                          index++
                        ) ...[
                          if (index != row * columns)
                            const SizedBox(width: railGap),
                          SizedBox.square(
                            dimension: side,
                            child: index < tools.length
                                ? _button(tools[index], label: false)
                                : null,
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    }
    if (horizontal) {
      return LayoutBuilder(
        builder: (context, constraints) {
          const gap = 7.0;
          final shared =
              (constraints.maxWidth - gap * (tools.length - 1)) / tools.length;
          // Names need room, and more of it when the text is enlarged. When
          // they cannot all fit, the pictures alone keep every tool in view;
          // only a very narrow window makes the row scroll.
          final textScale = MediaQuery.textScalerOf(context).scale(11) / 11;
          final named = shared >= 36 + 48 * textScale;
          if (named || shared >= 48) {
            return Row(
              children: [
                for (final tool in tools) ...[
                  if (tool != tools.first) const SizedBox(width: gap),
                  Expanded(child: _button(tool, label: named)),
                ],
              ],
            );
          }
          return SingleChildScrollView(
            key: const Key('toolsScroll'),
            scrollDirection: Axis.horizontal,
            primary: false,
            child: Row(
              children: [
                for (final tool in tools) ...[
                  if (tool != tools.first) const SizedBox(width: gap),
                  SizedBox(width: 48, child: _button(tool, label: false)),
                ],
              ],
            ),
          );
        },
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // Only a very short window makes the bar scroll.
        final column = _columnWidth(large);
        final count = tools.length;
        final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
        final (:columns, :rows, :gap, :height) = _columnLayout(
          constraints.maxHeight,
          textScale,
          count: count,
          large: large,
        );
        final roomy = gap == 10.0;
        return SizedBox(
          width: widthFor(
            constraints.maxHeight,
            textScale,
            count: count,
            large: large,
          ),
          child: SingleChildScrollView(
            primary: false,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: studioSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: studioLine),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: 5, bottom: roomy ? 14 : 8),
                    child: const Text(
                      'OUTILS',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        color: studioCaption,
                      ),
                    ),
                  ),
                  for (var row = 0; row < rows; row++) ...[
                    if (row != 0) SizedBox(height: gap),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (
                          var index = row * columns;
                          index < (row + 1) * columns;
                          index++
                        ) ...[
                          if (index != row * columns) SizedBox(width: gap),
                          // The last row of an odd count keeps its place.
                          SizedBox(
                            width: column,
                            child: index < count
                                ? _button(tools[index], height: height)
                                : null,
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
