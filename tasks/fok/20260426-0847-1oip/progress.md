# Step 4 進捗ログ — HUD パネル表示機構

**タスク**: 旧 TypeToTalkMainView ベース HUD を NSPanel(nonactivatingPanel) で実装
**フォルダ**: /Users/tamekuniz/GitHub/tamekuniz/TTT/tasks/fok/20260426-0847-1oip

---

## ログ

### 2026-04-26 08:47 — Step 4 プランニング完了
- **担当**: 桃ちゃん（プランナー小人ちゃん）
- **作業**: investigation.md（537行）を全件 Read。シア指定方針（Option 1: NSWindowController + NSHostingView）を採用して `todo.md` を作成。
- **決定事項**:
  - Phase A（骨組み: HUD 表示・基本連動）と Phase B（仕上げ: フェード・位置・トグル）に2分割。
  - HUD サイズは 280×200（マイク Φ72 + ステータス2行）。
  - SettingsLink / alert 系は HUD から削除。
  - 表示位置は画面下中央（Dock 上 40px）。
  - `visualFeedbackEnabled: Bool`（デフォルト true）を SettingsManager に追加し、SettingsView に「視覚フィードバック」トグルを追加。
  - error 状態は 5秒 auto-hide、idle 遷移後は 2秒 fadeOut。
- **影響ファイル（5件）**:
  - 新規: `/Sources/TypeToTalk/Views/HUDView.swift`
  - 新規: `/Sources/TypeToTalk/Managers/HUDPanelController.swift`
  - 編集: `/Sources/TypeToTalk/App/TypeToTalkApp.swift`
  - 編集: `/Sources/TypeToTalk/Managers/SettingsManager.swift`
  - 編集: `/Sources/TypeToTalk/Views/SettingsView.swift`
- **不確か明記**:
  - HUD 上マイクボタンの hit-test と nonactivatingPanel 相性 → Phase A 手動確認で検証
  - マルチディスプレイ位置調整は範囲外（`NSScreen.main` 採用、後続 issue）
  - HUD ドラッグ位置の永続化は範囲外
- **次フェーズへの引継ぎ**: 実装小人ちゃんは todo.md の Phase A → 動作確認 → Phase B の順で進めること。各 Phase 完了時に進捗を本ファイルに追記する。

---
