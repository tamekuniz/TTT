# フォK Step 4 進捗記録

## サイクル概要
- **要件**: ショートカット録音開始/停止時のフィードバック追加（触覚 + システム音 + 設定トグル）
- **計画作成日時**: 2026-04-25 23:53
- **タスク総数**: 2
- **想定サイクル**: 1サイクル完結

---

## タスク進捗

### Task 1: SettingsManager に音フィードバック設定プロパティを追加
- **ステータス**: 未着手
- **担当**: 実装小人ちゃん（次 phase）
- **対象**: `Sources/TypeToTalk/Managers/SettingsManager.swift`
- **完了条件**:
  - [ ] `@Published var soundFeedbackEnabled: Bool` 追加（デフォルト true）
  - [ ] init で UserDefaults `object(forKey:)` チェック付き復元実装
  - [ ] `swift build` 成功
- **完了日時**: -
- **メモ**: -

### Task 2: TypeToTalkApp & SettingsView に音フィードバック実装と UI を追加
- **ステータス**: 未着手（Task 1 完了後）
- **担当**: 実装小人ちゃん（次 phase）
- **対象**:
  - `Sources/TypeToTalk/App/TypeToTalkApp.swift`
  - `Sources/TypeToTalk/Views/SettingsView.swift`
- **完了条件**:
  - [ ] `playFeedbackSound(named:)` ヘルパー追加（settings.soundFeedbackEnabled ガード付き）
  - [ ] toggleRecording 内 録音停止直前に `playFeedbackSound(named: "Pop")` 追加
  - [ ] toggleRecording 内 録音開始直前に `playFeedbackSound(named: "Tink")` 追加
  - [ ] SettingsView に「フィードバック音」Toggle 追加
  - [ ] `swift build` 成功
  - [ ] `swift test` 既存 16 件 PASS
- **完了日時**: -
- **メモ**: -

---

## 検証履歴

### ビルド検証
- 未実施

### 自動テスト
- 未実施

### 実機目視テスト（Step 6 予定）
| # | テスト項目 | 結果 | 備考 |
|---|---|---|---|
| 1 | 設定 ON で録音開始 → Tink + 触覚 | - | - |
| 2 | 設定 ON で録音停止 → Pop + 触覚 | - | - |
| 3 | 設定 OFF で録音開始 → 触覚のみ | - | - |
| 4 | 設定 OFF で録音停止 → 触覚のみ | - | - |
| 5 | アプリ再起動 → 設定値維持 | - | - |
| 6 | 設定 UI トグル表示・操作 | - | - |
| 7 | 右Option トリガで同様動作 | - | - |

---

## 課題・懸念

- なし（investigation.md 完了済み、リスク低）

## 完了サマリ

- 未完了
