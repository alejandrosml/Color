// SPDX-License-Identifier: MIT
// Who made Color, under which licence it is given, and what it does with
// data: what « À propos » says of it, kept in one place.
import 'language.dart';

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
String get colorLegalese => inEnglish
    ? 'Color is free software, published under the MIT licence: anyone may '
          'use it, copy it, change it and give it away, as long as they keep '
          'the name of its author and this licence. It comes with no '
          'warranty at all.\n\n'
          'Below, the licence of Color, then those of what it is made with: '
          'Flutter and its packages, the recorded sounds, the fonts of the '
          'texts.'
    : 'Color est un logiciel libre, publié sous la licence MIT : chacun peut '
          'l’utiliser, le copier, le modifier et le redistribuer, à condition de '
          'garder la mention de son auteur et de cette licence. Il est fourni sans '
          'aucune garantie.\n\n'
          'Ci-dessous, la licence de Color, puis celles de ce avec quoi il est '
          'fait : Flutter et ses paquets, les sons enregistrés, les polices des '
          'textes.';

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
/// (docs/publication/confidentialite.html, in French and in English). They
/// say the same thing.
String get colorPrivacyPolicy => inEnglish
    ? _englishPrivacyPolicy
    : 'Color ne collecte aucune donnée. Il ne demande ni compte, ni nom, ni '
          'adresse, et il ne se connecte jamais à Internet : rien de ce que fait '
          'l’enfant ne quitte l’appareil.\n\n'
          'Ce que Color garde, et où. Les dessins que tu enregistres : sur un '
          'ordinateur, là où tu choisis de les ranger ; sur une tablette ou un '
          'téléphone, dans le dossier privé de Color sur cet appareil. Dans ce '
          'dossier privé, aussi : une copie de chaque dessin enregistré, pour '
          '« Mes dessins » ; une copie '
          'de secours du dessin en cours, pour le retrouver après une interruption ; '
          'les options choisies, et les dernières couleurs choisies. Rien de tout '
          'cela n’est envoyé à personne : ni à '
          'l’auteur de Color, ni à Apple, ni à Google, ni à aucun autre service.\n\n'
          'Ni publicité, ni mesure d’audience, ni suivi, ni bibliothèque d’un tiers '
          'qui en ferait. Color ne demande aucune autorisation pour lire autre chose '
          'que les fichiers que tu lui ouvres toi-même. Pour savoir si le pot de '
          'peinture peut fermer les petits trous, Color lit sur l’appareil le pays '
          'qu’il indique (sa région, son fuseau horaire, la boutique, la carte SIM '
          'et le réseau mobile) : ce pays n’est ni gardé ni envoyé.\n\n'
          'Imprimer. Quand tu imprimes, l’image du dessin va à l’imprimante que tu '
          'choisis, par le système de l’appareil.\n\n'
          'Effacer. Retirer une carte de « Mes dessins » efface sa copie. Supprimer '
          'Color de l’appareil efface tout son dossier privé — sur une tablette ou '
          'un téléphone, les dessins enregistrés avec lui. Les fichiers que tu as '
          'enregistrés ou exportés ailleurs restent à toi.\n\n'
          'Les enfants. Color est fait pour eux : il ne recueille rien sur eux, ni '
          'sur personne.\n\n'
          'Cette politique peut changer avec une nouvelle version de Color ; elle '
          'est toujours lisible ici, dans « À propos ». Dernière mise à jour : '
          '2 novembre 2026.';

const _englishPrivacyPolicy =
    'Color collects no data. It asks for no account, no name, no address, '
    'and it never connects to the Internet: nothing the child does leaves '
    'the device.\n\n'
    'What Color keeps, and where. The drawings you save: on a computer, '
    'wherever you choose to put them; on a tablet or a phone, in Color’s '
    'private folder on this device. In that private folder, too: a copy of '
    'each saved drawing, for “My drawings”; a backup copy of the drawing in '
    'progress, to find it again after an interruption; the options chosen, '
    'and the last colours chosen. None of this is sent to anyone: not to the '
    'author of Color, not to Apple, not to Google, not to any other '
    'service.\n\n'
    'No advertising, no audience measurement, no tracking, and no third-party '
    'library that would do any of it. Color asks for no permission to read '
    'anything but the files you open in it yourself. To know whether the '
    'paint pot may close small gaps, Color reads on the device the country it '
    'gives (its region, its time zone, the store, the SIM card and the mobile '
    'network): that country is neither kept nor sent.\n\n'
    'Printing. When you print, the picture of the drawing goes to the printer '
    'you choose, through the system of the device.\n\n'
    'Deleting. Removing a card from “My drawings” deletes its copy. Deleting '
    'Color from the device deletes its whole private folder — on a tablet or '
    'a phone, the saved drawings with it. The files you saved or exported '
    'elsewhere remain yours.\n\n'
    'Children. Color is made for them: it gathers nothing about them, or '
    'about anyone.\n\n'
    'This policy may change with a new version of Color; it can always be '
    'read here, in “About”. Last updated: 2 November 2026.';
