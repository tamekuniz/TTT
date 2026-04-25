# TypeToTalk メニューバー常駐型（アクセサリアプリ）移行調査報告

**調査者**: マンゴーどす（調査小人）  
**調査日**: 2026-04-25  
**バージョン**: 0.1.0 (ビルド 20260425F)  
**対象環境**: macOS 14.0+, SwiftUI, Swift 6.0  

---

## 1. 関連ファイル一覧

### A. アプリケーション構造
- **TypeToTalkApp.swift** (`/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`)
  - `@main struct TypeToTalkApp: App` (行 543-589)
  - `class TypeToTalkCoordinator: ObservableObject` (行 182-541)
  - `struct TypeToTalkMainView: View` (行 11-180)

### B. UI / Settings
- **SettingsView.swift** (`/Users/TypeToTalk/Sources/TypeToTalk/Views/SettingsView.swift`)
  - Settings Scene の唯一の実装（行 1-432）

### C. マネージャー群
- **AccessibilityManager.swift** (行 1-89)
  - `insertText(_:)` 出力時のフォーカス要素取得と書き込み
- **WhisperManager.swift** (行 1-236)
  - Whisper モデルロード・文字起こし処理
- **BonsaiManager.swift** (行 1-286)
  - ローカル LLM による文字成形処理
- **AudioRecorder.swift** (行 1-100+)
  - 音声録音の開始・停止
- **SettingsManager.swift** (行 1-150+)
  - 設定の永続化

### D. プロジェクト設定
- **Package.swift** (行 1-41)
  - 依存パッケージ宣言 (WhisperKit, KeyboardShortcuts, mlx-swift-lm, swift-transformers)
- **project.yml** (行 1-65)
  - Xcode プロジェクト設定, macOS 14.0 デプロイメントターゲット
- **Info.plist** (`Sources/TypeToTalk/Resources/Info.plist`)
  - バンドル識別子: `com.tamekuniz.TypeToTalk`
  - マイク使用説明書、アクセシビリティ権限説明書を記述

### E. エンタイトルメント / 権限
- 調査時点で `.entitlements` ファイルは**見つからず**
  - XcodeGen で自動生成される可能性がある
  - 必要な権限: `com.apple.security.device.microphone`, `com.apple.security.device.camera` (マイク)

---

## 2. 既存実装パターン（実コード根拠）

### A. WindowGroup と Settings シーン定義

**TypeToTalkApp.swift, 行 548-589**
```swift
@main
struct TypeToTalkApp: App {
    @StateObject private var coordinator = TypeToTalkCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {                                              // 行 549
            TypeToTalkMainView(coordinator: coordinator)           // 行 550
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)  // 行 552 ← 通常アプリ化
                    NSApplication.shared.activate(ignoringOtherApps: true)  // 行 553 ← フォーカス奪取
                    if let window = NSApplication.shared.windows.first {
                        window.identifier = NSUserInterfaceItemIdentifier("RecorderWindow")  // 行 555
                        window.title = "TypeToTalk"                // 行 556
                    }
                    coordinator.handleAppLaunch()
                }
                .onChange(of: coordinator.settings.formatterProviderRawValue) { _, _ in
                    coordinator.bonsai.configureSelectedModel(coordinator.settings.resolvedBonsaiModelID)
                }
                // ... 他の onChange ハンドラ ...
        }
        .windowResizability(.contentSize)                          // 行 576
        
        Settings {                                                  // 行 578 ← Settings シーン
            SettingsView(
                settings: coordinator.settings,
                whisper: coordinator.whisper,
                bonsai: coordinator.bonsai,
                accessibility: coordinator.accessibility,
                coordinator: coordinator
            )
        }
    }
}
```

**結論**: 
- メインウインドウは `WindowGroup` で定義
- Settings シーンは通常の `Settings { ... }` で定義
- 現在、アプリ起動時に `setActivationPolicy(.regular)` と `activate(ignoringOtherApps: true)` で通常アプリ化＆フォーカス奪取

---

### B. setActivationPolicy(.regular) と NSApp.activate() の全箇所

**TypeToTalkApp.swift, 行 552-553 (onAppear 内)**
```swift
NSApplication.shared.setActivationPolicy(.regular)
NSApplication.shared.activate(ignoringOtherApps: true)
```

**TypeToTalkApp.swift, 行 454-455 (showRecorderWindow メソッド)**
```swift
func showRecorderWindow() {
    NSApplication.shared.setActivationPolicy(.regular)            // 行 454
    NSApplication.shared.activate(ignoringOtherApps: true)        // 行 455
    for window in NSApplication.shared.windows {
        if window.identifier?.rawValue == "RecorderWindow" {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
    NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
}
```

**grep 確認結果**: 
```
/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift:
  行 552: NSApplication.shared.setActivationPolicy(.regular)
  行 553: NSApplication.shared.activate(ignoringOtherApps: true)
  行 454: NSApplication.shared.setActivationPolicy(.regular)
  行 455: NSApplication.shared.activate(ignoringOtherApps: true)
```

**結論**: 2箇所、両方とも `showRecorderWindow()` 経由またはウインドウ表示に絡む。

---

### C. showRecorderWindow() の現状

**TypeToTalkApp.swift, 行 453-463**
```swift
func showRecorderWindow() {
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.activate(ignoringOtherApps: true)
    for window in NSApplication.shared.windows {
        if window.identifier?.rawValue == "RecorderWindow" {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
    NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
}
```

**呼び出し元**: 
- **行 367** (`handleTriggerShortcutDown` 内): toggle モード、録音中でない時に呼び出し
- **行 372** (`handleTriggerShortcutDown` 内): pushToTalk モード、録音中でない時に呼び出し

```swift
// 行 360-376
private func handleTriggerShortcutDown() async {
    guard !isTriggerShortcutPressed else { return }
    isTriggerShortcutPressed = true
    recordTriggerFeedback(source: "グローバル")

    switch settings.shortcutTriggerMode {
    case .disabled:
        break
    case .toggle:
        if !recorder.isRecording {
            showRecorderWindow()                    // 行 367
        }
        await toggleRecording()
    case .pushToTalk:
        if !recorder.isRecording && !isProcessing {
            showRecorderWindow()                    // 行 372
            await toggleRecording()
        }
    }
}
```

**結論**: ショートカット押下時にウインドウを前面化して、ユーザーに UI を見せている。accessory 化では**削除必須**。

---

### D. handleAppLaunch() の現状

**TypeToTalkApp.swift, 行 273-278**
```swift
func handleAppLaunch() {
    startupLoadTask?.cancel()
    startupLoadTask = Task { @MainActor [weak self] in
        await self?.synchronizeModelsForCurrentSettings()
    }
}
```

**呼び出し元**:
- **行 558** (TypeToTalkApp の onAppear 内): アプリ起動時

**役割**: モデルの自動同期（Whisper / Bonsai）

**結論**: accessory 化後も継続必要。メインウインドウ表示とは独立した処理。

---

### E. 出力フロー（テキスト書き込み）

**TypeToTalkApp.swift, 行 280-353 (toggleRecording メソッド)**

**フロー概要**:
1. **行 281-285**: 録音停止、isProcessing = true に設定
2. **行 300-303**: Whisper で音声を文字起こし
3. **行 311-315**: 辞書による「事前置換」
4. **行 318-320**: AI による文字成形
5. **行 324-327**: 辞書による「事後置換」
6. **行 329-341**: **AccessibilityManager.insertText(finalText) で出力**

```swift
// 行 329-341
statusMessage = "テキスト入力中..."
switch accessibility.insertText(finalText) {
case .success:
    statusMessage = "完了"
    performHapticFeedback(.alignment)
case .missingPermission:
    statusMessage = "アクセシビリティ権限が必要です（テキスト入力に必要）"
    showAccessibilityPermissionAlert = true
case .noFocusedElement:
    statusMessage = "入力先が見つかりません"
case .unsupportedTarget:
    statusMessage = "この入力欄には書き込めません"
}
isProcessing = false
```

---

### F. AccessibilityManager.insertText() のフォーカス取得タイミング

**AccessibilityManager.swift, 行 36-61**
```swift
func insertText(_ text: String) -> InsertResult {
    guard !text.isEmpty else { return .success }
    refreshPermissionStatus()
    guard hasPermission else {
        return .missingPermission
    }
    
    let systemWideElement = AXUIElementCreateSystemWide()
    var focusedElement: AnyObject?
    let result = AXUIElementCopyAttributeValue(
        systemWideElement, 
        kAXFocusedUIElementAttribute as CFString,        // ← ここでフォーカス要素を「取得時点で」取得
        &focusedElement
    )
    
    guard result == .success, let element = focusedElement as! AXUIElement? else {
        return .noFocusedElement
    }

    if AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef) == .success {
        return .success
    }

    if typeTextUsingEvents(text) {
        return .success
    }

    return .unsupportedTarget
}
```

**重要な発見**: 
- **フォーカス要素取得は `insertText()` 呼び出し時点** (Whisper 完了後の「テキスト入力中」タイミング)
- showRecorderWindow() で `.regular` に変更 → ウインドウ前面化 → 別アプリへのフォーカスが失われる可能性
- ただし、現実には **ショートカット押下時に相手アプリへ戻らないケースが多い** ため、accessory 化で `activate()` を除去すれば、フォーカスが別アプリに留まる

**結論**: accessory 化＋activate 除去で、出力先の入力欄フォーカスが維持される可能性が高い。

---

## 3. 影響範囲（accessory 化で消える機能、移行が必要な機能）

### A. 消える機能

| 機能 | 現状 | accessory 化後 | リスク |
|------|------|----------------|--------|
| **Dock アイコン表示** | `setActivationPolicy(.regular)` で表示 | **消失** | 低い（仕様） |
| **メインウインドウ** | 常時表示可能 | **廃止 or Settings 経由** | 中（UI アクセス経路が限定） |
| **マイクボタンUI** | メインウインドウに大きく配置 | **廃止予定** | 中（代替手段が必要） |
| **フォーカス奪取** | `activate(ignoringOtherApps: true)` | **完全除去** | 低（フォーカス維持が目的） |

### B. 移行が必要な機能

| 機能 | 現状実装 | 移行先 | 難易度 |
|------|---------|--------|--------|
| **Settings UI 表示** | Settings シーン（ウインドウ化） | MenuBarExtra コンテキストメニューか Settings リンク | 低 |
| **レコーディング開始** | ショートカット OR マイクボタン OR 右Option | ショートカット OR 右Option のみ | 中（UI ボタン廃止） |
| **ステータス表示** | メインウインドウ内のテキスト表示 | **NSStatusItem アイコンの状態表現** | 中 |
| **アクセシビリティ権限申請** | Settings 画面内の「システム設定を開く」ボタン | **Menu bar アイコンのコンテキストメニューに移動** | 低 |

### C. 出力フロー への影響

**accessory 化 + activate() 除去 後の出力シーケンス**:
1. ユーザーが別アプリの入力欄にフォーカス
2. ショートカット押下 → TypeToTalk 録音開始（メニューバーアイコンが更新）
3. ショートカット停止 → Whisper → AI 成形 → **`insertText()` で「現在のフォーカス要素」に書き込み**
4. ユーザーがその時点でフォーカスを変えていなければ **元の入力欄に書き込まれる**

**リスク**: ユーザーが「Whisper 完了まで」の間に別アプリに切り替えた場合、その切り替え先に書き込まれる可能性。
- **現在の activate()** は「ウインドウが前面に出る」ことで相手アプリへの切り替えを阻害していた側面がある
- **accessory 化では、ユーザーの自由度が増す** (良い面もある)

---

## 4. 過去の類似実装（git log）

**調査実施**: `git log --all --format="%h %s"` で最新 50 件を確認

```
952921f [フォK] chore: トップ画面のショートカット説明 Text を削除
dc3459a [フォK] fix: Bonsai 自動ロード - HubApi のパス階層に合わせて修正
a578b32 [フォK] fix: Bonsai 状態伝播＋自動ロード健全化＋ビルド20260425D
...
4b03313 [フォK] feat: TypeToTalk リファクタ完了＋整形AI整合性とウインドウトグル追加
cb281cf Refactor: Modularize project structure
```

**「MenuBar」「accessory」「StatusItem」関連の変更**: **見つかりませんでした**
- 現在のコードベースは、アクセサリアプリ実装ゼロベース
- メニューバー機能に関する過去試行や知見なし

**結論**: 純粋な新規実装領域。参考資料なし。

---

## 5. 想定される副作用 / リスク

### A. Settings シーン が accessory アプリで開けるか？

**仕様**: macOS 14+ で `Settings { ... }` は SwiftUI 標準
- `setActivationPolicy(.accessory)` でも Settings シーンは**開くことができる**（実装例あり）
- ただし、ウインドウモーダルが変わる可能性あり

**テスト必須**: 
- Settings ウインドウが正常に前面化するか
- 閉じたあと メニューバーアイコンに戻るか
- 複数回オープン・クローズで安定するか

**リスク度**: 低～中（仕様内だが挙動確認が必要）

### B. KeyboardShortcuts ライブラリ が accessory アプリで動作するか？

**実装確認**:
- **TypeToTalkApp.swift, 行 7-9**
  ```swift
  extension KeyboardShortcuts.Name {
      static let triggerRecording = Self("triggerRecording")
  }
  ```
- **行 215-225**
  ```swift
  KeyboardShortcuts.onKeyDown(for: .triggerRecording) { [weak self] in
      Task { @MainActor in
          await self?.handleTriggerShortcutDown()
      }
  }

  KeyboardShortcuts.onKeyUp(for: .triggerRecording) { [weak self] in
      Task { @MainActor in
          await self?.handleTriggerShortcutUp()
      }
  }
  ```
- **SettingsView.swift, 行 236**
  ```swift
  KeyboardShortcuts.Recorder(for: .triggerRecording)
  ```

**動作環境**: KeyboardShortcuts は純粋な AppKit + Foundation API 利用のため、accessory アプリでも**動作する可能性が高い**

**ただし不確か**: 
- グローバルホットキー登録（`onKeyDown` / `onKeyUp`）が accessory アプリ登録でも機能するか、公式テストなし
- Sindresorhus's KeyboardShortcuts は活発に保守されているため、確認推奨

**リスク度**: 中（ほぼ大丈夫だが、実機確認必須）

### C. 出力先フォーカス維持は activate() 除去だけで足りるか？

**分析**:
- `AccessibilityManager.insertText()` は **Whisper 完了時に フォーカス要素を取得** (行 44-49)
- 取得時点でフォーカスが別アプリの入力欄にあれば、**AXUIElement は有効**なまま書き込まれる
- `activate()` を除去しても、別アプリへのフォーカスが失われない限り動作する

**問題シナリオ**:
```
1. ユーザーが Safari 検索欄にフォーカス
2. ショートカット押下 → 現在の activate() でウインドウ前面化
3. ウインドウが前面化する間に、Safari フォーカスが失われる可能性
4. Whisper 完了時に insertText() が「どこに書き込むか」が不定

vs

accessory 化後:
1. ユーザーが Safari 検索欄にフォーカス
2. ショートカット押下 → メニューバーアイコン更新のみ、Safari フォーカス維持
3. Whisper 完了時に insertText() が「Safari 検索欄」に確実に書き込まれる
```

**結論**: accessory 化 + activate() 除去 で、逆に**フォーカス維持が向上する可能性**

**リスク度**: 低～無視できる（むしろ改善）

### D. 録音停止時の非同期チェーン中、ユーザーが別アプリに切り替えたら？

**フロー**:
1. 行 282-285: 停止 + `isProcessing = true`
2. 行 300-303: Whisper (数秒～数十秒)
3. 行 318-320: AI 成形 (数秒)
4. 行 330-341: `insertText()` で書き込み

**タイムラグ** = Whisper + AI 成形時間（**ユーザーが別アプリへ切り替える余裕あり**）

**挙動**:
- `insertText()` は「呼び出し時点の」フォーカス要素に書き込む
- ユーザーが Safari → News → Mail と切り替えた場合、**最終的なフォーカス先（Mail）に書き込まれる**

**これは accessory 化の本来の目的に合致** (バックグラウンド処理、ユーザーの自由な操作)

**リスク度**: 低（機能として正常）

---

## 6. 制約条件

### A. macOS 14+ SwiftUI 規約

**確認**:
- **Package.swift, 行 6**: `platforms: [.macOS(.v14)]`
- **project.yml, 行 4**: `deploymentTarget: macOS: "14.0"`

**利用可能な API**:
- **MenuBarExtra** (macOS 13+): SwiftUI 標準メニューバーコンポーネント ✅
- **Settings** シーン (macOS 12+) ✅
- **setActivationPolicy(.accessory)** (AppKit 古くから): ✅

**結論**: macOS 14 デプロイでは制約なし

### B. NSStatusItem と MenuBarExtra の比較

| 要素 | MenuBarExtra (SwiftUI) | NSStatusItem (AppKit) |
|------|------------------------|-----------------------|
| **macOS 最小バージョン** | 13 | ほぼ全バージョン |
| **実装言語** | Swift / SwiftUI | AppKit |
| **状態管理** | `@ObservedObject` / `@State` で自然 | KVO / Notification 必要 |
| **アイコン描画** | SwiftUI View (制限あり) | NSImage カスタム描画 (自由度高) |
| **コンテキストメニュー** | `@Environment(\.openSettings)` で Settings リンク可 | 手動実装 |

**TTT のニーズ**:
- 4 種類のステータス表現: idle / 録音中 / 処理中 / エラー
- Settings へのリンク
- 純粋 SwiftUI 統合

**推奨**: **MenuBarExtra 採用** (macOS 14 対象なら充分、SwiftUI 統合が自然)

### C. accessory アプリでの Settings シーン挙動

**仕様**: accessory アプリでも Settings シーンは開く
- ウインドウの `canBecomeKey` が true のため、フォーカス可能
- メニューバーアイコンからのリンク（`EnvironmentKey` 経由）で自然に開く

**注意**:
- Settings ウインドウを閉じたあと、メニューバーアイコンに「戻る」ウインドウがない
  - 通常アプリなら「メインウインドウに戻る」が自然だが、accessory では不要
  - ユーザーは Settings を閉じて、別アプリで作業を続ける

**実装注意**:
- Settings を `WindowGroup` ではなく `Settings { ... }` で定義したまま ✅
- Menu bar アイコンから `@Environment(\.openSettings)` で呼び出し ✅

**リスク度**: 低

### D. アクセシビリティ権限の引き継ぎ

**問題**: accessory アプリでも `AXIsProcessTrusted()` は呼べるか？

**答え**: **はい、呼べる**
- AppKit の AX\* 関数は、アクティベーションポリシーに依存しない
- アプリが実行されていて `AXIsProcessTrusted()` を呼べば、権限をチェックできる

**ただし不確か**: 
- accessory アプリが「システム設定で信頼できるアプリ」として登録されるか
- バンドル識別子（`com.tamekuniz.TypeToTalk`）が同一なら、権限は引き継がれると予想

**テスト必須**: 
- accessory 化後、Settings で「アクセシビリティ権限が未許可」と表示されるか
- もし未許可表示が出たら、ユーザーが Settings で再度有効化

**リスク度**: 中（権限実装は複雑だが、見直しで解決）

---

## 7. テスト戦略（実機確認シナリオ）

### シナリオ 1: メニューバーアイコン表示と状態表現

**準備**: accessory 化後のビルド版を実機で実行

**テスト項目**:
- [ ] メニューバー右側に TypeToTalk アイコン表示
- [ ] **アイコンが 4 種類の状態を表現**:
  - [ ] Idle: グレー（デフォルト）
  - [ ] Recording: 青（録音中）
  - [ ] Processing: 黄色～オレンジ（処理中）
  - [ ] Error: 赤（エラー）
- [ ] マウスホバーで説明テキスト表示（tooltip）
- [ ] クリックで Settings ウインドウ開く（または コンテキストメニュー表示）

**判定基準**: 全てのアイコン状態遷移が正常に反映されること

---

### シナリオ 2: 別アプリの入力欄への入力フロー（コアテスト）

**準備**:
1. Safari を起動、Google 検索欄にフォーカス
2. TypeToTalk ビルド版で メニューバーアイコン確認
3. Whisper / Bonsai モデルがローカル存在確認（Settings から確認可）

**テスト手順**:
1. Safari 検索欄にフォーカス
2. ショートカット（例: Cmd+Shift+R）を押す
3. **メニューバーアイコンが「Recording」に変化**
4. マイクに向かって 5 秒ほど話す
5. ショートカット停止
6. **メニューバーアイコンが「Processing」に変化**
7. 数秒待つ
8. **Safari 検索欄にテキストが入力される**
9. **メニューバーアイコンが「Idle」に戻る**

**判定基準**: 
- [ ] Safari フォーカスが失われない（メニューバーアイコンはアクティブにならない）
- [ ] テキスト入力が正確に実行
- [ ] ステータス遷移がメニューバーに反映

**重要**: 「ショートカット押下時にウインドウが前面化しない」ことが成功条件

---

### シナリオ 3: Settings ウインドウの開閉

**テスト手順**:
1. メニューバーアイコンをクリック（または右クリック）
2. **Settings ウインドウが開く**
3. 各タブ（「一般」「スマート辞書」）が表示・操作可能か
4. Settings ウインドウ内から:
   - [ ] 「ショートカット」設定変更可
   - [ ] 「Whisper モデル」選択・ロード可
   - [ ] 「Bonsai ローカルモデル」選択・ロード可
   - [ ] 「アクセシビリティ権限」ステータス表示＆「システム設定を開く」動作
5. Settings ウインドウを閉じる
6. **メニューバーアイコンだけが残る**（メインウインドウなし）

**判定基準**: 
- [ ] Settings が正常に開く
- [ ] 権限確認と「システム設定を開く」が動作
- [ ] 設定変更がアプリに反映

---

### シナリオ 4: Dock にアイコンが出ないこと

**テスト手順**:
1. アプリ実行
2. Dock を確認
3. **TypeToTalk アイコンが Dock に出ていない**
4. Command+Tab で アプリスイッチャー起動
5. **TypeToTalk が表示されない** （もしくは表示されても Dock からアクセスできない）

**判定基準**: 
- [ ] Dock に表示なし
- [ ] Command+Tab スイッチャーに表示なし（Accessory ポリシー効果）

---

### シナリオ 5: 右 Option キーによる録音制御

**テスト手順**:
1. Safari 検索欄にフォーカス
2. **右 Option キーを長押し（3 秒）**
3. メニューバーアイコンが「Recording」に
4. マイクで話す
5. **右 Option キーを離す**
6. メニューバーアイコンが「Processing」→「Idle」に遷移
7. Safari 検索欄にテキスト入力

**判定基準**: 
- [ ] 右 Option キー単体でも録音制御可能
- [ ] フォーカスが Safari から奪われない

---

### シナリオ 6: エラーハンドリング

**テスト手順**:
1. **Whisper モデルを未ロード状態に**（Settings で アンロード操作、または初回起動）
2. ショートカット押下 → 録音開始を試みる
3. **メニューバーアイコンが「Error」に変化** OR メニューバーに通知メッセージ
4. Settings で Whisper モデルをロード
5. もう一度ショートカット試行 → 正常動作確認

**判定基準**: 
- [ ] エラー状態がメニューバーで視認可能
- [ ] ユーザーが対応可能な情報が Settings に表示

---

### シナリオ 7: 複数アプリでの連続使用

**テスト手順**:
1. Safari 検索欄にフォーカス → ショートカット → 入力（確認）
2. Finder ウインドウの検索欄にフォーカス → ショートカット → 入力（確認）
3. Mail 本文 → ショートカット → 入力（確認）
4. **全てのアプリで正常に入力される**
5. Dock からアプリを確認 → TypeToTalk なし

**判定基準**: 
- [ ] 複数アプリ間で安定して動作
- [ ] Dock に出現なし

---

## 8. 実装メモ（リスク軽減のための手順案）

### フェーズ 1: MenuBarExtra + Coordinator 統合
1. `TypeToTalkCoordinator` に `@Published var currentStatus: AppStatus` を追加
   ```swift
   enum AppStatus {
       case idle
       case recording
       case processing
       case error(String)
   }
   ```
2. `TypeToTalkApp` の Scene を以下に変更：
   ```swift
   MenuBarExtra("", image: statusImage) {
       // コンテキストメニュー
       Button("設定") { 
           NSApp.sendAction(#selector(NSApplication.orderFrontPreferencesPanel(_:)), to: nil, from: nil)
       }
       Divider()
       Button("終了") { 
           NSApplication.shared.terminate(nil) 
       }
   }
   .menuBarExtraStyle(.window)
   
   Settings {
       SettingsView(...)
   }
   ```

### フェーズ 2: activate() / showRecorderWindow() 除去
1. `showRecorderWindow()` メソッド削除
2. `handleTriggerShortcutDown()` の `showRecorderWindow()` 呼び出し削除
3. `onAppear` の `setActivationPolicy(.regular)` と `activate()` 削除
4. 同じく `onAppear` で `setActivationPolicy(.accessory)` を追加

### フェーズ 3: Settings アクセス経路の変更
1. メニューバー右クリック → "設定" メニュー項目
2. または Settings シーンをメニューバーアイコンリンクで開く（`@Environment(\.openSettings)` 使用）

### フェーズ 4: 実機テスト
- シナリオ 1～7 を順次実行
- バグ修正・微調整

---

## 結論

### accessory 化への準備状況

| 項目 | 準備状況 | 作業量 |
|------|---------|--------|
| **現在の Windows Group 構造** | 廃止予定 | 中 |
| **Settings シーン** | そのまま利用可能 | 無 |
| **activate() / showRecorderWindow()** | 除去予定 | 低 |
| **MenuBarExtra アイコン実装** | ゼロから実装 | 中 |
| **KeyboardShortcuts 統合** | 既存のまま機能予定 | 無（確認のみ） |
| **出力フロー（insertText）** | accessory 化で改善 | 無（改善される） |
| **権限管理** | accessory で も動作予想 | 低（テスト確認） |

### 推奨進め方

1. **MenuBarExtra + Coordinator** を実装（ステータス表現ロジック）
2. **NSApp.activate() 除去** と `setActivationPolicy(.accessory)` 適用
3. **Settings メニューアクセス** を再構築
4. **実機テスト** (シナリオ 1～7 で検証)

### リスク評価

- **全体リスク度**: **低～中**
- **最大のリスク**: KeyboardShortcuts の accessory アプリ対応確認 → **実機テストで確定**
- **出力フロー**: むしろ **改善される可能性**（accessory 化でユーザーフォーカス維持）

---

**調査完了**: 2026-04-25 23:45 JST  
**マンゴーどす（調査小人）より**

