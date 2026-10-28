# Color sur l'App Store — la fiche, prête à coller

Une seule fiche dans App Store Connect pour le Mac, l'iPhone et l'iPad : les trois portent l'identifiant `fr.aisml.color`. Les textes sont en français ; Color n'existe qu'en français.

## Où en est la fiche (28 octobre 2026)

**Color 1.0.0 (39) est soumise à Apple** le 28 octobre à 15 h 38 pour iOS et à 15 h 39 pour macOS : « En attente de vérification ».

Ce qui a été rempli dans App Store Connect :

- « Informations sur l'app » : nom, sous-titre, catégories, statut de non-professionnel ; droits sur le contenu (**oui**, avec les droits nécessaires) et classification par âge (**4+** dans 172 pays ou régions ; Brésil « AL », Corée du Sud « TOUS », Vietnam « 00+ »), faits par toi.
- Les versions 1.0.0 pour iOS et pour macOS : le build 39, les textes, les adresses, le copyright, le contact et les notes pour la vérification, la **publication manuelle**.
- « Tarifs et disponibilité » : gratuite, dans les 175 pays.
- « Confidentialité de l'app » : l'adresse de la politique de confidentialité, et « **Données non collectées** », publiée à ta demande.
- Les 12 captures, sur les pages produit de l'iPhone, de l'iPad 13 pouces et du Mac.

Pour une prochaine version, les mêmes réponses : droits sur le contenu « Oui » ; âge « Non » ou « Aucun » partout, sans « Conçu pour les enfants » ; confidentialité « Non, nous ne collectons aucune donnée via cette app ».

Ensuite :

1. Apple répond par courriel. D'après Apple, la moitié des soumissions sont vérifiées en moins de 24 heures, 90 % en moins de 48 heures. Une [vérification accélérée](https://developer.apple.com/help/app-review/after-submitting-for-review/request-expedited-review) se demande seulement pour une urgence réelle : un bogue grave, ou une sortie liée à un évènement daté.
2. Si Apple pose une question ou refuse, la réponse se fait dans « Vérification de l'app ».
3. La publication est manuelle : une fois Color acceptée, « Publier cette version » sur chaque version.

Facultatif : « Accessibilité de l'app » affiche sur la page produit les aides que Color prend en charge. À ne remplir que pour ce qui a été essayé sur un appareil, VoiceOver par exemple.

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

Dans App Store Connect, les images vont d'abord dans la « Bibliothèque de ressources », qui les range par appareil. Sur la page de la version iOS, la section des captures est cachée derrière le menu « En‑tête et résultats de recherche » : choisir « **Aperçus d'app et captures d'écran** », puis, pour chaque appareil, « **Parcourir les ressources** » et cocher les quatre images dans l'ordre. Sur la page de la version macOS, la section est visible tout de suite. L'en‑tête et la ressource des résultats de recherche sont facultatifs : sans eux, l'App Store montre les captures.

Pour les refaire, dans `prototypes/flutter-rust` :

```
COLOR_STORE_DIR=/un/dossier flutter test test/store_pictures_test.dart
```

## Sources

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Captures d'écran](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Catégories](https://developer.apple.com/app-store/categories/)
- [Statut de professionnel (DSA)](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements)
