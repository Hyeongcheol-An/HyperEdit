# Guide de l'utilisateur HyperEdit

<p align="center"><a href="USER_GUIDE.md">English</a> · <a href="USER_GUIDE.ko.md">한국어</a> · <a href="USER_GUIDE.zh-Hans.md">简体中文</a> · <a href="USER_GUIDE.ja.md">日本語</a> · <a href="USER_GUIDE.vi.md">Tiếng Việt</a> · <a href="USER_GUIDE.hi.md">हिन्दी</a> · <a href="USER_GUIDE.de.md">Deutsch</a> · Français · <a href="USER_GUIDE.es.md">Español</a> · <a href="USER_GUIDE.pt.md">Português</a> · <a href="USER_GUIDE.ar.md">العربية</a></p>

HyperEdit est un éditeur de texte brut rapide pour macOS, conçu autour d'un seul grand fichier de notes — celui que l'on complète pendant des années. Ce guide explique tout ce que vous pouvez faire avec, dans l'ordre où vous le rencontrerez probablement. Les raccourcis sont écrits avec les symboles Mac ⌘ Commande, ⇧ Majuscule, ⌥ Option, ⌃ Contrôle.

## Sommaire

1. [Installation et mise à jour](#1-installation-et-mise-à-jour)
2. [Premier lancement](#2-premier-lancement)
3. [Langue de l'interface](#3-langue-de-linterface)
4. [La fenêtre](#4-la-fenêtre)
5. [Bases de l'édition](#5-bases-de-lédition)
6. [Rechercher et remplacer](#6-rechercher-et-remplacer)
7. [Signets](#7-signets)
8. [Mode colonne et multi-curseur](#8-mode-colonne-et-multi-curseur)
9. [Outils de ligne et de texte](#9-outils-de-ligne-et-de-texte)
10. [Snippets](#10-snippets)
11. [Macros](#11-macros)
12. [Repliage de code et marqueurs de défilement](#12-repliage-de-code-et-marqueurs-de-défilement)
13. [Éditeur divisé](#13-éditeur-divisé)
14. [Ajout rapide](#14-ajout-rapide)
15. [Aperçu Markdown et coloration syntaxique](#15-aperçu-markdown-et-coloration-syntaxique)
16. [Thèmes, polices et texte CJK](#16-thèmes-polices-et-texte-cjk)
17. [Enregistrement, instantanés et encodages](#17-enregistrement-instantanés-et-encodages)
18. [Référence des réglages](#18-référence-des-réglages)
19. [Raccourcis clavier](#19-raccourcis-clavier)
20. [Fichiers écrits par HyperEdit](#20-fichiers-écrits-par-hyperedit)
21. [Dépannage](#21-dépannage)
22. [Limitations connues](#22-limitations-connues)
23. [Blocs secrets et verrouillage de l'app](#23-blocs-secrets-et-verrouillage-de-lapp)
24. [Obtenir de l'aide](#24-obtenir-de-laide)

## 1. Installation et mise à jour

**Configuration requise :** macOS 15 (Sequoia) ou ultérieur. L'app est un binaire universel (Apple Silicon et Intel), signé et notarisé : Gatekeeper l'ouvre donc sans avertissement.

**Homebrew**

```sh
brew tap Hyeongcheol-An/tap
brew install --cask hyperedit
```

Mettez à jour plus tard avec `brew upgrade --cask hyperedit`. Homebrew 7 peut vous demander d'abord de faire confiance au tap : `brew trust Hyeongcheol-An/tap`.

**DMG :** téléchargez `HyperEdit-x.y.z-universal.dmg` depuis [GitHub Releases](https://github.com/Hyeongcheol-An/HyperEdit/releases), ouvrez-le et glissez `HyperEdit.app` dans `Applications`. Pour vérifier un téléchargement, placez `SHA256SUMS` à côté du DMG et lancez `shasum -a 256 -c SHA256SUMS`.

HyperEdit ne contient aucun code réseau ni télémétrie : il ne contacte jamais de serveur, et les mises à jour sont quelque chose que vous faites, pas quelque chose qu'il fait.

## 2. Premier lancement

HyperEdit ouvre `~/Documents/HyperEdit/notes.md`. Si ce fichier n'existe pas, il est créé avec un court texte de bienvenue dans votre langue — supprimez-le et commencez à écrire. L'idée est de garder un seul fichier et de le compléter, mais rien ne vous y oblige :

- **⌘N** crée un nouveau fichier texte vide (vous choisissez le nom et le dossier).
- **⌘O** ouvre n'importe quel autre fichier texte. Le dernier fichier ouvert est mémorisé pour le prochain lancement.
- **Fichier › Ouvrir le document par défaut** vous ramène à `notes.md`.
- Les fichiers binaires (images, PDF, archives…) ne sont jamais chargés dans l'éditeur ; ils s'ouvrent dans leur app par défaut.

La position du curseur et du défilement est mémorisée pour chaque fichier : en rouvrant un fichier de 30 000 lignes, vous retrouvez l'endroit où vous vous étiez arrêté. **⌃⌘E** va à la fin du document — l'endroit où l'on veut généralement se trouver dans un fichier de notes.

## 3. Langue de l'interface

L'interface est disponible en onze langues : English (anglais), 한국어 (coréen), 简体中文 (chinois simplifié), 日本語 (japonais), Tiếng Việt (vietnamien), हिन्दी (hindi), Deutsch (allemand), Français, Español (espagnol), Português (portugais, orthographe brésilienne) et العربية (arabe). Le texte arabe s'écrit de droite à gauche, mais la disposition de la fenêtre — ruban, barre latérale, volets et éditeur — reste de gauche à droite, comme dans la plupart des éditeurs de code ; le texte que vous tapez suit sa propre direction.

Par défaut, HyperEdit suit la langue du système. Pour en choisir une autre :

1. Ouvrez les **Réglages (⌘,)** et regardez la section **Langue** en haut.
2. Choisissez une langue dans le menu **Langue de l'interface**. Chaque langue est indiquée dans sa propre écriture, pour que vous trouviez la vôtre même si la langue actuelle vous est inconnue. **Valeur par défaut du système** indique la langue que donnerait le réglage du système.
3. Cliquez sur **Relancer maintenant**. Le document est d'abord enregistré, puis HyperEdit quitte et se rouvre dans la nouvelle langue. (Vous pouvez aussi continuer à travailler et relancer plus tard ; le choix est déjà enregistré.)

Le choix est stocké au même endroit que **Réglages Système › Général › Langue et région › Applications**, de sorte que les deux restent cohérents. **Aide › Guide de l'utilisateur** et le bouton **Ouvrir le guide de l'utilisateur** des Réglages ouvrent ce guide dans la langue actuelle de l'interface.

Une langue absente de la liste retombe sur l'anglais (par exemple le chinois traditionnel). Le texte des documents, les noms de fichiers et les dates que vous insérez ne dépendent pas de la langue de l'interface — le jour de la semaine de l'horodatage suit les réglages régionaux du système.

## 4. La fenêtre

La disposition suit celle d'un éditeur à ruban classique, avec une barre de titre masquée.

- **Onglets du ruban** — **Accueil** (Presse-papiers, Rechercher, Insérer, Mode, Fichier), **Édition** (Lignes, Casse, Tri, Espaces, Colonne et multi-curseur, Outils, Macro), **Disposition** (Thème, Volets, Repliage, Markdown, Taille du texte), **Avancé** (Réglages, dossier des instantanés, rechargement, document par défaut), **Fenêtre** (plein écran, volets). Quand la fenêtre est étroite, les groupes se replient en icônes à partir de la droite ; l'infobulle de l'icône affiche le libellé.
- **Barre d'onglet du document** — le nom du fichier actuel avec les boutons Nouveau (⌘N) et Ouvrir (⌘O), plus les accès rapides Enregistrer / Annuler / Rétablir.
- **Barre latérale (⌘1)** — **Fichiers** (le dossier du fichier actuel ; un clic ouvre un fichier), **Plan (⌘3)** (titres, lignes `[Titre]` et éléments numérotés, avec un champ de filtre ; l'élément actuel est mis en évidence), **Chronologie (⌘4)** (titres horodatés groupés par mois, les plus récents en premier).
- **Volet inférieur (⌘2)** — **Résultats de recherche**, **Signets** et **Sortie**, un journal de ce que l'app a fait (enregistrements, remplacements, erreurs).
- **Barre d'état** — ligne et colonne (plus la longueur de la sélection ; survolez pour le décalage en caractères), fin de ligne (UNIX / DOS / MAC), encodage du fichier, **COL** quand le mode colonne est actif, nombre de curseurs, nombre de lignes · taille du fichier, le dernier message d'état, le langage de coloration (estompé quand la coloration syntaxique est désactivée), un menu de thème (marqué « · Système » quand l'apparence du système est suivie) et le pourcentage de zoom. La plupart des éléments sont cliquables.

## 5. Bases de l'édition

- La saisie reste rapide dans des fichiers de plusieurs mégaoctets ; seule la partie visible du document est mise en page.
- **Retour à la ligne** ⌥Z · **Numéros de ligne** ⌥⌘L · **Zoom** ⌘= / ⌘- / ⌘0 (aussi dans l'onglet Disposition).
- **Atteindre la ligne** ⌘L · **Fin du document** ⌃⌘E.
- **Insérer la date et l'heure** F7 insère un titre horodaté tel que `## 2026-10-31 (ven.) 14:05`. Le jour de la semaine suit les réglages régionaux du système. Ces lignes alimentent la Chronologie.
- La ligne actuelle est mise en évidence et la gouttière affiche son numéro dans la couleur du texte.
- Annuler et rétablir sont illimités au cours d'une session, et chaque outil ci-dessous constitue une seule étape d'annulation.

## 6. Rechercher et remplacer

- **Rechercher (⌘F)** ouvre la barre de recherche. Tapez une requête et appuyez sur Entrée : chaque occurrence est listée dans le volet inférieur avec son numéro de ligne, et les occurrences sont surlignées dans l'éditeur tant que la liste est ouverte. Options : expression régulière `.*`, respecter la casse `Aa`, mot entier `W`. **F3 / ⇧F3** passent à l'occurrence suivante / précédente. La liste se rafraîchit d'elle-même environ une seconde après une modification.
- **Remplacer (⌘R)** ajoute un champ de remplacement : remplacez l'occurrence actuelle et passez à la suivante, ou **Tout remplacer**. Avec les expressions régulières, des modèles comme `$1` insèrent les groupes capturés. Tout remplacer est une seule étape d'annulation, même avec des milliers d'occurrences.
- **Rechercher dans les fichiers (⇧⌘F)** parcourt un dossier (sous-dossiers inclus). Choisissez le dossier, limitez éventuellement avec des masques comme `*.md;*.txt`, et cliquez sur un résultat pour ouvrir ce fichier à cette ligne. Les fichiers cachés, les paquets, les fichiers binaires et les fichiers de plus de 20 Mo sont ignorés.
- **Sélectionner toutes les occurrences (⌥⌘A)** transforme chaque occurrence en curseur — voir le multi-curseur ci-dessous.

## 7. Signets

**⌘F2** pose un signet sur la ligne actuelle (ou le retire), **F2 / ⌥F2** vont au signet suivant / précédent, et l'onglet **Signets** du volet inférieur les liste tous ; vous pouvez y donner un nom à un signet. Les signets suivent leurs lignes pendant l'édition : insérer ou supprimer des lignes au-dessus les déplace, supprimer une ligne marquée le retire, et annuler les restaure. Ils sont stockés par document dans `~/Library/Application Support/HyperEdit/bookmarks/`, donc rien n'est écrit à côté de vos fichiers.

## 8. Mode colonne et multi-curseur

- **Mode colonne (⌥C)** — maintenez ⌥ et glissez, ou utilisez ⇧ avec les flèches, pour sélectionner un rectangle. La saisie et la suppression s'appliquent alors à chaque ligne du bloc, les lignes courtes sont complétées par de l'espace virtuel, et copier / coller fonctionnent ligne par ligne. La barre d'état affiche **COL**. ⌥C à nouveau le désactive.
- **Insérer un numéro (⌥⌘N)** — remplit une sélection en colonne (ou chaque curseur) avec une séquence : choisissez la valeur de départ et le pas ; les numéros sont complétés par des zéros pour avoir la même largeur.
- **Multi-curseur** — ⌘-clic ajoute un curseur, **⌘D** ajoute l'occurrence suivante du texte sélectionné (ou du mot au curseur), **⌥⌘A** sélectionne toutes les occurrences de la recherche. La saisie va à chaque curseur ; Esc revient à un seul. Chaque modification multi-curseur est une seule étape d'annulation.

## 9. Outils de ligne et de texte

Ils se trouvent dans l'onglet **Édition** du ruban et dans le menu **Ligne**. Ils agissent sur les lignes sélectionnées, ou sur la ligne actuelle quand rien n'est sélectionné.

| Groupe | Outils |
|---|---|
| Lignes | Supprimer la ligne ⇧⌘K · Dupliquer la ligne ⇧⌘D · Monter / Descendre la ligne ⌥↑ / ⌥↓ · Joindre les lignes ⇧⌘J · Inverser l'ordre des lignes · Numéroter |
| Casse | Majuscules · Minuscules · Majuscule initiale · Inverser la casse |
| Tri | Croissant · Décroissant · Tri numérique (selon le nombre en début de ligne) · Supprimer les lignes en double |
| Espaces | Supprimer les espaces de fin · Supprimer les espaces de début et de fin · Supprimer les lignes vides · Tab → Espaces · Espaces → Tab |

- **Calculer (⌃⌘=)** évalue la sélection, ou la ligne actuelle (la partie après le dernier `=` s'il y en a un), et ajoute ` ⇒ résultat` : `3+0.5+0.25` devient `3+0.5+0.25 ⇒ 3.75`. Relancé sur une ligne modifiée, il remplace l'ancien résultat. Pris en charge : `+ - * / % ^`, les parenthèses, les nombres `1,234` et `1_000`, `sqrt abs round floor ceil min max`, `pi` et `e`. Une expression qui ne peut pas être évaluée est signalée dans le volet Sortie et le texte reste intact.
- **Aligner les colonnes (⌃⌘T)** complète les colonnes séparées par des tabulations (les lignes sélectionnées, ou le bloc de lignes à tabulations autour du curseur) pour que chaque colonne commence à la même colonne d'affichage ; les caractères coréens, chinois et japonais comptent pour deux cellules. Si chaque ligne contient `|`, le bloc est traité comme un tableau Markdown : les cellules sont complétées à l'intérieur de ` | `, les lignes `---` sont redessinées et les colonnes `--:` sont alignées à droite.
- **Commenter/décommenter (⌘/)** commente ou décommente les lignes avec le marqueur du type de fichier : `//`, `#`, `--`… pour le code, `<!-- -->` pour Markdown et HTML, `/* */` pour CSS, `//` pour les notes simples. Si chaque ligne non vide est déjà commentée, toutes sont décommentées ; sinon toutes sont commentées, les marqueurs étant alignés sur l'indentation la moins profonde. Les lignes vides sont ignorées.
- **Formater JSON (⌃⌘J) / Compacter JSON** met en forme (indentation de 2 espaces) ou réduit la sélection, ou tout le document quand rien n'est sélectionné. L'ordre des clés et l'écriture des nombres sont préservés, le texte non ASCII n'est pas échappé, et l'entrée peut contenir des commentaires et des virgules finales (JSONC). En cas d'erreur de syntaxe, le texte reste intact, le volet Sortie indique `ligne:colonne` et le curseur s'y rend.

## 10. Snippets

Tapez un mot déclencheur et appuyez sur **Tab** pour le développer. Déclencheurs intégrés : `todo`, `date`, `time`, `now`, `meeting`, `table`, `link`, `code`. **Insérer un snippet… (⇧⌘I)** les liste tous avec un champ de filtre, et l'onglet Accueil a un bouton Snippet….

Le corps d'un snippet peut contenir des variables — `${date}`, `${time}`, `${datetime}`, `${selection}`, `${clipboard}`, `${filename}` — et des taquets `$1` … `$9`, `${1:placeholder}` et `$0`. Après le développement, Tab / ⇧Tab passent d'un taquet à l'autre (un numéro utilisé deux fois devient un multi-curseur), et Esc ou un clic termine la session.

**Modifier les snippets…** (menu Édition ou onglet Accueil) ouvre `~/Library/Application Support/HyperEdit/snippets.json` dans HyperEdit lui-même. Chaque entrée a un `trigger`, un `name` et un `body` ; le fichier est relu après l'enregistrement, donc un nouveau déclencheur fonctionne immédiatement.

## 11. Macros

Une macro enregistre ce que vous tapez et le rejoue ailleurs.

1. **Enregistrer une macro (⇧⌘M)** démarre l'enregistrement ; la barre d'état affiche `● REC`. La saisie (pour le coréen et les autres méthodes de saisie, les caractères validés), les déplacements du curseur, les suppressions, les retours à la ligne, le collage, les outils de texte et Rechercher le suivant (F3, avec sa requête) sont enregistrés. Les clics de souris, les changements de sélection et les modifications multi-curseur ne le sont pas.
2. **⇧⌘M** à nouveau arrête l'enregistrement.
3. **Exécuter la macro (⌥⌘M)** la rejoue au curseur. **Exécuter la macro plusieurs fois…** la répète jusqu'à 10 000 fois et s'arrête d'elle-même quand une étape Rechercher ne trouve rien ou qu'un passage ne change rien — un outil pratique pour « faire ceci sur chaque ligne ». Un passage complet est une seule étape d'annulation.

Le dernier enregistrement reste en mémoire seulement jusqu'à ce que vous quittiez, de sorte que rien de sensible tapé pendant l'enregistrement n'atteint le disque. **Sauvegarder la dernière macro sous…** l'ajoute définitivement au menu **Macro** ; les macros sauvegardées se trouvent dans `~/Library/Application Support/HyperEdit/macros/macros.json`, que **Modifier le fichier des macros…** ouvre dans l'éditeur.

## 12. Repliage de code et marqueurs de défilement

**Replier (⌥⌘←) / Déplier (⌥⌘→)** masquent ou affichent la région au curseur ; **⌥⇧⌘← / ⌥⇧⌘→** replient ou déplient tout. Une région est :

- les lignes indentées sous la ligne actuelle (lignes vides ignorées),
- en Markdown, tout ce qui suit un titre `#` jusqu'au titre suivant de même niveau ou de niveau supérieur (les blocs de code délimités se replient aussi),
- dans le code, une ligne se terminant par `{`, `[` ou `(` jusqu'à la ligne du crochet fermant.

Cliquez sur le chevron dans la gouttière ou sur la pastille `⋯ N lignes` après une ligne repliée pour basculer à la souris. Déplacer le curseur dans une ligne repliée (recherche, atteindre la ligne, signet, annulation) la déplie ; ↑ / ↓ sautent par-dessus les replis. Les replis suivent vos modifications et durent le temps de la session.

**Marqueurs de défilement** — une fine bande au bord droit de l'éditeur montre les occurrences de recherche (couleur d'accentuation), les signets (couleur d'avertissement), la ligne du curseur et les en-têtes repliés à leur position relative dans le fichier. Elle est masquée quand tout le document tient à l'écran. Désactivez-la dans **Présentation › Marqueurs de défilement** ou dans le groupe Repliage de l'onglet Disposition.

## 13. Éditeur divisé

**⌘\\** affiche le même document dans deux éditeurs côte à côte ; **Présentation › Division › Division superposée** les place l'un au-dessus de l'autre, et l'onglet Disposition a les mêmes boutons. Les deux vues modifient le même texte et partagent un seul historique d'annulation — tapez dans l'une, ⌘Z dans l'autre — mais défilent indépendamment, ce qui permet de lire une partie d'un fichier tout en écrivant dans une autre. Les commandes, la barre d'état et l'aperçu Markdown suivent l'éditeur cliqué en dernier ; **⌥⌘\\** passe le focus à l'autre. La barre d'état affiche **SPLIT** tant que la division est active ; ⌘\\ à nouveau la ferme.

## 14. Ajout rapide

**Ajout rapide (⇧⌘N)** ouvre un petit panneau flottant pour ajouter une note sans quitter ce que vous faisiez. Tapez la note, appuyez sur **⌘↩**, et elle est ajoutée à la fin du document — avec un titre horodaté par défaut — enregistrée aussitôt et annulable en une étape. Le panneau se masque ensuite et le focus revient à l'app où vous étiez. **Esc** ferme le panneau et conserve le brouillon pour la prochaine fois.

Comme le panneau n'active pas HyperEdit, il fonctionne aussi depuis n'importe quelle autre app grâce à un **raccourci global** : **⌃⌥N** par défaut. Dans les Réglages, vous pouvez le désactiver ou choisir ⌃⌥Space, ⌃⇧Space ou ⌃⌥⌘N à la place, et désactiver le titre horodaté. Le raccourci utilise le service de touches de raccourci du système, aucune autorisation d'accessibilité n'est donc nécessaire. Si une autre app possède déjà la combinaison, le volet Sortie le signale au lancement — choisissez-en une autre.

## 15. Aperçu Markdown et coloration syntaxique

- **Aperçu Markdown (⇧⌘P)** divise la fenêtre avec, à droite, un rendu du fichier actuel : titres, listes et listes de tâches, tableaux, code délimité, citations, liens et images, stylés avec le thème actuel. Il suit la position de défilement de l'éditeur et se met à jour peu après la fin de la saisie. Les liens s'ouvrent dans votre navigateur ; le HTML brut du fichier est affiché comme texte, jamais exécuté. Les fichiers de plus de 2 Mo affichent un avis au lieu d'un aperçu. La barre d'état affiche **MD** quand il est actif.
- **Coloration syntaxique (⌃⌘H)** est choisie selon l'extension du fichier et indiquée dans la barre d'état. Les notes et le Markdown reçoivent un jeu de règles léger — URL, dates et heures, titres, lignes `[Titre]`, puces de liste et cases `[ ]` / `[x]`, `#tags`, étiquettes `clé:`, `**gras**`, `` `code` `` et flèches `⇒ → ->` — et une vingtaine de langages de programmation reçoivent commentaires, chaînes, nombres, mots-clés, noms de fonctions et de types. Les couleurs ne sont dessinées que sur les lignes visibles, elles ne modifient donc jamais le fichier et ne ralentissent pas la saisie. Les constructions qui s'étendent sur plusieurs lignes gardent leur couleur jusqu'à leur fermeture : commentaires de bloc (`/* */`, `<!-- -->`), chaînes multilignes (`"""` de Swift et Python, littéraux de gabarit JavaScript, chaînes brutes Go, `r#"…"#` de Rust) et blocs de code délimités Markdown, colorés avec le langage nommé dans la chaîne d'info (```` ```python ````). Taper un délimiteur d'ouverture ou de fermeture recolore immédiatement les lignes suivantes.
- **Grammaires définies par l'utilisateur.** Pour colorer un langage que HyperEdit ne connaît pas, ou pour modifier un langage intégré, placez un fichier `*.json` dans `~/Library/Application Support/HyperEdit/grammars/`. **Fichier › Ouvrir le dossier des grammaires…** crée le dossier avec un `example.json` à copier et un README qui explique chaque clé — `name`, `extensions` ou `filenames`, `lineComments`, `blockComment`, `strings`, `multilineStrings`, `keywords`, `types`, `constants`, `builtins`, `caseInsensitive`. **Fichier › Recharger les grammaires** applique vos modifications sans redémarrer ; la barre d'état affiche le nom de la grammaire, Commenter (⌘/) utilise ses marqueurs de commentaire, et un fichier qui ne peut pas être analysé est ignoré avec un message dans le volet Sortie.

## 16. Thèmes, polices et texte CJK

**Thèmes.** 22 palettes — 5 claires, 17 sombres — sont livrées avec l'app. Par défaut, elle suit l'apparence du système : **Hyper Light** en mode clair, **Hyper Dark** en mode sombre. Choisissez un thème dans l'onglet Disposition, le menu de thème de la barre d'état, **Présentation › Thème** ou ⌥⌘] / ⌥⌘[ pour le fixer ; **Suivre l'apparence du système** se trouve dans les mêmes menus et dans les Réglages. Les mêmes palettes sont disponibles pour l'éditeur Zed (`hyperedit-themes.json` dans chaque version publiée).

**Curseur et opacité de la fenêtre.** Réglages › **Apparence** choisit la forme du curseur — **Barre** (par défaut), **Bloc** (la cellule du caractère est teintée de la couleur du curseur pour que le caractère reste lisible) ou **Souligné** — et s'il clignote ; les curseurs supplémentaires du multi-curseur et du mode colonne utilisent la même forme. **Opacité de la fenêtre** (50–100 %) rend toute la fenêtre translucide — éditeur, ruban, volets et barre d'état compris — tandis que le texte, les icônes et les bordures restent opaques, et **Flou derrière la fenêtre** ajoute le flou du système. Présentation › Opacité de la fenêtre propose les paliers 100 / 90 / 80 / 70 %.

**Polices.** HyperEdit utilise **Fira Code** lorsqu'elle est installée, et la police à chasse fixe du système sinon. Le texte coréen est dessiné avec une police distincte — **D2Coding** par défaut, lorsqu'elle est installée — mise à l'échelle pour qu'une syllabe hangeul fasse exactement deux cellules latines de large, ce qui garde droits les tableaux alignés par tabulations. Les ligatures, la hauteur de ligne, les deux familles de polices et l'échelle du hangeul sont dans les Réglages. Le texte chinois et japonais utilise les polices de secours du système et compte aussi pour deux cellules dans Aligner les colonnes.

## 17. Enregistrement, instantanés et encodages

- **L'enregistrement automatique** a lieu deux secondes après la fin de la saisie (⌘S enregistre maintenant). À la fermeture de l'app ou de la fenêtre et au changement de fichier, le document est enregistré immédiatement, rien n'est donc perdu dans la fenêtre de deux secondes. Chaque écriture est atomique.
- **Instantanés.** Avant le premier enregistrement de chaque session, une copie du fichier est stockée dans `~/Library/Application Support/HyperEdit/snapshots` (**Fichier › Ouvrir le dossier des instantanés**). Les 20 plus récents par fichier sont conservés et tout ce qui date de plus de 90 jours est supprimé.
- **Modifications externes.** Si un autre programme modifie le fichier pendant qu'il est ouvert et que vous n'avez aucune modification non enregistrée, HyperEdit le recharge et garde votre curseur à sa place. Si vous avez des modifications non enregistrées, la version externe est mise en instantané et un avertissement s'affiche ; l'enregistrement l'écrase alors.
- **Sécurité.** Un tampon vide n'est jamais écrit par-dessus un fichier qui avait du contenu. Si l'enregistrement échoue quand vous quittez, une copie de secours est écrite dans le dossier des instantanés et il vous est demandé si vous voulez quitter quand même.
- **Encodages.** Les fichiers sont lus d'abord en UTF-8, puis en EUC-KR (CP949), CP1252 et Latin-1, et enregistrés dans le même encodage (un BOM UTF-8 est préservé). Si vous tapez un caractère que l'encodage d'origine ne peut pas stocker, le fichier est enregistré en UTF-8 et la barre d'état l'indique. Un fichier qui ne peut être décodé dans aucun de ces encodages n'est pas ouvert du tout plutôt que d'être endommagé.
- **Les fins de ligne** (UNIX / DOS / MAC) sont détectées et préservées ; l'Ajout rapide et les outils de texte utilisent celles du fichier.
- **Exportation.** **Fichier › Exporter en HTML…** enregistre le document sous forme d'un fichier HTML autonome — le Markdown rendu comme dans l'aperçu, les notes et le code sous forme de bloc avec coloration syntaxique — et **Fichier › Exporter en PDF…** imprime la même page dans un PDF paginé (Letter aux États-Unis, au Canada et au Mexique, A4 ailleurs ; marges de 36 pt ; ni en-tête ni pied de page). Le panneau d'enregistrement permet de choisir le thème (actuel, Hyper Light, Hyper Dark) et, pour les notes et le code, les numéros de ligne. La page exportée ne contient aucun script et ne charge rien depuis le réseau ; les chemins d'images relatifs sont conservés, enregistrez donc le HTML à côté du fichier Markdown. L'exportation PDF fonctionne pour les fichiers jusqu'à 2 Mo. Les blocs secrets (section 23) sont exportés sous la forme `••••••••`.

## 18. Référence des réglages

Ouvrez les Réglages avec **⌘,** ou l'onglet Avancé.

| Section | Ce qu'elle contrôle |
|---|---|
| Langue | Langue de l'interface (Valeur par défaut du système ou l'une des onze langues), **Relancer maintenant**, **Ouvrir le guide de l'utilisateur** |
| Police | Famille de police latine, taille, ligatures, hauteur de ligne |
| Hangeul | Famille de police hangeul, la correction de largeur 2:1, l'échelle du hangeul ; indique si la police est installée |
| Thème | Suivre l'apparence du système, sélecteur de thème |
| Fichiers | Le fichier actuel, le document par défaut et le dossier des instantanés, avec des boutons pour les ouvrir |
| Ajout rapide | Raccourci global (Désactivé / ⌃⌥N / ⌃⌥Space / ⌃⇧Space / ⌃⌥⌘N), titre horodaté activé/désactivé |
| Apparence | Style du curseur (Barre / Bloc / Souligné), clignotement, opacité de la fenêtre 50–100 %, flou derrière la fenêtre |
| Secrets | Masquer les blocs secrets, masquer de nouveau après (10 / 30 / 60 s / Jamais), vider le presse-papiers après la copie d'un secret (Désactivé / 10 / 30 / 60 s) |

La visibilité des volets, le retour à la ligne, les numéros de ligne, la coloration syntaxique, les marqueurs de défilement, la division et l'onglet du ruban sont mémorisés automatiquement.

## 19. Raccourcis clavier

| Raccourci | Action | Raccourci | Action |
|---|---|---|---|
| ⌘N | Nouveau document | ⌘O | Ouvrir |
| ⌘S | Enregistrer | ⌘F | Rechercher |
| ⌘R | Remplacer | ⇧⌘F | Rechercher dans les fichiers |
| F3 / ⇧F3 | Occurrence suivante / précédente | ⌘L | Atteindre la ligne |
| ⌃⌘E | Fin du document | ⌥C | Mode colonne |
| ⌘D | Ajouter l'occurrence suivante | ⌥⌘A | Sélectionner toutes les occurrences |
| ⌥⌘N | Insérer des numéros | F7 | Insérer un horodatage |
| ⌘F2 | Basculer le signet | F2 / ⌥F2 | Signet suivant / précédent |
| ⇧⌘K | Supprimer la ligne | ⇧⌘D | Dupliquer la ligne |
| ⌥↑ / ⌥↓ | Monter / descendre la ligne | ⇧⌘J | Joindre les lignes |
| ⌃⌘= | Calculer | ⌃⌘T | Aligner les colonnes |
| ⌘/ | Commenter/décommenter | ⌃⌘J | Formater JSON |
| ⇧⌘I | Insérer un snippet | Tab | Développer le snippet / taquet suivant |
| ⇧⌘M | Enregistrer / arrêter la macro | ⌥⌘M | Exécuter la macro |
| ⌥⌘← / ⌥⌘→ | Replier / déplier | ⌥⇧⌘← / ⌥⇧⌘→ | Tout replier / tout déplier |
| ⌘\\ | Éditeur divisé | ⌥⌘\\ | Activer l'autre éditeur |
| ⇧⌘N | Ajout rapide | ⌃⌥N | Ajout rapide depuis n'importe quelle app (configurable) |
| ⌘1 | Barre latérale | ⌘2 | Volet inférieur |
| ⌘3 | Plan | ⌘4 | Chronologie |
| ⌥⌘L | Numéros de ligne | ⌥Z | Retour à la ligne |
| ⇧⌘P | Aperçu Markdown | ⌃⌘H | Coloration syntaxique |
| ⌥⌘] / ⌥⌘[ | Thème suivant / précédent | ⌘= / ⌘- / ⌘0 | Zoom avant / arrière / réinitialiser |
| ⌥⌘S | Révéler / masquer les blocs secrets | ⌘, | Réglages |
| ⌃⌘L | Verrouiller HyperEdit (Touch ID) | | |
| ⌘Q | Quitter (enregistre d'abord) | | |

## 20. Fichiers écrits par HyperEdit

HyperEdit ne touche qu'aux fichiers que vous ouvrez et à ses propres données :

| Chemin | Contenu |
|---|---|
| `~/Documents/HyperEdit/notes.md` | Le document par défaut (créé au premier lancement s'il n'existe pas) |
| `~/Library/Application Support/HyperEdit/snapshots/` | Instantanés pris avant enregistrement et copies de secours |
| `~/Library/Application Support/HyperEdit/bookmarks/` | Un fichier JSON par document comportant des signets |
| `~/Library/Application Support/HyperEdit/snippets.json` | Vos snippets |
| `~/Library/Application Support/HyperEdit/grammars/` | Grammaires définies par l'utilisateur (`*.json`), avec `example.json` et un README |
| `~/Library/Application Support/HyperEdit/macros/macros.json` | Macros sauvegardées |
| `~/Library/Preferences/io.github.hyeongcheol-an.hyperedit.plist` | Préférences, dont la langue de l'interface |

Rien n'est écrit à côté de vos documents, et rien ne quitte votre Mac.

## 21. Dépannage

- **La langue n'a pas changé.** La nouvelle langue s'applique après un redémarrage — utilisez **Relancer maintenant** dans les Réglages, ou quittez et rouvrez l'app. Si la langue du système n'est pas disponible dans HyperEdit, il s'affiche en anglais ; choisissez explicitement une langue dans les Réglages.
- **Un fichier ne s'ouvre pas.** Les fichiers binaires s'ouvrent volontairement dans leur app par défaut. Un fichier texte dans un encodage autre que UTF-8, EUC-KR, CP1252 ou Latin-1 est refusé plutôt qu'endommagé ; convertissez-le d'abord avec un autre outil.
- **Le raccourci global d'Ajout rapide ne fait rien.** Une autre app possède peut-être la combinaison, ou ⌃Space / ⌃⌥Space est peut-être réservé au changement de source de saisie dans Réglages Système › Clavier. Choisissez ⌃⌥N ou ⌃⌥⌘N dans les Réglages. Le volet Sortie indique le résultat de l'enregistrement du raccourci au lancement.
- **Le texte coréen paraît trop large ou trop étroit dans les tableaux.** Installez D2Coding, ou ajustez l'échelle du hangeul dans les Réglages ; la correction de largeur 2:1 nécessite une police hangeul à chasse fixe.
- **J'ai enregistré quelque chose par erreur.** Ouvrez le dossier des instantanés (**Fichier › Ouvrir le dossier des instantanés**) : la copie prise avant le premier enregistrement de la session s'y trouve, ainsi que les copies faites lors de la détection de modifications externes.
- **Le ruban n'affiche que des icônes.** La fenêtre est trop étroite pour cet onglet ; élargissez-la ou survolez une icône pour voir son libellé.

## 22. Limitations connues

- La coloration syntaxique suit les commentaires de bloc, les chaînes multilignes et les blocs délimités Markdown d'une ligne à l'autre, mais seuls les délimiteurs de chaîne identiques à l'ouverture et à la fermeture et une seule paire de commentaires de bloc par langage sont pris en charge, et les grammaires utilisateur sont des listes de mots sans règles d'expressions régulières. L'aperçu Markdown est une vue, pas un éditeur.
- Les macros n'enregistrent que l'édition au clavier (pas de souris, de sélection ni d'étapes multi-curseur). Calculer et Aligner les colonnes ne gèrent que l'arithmétique simple et les tableaux à tabulations / barres verticales.
- Les snippets, les macros et les grammaires utilisateur se modifient sous forme de fichiers JSON ; il n'y a pas d'éditeur graphique pour eux.
- L'exportation écrit uniquement le document entier, sans exportation de la sélection ni de plusieurs fichiers, sans options de page ou de police, ni table des matières PDF.
- Les blocs secrets ne sont masqués qu'à l'écran : le fichier, les enregistrements automatiques, les instantanés et les résultats de Rechercher dans les fichiers provenant d'autres fichiers sont en texte brut, et la barre de masquage indique la longueur de chaque ligne. Le verrouillage de l'app masque la fenêtre ; il ne chiffre rien, et une feuille ouverte au moment du verrouillage (Atteindre la ligne, Insérer un numéro, le sélecteur de snippets) reste au-dessus de l'écran de verrouillage sans afficher le document.
- Les replis durent le temps de la session et ne sont pas enregistrés par fichier ; un glisser de souris à travers une ligne repliée sélectionne quand même le texte masqué.
- Les documents constitués d'une seule ligne d'un mégaoctet ou plus sont lents à ouvrir et à parcourir ; Compacter JSON avertit avant d'en produire un.
- Fichiers locaux uniquement ; pas de synchronisation cloud ni d'app iOS pour l'instant.
- Les langues autres que les onze listées retombent sur l'anglais.

## 23. Blocs secrets et verrouillage de l'app

**Blocs secrets.** Un bloc de code délimité dont la chaîne d'info commence par `secret` est masqué dans l'éditeur :

````markdown
```secret bank
login: me@example.com
password: hunter2
```
````

Chaque ligne entre les délimiteurs est dessinée comme une barre vide avec `••••••••` ; les lignes de délimitation restent visibles pour que vous voyiez où se trouve le bloc et à quoi il sert. La règle est la même dans les fichiers Markdown et texte brut. Placez le curseur dans le bloc — en cliquant dessus, avec ↑ / ↓, Atteindre la ligne, un résultat de recherche ou un signet — et le bloc entier est révélé et modifiable ; sortez le curseur et il est de nouveau masqué. Seul l'affichage change : le texte est toujours dans le fichier, donc Rechercher, Remplacer, l'annulation et l'enregistrement fonctionnent exactement comme avant.

- **Révéler les secrets (⌥⌘S)** dans le menu Édition affiche tous les blocs à la fois ; après le délai **Réglages › Secrets › Masquer de nouveau après** (10 / 30 / 60 s, 30 s par défaut, ou Jamais), ils sont de nouveau masqués et le volet Sortie le consigne. La barre d'état affiche `REVEALED` pendant ce temps et `•••• N` tant que N blocs sont masqués. **Édition › Masquer les blocs secrets** désactive entièrement le masquage.
- Les lignes secrètes sont affichées comme `••••••••` dans la liste Résultats de recherche (l'occurrence et le numéro de ligne fonctionnent toujours), ignorées par le Plan et la Chronologie, et caviardées dans l'aperçu Markdown et dans les exportations HTML / PDF.
- **Vidage automatique du presse-papiers.** Lorsqu'une copie ou une coupe touche une ligne secrète — y compris les copies multi-curseur et en mode colonne — le presse-papiers est vidé après le délai **Réglages › Secrets › Vider le presse-papiers après la copie d'un secret** (Désactivé / 10 / 30 / 60 s, 30 s par défaut), sauf si vous avez copié autre chose entre-temps. **Édition › Vider le presse-papiers** le vide immédiatement.
- Les blocs secrets se replient comme n'importe quel bloc délimité (⌥⌘←).

> Masquer n'est pas chiffrer. Le fichier, les enregistrements automatiques et les instantanés sont en texte brut, et toute personne qui possède le fichier peut lire les secrets. La fonction les tient à l'écart de votre écran, des captures d'écran, des résultats de recherche, de l'aperçu et des exportations pendant que vous travaillez.

**Verrouillage de l'app (Touch ID).** **HyperEdit › Verrouiller HyperEdit (⌃⌘L)** (le menu de l'application, sous Réglages…) recouvre toute la fenêtre — ruban, barre latérale, éditeur, volets et barre d'état — d'un écran de verrouillage opaque dans le thème actuel, ferme une fenêtre Réglages ouverte et masque le panneau d'Ajout rapide. Rien du document, pas même le nom du fichier, n'est affiché tant que l'app est verrouillée. Cliquez sur **Déverrouiller** (ou appuyez sur Retour) pour vous authentifier avec **Touch ID** ; si Touch ID échoue ou si le Mac n'en a pas, macOS se rabat sur votre mot de passe de session. Annuler laisse HyperEdit verrouillé et le bouton permet de réessayer.

- **Réglages › Verrouillage de l'app.** *Exiger Touch ID ou le mot de passe pour ouvrir HyperEdit* (désactivé par défaut) démarre l'app verrouillée : le document est chargé et l'enregistrement automatique continue de fonctionner, mais rien n'est visible tant que vous ne vous êtes pas authentifié. *Verrouiller après inactivité* (Jamais / 1 / 5 / 15 / 30 minutes, Jamais par défaut) verrouille après ce délai sans frappe de touche ni clic dans HyperEdit, indépendamment de l'option de lancement. *Verrouiller quand le Mac suspend son activité ou que l'écran se verrouille* (activé par défaut) s'applique tant que l'option de lancement est activée. Une légende indique si Touch ID est disponible sur ce Mac.
- Tant que l'app est verrouillée, la saisie au clavier est ignorée et la barre des menus ne peut pas être ouverte ; seuls ⌘Q, ⌘H / ⌥⌘H, ⌘M, ⌘W, ⌃⌘F et le menu du Dock fonctionnent encore. Le raccourci global d'Ajout rapide affiche la demande de déverrouillage au lieu du panneau et ouvre le panneau une fois que vous vous êtes authentifié.
- Il s'agit d'un verrou de confidentialité pour l'écran, pas d'un chiffrement : les fichiers sur le disque sont inchangés et lisibles par n'importe quelle autre app. L'option *Exiger…* ne peut pas être activée tant que le Mac n'a ni Touch ID ni mot de passe de session, vous ne pouvez donc pas vous retrouver bloqué dehors.

## 24. Obtenir de l'aide

- Rapports de bugs et idées : [GitHub Issues](https://github.com/Hyeongcheol-An/HyperEdit/issues) et [Discussions](https://github.com/Hyeongcheol-An/HyperEdit/discussions).
- Problèmes de sécurité : voir [SECURITY.md](../../SECURITY.md) pour un signalement privé.
- Traductions : les chaînes de l'interface se trouvent dans `l10n/ui.<langue>.json` dans le dépôt et ce guide dans `docs/guide/` ; les corrections sont bienvenues sous forme de pull requests — voir [CONTRIBUTING.md](../../CONTRIBUTING.md).

HyperEdit est un logiciel libre sous licence MIT. Sa disposition s'inspire du ruban classique d'UltraEdit ; UltraEdit est une marque d'IDM Computer Solutions, Inc., et HyperEdit n'est pas affilié à IDM.
