**Color pour Windows, en version expérimentale** : le même atelier de dessin pour les enfants que sur le Mac App Store, pour Windows 10 et 11 (x64) et Windows 11 sur ARM.

## Pour l'essayer

1. Télécharge `Color-…-windows-x64.zip` (la plupart des PC) ou `Color-…-windows-arm64.zip` (PC « Copilot+ » à processeur Snapdragon).
2. Dézippe-le où tu veux, puis double-clique `color.exe`. Rien ne s'installe ; pour l'enlever, supprime le dossier.

## Windows affichera un avertissement

**Cette version n'est pas encore signée.** Au premier lancement, Windows peut afficher « Windows a protégé votre ordinateur », comme pour tout programme qu'il ne connaît pas encore : « Informations complémentaires », puis « Exécuter quand même ». Les empreintes SHA-256 des fichiers sont écrites plus bas.

Les fichiers `.msix` sont les paquets préparés pour le Microsoft Store : ils ne sont pas signés non plus, et ne s'installent pas par un double clic.

## Ce qui a été essayé

Ces fichiers sont construits et essayés automatiquement sur de vrais Windows, les machines de GitHub ([le flux « Windows »](../../actions/workflows/windows.yml)) : les tests du cœur et de l'interface, le lancement, un parcours complet de l'atelier dans sa fenêtre (dessiner, enregistrer, rouvrir, exporter, les options, le film du dessin), la fenêtre d'impression de Windows et des pages imprimées dans des fichiers PDF.

Pas encore essayé : le stylet et l'écran tactile, les sons (ces machines n'ont pas de haut-parleur), les affichages agrandis à 150 et 200 %, une vraie imprimante. Un problème ? [Dis-le ici](../../issues).

Color ne collecte aucune donnée : ni publicité, ni compte, ni Internet. Logiciel libre sous licence MIT, créé par Alejandro San Martin Lamas — https://github.com/alejandrosml
