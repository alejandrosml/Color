# Color sur l'App Store — la fiche, prête à coller

Une seule fiche dans App Store Connect pour le Mac, l'iPhone et l'iPad : les trois portent l'identifiant `fr.aisml.color`. Les textes sont en français ; jusqu'à la 1.0.1, Color n'existe qu'en français. La 1.1 parle aussi anglais : sa fiche reçoit une localisation anglaise, prête plus bas.

## Où en est la fiche (16 novembre 2026)

**La 1.1.1 (42) est publiée partout** : sur le Mac le 11 novembre, sur l'iPhone et l'iPad le 13 novembre, dans la catégorie Enfants, tranche « 5 ans et moins ». **La 1.2.0 (43) se prépare** : ses textes, en français et en anglais, sont plus bas, dans « La version 1.2 » — la description refaite (la pipette et le mélange sont devenus un réglage des adultes, les dix univers), les nouveautés, le texte promotionnel et les notes pour la vérification. `scripts/macos/app_store_connect.py preparer --fiche` les lit ici même et les écrit chez Apple, pour le Mac et pour l'iPhone et l'iPad ; les captures de la 1.2 se chargent par `captures`. Rien ne part à la vérification sans ton accord (`envoyer --accord-du-proprietaire`).

Ce qui suit raconte les versions précédentes.

**La 1.1.1 (42), 11 novembre : publiée sur le Mac, en attente de vérification pour l'iPhone et l'iPad.** Le 10 novembre, à ta demande (« pousser la dernière version, puis toujours la dernière »), les builds 1.1.1 (42) sont partis chez Apple par « Envoyer Color vers l'App Store », et les deux versions 1.1.1 ont été préparées par la clé d'API puis envoyées à la vérification vers 23 h, en publication automatique. Le 11 novembre vers 16 h 15, App Store Connect dit la 1.1.1 du Mac « prête pour la distribution » : elle est publiée, dans la catégorie Enfants. Celle de l'iPhone et de l'iPad a suivi le 13 novembre. Le détail : `docs/JALON-1.1.1.md`.

- **La 1.0.0 (39) de l'iPhone et de l'iPad a été acceptée le 10 novembre** (courriel de 8 h 56). Leur 1.0.1 et leur 1.1.0 ne sont jamais parties à la vérification : l'iPhone passe de la 1.0.0 à la 1.1.1, le Mac de la 1.0.1 à la 1.1.1. Les builds 1.1.0 (41) restent chez Apple sans servir.
- **« Fait pour les enfants » est coché, tranche « 5 ans et moins »** (10 novembre). Apple l'a accepté sur le Mac : la case ne se décoche plus, et toutes les versions suivantes suivent les règles 1.3 et 5.1.4.
- **Le sous-titre** est redevenu « Atelier de dessin pour enfants » ; la description redit « pour les enfants ».
- **Les pages anglaises** (`en-US` et `en-GB`) existent : description, mots-clés, texte promotionnel, nouveautés, adresses, sous-titre « Drawing studio for children ». **Le nom « Color » était déjà pris en anglais : tu as choisi « Color: Drawing Studio »** ; le nom français reste « Color ».
- **Les nouveautés de la 1.1.1** sont celles de la 1.1, plus bas, avec une ligne de plus : « Les douze pages à colorier ont été redessinées : de nouveaux dessins, plus beaux. » (« The twelve colouring pages have been redrawn: new, nicer drawings. »)
- **Les captures** de la 1.1.1 sont encore celles de la 1.0, en français même sur les pages anglaises, et celle du coloriage montre l'ancien dinosaure : la 1.2 les remplace toutes, en français et en anglais (voir « Les captures d'écran »).
- Apple Vision Pro : rien à faire, App Store Connect dit de lui-même que la 1.1.1 n'y est pas disponible.

**macOS : la 1.0.0 acceptée le 4 novembre, la 1.0.1 acceptée le 6.** Apple a accepté Color 1.0.0 (39) pour le Mac le 4 novembre au soir (courriel de 20 h 17), et l'a publiée aussitôt, comme prévu. Le 5 novembre, à ta demande, les builds 1.0.1 (40) du Mac, de l'iPhone et de l'iPad sont partis chez Apple (« Envoyer Color vers l'App Store », vers 0 h 25), et la version 1.0.1 du Mac a été envoyée à la vérification à 0 h 38, avec ton accord :

- la description commence par « Color est un petit atelier de dessin. », comme sur l'iPhone ;
- les nouveautés sont celles de la fiche, plus bas, sans leur première ligne : le doigt, le stylet et la main posée sur l'écran ne concernent pas le Mac ;
- publication automatique dès l'accord d'Apple, à tous les utilisateurs d'un coup, en gardant la note existante.

Apple a accepté la 1.0.1 (40) du Mac dans la nuit du 5 au 6 novembre (courriel de 0 h 05) : publiée automatiquement, comme la 1.0.0.

**iOS : refusée le 3 novembre, renvoyée le 4, toujours « En attente de vérification ».** Le 3 novembre au soir, Apple a refusé la version iOS 1.0.0 (39), vérifiée sur un iPad Air 11 pouces (M3), selon la règle **2.3.8, « Accurate Metadata »**. Le sous-titre « Atelier de dessin pour enfants » présentait Color comme faite pour les enfants, alors que l'app n'était pas dans la catégorie Enfants. Apple laissait le choix : retirer du nom, du sous-titre, de l'icône et des captures ce qui dit « pour enfants », ou cocher « Fait pour les enfants ».

Le 4 novembre, à ta demande :

- le sous-titre est devenu **« Atelier de dessin »** ;
- la description commence par « Color est un petit atelier de dessin. », sans « pour les enfants » ;
- tu as approuvé la réponse envoyée à Apple depuis la page « Vérification de l'app », à 11 h 37 ;
- le même build 39 a été renvoyé à 11 h 38 : « En attente de vérification ».

Le build 1.0.1 (40) de l'iPhone et de l'iPad est déjà chez Apple : leur version 1.0.1 se prépare dès que la 1.0.0 est acceptée, avec les nouveautés entières, puis part avec ton accord.

**La catégorie Enfants viendra avec la 1.1** (décidé le 4 novembre ; voir `docs/JALON-1.1.md`). « Fait pour les enfants » ne se décoche plus une fois l'app acceptée.

Le sous-titre est commun aux deux plateformes. La description de la 1.0.0 du Mac, acceptée telle quelle, disait encore « pour les enfants » ; celle de sa 1.0.1 ne le dit plus.

Le 28 octobre, **Color 1.0.0 (39) était soumise à Apple** à 15 h 38 pour iOS et à 15 h 39 pour macOS.

Ce qui a été rempli dans App Store Connect :

- « Informations sur l'app » : nom, sous-titre, catégories, statut de non-professionnel ; droits sur le contenu (**oui**, avec les droits nécessaires) et classification par âge (**4+** dans 172 pays ou régions ; Brésil « AL », Corée du Sud « TOUS », Vietnam « 00+ »), faits par toi.
- Les versions 1.0.0 pour iOS et pour macOS : le build 39, les textes, les adresses, le copyright, le contact et les notes pour la vérification, et la **publication automatique dès l'accord d'Apple** (choisie par toi le 28 octobre, après la soumission).
- « Tarifs et disponibilité » : gratuite, dans les 175 pays.
- « Confidentialité de l'app » : l'adresse de la politique de confidentialité, et « **Données non collectées** », publiée à ta demande.
- Les 12 captures, sur les pages produit de l'iPhone, de l'iPad 13 pouces et du Mac.

Pour une prochaine version, les mêmes réponses : droits sur le contenu « Oui » ; âge « Non » ou « Aucun » partout, avec « Fait pour les enfants », tranche « 5 ans et moins », depuis la 1.1.1 ; confidentialité « Non, nous ne collectons aucune donnée via cette app ».

Ensuite :

1. Apple répond par courriel. D'après Apple, la moitié des soumissions sont vérifiées en moins de 24 heures, 90 % en moins de 48 heures. Une [vérification accélérée](https://developer.apple.com/help/app-review/after-submitting-for-review/request-expedited-review) se demande seulement pour une urgence réelle : un bogue grave, ou une sortie liée à un évènement daté.
2. Si Apple pose une question ou refuse, la réponse se fait dans « Vérification de l'app ».
3. La publication est automatique : dès qu'Apple accepte une version, elle paraît sur l'App Store, sans autre clic.

Facultatif : « Accessibilité de l'app » affiche sur la page produit les aides que Color prend en charge. À ne remplir que pour ce qui a été essayé sur un appareil, VoiceOver par exemple.

## Informations sur l'app

| Champ | À mettre |
|---|---|
| Nom | **Color** en français. En anglais, où « Color » était pris : **Color: Drawing Studio** (ton choix du 10 novembre) |
| Sous-titre (30 caractères au plus) | **Atelier de dessin pour enfants**, revenu le 10 novembre avec la catégorie Enfants (du 4 au 10 novembre : « Atelier de dessin », règle 2.3.8). En anglais : Drawing studio for children |
| Identifiant de lot (Bundle ID) | fr.aisml.color |
| SKU | color |
| Langue principale | Français |
| Catégorie principale | Éducation |
| Catégorie secondaire | Divertissement |
| Droits sur le contenu | « Oui, l'app contient du contenu de tiers, et j'ai les droits nécessaires » : des sons sous licence CC0 et la police DejaVu Sans, dont les licences sont dans « À propos » → « Licences » |
| Classification par âge | Répondre « Aucun » à chaque question : Color obtient **4+** |
| Fait pour les enfants (« Made for Kids ») | **Coché le 10 novembre, tranche « 5 ans et moins »**, et accepté par Apple sur le Mac avec la 1.1.1 : ni la case ni, sans doute, la tranche ne se changent plus. Non coché pour la 1.0 ; décidé le 4 novembre pour la 1.1. La catégorie Enfants demande un contrôle parental devant ce qui fait sortir de l'app et devant les achats ; Color n'a ni l'un ni l'autre, et ses panneaux de fichiers restent dans l'app : pas de contrôle de plus, sauf si Apple le demande. Une seule tranche d'âge (5 ans et moins, 6–8 ou 9–11 ; conseil : 5 ans et moins), sans doute impossible à changer ensuite, comme la case. Retirer alors la disponibilité sur Apple Vision Pro : les apps pour enfants n'y sont pas permises |
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
| Texte promotionnel (170) | Jusqu'à la 1.1.1 : Dessine, colorie, tamponne, puis regarde ton dessin se refaire tout seul. Sans publicité, sans compte, sans Internet. Pour la 1.2 : voir « La version 1.2 ». |
| Mots-clés (100 octets) | dessin,enfant,coloriage,peinture,pinceau,tampon,colorier,atelier,crayon,maternelle,art |
| URL d'assistance | `https://alejandrosml.github.io/Color/` |
| URL marketing | `https://alejandrosml.github.io/Color/` |
| Copyright | 2026 Alejandro San Martin Lamas |
| Version | 1.0.0, 1.0.1 (Mac seulement), 1.1.1, puis **1.2.0** ; la 1.1.0 n'a jamais été envoyée à la vérification |

### Description (jusqu'à la 1.1.1)

Celle de la 1.2 est plus bas, dans « La version 1.2 » : la pipette n'y est plus promise à tous.

> Color est un petit atelier de dessin. Tout y est grand, simple et bien rangé, pour dessiner sans avoir besoin de lire.
>
> *(« pour les enfants » retiré le 4 novembre, puis remis le 10 novembre avec la catégorie Enfants : la description de la 1.1.1 commence par « Color est un petit atelier de dessin pour les enfants. »)*
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

### Nouveautés de la version 1.0.1 (4 000 caractères au plus)

Le champ « Nouveautés de cette version », que demande toute mise à jour. À mettre sur la page de la version 1.0.1, iOS et macOS, une fois la 1.0.0 « Prête à la distribution ». Sur le Mac (envoyée le 5 novembre), sans la première ligne, qui ne le concerne pas :

> Color est plus rapide et plus légère :
> • le trait suit le doigt et le stylet sans trembler ; une main posée sur l'écran ne dessine plus et ne zoome plus pendant que le stylet dessine ;
> • les grands dessins restent fluides quand on dessine, qu'on zoome ou qu'on déplace la feuille, et dans le film du dessin ;
> • les dessins et les pages à colorier s'ouvrent plus vite, et une image placée derrière un dessin se charge plus vite ;
> • les grands dessins sont copiés moins souvent pendant qu'on dessine ;
> • un dessin enregistré résiste mieux à une coupure de courant ;
> • un son rejoué part sans attendre ;
> • l'application prend moins de place.

### Nouveautés de la version 1.1 (4 000 caractères au plus)

Pour la page de la version 1.1, une fois la 1.0.1 envoyée et acceptée. En français :

> Color 1.1 : de nouveaux outils, et l'anglais.
> • Le pot de peinture remplit aussi le papier entre tes traits, et ne déborde plus par un tout petit trou (sauf aux États-Unis, pour l'instant) ; avec une couleur, un dégradé ou un dégradé rond.
> • « Formes » : le triangle, l'étoile, le cœur, le losange, l'hexagone, la flèche, et l'aimant, qui rend bien droite une forme dessinée à main levée.
> • « Magie » : un arc-en-ciel, de l'herbe, des briques, des confettis, et un miroir qui dessine deux fois.
> • Le pinceau a cinq pointes : rond, feutre, plume, craie, aérographe ; il suit la pression du stylet.
> • La gomme coupe les traits là où elle passe.
> • Tourner un élément, le retourner comme dans un miroir ; tourner un tampon avant de le poser.
> • Un mélangeur qui mélange les couleurs comme de la peinture ; tes couleurs restent d'une fois à l'autre.
> • Quatre écritures de plus pour les textes, dont celle de l'école.
> • Le diaporama de « Mes dessins ».
> • Pour toucher plus facilement : le doigt atteint ce qui est tout près, « Régler le toucher », le trait tranquille pour une main qui tremble, un pointeur au clavier ou à la manette.
> • Color parle anglais : il suit la langue de l'appareil, ou celle choisie dans les options.
> • Un dessin abîmé s'ouvre quand même : Color sauve tout ce qui peut l'être.
> • Les dessins enregistrés prennent moins de place. Enregistrés avec la 1.1, ils ne s'ouvrent plus avec les versions précédentes.

En anglais (localisation « English (U.K.) » ou « English (U.S.) ») :

> Color 1.1: new tools, and English.
> • The paint pot also fills the paper between your lines, with one colour, a gradient or a round gradient.
> • “Shapes”: triangle, star, heart, diamond, hexagon, arrow, and the magnet, which makes a freehand shape neat and straight.
> • “Magic”: a rainbow, grass, bricks, confetti, and a mirror that draws twice.
> • The brush has five tips: round, felt pen, nib, chalk, airbrush; it follows the pressure of the stylus.
> • The eraser cuts lines where it passes.
> • Turn an element, flip it as in a mirror; turn a stamp before you put it down.
> • A mixer that mixes colours like paint; your colours stay from one time to the next.
> • Four more fonts for texts, including school handwriting.
> • A slideshow of “My drawings”.
> • Easier to touch: a finger reaches what is very close, “Adjust touch”, a steady line for a shaky hand, a pointer with the keyboard or a gamepad.
> • Color speaks English: it follows the language of the device, or the one chosen in the options.
> • A damaged drawing still opens: Color saves all it can.
> • Saved drawings take less room. Saved with 1.1, they no longer open in earlier versions.

### La fiche en anglais (1.1)

Dans App Store Connect, « Informations sur l'app » → ajouter la langue anglaise ; les champs de la version aussi.

| Champ | En anglais |
|---|---|
| Nom | **Color: Drawing Studio** (« Color » seul était déjà pris en anglais) |
| Sous-titre (30) | Drawing studio for children (avec la catégorie Enfants ; sinon : Drawing studio) |
| Texte promotionnel (170) | Draw, colour, stamp, then watch your drawing make itself again. No ads, no account, no Internet. |
| Mots-clés (100 octets) | drawing,kids,colouring,coloring,paint,brush,stamp,art,crayon,preschool,sketch |

> Color is a little drawing studio for children. Everything in it is big, simple and tidy, so they can draw without needing to read.
>
> • The brush with five tips, lines, rectangles, ovals and six more shapes, the magnet that straightens a freehand shape, text in five fonts, the eraser and the paint pot.
> • Magic: rainbows, grass, bricks, confetti, and a mirror that draws twice.
> • Stamps to put down, turn and colour.
> • Twelve colouring pages, drawn for Color: the boat, the cat, the dinosaur, the tortoise…
> • A palette of colours, a mixer that mixes them like paint, thicknesses, the eyedropper to take a colour from the drawing.
> • “Watch your drawing again”: the film of your drawing making itself again, line after line.
> • “My drawings” keeps every saved drawing, to go on with it later, and shows them as a slideshow.
> • Undo and redo, as many times as needed.
> • Print, and export your drawing as a picture.
>
> For grown-ups, the options set what Color shows: a very simple interface for the youngest, a medium one, or all of Color with layers. You can also turn off sounds or printing, draw without holding the button, adjust touch, steady a shaky hand, move a pointer with the keyboard or a gamepad, write with an on-screen keyboard, and guard the options with a sum. Color speaks French and English.
>
> Color collects no data. No ads, no account, no purchases, no Internet: everything stays on the device.
>
> Color is free software, under the MIT licence, created by Alejandro San Martin Lamas.

### Notes pour la vérification (en anglais, pour le relecteur d'Apple)

> Color is a drawing app for children, in French only. It has no account, no in-app purchase, no advertising, no analytics and no network access: nothing leaves the device.
>
> To try it: choose a tool on the left (brush, shapes, stamps, text, eraser, paint bucket), pick a colour at the bottom and draw on the sheet. « Nouveau » (new) offers colouring pages: choose one, then colour its zones with the paint bucket (« Remplir »). « Revoir ton dessin » replays the drawing. « Enregistrer » saves it; « Mes dessins » lists saved drawings. « Imprimer » opens the system's print panel; « Exporter » (full interface) hands a PNG or SVG copy to the system's panel.
>
> The toothed wheel opens the adult's options (interface level, sounds, printing, accessibility). By default they open directly. When the option « Protéger les options par un calcul » is on, a multiplication of the tables from 6 to 9 is asked first: the answer is the product of the two numbers shown.
>
> The privacy policy is also in the app: « À propos » → « Confidentialité ».

Pour la 1.1, remplacer la première phrase par : « Color is a drawing app for children, in French and English: it follows the language of the device, or the one chosen in the options (the globe at the top of the toothed wheel's window). » Les noms en français entre guillemets restent ceux de l'interface française ; en anglais : « New », « Fill », « Watch your drawing again », « Save », « My drawings », « Print », « Export », « Guard the options with a sum », « About » → « Privacy ».

Et, pour la 1.1 dans la catégorie Enfants, ajouter après le troisième paragraphe : « Color has no link out of the app and no purchase. « Ouvrir » (open), « Sur une image » (draw on a picture) and « Exporter » (export) use the system's file panels, which stay inside the app; saving keeps the drawing in the app's own folder, and printing uses the system's print panel. »

## La version 1.2 (prête à coller)

Version **1.2.0**, build **43**, pour le Mac et pour l'iPhone et l'iPad ; publication automatique dès l'accord d'Apple, comme les précédentes ; copyright « 2026 Alejandro San Martin Lamas ». Les pages `fr-FR`, `en-US` et `en-GB`. Chaque bloc ci-dessous se colle tel quel — `app_store_connect.py preparer --fiche` les lit par leur titre : ne pas changer les titres.

Ce que la 1.2 change dans la fiche : **la pipette, le dégradé et le mélange ne sont plus pour tous** — ils sont dans « Toutes les couleurs, pour les grands », un réglage des adultes, éteint au départ ; **les dessins déjà enregistrés montrent les nouveaux tampons** ; les dix univers, leurs décors et leurs fiches ; « Regarder ».

### Description de la 1.2 (fr-FR)

> Color est un petit atelier de dessin pour les enfants. Tout y est grand, simple et bien rangé, pour dessiner sans avoir besoin de lire.
>
> • Le pinceau à cinq pointes, les lignes, les rectangles, les ovales et six autres formes, l’aimant qui redresse une forme dessinée à main levée, le texte, la gomme et le pot de peinture.
> • La magie : des arcs-en-ciel, de l’herbe, des briques, des confettis, et un miroir qui dessine deux fois.
> • Des tampons à poser, à tourner et à colorier.
> • Douze pages à colorier, dessinées pour Color : le bateau, le chat, le dinosaure, la tortue…
> • Dix couleurs, et leurs nuances d’un appui long.
> • Dix univers pour habiller l’atelier : le bureau près de la fenêtre, sous la mer, l’espace, la forêt, la campagne, la ville, la montagne, la savane… Le décor bouge doucement, et un double-clic sur une chose dit son nom.
> • « Revoir ton dessin » : le film de ton dessin qui se refait tout seul, trait après trait.
> • « Mes dessins » garde chaque dessin enregistré, pour le reprendre plus tard, et les montre en diaporama.
> • Annuler et rétablir, autant de fois qu’il faut.
> • Imprimer, et exporter ton dessin en image.
>
> Pour les adultes, les options règlent ce que Color montre : une interface très simplifiée pour les tout-petits, une interface moyenne, ou tout Color avec les calques ; l’univers et le mouvement du décor ; et « Toutes les couleurs, pour les grands » : le dégradé, la pipette et le mélange des couleurs. On peut aussi couper les sons ou l’impression, dessiner sans tenir le bouton, régler le toucher, calmer le trait d’une main qui tremble, déplacer un pointeur au clavier ou à la manette, écrire avec un clavier à l’écran, et protéger les options par un calcul. Color parle français et anglais.
>
> Color ne collecte aucune donnée. Pas de publicité, pas de compte, pas d’achat, pas d’Internet : tout reste sur l’appareil.
>
> Color est un logiciel libre, sous licence MIT, créé par Alejandro San Martin Lamas.

### Nouveautés de la 1.2 (fr-FR)

> Color 1.2 : un atelier tout neuf, et dix univers.
> • La feuille est trois fois plus grande. Les outils et les couleurs sont sur une ligne en bas ; « Mon dessin » et « Univers » en haut. Sur un téléphone, deux rails et un tiroir.
> • Dix couleurs sur la ligne, et leurs nuances d’un appui long. Le dégradé, la pipette et le mélange sont devenus un réglage des adultes : « Toutes les couleurs, pour les grands », dans les options.
> • Dix univers, à choisir par le bouton « Univers » : Classique, le bureau près de la fenêtre, Papier et crayons, sous la mer, l’espace, la forêt, la campagne, la ville, la montagne et la savane. Chacun habille l’atelier de ses couleurs, d’un décor autour de la feuille sur un ordinateur, et souvent d’un chapeau pour le personnage.
> • Le décor bouge doucement ; un adulte choisit combien, ou l’arrête. Au bureau près de la fenêtre, la lumière suit l’heure, et la lampe s’allume le soir.
> • Clique deux fois sur une chose du décor, ou garde le doigt dessus : son nom s’affiche, avec une petite phrase. Cent neuf fiches, vérifiées, en français et en anglais.
> • « Regarder » : chaque décor sur tout l’écran, qui bouge ; touche une chose pour savoir son nom.
> • « La pointe » : une petite pointe de couleur montre où l’outil agit ; au doigt, le pot de peinture montre ce qu’il va remplir avant que tu lèves le doigt.
> • Les 24 tampons ont été redessinés ; les dessins déjà enregistrés montrent les nouveaux.
> • De petites récompenses : des confettis quand tu enregistres, une éclaboussure de peinture, des étincelles derrière la magie. Elles se taisent quand le mouvement est arrêté, ou quand l’appareil demande moins d’animations.
> • Toute l’interface est écrite en Atkinson Hyperlegible, une écriture faite pour être lue facilement ; l’aide est refaite pour le nouvel atelier.

### Texte promotionnel de la 1.2 (fr-FR)

> Dessine, colorie et tamponne dans dix univers, puis regarde ton dessin se refaire tout seul. Sans publicité, sans compte, sans Internet.

### Description de la 1.2 (en)

> Color is a little drawing studio for children. Everything in it is big, simple and tidy, so they can draw without needing to read.
>
> • The brush with five tips, lines, rectangles, ovals and six more shapes, the magnet that straightens a freehand shape, text, the eraser and the paint pot.
> • Magic: rainbows, grass, bricks, confetti, and a mirror that draws twice.
> • Stamps to put down, turn and colour.
> • Twelve colouring pages, drawn for Color: the boat, the cat, the dinosaur, the tortoise…
> • Ten colours, and their shades with a long press.
> • Ten worlds to dress the studio: the desk by the window, under the sea, space, the forest, the countryside, the city, the mountain, the savanna… The scenery moves gently, and a double click on a thing says its name.
> • “Watch your drawing again”: the film of your drawing making itself again, line after line.
> • “My drawings” keeps every saved drawing, to go on with it later, and shows them as a slideshow.
> • Undo and redo, as many times as needed.
> • Print, and export your drawing as a picture.
>
> For grown-ups, the options set what Color shows: a very simple interface for the youngest, a medium one, or all of Color with layers; the world and the movement of its scenery; and “Every colour, for older children”: the gradient, the eyedropper and the colour mixer. You can also turn off sounds or printing, draw without holding the button, adjust touch, steady a shaky hand, move a pointer with the keyboard or a gamepad, write with an on-screen keyboard, and guard the options with a sum. Color speaks French and English.
>
> Color collects no data. No ads, no account, no purchases, no Internet: everything stays on the device.
>
> Color is free software, under the MIT licence, created by Alejandro San Martin Lamas.

### Nouveautés de la 1.2 (en)

> Color 1.2: a brand-new studio, and ten worlds.
> • The sheet is three times bigger. The tools and the colours are on a line at the bottom; “My drawing” and “Worlds” at the top. On a phone, two rails and a drawer.
> • Ten colours on the line, and their shades with a long press. The gradient, the eyedropper and the mixer are now a setting for adults: “Every colour, for older children”, in the options.
> • Ten worlds, chosen with the “Worlds” button: Classic, the desk by the window, paper and pencils, under the sea, space, the forest, the countryside, the city, the mountain and the savanna. Each one dresses the studio in its colours, with a scenery around the sheet on a computer, and often a hat for the companion.
> • The scenery moves gently; an adult chooses how much, or stops it. At the desk by the window, the light follows the time of day, and the lamp comes on in the evening.
> • Double-click a thing in the scenery, or keep your finger on it: its name appears, with a short sentence. A hundred and nine cards, checked, in French and English.
> • “Watch”: each scenery on the whole screen, moving; touch a thing to learn its name.
> • “The tip”: a small coloured tip shows where the tool acts; with a finger, the paint pot shows what it will fill before you lift your finger.
> • The 24 stamps have been redrawn; drawings already saved show the new ones.
> • Small rewards: confetti when you save, a splash of paint, sparkles behind the magic. They stay quiet when the movement is stopped, or when the device asks for fewer animations.
> • The whole interface is written in Atkinson Hyperlegible, a typeface made to be easy to read; the help is new, for the new studio.

### Texte promotionnel de la 1.2 (en)

> Draw, colour and stamp in ten worlds, then watch your drawing make itself again. No ads, no account, no Internet.

### Notes pour la vérification de la 1.2

En anglais, pour le relecteur d'Apple ; sur la page du Mac, « the device » devient « the Mac ».

> Color is a drawing app for children, in French and English: it follows the language of the device, or the one chosen in the options. It has no account, no in-app purchase, no advertising, no analytics and no network access: nothing leaves the device.
>
> Version 1.2 has a new interface. The tools and the colours are on a line at the bottom of the screen (on an iPhone, on two rails beside the sheet, the rest in a drawer). “My drawing”, at the top left, opens New, Open, My drawings, On a picture, Export, Print, Help, Options and About. “Worlds”, beside it, dresses the studio in one of ten worlds; on a computer, a scenery surrounds the sheet. On an iPhone or an iPad, a world is watched full screen with “Watch”, under each world in “Choose your world”; “← My drawing” brings the sheet back.
>
> To try it: choose a tool at the bottom (brush, shapes, stamps, text, eraser, paint pot), pick a colour and draw on the sheet. A long press on a colour opens its shades. A double click, or a long press, on a thing of the scenery shows a small card with its name and one or two lines; it has no link. “My drawing” → “New” offers colouring pages: choose one, then colour its zones with the paint pot (“Fill”). The film button at the top replays the drawing (“Watch your drawing again”). “Save” keeps it; “My drawings” lists saved drawings. “Print” opens the system’s print panel.
>
> The options (“My drawing” → “Options”) are for adults: interface level, world and movement of the scenery, sounds, printing, accessibility, and “Every colour, for older children” (the gradient, the eyedropper and the mixer). By default they open directly. When the option “Guard the options with a sum” is on, a multiplication of the tables from 6 to 9 is asked first: the answer is the product of the two numbers shown.
>
> Color has no link out of the app and no purchase. “Open”, “On a picture” and “Export” use the system’s file panels, which stay inside the app; saving keeps the drawing in the app’s own folder, and printing uses the system’s print panel. The time of the device is read only to light the desk scenery; it is neither kept nor sent.
>
> The privacy policy is also in the app: “My drawing” → “About” → “Privacy”. Interface names above are the English ones; in French: « Mon dessin », « Univers », « Regarder », « Nouveau », « Remplir », « Enregistrer », « Mes dessins », « Imprimer », « Options », « À propos » → « Confidentialité ».

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
