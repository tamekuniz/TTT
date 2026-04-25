# TypeToTalk 4件変更の徹底調査報告

調査日時: 2026-04-25  
調査者: マンゴスチン型調査妖精（バリバリのキナイ方言）

---

## 1. 関連ファイル一覧

| ファイルパス | 役割 | 関連要件 |
|---|---|---|
| `/Sources/TypeToTalk/Managers/BonsaiManager.swift` | Bonsai モデル管理・読込・推論 | 要件1, 要件3 |
| `/Sources/TypeToTalk/App/TypeToTalkApp.swift` | アプリ構造・Coordinator・ウインドウ管理・ショートカット登録 | 要件2, 要件4 |
| `/Sources/TypeToTalk/Managers/AudioRecorder.swift` | 音声録音・ファイルURL生成・タップハンドラー | 要件2 |
| `/Sources/TypeToTalk/Views/SettingsView.swift` | 設定UI・ショートカット Recorder・モデル読込ボタン | 要件3, 要件4 |
| `/Sources/TypeToTalk/Managers/SettingsManager.swift` | UserDefaults 永続化・モデルID解決 | 要件1, 要件4 |
| `/Sources/TypeToTalk/Managers/WhisperManager.swift` | Whisper モデル管理・同様の `needsExplicitLoad` パターン | 要件3 |
| `/Sources/TypeToTalk/Managers/AccessibilityManager.swift` | テキスト入力制御 | 要件2 |
| `/Sources/TypeToTalk/Models/DictionaryEntry.swift` | 辞書エントリー構造 | （参考） |
| `/Tests/TypeToTalkTests/ModelSelectionTests.swift` | モデル選択テスト | 要件3, 要件4 |
| `/Tests/TypeToTalkTests/AudioRecorderTests.swift` | 音声録音テスト | 要件2 |
| `/Package.swift` | 依存関係・Platform / KeyboardShortcuts 2.4.0 | 要件4 |

---

## 2. 既存実装パターン

### 2.1 KeyboardShortcuts の使用方法

**登録パターン** (`TypeToTalkApp.swift:5-7`)
```swift
extension KeyboardShortcuts.Name {
    static let triggerRecording = Self("triggerRecording")
}
```
- KeyboardShortcuts の extension で static property として定義
- String literal で一意な識別子を設定
- リトル構造で複数定義可能

**ハンドラー登録** (`TypeToTalkApp.swift:208-218`)
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
- `onKeyDown` / `onKeyUp` で key down/up を分離登録
- クロージャー内で async Task を起動（@MainActor isolation）
- weak self による循環参照回避

**SettingsView での Recorder UI** (`SettingsView.swift:184`)
```swift
KeyboardShortcuts.Recorder(for: .triggerRecording)
```
- 組み込み UI コンポーネント `KeyboardShortcuts.Recorder`
- ユーザーが対話的にキーを割り当て可能

### 2.2 Bonsai モデルパス参照方式

**現在の初期化** (`BonsaiManager.swift:26-29`)
```swift
init() {
    let baseDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".ttt/models")
    self.downloader = HuggingFaceHubDownloader(downloadBase: baseDirectory)
```
- homeDirectory + ".ttt/models" でパス構築
- `HuggingFaceHubDownloader` 初期化時に downloadBase を渡す
- Hub フレームワークの `HubApi` が実際のダウンロード・キャッシュ管理

**DownloadBase の使用側** (`BonsaiManager.swift:161-163`)
```swift
private struct HuggingFaceHubDownloader: Downloader {
    init(downloadBase: URL) {
        self.hubApi = HubApi(downloadBase: downloadBase)
    }
```
- `HubApi(downloadBase:)` に直接渡される
- HubApi が models, .git/lfs, cache などの管理に使用

### 2.3 needsExplicitLoad パターン（現在）

**BonsaiManager.swift:64-65（冗長）**
```swift
var needsExplicitLoad: Bool {
    loadedModelID != nil ? loadedModelID != nil && loadedModelID != currentSelectedModelID : true
}
```
- `loadedModelID != nil ?` → true なら `loadedModelID != nil && loadedModelID != currentSelectedModelID`
- 右側の `loadedModelID != nil` は左の条件で既に true なので冗長
- 三項演算子の右側で同じ条件を二度チェック

**WhisperManager.swift:39-40（シンプル・参考パターン）**
```swift
var needsExplicitLoad: Bool {
    whisperKit == nil || loadedModelID != selectedModelID
}
```
- `nil チェック || 不一致チェック`
- 明快・推測しやすい

### 2.4 ウインドウ管理・表示トグルロジック

**現在のウインドウ表示** (`TypeToTalkApp.swift:391-401`)
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
- `identifier == "RecorderWindow"` で特定ウインドウを識別
- `makeKeyAndOrderFront(nil)` で前面表示・フォーカス付与
- fallback で最初のウインドウを表示

**ウインドウ初期化** (`TypeToTalkApp.swift:450-455`)
```swift
if let window = NSApplication.shared.windows.first {
    window.identifier = NSUserInterfaceItemIdentifier("RecorderWindow")
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
}
```
- onAppear で identifier を付与
- 他プロパティも併設（UI カスタマイズ）

### 2.5 SettingsView での RecorderView 形式

**セッティング行の構造体** (`SettingsView.swift:272-281`)
```swift
@ViewBuilder
private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 92, alignment: .leading)
        content()
    }
}
```
- 左に caption ラベル、右に content
- ViewBuilder で柔軟な content 注入

**ショートカット行の用例** (`SettingsView.swift:183-185`)
```swift
settingRow("ショートカット") {
    KeyboardShortcuts.Recorder(for: .triggerRecording)
}
```
- settingRow に KeyboardShortcuts.Recorder を embed
- 同じ形式で新ショートカット行も追加可能

---

## 3. 影響範囲

### 3.1 要件1: Bonsai モデルパス修正（`~/.ttt/models` → `~/.typetotalk/models`）

**影響ノード一覧:**
1. **BonsaiManager.swift:26-29 (init)**
   - homeDirectory + ".ttt/models" → homeDirectory + ".typetotalk/models"

2. **HuggingFaceHubDownloader 経由で Hub フレームワークへ伝播**
   - Hub の HubApi が downloadBase でキャッシュを管理
   - 変更後は新パスにモデルをダウンロード

3. **SettingsView.swift:152 の UI テキスト**
   ```swift
   Text("初回利用時に `\(settings.resolvedBonsaiModelID)` をダウンロードし、`~/.typetotalk/models` 配下へキャッシュします。")
   ```
   - パス表示をここで言及しているため、こちらも更新必要（既に新パスと一致している可能性）

**呼び出し側:**
- BonsaiManager.init() は Coordinator.init() で 1 回だけ（`@Published var bonsai = BonsaiManager()`）
- 呼び出し時点でのみパス決定

**データフロー:**
```
BonsaiManager.init() 
  → HuggingFaceHubDownloader(downloadBase: baseDirectory)
    → HubApi(downloadBase: baseDirectory)
      → models 自動配置・キャッシュ
```

**既存ユーザーへの影響:**
- `~/.ttt/models/` にキャッシュされたモデルは孤児化
- 初回実行時に新パス `~/.typetotalk/models/` に再ダウンロード
- ディスク使用量が一時的に倍増する可能性

### 3.2 要件2: AudioRecorder 戻り値 URL の活用

**現在の URL 生成と使用:**

`AudioRecorder.swift:64, 84`
```swift
let url = FileManager.default.temporaryDirectory.appendingPathComponent("recording.wav")
...
return url  // startRecording() の戻り値
```

`TypeToTalkApp.swift:284`
```swift
_ = try await recorder.startRecording()  // 戻り値を捨てている
```

**改修対象:**

1. **Coordinator の recordingURL 保持**
   - `@Published var recordingURL: URL?` を追加（String Sendable チェック必要）
   - `toggleRecording()` の中で捕捉
   ```swift
   let recordingURL = try await recorder.startRecording()
   // 保持
   ```

2. **文字起こしフェーズでの使用** (`TypeToTalkApp.swift:234`)
   - 現状: ハードコード `temporaryDirectory.appendingPathComponent("recording.wav")`
   - 改修: 保持した `recordingURL` を使用
   ```swift
   let audioURL = recordingURL ?? FileManager.default.temporaryDirectory.appendingPathComponent("recording.wav")
   ```

3. **Sendable チェック**
   - URL は Sendable（Swift 6）
   - recordingURL を @Published プロパティとして保持 → @MainActor isolation で OK

**呼び出し側:**
- `toggleRecording()` → `whisper.transcribe(audioURL:)`
- URL は filePath を経由して AVAudioEngine へ

**データフロー:**
```
startRecording() → URL
  → Coordinator が capture
    → toggleRecording() 内で whisper.transcribe(audioURL:) に渡す
```

**リスク:**
- 複数回の toggleRecording() 呼び出しで recordingURL が上書きされる
  - Push-to-Talk + Toggle 混在時に予期しない URL を参照する可能性

### 3.3 要件3: BonsaiManager の needsExplicitLoad リファクタ

**現在の実装**
```swift
var needsExplicitLoad: Bool {
    loadedModelID != nil ? loadedModelID != nil && loadedModelID != currentSelectedModelID : true
}
```

**提案される実装**
```swift
var needsExplicitLoad: Bool {
    loadedModelID != currentSelectedModelID
}
```

**意味的等価性の検証:**

| loadedModelID | currentSelectedModelID | 旧論理 | 新論理 |
|---|---|---|---|
| nil | "model-a" | true | true ✓ |
| nil | "model-b" | true | true ✓ |
| "model-a" | "model-a" | false | false ✓ |
| "model-a" | "model-b" | true | true ✓ |

- 旧論理は `loadedModelID != nil` の場合のみ second check をするが、結果的に同じ
- 新論理は直接不一致チェック（nil ≠ "model-a" は true）
- 意味的に等価

**呼び出し側:**
- `SettingsView.swift:72, 143` → `loadStatusBlock()` の selectedModel 表示判定
- `SettingsView.swift:74, 145` → "再読込" ボタンの disabled 判定
- `WhisperManager` の statusText 内でも同様に使用

**テスト影響:**
- `ModelSelectionTests.testBonsaiManagerTracksSelectionChangeAsNotLoaded()` が対象
  - 現在: `manager.needsExplicitLoad == true`
  - 改修後: 同じく true（等価なので変更不要）

### 3.4 要件4: ウインドウ表示トグル用ショートカット新規追加

**新規ショートカット定義** (`TypeToTalkApp.swift:5-7`)
```swift
extension KeyboardShortcuts.Name {
    static let triggerRecording = Self("triggerRecording")  // 既存
    static let toggleWindow = Self("toggleWindow")          // 新規
}
```

**ハンドラー登録** (init に追加)
```swift
KeyboardShortcuts.onKeyDown(for: .toggleWindow) { [weak self] in
    Task { @MainActor in
        await self?.handleToggleWindow()
    }
}
```

**ハンドラー実装**
```swift
private func handleToggleWindow() async {
    // ウインドウの可視状態を判定・トグル
    for window in NSApplication.shared.windows {
        if window.identifier?.rawValue == "RecorderWindow" {
            if window.isVisible {
                window.orderOut(nil)  // 非表示
            } else {
                window.makeKeyAndOrderFront(nil)  // 表示
            }
            return
        }
    }
}
```

**SettingsView への Recorder UI 追加** (ショートカット行の下に新規行)
```swift
settingRow("ウインドウトグル") {
    KeyboardShortcuts.Recorder(for: .toggleWindow)
}
```

**ウインドウ可視状態の API:**
- `NSWindow.isVisible` → Bool
- `NSWindow.makeKeyAndOrderFront(nil)` → 表示 + フォーカス
- `NSWindow.orderOut(nil)` → 非表示 + バックグラウンド移動

**デフォルト未割当:**
- KeyboardShortcuts フレームワークの仕様
- ユーザーが SettingsView で対話的に設定
- デフォルト値は空 (nil)

**右Option キーとの相互作用:**
- `setupRightOptionMonitor()` → `handleFlagsChanged()` → `handleTriggerShortcutDown/Up()`
- 右Option は triggerRecording と同義（既存）
- toggleWindow は独立したショートカット（新規）
- 相互干渉なし

**データフロー:**
```
KeyboardShortcuts.onKeyDown(for: .toggleWindow)
  → handleToggleWindow()
    → NSWindow.isVisible チェック
      → orderOut() または makeKeyAndOrderFront()
```

**SettingsView での ショートカット行構成:**
```
ショートカット → KeyboardShortcuts.Recorder(for: .triggerRecording)  [既存]
ウインドウトグル → KeyboardShortcuts.Recorder(for: .toggleWindow)     [新規]
動作 → Picker (トリガー動作)                                           [既存]
```

---

## 4. 過去の類似実装

**git log より:**
```
cb281cf Refactor: Modularize project structure (App, Managers, Models, Views) for high maintainability
db58908 Implement Settings UI for API keys and custom prompts
1f0d5e7 Add documentation and Info.plist for system permissions
ca4c764 Initial commit of TTT (Talk to Type) macOS app
```

**類似ケースの有無:**
- KeyboardShortcuts の複数定義は過去に見当たらず（triggerRecording のみ）
- 右Option の監視は `setupRightOptionMonitor()` で 1 件（`handleFlagsChanged()` 経由）
- ウインドウトグル機能は過去実装なし

**参考になる実装:**
- Whisper / Bonsai の dual `needsExplicitLoad` パターン（WhisperManager.swift:39-40 がシンプル）
- SettingsView の settingRow composable（複数行の統一 UI）
- AudioRecorder.startRecording() の URL 戻り値（既に定義されているが未使用）

---

## 5. 想定される副作用 / リスク

### 5.1 要件1: Bonsai モデルパス変更

**副作用:**
- **既存キャッシュの孤児化**
  - `~/.ttt/models/` 下の既存ダウンロード済みモデルはアクセスされない
  - ディスク領域が無駄になる（既存ユーザーが手動削除しない限り）

- **初回実行時の再ダウンロード**
  - ネットワーク I/O 増加・DL 待機時間発生
  - 大型モデル（Ternary Bonsai 8B）の場合 GB 単位

**緩和策:**
- Changelog にパス変更を記載
- 初回起動時に旧パスからの migration スクリプト（任意）

**リスク度: 低～中（既存ユーザーへの負荷）**

### 5.2 要件2: AudioRecorder URL の活用

**副作用:**
- **recordingURL を @Published メモリに保持**
  - メモリ上では URL struct（小さい）なので影響小
  - 但し複数回録音時の上書き動作を明確にする必要

- **Sendable 関連の懸念**
  - URL は Sendable（Swift stdlib）
  - @Published @MainActor メンバーなので isolation OK
  - 新たな Sendable violation は生じない（予定）

**リスク度: 低（設計は安全）**

### 5.3 要件3: needsExplicitLoad のリファクタ

**副作用:**
- 意味的等価なので動作変化なし
- テストも修正不要（自動で通る）

**リスク度: 極低（コード品質向上のみ）**

### 5.4 要件4: ウインドウ表示トグル用ショートカット新規追加

**副作用:**
- **ウインドウ非表示時の右Option キー監視**
  - `setupRightOptionMonitor()` は global / local 両エクスポート登録済み
  - ウインドウが非表示でも NSEvent は監視継続（OS レベル）
  - CPU 使用率への影響は無視できる範囲

- **ウインドウ非表示時の stale reference**
  - `window.identifier` キャッシュ不要（毎回 NSApplication.shared.windows で再取得）
  - `isVisible` property は safe access

- **UI 表示順序**
  - SettingsView のタブ順（「一般」の中）に新ショートカット行を挿入
  - UI の再スタイリング・レイアウト変更が若干必要

**リスク度: 低（既存の window 管理 API の標準使用）**

### 5.5 統合リスク

- **4 件を並行実装**
  - 依存関係少なく独立（req1 = pathDir、req2 = URL capture、req3 = logic simplify、req4 = new shortcut）
  - テスト・検証も分離可能
  - merge conflict リスク低

---

## 6. 制約条件

### 6.1 Swift 言語・コンパイラ制約

**Swift 6.0（Package.swift:1）**
- `@MainActor` isolation 必須（Coordinator / Managers）
- Sendable チェック厳格（AudioRecorder の tap handler）
- concurrency safety が compile-time で強制

**implications:**
- recordingURL 保持時に Sendable チェック必要（ただし URL は Sendable）
- Task キャストを明示的に @MainActor で wrap（既存パターン踏襲）

### 6.2 macOS プラットフォーム

**Platform: macOS 14.0 以上（Package.swift:6-8）**
- NSApplication.shared / NSWindow / NSEvent 利用可
- KeyboardShortcuts はこの version range をサポート（Package.swift:14 より 2.4.0）
- `NSWindow.isVisible` は 10.5+ でサポート（macOS 14 なら OK）

### 6.3 KeyboardShortcuts フレームワーク

**Version: 2.4.0 以上（Package.swift:14）**
- `KeyboardShortcuts.Name` extension で複数定義可
- `KeyboardShortcuts.Recorder` UI コンポーネント対応
- `onKeyDown` / `onKeyUp` split callback 対応

**API stability:**
- 最新版（4.x+）でも後方互換性ありと思われるが、正確には GitHub repo confirm 必要
- 本調査では 2.4.0 を参照

### 6.4 SwiftUI for macOS

**Version: macOS 14.0 compat**
- TabView / VStack / HStack / Picker / SecureField / TextEditor
- すべて 14.0+ で利用可
- 新規 UI 요소は既存パターン踏襲（settingRow, GroupBox など）

### 6.5 既存命名規約

**Coordinator の命名:**
- `showRecorderWindow()` → display behavior（既存）
- `handleTriggerShortcutDown/Up()` → event handler（既存）
- `handleToggleWindow()` → event handler（新規・命名統一）

**Published property 命名:**
- `@Published var statusMessage` → UI 更新対象（既存）
- `@Published var recordingURL` → 新規・同規約で命名

**BonsaiManager の property 命名:**
- `var needsExplicitLoad` → computed property（既存・型 Bool）
- 変更なし（リファクタのみ）

---

## 7. テスト戦略

### 7.1 既存テストの拡張方針

**ModelSelectionTests.swift**

要件3 関連：
```swift
func testBonsaiManagerNeedsExplicitLoadAfterConfigureSelectedModel() {
    let manager = BonsaiManager()
    manager.configureSelectedModel("prism-ml/Ternary-Bonsai-8B-mlx-2bit")
    XCTAssertTrue(manager.needsExplicitLoad)
    // 新リファクタ後も同じ結果を期待
}

func testBonsaiManagerNeedsExplicitLoadEqualityAfterRefactor() {
    let manager = BonsaiManager()
    manager.currentSelectedModelID = "model-a"
    manager.loadedModelID = "model-b"
    // 旧: loadedModelID != nil ? loadedModelID != nil && loadedModelID != currentSelectedModelID : true
    // 新: loadedModelID != currentSelectedModelID
    XCTAssertTrue(manager.needsExplicitLoad)  // 同じ true
    
    manager.loadedModelID = "model-a"
    XCTAssertFalse(manager.needsExplicitLoad)  // 同じ false
}
```

要件4 関連（新規 test method）：
```swift
func testKeyboardShortcutsNameToggleWindowDefined() {
    // KeyboardShortcuts.Name.toggleWindow が定義されていることを確認
    // 実装上は compile-time で check される（static property）
    // Unit test では簡易確認のみ可能
    _ = KeyboardShortcuts.Name.toggleWindow
    // XCTest では pass（definition があれば compile）
}
```

**AudioRecorderTests.swift**

要件2 関連：
```swift
@MainActor
func testStartRecordingReturnsURL() async {
    let recorder = AudioRecorder()
    let recordingURL = try? await recorder.startRecording()
    XCTAssertNotNil(recordingURL)
    // ハードコードされた path と一致するか検証
    let expectedURL = FileManager.default.temporaryDirectory.appendingPathComponent("recording.wav")
    XCTAssertEqual(recordingURL, expectedURL)
    recorder.stopRecording()
}
```

### 7.2 テストできない領域・実機確認が必要な項目

**要件4: ウインドウトグル・ショートカット実機確認**

実装後に以下を manual test：
1. **ウインドウ表示トグル**
   - 新ショートカット `toggleWindow` を割り当て
   - ウインドウが visible → invisible → visible に遷移する
   - 録音中・非表示時に右Option キーで録音開始 → 正常に動作（ウインドウは非表示のまま）

2. **ショートカット UI の反応**
   - Settings → 一般タブ → ウインドウトグル行が表示される
   - Recorder UI が responsive
   - ユーザーがキー割り当て可能

3. **既存 triggerRecording との相互干渉**
   - 両ショートカットを異なるキーに割り当て
   - 同時押下時に correct callback が fire される

**要件1: パス変更の既存ユーザー影響確認**

実装後に以下を manual test：
1. **新環境での初回実行**
   - ~/.typetotalk/models に正常に create される
   - モデルが正常にダウンロード・ロード される

2. **既存ユーザーの upgrade scenario**
   - ~/.ttt/models/ が残り
   - ~/.typetotalk/models/ に新ダウンロード
   - 両方共存して問題ないか確認

**要件2: AudioRecorder URL の真の活用**

実装後に以下を manual test：
1. **複数回の push-to-talk**
   - 1 回目: ウインドウ表示 → 記録 → 文字起こし
   - 2 回目: 同じウインドウ → 新しい URL で記録 → 新しい文字起こし
   - 古い URL を参照しないことを確認

2. **実際の文字起こし精度**
   - captured URL で AVAudioEngine が正常に読み込めるか
   - ハードコード path 削除後も同じ結果

**要件3: needsExplicitLoad リファクタの動作確認**

実装後に以下を manual test（Settings 画面）:
1. **ボタン disabled 状態の正確性**
   - モデル未ロード時: "再読込" button は enabled
   - モデル ロード済み・same model 選択時: button は disabled
   - モデル ロード済み・different model 選択時: button は enabled

---

## 8. 実装順序の推奨

1. **要件3 (needsExplicitLoad リファクタ)** ← 最も低リスク
   - test も既存でカバー
   - review / merge 最短

2. **要件2 (AudioRecorder URL)** ← 次に低リスク
   - 戻り値は既存（使用されていないだけ）
   - URL capture は安全（Sendable）
   - 実機テスト必須だが、変更範囲小

3. **要件1 (Bonsai パス変更)** ← 既存ユーザーへの影響大
   - migration script / changelog 準備が必要
   - リリース note で告知

4. **要件4 (ウインドウトグルショートカット)** ← 最も複雑
   - 新ショートカット定義・ハンドラー登録・UI 追加
   - 実機テスト（shortcut fire + UI responsive）が重要
   - 既存 triggerRecording との相互干渉確認

---

## 9. 調査不確定事項

- **Hub フレームワークの downloadBase 挙動**
  - 本調査では Package.swift の dependency version (swift-transformers 1.1.9) のみ確認
  - 実際の HubApi implementation は `.build/checkouts/` にあるが詳細分析未実施
  - パス変更時に キャッシュ無効化 / 再ダウンロード判断ロジックの詳細は不明

- **NSWindow.isVisible / orderOut の macOS 14 での正確な挙動**
  - Apple API docs では 10.5+ と記載されているが、
  - macOS 14 特有の quirk / regression の有無は実機確認が必須

- **KeyboardShortcuts 2.4.0 の onKeyDown/onKeyUp 同時登録の callback order**
  - 複数ショートカット登録時に down/up の order が deterministic であるか
  - テスト環境での事前検証推奨

---

**調査完了。フォーメーションK の Step 3 としての務めを果たしたでおす。**

