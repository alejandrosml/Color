# Publier Color : le chemin, étape par étape

*Pour la version 1.0.0 (37) ; mis à jour le 27 octobre 2026.* Ce que fait chaque lanceur est écrit en tête de son script, dans `construction-mac/`. Après chaque mise à jour de Xcode, ouvre Xcode une fois avant de lancer un lanceur : il installe parfois des composants dont le simulateur a besoin.

## 1. Essayer Color sur iPhone, iPad et Android, sur le Mac

1. Double-clique **`Essayer Color sur iPhone et iPad.command`**. La première fois, Xcode télécharge le simulateur d'iOS (plusieurs gigaoctets), puis le lanceur installe Rust pour iOS. Il construit Color, crée un iPad et un iPhone dans le simulateur, y fait l'essai intégré (le cœur, les fichiers, une image, un son), et y laisse Color ouverte. Essaie-la à la souris ou au trackpad : un clic vaut un doigt.
2. Double-clique **`Essayer Color sur Android.command`**. La première fois, il installe un JDK et les outils d'Android, environ 6 Go en tout, dans le dossier `mobiles` à côté des dossiers de construction. **Les licences de Google s'affichent dans le Terminal : c'est toi qui les acceptes**, en répondant `y`. Puis il fait de même sur une tablette et un téléphone de l'émulateur.
3. Les deux écrivent leur journal et leurs captures dans `construction-mac/journal/`. Les captures de l'iPad et de l'iPhone sont aux tailles que l'App Store prend telles quelles.

## 2. Publier le code et les pages de confidentialité et d'aide

Les boutiques demandent une adresse web pour la politique de confidentialité et une pour l'aide. Elles seront sur GitHub, avec le code :

1. Sur [github.com/new](https://github.com/new), avec ton compte `alejandrosml` : nom du dépôt **`Color`**, **Public**, sans README ni licence (le code les apporte). « Create repository ». *Fait le 27 octobre.*
2. Dis-le-moi : j'y publie le code de Color, sous licence MIT, avec son README, sans l'historique de travail ni les journaux. *Fait le 27 octobre.*
3. Puis, dans le dépôt : **Settings → Pages → Source : « Deploy from a branch » → `main`, dossier `/docs` → Save**. Une minute plus tard, `https://alejandrosml.github.io/Color/` et `https://alejandrosml.github.io/Color/confidentialite.html` répondent.

## 3. Le Mac App Store, l'iPhone et l'iPad

Le lanceur « Envoyer Color vers l'App Store » ne sert qu'à la fin : il envoie Color dans **ton** compte d'Apple, qui doit exister avant. Tant que ces trois préparatifs ne sont pas faits, il ne peut rien envoyer.

**Les préparatifs, une seule fois :**

1. **Adhérer à l'Apple Developer Program**, comme particulier : [developer.apple.com/programs/enroll](https://developer.apple.com/programs/enroll/), ou l'app « Apple Developer » du Mac. 99 USD par an, payés en euros. Ton nom légal s'affichera comme vendeur. Attends le courriel d'Apple qui confirme l'adhésion : en général un ou deux jours.
2. **Donner ton compte à Xcode** : ouvre Xcode → menu **Xcode → Réglages… → Comptes** → « + » en bas à gauche → **Apple ID** → ton adresse et ton mot de passe. Ton nom apparaît alors dans la liste des équipes.
3. **Créer la place de Color chez Apple**, en deux pages :
   1. [Les identifiants de ton compte](https://developer.apple.com/account/resources/identifiers/list) : « + » → **App IDs** → **App** → Description `Color`, Bundle ID **Explicit** : `fr.aisml.color` → Continue → Register.
   2. [App Store Connect](https://appstoreconnect.apple.com) → **Apps** → « + » → **Nouvelle app** : coche **iOS** et **macOS** ; nom **Color** (s'il est pris : **Color Atelier de Dessin**) ; langue principale **Français** ; identifiant de lot **fr.aisml.color** ; SKU `color` ; accès complet → **Créer**.

**Ensuite, à chaque version :**

4. Double-clique **`Envoyer Color vers l'App Store.command`**. La première fois, il peut te demander ton **Team ID** : 10 lettres et chiffres, sur [ton compte de développeur](https://developer.apple.com/account), rubrique « Membership details ». Il construit Color pour le Mac puis pour l'iPhone et l'iPad, les fait signer par Xcode et les envoie. **Rien n'est publié à ce moment.**
5. Une demi-heure plus tard environ, les versions apparaissent dans App Store Connect → Color → **TestFlight**. Installe l'app **TestFlight** depuis le Mac App Store pour essayer la version Mac, telle qu'Apple la distribuera.
6. Remplis la fiche avec [FICHE-APP-STORE.md](FICHE-APP-STORE.md) : textes, catégorie, âge, confidentialité (« aucune donnée collectée »), statut de **non-professionnel**, captures. Choisis la version envoyée, puis « Ajouter pour vérification ». Apple vérifie en général en un ou deux jours, et Color paraît dès que tu le décides.

## 4. Google Play

1. **Créer un compte de développeur personnel** sur [play.google.com/console](https://play.google.com/console) : 25 USD une seule fois, une pièce d'identité. Google demande aussi de vérifier l'accès à un appareil Android avec l'app Play Console : il faut, cette fois-ci, un téléphone Android, même prêté.
2. Double-clique **`Préparer Color pour Google Play.command`**, après l'essai sur Android. La première fois, il crée ta **clé d'envoi** dans `Documents/Color - clé Google Play`. **Garde une copie de ce dossier en lieu sûr.** Il fait ensuite le fichier `google-play/Color-1.0.0+37.aab`.
3. Dans la Play Console : créer l'application **Color** (gratuite, application), remplir « Contenu de l'application » et la fiche avec [FICHE-GOOGLE-PLAY.md](FICHE-GOOGLE-PLAY.md).
4. **Test fermé** : créer une version avec le fichier `.aab`, ajouter au moins **12 testeurs**, et attendre **14 jours d'affilée**. Puis demander l'accès à la production depuis le tableau de bord, et publier.

## Ce que je ne peux pas faire à ta place

- Payer, adhérer, accepter les conditions d'Apple et de Google, créer les fiches dans App Store Connect et la Play Console : ce sont tes comptes.
- Accepter les licences d'Android : le lanceur te les montre.
- Créer le dépôt GitHub : ton compte, ta décision ; ensuite, j'y publie le code.
