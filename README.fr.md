<div align="center">

# ⚡ Codex Rate Watcher

### Ne soyez plus jamais limité en pleine session

Une application macOS ultra-rapide dans la barre de menu qui surveille en temps réel l'utilisation des limites de débit [OpenAI Codex](https://openai.com/index/codex/) (ChatGPT Pro / Team) — avec gestion multi-comptes, prédictions de consommation et changement intelligent.

[![en](https://img.shields.io/badge/lang-English-blue.svg)](README.md)
[![zh-CN](https://img.shields.io/badge/lang-简体中文-red.svg)](README.zh-CN.md)
[![ja](https://img.shields.io/badge/lang-日本語-green.svg)](README.ja.md)
[![ko](https://img.shields.io/badge/lang-한국어-yellow.svg)](README.ko.md)
[![es](https://img.shields.io/badge/lang-Español-orange.svg)](README.es.md)
[![fr](https://img.shields.io/badge/lang-Français-purple.svg)](README.fr.md)
[![de](https://img.shields.io/badge/lang-Deutsch-black.svg)](README.de.md)

![macOS](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.2-orange)
![License](https://img.shields.io/badge/license-MIT-brightgreen)
![Zero Dependencies](https://img.shields.io/badge/dependencies-zero-success)

<p>
  <img src="docs/screenshot.jpg" width="440" alt="Codex Rate Watcher — application macOS de barre de menu pour surveiller les limites de débit OpenAI Codex ChatGPT en temps réel" />
</p>

*Surveillance de quota en temps réel · Prédiction de consommation · Changement multi-comptes · Compte à rebours de réinitialisation*

</div>

---

## 🤯 Le Problème

Vous êtes en plein flow, en pair-programming avec Codex, en train de refactoriser un module critique — et soudain **vous heurtez le mur de la limite de débit**. Pas d'avertissement. Pas de compte à rebours. Juste un froid `429 Too Many Requests`.

Vous attendez. Vous rafraîchissez. Vous n'avez aucune idée de quand votre quota se réinitialise ni à quelle vitesse vous l'avez consommé.

**Codex Rate Watcher** résout ce problème. Définitivement.

## 🎯 Ce Qu'il Fait

Codex Rate Watcher réside dans votre barre de menu macOS et vous offre une **visibilité totale** sur l'utilisation des limites de débit OpenAI Codex / ChatGPT :

| Fonctionnalité | Description |
|---|---|
| **📊 Suivi en temps réel** | Surveillez les limites 5h primaire, hebdomadaire et de revue de code simultanément |
| **🔥 Prédiction de consommation** | Prédit *exactement* quand votre quota sera épuisé |
| **⏰ Compte à rebours** | Chaque carte affiche son heure de réinitialisation |
| **👥 Gestion multi-comptes** | Capture automatique des snapshots ; gérez Plus et Team en parallèle |
| **🧠 Changement intelligent** | Algorithme de scoring pondéré recommande le meilleur compte |
| **🔄 Réconciliation automatique** | Snapshots orphelins auto-découverts et enregistrés au démarrage |
| **🏷️ Badges de plan** | Affiche clairement Plus / Team dans l'interface |
| **🎨 UI thème sombre** | Design inspiré de Linear avec cartes de quota colorées |

## ✨ Fonctionnalités Clés

- **Statut barre de menu** — pourcentage restant toujours visible
- **Suivi tridimensionnel** — fenêtre 5h + hebdomadaire + revue de code
- **Prédictions de consommation** — régression linéaire sur les échantillons d'utilisation
- **Heure de réinitialisation sur chaque carte** — même pour les comptes actifs
- **Tri de disponibilité à 5 niveaux** — disponible → faible → bloqué → erreur → non vérifié
- **Changement en un clic** — sauvegarde automatique avant le changement
- **Surveillance du fichier auth** — détecte `codex login` en temps réel via kqueue
- **Réconciliation des snapshots orphelins** — ne perdez jamais un compte
- **Mode fenêtre de débogage** — drapeau `--window` pour fenêtre autonome
- **Zéro dépendance** — frameworks système Apple purs

## 📥 Téléchargement

Téléchargez les bundles `.app` pré-compilés sur la page [Releases](https://github.com/sinoon/codex-rate-watcher/releases) — **aucun Xcode ni toolchain Swift requis**.

| Puce | Téléchargement |
|---|---|
| **Apple Silicon** (M1 / M2 / M3 / M4) | [Dernière version — Apple Silicon](https://github.com/sinoon/codex-rate-watcher/releases/latest) |
| **Intel** (x86_64) | [Dernière version — Intel](https://github.com/sinoon/codex-rate-watcher/releases/latest) |

1. Téléchargez le `.zip` correspondant à la puce de votre Mac
2. Décompressez et glissez **Codex Rate Watcher.app** dans `/Applications`
3. Lancez — l'app apparaît dans la barre de menus (pas dans le Dock)
4. Vérifiez que Codex CLI est connecté (`~/.codex/auth.json`)

> **Premier lancement :** L'app n'est pas notariée. Clic droit → **Ouvrir**, ou Réglages → Confidentialité → **Ouvrir quand même**.

---

## 🚀 Compiler depuis les sources

### Prérequis

- **macOS 14** (Sonoma) ou ultérieur
- **Codex CLI** installé et connecté
- **Swift 6.2+** (Xcode 26 ou [swift.org](https://swift.org))

### Compiler et exécuter

```bash
git clone https://github.com/sinoon/codex-rate-watcher.git
cd codex-rate-watcher
swift run
```

## ⚙️ Stack Technique

| Composant | Technologie |
|---|---|
| Langage | Swift 6.2 |
| Framework UI | AppKit (code uniquement, sans SwiftUI/XIB) |
| Système de build | Swift Package Manager |
| Concurrence | Swift Concurrency (async/await, Actor) |
| Réseau | URLSession |
| Cryptographie | CryptoKit (empreinte SHA256) |
| Surveillance fichiers | GCD DispatchSource (kqueue) |
| Dépendances | **Aucune** — frameworks système purs |

## 🤝 Contribuer

Les contributions sont les bienvenues !

- Ouvrez une issue pour signaler des bugs ou demander des fonctionnalités
- Soumettez une pull request
- Partagez vos astuces de workflow multi-comptes

## 📄 Licence

[MIT](LICENSE) © 2026
