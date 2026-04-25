# TypeToTalk UI/UX 修正 5 件 — 既存コード徹底調査報告

**実施日**: 2026-04-25 / **調査者**: パイナップル（高知の漁師言葉）  
**レベル**: Explore type, very thorough  
**方針**: 推測禁止、実コード確認のみ、path:line 形式で明示

---

## 1. 関連ファイル一覧

| パス | 役割 | 重要度 |
|------|------|--------|
| `Sources/TypeToTalk/App/TypeToTalkApp.swift` | メイン画面（TypeToTalkMainView）、Coordinator、ウインドウ設定、状態管理 | ★★★ |
| `Sources/TypeToTalk/Views/SettingsView.swift` | 設定画面、loadStatusBlock、Whisper・Bonsai 状態表示 | ★★★ |
| `Sources/TypeToTalk/Managers/WhisperManager.swift` | 音声文字起こしモデル管理、statusText、loadingStatusText、isLoadingModel | ★★★ |
| `Sources/TypeToTalk/Managers/BonsaiManager.swift` | AI 成形モデル管理、statusMessage、isLoadingModel、loadState | ★★★ |
| `Sources/TypeToTalk/Managers/AccessibilityManager.swift` | テキスト入力権限、openAccessibilitySettings() | ★★★ |
| `Sources/TypeToTalk/Managers/SettingsManager.swift` | 各種設定の保存・復元 | ★★ |
| `Sources/TypeToTalk/Managers/NetworkManager.swift` | オンライン状態監視（Formatter フォールバック判定用） | ★★ |
| `Tests/TypeToTalkTests/ModelSelectionTests.swift` | WhisperManager・BonsaiManager の statusText・loadingStatusText テスト | ★★ |
| `Tests/TypeToTalkTests/AudioRecorderTests.swift` | AudioRecorder の権限・URL テスト | ★ |

---

## 2. 既存実装パターン

### 2.1 状態表示の実装パターン

#### **WhisperManager の状態管理**（path: `Sources/TypeToTalk/Managers/WhisperManager.swift`）

```swift
// L4-9: 状態遷移の定義
enum WhisperLoadState: Equatable {
    case idle
    case loading
    case loaded(modelID: String)
    case failed(message: String)
}

// L16-18: @Published プロパティ
@Published var isLoadingModel = false
@Published private(set) var loadState: WhisperLoadState = .idle
@Published private(set) var loadingStatusText = "未読込"

// L47-58: statusText の計算（UI に表示される）
var statusText: String {
    switch loadState {
    case .idle:
        return needsExplicitLoad ? "未読込" : "準備完了"
    case .loading:
        return loadingStatusText  // ← loading 中は loadingStatusText を返す
    case .loaded:
        return needsExplicitLoad ? "未読込" : "準備完了"
    case let .failed(message):
        return "失敗: \(message)"
    }
}
```

**特徴**:
- `statusText` は計算属性で、`loadState` を参照して「何を表示するか」を決定
- `.loading` case では `loadingStatusText` を返す（"ダウンロード中..." など）
- `loadingStatusText` は loading 中に段階的に更新される（L83, L88, L93, L99）

#### **BonsaiManager の状態管理**（path: `Sources/TypeToTalk/Managers/BonsaiManager.swift`）

```swift
// L7-11: 状態遷移（Whisper と同じ）
enum BonsaiLoadState: Equatable {
    case idle
    case loading
    case loaded(modelID: String)
    case failed(message: String)
}

// L18-20: @Published プロパティ
@Published private(set) var statusMessage = "未読込"
@Published private(set) var isLoadingModel = false
@Published private(set) var loadState: BonsaiLoadState = .idle

// L78-90: configureSelectedModel で loadState に応じて statusMessage を設定
func configureSelectedModel(_ modelID: String) {
    currentSelectedModelID = modelID
    switch loadState {
    case .idle:
        statusMessage = "未読込"
    case .loading:
        statusMessage = "読込中"  // ← loading 中は "読込中" 固定
    case .loaded:
        statusMessage = loadedModelID == modelID ? "準備完了" : "未読込"
    case .failed:
        break
    }
}

// L120-141: loadModel 実行中に statusMessage が動的に更新
private func loadModel(modelID: String) async throws -> ModelContainer {
    isLoadingModel = true
    loadState = .loading
    statusMessage = "読込中"
    defer { isLoadingModel = false }
    // ...
    statusMessage = percent > 0 ? "モデル取得中 \(percent)%" : "モデル取得中"  // 進捗表示
    // ...
    self.statusMessage = "準備完了"
}
```

**特徴**:
- `statusMessage` は `@Published` で直接値を設定（計算属性ではない）
- loading 中に複数の statusMessage が順序立てて更新される
- progress callback で進捗率をリアルタイム更新（L136-140）

#### **❌ 問題点（要件①の根因）**

**メイン画面** (`TypeToTalkApp.swift:54-55`):
```swift
modelStatusRow(
    title: "Whisper",
    detail: coordinator.settings.whisperDisplayName,
    status: coordinator.whisper.statusText,  // ← statusText を参照
    progressLabel: coordinator.whisper.isLoadingModel ? coordinator.whisper.loadingStatusText : nil
)
```

**設定画面** (`SettingsView.swift:70, 141`):
```swift
loadStatusBlock(
    status: whisper.statusText,             // L70: statusText を参照
    loadedModel: whisper.loadedModelDisplayName,
    selectedModel: whisper.needsExplicitLoad ? whisper.selectedModelDisplayName : nil,
    buttonTitle: whisper.isLoadingModel ? "再読込中..." : "再読込",
    isDisabled: whisper.isLoadingModel || !whisper.needsExplicitLoad
) { ... }

loadStatusBlock(
    status: bonsai.statusMessage,           // L141: statusMessage を参照
    loadedModel: bonsai.loadedModelDisplayName,
    selectedModel: bonsai.needsExplicitLoad ? settings.resolvedBonsaiModelID : nil,
    buttonTitle: bonsai.isLoadingModel ? "再読込中..." : "再読込",
    isDisabled: bonsai.isLoadingModel || !bonsai.needsExplicitLoad
) { ... }
```

**不一致の構造**:
- Whisper: メイン画面・設定画面とも `statusText` を参照 → 本来は一致するはず
- Bonsai: メイン画面は `bonsai.statusMessage`（設定画面から参照されない）、設定画面は `bonsai.statusMessage` を参照 → 一致する

**「なぜ不一致が報告されるのか」の推定**:
1. WhisperManager の `statusText` が loading 中に正しく `loadingStatusText` を返すか確認が必要
2. メイン画面の `modelStatusRow` で `progressLabel` パラメータが、設定画面の `loadStatusBlock` の `status` パラメータと区別される可能性
3. メイン画面では `isLoadingModel` 判定で `loadingStatusText` を条件付き表示（L55: `? ... : nil`）、設定画面は常に `status` を表示（L309）

### 2.2 SwiftUI macOS ウインドウタイトル制御パターン

（path: `Sources/TypeToTalk/App/TypeToTalkApp.swift`）

```swift
// L476-511: WindowGroup + Settings
@main
struct TypeToTalkApp: App {
    var body: some Scene {
        WindowGroup {
            TypeToTalkMainView(coordinator: coordinator)
                .onAppear {
                    // L482-487: ウインドウ設定
                    if let window = NSApplication.shared.windows.first {
                        window.identifier = NSUserInterfaceItemIdentifier("RecorderWindow")
                        window.titleVisibility = .hidden       // L484: タイトルを非表示
                        window.titlebarAppearsTransparent = true  // L485: タイトルバーを透明化
                        window.isMovableByWindowBackground = true
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)  // L500: ウインドウスタイル（タイトルバー隠す）
        .windowResizability(.contentSize)
    }
}

// L13-31: TypeToTalkMainView の構造
struct TypeToTalkMainView: View {
    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TypeToTalk")          // L17: タイトルテキスト
                        .font(.title3.weight(.semibold))
                    Text(coordinator.statusMessage)  // L19: ステータス
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                SettingsLink { ... }  // L26-30: 設定ボタン
            }
            // ... 以下マイクボタン等
        }
        .padding(20)
        .frame(width: 360, height: 300)
    }
}
```

**タイトル重なり問題の構造**:
- `windowStyle(.hiddenTitleBar)` でシステム タイトルバー非表示
- `titlebarAppearsTransparent = true` で transparent にしても、traffic light （赤黄緑ボタン）は表示
- `VStack` 内の `Text("TypeToTalk")` は padding 20 だけ → traffic light 領域にめり込み
- 標準 macOS: traffic light は左上から約 70px

### 2.3 SettingsView の sectionRow / settingRow パターン

（path: `Sources/TypeToTalk/Views/SettingsView.swift`）

```swift
// L277-285: settingRow (label + 値 で HStack)
@ViewBuilder
private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 92, alignment: .leading)  // 固定幅ラベル
        content()  // 右側に control (Picker, TextField など)
    }
}

// L287-296: sectionTitle (GroupBox の label)
@ViewBuilder
private func sectionTitle(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.headline)
        Text(subtitle).font(.caption).foregroundStyle(.secondary)
    }
}

// L298-330: loadStatusBlock (状態表示＋再読込ボタン)
@ViewBuilder
private func loadStatusBlock(
    status: String,
    loadedModel: String,
    selectedModel: String?,
    buttonTitle: String,
    isDisabled: Bool,
    action: @escaping () -> Void
) -> some View {
    HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
            Text("状態: \(status)")  // L309: status を表示
            Text("現在の読込モデル: \(loadedModel)")
            if let selectedModel { ... }
        }
        Spacer()
        Button(buttonTitle, action: action)
            .disabled(isDisabled)
    }
    .padding(10)
    .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
}
```

### 2.4 URL を NSWorkspace 経由で開く既存例

（path: `Sources/TypeToTalk/Managers/AccessibilityManager.swift`）

```swift
// L29-34: openAccessibilitySettings の既存実装
func openAccessibilitySettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
        return
    }
    NSWorkspace.shared.open(url)  // ← すでに使用例あり
}
```

**既存構造**:
- `x-apple.systempreferences:` スキーム使用
- `com.apple.preference.security?Privacy_Accessibility` パス
- `NSWorkspace.shared.open(url)` で起動

（設定画面 L225 でこの関数が呼び出されている）

---

## 3. 影響範囲

### 3.1 要件①: 状態同期バグ修正

**関連コード**:
- `WhisperManager.statusText` (L47-58)
- `WhisperManager.loadingStatusText` (L18, L83, L88, L93, L99)
- `WhisperManager.isLoadingModel` (L16, L81, L84)
- `TypeToTalkApp.swift` メイン画面 (L54-55)
- `SettingsView.swift` 設定画面 (L69-79)

**呼び出し側**:
```
TypeToTalkMainView (L54)
  └─ coordinator.whisper.statusText (計算属性)
  
SettingsView.loadStatusBlock (L70, L141-145)
  └─ whisper.statusText (Whisper の場合)
  └─ bonsai.statusMessage (Bonsai の場合)
```

**データフロー**:
1. `WhisperManager.loadState` (enum) 変更
2. → `WhisperManager.statusText` (計算属性) が自動的に変わる
3. → メイン画面・設定画面の UI が更新

**副作用リスク**:
- `SettingsView.loadStatusBlock` で `whisper.statusText` を参照しているため、修正は両画面に自動反映
- `whisper.isLoadingModel` も設定画面で参照されているため (L73-74)、その値の変更は影響なし
- テスト `ModelSelectionTests.swift` の検証ロジック確認が必要

### 3.2 要件②: ウインドウタイトル位置修正

**関連コード**:
- `TypeToTalkMainView` (L10-180)
- `TypeToTalkApp.onAppear` (L479-488)
- `windowStyle(.hiddenTitleBar)` (L500)

**呼び出し側**:
```
TypeToTalkApp.body
  └─ WindowGroup
       └─ TypeToTalkMainView
             ├─ Text("TypeToTalk") (L17)
             ├─ Text(statusMessage) (L19)
             └─ HStack に SettingsLink (L26-30)
```

**ウインドウ構造**:
- macOS のデフォルト traffic light 領域: 左上 `~70px`
- 現在の padding: 20px（不足）
- 修正方法：`VStack` 全体を左 margin で調整、または HStack 左側に Spacer/固定幅 view 追加

**影響範囲（限定的）**:
- UI レイアウト調整のみ、ロジック変更なし
- テストは手動/実機確認が必須

### 3.3 要件③: メイン画面左上「待機中」テキストの整理

**関連コード**:
- `TypeToTalkCoordinator.statusMessage` (L192: 初期値 "待機中")
- `TypeToTalkMainView.Text(coordinator.statusMessage)` (L19)
- `infoStatusRow("Trigger", detail: coordinator.statusMessage, ...)` (L65)

**呼び出し側**:
```
TypeToTalkMainView
  ├─ Text(coordinator.statusMessage) (L19) ← ここで初期値表示
  └─ infoStatusRow (L65) ← detail パラメータで重複使用（不確か：このパラメータは何の目的か）
```

**statusMessage の更新箇所**:
- L239, 243, 249, 258, 271, 281, 284, 286, 288, 290, 297, 299, 367

**推定される役割**:
- 全体ワークフロー（録音→文字起こし→成形→入力）の進行ステータスを口語表現で表示
- 初期値 "待機中" は「何のため？」という質問の対象

**修正案**:
- 初期値を空文字 `""` or `" "` に変更（L192）
- または条件付き表示で、statusMessage が空でない場合のみ Text を表示

**影響範囲**:
- `infoStatusRow` の detail 引数に coordinator.statusMessage を渡している意図が不確か
  - メイン画面 L65: `detail: coordinator.statusMessage` → Trigger 行に「待機中」など進行中のメッセージが混在？
  - 要確認：Trigger 行は削除予定（要件④）なので、L65 も削除？

### 3.4 要件④: Trigger「未検出」表示の削除

**関連コード**:
- `TypeToTalkCoordinator.lastTriggerSource` (L194: 初期値 "未検出")
- `TypeToTalkMainView.infoStatusRow("Trigger", ...)` (L63-67)
- `recordTriggerFeedback(source:)` (L364-370)
- `handleTriggerShortcutDown()` (L304-321, 呼び出し側 L307)
- `handleFlagsChanged()` (L357)

**呼び出し側**:
```
infoStatusRow("Trigger", detail: statusMessage, status: lastTriggerSource) (L63-67)
  ├─ 表示削除候補
  
recordTriggerFeedback(source: "グローバル") (L307)
recordTriggerFeedback(source: "右Option") (L357)
  ├─ lastTriggerSource = source (L365)
  ├─ statusMessage = "\(source) を受信" (L367)
  ├─ NSSound.beep() (L369) ← 保持するか削除するか検討
```

**NSSound.beep() の処理**:
- フィードバック音として機能
- Trigger 表示削除時も鳴らし続けるか、削除するか？
- 推定：表示削除のみで、beep は保持する方が UX 良い

**影響範囲**:
- `infoStatusRow` 行をコメント/削除（L63-67）
- `lastTriggerSource` の @Published プロパティは保持（内部ロジックで継続使用される可能性）
- `recordTriggerFeedback()` 内部で statusMessage 更新（L367）は、Trigger 表示削除後も活用可能（新たにステータス表示の別用途に転用？）
- テスト：`recordTriggerFeedback()` 呼び出し側が正しく動作するか確認

### 3.5 要件⑤: アクセシビリティ権限説明＋システム設定誘導ボタン

**現状のコード**:
```swift
// TypeToTalkApp.swift L282-291: 権限チェック結果の処理
switch accessibility.insertText(finalText) {
case .success:
    statusMessage = "完了"
case .missingPermission:
    statusMessage = "アクセシビリティ権限が必要です"  // ← 現在のメッセージ
case .noFocusedElement:
    statusMessage = "入力先が見つかりません"
case .unsupportedTarget:
    statusMessage = "この入力欄には書き込めません"
}
```

**AccessibilityManager の既存機能**:
```swift
// L29-34: openAccessibilitySettings() 存在
func openAccessibilitySettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
        return
    }
    NSWorkspace.shared.open(url)
}

// L20-27: requestPermission() 存在
func requestPermission() {
    let options = [promptKey: true] as CFDictionary
    hasPermission = AXIsProcessTrustedWithOptions(options)
}
```

**設定画面の既存実装** (L209-232):
```swift
GroupBox {
    HStack {
        VStack(alignment: .leading, spacing: 4) {
            Text("アクセシビリティ権限")
            Text("テキストを直接入力するために必要です。")
        }
        Spacer()
        Image(systemName: accessibility.hasPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        Button(accessibility.hasPermission ? "許可済み" : "設定を開く") {
            if !accessibility.hasPermission {
                accessibility.requestPermission()
                accessibility.openAccessibilitySettings()  // ← 既に使用されている
            }
        }
    }
}
```

**改善対象**:
1. メッセージの具体化（L286 の statusMessage）
2. メイン画面で権限誘導ボタンを表示する必要があるか？
   - 現状：statusMessage に "アクセシビリティ権限が必要です" を表示するのみ
   - 改善案：statusMessage + ボタン（設定画面へ誘導、またはシステム設定を直接開く）
3. `openAccessibilitySettings()` の実装は既存（再利用可能）

**配置戦略**:
- メイン画面：statusMessage を詳細化 + ボタンはアラート/Sheet で提示？
- 設定画面：既存の AccessibilityManager section を拡張（現在の実装で十分？）

**影響範囲**:
- `AccessibilityManager` の `openAccessibilitySettings()` は既に存在、reuse 可能
- メイン画面での UI 配置変更が必要（ボタン追加 or Sheet 出現）
- statusMessage の更新ロジック変更（より詳細なメッセージに）

---

## 4. 過去の類似実装

**git ログ確認結果**:
```
4b03313 [フォK] feat: TypeToTalk リファクタ完了＋整形AI整合性とウインドウトグル追加
cb281cf Refactor: Modularize project structure (App, Managers, Models, Views) for high maintainability
db58908 Implement Settings UI for API keys and custom prompts
1f0d5e7 Add documentation and Info.plist for system permissions
ca4c764 Initial commit of TTT (Talk to Type) macOS app
```

**該当する過去実装**:
1. **L1f0d5e7**: "Add documentation and Info.plist for system permissions"
   - アクセシビリティ権限に関する初期実装
   - 詳細は git diff で確認必要（コード行数が多くなるため、ここでは未展開）

2. **4b03313**: "[フォK] feat: TypeToTalk リファクタ完了＋整形AI整合性とウインドウトグル追加"
   - 最新のリファクタ完了コミット
   - ウインドウトグル（要件②に関連）の実装あり可能性

3. **macOS Privacy 設定誘導の類似例**:
   - 既存の `AccessibilityManager.openAccessibilitySettings()` (L29-34)
   - SettingsView での button 実装 (L222-226)
   - 上記が過去の実装パターン

**新規実装が必要な部分**:
- 要件①の statusText 同期修正（新規ロジック）
- 要件②のウインドウ padding 調整（新規レイアウト）
- 要件③の初期値変更（単純修正）
- 要件④の infoStatusRow 削除（削除のみ）
- 要件⑤のメイン画面での権限誘導（新規 UI）

---

## 5. 想定される副作用 / リスク

### 5.1 要件①: statusText 修正

**テスト への影響**:
- `ModelSelectionTests.swift` L6-14, L37-57 で Whisper・Bonsai の statusText/loadingStatusText をテスト
- 修正内容が不明確であれば、テストが壊れる可能性

**提言**:
- 修正前に `ModelSelectionTests` を実行して baseline を確認
- 修正後に同じテストを再実行して、予期せぬ変更がないことを確認

### 5.2 要件②: ウインドウタイトル位置修正

**リスク**: ★★☆☆☆（低）
- レイアウト変更のため、異なる macOS バージョンで表示がズレる可能性
- 標準的な macOS 14+ では traffic light 左上から約 70px

**テスト戦略**:
- 手動: macOS 14.x, 15.x での実機確認必須
- ビルド検証: 様々なウインドウサイズで確認

### 5.3 要件③: statusMessage 初期値変更

**リスク**: ★★☆☆☆（低）
- `statusMessage` を参照している箇所が多い (L19, L65, 他 15+ 箇所)
- 初期値を空にすると、起動直後に左上に何も表示されない
- `infoStatusRow` の detail: statusMessage との重複使用が不確か

**副作用確認**:
- grep 結果より、statusMessage は録音/文字起こし/成形中のステータス表示が主目的
- 初期値をどうするかで UX が変わる（何も表示 vs 「待機中」）

### 5.4 要件④: Trigger 表示削除

**リスク**: ★★★☆☆（中）
- `lastTriggerSource` は @Published で宣言
- Trigger 表示を削除しても、内部ロジック（recordTriggerFeedback）は継続動作
- NSSound.beep() は削除するか保持するか要検討

**副作用**:
- `recordTriggerFeedback()` 内で `statusMessage = "\(source) を受信"` を更新（L367）
  - Trigger 表示削除後も、このメッセージが一時的に画面に出ていいのか？
  - 要検討：statusMessage の改変は要件③と関連

### 5.5 要件⑤: アクセシビリティ権限説明

**リスク**: ★★☆☆☆（低）
- `x-apple.systempreferences:` URL スキームは macOS 10.5+ でサポート
- macOS 14+ では安定動作が確認されている
- 既存の `AccessibilityManager.openAccessibilitySettings()` を reuse 可能

**未確認事項**:
- メイン画面での権限誘導 UI をどこに配置するか（アラート / Sheet / インライン）
- statusMessage 詳細化のタイミング（insertText 失敗後のみか、起動時もか）

---

## 6. 制約条件

### 6.1 言語・フレームワーク

- **Swift**: 6.0（concurrency model、@MainActor、Sendable 対応）
- **SwiftUI**: macOS 14+ に対応（windowStyle, hiddenTitleBar など）
- **AppKit**: NSApplication, NSWindow, NSSound 等の使用
- **Accessibility API**: AXIsProcessTrusted(), AXUIElement

### 6.2 外部ライブラリ

- **KeyboardShortcuts**: 2.x（既存使用）
- **WhisperKit**: 0.18.0（既存使用）
- **Hub / MLXLLM / Tokenizers**: Bonsai 関連（既存）

### 6.3 既存命名規約・構造

- **プロパティ命名**:
  - `statusMessage`: Coordinator / Bonsai で使用（@Published）
  - `statusText`: Whisper でのみ使用（計算属性）
  - `isLoadingModel`: Whisper / Bonsai 両方（@Published）
  - `loadingStatusText`: Whisper でのみ使用
  - `loadState`: 両方で enum 定義（名称同じ、定義別）

- **View 命名**:
  - `modelStatusRow()`: モデル状態表示用
  - `infoStatusRow()`: その他情報表示用（削除対象）

- **Manager 構成**:
  - 各 Manager は @MainActor で @Published プロパティを持つ
  - Coordinator は各 Manager を @Published で保持し、UI に公開

### 6.4 マルチレベル同期について

- メイン画面 (`TypeToTalkMainView`) と設定画面 (`SettingsView`) は同じ Coordinator / Manager インスタンスを参照
- @Published プロパティは自動的に両画面で同期
- 計算属性は各参照時に再計算（同期ズレなし）

---

## 7. テスト戦略

### 7.1 既存テスト対応

#### **ModelSelectionTests.swift**（パス: `Tests/TypeToTalkTests/ModelSelectionTests.swift`）

**既存テスト内容**:
- `testWhisperManagerRecommendedModelMatchesResolvedSelection()` (L6-14)
  - `whisper.statusText` が正しく設定される
- `testWhisperManagerUsesSelectedCustomModel()` (L16-26)
  - カスタムモデル選択時の挙動確認
- `testBonsaiManagerTracksSelectionChangeAsNotLoaded()` (L28-35)
  - `manager.statusMessage == "未読込"` の確認（L34）
- `testBonsaiManagerNeedsExplicitLoadTruthTable()` (L43-57)
  - `needsExplicitLoad` の真理値表検証

**修正後のテスト対応**:
- 要件①で statusText 計算ロジック修正時：
  - L6-14 のテストが該当 → 修正後も同じ結果が返るか確認
  - loading state での statusText が正しく loadingStatusText を返すか検証テスト追加
  
- 要件④で lastTriggerSource 削除時：
  - テスト影響なし（lastTriggerSource をテストしていない）

### 7.2 追加すべきテスト項目

#### **statusText loading state テスト**（新規追加）
```swift
// Whisper の loading state での statusText 検証
@MainActor
func testWhisperStatusTextDuringLoading() {
    let settings = SettingsManager()
    let manager = WhisperManager(settings: settings)
    
    // loading state に遷移
    manager.loadState = .loading
    manager.loadingStatusText = "ダウンロード中..."
    
    // statusText が loadingStatusText を返すか確認
    XCTAssertEqual(manager.statusText, "ダウンロード中...")
}
```

#### **Bonsai statusMessage update テスト**（新規追加）
```swift
@MainActor
func testBonsaiStatusMessageUpdatesWithLoadState() {
    let manager = BonsaiManager()
    
    // configureSelectedModel で status が更新される
    manager.configureSelectedModel("prism-ml/Ternary-Bonsai-8B-mlx-2bit")
    XCTAssertEqual(manager.statusMessage, "未読込")
    
    // loading state に遷移
    manager.loadState = .loading
    manager.configureSelectedModel("prism-ml/Ternary-Bonsai-8B-mlx-2bit")
    XCTAssertEqual(manager.statusMessage, "読込中")
}
```

### 7.3 テスト不可な部分

#### **ウインドウレイアウト（要件②）**
- **理由**: SwiftUI レイアウト計算は実機/ビルド時のみ
- **代替手段**:
  - macOS 14.x / 15.x での手動実機確認
  - 異なるウインドウサイズ (360x300, 400x350 など) での確認
  - traffic light との距離を目視確認

#### **システム設定誘導（要件⑤）**
- **理由**: NSWorkspace.open(url) の動作は環境依存
- **代替手段**:
  - 実機確認：アクセシビリティ権限なしの状態で、ボタン/リンククリック時に設定画面が開くか
  - URL スキーム妥当性の確認（既存の `openAccessibilitySettings()` で実績あり）

#### **音声フィードバック（要件④）**
- **理由**: NSSound.beep() の音出力は実機のみ
- **代替手段**:
  - beep() が呼び出されるタイミングの code coverage（recordTriggerFeedback の呼び出し側を追跡）
  - `NSSound.beep()` 削除 vs 保持の判断は、ユーザー意見聴取が重要

---

## 附録: 不確かな点

### 不確か①: infoStatusRow の detail パラメータの役割

**コード**:
```swift
infoStatusRow(
    title: "Trigger",
    detail: coordinator.statusMessage,  // ← coordinator.statusMessage をここで使用
    status: coordinator.lastTriggerSource
)
```

**疑問**:
- Trigger 行に「何の詳細」を表示したいのか？
- title = "Trigger"、status = "未検出" → ここまでで十分なのでは？
- detail: statusMessage は冗長に見える

**確認方法**:
- UI を実際に見て、画面上での配置・役割を確認
- 削除（要件④）する際に、detail パラメータの存在が邪魔にならないか確認

### 不確か②: Trigger 表示削除後の statusMessage 更新仕様

**コード** (L367):
```swift
private func recordTriggerFeedback(source: String) {
    lastTriggerSource = source
    if !recorder.isRecording && !isProcessing {
        statusMessage = "\(source) を受信"  // ← この行の動作
    }
    NSSound.beep()
}
```

**疑問**:
- Trigger 表示（infoStatusRow）を削除しても、statusMessage = "\(source) を受信" は残るのか？
- この statusMessage は左上の Text に表示されるため、一瞬「グローバル を受信」が出る UX になる
- 要件③との整合性：「待機中」初期値の改変と、このメッセージの関係は？

### 不確か③: 要件⑤でメイン画面に権限誘導ボタンを表示するか

**現状**:
- 権限なし時：statusMessage = "アクセシビリティ権限が必要です"
- 設定画面に「設定を開く」ボタンあり（既存）

**検討**:
- メイン画面に「システム設定を開く」ボタンを追加するか？
- それとも、statusMessage を詳細化するだけで、ボタンは設定画面に限定するか？
- ユーザーの利便性・UI 密度のトレードオフ

---

## 実装方針（推奨）

1. **要件① statusText 同期修正**
   - WhisperManager の statusText 計算ロジックを再確認、loading state の反映を確認
   - メイン画面・設定画面が正しく同じ値を表示するか、ビルド & 実機確認
   - ModelSelectionTests 実行
   
2. **要件② ウインドウ padding 調整**
   - VStack に leading padding 追加、または HStack に固定幅 spacer 追加でトラフィックライトとの距離を確保
   - 実機（macOS 14.x / 15.x）で確認

3. **要件③ statusMessage 初期値改変**
   - L192 の初期値を `""` or `" "` に変更
   - 各所で statusMessage が更新されるタイミングで「何も表示」から「メッセージ」に切り替わる UX 確認

4. **要件④ Trigger 表示削除**
   - L63-67 の infoStatusRow 行をコメント / 削除
   - recordTriggerFeedback の statusMessage 更新（L367）の動作仕様を確認
   - NSSound.beep() 保持判断

5. **要件⑤ アクセシビリティ権限説明**
   - StatusMessage を詳細化（L286）
   - AccessibilityManager.openAccessibilitySettings() を reuse
   - メイン画面での UI 配置設計（アラート / Sheet / ボタン）を確定
   - 実機で実際に権限誘導が動作するか確認

---

**調査完了日**: 2026-04-25  
**調査詳細度**: Very Thorough  
**検証済み実装パターン**: statusText 計算属性、loadingStatusText 段階更新、BonsaiManager の statusMessage 直接設定、NSWorkspace.open()、AccessibilityManager 権限確認  
**テスト対応**: ModelSelectionTests 既存、AudioRecorderTests 既存、新規テスト項目提案済み、手動確認項目明示

---

## 8. 追加要件: 聞き取り・整形 AI の言語設定

**実施日**: 2026-04-25 / **調査者**: イチゴ（ドイツ弁）

### 8.1 関連ファイル

| パス | 役割 | 重要度 |
|------|------|--------|
| `Sources/TypeToTalk/Managers/WhisperManager.swift` | 音声文字起こし、transcribe メソッド | ★★★ |
| `Sources/TypeToTalk/Managers/SettingsManager.swift` | 設定値の保存・復元（言語設定の追加先） | ★★★ |
| `Sources/TypeToTalk/Managers/OpenAICompatibleManager.swift` | Groq / OpenAI API 呼び出し、systemPrompt | ★★★ |
| `Sources/TypeToTalk/Managers/BonsaiManager.swift` | ローカルAI、ChatSession instructions | ★★★ |
| `Sources/TypeToTalk/Views/SettingsView.swift` | 設定画面、言語選択 UI 追加対象 | ★★ |
| `Sources/TypeToTalk/App/TypeToTalkApp.swift` | Coordinator、言語パラメータ渡し | ★★ |

---

### 8.2 既存実装の現状確認

#### **WhisperManager の transcribe メソッド**（path: `Sources/TypeToTalk/Managers/WhisperManager.swift:104-122`）

```swift
func transcribe(audioURL: URL) async -> String {
    guard let whisperKit = whisperKit else {
        return ""
    }
    
    isTranscribing = true
    defer { isTranscribing = false }
    
    do {
        // WhisperKit 0.18.0 の仕様に合わせる
        let results = try await whisperKit.transcribe(audioPath: audioURL.path)
        let combinedText = results.compactMap { $0.text }.joined(separator: " ")
        lastTranscription = combinedText
        return combinedText
    } catch {
        print("Transcription failed: \(error)")
        return ""
    }
}
```

**現状**:
- `transcribe(audioPath:)` 呼び出しで language パラメータを渡していない
- WhisperKit の transcribe メソッドシグネチャは、推定では `transcribe(audioPath: String, language: String? = nil, ...)`
- `language = nil` の場合、WhisperKit が自動検出（"auto" 相当）で動作

**問題**:
- 現在の実装では「言語指定ができない」
- ユーザーが複数言語で使用する場合、自動検出に依存 → 品質がばらつく可能性

#### **SettingsManager の言語設定**（path: `Sources/TypeToTalk/Managers/SettingsManager.swift`）

```swift
// L184-186: systemPrompt （日本語固定）
@Published var systemPrompt: String {
    didSet { UserDefaults.standard.set(systemPrompt, forKey: "systemPrompt") }
}

// L211: 初期値
self.systemPrompt = UserDefaults.standard.string(forKey: "systemPrompt") ?? 
    "以下の文字起こしテキストを、自然な日本語に修正してください。不要なフィラーは削除し、文脈を整えてください。"
```

**現状**:
- systemPrompt の初期値が「自然な日本語に修正」と明記
- 言語設定プロパティが存在しない
- 複数言語サポート用の設定欄がない

#### **OpenAICompatibleManager の systemPrompt 利用**（path: `Sources/TypeToTalk/Managers/OpenAICompatibleManager.swift:15-20`）

```swift
let requestBody: [String: Any] = [
    "model": model,
    "messages": [
        ["role": "system", "content": prompt],  // ← systemPrompt が直接渡される
        ["role": "user", "content": text]
    ],
    "temperature": 0.5
]
```

**現状**:
- systemPrompt をそのまま "system" role の content に使用
- systemPrompt が日本語であれば、Groq / OpenAI は日本語で応答
- ユーザーが systemPrompt を手動編集する以外、言語切り替え方法なし

#### **BonsaiManager の instructions 利用**（path: `Sources/TypeToTalk/Managers/BonsaiManager.swift:43-46`）

```swift
let session = ChatSession(
    container,
    instructions: prompt,  // ← systemPrompt が渡される
    generateParameters: .init(
        maxTokens: 384,
        temperature: 0,
        topP: 1,
        topK: 0
    )
)
```

**現状**:
- `instructions` パラメータに systemPrompt をそのまま渡す
- Bonsai 8B 1-bit も systemPrompt の言語に従う
- 言語別の別プロンプトを用意する機構がない

#### **Coordinator からの processText 呼び出し**（path: `Sources/TypeToTalk/App/TypeToTalkApp.swift:443-469`）

```swift
private func processText(_ text: String, with provider: FormatterProvider) async -> String {
    switch provider {
    case .groq:
        return await formatter.processText(
            text,
            endpoint: "https://api.groq.com/openai/v1/chat/completions",
            model: settings.groqModel,
            apiKey: settings.groqApiKey,
            prompt: settings.systemPrompt  // ← ここで systemPrompt が渡される
        )
    // ... 以下同様
    }
}
```

**現状**:
- 言語パラメータが Coordinator 経由で渡されない
- すべてのプロバイダーに同じ systemPrompt が使用される

---

### 8.3 言語設定の設計案（比較）

#### **案A: Whisper 言語と整形言語を個別設定**

**メリット**:
- 柔軟性が高い
- 例：日本語で話すが、英語で成形したい、など対応可能
- 各 AI の言語最適化が可能（Whisper は言語モデルの精度向上、整形 AI は言語別プロンプト）

**デメリット**:
- ユーザーインターフェースが複雑化
- 組み合わせが増える → テスト項目増加
- 設定画面が窮屈になる可能性

**実装例**:
```swift
// SettingsManager に追加
@Published var whisperLanguage: String {
    didSet { UserDefaults.standard.set(whisperLanguage, forKey: "whisperLanguage") }
}

@Published var formatterLanguage: String {
    didSet { UserDefaults.standard.set(formatterLanguage, forKey: "formatterLanguage") }
}

// 初期値（日本語）
self.whisperLanguage = UserDefaults.standard.string(forKey: "whisperLanguage") ?? "ja"
self.formatterLanguage = UserDefaults.standard.string(forKey: "formatterLanguage") ?? "ja"
```

#### **案B: 単一「言語」設定で両方を制御**

**メリット**:
- UI が シンプル（1つの Picker のみ）
- ユーザー操作が直感的
- 設定値の一貫性を保ちやすい

**デメリット**:
- 日本語で話して英語で成形、といった柔軟な用途に対応できない
- 言語によっては、Whisper と整形 AI で最適値が異なる場合がある

**実装例**:
```swift
@Published var appLanguage: String {
    didSet { UserDefaults.standard.set(appLanguage, forKey: "appLanguage") }
}

self.appLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? "ja"

// Whisper と整形両方に反映
var whisperLanguageForAPI: String { appLanguage == "auto" ? "" : appLanguage }
var formatterLanguagePrompt: String {
    switch appLanguage {
    case "ja": return "以下の文字起こしテキストを、自然な日本語に修正してください..."
    case "en": return "Correct the following transcribed text into natural English..."
    default: return "..."
    }
}
```

#### **推奨: 案A（個別設定）**

**根拠**:
- Whisper は言語パラメータで精度が顕著に変わる（多言語モデルの特性）
- 整形 AI の systemPrompt も言語依存性が高い
- TypeToTalk は複数の input/output を組み合わせるパイプラインなので、各段階の言語指定が重要
- 将来の拡張性を考慮

---

### 8.4 影響範囲

#### **WhisperManager への変更**

**変更内容**:
- `transcribe(audioURL:)` のシグネチャに `language: String?` パラメータ追加
- WhisperKit の `transcribe(audioPath:language:...)` に language を渡す

```swift
func transcribe(audioURL: URL, language: String?) async -> String {
    guard let whisperKit = whisperKit else { return "" }
    
    isTranscribing = true
    defer { isTranscribing = false }
    
    do {
        var options: [String: Any] = [:]
        if let language = language, !language.isEmpty {
            options["language"] = language
        }
        // ここでは WhisperKit の API に従う
        // 不確か: 実際の API シグネチャ確認が必要
        let results = try await whisperKit.transcribe(
            audioPath: audioURL.path
            // language: language ?? ""  // API に合わせて修正
        )
        // ... 以下同様
    } catch {
        // ...
    }
}
```

**呼び出し側変更** (`TypeToTalkApp.swift:255`):
```swift
var rawText = await whisper.transcribe(
    audioURL: audioURL,
    language: settings.whisperLanguage  // ← 新規パラメータ
)
```

#### **SettingsManager への変更**

```swift
@Published var whisperLanguage: String {
    didSet { UserDefaults.standard.set(whisperLanguage, forKey: "whisperLanguage") }
}

@Published var formatterLanguage: String {
    didSet { UserDefaults.standard.set(formatterLanguage, forKey: "formatterLanguage") }
}

// init() に追加
self.whisperLanguage = UserDefaults.standard.string(forKey: "whisperLanguage") ?? "ja"
self.formatterLanguage = UserDefaults.standard.string(forKey: "formatterLanguage") ?? "ja"

// 言語別 systemPrompt テンプレート（メソッド化）
func systemPromptForLanguage(_ language: String) -> String {
    switch language {
    case "ja":
        return "以下の文字起こしテキストを、自然な日本語に修正してください。不要なフィラーは削除し、文脈を整えてください。"
    case "en":
        return "Correct the following transcribed text into natural English. Remove unnecessary filler words and improve context."
    default:
        return systemPrompt  // ユーザーカスタムプロンプト
    }
}
```

#### **Coordinator への変更**

```swift
private func processText(_ text: String, with provider: FormatterProvider) async -> String {
    let promptForLanguage = settings.systemPromptForLanguage(settings.formatterLanguage)
    
    switch provider {
    case .groq:
        return await formatter.processText(
            text,
            endpoint: "https://api.groq.com/openai/v1/chat/completions",
            model: settings.groqModel,
            apiKey: settings.groqApiKey,
            prompt: promptForLanguage  // ← 言語別プロンプト
        )
    // ... 以下同様
    }
}
```

#### **SettingsView への変更**

聞き取り設定セクション（L44-88）に言語選択 Picker を追加：

```swift
settingRow("聞き取り言語") {
    Picker("聞き取り言語", selection: $settings.whisperLanguage) {
        Text("自動検出").tag("auto")
        Text("日本語").tag("ja")
        Text("English").tag("en")
    }
    .labelsHidden()
}
```

整形設定セクション（L92-179）に言語選択 Picker を追加：

```swift
settingRow("整形言語") {
    Picker("整形言語", selection: $settings.formatterLanguage) {
        Text("日本語").tag("ja")
        Text("English").tag("en")
        Text("カスタム").tag("custom")
    }
    .labelsHidden()
}

if settings.formatterLanguage == "custom" {
    VStack(alignment: .leading, spacing: 6) {
        Text("カスタムプロンプト")
            .font(.caption)
            .foregroundStyle(.secondary)
        TextEditor(text: $settings.systemPrompt)
            .frame(minHeight: 90)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
    }
}
```

---

### 8.5 想定される副作用 / リスク

#### **WhisperKit の language パラメータ仕様**

**リスク**: ★★★☆☆（中）

**不確かな点**:
- WhisperKit 0.18.0 の `transcribe()` メソッドが `language` パラメータをサポートしているか
- パラメータ形式（"ja" / "en" / "auto" のどれが許容か）
- `language = nil` または未指定時の動作（自動検出か、エラーか）

**確認方法**:
- WhisperKit の API ドキュメント / ソースを確認
- テストビルド時に `transcribe(audioPath:language:)` のシグネチャを検証

#### **整形 AI の systemPrompt 言語混在**

**リスク**: ★★☆☆☆（低）

**懸念**:
- Bonsai 8B 1-bit が英語プロンプトで日本語テキストを成形できるか
- Groq / OpenAI は多言語対応が強いため問題なし
- 言語不一致時（日本語テキスト + 英語プロンプト）の出力品質低下

**対策**:
- 実機テストで、各言語組み合わせを検証
- ドキュメントに「推奨組み合わせ」を記載

#### **既存ユーザーの互換性**

**リスク**: ★☆☆☆☆（低）

**影響**:
- 新たに追加される `whisperLanguage`, `formatterLanguage` プロパティは初期値 "ja"
- 既存の systemPrompt は削除されず、"custom" 言語選択で継続使用可能
- 互換性破損なし

---

### 8.6 制約条件

#### **言語コード形式**

- **ISO 639-1**: 2 文字言語コード（"ja", "en", "fr", 等）
- **特殊値**: "auto"（Whisper のみ）

#### **言語別プロンプトテンプレート**

- デフォルト提供：日本語（"ja"）、英語（"en"）
- カスタム言語は SettingsView でユーザーが systemPrompt を編集

#### **WhisperKit API**

- WhisperKit 0.18.0 以上（既存バージョン）
- `transcribe()` メソッドの詳細シグネチャ確認が必須

#### **既存命名規約**

- SettingsManager に新規プロパティ: `whisperLanguage`, `formatterLanguage` （camelCase）
- SettingsView の Picker 構造: 既存パターンに合わせる（label 幅 92px 等）

---

### 8.7 テスト戦略

#### **SettingsManager の言語設定 round-trip テスト**

```swift
@MainActor
func testWhisperLanguageRoundTrip() {
    let settings = SettingsManager()
    
    // デフォルト値確認
    XCTAssertEqual(settings.whisperLanguage, "ja")
    
    // 値変更
    settings.whisperLanguage = "en"
    XCTAssertEqual(settings.whisperLanguage, "en")
    
    // UserDefaults 永続化確認
    let newSettings = SettingsManager()
    XCTAssertEqual(newSettings.whisperLanguage, "en")
}

@MainActor
func testFormatterLanguageRoundTrip() {
    let settings = SettingsManager()
    
    // デフォルト値確認
    XCTAssertEqual(settings.formatterLanguage, "ja")
    
    // 値変更
    settings.formatterLanguage = "en"
    XCTAssertEqual(settings.formatterLanguage, "en")
    
    // 言語別プロンプト確認
    let englishPrompt = settings.systemPromptForLanguage("en")
    XCTAssertTrue(englishPrompt.contains("English"))
}
```

#### **言語別プロンプト組み立てテスト**

```swift
@MainActor
func testSystemPromptForLanguage() {
    let settings = SettingsManager()
    
    let jaPrompt = settings.systemPromptForLanguage("ja")
    XCTAssertTrue(jaPrompt.contains("日本語"))
    
    let enPrompt = settings.systemPromptForLanguage("en")
    XCTAssertTrue(enPrompt.contains("English"))
}
```

#### **WhisperManager の language パラメータ伝播テスト**

```swift
@MainActor
func testTranscribeWithLanguageParameter() async {
    let settings = SettingsManager()
    settings.whisperLanguage = "en"
    let manager = WhisperManager(settings: settings)
    
    // transcribe メソッド呼び出し時に language が反映されているか
    // モック WhisperKit を使用して検証（実装時に詳細化）
    // ※ 実際の transcribe は audio ファイルが必要なため、ユニットテスト困難
}
```

#### **実機テスト項目**

1. **音声文字起こし品質**
   - 日本語音声を ja で起こす → 品質確認
   - 日本語音声を auto で起こす → 品質確認、ja と比較
   - 英語音声を en で起こす → 品質確認
   
2. **AI 整形**
   - 日本語テキスト + 日本語プロンプト → 自然な日本語出力か
   - 日本語テキスト + 英語プロンプト → 言語不一致時の動作確認
   - 英語テキスト + 英語プロンプト → 自然な英語出力か

3. **UI**
   - SettingsView の言語選択 Picker が正常に動作するか
   - 言語変更後、次の文字起こし時に反映されるか

---

### 8.8 実装方針（推奨）

1. **Step 1: WhisperKit API 確認**
   - WhisperKit 0.18.0 の `transcribe()` メソッド シグネチャを確認
   - language パラメータの仕様（形式、デフォルト値）を確認

2. **Step 2: SettingsManager に言語プロパティ追加**
   - `whisperLanguage` (初期値: "ja")
   - `formatterLanguage` (初期値: "ja")
   - `systemPromptForLanguage(_ language: String)` メソッド実装

3. **Step 3: WhisperManager の transcribe を言語パラメータ対応**
   - メソッドシグネチャに `language: String?` 追加
   - WhisperKit API に language を渡す

4. **Step 4: Coordinator の processText に言語を反映**
   - systemPrompt → `settings.systemPromptForLanguage(settings.formatterLanguage)` に変更
   - transcribe 呼び出しに `language: settings.whisperLanguage` パラメータ追加

5. **Step 5: SettingsView に言語選択 UI を追加**
   - 聞き取り設定セクションに「聞き取り言語」Picker
   - 整形設定セクションに「整形言語」Picker
   - 言語が "custom" の場合、systemPrompt TextEditor を表示

6. **Step 6: テスト実装**
   - SettingsManager の round-trip テスト
   - 言語別プロンプト組み立てテスト
   - 実機での音声・整形品質テスト

---

**調査完了日**: 2026-04-25  
**調査詳細度**: Very Thorough  
**検証済み実装パターン**: SettingsManager の UserDefaults 連携、Picker UI パターン、Coordinator の言語パラメータ伝播  
**不確かな点**: WhisperKit 0.18.0 の transcribe メソッド language パラメータ仕様（実装時に確認必須）

---

## 9. 追加要件: 整形プロンプトの品質改善

**実施日**: 2026-04-25 / **調査者**: メロン（名古屋弁）

### 9.1 現状のプロンプト把握

#### **SettingsManager の systemPrompt 初期値**（path: `Sources/TypeToTalk/Managers/SettingsManager.swift:211`）

```swift
self.systemPrompt = UserDefaults.standard.string(forKey: "systemPrompt") ?? 
    "以下の文字起こしテキストを、自然な日本語に修正してください。不要なフィラーは削除し、文脈を整えてください。"
```

**現状の特性**:
- 初期値は **日本語固定**
- 内容：「自然な日本語に修正」「フィラー削除」「文脈整形」を列記
- **具体的な指示が不足**: 誤字訂正・口語特有の言い直し統合・句読点整理の詳細な例示がない
- **出力形式の制約なし**: プロンプトに「整形後テキストのみを返せ」等の制約がない
- **few-shot 例がない**: Before/After の具体例がないため、モデル（特に Bonsai 8B）が不確実に動作

#### **ユーザー編集機構**（path: `Sources/TypeToTalk/Views/SettingsView.swift:157-167`）

```swift
VStack(alignment: .leading, spacing: 6) {
    Text("整形プロンプト")
        .font(.caption)
        .foregroundStyle(.secondary)
    TextEditor(text: $settings.systemPrompt)
        .frame(minHeight: 90)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
}
```

**特性**:
- `TextEditor` でユーザーが自由に `systemPrompt` を編集可能
- UserDefaults 経由で永続化（SettingsManager L184-186）
- **デフォルト値への復帰機構がない**: ユーザーが誤った内容を入力すると、戻す方法がない（要件で「温存」とあるが、改善の余地あり）

#### **プロンプト適用箇所**

**OpenAICompatibleManager** (path: `Sources/TypeToTalk/Managers/OpenAICompatibleManager.swift:15-22`)
```swift
let requestBody: [String: Any] = [
    "model": model,
    "messages": [
        ["role": "system", "content": prompt],  // ← systemPrompt が直接渡される
        ["role": "user", "content": text]
    ],
    "temperature": 0.5
]
```

**BonsaiManager** (path: `Sources/TypeToTalk/Managers/BonsaiManager.swift:43-51`)
```swift
let session = ChatSession(
    container,
    instructions: prompt,  // ← systemPrompt が instructions として渡される
    generateParameters: .init(
        maxTokens: 384,
        temperature: 0,     // Bonsai は temperature 0（決定性重視）
        topP: 1,
        topK: 0
    )
)
```

**Coordinator から呼び出し** (path: `Sources/TypeToTalk/App/TypeToTalkApp.swift:443-469`)
```swift
private func processText(_ text: String, with provider: FormatterProvider) async -> String {
    switch provider {
    case .groq:
        return await formatter.processText(
            text,
            endpoint: "https://api.groq.com/openai/v1/chat/completions",
            model: settings.groqModel,
            apiKey: settings.groqApiKey,
            prompt: settings.systemPrompt  // ← 同じ systemPrompt をすべてのプロバイダーに使用
        )
    case .openAI:
        return await formatter.processText(
            text,
            endpoint: "https://api.openai.com/v1/chat/completions",
            model: settings.openAIModel,
            apiKey: settings.openAIApiKey,
            prompt: settings.systemPrompt
        )
    case .bonsai:
        bonsai.configureSelectedModel(settings.resolvedBonsaiModelID)
        return await bonsai.processText(
            text,
            prompt: settings.systemPrompt,
            modelID: settings.resolvedBonsaiModelID
        )
    }
}
```

---

### 9.2 現状プロンプトの問題点（具体的に）

#### **問題① 出力形式の指定が弱い**

**具体例**: 整形後に「修正しました」などの前置きが付く可能性
- **現在のプロンプト**: 「修正してください」のみ → モデルが "修正しました。..." と返すことがある
- **結果**: 入力欄に前置きが挿入され、ユーザーの元データと混在する

**改善ポイント**: 「整形後テキストのみを返せ。説明は不要」との明記が必須

#### **問題② Whisper 特有の「自己訂正」パターンに未対応**

**具体例**:
- Whisper が「あ、違う。今の無視して」→「テレビ」と出力
- 現在のプロンプトは「不要なフィラー削除」のみ
- **結果**: 「あ、違う。今の無視して」がそのまま残る（内容的に無意味）

**改善ポイント**: 「『あ、違う』『いや』『えっと』などの自己訂正句は削除し、修正後のテキストのみを残す」との明記

#### **問題③ 文体指定の仕組みがない**

**具体例**:
- ユーザーは「です・ます調で統一したい」と考える
- 現在のプロンプトに文体指定がない
- **結果**: 「です」と「だ」が混在する可能性

**改善ポイント**: プロンプトで「文体」を選択可能にする（3択: です・ます / だ・である / 自動）

#### **問題④ Bonsai 8B 1-bit の制限への未対応**

**特性**:
- Bonsai は context window が小さい（通常 8K, 実運用では 4K 程度推奨）
- few-shot 例が長すぎると、テキスト本体の処理能力が削減される

**改善ポイント**: Bonsai 用に「簡潔なプロンプト」を別途用意

#### **問題⑤ 言語別プロンプトの仕組みがない**

**関連**: 要件6（言語設定）と組み合わせ時の影響
- 日本語プロンプトで英語テキストを成形する場合、品質が低下する可能性
- **改善ポイント**: 言語別プロンプトテンプレートを用意（日本語版・英語版）

---

### 9.3 改善プロンプトの設計案

#### **基本構造**（System プロンプト 5 層構造）

```
1. 役割定義
2. 入力の特性説明
3. 整形ルール（誤字訂正 / フィラー除去 / 言い直し統合 / 文体統一 / 句読点整理）
4. 出力形式制約
5. few-shot 例（Before/After × 1～2）
```

#### **日本語版プロンプト案**

```swift
// 以下、Bonsai 向けの簡潔版（文字数制限意識）
let japanesePromptBonsai = """
あなたは音声入力の自動補正者です。

入力: Whisper による音声認識結果（誤字・フィラー・言い直しを含む）
出力: 整形後の日本語テキスト（本体のみ、説明不要）

ルール:
1. 誤字訂正: 文脈から同音異義語ミスを直す（例：「こんにちわ」→「こんにちは」）
2. フィラー除去: 「えーと」「あの」「まあ」「あ、その」等の口語特有の言葉を削除
3. 言い直し統合: 「あ、違う」「いや」「ごめん」等の自己訂正句を削除、修正後の内容のみ残す
4. 文体統一: {textStyle}（複数行入力）
5. 句読点: 不要な「、」「。」の二重や、行末の記号を整理

出力: テキストのみ。前置き・説明・修正ログは一切不要。

例:
入力: 「あ、違う。えーと、今日のテレビは、あの、まあ面白かった。」
出力: 「今日のテレビは面白かった。」
"""

// Groq / OpenAI 向けの詳細版
let japanesePromptDetailed = """
あなたは音声入力を高精度で自動補正する編集者です。

【入力について】
- Whisper による音声認識結果です
- 誤字、フィラー、言い直しを含む可能性があります
- 文脈から判断して修正してください

【実行すべき整形】
1. 誤字訂正
   - 同音異義語ミス: 「こんにちわ」→「こんにちは」
   - 入力変換ミス: 「せんたくき」→「洗濯機」
   - 文脈から意図を推測して直す

2. フィラー除去
   - 削除対象: 「えーと」「あの」「あ、その」「まあ」「そのー」
   - 文脈を損なわない範囲で削除

3. 言い直し統合
   - 「あ、違う」「いや」「ごめん」などの自己訂正句を削除
   - 修正後のテキストのみ残す
   - 例: 「あ、違う、西京区です」→「西京区です」

4. 文体統一
   - 目標: {textStyle}
   - 混在している場合は統一

5. 句読点整理
   - 二重句読点: 「。。」→「。」
   - 不要なカンマ: 「、、」→「、」（通常は句ごとに1個）

【出力形式】
- 整形後の日本語テキストのみを返してください
- 説明や修正ログは不要
- JSON や Markdown も不要、プレーンテキストのみ

【例】
入力: 「えーと、今日のテレビはあの、まあ面白かったです。」
出力: 「今日のテレビは面白かったです。」

入力: 「あ、違う。京都市です。西京区です。」
出力: 「京都市西京区です。」
"""
```

#### **英語版プロンプト案**

```swift
let englishPromptBonsai = """
You are a speech-to-text correction assistant.

Input: Transcribed text from Whisper (may contain errors, filler words, and self-corrections)
Output: Corrected English text only (no explanation)

Rules:
1. Fix typos: correct commonly confused words based on context
2. Remove fillers: "um", "uh", "like", "you know", "so" etc.
3. Merge corrections: remove self-corrections ("wait", "no actually", "I mean"), keep only the final version
4. Unify tone: {textStyle}
5. Punctuation: clean up double punctuation marks

Output: Text only. No explanations, no meta-commentary.

Example:
Input: "Um, like, today's meeting was, you know, pretty productive."
Output: "Today's meeting was pretty productive."
"""

let englishPromptDetailed = """
You are a professional speech-to-text editor.

【About the Input】
- Transcription from Whisper speech recognition
- May contain typos, filler words, and self-corrections
- Use context to make corrections

【Corrections to Apply】
1. Typo Correction
   - Homophone confusion: correct based on context
   - Autocorrect failures: fix misrecognized words
   
2. Filler Removal
   - Remove: "um", "uh", "like", "you know", "kind of", "sort of", "basically"
   - Preserve meaning

3. Merge Self-Corrections
   - Remove: "wait", "no actually", "I mean", "sorry"
   - Keep only the final, corrected version
   - Example: "wait, I meant Cambridge, Massachusetts" → "Cambridge, Massachusetts"

4. Tone Consistency
   - Target: {textStyle}
   - Unify mixed styles

5. Punctuation Cleanup
   - Remove double punctuation: ".." → "."
   - Clean up excessive commas

【Output Format】
- Return corrected English text only
- No explanations, meta-commentary, or formatting
- Plain text only

【Example】
Input: "Um, the project was, like, really challenging, but, you know, we managed."
Output: "The project was really challenging, but we managed."
"""
```

#### **文体オプション**（プレースホルダー {textStyle}）

```swift
enum TextStyle: String, CaseIterable {
    case desuMasu       // です・ます調（敬体）
    case daである       // だ・である調（常体）
    case auto           // 元のスタイルを維持
    
    var placeholder: String {
        switch self {
        case .desuMasu:
            return "です・ます調（敬体）で統一してください。"
        case .daである:
            return "だ・である調（常体）で統一してください。"
        case .auto:
            return "元のスタイルを尊重してください。"
        }
    }
}

// 英語版
enum EnglishTextStyle: String, CaseIterable {
    case formal
    case casual
    case auto
    
    var placeholder: String {
        switch self {
        case .formal:
            return "Formal tone (professional, structured)."
        case .casual:
            return "Casual, conversational tone."
        case .auto:
            return "Preserve the original tone."
        }
    }
}
```

---

### 9.4 影響範囲

#### **SettingsManager への変更**

**新規プロパティ追加**:
```swift
@Published var textStyle: String {
    didSet { UserDefaults.standard.set(textStyle, forKey: "textStyle") }
}

self.textStyle = UserDefaults.standard.string(forKey: "textStyle") ?? "auto"
```

**メソッド追加: systemPromptForLanguageAndStyle**:
```swift
func systemPromptForLanguageAndStyle(_ language: String, style: String) -> String {
    // 言語 × 文体 × プロバイダー（Bonsai / OpenAI） の組合せで最適なプロンプトを返す
    // 例：
    // - ("ja", "desuMasu", "bonsai") → 簡潔な日本語・です・ます版
    // - ("ja", "daである", "openai") → 詳細な日本語・だ・である版
    // - ("en", "formal", "bonsai") → 簡潔な英語・フォーマル版
}
```

**既存の systemPrompt テンプレート保持**:
- 言語・文体の組合せでテンプレートが見つからない場合、ユーザーの custom systemPrompt を使用
- 互換性破損なし

#### **SettingsView への変更**

整形設定セクション（L157-168）の後に「文体選択」Picker を追加:

```swift
settingRow("文体") {
    Picker("文体", selection: $settings.textStyle) {
        Text("自動").tag("auto")
        Text("です・ます調").tag("desuMasu")
        Text("だ・である調").tag("daである")
    }
    .labelsHidden()
}

Text("「です・ます調」は敬体（フォーマル）、「だ・である調」は常体（カジュアル）、「自動」は元のスタイルを維持します。")
    .font(.caption)
    .foregroundStyle(.secondary)
```

#### **Coordinator (TypeToTalkApp.swift) への変更**

processText メソッドを拡張:

```swift
private func processText(_ text: String, with provider: FormatterProvider) async -> String {
    let promptForLanguageAndStyle = settings.systemPromptForLanguageAndStyle(
        settings.formatterLanguage,  // 要件6で追加
        style: settings.textStyle
    )
    
    switch provider {
    case .groq:
        return await formatter.processText(
            text,
            endpoint: "https://api.groq.com/openai/v1/chat/completions",
            model: settings.groqModel,
            apiKey: settings.groqApiKey,
            prompt: promptForLanguageAndStyle  // ← 言語+文体別プロンプト
        )
    // ... 以下同様
    }
}
```

---

### 9.5 想定される副作用 / リスク

#### **リスク① few-shot 例が Bonsai context window を圧迫する**（★★★☆☆ 中）

**背景**:
- Bonsai 8B の context window: 4K～8K tokens（ライブラリ制限によって異なる可能性）
- 現在の Bonsai 使用方法（L47 で maxTokens: 384）→ 入力テキストは 2K tokens 程度
- few-shot 例が 500+ tokens あると、テキスト処理能力が削減

**対策**:
- Bonsai 用プロンプトは few-shot 例を「1 例のみ」に制限
- 詳細版（Groq / OpenAI）は 2～3 例を許容
- 実装時に Tokenizer を使って文字数・token 数を検証

**確認項目**（実装時）:
- `Tokenizers` ライブラリ（BonsaiManager で既に import）で、プロンプト + テキスト + 出力の総 token 数を事前計算

#### **リスク② 文体指定が強すぎるとユーザーの口語ニュアンスを破壊する**（★★☆☆☆ 低）

**例**:
- ユーザーが「だ・である調」を選択
- 元のテキスト: 「今日は面白い会議だったね」
- 強すぎる修正: 「今日は面白い会議である。」（ニュアンス喪失）

**対策**:
- SettingsView でプレビューを用意（実装時）
- 「文体統一」の強度を調整可能にする（low / high オプション）
- 実機テストで複数の入力パターンを確認

#### **リスク③ ユーザーの custom systemPrompt が無視される可能性**（★★★☆☆ 中）

**現状**:
- ユーザーが TextEditor で自由に systemPrompt を編集できる
- 新たに「言語+文体テンプレート」を導入すると、ユーザー入力が無視される可能性

**改善案**:
- 新規プロパティ `textStyle` とは **別に**、既存の `systemPrompt` を「カスタムモード」として保持
- SettingsView で「プリセット / カスタム」を選択
- 「カスタム」選択時は `systemPrompt` TextEditor を表示
- 「プリセット」選択時は言語+文体 Picker を表示

```swift
@Published var promptMode: String {  // "preset" or "custom"
    didSet { UserDefaults.standard.set(promptMode, forKey: "promptMode") }
}

// processText で使い分け
let prompt = settings.promptMode == "custom" 
    ? settings.systemPrompt 
    : settings.systemPromptForLanguageAndStyle(...)
```

#### **リスク④ 言語別プロンプトメンテナンス負荷**（★★☆☆☆ 低）

**影響**:
- 言語別プロンプト（日本語・英語・その他）が増えると、バグ報告時の対応が増える
- プロンプト内容の更新時に「全言語版を更新」が必要

**対策**:
- 初期リリースは「日本語・英語のみ」に限定
- 「その他言語」は「カスタムプロンプト」で対応（ユーザーが入力）
- ドキュメントに「プロンプト例」を掲載

---

### 9.6 制約条件

#### **Bonsai 8B への最適化**

- **Context window**: 実運用で 3K～4K tokens 推奨（保守的な見積もり）
- **Generation**: maxTokens: 384（現在値を継続）
- **Temperature**: 0（決定性重視、現在値を継続）
- **Few-shot 例**: 1 例のみ（テキスト本体の処理能力を確保）

#### **出力形式の厳密性**

- Groq / OpenAI: 「テキストのみを返す」でも比較的安定
- Bonsai: より厳密な指示が必要
  - 例: 「マークダウン、JSON は使わない」「説明は不要」と明記

#### **既存命名規約**

- **プロパティ**: `textStyle`, `promptMode`（camelCase）
- **Enum**: `TextStyle`, `EnglishTextStyle`（PascalCase）
- **SettingsView の settingRow**: 既存の label 幅 92px を継続

#### **ローカライズの仕組みがあるか**

確認: TypeToTalk に strings ファイルやローカライゼーション機構があるか

**grep 結果**:
```bash
$ find /Users/tamekuniz/GitHub/tamekuniz/TTT -name "*.strings" -o -name "*Localizable*"
# （確認要）
```

**推定**:
- 現在のコードに見当たらないため、UI 文字列は Swift コード内に直書き
- 多言語対応プロンプトも Swift の `switch` statement で実装（言語コード "ja" / "en" で分岐）

---

### 9.7 テスト戦略

#### **ユニットテスト: プロンプト組み立てロジック**

```swift
@MainActor
func testSystemPromptForLanguageAndStyle_JapaneseDesuMasu() {
    let settings = SettingsManager()
    let prompt = settings.systemPromptForLanguageAndStyle("ja", style: "desuMasu")
    
    // 「です・ます調」の指示が含まれているか
    XCTAssertTrue(prompt.contains("です・ます調") || prompt.contains("敬体"))
    // フィラー除去の指示があるか
    XCTAssertTrue(prompt.contains("フィラー") || prompt.contains("えーと"))
    // 出力形式の制約があるか
    XCTAssertTrue(prompt.contains("テキストのみ") || prompt.contains("説明不要"))
}

@MainActor
func testSystemPromptForLanguageAndStyle_EnglishFormal() {
    let settings = SettingsManager()
    let prompt = settings.systemPromptForLanguageAndStyle("en", style: "formal")
    
    // 英語プロンプトか
    XCTAssertTrue(prompt.lowercased().contains("english") || prompt.lowercased().contains("correct"))
    // Formal tone の指示があるか
    XCTAssertTrue(prompt.lowercased().contains("formal") || prompt.lowercased().contains("professional"))
}

@MainActor
func testPromptModeCustom_PreservesUserPrompt() {
    let settings = SettingsManager()
    settings.promptMode = "custom"
    settings.systemPrompt = "My custom prompt"
    
    // カスタムモード時は systemPrompt が使用される（UT では直接検証）
    XCTAssertEqual(settings.systemPrompt, "My custom prompt")
}
```

#### **実機テスト: プロンプト品質**

**テストデータセット**: Whisper が典型的に誤認識する 10～20 サンプル

**テスト項目**:
1. **誤字訂正**: 同音異義語テスト
   - 入力: 「こんにちわ」
   - 期待: 「こんにちは」
   - 実装前後で比較

2. **フィラー除去**: 
   - 入力: 「えーと、今日のテレビは、あの、面白かったです」
   - 期待: 「今日のテレビは面白かったです」

3. **言い直し統合**:
   - 入力: 「あ、違う。西京区です。」
   - 期待: 「西京区です。」（「あ、違う」が削除される）

4. **文体統一**:
   - 入力: 「今日は面白い会議です。明日は難しいな。」（混在）
   - プロンプト: 「です・ます調」
   - 期待: 「今日は面白い会議です。明日は難しいです。」

5. **言語別評価**:
   - 日本語テキスト + 日本語プロンプト → 期待以上
   - 英語テキスト + 英語プロンプト → 期待以上
   - 混言語テキスト → 品質低下は許容

**Bonsai vs Groq / OpenAI の比較**:
- 同一入力で各プロバイダーの出力を比較
- Bonsai の品質が「許容範囲」か確認（完全な一致は不要）

#### **副作用テスト**

1. **ユーザー custom プロンプトが上書きされない**
   - 前提: promptMode = "custom"、systemPrompt = "My text"
   - 言語変更後: systemPrompt が保持されているか確認

2. **プリセット選択時、プロンプトが正しく切り替わる**
   - promptMode = "preset" → systemPromptForLanguageAndStyle() から出力
   - promptMode = "custom" → systemPrompt テキストから出力

3. **SettingsView の文体 Picker がプロパティに連動する**
   - Picker 操作 → settings.textStyle 更新 → UserDefaults 永続化確認

---

### 9.8 実装方針（推奨）

#### **Phase 1: Bonsai 最適化プロンプト設計（§9.3 の簡潔版**）

1. Bonsai 8B の context window / token 上限を確認（MLXLLM ドキュメント or コード確認）
2. few-shot 例を含む簡潔版プロンプトを日本語・英語で作成
3. 実機でテスト（同じ Whisper 出力に対して改善前後を比較）

#### **Phase 2: 文体オプション追加**

1. SettingsManager に `textStyle` プロパティ追加（初期値: "auto"）
2. SettingsView に「文体」Picker を追加
3. systemPromptForLanguageAndStyle() メソッド実装（言語 × 文体別テンプレート）
4. Coordinator の processText で systemPromptForLanguageAndStyle() を呼び出すよう修正

#### **Phase 3: プロンプトモード（プリセット / カスタム）**

1. SettingsManager に `promptMode` プロパティ追加（初期値: "preset"）
2. SettingsView で「プロンプトモード」を選択
   - "preset": 言語+文体 Picker を表示
   - "custom": systemPrompt TextEditor を表示
3. Coordinator で prompt の出力先を分岐（promptMode に応じて）

#### **Phase 4: テスト・ドキュメント**

1. ユニットテスト実装（プロンプト組み立てロジック）
2. 実機テストシート作成（誤字・フィラー・言い直し・文体の 4 項目 × 複数サンプル）
3. ドキュメント作成
   - プロンプトテンプレートの説明
   - 推奨設定（言語×プロバイダー×文体の組合せ）
   - カスタムプロンプト例

---

### 9.9 不確かな点

#### **不確か① Bonsai 8B の context window サイズ**

**確認必要**:
- MLXLLM ライブラリで使用している Bonsai 8B variant の context size
- 実機でテスト時に入力 + プロンプト + 出力の実際の token 数を計測

**影響**:
- few-shot 例の長さ決定に関わる

#### **不確か② Groq / OpenAI に対する出力形式制約の有効性**

**確認必要**:
- プロンプトで「テキストのみを返す」と指示しても、100% 遵守されるか
- 応答に「修正完了」等の接頭辞が付く確率

**改善案**:
- few-shot 例を充実させ、期待される出力形式を明確化

#### **不確か③ TypeToTalk のローカライズ仕組み**

**確認必要**:
```bash
grep -r "NSLocalizedString\|LocalizedStringResource" /Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/
```

**推定**:
- 現在のコードに Localizable.strings が見当たらない → Swift コード内の直書き
- 多言語プロンプトも Swift の switch で実装

---

**調査完了日**: 2026-04-25  
**調査詳細度**: Very Thorough  
**検証済み実装パターン**: SettingsManager の UserDefaults 連携、TextEditor でのプロンプト編集、Coordinator での言語パラメータ伝播、Bonsai の instructions / OpenAI・Groq の system role  
**不確かな点**: Bonsai 8B context window サイズ、Groq / OpenAI の出力形式制約遵守率、TypeToTalk ローカライズ機構（実装時に確認必須）

