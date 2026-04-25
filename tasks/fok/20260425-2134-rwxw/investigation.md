# BonsaiManager.isLocalModelAvailable パス検出ズレ問題 - 詳細調査報告書

## 1. 関連ファイル一覧（パス + 役割）

| ファイルパス | 役割 | 関連行 |
|-----------|-----|-------|
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/BonsaiManager.swift` | Bonsai モデル管理（自動ロード、ローカル存在判定） | 29-32 (init), 147-164 (isLocalModelAvailable), 108-141 (ensureSelectedModelLoaded) |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/.build/checkouts/swift-transformers/Sources/Hub/HubApi.swift` | Hugging Face Hub API クライアント。実際のモデル保存パスを生成 | 378-380 (localRepoLocation), 614-696 (snapshot) |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/.build/checkouts/swift-transformers/Sources/Hub/Hub.swift` | Hub の公開インターフェース。RepoType 定義 | 80-87 (RepoType enum), 93-108 (Repo struct) |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift` | 呼び出し側 (Coordinator)。BonsaiManager 初期化と ensureSelectedModelLoaded 呼び出し | 215 (configureSelectedModel), 501 (ensureSelectedModelLoaded) |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/WhisperManager.swift` | Whisper モデル管理（参照実装：WhisperManager.isLocalModelAvailable との比較対象） | 131-146 (isLocalModelAvailable) |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/.build/checkouts/mlx-swift-lm/Libraries/MLXLMCommon/ModelFactory.swift` | loadModelContainer の定義 | loadModelContainer 関数シグネチャ |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/.build/checkouts/mlx-swift-lm/Libraries/MLXLMCommon/ModelConfiguration.swift` | ModelConfiguration（HubApi へのモデルID受け渡し方法） | Identifier enum (34-37行) |

---

## 2. 既存実装パターン（実装詳細を行番号付きで）

### 2.1 BonsaiManager.swift: modelsBaseDirectory と HuggingFaceHubDownloader の初期化

**BonsaiManager.swift:29-36**
```swift
init() {
    let baseDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".typetotalk/models")
    self.modelsBaseDirectory = baseDirectory
    self.downloader = HuggingFaceHubDownloader(downloadBase: baseDirectory)
    self.tokenizerLoader = HuggingFaceTokenizerLoader()
    logger.debug("init modelsBaseDirectory=\(baseDirectory.path, privacy: .public)")
}
```

**重要な点：**
- `modelsBaseDirectory = ~/.typetotalk/models` に設定（31行）
- その直後、`HuggingFaceHubDownloader(downloadBase: baseDirectory)` に同じパスを渡す（33行）

### 2.2 HuggingFaceHubDownloader (BonsaiManager.swift:209-231)

**BonsaiManager.swift:209-231**
```swift
private struct HuggingFaceHubDownloader: Downloader {
    private let hubApi: HubApi
    
    init(downloadBase: URL) {
        self.hubApi = HubApi(downloadBase: downloadBase)
    }
    
    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        let revision = revision ?? "main"
        return try await hubApi.snapshot(
            from: id,
            revision: revision,
            matching: patterns,
            progressHandler: progressHandler
        )
    }
}
```

**流れ：**
1. `HubApi(downloadBase: ~/.typetotalk/models)` を初期化（213行）
2. `download(id: modelID, ...)` が呼ばれると `hubApi.snapshot(from: id, ...)` を呼び出す（224-229行）
3. `id` は `"prism-ml/Ternary-Bonsai-8B-mlx-2bit"` のような形式

### 2.3 HubApi.snapshot と localRepoLocation の関係

**HubApi.swift:378-380**
```swift
func localRepoLocation(_ repo: Repo) -> URL {
    downloadBase.appending(component: repo.type.rawValue).appending(component: repo.id)
}
```

**HubApi.swift:614-623 (snapshot メソッドの最初の部分)**
```swift
@discardableResult
func snapshot(from repo: Repo, revision: String = "main", matching globs: [String] = [], progressHandler: @escaping (Progress) -> Void = { _ in })
    async throws -> URL
{
    let repoDestination = localRepoLocation(repo)
    let repoMetadataDestination =
        repoDestination
        .appending(path: ".cache")
        .appending(path: "huggingface")
        .appending(path: "download")
    // ...
}
```

**HubApi の snapshot 呼び出し系（HubApi.swift:707-708）**
```swift
@discardableResult
func snapshot(from repoId: String, revision: String = "main", matching globs: [String] = [], progressHandler: @escaping (Progress) -> Void = { _ in }) async throws -> URL {
    try await snapshot(from: Repo(id: repoId), revision: revision, matching: globs, progressHandler: progressHandler)
}
```

**重要な点：**
- `snapshot(from: "prism-ml/Ternary-Bonsai-8B-mlx-2bit")` が呼ばれると
- 内部で `Repo(id: repoId)` が生成される（Repo デフォルト初期化で type = .models）
- `localRepoLocation(repo)` で `downloadBase.appending(component: "models").appending(component: "prism-ml/Ternary-Bonsai-8B-mlx-2bit")` が生成される
- したがって **実際の保存パス = `~/.typetotalk/models/models/prism-ml/Ternary-Bonsai-8B-mlx-2bit/`**

### 2.4 BonsaiManager.isLocalModelAvailable: 問題となるパス検出ロジック

**BonsaiManager.swift:147-164**
```swift
private func isLocalModelAvailable(modelID: String) -> Bool {
    let modelDir = modelsBaseDirectory.appendingPathComponent(modelID)
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: modelDir.path, isDirectory: &isDir)
    guard exists, isDir.boolValue else {
        logger.debug("isLocalModelAvailable: dir missing path=\(modelDir.path, privacy: .public) exists=\(exists, privacy: .public) isDir=\(isDir.boolValue, privacy: .public)")
        return false
    }
    // 中途半端に作られた空ディレクトリへの防御。
    // `.DS_Store` のみのケースも除外したいが、HuggingFaceHubDownloader が
    // 配置するファイル名に依存して固定リストを書くと壊れやすいので、
    // 「.で始まる隠しファイルを除いた数」で判定する。
    let allContents = (try? FileManager.default.contentsOfDirectory(atPath: modelDir.path)) ?? []
    let visibleContents = allContents.filter { !$0.hasPrefix(".") }
    let hasContent = !visibleContents.isEmpty
    logger.debug("isLocalModelAvailable: path=\(modelDir.path, privacy: .public) all=\(allContents.count, privacy: .public) visible=\(visibleContents.count, privacy: .public)")
    return hasContent
}
```

**問題の核心：**
- `modelID = "prism-ml/Ternary-Bonsai-8B-mlx-2bit"` が渡される（BonsaiManager.swift:129 の呼び出しから）
- `modelsBaseDirectory.appendingPathComponent(modelID)` で構成されるパス = `~/.typetotalk/models/prism-ml/Ternary-Bonsai-8B-mlx-2bit`
- **しかし実際の保存位置 = `~/.typetotalk/models/models/prism-ml/Ternary-Bonsai-8B-mlx-2bit/`**（HubApi の localRepoLocation で `models/` が自動挿入される）
- 結果：存在しないパスを検査して `false` を返す（自動ロードがスキップされる）

### 2.5 WhisperManager の参照実装（比較対象）

**WhisperManager.swift:131-146**
```swift
private func isLocalModelAvailable(variant: String) -> Bool {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let modelDir = documents
        .appendingPathComponent("huggingface")
        .appendingPathComponent("models")
        .appendingPathComponent("argmaxinc")
        .appendingPathComponent("whisperkit-coreml")
        .appendingPathComponent(variant)
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: modelDir.path, isDirectory: &isDir), isDir.boolValue else {
        return false
    }
    // 中途半端に作られた空ディレクトリへの防御
    let contents = (try? FileManager.default.contentsOfDirectory(atPath: modelDir.path)) ?? []
    return !contents.isEmpty
}
```

**Whisper との重要な違い：**
- Whisper は `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/<variant>/` を直接検査（135-138行）
- Whisper は HubApi に `downloadBase: nil` を渡し、デフォルト（`~/Documents/huggingface`）を使う
- HubApi は `localRepoLocation` で自動的に `<type>/<id>` を付加する（HubApi.swift:378-380）
- WhisperManager は **その付加されたパス構造全体を手作業で再現している**（WhisperManager.swift:134-138）
- その結果、WhisperManager.isLocalModelAvailable は HubApi.snapshot の実際の保存位置と合致している

---

## 3. 影響範囲（呼び出し側 / 依存性）

### 3.1 呼び出し側の流れ

**TypeToTalkApp.swift:489-505 (synchronizeModelsForCurrentSettings)**
```swift
func synchronizeModelsForCurrentSettings() async {
    let bonsaiModelID = settings.resolvedBonsaiModelID
    let provider = activeFormatterProvider
    logger.debug("synchronizeModels: provider=\(String(describing: provider), privacy: .public) bonsaiModelID=\(bonsaiModelID, privacy: .public)")

    await whisper.ensureSelectedModelLoaded()
    bonsai.configureSelectedModel(bonsaiModelID)

    guard provider == .bonsai else {
        logger.debug("synchronizeModels: skip Bonsai autoload (provider != .bonsai)")
        return
    }
    await bonsai.ensureSelectedModelLoaded(modelID: bonsaiModelID)  // ← ここで isLocalModelAvailable が呼ばれる
    // 自動ロード結果は loadState/statusMessage 経由で sink され、
    // formatterStatusText に反映される（refreshFormatterStatusText）。
    refreshFormatterStatusText()
}
```

**TypeToTalkCoordinator.swift:277-282 (handleAppLaunch)**
- `coordinator.handleAppLaunch()` → `synchronizeModelsForCurrentSettings()` へ

**呼び出しパス：**
1. アプリ起動 → TypeToTalkApp.onAppear (562行) → handleAppLaunch (562行)
2. 録音開始前 → toggleRecording (349行) → synchronizeModelsForCurrentSettings (349行)
3. 設定変更時 → onChange handlers (567-571行) → synchronizeModelsForCurrentSettings

### 3.2 既存ダウンロード済みモデルへの影響

**既存の `~/.typetotalk/models/models/<repo>` 配下のファイル：**
```
~/.typetotalk/models/
└── models/
    └── prism-ml/
        └── Ternary-Bonsai-8B-mlx-2bit/
            ├── model.safetensors (2.3GB - ダウンロード済み)
            ├── config.json
            ├── tokenizer.json
            └── .cache/huggingface/download/ (メタデータ)
```

**修正による影響：**
- 修正案 A, B, C いずれでも、既存の 2.3GB ダウンロード済みファイルは **そのまま有効**（再ダウンロード不要）
- パス検出ロジックが修正されるだけなので、ファイル自体は移動しない
- 修正後に ensureSelectedModelLoaded が正しいパスを検査して `true` を返すだけ

### 3.3 複数インスタンスと他の Manager への波及

**BonsaiManager：**
- `@MainActor final class` なので、アプリ内に 1 インスタンス（TypeToTalkCoordinator.bonsai）
- 複数インスタンス化の心配なし

**WhisperManager：**
- 独立して動作。WhisperManager.isLocalModelAvailable の実装は既に正しい
- 修正対象外

**loadModel() と loadModelContainer() の関係：**
- BonsaiManager.loadModel (171-206行) が HuggingFaceHubDownloader.download を呼ぶ
- その結果のパスが loadModelContainer(from: downloader, ...) に渡される（182行）
- HubApi.snapshot で返されるパスは **既に正しい** (`~/.typetotalk/models/models/prism-ml/Ternary-Bonsai-8B-mlx-2bit`)
- 問題はあくまで **isLocalModelAvailable の判定ロジック** のみ

---

## 4. 過去の類似実装（git log より）

### 4.1 aac4a7a コミット（重要）: モデル自動DL停止、ローカル存在時のみ自動ロード

**Date:** 2026-04-25 16:07:51  
**主要変更：**
- BonsaiManager に isLocalModelAvailable(modelID:) を追加（問題となる実装がここで導入）
- ensureSelectedModelLoaded() に isLocalModelAvailable ガード追加
- **コミットメッセージでの判定パス記述：**
  ```
  - Bonsai:  ~/.typetotalk/models/<modelID>/
  ```
  **→ これが既に間違っている（`models/` 層を見落とし）**

- 検証記録：「実機で『Whisper(DL済) 自動ロード成功 / Bonsai(未DL) サイレント / 再読込ボタンでDL成功』確認」
  - **ただし、Bonsai ダウンロード済みのケースは検証されていない（未DL のサイレント return と、再読込ボタン経由のダウンロードのみ確認）**

### 4.2 a578b32 コミット（現在）: Bonsai 状態伝播＋自動ロード健全化

**Date:** 2026-04-25 21:00:15  
**主要変更：**
- isLocalModelAvailable に os.Logger を追加し、すべてのパスをログ化
- loadState ベースの重複/競合ガードを追加
- `.DS_Store` 等の隠しファイル除外ロジック改善
- **ただし、パス層数の問題（`models/` 挿入）は解決していない**

**コミット a578b32 での実装（BonsaiManager.swift:147-164）：**
```swift
let modelDir = modelsBaseDirectory.appendingPathComponent(modelID)
```
- modelsBaseDirectory = `~/.typetotalk/models`
- modelID = `"prism-ml/Ternary-Bonsai-8B-mlx-2bit"`
- 検査パス = `~/.typetotalk/models/prism-ml/Ternary-Bonsai-8B-mlx-2bit` ← **ここに models/ 層がない**

### 4.3 過去ログから見える問題の根源

- aac4a7a で isLocalModelAvailable を最初に実装した際、コミットメッセージの「判定パス: Bonsai: ~/.typetotalk/models/<modelID>/」 という記述が誤り
- 実際には HubApi が `models/` を自動挿入するため、判定対象パスは `~/.typetotalk/models/models/<modelID>/` であるべき
- a578b32 でさらに洗練されたが、根本的なパス層数の誤りは引き継がれたまま

---

## 5. 想定される副作用 / リスク（修正案 A/B/C 別評価）

### 修正案 A: `isLocalModelAvailable` で 1 段階追加（models/ を足す）

```swift
// 案A実装例
private func isLocalModelAvailable(modelID: String) -> Bool {
    let modelDir = modelsBaseDirectory
        .appendingPathComponent("models")            // ← 追加
        .appendingPathComponent(modelID)
    // ... 以下同じ
}
```

**メリット：**
- 変更範囲が最小（isLocalModelAvailable メソッド内のみ、3-4行）
- BonsaiManager 内の他のロジックに影響なし

**デメリット / リスク：**
- `modelsBaseDirectory` という変数名が `~/.typetotalk/models` を指しているのに、その下にさらに `models/` 層があるという不可解な構造が表面化
- 今後のメンテナンス時に「なぜここで models/ を足すのか」という疑問が生じやすい
- HubApi の内部仕様（`downloadBase` → `<repoType>/<repoID>` への自動付加）への暗黙的な依存が強まる
- 意味的な一貫性が低い

**既存 2.3GB ファイル流用：**
- ✅ 完全互換。既存パスはそのまま有効

**副作用範囲：**
- ✅ なし

---

### 修正案 B: `modelsBaseDirectory` を `~/.typetotalk` に変更

```swift
// 案B実装例（BonsaiManager.swift:29-35）
init() {
    let baseDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".typetotalk")        // ← models/ を削除
    self.modelsBaseDirectory = baseDirectory
    self.downloader = HuggingFaceHubDownloader(downloadBase: baseDirectory.appendingPathComponent("models"))
    self.tokenizerLoader = HuggingFaceTokenizerLoader()
    logger.debug("init modelsBaseDirectory=\(baseDirectory.path, privacy: .public)")
}

// isLocalModelAvailable は変更なし（HubApi の自動付加と一致）
private func isLocalModelAvailable(modelID: String) -> Bool {
    let modelDir = modelsBaseDirectory
        .appendingPathComponent("models")             // これで HubApi と一致
        .appendingPathComponent(modelID)
    // ... 以下同じ
}
```

**メリット：**
- 「modelsBaseDirectory = ~/.typetotalk」という名前がより自然（ディレクトリツリーの論理的な親階層）
- HubApi へ渡す downloadBase を明示的に制御可能
- 将来的に他のコンポーネント（キャッシュ、ログ等）を `.typetotalk/` 直下に配置する場合に拡張しやすい

**デメリット / リスク：**
- HuggingFaceHubDownloader の初期化パスが変わる（33行）
  ```swift
  self.downloader = HuggingFaceHubDownloader(downloadBase: baseDirectory.appendingPathComponent("models"))
  ```
  → 複雑さが増す
- 変更行数が増える（init 内、isLocalModelAvailable 内で計 5-6 行）

**既存 2.3GB ファイル流用：**
- ✅ 完全互換。既存パスはそのまま有効（HuggingFaceHubDownloader への downloadBase 値が変わるだけで、HubApi の snapshot ロジックは同じ）

**副作用範囲：**
- ✅ BonsaiManager 内部のみ。呼び出し側は変更不要

---

### 修正案 C: HubApi.localRepoLocation を public 化し、BonsaiManager が直接利用

```swift
// HubApi.swift の localRepoLocation を public に（現在は private）
public func localRepoLocation(_ repo: Repo) -> URL {
    downloadBase.appending(component: repo.type.rawValue).appending(component: repo.id)
}

// BonsaiManager.swift での利用
private func isLocalModelAvailable(modelID: String) -> Bool {
    let repo = Hub.Repo(id: modelID)  // デフォルト .models タイプ
    let modelDir = downloader.hubApi.localRepoLocation(repo)  // ← HubApi から直接取得
    // ... 以下同じ
}
```

**問題：**
- `HuggingFaceHubDownloader` は `private` 構造体で、`hubApi` メンバへのアクセスが不可（29行参照）
- HubApi の localRepoLocation は **外部 API として公開されていない**（設計上、内部実装詳細）
- swift-transformers ライブラリの公開 API 仕様に変更が必要（他のユーザーへの互換性影響）

**メリット（仮定上）：**
- 単一の真実の源（HubApi）から直接パスを取得でき、重複実装を避けられる

**デメリット / リスク：**
- swift-transformers は外部ライブラリ（.build/checkouts 経由で管理）
- public API を追加するには、ライブラリの変更が必要
- **実用性が低い**（外部ライブラリ変更のコストが大きい）

**既存 2.3GB ファイル流用：**
- ✅ 完全互換（パス検査ロジックの改善のみ）

**副作用範囲：**
- swift-transformers のライブラリ API が変わる場合、他の使用者への影響あり

---

## 6. 制約条件（HubApi 内部仕様への依存度、後方互換、既存 DL ファイル流用可否）

### 6.1 HubApi 内部仕様への依存度

**HubApi.snapshot の実装フロー（HubApi.swift:614-696）：**
1. `snapshot(from: repoId: String, ...)` が呼ばれる → 重載版へ
2. `Repo(id: repoId)` 生成（タイプ デフォルト .models）（708行）
3. `localRepoLocation(repo)` で実際の保存パスを計算（617行）
   ```swift
   let repoDestination = localRepoLocation(repo)
   // = downloadBase.appending(component: "models").appending(component: repoId)
   ```

**BonsaiManager の依存性：**
- aac4a7a 以降、BonsaiManager は **HubApi の localRepoLocation の実装詳細に依存している**
- 具体的には：「`downloadBase` → `<downloadBase>/<repoType>/<repoID>` へ自動変換される」という仕様
- この仕様が変わった場合、isLocalModelAvailable が破損する

**リスク評価：**
- swift-transformers は Hugging Face 公式ライブラリ
- localRepoLocation のロジック（Path = downloadBase + /models/ + repoId）は HubApi の本質的な動作
- 今後のバージョンで破壊的変更の可能性は低い

### 6.2 swift-transformers 公開 API の有無

**HubApi.localRepoLocation：**
- **private 関数**（HubApi.swift:378）
- 外部から直接利用できない
- 修正案 C はこの制約により実用的でない

**swift-transformers の設計思想：**
- `HubApi.snapshot()` は公開
- snapshot が返すパスが真実の源
- isLocalModelAvailable は**外部責任**ではなく、**呼び出し側が保証すべき**という立場

### 6.3 後方互換性

**修正案 A, B, C すべて：**
- ✅ 既存ダウンロード済みファイル（`~/.typetotalk/models/models/<repo>`）は **そのまま有効**
- パス判定ロジックの修正であり、ファイル移動やリネームは不要
- 既存ユーザーが修正版をインストール後、自動ロードが正しく動作するようになるだけ

**破壊的変更なし。**

### 6.4 既存 DL ファイル流用可否

**状況：**
- 2.3GB のダウンロード済みファイルが `~/.typetotalk/models/models/prism-ml/Ternary-Bonsai-8B-mlx-2bit/` に存在
- 修正後、isLocalModelAvailable が正しいパスを検査して存在を認識
- loadModel → loadModelContainer が同じ downloader を使用
- downloader.download(id: modelID, ...) が HubApi.snapshot を呼び出し
- HubApi.snapshot は既存ファイルを検出し、キャッシュ確認（etag, commit hash）後、再ダウンロードを**スキップ**（HubApi.swift:544-549）

**流用可否：**
- ✅ **完全流用可能**。マイグレーション不要

**検証条件：**
- HubApi.snapshot の etag / commit hash チェックロジック（544-577行）が正しく動作することが前提

---

## 7. テスト戦略（ビルド確認 + 実機での自動ロード確認手順）

### 7.1 ビルド確認

**手順：**
```bash
cd /Users/tamekuniz/GitHub/tamekuniz/TTT

# Swift Lint / Format チェック
swift package describe

# ビルド確認
xcodebuild -scheme TypeToTalk -configuration Debug build

# ユニットテスト（あれば）
swift test
```

**確認ポイント：**
- ✅ コンパイルエラーなし
- ✅ コンパイル警告なし

### 7.2 実機での自動ロード確認（修正後の検証シナリオ）

**前提条件：**
- 実機（M1/M2 Mac）に TTT アプリがインストール済み
- 既存ダウンロード済みモデル `~/.typetotalk/models/models/prism-ml/Ternary-Bonsai-8B-mlx-2bit/` が存在（2.3GB）
- 修正コード適用

**シナリオ 1: 起動時の自動ロード確認**

```
1. アプリ起動
2. メインウインドウ観察
   - Formatter ステータスが「準備完了」と表示されるか？
   - または「読込中」から「準備完了」へ遷移するか？
3. ログ確認（下記参照）
   - isLocalModelAvailable パスが正しいか
   - available = true と記録されるか
   - loadModel が正常に完了するか
```

**シナリオ 2: 設定変更による再ロード**

```
1. 設定画面で Formatter を「Bonsai」に変更
   → BonsaiManager.configureSelectedModel() が呼ばれる
   → TypeToTalkCoordinator.synchronizeModelsForCurrentSettings() 実行
2. メインウインドウで Formatter ステータス変化観察
3. ログで isLocalModelAvailable が再度呼ばれることを確認
```

**シナリオ 3: ネットワークオフラインでの確認**

```
1. Wi-Fi を OFF
2. アプリ再起動
3. Formatter ステータスが「準備完了」と表示される（キャッシュから自動ロード）
4. インターネット接続を再開
   → オフラインでも自動ロードできることを確認
```

### 7.3 ログ取得方法

**Console.app での確認（Apple 標準）：**
```bash
log show --predicate 'subsystem == "com.tamekuniz.TypeToTalk"' --level debug
```

**リアルタイムストリーミング：**
```bash
log stream --predicate 'subsystem == "com.tamekuniz.TypeToTalk"' --level debug
```

**期待されるログ出力（修正案 A 適用時）：**

```
com.tamekuniz.TypeToTalk: [Bonsai] init modelsBaseDirectory=/Users/XXX/.typetotalk/models

com.tamekuniz.TypeToTalk: [Bonsai] ensureSelectedModelLoaded modelID=prism-ml/Ternary-Bonsai-8B-mlx-2bit canAutoLoad=true loadState=idle

com.tamekuniz.TypeToTalk: [Bonsai] ensureSelectedModelLoaded: isLocalModelAvailable=true modelID=prism-ml/Ternary-Bonsai-8B-mlx-2bit

com.tamekuniz.TypeToTalk: [Bonsai] isLocalModelAvailable: path=/Users/XXX/.typetotalk/models/models/prism-ml/Ternary-Bonsai-8B-mlx-2bit all=4 visible=3

com.tamekuniz.TypeToTalk: [Bonsai] ensureSelectedModelLoaded: load success modelID=prism-ml/Ternary-Bonsai-8B-mlx-2bit
```

**確認ポイント：**
- `isLocalModelAvailable: path=.../.typetotalk/models/models/prism-ml/...` → パスが正しいか
- `isLocalModelAvailable=true` → 判定が true か（修正前は false）
- `load success` → ロード成功か（修正前は `ensureSelectedModelLoaded: skipped (isLocalModelAvailable=false)` で終了）

### 7.4 ビルド確認追加項目（修正案別）

**修正案 A の場合：**
- 「models/」層の追加が一意に定まるか確認
- 他の appendingPathComponent 呼び出しと整合性確認

**修正案 B の場合：**
- HuggingFaceHubDownloader へ渡される downloadBase が `~/.typetotalk/models` に正しく設定されているか
- isLocalModelAvailable 内で同じ `models/` 層を追加しているか

**修正案 C の場合：**
- HubApi.localRepoLocation の public 化による外部ライブラリ API 変更
- 別プロジェクトでの互換性確認が必要（この TTT プロジェクト外）

---

## 修正案の比較表

| 項目 | 修正案 A | 修正案 B | 修正案 C |
|-----|---------|---------|---------|
| **実装行数** | 1 行追加（models/ をappend） | 5-6 行変更（init + isLocalModelAvailable） | 3-5 行変更 + ライブラリ API 変更 |
| **変更範囲** | isLocalModelAvailable メソッド内 | BonsaiManager.init + isLocalModelAvailable | BonsaiManager + HubApi public API |
| **HubApi 内部仕様変更への耐性** | 低（localRepoLocation ロジック変更で破損） | 低（同上） | 中（代替 API 実装で対応可能だが、本質的には同じ依存） |
| **既存 2.3GB ファイル流用** | ✅ 完全互換 | ✅ 完全互換 | ✅ 完全互換 |
| **命名・抽象化の妥当性** | △ 低（modelsBaseDirectory + models/ は不自然） | ○ 高（modelsBaseDirectory = ~/.typetotalk は自然） | ✅ 最高（HubApi から直接取得） |
| **副作用範囲** | なし | なし | HubApi public API 変更 |
| **保守性・可読性** | 低（「なぜ models/を足すのか」が不明） | 高（階層構造が明確） | 最高（外部 API が真実の源） |
| **実装複雑性** | 最小 | 中 | 中（ただし外部ライブラリ変更が必要） |

---

## 推奨案

**修正案 B を推奨します。**

### 理由

1. **命名・設計の妥当性が高い**
   - `modelsBaseDirectory = ~/.typetotalk` という名前が、ディレクトリツリーの論理的な親階層を正確に表す
   - 「.typetotalk 配下に models フォルダがあり、その中に各リポジトリが置かれる」という構造が明確
   - 将来的に `.typetotalk/` 直下にログ、キャッシュ、設定等を配置する場合に拡張しやすい

2. **HubApi 内部仕様への依存度が修正案 A と同等**
   - 修正案 C が推奨できない理由（public API 化のコスト）と同じ理由で、修正案 A, B も HubApi の localRepoLocation ロジックに依存
   - ただし修正案 B は、その依存を「明示的な downloadBase 設定」として顕在化させるため、将来の変更に対する耐性が若干高い

3. **実装コストが妥当**
   - 修正案 A より数行多いが（3-4 行追加 vs 1 行追加）、その代わりに可読性と拡張性が大幅に向上
   - 修正案 C は外部ライブラリ変更が必要で、リリースコストが高い

4. **既存ファイル流用が確実**
   - 修正案 A, B, C すべてで既存 2.3GB ファイルが流用可能だが、修正案 B は HuggingFaceHubDownloader への入力が明示的に制御されるため、エラーが起きた場合のデバッグが容易

5. **チームの将来の保守負荷を軽減**
   - 「modelsBaseDirectory に models/ を足すのはなぜ？」という疑問が生じにくい
   - コードレビュー時に「.typetotalk/ 直下に新しいコンポーネントを追加する際も同じ親パスを使う」という意思統一が容易

---

## 結論

**パス検出ズレの根本原因：**
- BonsaiManager.isLocalModelAvailable が、HubApi.snapshot の内部的なパス生成ロジック（downloadBase → downloadBase/models/<repoId>） を見落とし、ダウンロード後の実際の保存パス（~/.typetotalk/models/models/<repoId>/）と、検査するパス（~/.typetotalk/models/<repoId>/）がズレている

**修正案評価：**
- **修正案 A（isLocalModelAvailable で 1 段階追加）：** 実装最小だが、命名と実装のズレが残る
- **修正案 B（modelsBaseDirectory を ~/.typetotalk に変更）：** 命名・設計・拡張性で最適。推奨案
- **修正案 C（HubApi.localRepoLocation を public 化）：** 理想的だが、外部ライブラリ変更コストが大きく現実的でない

**修正案 B の実装手順：**
1. BonsaiManager.init の `modelsBaseDirectory` を `~/.typetotalk` に変更
2. HuggingFaceHubDownloader 初期化時、downloadBase に `models/` 層を追加
3. isLocalModelAvailable で同じく `models/` 層を追加（修正案 A と同じ）
4. ビルド確認 + 実機テスト（シナリオ 1-3）実施
5. ログで isLocalModelAvailable が true を返すことを確認
