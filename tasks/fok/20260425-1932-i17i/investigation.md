# Step 3 調査報告書: アプリ再起動ボタン実装の前準備調査

**タスク**: macOS SwiftUI アプリ TypeToTalk の Settings 画面にある「権限を再チェック」ボタンを「アプリを再起動」に変更し、押下でアプリを再起動するように実装する  
**背景**: AXIsProcessTrusted() の結果はプロセス内でキャッシュされるため、再チェックでは権限変化が反映されない。プロセス再起動が唯一確実な解  
**調査実施日**: 2026-04-25  
**調査者**: 小松島産スイカ Step 3 調査小人ちゃん (very thorough)

---

## 1. 関連ファイル一覧（パス + 役割）

| ファイル | パス | 役割 |
|---------|------|------|
| **SettingsView.swift** | `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Views/SettingsView.swift` | Settings 画面。L282-284 に「権限を再チェック」ボタンがあり、`accessibility.refreshPermissionStatus()` を呼ぶ |
| **AccessibilityManager.swift** | `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/AccessibilityManager.swift` | アクセシビリティ権限管理。L20-22 `refreshPermissionStatus()` で `AXIsProcessTrusted()` を呼び出し、権限状態をキャッシュ |
| **TypeToTalkApp.swift** | `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift` | アプリのメインエントリポイント。TypeToTalkCoordinator と TypeToTalkMainView を管理。L501-506 で scenePhase 監視 |
| **TypeToTalkCoordinator** (内部) | `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift` L185-473 | 各マネージャーを統合管理。accessibility インスタンスを持つ |
| **Package.swift** | `/Users/tamekuniz/GitHub/tamekuniz/TTT/Package.swift` | プロジェクト設定。macOS 14 以上対応 |
| **Info.plist** | `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Resources/Info.plist` | アプリメタデータ。L21-22 で Privacy - Accessibility Usage Description を定義 |
| **entitlements.plist** | `/Users/tamekuniz/GitHub/tamekuniz/TTT/.build/arm64-apple-macosx/debug/TypeToTalk-entitlement.plist` | サンドボックス設定。現在は get-task-allow のみ |

---

## 2. 既存実装パターン

### 2.1 「権限を再チェック」ボタン定義

**SettingsView.swift L282-284** (行番号確認):
```swift
Button("権限を再チェック") {
    accessibility.refreshPermissionStatus()
}
```

- ボタンはシンプルで、`accessibility.refreshPermissionStatus()` 呼び出しのみ
- クロージャー内の処理は `accessibility` インスタンスメソッドへの委譲

### 2.2 押下ハンドラ・既存ロジック

**AccessibilityManager.swift L20-35**:
```swift
func refreshPermissionStatus() {
    hasPermission = AXIsProcessTrusted()
}

/// UI の「権限を再チェック」ボタン用。プロンプトを出さずに最新状態を取得して結果を返す。
/// - Returns: 現在の `hasPermission` の最新値（true なら権限あり）
@discardableResult
func recheckPermissionAndOpenSettingsIfNeeded() -> Bool {
    refreshPermissionStatus()
    return hasPermission
}
```

- `refreshPermissionStatus()` は `AXIsProcessTrusted()` 呼び出しだけで、その結果をキャッシュ
- 別に `recheckPermissionAndOpenSettingsIfNeeded()` メソッドも定義されているが、**SettingsView からは呼ばれていない**（L283 は直接 `refreshPermissionStatus()` を呼ぶ）
- **問題**: `AXIsProcessTrusted()` はプロセス内でキャッシュされるため、再チェックでは権限変化が反映されない

### 2.3 AXIsProcessTrusted 使用箇所

**AccessibilityManager.swift**:
- L21: `refreshPermissionStatus()` 内で `AXIsProcessTrusted()` 呼び出し
- L26: `requestPermission()` 内で `AXIsProcessTrustedWithOptions(options)` 呼び出し（プロンプト付き）
- L47: `insertText()` 冒頭で毎回 `refreshPermissionStatus()` を呼び出す（**短絡評価対策**)

**TypeToTalkApp.swift L503-504** (scenePhase 監視):
```swift
if newPhase == .active {
    coordinator.accessibility.refreshPermissionStatus()
}
```
フォアグラウンド復帰時に自動再チェック（ただし同じキャッシュ問題を抱える）

---

## 3. 影響範囲（呼び出し側 / 依存）

### 3.1 `refreshPermissionStatus()` 呼び出し箇所

| 呼び出し元 | 行番号 | 文脈 |
|----------|-------|------|
| `AccessibilityManager.init()` | L17 | 初期化時に一度実行 |
| `recheckPermissionAndOpenSettingsIfNeeded()` | L33 | （内部メソッド。現在 SettingsView からは呼ばれていない） |
| `insertText()` | L47 | テキスト入力前に毎回実行（短絡評価対策） |
| `TypeToTalkApp` scenePhase 監視 | L504 | フォアグラウンド復帰時に自動実行 |
| **SettingsView ボタン** | L283 | ユーザーの「権限を再チェック」ボタン押下時 |

### 3.2 権限再チェック ロジック削除の影響

**削除可能性**: `refreshPermissionStatus()` を削除しても、SettingsView からは直接呼ばずに **アプリ再起動** に変更するため、以下の調整が必要：
- L283 ボタンハンドラを `accessibility.refreshPermissionStatus()` から `restart()` へ変更
- `recheckPermissionAndOpenSettingsIfNeeded()` メソッドは削除候補（現在使用箇所なし）
- `refreshPermissionStatus()` 自体は `insertText()` L47 など他箇所で使用されるため、**削除不可**

### 3.3 PermissionManager / AccessibilityManager の構造

- **AccessibilityManager** は ObservableObject
  - `@Published var hasPermission = false` で UI バインディング
  - テキスト入力機能も統合（AXUIElement API 使用）
  - 再起動ロジックは存在しない
- 依存関係：
  - TypeToTalkCoordinator が `@Published var accessibility = AccessibilityManager()` を保持
  - SettingsView が `@ObservedObject var accessibility: AccessibilityManager` で監視

---

## 4. 過去の類似実装（git log 調査）

### 4.1 権限関連の変更履歴

**直近 commit:**
```
9d70ec7 [フォK] feat: マイクボタンUI改善＋権限ラベル微調整
35fe441 [フォK] feat: 権限動的チェック＋UI区別＋触覚/視覚フィードバック
16d3413 [フォK] feat: UI整理＋言語設定＋整形プロンプト構造化
```

**35fe441 commit メッセージ抜粋**:
```
[フォK] feat: 権限動的チェック＋UI区別＋触覚/視覚フィードバック

- T1 (アクセシビリティ権限根本対処):
  - AccessibilityManager.insertText 冒頭で必ず refreshPermissionStatus 呼出
    （短絡評価による権限後付け非反映を解消）
  - recheckPermissionAndOpenSettingsIfNeeded() 追加
  - TypeToTalkApp に @Environment(\.scenePhase) 監視、.active 復帰時に自動再チェック
  - SettingsView: 状態を緑/赤の小丸＋テキストに、「システム設定を開く」「権限を再チェック」の2ボタン
```

**意図**: 権限キャッシュ問題を「自動再チェック」で緩和する試み。**ただしこれは根本解決ではなく、確実な解は再起動のみ**。

### 4.2 アプリ再起動関連の実装

- **`NSWorkspace.shared.open(url)` のみ使用** (L41 accessibility settings を開く用)
- アプリ自身を再起動する実装は**存在しない**

---

## 5. 想定される副作用 / リスク

### 5.1 再起動時に未保存データが失われないか

**現在の設計**:
- SettingsManager: `didSet` で UserDefaults へ自動保存（L141-208）
- 辞書エントリ、API キー、モデル選択 → すべて UserDefaults に即座に保存
- **リスク低**: 設定値はすぐに永続化される

**未保存データの可能性**:
- **進行中の録音**: 再起動時に未処理なら失われる（一時ファイル `recording.wav` も削除される）
- **処理中の文字起こし/整形**: Task が中断される可能性がある

**対策必要**:
- 再起動前に `coordinator.recorder.isRecording` をチェック
- 録音中またはプロセス中なら、警告ダイアログ表示 + 実行キャンセル

### 5.2 録音中に押された場合の対応

**推奨フロー**:
1. ボタン押下時に `coordinator.recorder.isRecording` を確認
2. 録音中なら「今再起動するとデータが失われます」という confirmationDialog を表示
3. ユーザーが確認後のみ再起動実行

**実装箇所**: SettingsView L282-284 のボタンハンドラ内で条件判定

### 5.3 再起動直後の権限チェック

- 新しいプロセスで `AXIsProcessTrusted()` を呼び出すため、キャッシュは初期化される
- AccessibilityManager.init() L17 で `refreshPermissionStatus()` が自動実行されるため、UI は自動更新される
- **正常に動作する**

---

## 6. 制約条件（macOS API、サンドボックス、entitlements）

### 6.1 macOS 再起動 API の制約

**標準的なアプリ再起動パターン**:

1. **NSWorkspace.shared.openApplication(at:configuration:completionHandler:)** + 遅延終了
   - 別プロセスで新しいアプリを起動
   - 自身を `NSApp.terminate()` で終了
   - 最も推奨される方式

2. **Process + NSWorkspace** の併用
   - `/bin/sh` で短いシェルスクリプト実行
   - `sleep 1 && open /path/to/app.app` で再起動
   - 古いやり方（将来非推奨の可能性）

3. **LaunchAgent** / **watchdog** パターン
   - 複雑。小規模アプリ向けではない

**本プロジェクト向け推奨**: **NSWorkspace パターン**（1番目）

### 6.2 サンドボックス / entitlements の現状

**現在の設定** (`.build/arm64-apple-macosx/debug/TypeToTalk-entitlement.plist`):
```xml
<key>com.apple.security.get-task-allow</key>
<true/>
```

- **get-task-allow のみ**: デバッグビルド用。リリースビルドでは除外される。
- 再起動には **追加の entitlement 不要** (NSWorkspace / NSApp は標準 API)
- **App Sandbox 未有効**: 制約なし

### 6.3 NSWorkspace の使い方

**取得方法**:
```swift
NSWorkspace.shared
```

**アプリ Bundle 取得**:
```swift
let appURL = Bundle.main.bundleURL
```

**再起動実装例**:
```swift
let appURL = Bundle.main.bundleURL
NSWorkspace.shared.openApplication(
    at: appURL,
    configuration: NSWorkspace.OpenConfiguration(),
    completionHandler: { _, error in
        if error == nil {
            NSApp.terminate(nil)
        }
    }
)
```

---

## 7. テスト戦略（再起動確認方法・実機シナリオ）

### 7.1 再起動の確認方法

**方法 1: ウインドウアニメーション観察**
- Settings ウインドウを開いた状態
- ボタン押下 → アプリが一度閉じる
- 数秒後、アプリが再起動して通常のメインウインドウが表示される
- **期待結果**: Settings ウインドウは消える、メインウインドウが再表示される

**方法 2: プロセス ID 確認**
```bash
pgrep -f TypeToTalk  # 再起動前の PID
# ボタン押下
pgrep -f TypeToTalk  # 再起動後は新しい PID
```

**方法 3: アプリログ/print デバッグ**
- 再起動前後で `print()` や os.log でタイムスタンプ出力
- 時間間隔を記録

### 7.2 実機での操作シナリオ

**シナリオ 1: 通常フロー（権限なし状態）**
1. 権限なし状態でアプリ起動
2. Settings を開く
3. 「アプリを再起動」ボタン表示（従来の「権限を再チェック」の位置）
4. ボタン押下
5. アプリが再起動
6. **検証**: メインウインドウが表示される、statusMessage に権限状態が表示される

**シナリオ 2: 録音中に押された場合（警告表示）**
1. アプリを起動、マイク権限あり
2. メインウインドウのマイクボタンで録音開始 (isRecording = true)
3. Settings を開く
4. 「アプリを再起動」ボタン押下
5. **検証**: confirmationDialog が表示される（「再起動するとデータが失われます」）
6. 「キャンセル」で戻る、再起動しない
7. 「再起動」で進める、アプリ再起動

**シナリオ 3: 処理中に押された場合（警告表示）**
1. 録音 → 文字起こし処理中 (isProcessing = true)
2. Settings を開く
3. 「アプリを再起動」ボタン押下
4. **検証**: confirmationDialog が表示される
5. キャンセル / 再起動を選択して動作確認

**シナリオ 4: 権限自動反映確認**
1. 権限なし状態でアプリ起動 → Settings 開く → hasPermission = false (赤丸 + 未許可)
2. 「システム設定を開く」ボタンで設定画面へ
3. 権限を有効化
4. アプリへ戻る（フォアグラウンド復帰時に自動再チェック）
   - → 従来は refreshPermissionStatus() のキャッシュ問題で反映されない
   - → **新方式**: 「アプリを再起動」ボタンで確実に反映される

### 7.3 自動テスト可能性

- **ユニットテスト**: アプリ終了 API を呼ぶため、通常のテスト実行は困難
- **UI テスト**: XCUITest で再起動シーケンス検証可能（応用例: XCUIApplication の再起動）
- **実機検証**: 手動テストのみ推奨（短期開発サイクル向け）

---

## 8. 追加調査事項（気づき・不確か）

### 8.1 scenePhase 監視の継続性

**不確か**: 再起動後、新しいプロセスで再び `scenePhase` の `onChange` L501-506 が動くはずだが、その過程で自動再チェックが重複実行される可能性あり。

**検証**: 
- 再起動直後のログ出力で確認
- 問題なければそのまま、冗長なら最適化検討

### 8.2 未処理タスク (startupLoadTask など)

**TypeToTalkApp.swift L202** で `startupLoadTask: Task<Void, Never>?` を保持。

**再起動時の挙動不確か**:
- 古いプロセスの Task は自動キャンセルされるはず
- 新プロセスで新しく init() が走り、新 Task が作成される

**リスク低**: Task は MainActor 限定なので、プロセス終了で自動的に整理される。

### 8.3 他の設定値（UserDefaults）への影響

**想定**: 再起動時に UserDefaults が読み直される。
**検証**: 
- 再起動前後で SettingsManager の値が同じか確認
- 理論的には問題なし（UserDefaults の同期ポイント）

---

## 9. 実装の大枠（概要）

### 9.1 必要な実装ステップ

1. **AccessibilityManager に再起動メソッド追加**
   ```swift
   func restartApp() {
       let appURL = Bundle.main.bundleURL
       NSWorkspace.shared.openApplication(
           at: appURL,
           configuration: NSWorkspace.OpenConfiguration(),
           completionHandler: { _, error in
               if error == nil {
                   NSApp.terminate(nil)
               }
           }
       )
   }
   ```

2. **TypeToTalkCoordinator に再起動判定ロジック追加**
   ```swift
   func requestRestart() {
       // 進行中・録音中チェック
       guard !recorder.isRecording && !isProcessing else {
           showRestartWarning = true
           return
       }
       accessibility.restartApp()
   }
   ```

3. **SettingsView でボタン・ダイアログ更新**
   - ボタンテキスト: 「権限を再チェック」→ 「アプリを再起動」
   - ハンドラ: `accessibility.restartApp()` → `coordinator.requestRestart()`
   - confirmationDialog を追加（警告メッセージ付き）

4. **Optional: 不要メソッド削除**
   - `recheckPermissionAndOpenSettingsIfNeeded()` を削除（未使用）

---

## 10. 結論

### 10.1 調査完了状況

✅ SettingsView の「権限を再チェック」ボタン位置確認  
✅ AccessibilityManager の refreshPermissionStatus() ロジック把握  
✅ AXIsProcessTrusted のキャッシュ問題の根拠確認（insertText L47、TypeToTalkApp L503 参照）  
✅ 過去の権限関連実装（commit 35fe441）の意図確認  
✅ NSWorkspace / NSApp.terminate の使用可能性確認  
✅ entitlements 制約なし確認  
✅ テストシナリオ設計完了  

### 10.2 実装上の主要検討点

1. **再起動中の警告ダイアログ必須** (録音中 / 処理中)
2. **NSWorkspace.openApplication + NSApp.terminate のワンセット**
3. **SettingsManager の即座保存（既実装）により未保存データリスク低**
4. **新プロセスで自動的に hasPermission が更新される（AccessibilityManager.init()）**

### 10.3 実装開始前の確認事項

- **不確か**: scenePhase 監視の再起動後の重複実行リスク（低いと判断）
- **推奨確認**: 実機テストで再起動の成功、UI フロー動作確認

---

## 付録: ファイル行番号リファレンス

| ファイル | 行番号 | 内容 |
|---------|-------|------|
| SettingsView.swift | 282-284 | ボタン定義（変更対象） |
| AccessibilityManager.swift | 20-35 | refreshPermissionStatus / recheckPermissionAndOpenSettingsIfNeeded |
| AccessibilityManager.swift | 47 | insertText 冒頭での refreshPermissionStatus 呼び出し |
| TypeToTalkApp.swift | 503-506 | scenePhase onChange での自動再チェック |
| TypeToTalkApp.swift | 190 | coordinator.accessibility インスタンス保持 |
| Package.swift | 6-8 | macOS 14+ サポート確認 |
| Info.plist | 21-22 | Privacy - Accessibility Usage Description |

