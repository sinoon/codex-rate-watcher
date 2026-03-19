<div align="center">

# ⚡ Codex Rate Watcher

### Nie wieder mitten in der Session gedrosselt werden

Eine blitzschnelle macOS-Menüleisten-App, die die [OpenAI Codex](https://openai.com/index/codex/) (ChatGPT Pro / Team) Rate-Limit-Nutzung in Echtzeit überwacht — mit Multi-Account-Verwaltung, Verbrauchsprognosen und intelligentem Kontowechsel.

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
  <img src="docs/screenshot.jpg" width="440" alt="Codex Rate Watcher — macOS Menüleisten-App zur Echtzeit-Überwachung von OpenAI Codex ChatGPT Rate-Limits" />
</p>

*Echtzeit-Kontingentüberwachung · Verbrauchsprognose · Multi-Account-Wechsel · Reset-Countdown*

</div>

---

## 🤯 Das Problem

Sie sind im Flow-Zustand, programmieren im Pair mit Codex, refaktorisieren ein kritisches Modul — und plötzlich **trifft Sie die Rate-Limit-Mauer**. Keine Warnung. Kein Countdown. Nur ein kaltes `429 Too Many Requests`.

Sie warten. Sie aktualisieren. Sie haben keine Ahnung, wann Ihr Kontingent zurückgesetzt wird oder wie schnell Sie es verbraucht haben.

**Codex Rate Watcher** löst dieses Problem. Endgültig.

## 🎯 Was Es Macht

Codex Rate Watcher lebt in Ihrer macOS-Menüleiste und bietet Ihnen **vollständige Transparenz** über Ihre OpenAI Codex / ChatGPT Rate-Limit-Nutzung:

| Fähigkeit | Beschreibung |
|---|---|
| **📊 Echtzeit-Kontingent-Tracking** | Überwacht 5-Stunden-Primär-, Wochen- und Code-Review-Limits gleichzeitig |
| **🔥 Verbrauchsprognose** | Sagt *genau* voraus, wann Ihr Kontingent aufgebraucht ist |
| **⏰ Reset-Countdown** | Jede Kontingent-Karte zeigt ihre Reset-Zeit |
| **👥 Multi-Account-Verwaltung** | Automatische Snapshot-Erfassung; Plus und Team parallel verwalten |
| **🧠 Intelligenter Wechsel** | Gewichteter Scoring-Algorithmus empfiehlt das beste Konto |
| **🔄 Automatische Abstimmung** | Verwaiste Snapshots werden beim Start automatisch erkannt und registriert |
| **🏷️ Plan-Badges** | Zeigt Plus / Team deutlich in der UI an |
| **🎨 Dunkles Theme** | Von Linear inspiriertes Design mit farbcodierten Kontingent-Karten |

## ✨ Hauptmerkmale

- **Menüleisten-Status** — verbleibender Prozentsatz immer sichtbar
- **Dreidimensionales Tracking** — 5h-Primär + Wöchentlich + Code-Review
- **Verbrauchsprognosen** — lineare Regression über Nutzungssamples
- **Reset-Zeit auf jeder Karte** — auch für aktive Konten
- **5-stufige Verfügbarkeitssortierung** — nutzbar → niedrig → gesperrt → Fehler → nicht verifiziert
- **Ein-Klick-Wechsel** — automatisches Backup vor dem Wechsel
- **Auth-Datei-Überwachung** — erkennt `codex login` in Echtzeit via kqueue
- **Verwaiste Snapshot-Abstimmung** — Konten gehen nie verloren
- **Debug-Fenstermodus** — `--window`-Flag für eigenständiges Fenster
- **🔔 Intelligentes Warnsystem** — konfigurierbare Schwellenwert-Benachrichtigungen (50 %, 30 %, 15 %, 5 %), native macOS-Benachrichtigungen, Deduplizierung pro Reset-Fenster und dringlichkeitsbasierte Tonalarme
- **🎨 Dynamisches Statusleisten-Icon** — das Menüleisten-Icon ändert seine Farbe in Echtzeit je nach Kontingent-Gesundheit (grün → gelb → orange → rot), sofortiges visuelles Feedback ohne die App zu öffnen
- **Null Abhängigkeiten** — reine Apple-System-Frameworks

## 📥 Download

Laden Sie die vorgefertigten `.app`-Bundles von der [Releases](https://github.com/sinoon/codex-rate-watcher/releases)-Seite herunter — **kein Xcode oder Swift Toolchain erforderlich**.

| Chip | Download |
|---|---|
| **Apple Silicon** (M1 / M2 / M3 / M4) | [Neueste Version — Apple Silicon](https://github.com/sinoon/codex-rate-watcher/releases/latest) |
| **Intel** (x86_64) | [Neueste Version — Intel](https://github.com/sinoon/codex-rate-watcher/releases/latest) |

1. Laden Sie die `.zip` für den Chip Ihres Macs herunter
2. Entpacken und **Codex Rate Watcher.app** in `/Applications` ziehen
3. Starten — die App erscheint in der Menüleiste (nicht im Dock)
4. Stellen Sie sicher, dass Codex CLI angemeldet ist (`~/.codex/auth.json`)

> **Erster Start:** Die App ist nicht notarisiert. Rechtsklick → **Öffnen**, oder Systemeinstellungen → Datenschutz & Sicherheit → **Trotzdem öffnen**.

---

## 🚀 Aus dem Quellcode bauen

### Voraussetzungen

- **macOS 14** (Sonoma) oder neuer
- **Codex CLI** installiert und angemeldet
- **Swift 6.2+** (Xcode 26 oder [swift.org](https://swift.org))

### Bauen und ausführen

```bash
git clone https://github.com/sinoon/codex-rate-watcher.git
cd codex-rate-watcher
swift run
```

## ⚙️ Tech-Stack

| Komponente | Technologie |
|---|---|
| Sprache | Swift 6.2 |
| UI-Framework | AppKit (nur Code, kein SwiftUI/XIB) |
| Build-System | Swift Package Manager |
| Nebenläufigkeit | Swift Concurrency (async/await, Actor) |
| Netzwerk | URLSession |
| Kryptographie | CryptoKit (SHA256-Fingerprint) |
| Dateiüberwachung | GCD DispatchSource (kqueue) |
| Abhängigkeiten | **Keine** — reine System-Frameworks |

## 🤝 Mitwirken

Beiträge sind willkommen!

- Öffnen Sie ein Issue für Fehlerberichte oder Feature-Anfragen
- Reichen Sie einen Pull Request ein
- Teilen Sie Ihre Multi-Account-Workflow-Tipps

## 📄 Lizenz

[MIT](LICENSE) © 2026
