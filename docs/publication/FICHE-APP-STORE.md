# Color sur l'App Store — la fiche, prête à coller

Une seule fiche dans App Store Connect pour le Mac, l'iPhone et l'iPad : les trois portent l'identifiant `fr.aisml.color`. Les textes sont en français ; Color n'existe qu'en français.

## Informations sur l'app

| Champ | À mettre |
|---|---|
| Nom | **Color** ; s'il est déjà pris : **Color Atelier de Dessin** |
| Sous-titre (30 caractères au plus) | Atelier de dessin pour enfants |
| Identifiant de lot (Bundle ID) | fr.aisml.color |
| SKU | color |
| Langue principale | Français |
| Catégorie principale | Éducation |
| Catégorie secondaire | Divertissement |
| Droits sur le contenu | « Oui, l'app contient du contenu de tiers, et j'ai les droits nécessaires » : des sons sous licence CC0 et la police DejaVu Sans, dont les licences sont dans « À propos » → « Licences » |
| Classification par âge | Répondre « Aucun » à chaque question : Color obtient **4+** |
| Fait pour les enfants (« Made for Kids ») | **Non coché** pour la première version : la catégorie Enfants impose un contrôle parental devant tout ce qui mène hors de l'app, et « Exporter » ouvre le panneau du système. À reconsidérer ensuite, avec le calcul des options activé par défaut sur iPhone et iPad |
| Statut de professionnel (Union européenne) | **Je ne suis pas un professionnel** |

## Prix et disponibilité

- Prix : **gratuit** (0 €).
- Disponibilité : tous les pays.

## Confidentialité de l'app

- URL de la politique de confidentialité : `https://alejandrosml.github.io/Color/confidentialite.html`
- Collecte de données : **« Nous ne collectons pas de données de cette app »**.

## Pour chaque version (macOS, puis iOS)

| Champ | À mettre |
|---|---|
| Texte promotionnel (170) | Dessine, colorie, tamponne, puis regarde ton dessin se refaire tout seul. Sans publicité, sans compte, sans Internet. |
| Mots-clés (100 octets) | dessin,enfant,coloriage,peinture,pinceau,tampon,colorier,atelier,crayon,maternelle,art |
| URL d'assistance | `https://alejandrosml.github.io/Color/` |
| URL marketing | `https://alejandrosml.github.io/Color/` |
| Copyright | 2026 Alejandro San Martin Lamas |
| Version | 1.0.0 |

### Description

> Color est un petit atelier de dessin pour les enfants. Tout y est grand, simple et bien rangé, pour dessiner sans avoir besoin de lire.
>
> • Le pinceau, les lignes, les rectangles et les ovales, le texte, la gomme et le pot de peinture.
> • Des tampons à poser et à colorier.
> • Douze pages à colorier, dessinées pour Color : le bateau, le chat, le dinosaure, la tortue…
> • Une palette de couleurs, des épaisseurs, la pipette pour reprendre une couleur du dessin.
> • « Revoir ton dessin » : le film de ton dessin qui se refait tout seul, trait après trait.
> • « Mes dessins » garde chaque dessin enregistré, pour le reprendre plus tard.
> • Annuler et rétablir, autant de fois qu'il faut.
> • Imprimer, et exporter ton dessin en image.
>
> Pour les adultes, les options règlent ce que Color montre : une interface très simplifiée pour les tout-petits, une interface moyenne, ou tout Color avec les calques. On peut aussi couper les sons ou l'impression, dessiner sans tenir le bouton, écrire avec un clavier à l'écran, et protéger les options par un calcul.
>
> Color ne collecte aucune donnée. Pas de publicité, pas de compte, pas d'achat, pas d'Internet : tout reste sur l'appareil.
>
> Color est un logiciel libre, sous licence MIT, créé par Alejandro San Martin Lamas.

### Notes pour la vérification (en anglais, pour le relecteur d'Apple)

> Color is a drawing app for children, in French only. It has no account, no in-app purchase, no advertising, no analytics and no network access: nothing leaves the device.
>
> To try it: choose a tool on the left (brush, shapes, stamps, text, eraser, paint bucket), pick a colour at the bottom and draw on the sheet. « Nouveau » (new) offers colouring pages: choose one, then colour its zones with the paint bucket (« Remplir »). « Revoir ton dessin » replays the drawing. « Enregistrer » saves it; « Mes dessins » lists saved drawings. « Imprimer » opens the system's print panel; « Exporter » (full interface) hands a PNG or SVG copy to the system's panel.
>
> The toothed wheel opens the adult's options (interface level, sounds, printing, accessibility). By default they open directly. When the option « Protéger les options par un calcul » is on, a multiplication of the tables from 6 to 9 is asked first: the answer is the product of the two numbers shown.
>
> The privacy policy is also in the app: « À propos » → « Confidentialité ».

## Les captures d'écran

Faites le 28 octobre 2026 par Color elle-même, avec son cœur et ses polices, aux tailles qu'App Store Connect exige (`prototypes/flutter-rust/test/store_pictures_test.dart`), sans canal alpha. Elles sont dans `docs/publication/captures/` des sources et, en ligne, sous [alejandrosml.github.io/Color/captures/](https://alejandrosml.github.io/Color/captures/iphone-1-dessin.png).

| Appareil | Taille | Captures |
|---|---|---|
| iPhone (Dynamic Island, taille moyenne) | 2556 × 1179 | `iphone-1-dessin`, `iphone-2-film`, `iphone-3-coloriage`, `iphone-4-tout-petits` |
| iPad 13 pouces | 2752 × 2064 | `ipad-1-dessin` … `ipad-4-tout-petits` |
| Mac | 2880 × 1800 (16:10) | `mac-1-dessin` … `mac-4-tout-petits` |

Dans l'ordre : un dessin avec des tampons et un titre ; son film, « Revoir ton dessin », en train de se refaire ; une page à colorier, le dinosaure, coloriée au pot ; l'interface très simplifiée des tout-petits, avec un arc-en-ciel au pinceau. Sur l'iPhone, le studio du téléphone à l'horizontale ; sur l'iPad, le studio au doigt ; sur le Mac, la fenêtre. Les lettres du système y sont celles de Roboto, pas celles d'Apple.

Pour les refaire, dans `prototypes/flutter-rust` :

```
COLOR_STORE_DIR=/un/dossier flutter test test/store_pictures_test.dart
```

## Sources

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Captures d'écran](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Catégories](https://developer.apple.com/app-store/categories/)
- [Statut de professionnel (DSA)](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements)
