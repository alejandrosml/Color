# Color sur Google Play — la fiche, prête à coller

## Fiche du Play Store

| Champ | À mettre |
|---|---|
| Nom de l'application (30) | Color |
| Description courte (80) | Un atelier de dessin pour les enfants : pinceau, tampons, pages à colorier. |
| Description complète (4 000) | La description de l'App Store ([FICHE-APP-STORE.md](FICHE-APP-STORE.md)), telle quelle |
| Icône (512 × 512) | [`icone-google-play-512.png`](icone-google-play-512.png) |
| Image de présentation (1024 × 500) | [`image-google-play-1024x500.png`](image-google-play-1024x500.png) |
| Captures de téléphone (2 à 8) | `captures/telephone.png` du journal de « Essayer Color sur Android » |
| Captures de tablette 10 pouces | `captures/tablette.png` du même journal |
| Catégorie | Éducation |
| Adresse e-mail de contact | **À choisir par toi** : Google l'affiche sur la fiche. Une adresse réservée à Color évite de montrer ton adresse personnelle |
| Site web | `https://alejandrosml.github.io/Color/` |
| Règles de confidentialité | `https://alejandrosml.github.io/Color/confidentialite.html` |
| Prix | Gratuite |

## « Contenu de l'application » (Règles et programmes)

| Déclaration | Réponse |
|---|---|
| Règles de confidentialité | L'adresse ci-dessus |
| Publicités | L'application ne contient pas de publicités |
| Accès à l'application | Toutes les fonctionnalités sont disponibles sans accès spécial |
| Classification du contenu | Questionnaire IARC : catégorie « Toutes les autres applications » ; « non » à toutes les questions (violence, peur, sexualité, jeux d'argent, achats, partage de données, contenu généré partagé) : PEGI 3 attendu |
| Public cible | « 5 ans et moins », « 6 à 8 ans », « 9 à 12 ans ». Les règles « Familles » s'appliquent alors : Color les respecte (aucune donnée, aucune publicité, aucun SDK de tiers qui en ferait) |
| Sécurité des données | « Aucune donnée collectée », « Aucune donnée partagée » |
| Application gouvernementale, fonctionnalités financières, santé, actualités | Non |

## La version

- Fichier : `google-play/Color-1.0.0+39.aab`, fait par « Préparer Color pour Google Play » et signé avec ta clé d'envoi.
- Nom de la version : 1.0.0 (39).
- Notes de version : « Première version de Color. »
- Signature de l'application par Google Play (« Play App Signing ») : accepter. Google garde la clé qui signe Color ; ta clé d'envoi ne sert qu'à lui confier les fichiers.

## La version 1.1

- Notes de version (500 caractères par langue au plus), en français : « Nouveaux outils : formes, aimant, magie (arc-en-ciel, herbe, briques, confettis, miroir), pinceau à cinq pointes, gomme qui coupe, pot avec dégradés, mélangeur de couleurs, quatre écritures de plus, diaporama de Mes dessins. Plus facile à toucher. Color parle anglais. Un dessin abîmé s'ouvre quand même. Les dessins enregistrés avec la 1.1 ne s'ouvrent plus avec les versions précédentes. »
- En anglais (« en-GB » ou « en-US ») : « New tools: shapes, magnet, magic (rainbow, grass, bricks, confetti, mirror), five brush tips, an eraser that cuts lines, a paint pot with gradients, a colour mixer, four more fonts, a slideshow of My drawings. Easier to touch. Color speaks English. A damaged drawing still opens. Drawings saved with 1.1 no longer open in earlier versions. »
- La fiche en anglais : nom « Color », description courte « A drawing studio for children: brushes, stamps, colouring pages. », description complète : celle de l'App Store en anglais ([FICHE-APP-STORE.md](FICHE-APP-STORE.md)).
- Les tailles de l'App Bundle de la 1.1 ne sont pas encore mesurées : la préparation les donne et ne s'arrête pas (`scripts/budgets.json`) ; on les écrit ensuite dans ce fichier.

## Avant la production : 12 testeurs, 14 jours

Un compte personnel créé après le 13 novembre 2023 doit d'abord publier Color en **test fermé**, avec **au moins 12 testeurs** inscrits **14 jours d'affilée**. Ensuite seulement, le tableau de bord de la Play Console propose de demander l'accès à la production. Les testeurs : des personnes de ton entourage avec un téléphone ou une tablette Android et un compte Google ; tu ajoutes leurs adresses dans la liste du test fermé, ils acceptent l'invitation et installent Color depuis le lien du test.

## Sources

- [Tests des nouveaux comptes personnels](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en-GB)
- [Inscription à la Play Console](https://support.google.com/googleplay/android-developer/answer/6112435?hl=en)
- [Règles « Familles »](https://support.google.com/googleplay/android-developer/answer/9893335?hl=en)
- [Niveau d'API cible](https://developer.android.com/google/play/requirements/target-sdk)
