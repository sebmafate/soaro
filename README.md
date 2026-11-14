<img src="assets/icon.svg" width="64" height="64" alt="">

# Accalmie

*Accalmie* : le moment où la houle s'apaise. C'est l'idée de l'icône : des vagues qui s'aplatissent jusqu'à devenir une ligne droite, comme un Mac qu'on a remis au calme.

Application macOS native (Swift / SwiftUI) qui vit dans la barre de menus : elle surveille **CPU, GPU, mémoire, disque, réseau et batterie**, garde un historique, et propose des actions concrètes pour garder le Mac rapide et propre. Empreinte au repos : ~20-35 Mo de RAM, ~1-2 % de CPU.

## Deux façons de l'utiliser

- **Le panneau de la barre de menus** : coup d'œil rapide, se referme quand on clique ailleurs.
- **La fenêtre indépendante** (bouton fenêtre en haut du panneau, ou en relançant l'app depuis le Finder/Spotlight) : barre latérale, reste ouverte, style « verre » translucide (Liquid Glass sur macOS 26+, matériau translucide avant), bouton **épingle** pour la garder au premier plan, avec en plus la section **Ce Mac** (modèle, puce, cœurs, mémoire, écrans, numéro de série) et les réglages.

La barre de menus affiche les mesures choisies en style **compact** (petit libellé au-dessus de la valeur) ou en texte sur une ligne : CPU, GPU, mémoire, disque, réseau, batterie.

Chaque valeur change de couleur selon son niveau : par défaut (normal), **orange** (moyen), **rouge** (élevé), **pastille écarlate** (critique). Seuils par défaut, **réglables dans les réglages** : CPU/GPU 60 / 80 / 95 % ; disque 80 / 90 / 95 % occupés ; batterie 20 / 10 / 5 % hors secteur. Non réglable : la mémoire, colorée d'après la *pression réelle* de macOS (et le swap), pas le pourcentage utilisé. L'icône d'Accalmie reste toujours visible, avec un petit badge en cas d'alerte, et une **infobulle au survol** explique chaque alerte et chaque valeur colorée.

## Onglets

| Onglet | Contenu |
| --- | --- |
| **Aperçu** | 6 jauges (CPU, mémoire, GPU, disque, réseau, batterie) avec courbes, recommandations, apps les plus gourmandes |
| **Performances** | Charge **par cœur** (cœurs E / P d'Apple Silicon), détail mémoire (pression, swap, compressée…), GPU, disque (débits lecture/écriture, état SMART), **températures, ventilateurs, consommation (W)**, processus triés par CPU / mémoire / disque |
| **Batterie** | Niveau, état de charge, temps restant, **santé** (capacité max / d'origine), **cycles**, puissance (W), chargeur, température, **impact énergétique par application** |
| **Réseau** | Débits ↓↑, volume du jour, **détection du VPN** (nom, tout le trafic ou partiel), **IP publique + pays avec drapeau** (optionnel), IP locale, Wi-Fi (qualité, signal, débit négocié), latence (optionnelle), **trafic par application** |
| **Historique** | Graphiques sur 1 h / 24 h / 7 j / 30 j pour chaque mesure, stockés localement (SQLite) |
| **Nettoyage** | Nettoyage rapide, caches système et développeur, puis 4 outils : **gros fichiers**, **projets inactifs** (`node_modules`, `.build`, `target`, `Pods`), **désinstalleur** d'apps avec leurs restes, **éléments de démarrage** |

La barre de menus affiche au choix CPU, mémoire, GPU, batterie, débit réseau (réglages).

## Recommandations automatiques

Disque presque plein · mémoire sous pression (propose de quitter l'app la plus lourde) · **fuite mémoire probable** (croissance linéaire soutenue sur 30 min+) · CPU saturé · Mac qui chauffe · batterie faible / usée / chaude · redémarrage conseillé après 14 jours. Notifications uniquement pour le critique (max. une par type toutes les 2 h).

## Conseils de réglage

Section distincte des alertes (ni notification, ni badge), dans l'Aperçu. Accalmie **lit** certains réglages de macOS et explique quoi faire ; elle **ne modifie jamais un réglage** : le bouton ouvre le bon panneau de Réglages Système. Chaque conseil peut être ignoré définitivement (et réaffiché depuis les réglages).

| Conseil | Quand |
| --- | --- |
| Charge limitée à N % par macOS | Batterie branchée qui ne charge pas à cause de la recharge optimisée |
| Mode économie d'énergie | ≤ 30 % de batterie, hors secteur |
| Une app empêche la mise en veille | Veille bloquée depuis plus de 2 h par une app tierce |
| Programmes au démarrage | 12 agents de lancement actifs ou plus |
| Spotlight indexe vos fichiers | Indexation qui occupe le processeur (pour dire que c'est temporaire) |
| Optimiser le stockage / corbeille automatique | Moins de 20 % d'espace libre |
| Mise à jour de macOS disponible | Version en attente plus récente que celle installée |
| Sauvegarde Time Machine | Aucune destination, ou dernière sauvegarde de plus de 14 jours |

`Accalmie --advice` affiche en texte les réglages lus et les conseils qui en découlent.

## Sécurité et vie privée

- Tout ce qui est supprimé est confirmé avant, et limité à **votre dossier personnel** (`CleanupService.isSafeToDelete`, testé). Jamais le dossier personnel lui-même.
- Gros fichiers et désinstalleur : **mise à la corbeille** (récupérable). Caches et dossiers régénérables : suppression directe, après confirmation.
- Les dossiers de projet ne sont proposés que s'ils sont accompagnés de leur fichier de projet (`package.json`, `Package.swift`, `Cargo.toml`…). Un `build/` ou `dist/` n'est jamais proposé à la suppression.
- Le désinstalleur utilise une correspondance **stricte** (identifiant de bundle exact) pour les restes ; il refuse les apps Apple et les apps ouvertes.
- Aucune donnée ne quitte le Mac, sauf deux options **désactivées par défaut** : le ping de latence vers 1.1.1.1, et la recherche d'**IP publique / pays** (service tiers ipwho.is, ipapi.co en secours : il voit votre IP publique ; au plus une requête toutes les 5 min, uniquement onglet Réseau ouvert, session éphémère sans cookie ni cache, rien n'est écrit sur le disque). La détection du VPN est, elle, 100 % locale (route par défaut, services VPN de macOS, interfaces de tunnel).
- Capteurs de température/ventilateurs : interfaces non documentées par Apple (HID, SMC), lues de façon défensive ; si une lecture échoue, la section disparaît.

## Utilisation

```bash
swift run                         # lancer en développement
swift test                        # tests (128)
scripts/build-app.sh              # produit build/Accalmie.app (icône, LSUIElement, signature ad-hoc)
scripts/build-app.sh --install    # idem + copie dans /Applications
```

Outils de vérification (aucune écriture, aucune suppression) :

```bash
Accalmie --diagnostics           # affiche toutes les mesures en texte (CPU/cœurs, GPU, batterie, réseau, capteurs…)
Accalmie --diagnostics --public-ip   # idem + requête IP publique (explicite)
Accalmie --scan [--per-root]     # lance les scanners de nettoyage en lecture seule sur votre dossier personnel
Accalmie --snapshot <dossier> [--dark] [--tools] [--window]   # rend chaque onglet en PNG (historique factice en mémoire)
```

Prérequis : macOS 14+, Xcode / Swift 6.

L'identifiant de l'app (`local.accalmie`) est volontairement neutre : à remplacer par un domaine qui vous appartient (`BUNDLE_ID` dans `scripts/build-app.sh`) avant toute diffusion.

### Anciennes versions

L'app s'est d'abord appelée « MyCleaner ». Au premier lancement, `LegacyMigration` reprend l'historique (`~/Library/Application Support/MyCleaner` → `Accalmie`) et les préférences (`com.mycleaner.app`), sans jamais écraser une valeur existante. Les anciens fichiers de préférences (`~/Library/Preferences/com.mycleaner.app.plist` et `MyCleaner.plist`) peuvent être supprimés à la main.

### Autorisations demandées par macOS

- **Finder** (automatisation) au premier « Vider la corbeille ».
- **System Events** (automatisation) si vous affichez la liste « Ouvrir à la connexion ».
- **Documents / Téléchargements / etc.** lors de l'analyse des gros fichiers.
- La taille de la **corbeille** n'est lisible qu'avec « Accès complet au disque » ; elle peut être vidée sans.
- Le nom du réseau Wi-Fi (SSID) reste masqué sans autorisation de localisation (le reste des infos Wi-Fi fonctionne).
- « Ouvrir à la connexion » ne fonctionne que si l'app est dans `/Applications`.

## Architecture

| Fichier | Rôle |
| --- | --- |
| `SystemSampler.swift` | CPU (global + par cœur), mémoire, disque, uptime, liste des processus (Mach, `sysctl`, `ps`) |
| `Samplers/IOKitSamplers.swift` | GPU, batterie, E/S disque, SMART (IOKit) |
| `Samplers/NetworkSampler.swift` | Débits, Wi-Fi, ping, `nettop` par app, énergie par app (`top`), E/S par processus |
| `Samplers/VPNDetector.swift`, `Samplers/PublicIPService.swift` | Détection VPN locale ; IP publique, pays et drapeau (réponse validée, jamais affichée si ce n'est pas une vraie IP) |
| `Samplers/SensorSampler.swift` | Températures (HID), ventilateurs et puissance (SMC) |
| `HistoryStore.swift` | Historique SQLite, agrégation par tranches, rétention 30 jours |
| `LeakDetector.swift` | Détection de fuite mémoire (régression linéaire + seuils) |
| `Advice.swift` | Conseils de réglage : collecte en lecture seule (`pmset`, `tmutil`, préférences), analyse et moteur purs |
| `RecommendationEngine.swift` | Fonction pure : mesures → recommandations |
| `CleanupService.swift`, `Cleanup/*` | Caches, gros fichiers, projets inactifs, désinstalleur, éléments de démarrage |
| `LegacyMigration.swift` | Reprise des données de l'ancien nom (historique, préférences) |
| `AppState.swift` | Cadencement (3 s ; capteurs et batterie 9 s panneau fermé), historique, actions, notifications |
| `Views/MainWindow.swift`, `MachineInfo.swift` | Fenêtre indépendante (AppKit, créée à la demande, détruite à la fermeture) et fiche « Ce Mac » |
| `Views/MenuBarWidgets.swift` | Libellé compact de la barre de menus, dessiné dans une image modèle |
| `Views/` | Panneau à onglets. Le contenu est retiré de la hiérarchie SwiftUI quand le panneau est caché, pour ne rien coûter au repos |

Créé avec [T3 Code](https://t3.codes).
