# Color

![Le logo de Color : un enfant dans son fauteuil roulant électrique lève son crayon.](docs/icone-app-store-1024.png)

**Color** est un petit atelier de dessin pour les enfants, inspiré de Tux Paint mais écrit entièrement de zéro : sur Mac, iPhone, iPad et Android. Le pinceau, les formes, les tampons, le texte, la gomme, le pot de peinture, douze pages à colorier, « Mes dessins », l'impression, et le film du dessin qui se refait tout seul. Sans publicité, sans compte, sans Internet : Color ne collecte aucune donnée ([confidentialité](docs/confidentialite.html)).

Créé par **Alejandro San Martin Lamas**. Logiciel libre sous [licence MIT](LICENSE) : chacun peut l'utiliser, le copier, le modifier et le redistribuer, en gardant la mention de son auteur.

## Comment il est fait

- L'interface en Dart, avec Flutter : `prototypes/flutter-rust/lib/`.
- Le cœur en Rust — le document, son format de fichier, l'historique, les pages à colorier, les tampons, les sons : `prototypes/native-swift-rust/core/`. Ses seules bibliothèques, celles de la lecture SVG, sont recopiées dans `vendor/` : rien n'est téléchargé pour le construire.
- Ce que seul chaque système sait faire : en Swift sur le Mac, l'iPhone et l'iPad (impression, sons, enregistrement), en Kotlin sur Android (impression, enregistrement).

## Construire

- Flutter 3.47 et le Rust de Homebrew (1.99).
- Mac : `scripts/macos/construire-color.py`.
- iPhone et iPad, Android : `scripts/macos/essayer-ios.py` et `scripts/macos/essayer-android.py` installent ce qu'il faut, construisent Color et l'essaient dans le simulateur et l'émulateur ; `scripts/android/construire-le-coeur.sh` construit le cœur pour Android.
- Les tests : `cargo test` dans le dossier du cœur, `flutter test` dans celui de l'application.

Les sons, la police et les bibliothèques gardent leurs propres licences : `prototypes/native-swift-rust/core/sons/PROVENANCE.md`, `prototypes/native-swift-rust/core/third-party-notices.txt`, `prototypes/flutter-rust/fonts/LICENCE-DejaVu.txt`.
