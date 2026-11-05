// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import 'fit_to_screen.dart';
import 'png_export.dart';
import 'language.dart';

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
          title: Text(tr('Emporter ton dessin')),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr(
                      'Choisis une image à partager. Pour continuer ton dessin plus tard, enregistre aussi le projet Color.',
                    ),
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
                    label: Text(tr('Image PNG')),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    trf('Pour partager et imprimer · {0} × {1} pixels', [
                      width * (large ? 2 : 1),
                      height * (large ? 2 : 1),
                    ]),
                    style: const TextStyle(fontSize: 12),
                  ),
                  CheckboxListTile(
                    key: const Key('pngScale2'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      tr('Grand format (×2)'),
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
                    Text(
                      tr(
                        'Cette feuille est trop grande pour une image PNG. Choisis le format SVG.',
                      ),
                      style: TextStyle(fontSize: 12),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('exportSvg'),
                    onPressed: () =>
                        Navigator.pop(dialogContext, ExportChoice.svg),
                    icon: const Icon(Icons.zoom_out_map),
                    label: Text(tr('Image vectorielle SVG')),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hasBackground
                        ? tr(
                            'Les traits restent vectoriels. Ton image de fond garde sa résolution.',
                          )
                        : tr('Pour agrandir sans perdre en netteté.'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr('Annuler')),
            ),
          ],
        ),
      ),
    ),
  );
}
