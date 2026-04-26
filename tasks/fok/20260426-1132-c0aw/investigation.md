# Step 3 調査報告書: アクセシビリティ権限取得フローの完全自動化

**タスク**: アプリ起動時に hasPermission==false → 誘導アラート表示 → 「許可する」でシステム設定該当ページを openAccessibilitySettings で開く → 裏で AXIsProcessTrusted を 1 秒間隔 polling → true 検出で即 restartApp()（ワンクッション無し）  
**背景**: 現在、権限不足時は SettingsView にアラート表示されるが、自動化されていない。アプリ起動時に自動誘導する必要がある  
**調査実施日**: 2026-04-26  
**調査者**: フォルダからの小人ちゃん (very thorough)

---

## 1. 関連ファイル一覧

| ファイル | パス | 役割 |
|---------|------|------|
| **AccessibilityManager.swift** | `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/AccessibilityManager.swift` | 権限管理マネージャー。hasPermission, refreshPermissionStatus(), openAccessibilitySettings(), requestPermission() を定義 |
| **TypeToTalkApp.swift** | `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift` | アプリエントリポイント。TypeToTalkCoordinator (L12-438) と MenuBarLabel (L446-512) を管理。handleAppLaunch(), restartApp() を実装 |
| **SettingsView.swift** | `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Views/SettingsView.swift` | Settings 画面。L302-315 で「アプリを再起動」ボタンと confirmationDialog を実装 |
| **Package.swift** | `/Users/tamekuniz/GitHub/tamekuniz/TTT/Package.swift` | プロジェクト設定。L7 で macOS(.v14) 指定（macOS 14+）|
| **Info.plist** | `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Resources/Info.plist` | L21-22 で Privacy - Accessibility Usage Description を定義 |

---

## 2. 既存実装パターン

### 2.1 hasPermission @Published 定義

**AccessibilityManager.swift L13**:
```swift
@Published var hasPermission = false
```

- ObservableObject のプロパティ
- 初期値は false（未許可）
- refreshPermissionStatus() により更新される（同ファイル L20-22）

### 2.2 refreshPermissionStatus() / AXIsProcessTrusted 呼び出し

**AccessibilityManager.swift L20-22**:
```swift
func refreshPermissionStatus() {
    hasPermission = AXIsProcessTrusted()
}
```

- **問題**: AXIsProcessTrusted() はプロセス内でキャッシュされるため、再チェックでは新しい権限状態が反映されない
- AccessibilityManager.init() L17 で初期化時に一度呼ぶ
- insertText() L39 でテキスト入力前に毎回呼ぶ（短絡評価対策）
- TypeToTalkApp の scenePhase 監視時（L508）にフォアグラウンド復帰時に呼ぶ

### 2.3 requestPermission() / AXIsProcessTrustedWithOptions

**AccessibilityManager.swift L24-27**:
```swift
func requestPermission() {
    let options = [promptKey: true] as CFDictionary
    hasPermission = AXIsProcessTrustedWithOptions(options)
}
```

- L14 で `promptKey = "AXTrustedCheckOptionPrompt" as CFString` を定義
- AXIsProcessTrustedWithOptions(options) でプロンプト付き確認が可能
- 現在、SettingsView L304-305 で「システム設定を開く」ボタン押下時に呼ぶ

### 2.4 openAccessibilitySettings() の URL スキーム

**AccessibilityManager.swift L29-34**:
```swift
func openAccessibilitySettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
        return
    }
    NSWorkspace.shared.open(url)
}
```

- **URL スキーム**: `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`
- この URL でシステム設定アプリの「プライバシーとセキュリティ → アクセシビリティ」ページを直接開く
- NSWorkspace.shared.open() で実行

### 2.5 既存の showAccessibilityPermissionAlert の使い方

**TypeToTalkApp.swift L34**:
```swift
@Published var showAccessibilityPermissionAlert = false
```

- TypeToTalkCoordinator のプロパティ（@Published）
- L237 で insertText() の戻り値が .missingPermission の場合に true にセットされる
- **ただし、MenuBarLabel にアラート表示の bind がない**（L481-512 のbody に .alert(..) がない）
- つまり、showAccessibilityPermissionAlert が true でも、ユーザーには見えない状態

### 2.6 restartApp() の実装

**TypeToTalkApp.swift L364-380**:
```swift
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

- NSWorkspace.shared.openApplication() で新プロセスを起動
- createsNewApplicationInstance = true で別プロセス実行を強制
- 新プロセス起動成功後に NSApp.terminate(nil) で現在のプロセスを終了
- completionHandler 内の処理なので、起動非同期的

### 2.7 handleAppLaunch() の現状

**TypeToTalkApp.swift L167-173**:
```swift
func handleAppLaunch() {
    startupLoadTask?.cancel()
    startupLoadTask = Task { @MainActor [weak self] in
        await self?.synchronizeModelsForCurrentSettings()
        self?.currentStatus = .idle
    }
}
```

- MenuBarLabel の onAppear (L490-495) で呼ばれる
- 現在は synchronizeModelsForCurrentSettings() を呼んで AI モデル同期するだけ
- **権限チェックを含まない**

---

## 3. 影響範囲

### 3.1 起動フローとの競合

**現在のフロー** (MenuBarLabel の onAppear):
1. didLaunch 判定 (L491-495)
2. handleAppLaunch() 呼び出し (L493)
3. synchronizeModelsForCurrentSettings() 実行 (L170)
4. currentStatus = .idle セット (L171)

**新機能追加時の影響**:
- handleAppLaunch() に権限チェック + polling ロジック追加が必要
- polling 中に UI が frozen しないよう非同期タスク化が必須
- currentStatus = .idle のセット時点で権限判定が必要になる可能性あり（.error 状態になるかどうか）

### 3.2 scenePhase 監視との競合

**TypeToTalkApp.swift L505-510**:
```swift
.onChange(of: scenePhase) { _, newPhase in
    // フォアグラウンド復帰時に権限状態を最新化（システム設定で変更後の反映）
    if newPhase == .active {
        coordinator.accessibility.refreshPermissionStatus()
    }
}
```

- フォアグラウンド復帰時に refreshPermissionStatus() を呼ぶ
- **ただし AXIsProcessTrusted() キャッシュ問題により、実際には更新されない**
- 新しい polling メカニズムとの共存が必要（むしろ置き換えが望ましい）

### 3.3 メニューバー常駐型での NSAlert 表示挙動

**アプリ構成** (TypeToTalkApp.swift L566):
```swift
NSApplication.shared.setActivationPolicy(.accessory)
```

- メニューバー常駐型（Dock 非表示）で activationPolicy = .accessory
- **NSAlert は親ウインドウなしでは表示できない可能性あり**（不確か）
- SwiftUI の .alert() modifier ならば MenuBarExtra でも機能する可能性あり（不確か）
- テストが必須

### 3.4 showAccessibilityPermissionAlert フラグの現状

- TypeToTalkCoordinator L34 で @Published として定義
- L237 で true にセット
- **MenuBarLabel の body に .alert(..) がない** → 表示されていない
- 新機能では MenuBarLabel または MenuContentView に alert binding が必要

---

## 4. 過去の類似実装

### 4.1 権限関連の git log

```
1d0ac09 [フォK] feat: メニューバーUIを動的化 (Phase 2)
d08f241 [フォK] feat: 権限再チェックボタンをアプリ再起動ボタンに変更
35fe441 [フォK] feat: 権限動的チェック＋UI区別＋触覚/視覚フィードバック
```

### 4.2 restartApp() 実装の履歴

- **d08f241 コミット** (2026-04-25 19:42):
  - TypeToTalkCoordinator に restartApp() を追加（L364-380）
  - NSWorkspace.openApplication() + createsNewApplicationInstance で新プロセス起動
  - completionHandler 内で NSApp.terminate(nil) を呼ぶ
  - SettingsView L302-315 で「アプリを再起動」ボタンと confirmationDialog を実装

### 4.3 権限チェックの進化

- **35fe441 コミット** (2026-04-25 以前):
  - AccessibilityManager に refreshPermissionStatus() を追加
  - insertText() L39 でテキスト入力前に毎回呼び出し（短絡評価対策）
  - TypeToTalkApp の scenePhase 監視で フォアグラウンド復帰時に自動再チェック

---

## 5. 想定される副作用 / リスク

### 5.1 Polling のオーバーヘッド

**1 秒間隔で AXIsProcessTrusted() を呼び出す場合**:
- AXIsProcessTrusted() 自体は高速（システムコール 1 回）
- ただし、1 秒ごとのタイマーやタスク起動は CPU/メモリに微量の負荷
- **メニューバー常駐型で常に polling するのはリスク** → ユーザーが権限付与するまでの限定期間のみ実行すべき

### 5.2 AXIsProcessTrusted がプロセス内キャッシュで false のままの可能性

**現象**: 
- ユーザーがシステム設定で TypeToTalk を有効にしても、AXIsProcessTrusted() は false を返し続ける
- 理由：プロセス起動時に一度 false を取得したら、プロセス終了まで再評価されない（キャッシュ）

**回避策**:
- **プロセス再起動が唯一確実な解** → restartApp() の呼び出しで対応
- polling で true を検出した直後に restartApp() を呼ぶフローが正解

### 5.3 自動再起動中の録音中断

**シナリオ**: ユーザーが権限付与直後に restartApp() が実行される際、もし進行中の録音があれば中断される

**現在の対策**:
- SettingsView L310-315 で confirmationDialog を表示（録音中/処理中の警告）
- startup フロー（handleAppLaunch）では録音は発生しないので問題なし

**ただし**:
- 起動直後に polling で自動 restartApp() される場合、通常はアイドル状態なので問題なし
- しかし「アプリ起動後、ユーザーが即座に録音開始」した場合、restartApp() と競合する可能性あり
- → Polling 中に isRecording や isProcessing をチェックして、アクティブ中は restart を遅延/キャンセルすべき（不確か、仕様依存）

### 5.4 ユーザーが「キャンセル」したときの挙動

**シナリオ**: 誘導アラートで「許可する」の代わりに「キャンセル」を選んだ場合

**現在の設計**:
- アラート「許可する」 → openAccessibilitySettings() を呼ぶ
- アラート「キャンセル」 → 何もしない

**polling の可能性**:
- キャンセル後、polling は停止すべき（無限 polling するべきではない）
- タイムアウト機構が必要（例：30 秒待機後に polling 中止）

---

## 6. 制約条件

### 6.1 macOS バージョン

**Package.swift L7**:
```swift
platforms: [
    .macOS(.v14)
]
```

- **macOS 14+ のみ対応**
- AXIsProcessTrusted(), AXIsProcessTrustedWithOptions() は macOS 10.9 以降で使用可能（macOS 14 ならば問題なし）
- NSWorkspace.OpenConfiguration.createsNewApplicationInstance も macOS 10.15+ で使用可能

### 6.2 accessory アプリでの NSAlert 表示

**TypeToTalkApp.swift L566**:
```swift
NSApplication.shared.setActivationPolicy(.accessory)
```

- activationPolicy = .accessory （メニューバー常駐型、Dock 非表示）
- NSAlert は親ウインドウなしで表示できるか？ → **不確か**
  - 通常の NSAlert は親ウインドウの中央に表示される
  - accessory アプリは ウインドウレス なので、NSAlert 表示位置が不定になる可能性あり
  
- SwiftUI の .alert() modifier を使えば、MenuBarExtra 内でも表示できる可能性あり（不確か）
- 実機テストが必須

### 6.3 SwiftUI Alert vs NSAlert の選択

**現在の MenuContentView** (TypeToTalkApp.swift L519-558):
```swift
struct MenuContentView: View {
    @ObservedObject var coordinator: TypeToTalkCoordinator

    var body: some View {
        // A. 権限誘導項目（権限なし時のみ、メニュー先頭）
        if !coordinator.accessibility.hasPermission {
            Button("アクセシビリティ権限を設定...") {
                coordinator.accessibility.openAccessibilitySettings()
            }
            Divider()
        }
        ...
    }
}
```

- 現在はメニュー内にボタンを表示する形式
- 起動時の「誘導アラート」を新たに追加する場合：
  - **SwiftUI の .alert() + @State** を MenuBarLabel または MenuContentView に追加が合理的
  - NSAlert を使う場合は、accessory アプリでの表示挙動確認が必須

---

## 7. テスト戦略

### 7.1 権限剥奪 → アプリ起動 → アラート → 設定画面 → ON → 自動再起動 のフロー実機確認

**ステップ 1: 権限剥奪**
- システム設定 → プライバシーとセキュリティ → アクセシビリティ
- TypeToTalk のチェックを OFF

**ステップ 2: アプリ起動**
- TypeToTalk アプリを起動
- **期待動作**: 誘導アラート表示（「許可する」「キャンセル」ボタン）
- **検証**: showAccessibilityPermissionAlert が true で、MenuBarLabel に alert が表示される

**ステップ 3: 「許可する」 を押す**
- アラートのボタンをクリック
- **期待動作**: openAccessibilitySettings() でシステム設定が開く
- **期待動作**: 裏で AXIsProcessTrusted() を 1 秒間隔で polling 開始
- **検証**: 1 秒ごとに accessibilityManager.hasPermission の更新を試みる（logging で確認）

**ステップ 4: システム設定で TypeToTalk を有効**
- システム設定 → プライバシーとセキュリティ → アクセシビリティ
- TypeToTalk をチェック ON

**ステップ 5: polling で true 検出 → 自動再起動**
- 次の polling サイクルで AXIsProcessTrusted() が true を返す
- **期待動作**: 即座に restartApp() を呼び出し（ワンクッション無し）
- **検証**: アプリが自動再起動される（プロセスが新しくなる）

### 7.2 polling のタイムアウト

**シナリオ**: ユーザーが「キャンセル」を押した場合、またはシステム設定で ON にしない場合

**期待動作**: polling を 30 秒程度で中止
- タイムアウト後、statusMessage に「キャンセルされました」など表示

### 7.3 アクティブ中 restart 抑制（仕様による）

**シナリオ**: 起動後すぐに ユーザーが録音開始 → 権限 ON → polling で true 検出

**仕様**:
- 現在のコードは起動時に権限チェックするため、権限なしなら recording は開始できない（L272-275）
- ただし念のため：polling 実行中に isRecording = true に変わった場合、restart を遅延すべきか？
- → **不確か。仕様を確認してからテスト設計を決める**

### 7.4 MenuBarExtra での alert 表示確認

- 誘導アラート（「許可する」「キャンセル」）が MenuBarExtra のコンテキストで正常に表示されるか
- NSAlert と SwiftUI .alert() のどちらが使用可能か実機確認

---

## 追加調査: AXIsProcessTrustedWithOptions の詳細

### 不確かな点

- **AXIsProcessTrustedWithOptions(options) の挙動**:
  - `promptKey: true` を指定してプロンプト表示が可能かどうか、完全には実装例がない
  - 現在、SettingsView L304-305 で requestPermission() が呼ばれているが、プロンプト表示の成功確認がない
  - 実装者はこのプロンプト表示 + polling + 自動 restart の組み合わせが新しいアプローチ

- **NSNotificationCenter による権限変更通知**:
  - macOS accessibility フレームワークに `kAXNotificationClass` 系のシステム通知があるか不確か
  - Polling の代替手段として、KVO や NotificationCenter で権限変更を検知できるか不確か
  - → Apple のドキュメント確認が必要（UIAccessibility.h などを参照）

- **DispatchSourceTimer vs Task.sleep ループ**:
  - 1 秒間隔 polling の実装方法：
    - Timer (Foundation) ← 古典的，reliable
    - DispatchSourceTimer (Dispatch) ← より精密
    - Task.sleep(nanoseconds: 1_000_000_000) ループ ← async/await 現代的
  - 現在コード (TypeToTalkApp L160) では Task.sleep を使用しているため，同じ pattern 採用が合理的

---

## コード根拠まとめ（行番号付き）

| 項目 | ファイル | 行番号 | コード根拠 |
|-----|---------|--------|-----------|
| hasPermission 定義 | AccessibilityManager.swift | L13 | `@Published var hasPermission = false` |
| refreshPermissionStatus | AccessibilityManager.swift | L20-22 | `func refreshPermissionStatus() { hasPermission = AXIsProcessTrusted() }` |
| requestPermission | AccessibilityManager.swift | L24-27 | `func requestPermission() { let options = [promptKey: true] as CFDictionary; hasPermission = AXIsProcessTrustedWithOptions(options) }` |
| openAccessibilitySettings | AccessibilityManager.swift | L29-34 | `func openAccessibilitySettings() { ... "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" }` |
| showAccessibilityPermissionAlert | TypeToTalkApp.swift | L34 | `@Published var showAccessibilityPermissionAlert = false` |
| showAccessibilityPermissionAlert 設定 | TypeToTalkApp.swift | L237 | `showAccessibilityPermissionAlert = true` |
| restartApp | TypeToTalkApp.swift | L364-380 | `func restartApp() { ... NSWorkspace.shared.openApplication(..., createsNewApplicationInstance: true, ...) }` |
| handleAppLaunch | TypeToTalkApp.swift | L167-173 | `func handleAppLaunch() { ... await self?.synchronizeModelsForCurrentSettings(); self?.currentStatus = .idle }` |
| activationPolicy | TypeToTalkApp.swift | L566 | `NSApplication.shared.setActivationPolicy(.accessory)` |
| scenePhase 監視 | TypeToTalkApp.swift | L505-510 | `.onChange(of: scenePhase) { ... if newPhase == .active { coordinator.accessibility.refreshPermissionStatus() } }` |
| macOS version | Package.swift | L7 | `platforms: [ .macOS(.v14) ]` |
| accessibility description | Info.plist | L21-22 | `<key>Privacy - Accessibility Usage Description</key>` |

