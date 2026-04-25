# Step 4 進捗記録: TypeToTalk ショートカット仕様改修

**サイクル**: fok/20260425-1921-vg3h
**作成日**: 2026-04-25

---

## 進捗ログ

### 2026-04-25 — Step 4 計画完了
- 担当: Step 4 プランナー小人ちゃん（もも、博多弁）
- 入力: investigation.md（Step 3 調査報告）+ シア指定の採用方針
- 成果: todo.md 作成（2 タスク構成、検証計画含む）
- 採用方針: triggerRecording 1 つに統合、toggleWindow 削除、互換性なし
- 録音停止後のウインドウは「閉じない」方針（Step 8 でズンジー判断後に反転可）

---

## Task 進捗

### Task 1: triggerRecording のハンドラ統合 + toggleWindow 削除
- **状態**: 完了
- **担当**: Step 6 実装小人ちゃん（広島弁、Step 7 検証 みかん 大阪弁）
- **対象**: `Sources/TypeToTalk/App/TypeToTalkApp.swift`
- **実装**:
  - `KeyboardShortcuts.Name.toggleWindow` 定義を削除
  - `KeyboardShortcuts.onKeyDown(for: .toggleWindow)` ハンドラ削除
  - `handleToggleWindow()` メソッド削除
  - `handleTriggerShortcutDown()` の `.toggle` モードに `if !recorder.isRecording { showRecorderWindow() }` を追加してから `toggleRecording()` を呼ぶ構造に変更
  - `pushToTalk` モードにも同様の `showRecorderWindow()` 呼び出しを追加（録音開始時に必ず手前へ）
  - 録音停止後はウインドウを閉じない

### Task 2: SettingsView から toggleWindow UI を削除
- **状態**: 完了
- **担当**: Step 6 実装小人ちゃん
- **対象**: `Sources/TypeToTalk/Views/SettingsView.swift`
- **実装**: `settingRow("ウインドウ表示トグル") { KeyboardShortcuts.Recorder(for: .toggleWindow) }` 行を削除。caption は triggerRecording 説明として整合済みのため維持

### 検証
- xcodebuild BUILD SUCCEEDED
- grep -rn "toggleWindow|handleToggleWindow" Sources/ → NO_MATCHES
- 品質セルフチェック問題なし
- 実機確認はズンジー側で要実施

---

## 検証ログ

### ビルド検証
- 未実施

### 動作検証（S1〜S7）
- 未実施

### コード検証（grep）
- 未実施

---

## 課題・不確かポイント

- `showRecorderWindow()` のアクティベート有無 → Step 5 開始時に実装小人ちゃんが Read で確認
- 録音停止後のウインドウ挙動「閉じない」方針 → Step 8 でズンジーレビュー、次サイクルで反転検討

---

## 次アクション

- Step 5: 実装小人ちゃんを手配し、todo.md の Task 1 / Task 2 を実行
