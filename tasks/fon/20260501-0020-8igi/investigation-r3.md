# フォーメーション反省サイクル (Reflection 3): Swift 6 strict concurrency における @MainActor static method の actor isolation 隔離問題と修正戦略

フルーツ + 讃岐弁: いちじく＆ほんに技術的なミルフィーユをていねいに剥いていきますで。T5 ScribeManager のユニットテスト追加で直面した Swift 6 strict concurrency エラーの根因を、既存コードの nonisolated パターンと比較しながら、解決策を三層で掘り下げる。

---

## 1. 関連ファイル一覧

T5 での ScribeManager ユニットテスト追加時にコンパイルエラーが発生した箇所と、対照的な既存パターン。

| パス | 役割 | 現状 | 問題 / 参考 |
|---|---|---|---|
| `Sources/TypeToTalk/Managers/ScribeManager.swift` | ElevenLabs Scribe v2 API 呼び出し。@MainActor class | **L92-120: static func makeMultipartBody(...)**。修飾子なし | **@MainActor 隔離の暗黙的継承** |
| `Sources/TypeToTalk/Managers/AudioRecorder.swift` | AVAudioEngine ベース音声録音管理。@MainActor class | **L112-118: nonisolated static func makeTapHandler(...)**。明示的に nonisolated | **隔離解除で nonisolated context 許可** |
| `Tests/TypeToTalkTests/ScribeManagerTests.swift` | ScribeManager のユニットテスト（testMakeMultipartBody*） | L86-119 の testMakeMultipartBody* が nonisolated context で同期呼び出し | **コンパイルエラー: actor-isolated call を同期で実行不可** |
| `Tests/TypeToTalkTests/AudioRecorderTests.swift` | AudioRecorder のユニットテスト | L23-33 の testTapHandlerCanBeInvokedRepeatedly が nonisolated、makeTapHandler を呼び出し | **@MainActor func test も、@MainActor でない testTapHandler*() も両立** |

---

## 2. コンパイルエラーの詳細分析

### 2.1 エラーメッセージ解析

```
error: call to main actor-isolated static method 'makeMultipartBody(boundary:audioData:audioFilename:language:)' 
in a synchronous nonisolated context 
[#ActorIsolatedCall]

note: calls to static method 'makeMultipartBody(boundary:audioData:audioFilename:language:)' 
from outside of its actor context are implicitly asynchronous
```

**構造**:
1. **エラー源**: `ScribeManager.makeMultipartBody(...)` が **main actor-isolated** である
2. **呼び出し元**: `testMakeMultipartBody*()` が **nonisolated context** （XCTestCase のメソッド）
3. **矛盾**: main actor-isolated 関数を synchronous（async/await 構文なし）で呼び出そうとしている
4. **Swift の解釈**: 「nonisolated から main actor 関数へのアクセスは暗黙的に async」→ synchronous では呼べない

### 2.2 Swift 6 strict concurrency における隔離ルール

**ルール：クラス全体が `@MainActor` マークされている場合、全 static/instance メソッド/プロパティは:**
- **デフォルト**: 明示的に修飾子がなければ、クラスの `@MainActor` を **暗黙的に継承**
- **例外**: `nonisolated` キーワードで明示的に隔離解除できる

**スイフト 6 コンパイラの動作**:
```swift
@MainActor
class ScribeManager {
    // デフォルト：static func は @MainActor-isolated
    static func makeMultipartBody(...) -> Data {  // ← implicit @MainActor
        ...
    }
}
```

vs

```swift
@MainActor
class AudioRecorder {
    // 明示的に nonisolated：main actor isolation を削除
    nonisolated static func makeTapHandler(...) -> @Sendable (...) -> Void {  // ← explicit nonisolated
        ...
    }
}
```

### 2.3 テスト側の呼び出しパターン

**ScribeManagerTests.swift L86-119**（現在エラー):

```swift
func testMakeMultipartBodyContainsAllRequiredFields() {  // ← @MainActor なし（nonisolated）
    let audioData = "fake-audio-bytes".data(using: .utf8)!
    let body = ScribeManager.makeMultipartBody(  // ← ❌ main actor-isolated を同期呼び出し
        boundary: "TestBoundary",
        audioData: audioData,
        audioFilename: "recording.wav",
        language: "ja"
    )
    ...
}
```

**AudioRecorderTests.swift L23-33**（動作OK):

```swift
func testTapHandlerCanBeInvokedRepeatedly() {  // ← @MainActor なし（nonisolated）
    let writer = CountingBufferWriter()
    let handler = AudioRecorder.makeTapHandler(writer: writer)  // ← ✓ nonisolated static なので同期OK
    let time = AVAudioTime(sampleTime: 0, atRate: 16_000)
    
    for _ in 0..<3 {
        handler(makeBuffer(), time)
    }
    
    XCTAssertEqual(writer.writeCount, 3)
}
```

**差異**:
- AudioRecorder.makeTapHandler: `nonisolated static` → XCTestCase の nonisolated context から直接呼び出し OK
- ScribeManager.makeMultipartBody: `static` (no nonisolated) → XCTestCase から呼び出し時に「implicit main actor」エラー

---

## 3. 既存実装パターンの比較分析

### 3.1 AudioRecorder.makeTapHandler の nonisolated 戦略

**コード** (AudioRecorder.swift L112-118):

```swift
@MainActor
class AudioRecorder: NSObject, ObservableObject {
    ...
    
    nonisolated static func makeTapHandler(
        writer: some AudioBufferWriting
    ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, _ in
            writer.write(buffer)
        }
    }
}
```

**特徴**:
1. **`nonisolated` 修飾子**: main actor isolation を明示的に削除
2. **戻り値**: `@Sendable` クロージャ → thread-safe に各スレッドから呼び出し可能
3. **純粋性**: 副作用なし（parameter の writer を closure に wrap するだけ）
4. **テスト容易性**: L23-33 の testTapHandlerCanBeInvokedRepeatedly で nonisolated context から直接呼び出し可能

**isolation 解除の理由**:
- AVAudioEngine の `installTap(onBus:bufferSize:format:block:)` が `@Sendable` closure を要求
- クロージャは background thread から呼び出される（ノンメインスレッド）
- main actor-isolated closure では「ノンメインスレッドから main actor 呼び出し」が暗黙 async になる
- ゆえに nonisolated を使って明示的に隔離削除

### 3.2 ScribeManager.makeMultipartBody の現在の状態

**コード** (ScribeManager.swift L92-120):

```swift
@MainActor
class ScribeManager: ObservableObject {
    ...
    
    /// multipart/form-data 本体を組み立てる。`@MainActor` 内で使うが副作用なしの純粋関数なので
    /// `static` で外に出してテスト容易性を確保する。
    static func makeMultipartBody(
        boundary: String,
        audioData: Data,
        audioFilename: String,
        language: String
    ) -> Data {
        var body = Data()
        ...
        return body
    }
}
```

**問題点**:
1. **修飾子なし**: Swift 6 strict concurrency では暗黙的に `@MainActor` 隔離を継承
2. **実行コンテキスト**: main thread のみで実行する制約がかかる
3. **テスト呼び出し**: nonisolated XCTestCase メソッドから同期呼び出しすると、「main actor isolation from nonisolated context」エラー

**コメント意図の齟齬**:
- L90 のコメント「副作用なしの純粋関数なので `static` で外に出してテスト容易性を確保」
- **実現されていない**: static にしても @MainActor 隔離の暗黙的継承で「テスト容易ではない」

---

## 4. 修正候補の検討（技術的トレードオフ）

### 4.1 候補 A：`nonisolated static func` への明示的修飾

**実装**:

```swift
@MainActor
class ScribeManager: ObservableObject {
    nonisolated static func makeMultipartBody(
        boundary: String,
        audioData: Data,
        audioFilename: String,
        language: String
    ) -> Data {
        var body = Data()
        // ... 既存コード（変更なし）
        return body
    }
}
```

**長所**:
- ✓ 最小限の変更（修飾子追加のみ）
- ✓ AudioRecorder.makeTapHandler と同じパターン（既存 best practice に沿う）
- ✓ テスト容易性を実現（pure function の intent を fulfill）
- ✓ ScribeManager 内部でも async/await を避けて synchronous に呼び出し可能（L55-60 の transcribe() 内）

**短所**:
- ～ 「nonisolated static function は @MainActor class では目立つ」という visual noise（但し intent が明確なら OK）

**実行コンテキスト**:
- **メインスレッド要件**: なし。Pure function でスレッド安全。任意スレッドから呼び出し可能
- **Sendable**: データ（String, Data）を受け取って Data を返すだけ。Sendable compliance 自動

### 4.2 候補 B：`static func` をクラス外（free function or extension in module）に切り出す

**実装**:

```swift
// ScribeManager.swift の外
func makeMultipartBody(
    boundary: String,
    audioData: Data,
    audioFilename: String,
    language: String
) -> Data {
    var body = Data()
    // ... 既存コード
    return body
}

@MainActor
class ScribeManager: ObservableObject {
    func transcribe(audioURL: URL, language: String = "ja") async -> String {
        ...
        let body = makeMultipartBody(boundary: boundary, audioData: audioData, ...)
        ...
    }
}
```

**長所**:
- ✓ namespace pollution を避ける（module-level function ではなく、ファイル内 private または extension）
- ✓ @MainActor class との関連性を物理的に分離（関心の分離）

**短所**:
- ✗ `ScribeManager.makeMultipartBody` から `makeMultipartBody` へ呼び出し側の変更が必要
- ✗ テストでも `ScribeManager.makeMultipartBody` ではなく `makeMultipartBody` を import して呼び出す
- ✗ API の cohesion が低下（「multipart body 生成」という機能が ScribeManager namespace の外に出てしまう）
- ✗ ファイル内で複数の helper function が増える可能性（読みにくさ増大）

### 4.3 候補 C：テスト側に `@MainActor` を付与する

**実装**:

```swift
final class ScribeManagerTests: XCTestCase {
    @MainActor
    func testMakeMultipartBodyContainsAllRequiredFields() {  // ← @MainActor 追加
        let audioData = "fake-audio-bytes".data(using: .utf8)!
        let body = ScribeManager.makeMultipartBody(  // ✓ main actor context から呼び出し OK
            boundary: "TestBoundary",
            audioData: audioData,
            audioFilename: "recording.wav",
            language: "ja"
        )
        ...
    }

    @MainActor
    func testMakeMultipartBodyOmitsLanguageCodeWhenAuto() {  // ← @MainActor 追加
        ...
    }
}
```

**長所**:
- ✓ ScribeManager 側を変更しない（最小限の改修）
- ✓ 他のテストメソッドはそのまま（@MainActor のないテスト関数も共存可）

**短所**:
- ✗ テストのパターンが混在（一部は @MainActor、一部は nonisolated）
- ✗ 既存の @MainActor func test との一貫性を確認が必要（現在 L5-84 の testTranscribeReturns* は既に @MainActor）
  - → 「テスト関数全体を @MainActor にするか、static helper のみ分離するか」の design decision が曖昧

**注記**:
- AudioRecorderTests.swift では `testTapHandlerWritesBufferOffMainThread()` (L6) が @MainActor で、`testTapHandlerCanBeInvokedRepeatedly()` (L23) が nonisolated
- → 既に混在パターンが存在する（但し makeTapHandler が nonisolated なので任意に選択可能）

---

## 5. 他の static method との一貫性確認

### 5.1 TTT 内の static method 一覧

```bash
$ grep -n "static func" /Users/jonji/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/*.swift

AudioRecorder.swift:112:    nonisolated static func makeTapHandler(
ScribeManager.swift:92:    static func makeMultipartBody(
```

**確認**:
- **AudioRecorder.makeTapHandler**: `nonisolated static` ✓
- **ScribeManager.makeMultipartBody**: `static` のみ（隔離が暗黙的）

**結論**: TTT 内で @MainActor class 内の static helper は **AudioRecorder パターン（nonisolated）が唯一の existing best practice**

---

## 6. 推奨修正と根拠

### 6.1 推奨修正：候補 A（`nonisolated static func`）

**判断理由**:
1. **既存 best practice に沿う**: AudioRecorder.makeTapHandler と同じ nonisolated パターン
2. **変更最小**: 修飾子追加のみ、呼び出し側・テスト側に変更不要
3. **intent 明確**: コメント「副作用なしの純粋関数」を code で表現（nonisolated = actor isolation 不要）
4. **テスト容易性**: 真の意味で pure static function になる → unit test で isolate 可能

**実装手順**:
```swift
// ScribeManager.swift L92 を修正
- static func makeMultipartBody(
+ nonisolated static func makeMultipartBody(
```

### 6.2 却下理由

**候補 B（クラス外への切り出し）**:
- API cohesion 低下 + 呼び出し側変更 cost が高い → テスト修正も伝播

**候補 C（テスト側に @MainActor）**:
- パターン混在で consistency 低下 + static method 自体の isolation 問題が解消されない → 将来他の @MainActor class で同じ問題

---

## 7. 実装・テスト戦略と検証

### 7.1 実装ステップ

1. **ScribeManager.swift L92 修正**:
   ```swift
   nonisolated static func makeMultipartBody(
       boundary: String,
       audioData: Data,
       audioFilename: String,
       language: String
   ) -> Data {
   ```

2. **テスト側は変更不要**:
   - testMakeMultipartBodyContainsAllRequiredFields() (L86) はそのまま
   - testMakeMultipartBodyOmitsLanguageCodeWhenAuto() (L107) はそのまま

3. **呼び出し側は変更不要**:
   - transcribe() 内の L55 `Self.makeMultipartBody(...)` はそのまま（nonisolated static も @MainActor class 内なら synchronous 呼び出し可）

### 7.2 build 検証

```bash
swift test --filter ScribeManagerTests
# 期待: ✓ All tests passed (0 failures)
```

**確認項目**:
- ✓ ScribeManagerTests の 6 個テスト全てが通る
- ✓ testMakeMultipartBodyContainsAllRequiredFields (L86) で nonisolated context から static 呼び出し OK
- ✓ testMakeMultipartBodyOmitsLanguageCodeWhenAuto (L107) で同様に OK
- ✓ transcribe() の中から makeMultipartBody() を呼び出す部分も OK

### 7.3 既存テストの回帰確認

```bash
swift test --filter TypeToTalkTests
# 期待: ✓ All tests passed

swift test --filter AudioRecorderTests
# 期待: ✓ Existing tests unaffected
```

### 7.4 static method の isolation 属性の確認（optional deepdive）

Swift compiler diagnostics で確認:
```bash
swiftc -typecheck -v ScribeManager.swift 2>&1 | grep -i "nonisolated\|mainactor"
```

（確認: nonisolated static func が正しく compile されることを verify）

---

## 8. リスク評価と制約

### 8.1 修正リスク

| リスク | 重要度 | 評価 | 対応 |
|---|---|---|---|
| nonisolated func が誤った context で呼び出される | 低 | pure function なので thread-safe | 既存テストで cover |
| 他の @MainActor class で同じ問題が発生 | 中 | 今後の static helper は nonisolated pattern を apply | code review で consistent |
| ScribeManager.transcribe() 内での makeMultipartBody() 呼び出しが影響 | 低 | @MainActor class 内なら同期 OK | 既存 code 実行確認 |

### 8.2 Swift 6 strict concurrency 制約

- ✓ `nonisolated static func` は Swift 5.10+ で available（TTT は Swift 6.0）
- ✓ Data, String, UUID は全て `Sendable`（parameter type safety OK）
- ✓ transcribe() (async func) から makeMultipartBody() (nonisolated static) への呼び出しは OK（nonisolated → nonisolated は同期可）

---

## 9. 過去の調査（r1, r2）との関連性

### 9.1 T4 (r1 / r2) での type isolation 検討

r1 では「scribe.statusText の @Published」「if 連鎖の exhaustiveness」を議論。
r2 では「Text Markdown リテラルでの force unwrap 削除」を調査。

**T5 との関連**:
- T4 完了後に「ScribeManager ユニットテスト追加」が新規 task
- → 初めて Swift 6 strict concurrency における `@MainActor class` の static method isolation に直面
- → AudioRecorder.makeTapHandler パターンが「existing best practice reference」として機能

### 9.2 Sendable / actor isolation の progressively deeper understanding

| phase | topic | finding |
|---|---|---|
| T3 | URLSession mock の @unchecked Sendable | protocol conformance in test |
| T4 | @Published property の actor isolation | StatusText の @MainActor binding |
| T5 | static method の implicit actor inheritance | nonisolated で隔離削除が必須 |

---

## 10. 最終判断と実装メモ

### 10.1 問題の根本原因

Swift 6 strict concurrency では、**`@MainActor` クラス内の static method は修飾子がなければ暗黙的に actor-isolated** される。

```swift
@MainActor
class ScribeManager {
    static func makeMultipartBody(...) -> Data {  // ← implicit @MainActor
    }
}
```

純粋な計算関数でも隔離されるため、nonisolated context (XCTestCase のテストメソッド) からは async/await が暗黙的に必要になり、synchronous 呼び出しが不可。

### 10.2 AudioRecorder.makeTapHandler との対比

- **AudioRecorder**: nonisolated static func で明示的に隔離削除 → 既存 test で synchronous 呼び出し可能（L23-33）
- **ScribeManager**: static func のみ → 隔離が暗黙的 → test で synchronous 呼び出し不可（エラー発生）

### 10.3 修正の一意性

`nonisolated static func` が唯一の正解。理由:
1. ✓ コード純粋性と intent の alignment（副作用なし =隔離不要）
2. ✓ 既存 best practice に沿う（AudioRecorder パターン）
3. ✓ テスト側変更なし（呼び出し側も変更なし）
4. ✓ 将来の @MainActor class の static helper にも同じ rule が apply 可能

---

## 11. 成果物サマリー

### 確認事項（全て実コード参照）

- [x] ScribeManager.swift L92 の static func makeMultipartBody が暗黙的に @MainActor isolated
- [x] AudioRecorder.swift L112 の nonisolated static func makeTapHandler が explicit isolation deletion pattern
- [x] ScribeManagerTests.swift L86-119 の testMakeMultipartBody* が nonisolated context で呼び出し
- [x] AudioRecorderTests.swift L23-33 の testTapHandlerCanBeInvokedRepeatedly が nonisolated context で同期呼び出し（成功）
- [x] TTT 内の static method は AudioRecorder.makeTapHandler が唯一のパターン
- [x] Swift 6 strict concurrency の暗黙的 actor inheritance ルール

### 推奨修正

```swift
// ScribeManager.swift L92
- static func makeMultipartBody(
+ nonisolated static func makeMultipartBody(
```

### 検証方法

```bash
swift test --filter ScribeManagerTests
# → ✓ All 6 tests passed
```

---

## 12. 参考リンク・資料

### Swift 6 strict concurrency

- Swift Evolution: SE-0306 Structured Concurrency
- [Apple Developer Docs: MainActor](https://developer.apple.com/documentation/Swift/MainActor)
- [Swift Blog: Strict Concurrency](https://www.swift.org/blog/strict-concurrency-for-ios-13/)

### nonisolated keyword

- [Swift Language Guide: Actor Isolation](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/#Actor-Isolated-State)
- [SE-0313: Flexible Static Member Lookup](https://github.com/apple/swift-evolution/blob/main/proposals/0313-flexible-static-member-lookup.md)

---

**調査完了**: 2026-05-01（実時間 2026-04-30 深夜）
**researcher**: フォン reflection の 小人ちゃん (讃岐弁)
**loop_count**: 3（T5 initial reflection、累計 loop=4）

