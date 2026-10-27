// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import 'vector_art.dart';

/// What « Nouveau » starts: an empty sheet of one shape, or a colouring page
/// on the sheet it was drawn for.
sealed class NewSheetChoice {
  /// Size of the new sheet, in units of the drawing.
  int get width;
  int get height;
}

enum NewSheetShape implements NewSheetChoice {
  landscape('Paysage', 1200, 800),
  portrait('Portrait', 800, 1200),
  square('Carré', 1200, 1200);

  const NewSheetShape(this.label, this.width, this.height);
  final String label;
  @override
  final int width;
  @override
  final int height;
}

/// One colouring page of the core: an original drawing whose closed regions
/// the paint pot colours. coloring_pages.dart reads them from the core;
/// choosing one makes its document, RustDocument.fromPage.
final class ColoringPage implements NewSheetChoice {
  const ColoringPage({
    required this.id,
    required this.key,
    required this.title,
    required this.regions,
    required this.details,
    required this.picture,
    required this.width,
    required this.height,
  });

  /// Its identifier in the core that described it.
  final int id;

  /// The name of its file in the core, without `.svg`: lowercase letters and
  /// hyphens, stable from one version to the next.
  final String key;

  /// The French title shown to the child.
  final String title;

  /// The filled elements of its file, white: the zones that « Remplir »
  /// colours.
  final int regions;

  /// Its other elements: lines, polylines, open paths and unfilled shapes.
  final int details;

  /// The page as its thumbnail shows it.
  final VectorPicture picture;

  /// The sheet the page needs.
  @override
  final int width;
  @override
  final int height;

  /// The elements of its file, not the objects of its document: there a
  /// zone is also a line, and a line may be cut in pieces where a zone drawn
  /// after it covers it.
  int get elementCount => regions + details;
}

class NewSheetDialog extends StatefulWidget {
  const NewSheetDialog({super.key, this.pages = const []});

  /// The colouring pages offered under the empty sheets. Choosing one
  /// closes the dialog with it at once; without pages, no such section.
  final List<ColoringPage> pages;

  @override
  State<NewSheetDialog> createState() => _NewSheetDialogState();
}

class _NewSheetDialogState extends State<NewSheetDialog> {
  NewSheetShape _selected = NewSheetShape.landscape;
  final _choiceKeys = {
    for (final shape in NewSheetShape.values) shape: GlobalKey(),
  };
  final _focusNodes = {
    for (final shape in NewSheetShape.values) shape: FocusNode(),
  };

  @override
  void initState() {
    super.initState();
    for (final shape in NewSheetShape.values) {
      _focusNodes[shape]!.addListener(() {
        if (!_focusNodes[shape]!.hasFocus) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_focusNodes[shape]!.hasFocus) return;
          final target = _choiceKeys[shape]!.currentContext;
          if (target != null) {
            Scrollable.ensureVisible(
              target,
              alignment: .5,
              duration: const Duration(milliseconds: 150),
            );
          }
        });
      });
    }
  }

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('newSheetDialog'),
    scrollable: true,
    insetPadding: const EdgeInsets.all(16),
    constraints: const BoxConstraints(maxWidth: 480),
    title: const Text('Choisis la forme de ta feuille'),
    // The keyboard goes through the shapes, then through the pages in the
    // order they are written, though some are scrolled out of sight: the
    // order of the screen would put those after the buttons below.
    content: FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RadioGroup<NewSheetShape>(
              groupValue: _selected,
              onChanged: (shape) {
                if (shape != null) setState(() => _selected = shape);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final shape in NewSheetShape.values) ...[
                    if (shape != NewSheetShape.landscape)
                      const SizedBox(height: 8),
                    KeyedSubtree(
                      key: _choiceKeys[shape],
                      child: RadioListTile<NewSheetShape>(
                        key: Key('newSheet-${shape.name}'),
                        focusNode: _focusNodes[shape],
                        value: shape,
                        selected: _selected == shape,
                        autofocus: shape == NewSheetShape.landscape,
                        minTileHeight: 72,
                        visualDensity: VisualDensity.standard,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: _selected == shape
                                ? const Color(0xff846bae)
                                : const Color(0xffd9e6e3),
                            width: _selected == shape ? 2 : 1,
                          ),
                        ),
                        tileColor: _selected == shape
                            ? const Color(0xfff1ebfa)
                            : Colors.white,
                        controlAffinity: ListTileControlAffinity.trailing,
                        title: Text(
                          shape.label,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        secondary: ExcludeSemantics(
                          child: SizedBox(
                            width: 64,
                            height: 54,
                            child: Center(
                              child: AspectRatio(
                                key: Key('newSheetPreview-${shape.name}'),
                                aspectRatio: shape.width / shape.height,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: const Color(0xff526f70),
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.pages.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'Ou une page à colorier',
                key: const Key('coloringPagesTitle'),
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              _PageChoices(
                pages: widget.pages,
                onChosen: (page) => Navigator.pop(context, page),
              ),
            ],
          ],
        ),
      ),
    ),
    actionsPadding: const EdgeInsets.all(16),
    actionsOverflowButtonSpacing: 8,
    actions: [
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: TextButton(
          key: const Key('cancelNewSheet'),
          style: TextButton.styleFrom(
            minimumSize: const Size(88, 48),
            visualDensity: VisualDensity.standard,
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
      ),
      FilledButton(
        key: const Key('createNewSheet'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(88, 48),
          visualDensity: VisualDensity.standard,
        ),
        onPressed: () => Navigator.pop(context, _selected),
        child: const Text('Créer'),
      ),
    ],
  );
}

/// The pages in rows of three: a row takes the height of its tallest
/// title, so that the pictures of a row stay side by side.
class _PageChoices extends StatelessWidget {
  const _PageChoices({required this.pages, required this.onChosen});
  final List<ColoringPage> pages;
  final ValueChanged<ColoringPage> onChosen;

  static const _columns = 3;
  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var start = 0; start < pages.length; start += _columns) ...[
        if (start > 0) const SizedBox(height: _gap),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var column = 0; column < _columns; column++) ...[
                if (column > 0) const SizedBox(width: _gap),
                Expanded(
                  child: start + column < pages.length
                      ? _PageButton(
                          page: pages[start + column],
                          onPressed: () => onChosen(pages[start + column]),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      ],
    ],
  );
}

class _PageButton extends StatelessWidget {
  const _PageButton({required this.page, required this.onPressed});
  final ColoringPage page;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    key: Key('page-${page.key}'),
    onPressed: onPressed,
    style:
        OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.all(6),
          alignment: Alignment.topCenter,
          backgroundColor: Colors.white,
          visualDensity: VisualDensity.standard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ).copyWith(
          // The page that the keyboard reached is framed like a chosen
          // shape.
          side: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? const BorderSide(color: Color(0xff846bae), width: 2)
                : const BorderSide(color: Color(0xffd9e6e3)),
          ),
        ),
    // One name on the button itself, which keeps its own action: the
    // picture and the title written under it only decorate.
    child: Semantics(
      label: page.title,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: page.width / page.height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xffb9c9c6)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: CustomPaint(painter: _PagePainter(page.picture)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Three lines keep « Le bonhomme de neige » whole in large text.
          Text(
            page.title,
            maxLines: 3,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

class _PagePainter extends CustomPainter {
  const _PagePainter(this.picture);
  final VectorPicture picture;

  @override
  void paint(Canvas canvas, Size size) =>
      picture.paint(canvas, Offset.zero & size, minimumStroke: 1.2);

  @override
  bool shouldRepaint(_PagePainter old) => !identical(old.picture, picture);
}
