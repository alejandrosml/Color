// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import 'child_art.dart';
import 'stamp_catalog.dart';
import 'stamp_dialog.dart';
import 'studio_colors.dart';
import 'studio_painters.dart';
import 'studio_tool.dart';
import 'text_layout.dart';

/// The side panel of wide windows: what the current tool does, with an
/// example in the current colour, an idea to try and the mascot.
class StudioInspector extends StatelessWidget {
  const StudioInspector({
    super.key,
    required this.tool,
    required this.help,
    required this.rgb,
    required this.width,
    required this.fillRgb,
    required this.stamp,
  });

  final StudioTool tool;

  /// The sentence that explains the tool, as under the palette.
  final String help;
  final int rgb;
  final double width;

  /// Inside colour of new shapes; null when they are not filled.
  final int? fillRgb;

  /// The stamp that a click would pose; null if the catalogue is unavailable.
  final StampArt? stamp;

  String get _headline => switch (tool) {
    StudioTool.select => 'Ton dessin peut bouger !',
    StudioTool.fill => 'De la couleur partout !',
    StudioTool.eraser => 'Oups ? On efface.',
    StudioTool.brush => 'Un trait, une idée.',
    StudioTool.text => 'Des mots dans ton dessin.',
    StudioTool.stamp => 'Un tampon, et hop !',
    StudioTool.line ||
    StudioTool.rectangle ||
    StudioTool.ellipse => 'Une forme, mille idées.',
  };

  Widget _example() {
    final kind = tool.kind;
    if (kind == null) {
      return Center(child: EduIllustration(art: tool.art, size: 56));
    }
    switch (tool) {
      case StudioTool.text:
        return Center(
          child: ExcludeSemantics(
            child: Text(
              'Abc',
              style: TextStyle(
                fontFamily: colorTextFontFamily,
                fontSize: 34,
                color: Color(0xff000000 | rgb),
              ),
            ),
          ),
        );
      case StudioTool.stamp:
        return Center(
          child: stamp == null
              ? const EduIllustration(art: EduArt.stamp, size: 56)
              : StampPreview(stamp: stamp!, rgb: rgb, size: 64),
        );
      default:
        return CustomPaint(
          painter: ToolPreviewPainter(
            Color(0xff000000 | rgb),
            width,
            kind,
            fillRgb == null ? null : Color(0xff000000 | fillRgb!),
          ),
          child: const SizedBox.expand(),
        );
    }
  }

  // The cards scroll if the window is too short for them. The mascot under
  // them is shown whole or not at all: where it would be cut by the bottom
  // of the window it is left out. It still stands beside the help under
  // the colours.
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 204,
    child: CustomMultiChildLayout(
      delegate: _InspectorLayout(),
      children: [
        LayoutId(id: _InspectorPart.cards, child: _cards()),
        LayoutId(
          id: _InspectorPart.mascot,
          child: const EduIllustration(
            key: Key('inspectorMascot'),
            art: EduArt.mascot,
            size: 104,
          ),
        ),
      ],
    ),
  );

  Widget _cards() => SingleChildScrollView(
    primary: false,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 67),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: studioSurface,
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: studioLine),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tool.label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  color: studioInspectorCaption,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _headline,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                height: 80,
                decoration: BoxDecoration(
                  color: studioPreviewBox,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _example(),
              ),
              const SizedBox(height: 16),
              Text(
                help,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: studioInspectorText,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: studioIdeaCard,
            borderRadius: BorderRadius.circular(19),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'UNE PETITE IDÉE',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: studioIdeaTitle,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Et si le ciel était rose ?',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 9),
              Text(
                'Tu peux essayer toutes les couleurs. Annuler est là pour revenir en arrière.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: studioIdeaText,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

enum _InspectorPart { cards, mascot }

class _InspectorLayout extends MultiChildLayoutDelegate {
  static const _mascot = Size.square(104);
  static const _gap = 16.0;

  @override
  void performLayout(Size size) {
    final cards = layoutChild(
      _InspectorPart.cards,
      BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        maxHeight: size.height,
      ),
    );
    positionChild(_InspectorPart.cards, Offset.zero);
    final room = size.height - cards.height - _gap >= _mascot.height;
    // Without room it takes no place and paints nothing.
    layoutChild(
      _InspectorPart.mascot,
      BoxConstraints.tight(room ? _mascot : Size.zero),
    );
    positionChild(
      _InspectorPart.mascot,
      Offset((size.width - _mascot.width) / 2, cards.height + _gap),
    );
  }

  @override
  bool shouldRelayout(_InspectorLayout oldDelegate) => false;
}
