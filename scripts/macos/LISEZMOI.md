# Construire Color sur le Mac du projet

Quatre fichiers : trois pour obtenir `Color.app` sans taper une commande, un pour contrôler ce qui a été remis.

| Fichier | Rôle |
|---|---|
| `Construire Color pour Mac.command` | Le fichier à ouvrir depuis le Finder. Il cherche Python, empêche la mise en veille et lance le programme ci-dessous dans une fenêtre du Terminal. |
| `construire-color.py` | Vérifie l'outillage, lance la recette du projet sans la modifier ([`build-flutter-study.py`](../build-flutter-study.py)), remet l'application à côté des sources, puis lance les tests du cœur Rust. |
| `essai-du-lanceur.py` | Essaie `construire-color.py` hors du Mac, avec de faux outils. Il éprouve le lanceur, pas une construction. |
| `controler-la-remise.py` | Contrôle après coup, sans rien y changer, l'application remise par un passage : est-elle la sortie de la recette, ses empreintes sont-elles celles du journal, contient-elle tel changement — un texte dans le cœur, dans le code Dart ou dans le programme, un droit ajouté à la signature. Il ne lance aucun programme du Mac, n'ouvre pas l'application, et n'écrit que son compte rendu, quand on le lui demande. |

## Disposition attendue sur le Mac

Le lanceur et son programme ne se lancent pas depuis ce dossier du dépôt. Ils s'installent, avec le programme de contrôle, dans un dossier de travail, à côté des sources à construire :

```text
Color-travail/
  Construire Color pour Mac.command
  construction-mac/
    construire-color.py
    controler-la-remise.py
    journal/                      un dossier par passage
  Color-<version>-sources/Color/  les sources, telles que l'archive les déplie
  Color <version> pour Mac/       la remise : Color.app, son ZIP, une notice
```

Le programme construit le dossier `Color-<version>-sources` dont le numéro de version est le plus élevé ; un autre peut être nommé en second argument. Chaque version a ses propres dossiers de travail, `macos-color-<version>-work` et `-release`, dans le dossier de construction local (`~/Color-construction`, ou celui que nomme la variable `COLOR_LOCAL_BUILD`), qui contient déjà le SDK Flutter épinglé et le cache des dépendances.

## Ce qu'il lui faut

- Le disque « Extreme SSD » branché : le SDK Dart du projet s'y trouve.
- Xcode, et Rust installé par Homebrew. Color suit le Rust de Homebrew, quelle qu'en soit la version ([`scripts/rust-reference.json`](../rust-reference.json)) : le programme lit ce que Homebrew propose sur ce Mac, sans rien installer ni mettre à jour. Il le signale d'une ligne, sans s'arrêter, quand une version plus récente y attend — « brew upgrade rust » la prend — ou quand le Rust trouvé n'est pas celui de Homebrew.
- Au moins 4 Go libres. Chaque version construite occupe environ 1 Go dans le dossier de construction local.

Quand quelque chose manque, le programme le dit et s'arrête avant de rien construire.

## Ce qu'il garantit, et ce qu'il ne fait pas

- Chaque passage a son journal et remet son application dans un dossier à lui : rien de ce qui a été remis n'est remplacé. Seuls ses dossiers de travail sont rafraîchis d'un passage à l'autre, par la recette elle-même.
- Si seuls des tests de l'interface arrêtent la recette, une application est tout de même compilée et remise dans un dossier marqué « NON QUALIFIEE », avec la liste des tests en échec.
- Il n'ouvre pas l'application : il la montre dans le Finder. L'essai à l'écran reste à faire par une personne.
- Il n'envoie aucun événement de clavier ou de souris, ne réveille aucune machine virtuelle, n'imprime rien.

## Depuis Color 0.7.1 : le cœur est construit par cargo

Le lanceur n'a pas changé : les trois fichiers installés sur le Mac le 4 octobre sont ceux de ce dossier, à l'octet près. Ce qui change est dans la recette qu'il exécute, [`build-flutter-study.py`](../build-flutter-study.py), parce que le cœur Rust a désormais une dépendance — usvg, pour lire le SVG ([bibliothèques tierces](../../docs/BIBLIOTHEQUES-TIERCES.md)) :

- **cargo au lieu de `rustc` seul.** cargo vient avec le Rust de Homebrew : rien de plus à installer. Sans cargo, la recette s'arrête en le disant.
- **Rien n'est téléchargé.** Les sources des 22 bibliothèques sont dans `Color/prototypes/native-swift-rust/core/vendor/`, et le réglage du dossier du cœur (`.cargo/config.toml`) interdit le réseau à cargo. La recette l'appelle avec `--offline --frozen`.
- **Un contrôle avant cargo** : [`check-vendored-sources.py`](../check-vendored-sources.py) compare chaque fichier de `vendor/` à son empreinte et dit en clair ce qui manque. C'est la raison pour laquelle les sources se déplient **depuis leur archive** : une copie faite par un outil ou une commande qui laisse de côté les fichiers dont le nom commence par un point perdrait `.cargo/config.toml` et les listes d'empreintes, et la construction s'arrêterait là.
- **Où cargo travaille** : dans `macos-color-cargo-target`, dans le dossier de construction local, à côté des dossiers de travail. Le lanceur s'en servait déjà pour les tests du cœur ; la première construction y compile les bibliothèques, les suivantes les retrouvent.
- **La bibliothèque du cœur est mise en place d'un coup** : écrite à côté de sa place, puis déplacée. La réécrire sur place, comme le faisait la première forme de cette recette, risquait sur Apple Silicon qu'une seconde construction de la même version soit arrêtée par le système pour signature invalide ; c'est une lecture du code, non vérifiée faute de Mac.
- **Les tests du cœur**, que le lanceur lance après la recette, comptent sur le Mac quatre tests de moins que sous Linux : ceux qui essaient le lecteur de sons de Linux.

**Rien de cela n'avait été exécuté sur un Mac quand ces lignes ont été écrites.** Hors du Mac, `essai-du-lanceur.py` rejoue le lanceur et la recette avec un faux cargo : le cœur « compilé » par cargo, une compilation du cœur en échec, une copie des sources abîmée.

## Ce qui est prouvé, et comment

Sur le Mac, seul le chemin réussi a été exercé : les rapports [`color-0.7.0-atelier-macos`](../../reports/flutter/color-0.7.0-atelier-macos/README.md) et suivants. Le lanceur y a tourné une fois dans sa forme actuelle, pour [0.7.0+31](../../reports/flutter/color-0.7.0+31-macos/README.md) ; les trois constructions précédentes avaient employé ses formes antérieures. Le programme de contrôle n'est pas lancé par macOS : il lit les dossiers du Mac depuis un environnement Linux qui les voit. Sa forme actuelle a servi une fois, pour 0.7.0+31 ; la précédente pour 0.7.0+29 et 0.7.0+30 ; il n'existait pas pour 0.7.0+28. Les refus et les réserves — disque absent, Xcode muet, place insuffisante, tests en échec, sources incomplètes, seconde remise, Rust qui n'est pas celui de Homebrew ou que Homebrew a dépassé — sont éprouvés hors du Mac par `essai-du-lanceur.py` :

```sh
python3 scripts/macos/essai-du-lanceur.py
```

Cet essai remplace Xcode, Flutter, Rust, `codesign` et `ditto` par de petits scripts ; la recette du projet y tourne telle quelle sur une copie des sources. Il ne dit rien d'une vraie construction.
