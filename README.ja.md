<div align="center">

# ⚡ Codex Rate Watcher

### セッション中のレート制限に、もう悩まされない

[OpenAI Codex](https://openai.com/index/codex/)（ChatGPT Pro / Team）のレート制限使用量をリアルタイムで監視する超高速 macOS メニューバーアプリ —— マルチアカウント管理、消費率予測、スマート切り替え機能付き。

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
  <img src="docs/screenshot.jpg" width="440" alt="Codex Rate Watcher — OpenAI Codex ChatGPT レート制限をリアルタイム監視する macOS メニューバーアプリ" />
</p>

*リアルタイムクォータ監視 · 消費率予測 · マルチアカウント切替 · リセットカウントダウン*

</div>

---

## 🤯 課題

フロー状態で Codex とペアプログラミングしている最中、重要なモジュールをリファクタリングしているとき——突然**レート制限の壁にぶつかる**。警告なし、カウントダウンなし。冷たい `429 Too Many Requests` だけ。

待って、リフレッシュして、クォータがいつリセットされるか、どれだけ速く消費したか、全くわからない。

**Codex Rate Watcher** がこの問題を完全に解決します。

## 🎯 機能概要

Codex Rate Watcher は macOS メニューバーに常駐し、OpenAI Codex / ChatGPT のレート制限使用量を**完全に可視化**します：

| 機能 | 説明 |
|---|---|
| **📊 リアルタイムクォータ追跡** | 5時間プライマリ、週間、コードレビュー制限を同時監視 |
| **🔥 消費率予測** | クォータ枯渇時刻を正確に予測（例：「1h32min後に枯渇、14:30リセット」） |
| **⏰ リセットカウントダウン** | 全クォータカードにリセット時刻を表示——ブロック時だけでなく |
| **👥 マルチアカウント管理** | アカウントスナップショットを自動キャプチャ; Plus と Team を並行管理 |
| **🧠 スマート切替** | 重み付けスコアリングで最適な切替先を推奨 |
| **🔄 孤立スナップショット自動統合** | 起動時にインデックス外の認証スナップショットを自動発見・登録 |
| **🏷️ プランバッジ** | UI で Plus / Team を明確に表示 |
| **🎨 ダークテーマ UI** | Linear インスパイアのデザイン、カラーコード付きクォータカード |

## ✨ 主な特徴

- **メニューバーステータス** —— 残量パーセンテージを常時表示
- **3次元トラッキング** —— 5h プライマリ + 週間 + コードレビュー
- **消費率予測** —— 使用量サンプルの線形回帰で枯渇時刻を予測
- **全カードにリセット時刻** —— アクティブアカウントでも表示
- **5段階アベイラビリティソート** —— 使用可能 → 残り少 → ブロック → エラー → 未検証
- **ワンクリック切替** —— 切替前に自動バックアップ
- **認証ファイル監視** —— kqueue で `codex login` をリアルタイム検出
- **孤立スナップショット統合** —— インデックス破損でもアカウントを失わない
- **デバッグウィンドウモード** —— `--window` フラグでスタンドアロンウィンドウ起動
- **ゼロ依存** —— 純正 Apple システムフレームワークのみ

## 📥 ダウンロード

[Releases](https://github.com/sinoon/codex-rate-watcher/releases) ページからビルド済み `.app` をダウンロードできます — **Xcode や Swift ツールチェーンは不要**です。

| チップ | ダウンロード |
|---|---|
| **Apple Silicon**（M1 / M2 / M3 / M4） | [最新版 — Apple Silicon](https://github.com/sinoon/codex-rate-watcher/releases/latest) |
| **Intel**（x86_64） | [最新版 — Intel](https://github.com/sinoon/codex-rate-watcher/releases/latest) |

1. お使いの Mac のチップに対応する `.zip` をダウンロード
2. 解凍して **Codex Rate Watcher.app** を `/Applications` にドラッグ
3. 起動 — メニューバーに表示されます（Dock には表示されません）
4. Codex CLI がログイン済みであることを確認（`~/.codex/auth.json` が必要）

> **初回起動時：** アプリは公証されていません。右クリック → **開く**、またはシステム設定 → プライバシーとセキュリティ → **このまま開く**。

---

## 🚀 ソースからビルド

### 前提条件

- **macOS 14**（Sonoma）以降
- **Codex CLI** インストール・ログイン済み（`~/.codex/auth.json`）
- **Swift 6.2+**（Xcode 26 または [swift.org](https://swift.org) ツールチェーン）

### ビルドと実行

```bash
git clone https://github.com/sinoon/codex-rate-watcher.git
cd codex-rate-watcher
swift run
```

## ⚙️ テックスタック

| コンポーネント | テクノロジー |
|---|---|
| 言語 | Swift 6.2 |
| UI フレームワーク | AppKit（コードオンリー、SwiftUI/XIB なし） |
| ビルドシステム | Swift Package Manager |
| 並行処理 | Swift Concurrency（async/await, Actor） |
| ネットワーク | URLSession |
| 暗号 | CryptoKit（SHA256 フィンガープリント） |
| ファイル監視 | GCD DispatchSource（kqueue） |
| 依存関係 | **なし** —— 純正システムフレームワーク |

## 🤝 コントリビューション

コントリビューション大歓迎です！

- バグ報告や機能リクエストの Issue を開く
- Pull Request を提出する
- マルチアカウントワークフローのヒントを共有する

## 📄 ライセンス

[MIT](LICENSE) © 2026
