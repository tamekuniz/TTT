# Step 3 調査: Whisper / Bonsai モデル自動ダウンロード停止

## 1. 関連ファイル一覧（パス + 役割）

### Core Manager ファイル
- **`/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/WhisperManager.swift`**
  - WhisperKit のラッパー Manager
  - `ensureSelectedModelLoaded()`: 自動ロード（起動時・録音時に呼ばれる）
  - `loadSelectedModel()`: 明示的ロード（設定画面「再読込」ボタンから呼ばれる）
  - `setupWhisper(forceReload:)`: 内部実装、`WhisperKit.download(variant:)` を呼び出す

- **`/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/BonsaiManager.swift`**
  - MLX-Swift + Hub を使った Ternary Bonsai ローカル実行 Manager
  - `ensureSelectedModelLoaded(modelID:)`: 自動ロード（起動時・録音時に呼ばれる）
  - `loadSelectedModel(modelID:)`: 明示的ロード（設定画面「再読込」ボタンから呼ばれる）
  - `loadModel(modelID:)`: 内部実装、`HuggingFaceHubDownloader` 経由で `hubApi.snapshot()` を呼び出す
  - `HuggingFaceHubDownloader`: 内部 struct、Hub ライブラリを包装

### App 統合ファイル
- **`/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`**
  - `TypeToTalkCoordinator.handleAppLaunch()`: アプリ起動時、`synchronizeModelsForCurrentSettings()` を呼ぶ
  - `TypeToTalkCoordinator.toggleRecording()`: 録音開始時に `synchronizeModelsForCurrentSettings()` を呼ぶ（else 分岐）
  - `TypeToTalkCoordinator.synchronizeModelsForCurrentSettings()`: 両 Manager の `ensureSelectedModelLoaded()` を呼ぶ

### Settings / UI ファイル
- **`/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Views/SettingsView.swift`**
  - 「再読込」ボタン（Whisper 用, Bonsai 用）を提供
  - ボタン click → `whisper.loadSelectedModel()` / `bonsai.loadSelectedModel(modelID:)` を呼ぶ
  - 状態表示: ロード済み状態 / ロード中状態 / 未ロード状態 / エラーを表示

- **`/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/SettingsManager.swift`**
  - モデル選択の永続化（UserDefaults）
  - `resolvedWhisperModelID`: ユーザー選択モデル ID の解決

### 依存パッケージ（.build/checkouts）
- **WhisperKit (0.18.0)**
  - `/Users/tamekuniz/GitHub/tamekuniz/TTT/.build/checkouts/WhisperKit/Sources/WhisperKit/Core/WhisperKit.swift`
    - `WhisperKit.download(variant:downloadBase:...)`: 静的メソッド、`HubApi.snapshot()` を使用
  - `/Users/tamekuniz/GitHub/tamekuniz/TTT/.build/checkouts/ArgmaxCore/ModelDownloader.swift`
    - `ModelDownloader.downloadModel(modelInfo:downloadBase:useOfflineMode:)`: Hub キャッシュ管理

- **Hub / swift-transformers**
  - `/Users/tamekuniz/GitHub/tamekuniz/TTT/.build/checkouts/swift-transformers/Sources/Hub/HubApi.swift`
    - `HubApi.snapshot(from:revision:matching:progressHandler:)`: モデルダウンロード実装
    - ネットワーク接続検出と offline mode サポート

- **mlx-swift-lm**
  - `/Users/tamekuniz/GitHub/tamekuniz/TTT/.build/checkouts/mlx-swift-lm/Libraries/MLXLMCommon/ModelFactory.swift`
    - `loadModelContainer(from:using:configuration:...)`: Bonsai モデルロード API

---

## 2. 既存実装パターン（命名・構造、両 Manager のロード関数の呼ばれ方）

### WhisperManager のロード流
```
ensureSelectedModelLoaded()
  └─ canAutoLoad チェック（モデル ID が空文字列でないか）
  └─ setupWhisper(forceReload: false)
       └─ forceReload == false かつ既にロード済みなら早期返却
       └─ WhisperKit.download(variant: selectedModelID)  ← ★ ここで自動ダウンロード
       └─ WhisperKit(model:modelFolder:) で初期化
       └─ whisperKit プロパティに保存 / loadState を .loaded に遷移

loadSelectedModel()
  └─ setupWhisper(forceReload: true)
       └─ 常に再ロード（キャッシュをスキップ）
```

### BonsaiManager のロード流
```
ensureSelectedModelLoaded(modelID:)
  └─ canAutoLoad チェック（モデル ID が空文字列でないか）
  └─ loadModel(modelID:)
       └─ loadModelContainer(from: downloader, using: tokenizerLoader, ...)
            └─ downloader: HuggingFaceHubDownloader (hubApi を内部保有)
            └─ hubApi.snapshot(from:revision:matching:progressHandler:)  ← ★ ここで自動ダウンロード
       └─ modelContainer プロパティに保存 / loadState を .loaded に遷移

loadSelectedModel(modelID:)
  └─ loadModel(modelID:)
       └─ 上記と同じ（forceReload フラグなし、毎回実行される）
```

### 既存の @Published & @MainActor の構造
- `@MainActor class WhisperManager` / `@MainActor final class BonsaiManager`
- すべての UI 更新は MainActor で実行
- `loadState` enum: `.idle` / `.loading` / `.loaded(modelID:)` / `.failed(message:)`
- `statusMessage` / `statusText`: UI に表示する状態文字列

---

## 3. 影響範囲（呼び出し側、依存先、データフロー）

### 呼び出し側（TypeToTalkApp.swift）
1. **アプリ起動時**
   ```swift
   // TypeToTalkApp.onAppear
   coordinator.handleAppLaunch()
     └─ coordinator.synchronizeModelsForCurrentSettings()
   ```

2. **録音開始時**
   ```swift
   // TypeToTalkCoordinator.toggleRecording()
   } else {
       do {
           await synchronizeModelsForCurrentSettings()  ← toggleRecording の else 分岐
           recordingURL = try await recorder.startRecording()
   ```

3. **設定画面から明示的に**
   ```swift
   // SettingsView.swift の loadStatusBlock
   Button(action: { await whisper.loadSelectedModel() })
   Button(action: { await bonsai.loadSelectedModel(modelID:) })
   ```

### 依存先の関数
- **WhisperManager**
  - `WhisperKit.download(variant:)` → `HubApi.snapshot()`
  - ネット通信が自動的に発生
  - キャッシュ先: `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/<variant>/` (Hub デフォルト)

- **BonsaiManager**
  - `HuggingFaceHubDownloader` → `HubApi.snapshot()`
  - ネット通信が自動的に発生
  - キャッシュ先: `~/.typetotalk/models/` (BonsaiManager init で指定)

### データフロー図
```
[アプリ起動 / 録音開始]
  ↓
TypeToTalkCoordinator.synchronizeModelsForCurrentSettings()
  ├─ whisper.ensureSelectedModelLoaded()
  │   └─ setupWhisper(forceReload: false)
  │       └─ WhisperKit.download() ← ★ 自動ネット通信
  │
  └─ bonsai.ensureSelectedModelLoaded(modelID:)
      └─ loadModel(modelID:)
          └─ hubApi.snapshot() ← ★ 自動ネット通信

[設定画面「再読込」ボタン]
  ↓
whisper.loadSelectedModel() / bonsai.loadSelectedModel(modelID:)
  └─ 上記と同じ流れ（明示的なユーザー操作のため意図的）
```

---

## 4. 過去の類似実装（git log で拾うモデルロード関連コミット）

### 直近のコミット履歴
```
35fe441 [フォK] feat: 権限動的チェック＋UI区別＋触覚/視覚フィードバック
  - AccessibilityManager 権限チェック追加
  - アクセシビリティパーミッション関連のみ、モデルロードには関係なし

16d3413 [フォK] feat: UI整理＋言語設定＋整形プロンプト構造化
  - SettingsView の言語設定追加
  - 既存のモデルロード機構には手を入れていない

4b03313 [フォK] feat: TypeToTalk リファクタ完了＋整形AI整合性とウインドウトグル追加
  - TypeToTalkCoordinator, synchronizeModelsForCurrentSettings() 導入
  - WhisperManager / BonsaiManager の統合

cb281cf Refactor: Modularize project structure (App, Managers, Models, Views) for high maintainability
  - ファイル構成の整理（Managers, Views に分割）
  - 機能的な変化なし

db58908 Implement Settings UI for API keys and custom prompts
  - 設定画面の初期実装

ca4c764 Initial commit of TTT (Talk to Type) macOS app
  - 初期コミット
```

### 重要な知見
- **モデルロード戦略は起案後、大きな変更がない**
  - Coordinator パターン導入（cb281cf）時に全体構造が確定
  - 以来、自動ロード（ensureSelectedModelLoaded）と明示的ロード（loadSelectedModel）の区別は維持されている
- **「未ダウンロード時は何もしない」という要件は新規（過去コミットに類例なし）**
  - 従来は「必要なら自動ダウンロード」が原則

---

## 5. 想定される副作用 / リスク（既存ユーザーの体験変化、エラーパス、UI 状態）

### 既存ユーザーへの影響

#### シナリオ 1: ダウンロード済みユーザー（Happy Path）
- **従来**: アプリ起動時に自動ロード → 使用可能
- **変更後**: 同じく自動ロード（ローカル存在確認により）→ 使用可能
- **体験変化**: なし（想定通り）

#### シナリオ 2: 未ダウンロードで Wi-Fi あり
- **従来**: アプリ起動時に自動ダウンロード開始 → ダウンロード完了後ロード → 使用可能
- **変更後**: 
  - アプリ起動時は何もしない（「未読込」状態のまま）
  - 設定画面の「再読込」ボタンを明示的に押す → ダウンロード開始
  - **UI上の変化**: 「未読込」表示が変わらない（ユーザー困惑 risk）

#### シナリオ 3: 未ダウンロードで Wi-Fi なし（要件のメイン場面）
- **従来**: アプリ起動時に自動ダウンロード試行 → ネットワークエラー → エラーメッセージ表示 → 使用不可
- **変更後**: アプリ起動時は何もしない（サイレント、エラーなし）→ 「未読込」状態 → 使用不可
- **体験変化**: 「ネットワークエラー」メッセージが消える（良い）、しかし「未読込」がなぜなのか不明確（要改善）

### エラーパスの変化

| 場面 | 従来 | 変更後 |
|------|------|-------|
| アプリ起動時、未 DL | エラーメッセージ（ネットエラー） | サイレント（未読込状態） |
| 録音開始時、未 DL | エラーメッセージ（ネットエラー） | サイレント（未読込状態）、かつ後続のエラー処理 |
| 「再読込」ボタン、ネットなし | ダウンロード失敗 → エラーメッセージ | 同じ（明示的操作なので予期される） |

### UI 状態の問題点
- **問題**: 「未読込」のまま居続ける状態を、ユーザーが「なぜか分からない」と感じる可能性
- **現在の表示**:
  ```swift
  var statusText: String {
      switch loadState {
      case .idle:
          return needsExplicitLoad ? "未読込" : "準備完了"
      ...
  }
  ```
  - "未読込" にはモデルが明示的にロードされていないだけの情報しかない
  - 「ダウンロード未実施」なのか「ロードに失敗」なのか区別がつかない

### 記録すべき副作用
- **ローカル存在確認自体のコスト**: ファイル I/O が発生（実測必要だが軽微と予想）
- **連鎖エラー**: モデルロードされていない → `whisper.transcribe()` の早期ガード発動 → "モデルを読み込んでください" メッセージ
- **オフライン時の UX**: 「未読込」表示のままで、ユーザーは何をすべきか指示がない

---

## 6. 制約条件（命名規約 / SwiftUI / @MainActor / WhisperKit 0.18.0 / MLX-Swift）

### SwiftUI & @MainActor
- 両 Manager は `@MainActor` クラス（UI 更新は主スレッド必須）
- `@Published` プロパティ: SwiftUI が自動購読する
- `statusMessage` / `loadState` の更新は自動的に View を更新

### WhisperKit 0.18.0 の API 制約
```swift
public static func download(
    variant: String,
    downloadBase: URL? = nil,
    useBackgroundSession: Bool = false,
    from repo: String = "argmaxinc/whisperkit-coreml",
    token: String? = nil,
    endpoint: String = Constants.defaultRemoteEndpoint,
    progressCallback: ((Progress) -> Void)? = nil
) async throws -> URL
```
- **downloadBase**: キャッシュ先を明示可能（nil の場合 Hub デフォルト `~/Documents/huggingface`)
- **useBackgroundSession**: バックグラウンドセッション使用可（デフォルト false）
- **戻り値**: ダウンロード完了した URL（即座に初期化に使う）

### Hub / HubApi のオフラインモード
```swift
public struct HubApi: Sendable {
    var useOfflineMode: Bool?  // nil=自動検出、true=強制オフライン、false=強制オンライン
    
    func snapshot(
        from repo: Repo,
        revision: String = "main",
        matching globs: [String] = [],
        progressHandler: @escaping (Progress) -> Void = { _ in }
    ) async throws -> URL
}
```
- **useOfflineMode**: 
  - `nil` → `NetworkMonitor.shared.state.shouldUseOfflineMode()` で自動判定
  - `true` → ローカルキャッシュのみ検索、ネットなし
  - `false` → 常にネット試行

### MLX-Swift の loadModelContainer
- `Downloader` / `TokenizerLoader` をプロトコルで抽象化
- `from: downloader` → ダウンロード実装を注入可能
- BonsaiManager は `HuggingFaceHubDownloader` を実装（Hub を使う）

### 命名規約（既存）
- **Manager クラス**: 末尾が "Manager" （WhisperManager, BonsaiManager）
- **メソッド**: 
  - `ensureSelected...`: 自動ロード（条件付き）
  - `loadSelected...`: 明示的ロード
  - `setupWhisper() / loadModel()`: 内部実装
- **@Published プロパティ**: statusMessage, loadState, isLoadingModel
- **状態管理**: enum (WhisperLoadState, BonsaiLoadState) で明確化

---

## 7. テスト戦略（実機 / シミュレータ確認ポイント）

このプロジェクトは SwiftUI アプリで、自動テストが難しい（Async/Await + UI 統合）。
以下は実機 / シミュレータでの確認ポイント（手動テスト）。

### T1. ローカル存在確認機構のテスト

#### T1-1: WhisperKit モデル存在確認
- [ ] アプリが初回起動時（モデル未ダウンロード）、自動ロードを **スキップ** すること
  - 確認: SettingsView で Whisper の status が「未読込」のままか
  - 確認: Console に "WhisperKit setup failed" が出ないか（エラーではなく、スキップ）

- [ ] `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-tiny/` をあらかじめ配置
  - 確認: アプリ起動時に自動ロードが実行されることを Console で確認
  - 確認: status が「準備完了」になることを UI で確認

#### T1-2: Bonsai モデル存在確認
- [ ] `~/.typetotalk/models/mlx-community/Mistral-7B-Instruct-v0.1/` をあらかじめ配置（※実際のモデル構造に合わせる）
  - 確認: アプリ起動時に自動ロードが実行される
  - 確認: status が「準備完了」になる

### T2. 未ダウンロード時のサイレント動作

#### T2-1: オフライン（Wi-Fi なし）シナリオ
- [ ] Wi-Fi / モバイルデータをオフにした状態でアプリ起動
  - 確認: ネット通信エラーが出ない（エラーメッセージが表示されない）
  - 確認: SettingsView の Whisper / Bonsai が「未読込」状態で止まる
  - 確認: Console にネットワークエラーログがない

#### T2-2: ネット接続あり、モデル未ダウンロード
- [ ] Wi-Fi に接続した状態でアプリ起動
  - 確認: 自動ダウンロードが発生しない（status が「未読込」のまま）
  - 確認: Console に "WhisperKit.download()" や "hubApi.snapshot()" が出ない

### T3. 明示的なロード（「再読込」ボタン）の動作

#### T3-1: 「再読込」ボタンの操作
- [ ] SettingsView で Whisper の「再読込」ボタンを押す
  - 確認: ダウンロード開始（「ダウンロード中...」メッセージが表示される）
  - 確認: Console に download URL が出る
  - 確認: 完了後 status が「準備完了」になる

- [ ] 同じく Bonsai の「再読込」ボタン
  - 確認: ダウンロード開始（「モデル取得中...」メッセージ）
  - 確認: 進捗表示（ "モデル取得中 XX%" ）

#### T3-2: オフライン時の「再読込」
- [ ] Wi-Fi をオフにして「再読込」ボタンを押す
  - 確認: エラーメッセージが表示される（「ネットワークエラー」など）
  - これは **予期された動作**（明示的操作なので）

### T4. 録音フロー での状態確認

#### T4-1: モデル未ロード状態での録音開始
- [ ] SettingsView で Whisper が「未読込」のまま、メイン画面に戻る
- [ ] マイクボタンを押して録音開始
  - 確認: 「聞き取りモデルを読み込んでください」メッセージが出る
  - 確認: 録音は進まない（ガード条件で early return）

#### T4-2: モデルロード済み状態での録音
- [ ] SettingsView の「再読込」で Whisper をロード完了
- [ ] メイン画面で録音開始
  - 確認: 正常に録音・文字起こしが進む

### T5. UI 表示の整合性

#### T5-1: Status Badge の色分け
- [ ] 「未読込」 → 橙色（準備不足）
- [ ] 「準備完了」 → 緑色（OK）
- [ ] 「読込中」 → 橙色（進行中）
- [ ] 「失敗」 → 赤色（エラー）

#### T5-2: ボタン有効 / 無効状態
- [ ] 未ロード時: 「再読込」ボタンが有効（押せる）
- [ ] ロード中: 「再読込」ボタンが無効（「再読込中...」テキスト）
- [ ] ロード済み: 「再読込」ボタンが無効（既にロード済みなので）

### T6. キャッシュディレクトリの確認

#### T6-1: ローカル存在チェックの実装対象
- [ ] `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/<variant>/` の存在確認（WhisperKit 用）
  - 最小確認: 特定ファイル（e.g., `config.json`）の存在チェック
  - または: ディレクトリ自体の存在 + 内部ファイル数 > 0

- [ ] `~/.typetotalk/models/<model-id>/` の存在確認（Bonsai 用）
  - 最小確認: `config.json` / `model.safetensors` など重要ファイルの存在
  - または: ディレクトリ自体の存在 + サイズチェック

#### T6-2: 中途半端なダウンロード状態の対処
- [ ] ダウンロード失敗後の再試行（「再読込」ボタン）
  - 確認: 部分ダウンロードの再開 or 再開始
  - （Hub ライブラリはデフォルトで resume をサポート）

---

## 補足: 深掘り結果（A, B, C の特記事項）

### A. モデルローカル判定方法（深掘り結果）

#### WhisperKit (0.18.0)
**キャッシュパス**: `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/<variant>/`
- WhisperKit は `HubApi` の default `downloadBase` を使う
- デフォルトは `FileManager.default.urls(for: .documentDirectory, ...).first!.appending(component: "huggingface")`
- variant は "openai_whisper-tiny", "openai_whisper-base" など

**判定方法**:
```swift
// WhisperManager に追加すべき helper
private func isLocalModelAvailable(variant: String) -> Bool {
    let huggingfaceDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        .first!.appending(component: "huggingface")
    let modelPath = huggingfaceDir.appending(component: "models/argmaxinc/whisperkit-coreml/\(variant)")
    return FileManager.default.fileExists(atPath: modelPath.path)
}
```

**注意**: Hub ライブラリは snapshot() 内で「オフラインモード時にメタデータ確認」をするため、
単純なディレクトリ存在確認では不十分かもしれない。ただし、
WhisperKit 0.18.0 の `WhisperKit.download()` は `useOfflineMode` パラメータを渡さないため、
**アプリ側でローカル存在確認 → スキップ** が最も安全。

#### Bonsai (MLX-Swift + Hub)
**キャッシュパス**: `~/.typetotalk/models/` （BonsaiManager init で指定）
- Hub ライブラリの `HubApi.snapshot()` は、ダウンロードベース配下に `<model-id>` ディレクトリを作成
- 例: `~/.typetotalk/models/mlx-community/Mistral-7B-Instruct-v0.1/`

**判定方法**:
```swift
// BonsaiManager に追加すべき helper
private func isLocalModelAvailable(modelID: String) -> Bool {
    let baseDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".typetotalk/models")
    let modelPath = baseDirectory.appendingPathComponent(modelID)
    return FileManager.default.fileExists(atPath: modelPath.path)
}
```

**確認項目**: 
- ディレクトリ存在のみで良い（Hub は内部でメタデータキャッシュを持つ）
- または、特定ファイル（`config.json`）の存在確認でより厳密に

### B. ネット通信の回避可能性（深掘り結果）

#### WhisperKit.download() の動作
```swift
let modelFolder = try await hubApi.snapshot(
    from: repo, matching: [modelSearchPath]
)
```
- **現状**: `useOfflineMode` を渡していない → nil → 自動検出
- **問題**: 自動検出は `NetworkMonitor.shared.state.shouldUseOfflineMode()` に依存
  - これが正確に動作しない or 遅延する可能性がある
- **対策**: アプリ側で「ローカル存在確認」を先に行う → ローカルあれば download() を呼ばない

#### HubApi.snapshot() の HEAD リクエスト
HubApi.snapshot() 内部を確認すると：
```swift
let filenames = try await getFilenames(from: repo, revision: revision, matching: globs)
// → hub API の HEAD リクエストでリスト取得
for filename in filenames {
    try await downloader.download(...)
}
```
- **確認**: getFilenames() は HTTP ヘッダー情報を取得する（= ネット通信）
- **判定**: ローカル存在確認により getFilenames() を呼ばなくなれば、ネット通信は回避できる

**結論**: アプリ側で「ローカル存在確認 → あれば download()/snapshot() 呼び出しスキップ」が必須

### C. UI への影響（深掘り結果）

#### 現状の status 表示
```swift
var statusText: String {
    switch loadState {
    case .idle:
        return needsExplicitLoad ? "未読込" : "準備完了"
    case .loading:
        return loadingStatusText  // "ダウンロード中..."
    case .loaded:
        return needsExplicitLoad ? "未読込" : "準備完了"
    case let .failed(message):
        return "失敗: \(message)"
    }
}
```

#### 問題点
- "未読込" = ダウンロード未実施 or ロード失敗 の区別がない
- ユーザーが「なぜ未読込なのか」判断できない

#### 改善案
**案 1**: status を細分化（小カンマス）
```swift
case .idle:
    return "未読込（未ダウンロード）"  // or "オフライン中"
case .idle, .failed:
    return "準備不可（エラー）"
```

**案 2**: ローカル存在確認後、状態を分離
```swift
enum WhisperLoadState {
    case idle
    case notDownloaded  // ← 新規: ローカルに存在しない
    case loading
    case loaded(modelID: String)
    case failed(message: String)
}
```

**推奨**: **案 1 がシンプル**。statusText の返却時に、ローカル存在状況をテキストに反映する。
ただし、明示的なエラーメッセージ（ネットワークエラー）との区別は別途対応が必要。

---

## 結論: 不確かな点 & 安全側の指針

### 不確か
1. **Hub.snapshot() の完全なオフライン対応**: 
   - NetworkMonitor の自動検出が確実に動作するかは実測が必要
   - ローカルあってもリスト取得で HEAD リクエスト を投げるかもしれない

2. **WhisperKit のモデルディレクトリ構造**:
   - variant "openai_whisper-tiny" の実際のローカルパスが `openai_whisper-tiny/` なのか
     `tiny/` なのか、`coreml_models/openai_whisper-tiny/` なのか実測が必要
   - （GitHubを見て確認すべき）

### 安全側の指針
- **ローカル存在確認は必須**: アプリ側で download()/snapshot() を呼ぶ前に必ず確認する
- **ネット通信を期待しない**: ローカルあれば 100% オフラインで動作することを想定する
- **エラーパスは明示的に**: ダウンロード失敗時のメッセージは「なぜ失敗したのか」を明記する

