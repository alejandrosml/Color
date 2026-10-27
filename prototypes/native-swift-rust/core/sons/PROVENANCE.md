# Provenance des sons enregistrés

Écrit par [`scripts/sons/preparer-les-sons.py`](../../../../scripts/sons/preparer-les-sons.py) : ne pas modifier à la main. Les tests du cœur relisent ce fichier.

Ces sons du catalogue de `src/sound.rs` sont des enregistrements, et non plus des recettes calculées par le cœur. Chacun est un court extrait d’un fichier publié sous **CC0** ou versé au **domaine public** par son auteur : aucune attribution n’est exigée, Color cite tout de même ses sources, ici et dans « À propos » → « Licences ». Aucun ne vient de Tux Paint ni d’EduPaint. Les originaux ne sont pas gardés dans le dépôt : chacun se retélécharge à l’adresse donnée et se reconnaît à son empreinte SHA-256. Pour un son de Freesound, le fichier utilisé est l’aperçu en Ogg Vorbis que le site publie pour tous : il ne donne l’original qu’à un compte connecté.

Traitement commun, dans cet ordre : décodage par FFmpeg ; une seule voie, moyenne des voies de l’original ; passage à 44 100 Hz s’il le faut (sinus cardinal fenêtré par Blackman, 32 lobes de part et d’autre) ; retrait de la composante continue ; passe-haut de Butterworth d’ordre 2 à 60 Hz, appliqué dans les deux sens ; pour certains, un passe-bas du même ordre, appliqué de même, nommé plus bas ; extrait ; montée et descente en courbe « smoothstep », qui partent de zéro et y reviennent exactement ; retrait, le long d’une arche nulle aux deux bouts, de ce qui pousserait le haut-parleur d’un côté (la somme des échantillons devient nulle) ; mise à l’échelle de l’échantillon le plus fort à la crête donnée ; arrondi au plus proche sur 16 bits. Fichier : WAV PCM, mono, 16 bits, 44 100 Hz, en-tête de 44 octets. Pour refaire les fichiers : placer les originaux dans un dossier, puis `python3 -I scripts/sons/preparer-les-sons.py DOSSIER` (`--check` vérifie sans rien écrire).

## « trait » — Pinceau

Ce qu’on entend : un pinceau qui passe une fois sur une feuille. Un seul passage de pinceau, pris dans un enregistrement où l’on dessine, brosse, peint et vernit un vieux parchemin, de près, sans bruit de fond ni réverbération. Il revient sans cesse pendant qu’on peint : adouci au-dessus de 5 000 Hz.

- Enregistrement : « Parchment - Draw & paint », enregistré par Vrymaa (Freesound, son n° 753281), publié le 5 septembre 2024
- Page : <https://freesound.org/people/Vrymaa/sounds/753281/>
- Fichier original : <https://freesound.org/people/Vrymaa/sounds/753281/> — WAV, 48 kHz, 16 bits, mono, 1 min 0,7 s ; Freesound ne le donne qu’à un compte connecté
- Fichier utilisé : <https://cdn.freesound.org/previews/753/753281_13973196-hq.ogg> — l’aperçu en Ogg Vorbis que Freesound publie pour tous
- Licence : CC0 1.0 universel (transfert dans le domaine public) — <https://creativecommons.org/publicdomain/zero/1.0/deed.fr>
- SHA-256 du fichier utilisé : `7fbc6dad2d1a5bf08af4936aa7b1f4f92e9c52a9b63c81760f342da60259851b`
- Adouci : passe-bas de Butterworth d’ordre 2 à 5 000 Hz, appliqué dans les deux sens
- Extrait : de 33,100 s à 33,580 s du fichier
- Montée 5 ms, descente 60 ms, crête 3400 (−19,7 dBFS)
- Fichier du cœur : `sons/trait.wav`, 42380 octets, 21168 échantillons (0,480 s)
- SHA-256 du fichier du cœur : `a4df7c6d85b2786bfdec883258c74acbae5dc77cf8e1a50af98a559208ebc3eb`

## « forme » — Ligne, rectangle, ovale

Ce qu’on entend : un crayon de papier qui trace un trait rapide sur une feuille. Un seul trait, pris dans un enregistrement de crayon qui écrit sur du papier : le grain du papier, un appui qui enfle puis s’éteint.

- Enregistrement : « pencil_write », enregistré par NachtmahrTV (Freesound, son n° 571800) et republié par AntumDeluge dans « Pencil Sounds » sur OpenGameArt, le 29 novembre 2021
- Page : <https://opengameart.org/content/pencil-sounds>
- Fichier original : <https://opengameart.org/sites/default/files/pencil.zip> — membre `flac/pencil_write.flac` de l’archive
- Licence : CC0 1.0 universel (transfert dans le domaine public) — <https://creativecommons.org/publicdomain/zero/1.0/deed.fr>
- SHA-256 de l’original : `e944c3a6261b4eda793247e90e0905a9b3a2bec48a4fab44fdd63a08109cd28a`
- SHA-256 de `flac/pencil_write.flac` : `aa835e94c7bafed9e096684a709f20de806083da5511e284d802bd16e244c025`
- Extrait : de 0,880 s à 1,200 s du fichier
- Montée 5 ms, descente 30 ms, crête 4600 (−17,1 dBFS)
- Fichier du cœur : `sons/forme.wav`, 28268 octets, 14112 échantillons (0,320 s)
- SHA-256 du fichier du cœur : `a5d35e3d11d6102c1cee235e1b0fe3a2df2fde28b4b0bb1b53d5c965a7b82d85`

## « tampon » — Tampon

Ce qu’on entend : un tampon qu’on appuie d’un coup sur une lettre. Un seul coup, pris parmi les dizaines d’un enregistrement qu’un ancien postier a fait pour retrouver le bruit des lettres qu’on tamponne au guichet : un coup sourd et bref, éteint en un cinquième de seconde.

- Enregistrement : « stamp post office mail.wav », enregistré par frank_the_noise (Freesound, son n° 160879), publié le 9 juillet 2012
- Page : <https://freesound.org/people/frank_the_noise/sounds/160879/>
- Fichier original : <https://freesound.org/people/frank_the_noise/sounds/160879/> — WAV, 48 kHz, 16 bits, stéréo, 1 min 56,5 s ; Freesound ne le donne qu’à un compte connecté
- Fichier utilisé : <https://cdn.freesound.org/previews/160/160879_1481750-hq.ogg> — l’aperçu en Ogg Vorbis que Freesound publie pour tous
- Licence : CC0 1.0 universel (transfert dans le domaine public) — <https://creativecommons.org/publicdomain/zero/1.0/deed.fr>
- SHA-256 du fichier utilisé : `b1bfc491e67d9e495ae2ac32d9289b2291a9915dd15c15913a4b62ee90dd8153`
- Extrait : de 57,582 s à 57,872 s du fichier
- Montée 4 ms, descente 60 ms, crête 5000 (−16,3 dBFS)
- Fichier du cœur : `sons/tampon.wav`, 25622 octets, 12789 échantillons (0,290 s)
- SHA-256 du fichier du cœur : `2afd4af8bbb27ce7948deb354c5276c02f4a09d80e591994a3e6afe2d1119fd0`

## « pot » — Remplir

Ce qu’on entend : un seau d’eau qu’on vide, l’eau qui coule puis tombe à flots. Le seau penche, un filet coule, puis le seau bascule et l’eau tombe à flots ; l’extrait s’éteint pendant qu’elle coule encore. Adouci au-dessus de 6 000 Hz : les éclaboussures y sifflaient.

- Enregistrement : « pouring bucket », enregistré par 13F_Panska_Koprivikova_Klara (Freesound, son n° 378317), publié le 29 janvier 2017
- Page : <https://freesound.org/people/13F_Panska_Koprivikova_Klara/sounds/378317/>
- Fichier original : <https://freesound.org/people/13F_Panska_Koprivikova_Klara/sounds/378317/> — WAV, 48 kHz, 16 bits, stéréo, 4,2 s ; Freesound ne le donne qu’à un compte connecté
- Fichier utilisé : <https://cdn.freesound.org/previews/378/378317_7020096-hq.ogg> — l’aperçu en Ogg Vorbis que Freesound publie pour tous
- Licence : CC0 1.0 universel (transfert dans le domaine public) — <https://creativecommons.org/publicdomain/zero/1.0/deed.fr>
- SHA-256 du fichier utilisé : `3d43aaa1d3fe669443b7952e9654b413350620c5a697d9406c30d19076980c3d`
- Adouci : passe-bas de Butterworth d’ordre 2 à 6 000 Hz, appliqué dans les deux sens
- Extrait : de 0,700 s à 1,600 s du fichier
- Montée 8 ms, descente 200 ms, crête 5000 (−16,3 dBFS)
- Fichier du cœur : `sons/pot.wav`, 79424 octets, 39690 échantillons (0,900 s)
- SHA-256 du fichier du cœur : `431d166156b9b77b2d09f52bfc92357b8cb33e07c262db9a07a9660a2243669a`

## « gomme » — Gomme

Ce qu’on entend : une gomme qui efface du crayon sur une feuille, en trois allers-retours. Une gomme en plastique qui efface un trait de crayon sur une feuille de cahier ; adouci au-dessus de 6 000 Hz, où le frottement sifflait. Elle remplace « pencil_erase » de « Pencil Sounds », qui était en fait un doigt frotté sur une vitre (« window finger rub », de damsur, Freesound n° 443241) : il grinçait au lieu de frotter.

- Enregistrement : « eraser.aiff », enregistré par jc144940 (Freesound, son n° 180943), publié le 15 mars 2013
- Page : <https://freesound.org/people/jc144940/sounds/180943/>
- Fichier original : <https://freesound.org/people/jc144940/sounds/180943/> — AIFF, 44,1 kHz, stéréo, 12,8 s ; Freesound ne le donne qu’à un compte connecté
- Fichier utilisé : <https://cdn.freesound.org/previews/180/180943_2596329-hq.ogg> — l’aperçu en Ogg Vorbis que Freesound publie pour tous
- Licence : CC0 1.0 universel (transfert dans le domaine public) — <https://creativecommons.org/publicdomain/zero/1.0/deed.fr>
- SHA-256 du fichier utilisé : `d2b8c2fa7dd6dad8dcc2757178b51fcdb724ceec891480fa0e923ccbbb67b895`
- Adouci : passe-bas de Butterworth d’ordre 2 à 6 000 Hz, appliqué dans les deux sens
- Extrait : de 7,900 s à 8,380 s du fichier
- Montée 5 ms, descente 40 ms, crête 4800 (−16,7 dBFS)
- Fichier du cœur : `sons/gomme.wav`, 42380 octets, 21168 échantillons (0,480 s)
- SHA-256 du fichier du cœur : `5195aa447212a9db0e73d55279230b76b2756b03a18a9ee38685a6f1f868f849`

## « texte » — Texte

Ce qu’on entend : trois frappes d’une machine à écrire, sans la sonnette. Trois touches d’une vraie machine à écrire, enregistrées de près au téléphone ; les frappes sont vives, comme sur la machine.

- Enregistrement : « typewriter8 », enregistré au téléphone par Cassie-OrbitGames, « Typewriter sounds » sur OpenGameArt, le 6 septembre 2025
- Page : <https://opengameart.org/content/typewriter-sounds>
- Fichier original : <https://opengameart.org/sites/default/files/typewriter8.wav>
- Licence : CC0 1.0 universel (transfert dans le domaine public) — <https://creativecommons.org/publicdomain/zero/1.0/deed.fr>
- SHA-256 de l’original : `c29966383e602df84db68577758e34f830deb01aff6a208579ee943511217118`
- Extrait : de 0,030 s à 0,420 s du fichier
- Montée 4 ms, descente 25 ms, crête 4950 (−16,4 dBFS)
- Fichier du cœur : `sons/texte.wav`, 34442 octets, 17199 échantillons (0,390 s)
- SHA-256 du fichier du cœur : `3408ee12b1a796b6be3cb171f79de08eb195b9b6361485aaf7e84557dd0a3bd2`

## « choisir » — Choisir

Ce qu’on entend : un petit clic, bref et sourd. Un clic pris en entier dans le jeu de sons d’interface de Kenney.

- Enregistrement : « click2 », du « UI SFX Set » (UI Audio) de Kenney Vleugels, Kenney.nl
- Page : <https://kenney.nl/assets/ui-audio>
- Fichier original : <https://kenney.nl/media/pages/assets/ui-audio/490d233f68-1677590494/kenney_ui-audio.zip> — membre `Audio/click2.ogg` de l’archive
- Licence : CC0 1.0 universel (transfert dans le domaine public) — <https://creativecommons.org/publicdomain/zero/1.0/deed.fr>
- SHA-256 de l’original : `946fc23a63d535d693eb31b2eabb80c8c28d6351e2186b344ceb71b2cb1d5eb6`
- SHA-256 de `Audio/click2.ogg` : `c394b46bc6737f7f7edfbfa3031ce621b7a43d498d456d6198364eee9cd3e306`
- Extrait : de 0,000 s à 0,051 s du fichier
- Montée 3 ms, descente 10 ms, crête 3800 (−18,7 dBFS)
- Fichier du cœur : `sons/choisir.wav`, 4542 octets, 2249 échantillons (0,051 s)
- SHA-256 du fichier du cœur : `23fcb18607b921a779571e660b74bdd9f070c1e1c8d7945663987236c8e3b562`
