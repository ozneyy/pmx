# 🚀 PMX - Simple utilisation de Proxmox CLI

PMX est un utilitaire CLI léger conçu pour la surveillance et la gestion rapide de vos instances Proxmox VE.

Contrairement aux outils de monitoring classiques, PMX utilise un rafraîchissement dynamique "in-place" qui n'efface pas votre terminal (style `cat`), vous permettant de conserver l'historique de commandes et votre prompt visibles pendant la surveillance.

---

## 📦 Installation rapide

Exécutez cette commande en tant que `root` sur votre nœud Proxmox (remplacez `VOTRE_PSEUDO` par votre nom d'utilisateur GitHub si nécessaire) :

```bash
curl -sSL https://raw.githubusercontent.com/ozneyy/PMX/main/install.sh | bash
```

Le script d'installation gère automatiquement les dépendances minimales requises (notamment `jq` et `bc`).

---

## 🛠️ Utilisation

Commandes principales :

| Commande       | Action                                                                 |
| -------------- | ---------------------------------------------------------------------- |
| `pmx`          | Liste rapide des VM/CT avec leur statut.                              |
| `pmx perf`     | Dashboard complet (CPU, RAM, DISK) en temps réel.                      |
| `pmx perf ID`  | Monitoring live focalisé sur une machine (ex: `pmx perf 106`).        |
| `pmx off`      | Filtre les machines éteintes pour un démarrage instantané.            |
| `pmx ID`       | Connexion terminal immédiate à la machine (ex: `pmx 106`).            |
| `pmx -help`    | Affiche l'aide et les options disponibles.                             |

Exemples rapides :

```bash
# Afficher la liste et le statut
pmx

# Dashboard général en temps réel
pmx perf

# Focus sur la VM/CT 106
pmx perf 106

# Se connecter à la VM/CT 106
pmx 106
```

---

## ✨ Caractéristiques techniques

- **Live Refresh In-Place** : Mise à jour du tableau sans `clear`, préservant l'historique du shell et évitant le scintillement.
- **Haute précision** : Consommation CPU calculée avec deux décimales (ex: `0.45%`) pour une surveillance précise.
- **Rendu adaptatif** : L'installateur permet de choisir entre un style graphique riche (icônes) ou une compatibilité maximale (ASCII).
- **Léger & Autonome** : Dépendances minimales (`jq`, `bc`) gérées automatiquement lors de l'installation.
- **Interface contextuelle** : Le prompt d'action s'adapte dynamiquement selon le mode (Démarrage, Connexion, Focus).

---

## 💡 Note sur les polices (NerdFonts)

L'utilisation des NerdFonts est totalement optionnelle.

Lors de l'installation, le script vous proposera deux modes :

- **Mode NerdFont** : Utilise des icônes graphiques (nécessite une police patchée comme JetBrainsMono NF, Meslo, etc.).
- **Mode Standard** : Utilise uniquement des caractères ASCII simples. Ce mode est compatible avec tous les terminaux, clients SSH mobiles et anciennes consoles.

---

## 🧰 Prérequis

- Un hôte Proxmox VE (accès root ou sudo).
- `curl` installé (utilisé pour l'installation).
- (Le script d'installation installera `jq` et `bc` si nécessaire.)

---

## 📝 Contribution

Contributions, retours et demandes d'amélioration bienvenus — ouvrez une issue ou une pull request sur le dépôt GitHub.

---



Merci d'utiliser PMX — monitoring simple, rapide et non intrusif pour Proxmox VE !
