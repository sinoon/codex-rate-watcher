<div align="center">

# ⚡ Codex Rate Watcher

### 세션 중간에 속도 제한에 걸리지 마세요

[OpenAI Codex](https://openai.com/index/codex/) (ChatGPT Pro / Team) 속도 제한 사용량을 실시간으로 모니터링하는 초고속 macOS 메뉴 바 앱 —— 다중 계정 관리, 소비율 예측, 스마트 전환 기능 포함.

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
  <img src="docs/screenshot.jpg" width="440" alt="Codex Rate Watcher — OpenAI Codex ChatGPT 속도 제한을 실시간 모니터링하는 macOS 메뉴 바 앱" />
</p>

*실시간 할당량 모니터링 · 소비율 예측 · 다중 계정 전환 · 리셋 카운트다운*

</div>

---

## 🤯 문제

몰입 상태에서 Codex와 페어 프로그래밍하며 핵심 모듈을 리팩토링하고 있는데——갑자기 **속도 제한 벽에 부딪힙니다**. 경고도 없고, 카운트다운도 없이 차가운 `429 Too Many Requests`만 남습니다.

기다리고, 새로고침하고, 할당량이 언제 리셋되는지, 얼마나 빠르게 소비했는지 전혀 알 수 없습니다.

**Codex Rate Watcher**가 이 문제를 완전히 해결합니다.

## 🎯 핵심 기능

Codex Rate Watcher는 macOS 메뉴 바에 상주하며 OpenAI Codex / ChatGPT 속도 제한 사용량을 **완전히 가시화**합니다:

| 기능 | 설명 |
|---|---|
| **📊 실시간 할당량 추적** | 5시간 기본, 주간, 코드 리뷰 제한을 동시 모니터링 |
| **🔥 소비율 예측** | 할당량 소진 시각을 정확하게 예측 |
| **⏰ 리셋 카운트다운** | 모든 할당량 카드에 리셋 시간 표시 |
| **👥 다중 계정 관리** | 계정 스냅샷 자동 캡처; Plus와 Team 계정 병행 관리 |
| **🧠 스마트 전환** | 가중 점수 알고리즘으로 최적의 전환 대상 추천 |
| **🔄 고아 스냅샷 자동 통합** | 시작 시 인덱스 외 인증 스냅샷 자동 발견 및 등록 |
| **🏷️ 플랜 배지** | UI에서 Plus / Team을 명확히 표시 |
| **🎨 다크 테마 UI** | Linear 영감의 디자인, 색상 코딩된 할당량 카드 |

## ✨ 주요 특징

- **메뉴 바 상태** —— 남은 퍼센트 항상 표시
- **3차원 추적** —— 5h 기본 + 주간 + 코드 리뷰
- **소비율 예측** —— 사용량 샘플의 선형 회귀로 소진 시각 예측
- **모든 카드에 리셋 시간** —— 활성 계정에도 표시
- **5단계 가용성 정렬** —— 사용 가능 → 부족 → 차단 → 오류 → 미검증
- **원클릭 전환** —— 전환 전 자동 백업
- **인증 파일 감시** —— kqueue로 `codex login` 실시간 감지
- **고아 스냅샷 통합** —— 인덱스가 깨져도 계정을 잃지 않음
- **디버그 윈도우 모드** —— `--window` 플래그로 독립 창 실행
- **🔔 스마트 알림 시스템** —— 설정 가능한 임계값 알림(50%, 30%, 15%, 5%), macOS 네이티브 알림, 리셋 윈도우별 중복 제거, 긴급도에 따른 사운드 알림
- **🎨 동적 상태 바 아이콘** —— 메뉴 바 아이콘이 쿼터 상태에 따라 실시간으로 색상 변경(녹색 → 노란색 → 주황색 → 빨간색), 앱을 열지 않아도 한눈에 파악 가능
- **제로 의존성** —— 순수 Apple 시스템 프레임워크만 사용

## 📥 다운로드

[Releases](https://github.com/sinoon/codex-rate-watcher/releases) 페이지에서 사전 빌드된 `.app` 번들을 다운로드하세요 — **Xcode나 Swift 툴체인 불필요**.

| 칩 | 다운로드 |
|---|---|
| **Apple Silicon** (M1 / M2 / M3 / M4) | [최신 버전 — Apple Silicon](https://github.com/sinoon/codex-rate-watcher/releases/latest) |
| **Intel** (x86_64) | [최신 버전 — Intel](https://github.com/sinoon/codex-rate-watcher/releases/latest) |

1. Mac 칩에 맞는 `.zip` 다운로드
2. 압축 해제 후 **Codex Rate Watcher.app**을 `/Applications`으로 드래그
3. 실행 — 메뉴 바에 표시됩니다 (Dock 아님)
4. Codex CLI 로그인 확인 (`~/.codex/auth.json` 필요)

> **첫 실행 시:** 앱이 공증되지 않았습니다. 우클릭 → **열기**, 또는 시스템 설정 → 개인정보 보호 및 보안 → **확인 없이 열기**.

---

## 🚀 소스에서 빌드

### 사전 요구사항

- **macOS 14** (Sonoma) 이상
- **Codex CLI** 설치 및 로그인 (`~/.codex/auth.json`)
- **Swift 6.2+** (Xcode 26 또는 [swift.org](https://swift.org) 툴체인)

### 빌드 및 실행

```bash
git clone https://github.com/sinoon/codex-rate-watcher.git
cd codex-rate-watcher
swift run
```

## ⚙️ 기술 스택

| 구성 요소 | 기술 |
|---|---|
| 언어 | Swift 6.2 |
| UI 프레임워크 | AppKit (코드만, SwiftUI/XIB 없음) |
| 빌드 시스템 | Swift Package Manager |
| 동시성 | Swift Concurrency (async/await, Actor) |
| 네트워크 | URLSession |
| 암호화 | CryptoKit (SHA256 핑거프린트) |
| 파일 감시 | GCD DispatchSource (kqueue) |
| 의존성 | **없음** — 순수 시스템 프레임워크 |

## 🤝 기여

기여를 환영합니다!

- 버그 보고나 기능 요청 Issue 열기
- Pull Request 제출
- 다중 계정 워크플로 팁 공유

## 📄 라이선스

[MIT](LICENSE) © 2026
