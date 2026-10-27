// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import 'french.dart';
import 'rust_document.dart' show LayerData, maxLayers;
import 'studio_colors.dart';

/// The interface offers eight layers to draw on; a project may hold up to
/// sixteen layers, the locked ones of a colouring page included.
const int maxInterfaceLayers = 8;

/// The name of a locked layer: it holds a colouring page.
const String pageLayerName = 'Page';

/// The name of the layer [id] among [layers]: [pageLayerName] for a locked
/// layer; otherwise « Calque » and a number that stays the same while the
/// drawing is open. The locked layers take no number: on a colouring page
/// as on an empty sheet, the child draws first on « Calque 1 ».
String layerName(int id, List<LayerData> layers) {
  var lockedBefore = 0;
  for (final layer in layers) {
    if (!layer.locked) continue;
    if (layer.id == id) return pageLayerName;
    if (layer.id < id) lockedBefore++;
  }
  return 'Calque ${id + 1 - lockedBefore}';
}

/// Whether the layer at position [from] in [layers] may move to position
/// [to]: two different places in the stack, and no locked layer from one to
/// the other, both included. No layer passes the page of a colouring page,
/// which stays where it is: the layers between two of its locked layers are
/// reordered among themselves. The core refuses any other move.
bool canMoveLayer(List<LayerData> layers, int from, int to) {
  if (from == to ||
      from < 0 ||
      to < 0 ||
      from >= layers.length ||
      to >= layers.length) {
    return false;
  }
  final low = from < to ? from : to;
  final high = from < to ? to : from;
  for (var position = low; position <= high; position++) {
    if (layers[position].locked) return false;
  }
  return true;
}

/// Live view of the studio's layers. Every callback edits the drawing through
/// the studio, which keeps the undo history and the save state up to date.
class LayerPanelActions {
  const LayerPanelActions({
    required this.layers,
    required this.activeLayer,
    required this.select,
    required this.add,
    required this.remove,
    required this.move,
    required this.setVisible,
  });
  final List<LayerData> Function() layers;
  final int Function() activeLayer;
  final void Function(int id) select;
  final void Function() add;
  final void Function(int position) remove;
  final void Function(int from, int to) move;
  final void Function(int position, bool visible) setVisible;
}

class LayersDialog extends StatefulWidget {
  const LayersDialog({super.key, required this.actions});
  final LayerPanelActions actions;

  @override
  State<LayersDialog> createState() => _LayersDialogState();
}

class _LayersDialogState extends State<LayersDialog> {
  // The studio has already applied the change: read its layers again.
  void _run(VoidCallback action) => setState(action);

  Widget _iconButton({
    required String key,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) => IconButton(
    key: Key(key),
    tooltip: label,
    onPressed: onPressed,
    style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    icon: Icon(icon, semanticLabel: label),
  );

  @override
  Widget build(BuildContext context) {
    final actions = widget.actions;
    final layers = actions.layers();
    final active = actions.activeLayer();
    // The layers to draw on: those of a colouring page are not.
    final drawable = layers.where((layer) => !layer.locked).length;
    final visibleDrawable = layers
        .where((layer) => !layer.locked && layer.visible)
        .length;
    final full = drawable >= maxInterfaceLayers || layers.length >= maxLayers;
    return AlertDialog(
      key: const Key('layersDialog'),
      scrollable: true,
      insetPadding: const EdgeInsets.all(16),
      title: const Text('Mes calques'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Les calques sont des feuilles transparentes posées l’une sur '
              'l’autre. Celui du haut de la liste passe devant les autres.',
            ),
            if (drawable < layers.length) ...[
              const SizedBox(height: 8),
              const Text(
                'La page à colorier est verrouillée : tu peux la cacher et '
                'la montrer, mais pas la changer.',
                key: Key('lockedPageNote'),
              ),
            ],
            const SizedBox(height: 12),
            // Top of the stack first, as it appears on the sheet.
            for (var position = layers.length - 1; position >= 0; position--)
              _row(layers, position, active, visibleDrawable, drawable),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('addLayer'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: full ? null : () => _run(actions.add),
              icon: const Icon(Icons.add),
              label: Text(
                // A project made elsewhere may hold more than this panel
                // lets one add: say the number there really is.
                full ? 'Tu as déjà $drawable calques' : 'Ajouter un calque',
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.all(16),
      actions: [
        FilledButton(
          key: const Key('closeLayers'),
          style: FilledButton.styleFrom(minimumSize: const Size(88, 48)),
          onPressed: () => Navigator.pop(context),
          child: const Text('Revenir au dessin'),
        ),
      ],
    );
  }

  Widget _row(
    List<LayerData> layers,
    int position,
    int active,
    int visibleDrawable,
    int drawable,
  ) {
    final actions = widget.actions;
    final layer = layers[position];
    final name = layerName(layer.id, layers);
    // A locked layer holds a colouring page: it can be hidden and shown,
    // nothing more. The core would refuse the rest anyway.
    final locked = layer.locked;
    // How the buttons name it in their sentence.
    final named = locked ? 'la page' : name;
    final isActive = layer.id == active;
    final choose = isActive || locked
        ? null
        : () => _run(() => actions.select(layer.id));
    return Container(
      key: Key('layer-row-${layer.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? studioSelected : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? studioGreen : studioLine,
          width: isActive ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              container: true,
              // Nothing to choose on the page: it is no button.
              button: !locked,
              selected: isActive,
              label: locked
                  ? 'Page à colorier, verrouillée'
                  : isActive
                  ? '$name, tu dessines sur ce calque'
                  : 'Dessiner sur $name',
              // The row's parts are replaced by this one name: its action
              // must be given again, or a screen reader could not choose.
              onTap: choose,
              excludeSemantics: true,
              child: InkWell(
                key: Key('layer-select-${layer.id}'),
                borderRadius: BorderRadius.circular(10),
                onTap: choose,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Icon(
                          locked
                              ? Icons.lock_outline
                              : isActive
                              ? Icons.brush
                              : Icons.circle_outlined,
                          size: 22,
                          color: isActive ? studioGreen : studioQuietMark,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                // The elements of the page tell how it was
                                // made, not what the child did: a locked
                                // layer shows no count.
                                locked
                                    ? 'verrouillée${layer.visible ? '' : ' · cachée'}'
                                    : '${elementCount(layer.objectCount)}${layer.visible ? '' : ' · caché'}'
                                          '${isActive ? ' · tu dessines ici' : ''}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          _iconButton(
            key: 'layer-visible-${layer.id}',
            icon: layer.visible
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            label: layer.visible ? 'Cacher $named' : 'Montrer $named',
            // The sheet always keeps one visible layer to draw on; the page
            // is not one, and may always be hidden.
            onPressed: !locked && layer.visible && visibleDrawable == 1
                ? null
                : () =>
                      _run(() => actions.setVisible(position, !layer.visible)),
          ),
          // The page stays put, and no layer passes it: a layer next to it
          // does not move towards it.
          _iconButton(
            key: 'layer-up-${layer.id}',
            icon: Icons.arrow_upward,
            label: 'Passer $named devant',
            onPressed: canMoveLayer(layers, position, position + 1)
                ? () => _run(() => actions.move(position, position + 1))
                : null,
          ),
          _iconButton(
            key: 'layer-down-${layer.id}',
            icon: Icons.arrow_downward,
            label: 'Passer $named derrière',
            onPressed: canMoveLayer(layers, position, position - 1)
                ? () => _run(() => actions.move(position, position - 1))
                : null,
          ),
          _iconButton(
            key: 'layer-delete-${layer.id}',
            icon: Icons.delete_outline_rounded,
            label: 'Effacer $named',
            // The page stays, and so does one layer to draw on.
            onPressed: locked || drawable == 1
                ? null
                : () => _run(() => actions.remove(position)),
          ),
        ],
      ),
    );
  }
}
