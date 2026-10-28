// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import 'fit_to_screen.dart';
import 'png_export.dart';

/// What the child chose in « Emporter ton dessin ».
enum ExportChoice { png, largePng, svg }

/// Asks which image to make of a sheet of the given size. Returns null when
/// the dialog is cancelled. Nothing is written here.
Future<ExportChoice?> showExportDialog(
  BuildContext context, {
  required int width,
  required int height,
  required bool hasBackground,
}) {
  var large = false;
  return showDialog<ExportChoice>(
    context: context,
    builder: (dialogContext) => FitDialog(
      child: StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Emporter ton dessin'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Choisis une image à partager. Pour continuer ton dessin plus tard, enregistre aussi le projet Color.',
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    key: const Key('exportPng'),
                    onPressed:
                        canExportDocumentPng(
                          width: width,
                          height: height,
                          scale: large ? 2 : 1,
                        )
                        ? () => Navigator.pop(
                            dialogContext,
                            large ? ExportChoice.largePng : ExportChoice.png,
                          )
                        : null,
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Image PNG'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Pour partager et imprimer · ${width * (large ? 2 : 1)} × ${height * (large ? 2 : 1)} pixels',
                    style: const TextStyle(fontSize: 12),
                  ),
                  CheckboxListTile(
                    key: const Key('pngScale2'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'Grand format (×2)',
                      style: TextStyle(fontSize: 14),
                    ),
                    value: large,
                    onChanged:
                        canExportDocumentPng(
                          width: width,
                          height: height,
                          scale: 2,
                        )
                        ? (value) => update(() {
                            large = value!;
                          })
                        : null,
                  ),
                  if (!canExportDocumentPng(width: width, height: height))
                    const Text(
                      'Cette feuille est trop grande pour une image PNG. Choisis le format SVG.',
                      style: TextStyle(fontSize: 12),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('exportSvg'),
                    onPressed: () =>
                        Navigator.pop(dialogContext, ExportChoice.svg),
                    icon: const Icon(Icons.zoom_out_map),
                    label: const Text('Image vectorielle SVG'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hasBackground
                        ? 'Les traits restent vectoriels. Ton image de fond garde sa résolution.'
                        : 'Pour agrandir sans perdre en netteté.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
          ],
        ),
      ),
    ),
  );
}
