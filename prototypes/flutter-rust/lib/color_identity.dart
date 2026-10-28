// SPDX-License-Identifier: MIT
// Who made Color, under which licence it is given, and what it does with
// data: what « À propos » says of it, kept in one place.

/// The author of Color, as « © 2026 … » names them: in « À propos », on the
/// page of the licences, and in the LICENSE file of the sources. Written by
/// scripts/inscrire-l-auteur.py with the other places that name the author;
/// empty until the name is given, and then nothing names anyone.
const colorAuthor = 'Alejandro San Martin Lamas';

/// The year of the first public version.
const colorYear = 2026;

/// « © 2026 … », or nothing while [colorAuthor] is empty.
String get colorCopyright =>
    colorAuthor.isEmpty ? '' : '© $colorYear $colorAuthor';

/// Under which terms Color itself is given, on the page of the licences.
const colorLegalese =
    'Color est un logiciel libre, publié sous la licence MIT : chacun peut '
    'l’utiliser, le copier, le modifier et le redistribuer, à condition de '
    'garder la mention de son auteur et de cette licence. Il est fourni sans '
    'aucune garantie.\n\n'
    'Ci-dessous, la licence de Color, puis celles de ce avec quoi il est '
    'fait : Flutter et ses paquets, les bibliothèques du cœur Rust, la police '
    'des textes.';

/// The text of the MIT licence, as the LICENSE file of the sources gives
/// it, with the line that names the author.
String get colorLicenceText =>
    '${colorAuthor.isEmpty ? 'Copyright (c) $colorYear' : 'Copyright (c) $colorYear $colorAuthor'}\n\n'
    'Permission is hereby granted, free of charge, to any person obtaining a '
    'copy of this software and associated documentation files (the '
    '"Software"), to deal in the Software without restriction, including '
    'without limitation the rights to use, copy, modify, merge, publish, '
    'distribute, sublicense, and/or sell copies of the Software, and to permit '
    'persons to whom the Software is furnished to do so, subject to the '
    'following conditions:\n\n'
    'The above copyright notice and this permission notice shall be included '
    'in all copies or substantial portions of the Software.\n\n'
    'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS '
    'OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF '
    'MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN '
    'NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, '
    'DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR '
    'OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE '
    'USE OR OTHER DEALINGS IN THE SOFTWARE.';

/// The address where the privacy policy and the help page are published
/// (GitHub Pages of the public repository, online since 27 October 2026).
/// Color shows it as text: it never opens a connection itself.
const colorSupportAddress = 'https://alejandrosml.github.io/Color/';

/// The privacy policy of Color, as « À propos » → « Confidentialité » shows
/// it and as it is published beside the sources
/// (docs/publication/confidentialite.html). The two say the same thing.
const colorPrivacyPolicy =
    'Color ne collecte aucune donnée. Il ne demande ni compte, ni nom, ni '
    'adresse, et il ne se connecte jamais à Internet : rien de ce que fait '
    'l’enfant ne quitte l’appareil.\n\n'
    'Ce que Color garde, et où. Les dessins que tu enregistres, là où tu '
    'choisis de les ranger. Dans le dossier privé de Color sur cet appareil : '
    'une copie de chaque dessin enregistré, pour « Mes dessins » ; une copie '
    'de secours du dessin en cours, pour le retrouver après une interruption ; '
    'et les options choisies. Rien de tout cela n’est envoyé à personne : ni à '
    'l’auteur de Color, ni à Apple, ni à Google, ni à aucun autre service.\n\n'
    'Ni publicité, ni mesure d’audience, ni suivi, ni bibliothèque d’un tiers '
    'qui en ferait. Color ne demande aucune autorisation pour lire autre chose '
    'que les fichiers que tu lui ouvres toi-même.\n\n'
    'Imprimer. Quand tu imprimes, l’image du dessin va à l’imprimante que tu '
    'choisis, par le système de l’appareil.\n\n'
    'Effacer. Retirer une carte de « Mes dessins » efface sa copie. Supprimer '
    'Color de l’appareil efface tout son dossier privé. Les fichiers que tu as '
    'enregistrés ailleurs restent à toi.\n\n'
    'Les enfants. Color est fait pour eux : il ne recueille rien sur eux, ni '
    'sur personne.\n\n'
    'Cette politique peut changer avec une nouvelle version de Color ; elle '
    'est toujours lisible ici, dans « À propos ». Dernière mise à jour : '
    '24 octobre 2026.';
