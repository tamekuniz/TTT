# フォK 進捗ログ: 「権限を再チェック」→「アプリを再起動」変更

**タスク ID**: 20260425-1932-i17i
**開始日**: 2026-04-25

---

## Step 履歴

### Step 1: 要件定義（完了）
- ボタンラベル「アプリを再起動」へ変更
- 録音中/処理中は confirmationDialog で警告
- 再起動方式: NSWorkspace.openApplication + NSApp.terminate

### Step 2: 計画素案（完了）
- シア指定方針: 再起動ロジックは AccessibilityManager ではなく責務に合った場所
- 旧 `recheckPermissionAndOpenSettingsIfNeeded()` は未使用なら削除
- 周辺ラベルも整合

### Step 3: 調査（完了）
- 担当: 小松島産スイカ Step 3 調査小人ちゃん
- 成果物: investigation.md
- 主要発見:
  - SettingsView L282-284 に対象ボタン
  - AccessibilityManager L29-34 の `recheckPermissionAndOpenSettingsIfNeeded()` は未使用
  - `refreshPermissionStatus()` 本体は他 4 箇所で使用中（削除不可）
  - entitlements 制約なし、NSWorkspace で再起動可能
  - 録音中・処理中の警告ダイアログ必須

### Step 4: 計画（本ステップ・完了）
- 担当: いちご Step 4 計画小人ちゃん
- 成果物: todo.md
- 設計決定:
  - **再起動ロジック配置**: `TypeToTalkCoordinator.restartApp()` （recorder/isProcessing 同一スコープ参照のため）
  - **ダイアログ配置**: SettingsView 内 `.confirmationDialog`（UI 責務）
  - **削除**: `AccessibilityManager.recheckPermissionAndOpenSettingsIfNeeded()`
- 1 サイクル / 1 タスクに収束（変更ファイル 3 つを一括）

### Step 6: 実装（完了）
- 担当: マンゴー小人ちゃん
- 実装内容:
  - `TypeToTalkApp.swift`: `TypeToTalkCoordinator.restartApp()` 追加（NSWorkspace.openApplication + completionHandler 内 NSApp.terminate、createsNewApplicationInstance=true、error 時は terminate しない）。Settings シーンに coordinator 渡す
  - `SettingsView.swift`: @ObservedObject coordinator + @State showRestartConfirmation を追加。ボタン「アプリを再起動」、録音中/処理中なら confirmationDialog で警告
  - `AccessibilityManager.swift`: `recheckPermissionAndOpenSettingsIfNeeded()` 削除

### Step 7: 自己検証（完了）
- 担当: 検証小人ちゃん（sonnet）
- xcodebuild BUILD SUCCEEDED
- grep "recheckPermissionAndOpenSettingsIfNeeded|権限を再チェック" → NO_MATCHES
- 品質セルフチェック: 命名◎、エラーハンドリング適切、過剰設計なし

### Step 8/9: 進捗更新・コミット
- 実機確認はズンジー側で実施予定
- メッセージ案: `[フォK] feat: 権限再チェックボタンをアプリ再起動ボタンに変更`

---

## メモ・注意事項

- **scenePhase 監視**: 再起動後の自動再チェックは継続動作（investigation 8.1 リスク低）
- **未保存データ**: SettingsManager は didSet で UserDefaults に即座保存済み（リスク低）
- **新プロセス**: AccessibilityManager.init() で hasPermission が自動更新される
- **AppKit import**: 既に NSApp/NSWorkspace 使用箇所があれば import 済みのはず（実装時確認）

## 不確か事項（実装時確認）

1. `coordinator.isProcessing` のプロパティ名・存在 → Grep で確認
2. SettingsView から coordinator への参照経路 → init 引数を Read で確認
3. TypeToTalkApp.swift の AppKit import 状況 → 冒頭 import を確認
