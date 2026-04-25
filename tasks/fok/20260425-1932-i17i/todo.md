# フォK Step 4 計画書: 「権限を再チェック」→「アプリを再起動」変更

**作成日**: 2026-04-25
**プランナー**: いちご Step 4 計画小人ちゃん
**前提**: investigation.md を読了済み
**サイクル粒度**: 1 サイクル / 1 タスク（密接に関係する文言・ロジック・削除を一括処理）

---

## 0. 要件サマリ

- SettingsView の「権限を再チェック」ボタンを「アプリを再起動」に変更
- 押下時の挙動:
  - 録音中 (`recorder.isRecording == true`) または 処理中 (`isProcessing == true`) → confirmationDialog で警告 → OK で再起動 / Cancel で中止
  - それ以外 → 即座に再起動
- 再起動方式: `NSWorkspace.shared.openApplication(at:configuration:completionHandler:)` + `NSApp.terminate(nil)`
- 周辺ラベル（「権限を再チェックする」等の説明文）も整合させる
- 未使用の `recheckPermissionAndOpenSettingsIfNeeded()` は削除

---

## 1. 設計方針（責務配置）

### 1.1 再起動ロジックの配置先

**結論**: `TypeToTalkCoordinator` に `restartApp()` を実装する。

**Why**:
- `recorder.isRecording` と `isProcessing` を同一スコープで参照できる（Coordinator は両マネージャを保持）
- AccessibilityManager は権限管理が責務であり、アプリライフサイクル制御は責務外
- 独立 Helper を作るほどの汎用性はない（呼び出し箇所は SettingsView 1 箇所のみ）

### 1.2 警告ダイアログの配置先

**結論**: `SettingsView` 内に `confirmationDialog` を配置。

**Why**:
- ダイアログは UI 層の責務
- Coordinator 側に State を持たせると ObservableObject の `@Published` 追加が必要になり、責務が肥大化
- SettingsView で `@State private var showRestartConfirmation = false` を持つのが最小

### 1.3 ボタン押下フロー

```
[Button "アプリを再起動" 押下]
        │
        ├─ recorder.isRecording || isProcessing → confirmationDialog 表示
        │       │
        │       ├─ "再起動" → coordinator.restartApp()
        │       └─ "キャンセル" → 何もしない
        │
        └─ それ以外 → coordinator.restartApp() を即実行
```

---

## 2. 実装タスク（1 サイクルで完了）

### Task 1: 「アプリを再起動」機能実装

**対象ファイル**:
1. `Sources/TypeToTalk/App/TypeToTalkApp.swift`
   - `TypeToTalkCoordinator` に `restartApp()` メソッド追加（NSWorkspace + NSApp.terminate パターン）
2. `Sources/TypeToTalk/Views/SettingsView.swift`
   - L282-284 のボタンを「アプリを再起動」に変更
   - 周辺の説明ラベル（「権限を再チェックする」等）を整合
   - `@State private var showRestartConfirmation = false` 追加
   - `.confirmationDialog` モディファイア追加（録音中/処理中の警告）
   - 押下ハンドラで `recorder.isRecording || isProcessing` を判定
3. `Sources/TypeToTalk/Managers/AccessibilityManager.swift`
   - 未使用の `recheckPermissionAndOpenSettingsIfNeeded()` を削除（L29-34 周辺）

**実装詳細**:

#### 2.1 TypeToTalkCoordinator.restartApp()

```swift
/// アプリを再起動する。新しいプロセスを openApplication で起動してから自身を terminate する。
/// 主用途: アクセシビリティ権限の AXIsProcessTrusted キャッシュを破棄するため。
func restartApp() {
    let appURL = Bundle.main.bundleURL
    let config = NSWorkspace.OpenConfiguration()
    config.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(
        at: appURL,
        configuration: config,
        completionHandler: { _, error in
            DispatchQueue.main.async {
                if error == nil {
                    NSApp.terminate(nil)
                }
                // error 時は terminate しない（ユーザーが手動でリトライ可能）
            }
        }
    )
}
```

**注意点**:
- `createsNewApplicationInstance = true` を必ず設定（既に起動中の自分を再フォーカスして終わらないように）
- `NSApp.terminate` は MainActor 必須なので completionHandler 内で `DispatchQueue.main.async`
- import が必要: `AppKit` (TypeToTalkApp.swift で既に import 済みの想定。investigation で要確認 → 既に NSApp 使用箇所があれば import 済み)

#### 2.2 SettingsView 変更

**ボタン置換**（L282-284 周辺）:
```swift
// 旧
Button("権限を再チェック") {
    accessibility.refreshPermissionStatus()
}

// 新
Button("アプリを再起動") {
    if coordinator.recorder.isRecording || coordinator.isProcessing {
        showRestartConfirmation = true
    } else {
        coordinator.restartApp()
    }
}
.confirmationDialog(
    "録音中または処理中です。再起動しますか？",
    isPresented: $showRestartConfirmation,
    titleVisibility: .visible
) {
    Button("再起動", role: .destructive) {
        coordinator.restartApp()
    }
    Button("キャンセル", role: .cancel) {}
} message: {
    Text("進行中の録音・処理は失われます。")
}
```

**周辺ラベル整合**:
- 「権限を再チェックする」「再チェック」等の文言が説明テキスト・ヘルプ文にある場合は「権限を再認識させるためにはアプリを再起動してください」等へ変更
- 実装時に Grep で `権限を再チェック` `再チェック` を周辺確認すること

**State 追加**:
```swift
@State private var showRestartConfirmation = false
```

**Coordinator 参照**:
- 既存の `accessibility: AccessibilityManager` だけでなく、`coordinator: TypeToTalkCoordinator` も参照可能か確認
- もし SettingsView が `coordinator` を直接持っていない場合は、`recorder` と `isProcessing` を個別に渡す or coordinator 全体を渡すかを実装時判断
- **小人ちゃんへの指示**: 既存 SettingsView の init 引数を Read で確認してから判断する

#### 2.3 AccessibilityManager から不要メソッド削除

```swift
// 削除対象（investigation L29-34）
@discardableResult
func recheckPermissionAndOpenSettingsIfNeeded() -> Bool {
    refreshPermissionStatus()
    return hasPermission
}
```

`refreshPermissionStatus()` 自体は他箇所（init / insertText / scenePhase）で使用中なので **絶対に削除しない**。

---

## 3. 検証計画（Step 6 自己検証）

### 3.1 ビルド検証
```bash
swift build 2>&1 | tail -20
```
警告・エラーなしを確認。

### 3.2 実機動作シナリオ

**シナリオ A: 通常フロー（idle 状態）**
1. アプリ起動、Settings を開く
2. 「アプリを再起動」ボタン表示を目視確認
3. ボタン押下 → 即座に再起動
4. 新プロセスでメインウインドウが表示されること

**シナリオ B: 録音中の警告**
1. メインで録音開始 → Settings 開く
2. 「アプリを再起動」押下
3. confirmationDialog が表示されること
4. 「キャンセル」→ 何も起きない、録音継続
5. 再度押下 →「再起動」→ アプリ再起動

**シナリオ C: 処理中の警告**
1. 録音 → 文字起こし処理中に Settings 開く
2. 同様に dialog 表示・キャンセル/再起動を確認

**シナリオ D: 権限反映**
1. 権限 OFF 状態で起動
2. システム設定で権限 ON
3. アプリへ戻る → 「アプリを再起動」押下 → 再起動後に hasPermission = true（緑丸）になること

### 3.3 確認コマンド（再起動成否）
```bash
# 再起動前後で PID が変わることを確認
pgrep -f TypeToTalk
```

---

## 4. ロールバック計画

問題があれば、変更ファイル 3 つを git revert で戻す:
- `Sources/TypeToTalk/App/TypeToTalkApp.swift`
- `Sources/TypeToTalk/Views/SettingsView.swift`
- `Sources/TypeToTalk/Managers/AccessibilityManager.swift`

---

## 5. リスク・不確か事項

| 項目 | リスク | 対策 |
|------|-------|------|
| `coordinator.isProcessing` プロパティ存在確認 | プロパティ名違いの可能性 | 実装時 Grep で確認、必要なら recorder/transcriber 等の状態から判定 |
| SettingsView の coordinator アクセス | 直接保持していない可能性 | 実装時に init 引数を Read、必要に応じて引数追加 |
| `AppKit` import | TypeToTalkApp.swift で未 import の可能性 | 実装時冒頭の import 文を確認、なければ追加 |
| createsNewApplicationInstance | macOS 14 で確実に動くか | 標準 API、macOS 10.15+ 対応で問題なし |

これらは Step 5 実装時に小人ちゃんが確認・対応する。

---

## 6. スコープ外（明示）

- ビルドナンバー表示（別論点）
- 完了済みの権限関連 UI 改善（既に commit 済み）
- `refreshPermissionStatus()` 自体の削除（他箇所で使用中）
- scenePhase 監視の最適化（投資gation 8.1 で「リスク低」判定済み）
