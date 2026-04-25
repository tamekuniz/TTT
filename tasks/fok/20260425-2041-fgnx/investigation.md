# Bonsai モデルステータス表示不整合 ＆ 自動ロード不安定 - 調査報告書

**調査対象**: TypeToTalk macOS SwiftUI アプリにおいて、Bonsai モデルのステータス表示・自動ロードに関する2つの問題

**問題現象**:
- **問題 A（自動ロード不安定）**: アプリ起動時、ローカルモデルが存在してもロードされず、手動で「再読込」ボタン操作が必要な場面が頻発
- **問題 B（表示食い違い）**: 設定画面では Bonsai「準備完了」と表示されるが、メインウインドウでは「未読込」と表示される。同じ状態なのに表示が異なる

**参考**: Whisper でも同じ問題 B があり、commit 848ef06 で修正済み。修正パターンは「statusText を計算型から @Published プロパティに昇格＋ didSet で手動更新」

---

## 1. 関連ファイル一覧（パス + 役割）

| ファイルパス | 役割 | 重要度 |
|-----------|------|------|
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/BonsaiManager.swift` | Bonsai モデル管理、ステータス定義、ロード/自動ロード実装 | **最高** |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift` | アプリ起動、Coordinator、メインビュー、自動ロードトリガ定義 | **最高** |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Views/SettingsView.swift` | 設定画面 UI、Bonsai ステータス表示、再読込ボタン | **最高** |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/WhisperManager.swift` | Whisper モデル管理（参考実装・修正済み） | 中 |

---

## 2. 既存実装パターン（BonsaiManager の構造、ロードフロー、自動ロードトリガ箇所、状態管理、statusText/statusMessage の定義）

### 2.1 BonsaiManager.swift の @Published プロパティ

**ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/BonsaiManager.swift`（行 14-20）

```swift
@MainActor
final class BonsaiManager: ObservableObject {
    @Published private(set) var isModelLoaded = false
    @Published private(set) var loadedModelID: String?
    @Published private(set) var statusMessage = "未読込"      // ← ✅ @Published
    @Published private(set) var isLoadingModel = false
    @Published private(set) var loadState: BonsaiLoadState = .idle
    
    private var modelContainer: ModelContainer?
    private let downloader: any Downloader
    private let tokenizerLoader: any TokenizerLoader
    private let modelsBaseDirectory: URL
```

**@Published の内訳**:
- `loadState`: Enum 型で `idle | loading | loaded(modelID: String) | failed(message: String)` ✅ @Published
- `statusMessage`: 「未読込」「読込中」「準備完了」「失敗:...」を管理 ✅ @Published ← statusText ではなく statusMessage
- `isLoadingModel`: 読込中フラグ ✅ @Published
- `loadedModelID`: ロード済みモデル ID ✅ @Published
- `isModelLoaded`: ロード済みフラグ ✅ @Published

**重要**: BonsaiManager は statusMessage を @Published プロパティで持つため、値が変わるたびに objectWillChange が発火する（Whisper の修正後と同じ方式）

### 2.2 statusMessage の更新箇所

**ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/BonsaiManager.swift`

手動で statusMessage を更新する箇所:
- 行39: `statusMessage = "モデルを読み込んでください"` (processText 内)
- 行44, 57: `statusMessage = "準備完了"` (processText 内)
- 行60: `statusMessage = "エラー: \(error.localizedDescription)"` (processText catch)
- 行84: `statusMessage = "未読込"` (configureSelectedModel)
- 行86: `statusMessage = "読込中"` (configureSelectedModel)
- 行88: `statusMessage = loadedModelID == modelID ? "準備完了" : "未読込"` (configureSelectedModel)
- 行101: `statusMessage = "失敗: \(message)"` (loadSelectedModel catch)
- 行117: `statusMessage = "失敗: \(message)"` (ensureSelectedModelLoaded catch)
- 行148: `statusMessage = "読込中"` (loadModel 開始)
- 行160: `statusMessage = "モデル取得中 \(percent)%"` (loadModel 進捗)
- 行168: `statusMessage = "準備完了"` (loadModel 成功)

### 2.3 自動ロード流のコード実装

**ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/BonsaiManager.swift`（行 105-119）

```swift
func ensureSelectedModelLoaded(modelID: String) async {
    currentSelectedModelID = modelID
    guard canAutoLoad else { return }
    // 自動ロードはローカルにモデルが既にダウンロードされている場合のみ。
    // 未ダウンロードなら勝手にネットへ取りに行かず、状態は .idle のままサイレントに return。
    // 明示的な「再読込」は loadSelectedModel(modelID:) 経由で行うこと。
    guard isLocalModelAvailable(modelID: modelID) else { return }
    do {
        _ = try await loadModel(modelID: modelID)
    } catch {
        let message = error.localizedDescription
        loadState = .failed(message: message)
        statusMessage = "失敗: \(message)"
    }
}

/// `~/.typetotalk/models/<modelID>/` にモデル本体が既にダウンロードされ、中身が空でないかを判定する。
private func isLocalModelAvailable(modelID: String) -> Bool {
    let modelDir = modelsBaseDirectory.appendingPathComponent(modelID)
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: modelDir.path, isDirectory: &isDir), isDir.boolValue else {
        return false
    }
    // 中途半端に作られた空ディレクトリへの防御
    let contents = (try? FileManager.default.contentsOfDirectory(atPath: modelDir.path)) ?? []
    return !contents.isEmpty
}
```

**特性**:
- `ensureSelectedModelLoaded()` に `isLocalModelAvailable()` ガード機構がある（aac4a7a コミット由来）
- ローカルに存在しなければサイレントに return（loadState は .idle のまま）
- `configureSelectedModel()` とは別フェーズで呼ばれる

### 2.4 configureSelectedModel の役割

**ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/BonsaiManager.swift`（行 80-92）

```swift
func configureSelectedModel(_ modelID: String) {
    currentSelectedModelID = modelID
    switch loadState {
    case .idle:
        statusMessage = "未読込"
    case .loading:
        statusMessage = "読込中"
    case .loaded:
        statusMessage = loadedModelID == modelID ? "準備完了" : "未読込"
    case .failed:
        break
    }
}
```

**役割**:
- currentSelectedModelID を設定
- 現在の loadState に基づいて statusMessage を更新（計算型ではなく直接更新）

---

## 3. 影響範囲（呼び出し側 / 依存。Coordinator → BonsaiManager の関係、メインウインドウ・設定画面それぞれのステータス参照経路、Whisper との並行ロードの有無）

### 3.1 TypeToTalkCoordinator の依存構造

**ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`（行 186-215）

```swift
@MainActor
class TypeToTalkCoordinator: ObservableObject {
    @Published var recorder = AudioRecorder()
    @Published var whisper: WhisperManager
    @Published var formatter = OpenAICompatibleManager()
    @Published var bonsai = BonsaiManager()              // ← 公開されている
    @Published var accessibility = AccessibilityManager()
    @Published var network = NetworkManager()
    @Published var settings: SettingsManager
    
    init() {
        let settings = SettingsManager()
        self.settings = settings
        self.whisper = WhisperManager(settings: settings)
        // ...
    }
}
```

**重要な計算型プロパティ**: `activeFormatterStatusText`（行 402-409）

```swift
var activeFormatterStatusText: String {
    switch activeFormatterProvider {
    case .groq, .openAI:
        return network.isOnline ? "準備完了" : "未接続"
    case .bonsai:
        return bonsai.statusMessage      // ← Bonsai の @Published 値を返す計算型
    }
}
```

**問題 B の原因**: この `activeFormatterStatusText` が計算型プロパティであること

### 3.2 メインウインドウ (TypeToTalkMainView) のステータス参照経路

**ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`（行 9-87）

```swift
struct TypeToTalkMainView: View {
    @ObservedObject var coordinator: TypeToTalkCoordinator
    
    // ...
    
    VStack(spacing: 10) {
        modelStatusRow(
            title: "Whisper",
            detail: coordinator.settings.whisperDisplayName,
            status: coordinator.whisper.statusText       // ← 行81: 計算型プロパティ
        )
        modelStatusRow(
            title: "Formatter",
            detail: coordinator.activeFormatterDisplayName,
            status: coordinator.activeFormatterStatusText  // ← 行86: 計算型プロパティ
        )
    }
}
```

**参照方式**: `@ObservedObject var coordinator` → `coordinator.activeFormatterStatusText` → `bonsai.statusMessage`
- 3段階の参照チェーン
- 最後の計算型プロパティが原因で、Bonsai の statusMessage 変化が Coordinator 経由で View に伝わらない

### 3.3 設定画面 (SettingsView) のステータス参照経路

**ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Views/SettingsView.swift`（行 149）

```swift
struct SettingsView: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var whisper: WhisperManager
    @ObservedObject var bonsai: BonsaiManager            // ← 直接参照
    @ObservedObject var accessibility: AccessibilityManager
    
    // ...
    
    loadStatusBlock(
        status: bonsai.statusMessage,   // ← 直接参照、計算型ではない
        loadedModel: bonsai.loadedModelDisplayName,
        // ...
    )
```

**参照方式**: `@ObservedObject var bonsai` → `bonsai.statusMessage` (直接)
- 1段階だけ（Coordinator を経由しない）
- Bonsai の statusMessage が @Published なので、変化が直接 SettingsView に伝わる ✅

### 3.4 参照経路の比較表

| 参照元 | 参照パス | 経由プロパティ | statusMessage 伝播 | 理由 |
|------|--------|-------------|----------|------|
| SettingsView | `bonsai.statusMessage` | 直接（@Published） | ✅ | Bonsai の @Published が直接発行 |
| TypeToTalkMainView | `coordinator.activeFormatterStatusText` → `bonsai.statusMessage` | 計算型（activeFormatterStatusText） | ❌ | Coordinator 経由の計算型が中断 |

### 3.5 自動ロード呼び出し順序

**ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`（行 447-453, 510）

```swift
// TypeToTalkApp.swift 行510: アプリ起動
.onAppear {
    coordinator.handleAppLaunch()
}

// 行226-231: handleAppLaunch
func handleAppLaunch() {
    startupLoadTask?.cancel()
    startupLoadTask = Task { @MainActor [weak self] in
        await self?.synchronizeModelsForCurrentSettings()
    }
}

// 行447-453: synchronizeModelsForCurrentSettings
func synchronizeModelsForCurrentSettings() async {
    await whisper.ensureSelectedModelLoaded()
    bonsai.configureSelectedModel(settings.resolvedBonsaiModelID)     // ← 行449
    
    guard activeFormatterProvider == .bonsai else { return }
    await bonsai.ensureSelectedModelLoaded(modelID: settings.resolvedBonsaiModelID)  // ← 行452
}
```

**呼び出し順序**:
1. `handleAppLaunch()` (行510) → `synchronizeModelsForCurrentSettings()`
2. Whisper: `ensureSelectedModelLoaded()` (行448)
3. Bonsai: `configureSelectedModel()` (行449) ← statusMessage 更新
4. Bonsai が activeFormatterProvider なら `ensureSelectedModelLoaded()` (行452) ← 実際のロード開始

### 3.6 Whisper / Bonsai の並行ロード

- Whisper は行448で `await ensureSelectedModelLoaded()` （待機）
- Bonsai は行449-452で `configureSelectedModel()` (同期) → 必要に応じて `ensureSelectedModelLoaded()` (await)
- 論理的には並行ではなく順序建てられている

---

## 4. 過去の類似実装（git log で最近の修正パターンを確認。特に commit 848ef06 と aac4a7a を比較）

### 4.1 最近 50 コミット

```
380c996 [フォK] feat: Whisper hallucination 3層防御＋ビルド20260425C
021cf2b [フォK] chore: ビルド番号を 20260425B に更新
3d2a030 [フォK] feat: ビルドナンバー YYYYMMDDA 形式を Settings に表示
d08f241 [フォK] feat: 権限再チェックボタンをアプリ再起動ボタンに変更
9c10aed [フォK] feat: ショートカットを triggerRecording 1つに統合
848ef06 [フォK] fix: Whisperステータスがメインウインドウに伝播しない不整合を修正   ← ★ 問題 B の修正パターン
c57309d [フォK] feat: ウインドウタイトルを Mac 標準タイトルバーに移行
1883798 [フォK] fix: 録音終了後のマイクボタンパルス停止バグを修正
9d70ec7 [フォK] feat: マイクボタンUI改善＋権限ラベル微調整
aac4a7a [フォK] feat: モデル自動DL停止、ローカル存在時のみ自動ロード   ← ★ 問題 A のためのガード機構
```

### 4.2 commit 848ef06: Whisper ステータス伝播修正（参考実装）

**コミットメッセージ**: "WhisperManager.statusText を計算型から @Published private(set) var に昇格。loadState/loadingStatusText/whisperKit/loadedModelID の didSet で refreshStatusText() を呼ぶことで、Coordinator 経由で参照しているメインウインドウにも変化が伝わるようにした。"

**修正の要点**:
- `statusText` を計算型プロパティから `@Published private(set) var statusText: String = "未読込"` に昇格
- 依存するプロパティ（loadState, loadingStatusText, whisperKit, loadedModelID）に `didSet { refreshStatusText() }` を追加
- refreshStatusText() 関数を新設して、switch-case で statusText を計算して直接割り当て

**Bonsai への適用可能性**: 
- Whisper は statusText が計算型のまま（修正前）だったから問題が発生
- **Bonsai は既に statusMessage を @Published で管理しているため、この側面での問題はない**
- ただし、Coordinator の activeFormatterStatusText が計算型であることが問題

### 4.3 commit aac4a7a: モデル自動 DL 停止、ローカル存在時のみ自動ロード

**コミットメッセージ**: "ensureSelectedModelLoaded() に isLocalModelAvailable() ガードを追加。未ダウンロードならサイレントに return（loadState は .idle のまま、エラー出力もネット通信もしない）"

**修正の要点**:
- Whisper: `ensureSelectedModelLoaded()` に `isLocalModelAvailable(variant:)` ガード
  - キャッシュ先: `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/<variant>/`
  
- Bonsai: `ensureSelectedModelLoaded()` に `isLocalModelAvailable(modelID:)` ガード
  - キャッシュ先: `~/.typetotalk/models/<modelID>/`
  - `modelsBaseDirectory` を init で生成していた場所からプロパティに格上げ

**現在の Bonsai への適用状況**: 
- **既に実装済み**（BonsaiManager 行 105-119 を確認）
- ローカルモデル不存在時はサイレントに return

**問題 A（自動ロード不安定）の仮説**:
- aac4a7a で ローカル判定がガードされたため、「ローカルに存在しないモデルは自動ロードされない」が正常動作
- ユーザーが「ローカルモデル存在すると思っていたが、実はダウンロードされていなかった」という可能性が高い
- または、ローカル判定ロジック（`isLocalModelAvailable`）に不具合がある可能性

---

## 5. 想定される副作用 / リスク

### 5.1 問題 B 修正時の副作用（Coordinator の activeFormatterStatusText を @Published に昇格した場合）

1. **Coordinator に新プロパティ追加**: `@Published private(set) var formatterStatusText: String = "未読込"`
   - Coordinator の objectWillChange トリガが増加 → View 再評価頻度が増加（マイナーな影響）

2. **複数の formatter provider での状態管理複雑化**:
   - Groq, OpenAI, Bonsai で異なる状態ロジック（ネットワーク状態 vs ローカルロード状態）
   - 各 provider の状態変化をすべて Coordinator で監視・転送する必要

3. **既存 View（SettingsView）への影響**:
   - SettingsView は既に `bonsai.statusMessage` を直接参照しているため、新プロパティ追加後も動作継続
   - ただし、Coordinator の同じプロパティが並行して存在するため、整合性確保が必要

### 5.2 問題 A 修正時の副作用（自動ロード流の改善）

1. **configureSelectedModel と ensureSelectedModelLoaded の依存関係**:
   - 現在、configureSelectedModel が先に呼ばれて statusMessage を更新してから ensureSelectedModelLoaded が呼ばれる
   - この順序は正しいが、configureSelectedModel 内で loadState に基づいて statusMessage を書き直しているため、「ローカル判定前に statusMessage が確定」している

2. **loadState の二重管理**:
   - configureSelectedModel: statusMessage を直接更新（loadState に基づく）
   - ensureSelectedModelLoaded / loadSelectedModel: statusMessage を (別途の手動更新 / loadModel の進捗で) 更新
   - ダブルライト防止のため、coordi通知タイミング要確認

3. **エラーハンドリング**:
   - ensureSelectedModelLoaded の catch で statusMessage = "失敗:..." を設定（行117）
   - ただし、その前に configureSelectedModel でデフォルト値をセットしているため、エラー上書きは意図的

### 5.3 Whisper との相互作用

- Whisper も aac4a7a で isLocalModelAvailable ガードを追加済み
- Whisper は statusText を @Published に昇格済み（848ef06）
- Bonsai は statusMessage を @Published で管理しているが、Coordinator 経由参照が計算型のため、Whisper と異なる不整合パターン

---

## 6. 制約条件（Swift Concurrency、@MainActor、@Published、Task）

### 6.1 現在のアーキテクチャ制約

1. **@MainActor 標準化**: BonsaiManager, Coordinator 共に `@MainActor` で宣言
   - UI 更新は Main Thread のみで実行される
   - async/await 内で Task @MainActor を使用

2. **ObservableObject パターン**: Coordinator と各 Manager が ObservableObject に準拠
   - @Published プロパティの変化が自動的に objectWillChange を発火

3. **Swift Concurrency**: async/await で非同期処理を実装
   - BonsaiManager.ensureSelectedModelLoaded は async
   - TypeToTalkCoordinator.handleAppLaunch は Task { @MainActor } で wrap

4. **@Published の伝播ルール**:
   - 子オブジェクトの @Published 変化が親オブジェクト（Coordinator）を通じて伝播するには：
     - 親が子を @Published で保持する必要がある ✅ (coordinator は @Published var bonsai)
     - ただし、親から子の内部状態へのアクセスが計算型プロパティだと伝播が止まる ❌

### 6.2 計算型プロパティと @Published の相互作用ルール（Whisper 調査結果から）

| パターン | View 再評価 | 備考 |
|---------|---------|------|
| @Published プロパティを View で参照 | ✅ | objectWillChange 発火 |
| 計算型プロパティ（@Published なし）を View で参照 | ❌ | 依存元の @Published が変わっても、計算型自体が @Published でないと追跡されない |
| Coordinator 経由で @Published プロパティを参照（計算型を介さず） | ✅ | Coordinator の @Published 変化 → objectWillChange → View 再評価 |
| Coordinator 経由で @Published プロパティを参照（計算型を介す）| ❌ | Coordinator の計算型が伝播を中断 |

### 6.3 修正時に守るべき Swift 流儀

1. **@ObservedObject の多段参照を避ける**: `coordinator.activeFormatterStatusText` より `coordinator.formatterStatusText` が好ましい
2. **計算型プロパティは View 更新トリガにしない**: 値の計算は必要だが、View の再評価トリガは @Published で担当させるべき
3. **Coordinator が中継する場合は、子の @Published 変化を明示的に転送**: 計算型ではなく @Published で値を管理

---

## 7. テスト戦略（実機確認シナリオ）

### 7.1 問題 B（表示食い違い）バグ再現手順

**環境**: macOS 実機推奨（Bonsai モデルダウンロード時間: 数分）

1. **初期状態（未ロード）**:
   - TypeToTalk を起動 → メインウインドウ開く
   - ⚙️ 設定を開く
   - Bonsai が activeFormatterProvider でない場合: 設定画面で「Formatter」を「Bonsai」に変更

2. **ロード前の状態確認**:
   - 設定画面: 「Formatter」セクション → Bonsai ステータス「未読込」 ✅
   - メインウインドウ: 下部「Formatter」ステータス「未読込」 ✅（この時点では一致）

3. **再読込ボタンをクリック**:
   - 設定画面: 「再読込」ボタン押下
   - Bonsai ダウンロード＆ロード開始

4. **ロード中の状態確認**:
   - 設定画面: 「状態: モデル取得中...」に変わる ✅
   - メインウインドウ: Formatter ステータス「モデル取得中...」に変わる ✅（この時点では一致）

5. **ロード完了後の状態確認**（バグが顕在化する箇所）:
   - 設定画面: 「状態: 準備完了」と表示 ✅
   - メインウインドウ: Formatter ステータス「???」 ← **要確認（現状は「未読込」のはず）**

### 7.2 問題 A（自動ロード不安定）確認手順

**前提**: Bonsai モデルが `~/.typetotalk/models/<modelID>/` に既にダウンロード済み

1. **アプリ終了 → 再起動**:
   - TypeToTalk を完全に終了
   - Xcode Debug から再実行、または アプリを再起動

2. **起動後の状態確認**:
   - メインウインドウが開く
   - Formatter ステータスが「準備完了」か「未読込」か を確認
   - **期待値**: ローカルモデル存在 → 自動ロード → 「準備完了」
   - **現状**: 不安定（手動「再読込」が必要な場面が頻発）

3. **ローカルモデル存在確認**:
   - Terminal で確認: `ls -la ~/.typetotalk/models/`
   - 対象 modelID のディレクトリが存在し、中身が空でないか確認

4. **Xcode デバッグ出力確認**:
   - BonsaiManager.ensureSelectedModelLoaded() 内で print を仕込む
   - `isLocalModelAvailable()` が true を返しているか false を返しているか確認
   - ローカルモデル存在なのに false を返す場合 → isLocalModelAvailable ロジックのバグ疑い

### 7.3 実装修正後のテスト確認ポイント

**問題 B 修正後**:
- メインウインドウと設定画面の Formatter ステータスが常に同じ値を表示すること
- ロード中は両画面で「モデル取得中 XX%」と同期すること
- ロード完了後は両画面で「準備完了」に同期すること

**問題 A 修正後**:
- アプリ再起動後、ローカルモデル存在時は自動ロード（手動「再読込」不要）
- ローカルモデル未存在時はサイレントに待機（statusMessage は「未読込」のまま）
- ユーザーが「再読込」ボタンを押すとダウンロード開始

---

## 8. 根本原因 - 最終確定

### 8.1 問題 B（表示食い違い）の根本原因

**Coordinator.activeFormatterStatusText が計算型プロパティであり、@Published アノテーションが付いていない**

**ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`（行 402-409）

```swift
var activeFormatterStatusText: String {  // ← 計算型、@Published なし
    switch activeFormatterProvider {
    case .groq, .openAI:
        return network.isOnline ? "準備完了" : "未接続"
    case .bonsai:
        return bonsai.statusMessage      // ← @Published だが、計算型で包まれている
    }
}
```

**問題の現象**:
- TypeToTalkMainView は `@ObservedObject var coordinator` を持つ
- `coordinator.activeFormatterStatusText` を参照（計算型への参照）
- `bonsai.statusMessage` が変わった → `bonsai.objectWillChange` 発火
- **しかし Coordinator の objectWillChange は発火しない** ← @Published var bonsai の再割り当てではなく、内部プロパティ変化だから
- View 再評価されない
- → メインウインドウは初期値（「未読込」）のまま

**対比: SettingsView はなぜ正しく表示されるか**:
- SettingsView は `@ObservedObject var bonsai` で直接監視
- `bonsai.statusMessage` を参照（計算型ではない、直接参照）
- `bonsai.statusMessage` が変わった → `bonsai.objectWillChange` 発火
- View 再評価 → statusMessage 再読み取り → 新しい値表示 ✅

### 8.2 問題 A（自動ロード不安定）の根本原因候補

**仮説 1: isLocalModelAvailable() ロジックのバグ**
- Bonsai のキャッシュ先が複数存在する、または パスが変わった
- ローカルモデル存在なのに判定で false を返す

**仮説 2: configureSelectedModel と ensureSelectedModelLoaded の呼び出し順序問題**
- 行449で configureSelectedModel を呼んで statusMessage を更新
- 行451-452で activeFormatterProvider == .bonsai なら ensureSelectedModelLoaded を呼ぶ
- ローカル判定がこの間に "false" になるシナリオはあるか？（考えにくい）

**仮説 3: Coordinator 初期化時のタイミング**
- Bonsai は init() でのみ modelsBaseDirectory を設定（行27-30）
- settings の resolvedBonsaiModelID がまだ確定していない段階で ensureSelectedModelLoaded が呼ばれる可能性

**最有力仮説**: 仮説 1（isLocalModelAvailable ロジック）
- aac4a7a で Bonsai の isLocalModelAvailable は新規実装
- Whisper のそれと同じはずだが、パス仕様が異なるため、タイポやパス不一致がありうる

---

## 9. 最終結論と修正提案

### 9.1 問題 B（表示食い違い）の修正方針

**原因**: Coordinator.activeFormatterStatusText が計算型プロパティ

**修正方案**: Whisper の修正パターン（848ef06）を Coordinator に適用

**実装方針**:
1. Coordinator に新プロパティを追加: `@Published private(set) var formatterStatusText: String = "未読込"`
2. bonsai, network, settings などのプロパティの変化をリスンして、formatterStatusText を計算・更新
3. TypeToTalkMainView の参照を `coordinator.activeFormatterStatusText` から `coordinator.formatterStatusText` に変更

**影響度**: 低（Coordinator 内部の計算ロジックを移動するだけ）

**修正粒度**: 1 コミット（Whisper の修正パターンと同じ）

### 9.2 問題 A（自動ロード不安定）の修正方針

**原因**: isLocalModelAvailable() のロジック不具合 OR 呼び出しタイミング問題

**修正方案**:
1. isLocalModelAvailable() のロジック検証（ファイルシステム確認、パス一致確認）
2. 必要に応じてデバッグ print を仕込んで、実機で動作確認
3. ensureSelectedModelLoaded() の呼び出しタイミング（configureSelectedModel との相互依存）を確認
4. modelsBaseDirectory の初期化タイミングが遅延していないか確認（Coordinator init 時点で設定済みか）

**修正粒度**: 要調査。1 コミットで完結する可能性が高い

### 9.3 1 サイクルで修正可能か、分割すべきか

**判定**:
- 問題 A と B は独立した根本原因を持つ
- **推奨**: 1 サイクルで両方修正可能（別々の修正ポイント、Whisper 修正パターン既に確立）
- ただし、問題 A の原因確定に実機テストが必要なため、詳細原因分析は問題 B 修正と同並行で実施

**修正ステップ**:
1. Step 3-1: 問題 B 修正（Coordinator.formatterStatusText の @Published 化）
   - 実装簡単、テストも明確、Whisper パターンと同じ

2. Step 3-2: 問題 A 詳細原因分析（isLocalModelAvailable / 呼び出しタイミング）
   - 実機テスト必要、Xcode デバッグ出力確認

3. Step 3-3: 問題 A 修正実装
   - 原因に応じて修正内容が変わる（最小修正 or ロジック改善）

---

## 10. 補足資料

### 10.1 BonsaiManager vs WhisperManager のステータス管理比較

| 項目 | Bonsai | Whisper |
|------|--------|---------|
| ステータスプロパティ名 | statusMessage | statusText (修正後) |
| @Published | ✅ | ✅ (修正前は計算型) |
| 手動更新方式 | 直接代入（複数箇所） | refreshStatusText() 関数（didSet から呼び出し） |
| 計算依存 | loadState, loadedModelID | loadState, loadingStatusText, needsExplicitLoad |
| Coordinator での使用 | activeFormatterStatusText (計算型) | whisper.statusText (直接参照) |
| メインウインドウ参照 | Coordinator 経由（計算型で伝播中断） | Coordinator 経由（statusText は @Published なので伝播） |

### 10.2 aac4a7a コミット以降の isLocalModelAvailable 仕様

**Whisper の仕様**:
- キャッシュ先: `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/<variant>/`
- ファイルシステム確認: ディレクトリ存在 + 中身が空でない

**Bonsai の仕様**:
- キャッシュ先: `~/.typetotalk/models/<modelID>/`
- ファイルシステム確認: ディレクトリ存在 + 中身が空でない
- modelsBaseDirectory プロパティ化: init での `baseDirectory` をプロパティに格上げ

**現状**: BonsaiManager 行 125-134 で実装済み

---

