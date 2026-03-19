<div align="center">

# ⚡ Codex Rate Watcher

### Nunca más te quedes sin cuota a mitad de sesión

Una app ultrarrápida para la barra de menú de macOS que monitorea en tiempo real el uso del límite de velocidad de [OpenAI Codex](https://openai.com/index/codex/) (ChatGPT Pro / Team) — con gestión de múltiples cuentas, predicciones de consumo y cambio inteligente.

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
  <img src="docs/screenshot.jpg" width="440" alt="Codex Rate Watcher — app de barra de menú macOS para monitorear límites de velocidad de OpenAI Codex ChatGPT en tiempo real" />
</p>

*Monitoreo de cuota en tiempo real · Predicción de consumo · Cambio de cuentas · Cuenta regresiva de reinicio*

</div>

---

## 🤯 El Problema

Estás en pleno estado de flujo, programando en pareja con Codex, refactorizando un módulo crítico — y de repente **chocas contra el muro del límite de velocidad**. Sin aviso. Sin cuenta regresiva. Solo un frío `429 Too Many Requests`.

Esperas. Refrescas. No tienes idea de cuándo se reinicia tu cuota ni qué tan rápido la consumiste.

**Codex Rate Watcher** soluciona esto. Permanentemente.

## 🎯 Qué Hace

Codex Rate Watcher vive en tu barra de menú de macOS y te da **visibilidad total** sobre el uso de límites de velocidad de OpenAI Codex / ChatGPT:

| Capacidad | Descripción |
|---|---|
| **📊 Seguimiento en tiempo real** | Monitorea límites de 5 horas primario, semanal y revisión de código simultáneamente |
| **🔥 Predicción de consumo** | Predice *exactamente* cuándo se agota tu cuota |
| **⏰ Cuenta regresiva de reinicio** | Cada tarjeta muestra su hora de reinicio — no solo cuando estás bloqueado |
| **👥 Gestión de múltiples cuentas** | Captura automática de snapshots; gestiona cuentas Plus y Team en paralelo |
| **🧠 Cambio inteligente** | Algoritmo de puntuación ponderada recomienda la mejor cuenta |
| **🔄 Reconciliación automática** | Snapshots huérfanos auto-descubiertos y registrados al iniciar |
| **🏷️ Insignias de plan** | Muestra claramente Plus / Team en la interfaz |
| **🎨 UI de tema oscuro** | Diseño inspirado en Linear con tarjetas de cuota codificadas por color |

## ✨ Características Principales

- **Estado en barra de menú** — porcentaje restante siempre visible
- **Seguimiento tridimensional** — ventana de 5h + semanal + revisión de código
- **Predicciones de consumo** — regresión lineal sobre muestras de uso
- **Hora de reinicio en cada tarjeta** — incluso para cuentas activas
- **Ordenamiento de disponibilidad en 5 niveles** — disponible → bajo → bloqueado → error → sin verificar
- **Cambio con un clic** — respaldo automático antes de cambiar
- **Monitoreo de archivo auth** — detecta `codex login` en tiempo real vía kqueue
- **Reconciliación de snapshots huérfanos** — nunca pierdas una cuenta
- **Modo ventana de depuración** — bandera `--window` para ventana independiente
- **🔔 Sistema de alertas inteligentes** — notificaciones configurables por umbral (50%, 30%, 15%, 5%), alertas nativas de macOS, deduplicación por ventana de reinicio y alertas sonoras según la urgencia
- **🎨 Icono dinámico en la barra de menú** — el icono cambia de color en tiempo real según el estado de la cuota (verde → amarillo → naranja → rojo), retroalimentación visual instantánea sin abrir la app
- **Cero dependencias** — frameworks puros del sistema Apple

## 📥 Descarga

Descarga los paquetes `.app` precompilados en [Releases](https://github.com/sinoon/codex-rate-watcher/releases) — **sin necesidad de Xcode ni Swift**.

| Chip | Descarga |
|---|---|
| **Apple Silicon** (M1 / M2 / M3 / M4) | [Última versión — Apple Silicon](https://github.com/sinoon/codex-rate-watcher/releases/latest) |
| **Intel** (x86_64) | [Última versión — Intel](https://github.com/sinoon/codex-rate-watcher/releases/latest) |

1. Descarga el `.zip` para el chip de tu Mac
2. Descomprime y arrastra **Codex Rate Watcher.app** a `/Applications`
3. Ejecútala — aparece en la barra de menú (no en el Dock)
4. Asegúrate de que Codex CLI esté conectado (`~/.codex/auth.json`)

> **Primer inicio:** La app no está notarizada. Clic derecho → **Abrir**, o Configuración → Privacidad → **Abrir de todos modos**.

---

## 🚀 Compilar desde el código fuente

### Requisitos previos

- **macOS 14** (Sonoma) o posterior
- **Codex CLI** instalado y con sesión iniciada
- **Swift 6.2+** (Xcode 26 o [swift.org](https://swift.org))

### Compilar y ejecutar

```bash
git clone https://github.com/sinoon/codex-rate-watcher.git
cd codex-rate-watcher
swift run
```

## ⚙️ Stack Tecnológico

| Componente | Tecnología |
|---|---|
| Lenguaje | Swift 6.2 |
| Framework UI | AppKit (solo código, sin SwiftUI/XIB) |
| Sistema de build | Swift Package Manager |
| Concurrencia | Swift Concurrency (async/await, Actor) |
| Red | URLSession |
| Criptografía | CryptoKit (fingerprint SHA256) |
| Monitoreo de archivos | GCD DispatchSource (kqueue) |
| Dependencias | **Ninguna** — frameworks puros del sistema |

## 🤝 Contribuciones

¡Las contribuciones son bienvenidas!

- Abre un issue para reportar bugs o solicitar funciones
- Envía un pull request
- Comparte tus consejos de flujo de trabajo multi-cuenta

## 📄 Licencia

[MIT](LICENSE) © 2026
