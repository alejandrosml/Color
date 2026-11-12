// SPDX-License-Identifier: MIT
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'child_art.dart';
import 'rust_document.dart' show NewShape;
import 'stamp_catalog.dart';
import 'stamp_dialog.dart';
import 'studio_colors.dart';
import 'studio_shapes.dart';
import 'studio_painters.dart';
import 'studio_tool.dart';
import 'text_layout.dart';
import 'language.dart';
import 'companion.dart';

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
    this.shape = NewShape.star,
    this.companionCue,
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

  /// The shape that « Formes » draws.
  final NewShape shape;

  /// What makes the companion stand up and paint (lib/companion.dart).
  final ValueListenable<int>? companionCue;

  String get _headline => switch (tool) {
    StudioTool.select => tr('Ton dessin peut bouger !'),
    StudioTool.fill => tr('De la couleur partout !'),
    StudioTool.eraser => tr('Oups ? On efface.'),
    StudioTool.brush => tr('Un trait, une idée.'),
    StudioTool.text => tr('Des mots dans ton dessin.'),
    StudioTool.stamp => tr('Un tampon, et hop !'),
    StudioTool.line ||
    StudioTool.rectangle ||
    StudioTool.ellipse ||
    StudioTool.shapes => tr('Une forme, mille idées.'),
    StudioTool.magic => tr('Un peu de magie !'),
    StudioTool.magnet => tr('Ta forme devient toute droite.'),
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
              tr('Abc'),
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
            shape: shape,
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
          child: Companion(
            key: const Key('inspectorMascot'),
            size: 104,
            cue: companionCue,
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
          decoration: studioPanel(radius: 19),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tool.label.toUpperCase(),
                style: TextStyle(
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
                style: TextStyle(
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
          decoration: studioPanel(
            color: studioIdeaCard,
            radius: 19,
            line: false,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('UNE PETITE IDÉE'),
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: studioIdeaTitle,
                ),
              ),
              SizedBox(height: 12),
              Text(
                tr('Et si le ciel était rose ?'),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 9),
              Text(
                tr(
                  'Tu peux essayer toutes les couleurs. Annuler est là pour revenir en arrière.',
                ),
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
