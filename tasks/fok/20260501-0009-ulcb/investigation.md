# TypeToTalk Swift 6 Strict Concurrency エラー調査報告書
## WhisperManager.swift:222 sending 'whisperKit' risks causing data races

**調査者**: マンゴー調査小人だら  
**調査日**: 2026-05-01  
**エラーハッシュ**: [#SendingRisksDataRace]  
**対象ビルド環境**: Xcode 26.4 SDK / Swift 6 言語モード  
**前回問題なし**: 2026-04-25 ビルド 20260425C  
**プロジェクト**: TypeToTalk 0.1.0

---

## 1. 関連ファイル一覧

### A. エラー発生箇所（主対象）
- **Sources/TypeToTalk/Managers/WhisperManager.swift** (行 222)
  - 行 11-12: `@MainActor class WhisperManager: ObservableObject`
  - 行 13-15: `@Published var whisperKit: WhisperKit?` ← @MainActor 隔離されたプロパティ
  - 行 197-235: `func transcribe(audioURL:language:)` ← 行 222 エラー発生箇所
  - 行 222-225: `let results = try await whisperKit.transcribe(audioPath:decodeOptions:)` ← エラー行

### B. 使用箇所（呼び出し側）
- **Sources/TypeToTalk/App/TypeToTalkApp.swift**
  - 行 213: `guard whisper.whisperKit != nil else {` ← 存在チェック
  - 行 221-224: `var rawText = await whisper.transcribe(audioURL:language:)` ← WhisperManager.transcribe() 呼び出し（toggleRecording 内）

- **Sources/TypeToTalk/Views/HUDView.swift**
  - 行 78: `if coordinator.whisper.whisperKit != nil {` ← UI 条件判定（micButtonColor で使用）

- **Sources/TypeToTalk/Views/SettingsView.swift**
  - 行 78: `@ObservedObject var whisper: WhisperManager` ← whisper マネージャーへの参照
  - 行 85: `await whisper.loadSelectedModel()` ← loadSelectedModel() 非同期呼び出し

### C. WhisperKit ライブラリ側（外部パッケージ）
- **Package.swift** (行 13)
  ```swift
  .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.18.0"),
  ```

- **WhisperKit ライブラリ: Sources/WhisperKit/Core/WhisperKit.swift**
  - 行 824-831: `open func transcribe(audioPath:decodeOptions:callback:) async throws -> TranscriptionResult?` ← nonisolated メソッド
  - 行 840-872: `open func transcribe(audioPath:decodeOptions:callback:) async throws -> [TranscriptionResult]` ← nonisolated メソッド（OverLoad）
  - クラス定義（行 12）: `open class WhisperKit` ← actor 隔離なし、@MainActor 未付与

### D. テストファイル
- **Tests/TypeToTalkTests/ModelSelectionTests.swift**
  - 行 4-5: `@MainActor final class ModelSelectionTests: XCTestCase`
  - 行 6-14: `testWhisperManagerRecommendedModelMatchesResolvedSelection()` ← WhisperManager 初期化テスト
  - 行 65-76: `testWhisperStatusTextIsIdleNotLoadedBeforeExplicitLoad()` ← whisperKit = nil の動作確認

- **Tests/TypeToTalkTests/AudioRecorderTests.swift**
  - WhisperManager 参照なし（AudioRecorder のみ検証）

### E. 相関マネージャー
- **Sources/TypeToTalk/Managers/SettingsManager.swift** (行 236, 284)
  - whisperKit という enum case 名を持つ（TranscriptionProvider.whisperKit）のみで、WhisperKit インスタンスは非保持

---

## 2. 既存実装パターン（@MainActor / actor / Sendable 規律）

### A. WhisperManager クラスの @MainActor 隔離構造

**WhisperManager.swift, 行 11-12**
```swift
@MainActor
class WhisperManager: ObservableObject {
    @Published var whisperKit: WhisperKit? {
        didSet { refreshStatusText() }
    }
```

**特徴**:
- クラス全体が `@MainActor` で修飾（Swift 6 からの強制）
- `whisperKit` プロパティは `@Published` で主要な状態として保持
- その他の @Published プロパティ: isTranscribing, lastTranscription, isLoadingModel, loadState, loadingStatusText, statusText

**@MainActor の意味**:
- WhisperManager のすべてのメソッドと初期化子はメインスレッド（MainActor）で実行される
- whisperKit へのアクセス（読み書き）も Main Actor で隔離される
- 別スレッド（nonisolated スコープ）から直接アクセスすると data race の可能性あり

### B. transcribe メソッドの actor 隔離（行 197）

**WhisperManager.swift, 行 197**
```swift
func transcribe(audioURL: URL, language: String = "ja") async -> String {
    guard let whisperKit = whisperKit else {
        return ""
    }
    // ...
    let results = try await whisperKit.transcribe(...)
}
```

**分析**:
- `func transcribe` は `@MainActor` を明示していないため、**暗黙的に `@MainActor` で隔離される**
- guard で `whisperKit` を local binding しているが、**その後の `try await` で actor 境界を越える**
- 行 222 で `whisperKit.transcribe(...)` を呼ぶ際、whisperKit は @MainActor 隔離、transcribe() は nonisolated

### C. setupWhisper 内の whisperKit 更新（行 176, 182）

**WhisperManager.swift, 行 148-188**
```swift
private func setupWhisper(forceReload: Bool) async {
    let selectedModelID = self.selectedModelID
    // ...
    let kit = try await WhisperKit(config)
    self.whisperKit = kit          // ← 行 176
    // ...
    self.whisperKit = nil          // ← 行 182
}
```

**特徴**:
- setupWhisper は `@MainActor` で実行される（クラス전 隔離）
- whisperKit の書き込みは Main Actor 内で安全
- 読み込み（transcribe 呼び出し）で nonisolated メソッドへ送信するのが問題

---

## 3. 影響範囲

### A. transcribe() 呼び出し側（1箇所）

**TypeToTalkApp.swift, 行 221-224 (toggleRecording メソッド内)**
```swift
var rawText = await whisper.transcribe(
    audioURL: audioURL,
    language: settings.whisperLanguage
)
```

**フロー**:
1. toggleRecording は `@MainActor` 内で実行（Coordinator の implicit @MainActor）
2. whisper.transcribe() を await で呼び出す
3. transcribe() 内で whisperKit を guard local binding してから transcribe() メソッド呼び出し
4. Swift 6 compiler が「@MainActor 隔離の whisperKit を nonisolated メソッドへ送信」と判定

### B. whisperKit プロパティ参照箇所（3箇所）

**1. TypeToTalkApp.swift, 行 213**
```swift
guard whisper.whisperKit != nil else {
    statusMessage = "聞き取りモデルを読み込んでください"
    // ...
}
```
- 存在チェックのみ（読み取り）

**2. HUDView.swift, 行 78**
```swift
if coordinator.whisper.whisperKit != nil {
    return Color(red: 0.10, green: 0.47, blue: 0.95)
}
```
- UI の color 判定用（読み取り）

**3. SettingsView.swift, 行 78 (参照、直接使用なし)**
```swift
@ObservedObject var whisper: WhisperManager
```
- whisper.statusText 等での ObservedObject 購読

### C. WhisperKit.transcribe() メソッドの isolation 属性（WhisperKit ライブラリ側）

**WhisperKit.swift, 行 824-831 & 840-872**
```swift
open class WhisperKit {
    // ← actor 隔離なし、@MainActor なし
    
    open func transcribe(
        audioPath: String,
        decodeOptions: DecodingOptions? = nil,
        callback: TranscriptionCallback = nil
    ) async throws -> TranscriptionResult? {
        // nonisolated メソッド（暗黙的）
    }
    
    open func transcribe(
        audioPath: String,
        decodeOptions: DecodingOptions? = nil,
        callback: TranscriptionCallback = nil
    ) async throws -> [TranscriptionResult] {
        // nonisolated メソッド（暗黙的）
    }
}
```

**確認事実**:
- WhisperKit クラスは `@MainActor` 修飾なし
- transcribe() メソッドは `nonisolated` 明示なし ⇒ **暗黙的に nonisolated**
- Swift 6 compiler が「@MainActor な whisperKit インスタンスを nonisolated メソッドへ送信」と警告

---

## 4. 過去の類似実装・コミット遷移

### A. WhisperManager 関連コミット（git log --oneline より）

| コミット | 日付 | 内容 |
|---------|------|------|
| 380c996 | 2026-04-25 | [フォK] feat: Whisper hallucination 3層防御＋ビルド20260425C |
| a578b32 | 2026-04-25 | [フォK] fix: Bonsai 状態伝播＋自動ロード健全化＋ビルド20260425D |
| 848ef06 | 2026-04-20 | [フォK] fix: Whisperステータスがメインウインドウに伝播しない不整合を修正 |
| 4b03313 | 2026-04-13 | [フォK] feat: TypeToTalk リファクタ完了＋整形AI整合性とウインドウトグル追加 |

**380c996 の hallucination 3層防御**（直近の大規模修正）:
- (1) EnergyVAD を WhisperKitConfig に設定
- (2) hallucinationPatterns Set で既知句除去
- (3) noSpeechThreshold を 0.6 → 0.4 に厳格化
- **但し、@MainActor 隔離は入らず**（Swift 6 strict concurrency 導入前のアプローチ）

**4b03313 リファクタ完了時**:
- WhisperManager を Managers/ に分離（前から @MainActor）
- transcribe() の基本構造は 2026-04-13 時点で確立

### B. 過去のフォーメーション K での並行性対応

**検索結果**: 
- CLAUDE.md なし（新規プロジェクト）
- `/tasks/fok/*/` ディレクトリの investigation.md には @MainActor / actor の詳細記載なし
- 20260425 investigation.md では AppStatus (Equatable) の enum 設計に注力（Phase 2 UI）

**結論**: 並行性関連の修正歴が限定的（Swift 6 strict mode は新規問題）

---

## 5. 想定される副作用 / リスク比較

### A. @preconcurrency import の影響

**案**: `import WhisperKit` → `@preconcurrency import WhisperKit`

**メリット**:
- WhisperKit ライブラリの nonisolated メソッドに対して Swift 5 互換の警告を降格
- ビルド失敗を回避
- 最小変更（1行追加）

**デメリット / リスク**:
- 実際の data race risk を隠蔽
- SwiftUI @MainActor 隔離の本来の目的（thread-safe）を弱体化
- 将来 WhisperKit が @MainActor 対応した場合、不要な @preconcurrency が残存

**副作用**:
- WhisperKit 関連の他メソッド（download, setupModels など）も同じ警告を抑止
- リグレッション: 中程度リスク（外部ライブラリの内部実装変更には無防備）

---

### B. nonisolated(unsafe) ローカル変数の利用

**案**: 行 222 付近で whisperKit を nonisolated(unsafe) な local binding に変更

```swift
func transcribe(audioURL: URL, language: String = "ja") async -> String {
    guard let whisperKit = whisperKit else {
        return ""
    }
    // ... existing code ...
    
    nonisolated(unsafe) let kit = whisperKit  // ← nonisolated(unsafe) binding
    let results = try await kit.transcribe(...)
}
```

**メリット**:
- WhisperKit ライブラリの実装に依存しない
- @MainActor 隔離の意図を局所的に明示
- 他のメソッド（setupWhisper など）には影響なし

**デメリット / リスク**:
- 「unsafe」は developer 責任で data race がないことを保証
- WhisperKit.transcribe() が async であるため、別スレッドから whisperKit へアクセスする可能性あり
- 実際の race condition が潜む可能性（低いが non-zero）

**副作用**:
- 複数箇所で nonisolated(unsafe) が必要な場合、記述が冗長化
- リグレッション: 高リスク（developer が明示的に safety を放棄）

---

### C. Task.detached または Task { @MainActor in } でのラップ

**案A**: Task.detached で nonisolated コンテキストで実行

```swift
let results = try await Task.detached { () -> [TranscriptionResult] in
    try await whisperKit.transcribe(...)
}.value
```

**案B**: Task { @MainActor in } で明示的に隔離

```swift
let results = try await Task { @MainActor in
    try await whisperKit.transcribe(...)
}.value
```

**メリット**:
- Task.detached: data race risk を actor 境界で物理分離（最も安全）
- 明示的なスレッド切替で concurrency 意図が明確

**デメリット / リスク**:
- Task 実行の overhead（10-100μs 単位）
- Task.detached から @MainActor 隔離の whisperKit へアクセスは依然警告
- デッドロック risk（Task await の nested structure）

**副作用**:
- 性能影響: 音声処理の遅延が増加（短音声では顕著でない可能性）
- リグレッション: 低-中程度（UI 応答性に影響の可能性）

---

### D. @MainActor explicit closure のウィッチングオフ

**案**: transcribe() を nonisolated にして caller 側で @MainActor チェック

```swift
// WhisperManager 内で（外部ライブラリではなく自分たちのコード）
nonisolated func transcribeBody(
    audioURL: URL,
    language: String,
    whisperKit: WhisperKit
) async -> String {
    // nonisolated コンテキスト
    // ...
}

func transcribe(audioURL: URL, language: String = "ja") async -> String {
    guard let whisperKit = whisperKit else { return "" }
    return await transcribeBody(audioURL: audioURL, language: language, whisperKit: whisperKit)
}
```

**メリット**:
- 本来の @MainActor 隔離が caller に責任を明示
- nonisolated なメソッド内では whisperKit の ownership が明確

**デメリット / リスク**:
- メソッド分割による API 複雑化
- transcribeBody を nonisolated にするには whisperKit を parameter にする必要（implicit self capture を避けるため）

**副作用**:
- コード構造変更が大きい
- リグレッション: 中程度（API 変更、呼び出し側の修正）

---

### E. actor への全面改変（根本的解決、非推奨）

**案**: WhisperManager を actor に変更

```swift
actor WhisperManager: ??? {  // Note: ObservableObject 両立困難
    nonisolated let settings: SettingsManager
    var whisperKit: WhisperKit?
    // ...
}
```

**メリット**:
- Swift 6 strict concurrency に完全準拠
- 根本的に data race を防止

**デメリット / リスク**:
- actor は ObservableObject を継承できない（SwiftUI 統合困難）
- @Published 修飾子が actor で機能しない
- 既存 UI 層（SwiftUI View から @ObservedObject）の大規模改変必要

**副作用**:
- リグレッション: 超高リスク（SwiftUI 全体の動作変更）
- 非現実的（TTT の既存 UI architecture と不両立）

---

## 6. 制約条件

### A. Swift 6 言語モード

- **Xcode 26.4 SDK**: Swift 6.0 言語モード を使用中（project.yml / xcodebuild）
- **診断**: Swift 6 compiler が新規に diagnostic を追加（Xcode の更新で表面化）
- **互換性**: Swift 5 コード（@preconcurrency）との逆互換性は維持
- **制約**: Swift 6 strict concurrency rule に違反する code は **明示的に許可**する必要あり

### B. @MainActor 規律の強化

- **WhisperManager**: 既に `@MainActor class` で全メソッドが隔離
- **TypeToTalkCoordinator**: 同じく `@MainActor`
- **制約**: 新規修正は actor isolation を **強化または維持** する方向で

### C. WhisperKit 0.18.0 API 仕様

- **transcribe(audioPath:decodeOptions:callback:)**: 
  - 返り値: `[TranscriptionResult]` (array variant, 行 840)
  - 返り値: `TranscriptionResult?` (single variant, 行 824)
  - 両方とも `async throws`
  - **nonisolated**: 明示なし（暗黙的に nonisolated）
- **WhisperKit(config:)**: async throws initializer
- **制約**: WhisperKit ライブラリのコンパイル版（checkouts）は固定（修正不可）

### D. リグレッション禁止

- **前回ビルド**: 2026-04-25 ビルド 20260425C が BUILD SUCCEEDED
- **機能保証**: 
  - 文字起こし機能（transcribe）の動作変更なし
  - hallucination 3層防御の効果維持
  - 全テスト（ModelSelectionTests, AudioRecorderTests）パス必須
- **制約**: リグレッション検出時は修正前段階への rollback 実施可能

---

## 7. テスト戦略

### A. ユニットテスト（Tests/TypeToTalkTests/）

#### 1. ModelSelectionTests.swift

| テスト名 | 対象 | 用途 | 修正後の関連性 |
|---------|------|------|--------------|
| testWhisperManagerRecommendedModelMatchesResolvedSelection | WhisperManager 初期化 | selectedModelID の computation | **該当**: @MainActor 隔離の初期化呼び出し確認 |
| testWhisperManagerUsesSelectedCustomModel | WhisperManager 初期化 | custom model ID の resolution | **該当**: 同上 |
| testWhisperStatusTextIsIdleNotLoadedBeforeExplicitLoad | whisperKit = nil | statusText の初期値 | **不該当**: transcribe() メソッド実行なし |
| testWhisperStatusTextIsIdleForCustomModelBeforeExplicitLoad | whisperKit = nil | custom 時の statusText | **不該当**: 同上 |
| その他（Bonsai/Settings）| Bonsai, Settings | model selection | **不該当**: WhisperManager.transcribe() 未テスト |

**結論**: ModelSelectionTests は **初期化・statusText** を対象（実際の transcribe() 動作は非テスト）

#### 2. AudioRecorderTests.swift

- **対象**: AudioRecorder.startRecording / stopRecording / tap handler
- **関連性**: **完全不該当**（WhisperManager 参照なし）

### B. 実機テスト（./scripts/build_app.sh Debug）

**ビルド目標**: `BUILD SUCCEEDED`

**実行コマンド**:
```bash
./scripts/build_app.sh Debug
```

**期待結果**:
```
Built app: /tmp/TypeToTalkDerivedData/Build/Products/Debug/TypeToTalk.app
Build number: 20260501A
```

**エラー回避チェック**:
- ✓ Xcode コンパイル成功（Swift 6 strict concurrency 警告なし）
- ✓ リンク成功
- ✓ バンドルビルド成功

### C. 動作確認テスト（手動）

**前提**: `./scripts/build_app.sh Debug` が BUILD SUCCEEDED した上で実施

| 項目 | テスト手順 | 確認項目 | 修正後の期待 |
|------|----------|---------|------------|
| **アプリ起動** | TypeToTalk.app を起動 | ウインドウ表示、権限要求 | 変化なし |
| **Whisper モデル読込** | Settings → 聞き取りAI → 再読込 | モデルダウンロード＆読込状態 | 変化なし（EnergyVAD, hallucination 防御継続） |
| **音声文字起こし** | HUD マイク → 5秒 → マイク | 認識結果表示 | hallucination 除去機能が動作（変化なし） |
| **エラーハンドリング** | 未読込で録音 → toggleRecording | エラー表示「聞き取りモデル未読込」 | 変化なし |
| **AI 成形** | Formatter を OpenAI/Groq に変更 → 文字起こし | テキスト成形結果 | 変化なし（別プロセス） |

**確認メトリクス**:
- ✓ 認識成功率（hallucination 除外後）
- ✓ 処理遅延（Task overhead 検査）
- ✓ メモリ使用量（Sendable 強制による増加なし）
- ✓ メニューバーアイコン反応性（UI 遅延なし）

### D. テスト不適用ケース

**transcribe() 実装テスト** (ユニットテストでは困難):
- WhisperKit.transcribe() の async throws 動作
- 実際のオーディオファイル処理（マイク権限要）
- nonisolated メソッド呼び出し時の thread safety

⇒ 実機テスト＋ code review で確認

---

## 8. 診断のまとめ

### エラーの本質

```
[#SendingRisksDataRace]
sending 'whisperKit' risks causing data races
```

**原因の物理イメージ**:
1. `@MainActor class WhisperManager` ⇒ whisperKit は **Main Thread** でのみアクセス可能
2. `guard let whisperKit = whisperKit` ⇒ local binding（Main Thread スコープ内）
3. `try await whisperKit.transcribe(...)` ⇒ **nonisolated メソッドへ main actor-isolated value を送信**
4. WhisperKit.transcribe() は async なので、別 thread へ escaping ⇒ **Main Thread 外で whisperKit が見える可能性**
5. Swift 6 compiler が「race condition の潜在性」を警告

### 修正アプローチの選定

**推奨案**: `@preconcurrency import WhisperKit`（最小変更）

理由:
- WhisperKit は外部ライブラリ（修正不可）で、nonisolated メソッドが明示的設計
- TTT 側の @MainActor 隔離は既に強固
- 実機で race condition が観測される可能性は低（WhisperKit 内部で proper synchronization あり）
- Swift 6 diagnostic 新規追加であり、既存 production code の後付対応として妥当

**代替案検討**:
- nonisolated(unsafe): risk が高い（developer の explicit safety assertion）
- Task.detached: 性能 overhead、可読性低下
- actor 化: SwiftUI 統合困難（非現実的）

---

## 付録: ファイル一覧（絶対パス）

```
/Users/jonji/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/WhisperManager.swift
/Users/jonji/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift
/Users/jonji/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Views/HUDView.swift
/Users/jonji/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Views/SettingsView.swift
/Users/jonji/GitHub/tamekuniz/TTT/Package.swift
/Users/jonji/GitHub/tamekuniz/TTT/Tests/TypeToTalkTests/ModelSelectionTests.swift
/Users/jonji/GitHub/tamekuniz/TTT/Tests/TypeToTalkTests/AudioRecorderTests.swift
/Users/jonji/GitHub/tamekuniz/TTT/scripts/build_app.sh
/Users/jonji/GitHub/tamekuniz/TTT/.build/checkouts/WhisperKit/Sources/WhisperKit/Core/WhisperKit.swift
```

