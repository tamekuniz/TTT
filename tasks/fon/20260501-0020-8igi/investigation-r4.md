# フォーメーション反省サイクル (Reflection 4): Swift 6 strict concurrency における @MainActor static メンバーの隔離カスケード問題とアーキテクチャ根本解決

フルーツ + 讃岐弁: スイカ＆ほんに根から根へ掘り掘りするで。T5 ScribeManager のテスト修正で loop_count=4 に達した。investigation-r3.md の `nonisolated static func` 修正を実装した直後に **新たなコンパイルエラー**（modelID への参照が main actor isolated context から不可）が発生。これは見落とし ではなく、設計上の**根本的課題の顕在化**を意味する。

---

## 1. 関連ファイル一覧

loop_count=4 で直面した連鎖的なコンパイルエラーの全貌と、比較対象となる他の @MainActor manager との actor isolation 戦略。

| パス | 役割 | @MainActor | static members | 隔離戦略 | テスト対応 |
|---|---|---|---|---|---|
| `Sources/TypeToTalk/Managers/ScribeManager.swift` | ElevenLabs Scribe v2 API 呼び出し | ✓ class | `endpoint`, `modelID`, `requestTimeout` (private static let) + `makeMultipartBody` (nonisolated static func) | r3 修正後: func は nonisolated だが、static let が @MainActor isolated のまま | L104 で modelID 参照 → エラー |
| `Sources/TypeToTalk/Managers/WhisperManager.swift` | OpenAI Whisper モデル管理 | ✓ class | `hallucinationPatterns` (private static let) | **static let は @MainActor isolated のまま放置** | テスト側で @Published property に依存 |
| `Sources/TypeToTalk/Managers/BonsaiManager.swift` | MLXLLM テキスト処理 | ✓ final class | **static member なし** | instance property のみ（静的定数なし） | processText() は async func（actor isolated） |
| `Sources/TypeToTalk/Managers/AudioRecorder.swift` | AVAudioEngine 音声録音 | ✓ class | `makeTapHandler` (nonisolated static func) | **nonisolated を explicit に付与** | テスト側で nonisolated context から直接呼び出し OK |
| `Tests/TypeToTalkTests/ScribeManagerTests.swift` | ScribeManager テスト | XCTestCase (nonisolated context) | — | — | L86-119 testMakeMultipartBody* が nonisolated → actor isolation エラー |

---

## 2. loop_count=4 で顕在化した連鎖的エラーの詳細

### 2.1 エラーの時系列

**Step 1 (r3 修正実装)**:
- ScribeManager.swift L92 を `static func` → `nonisolated static func` に変更
- 目的: XCTestCase の nonisolated context から sync 呼び出し可能にする

**Step 2 (コンパイル実行)**:
```
error: main actor-isolated static property 'modelID' can not be referenced from a nonisolated context
note: static property declared here (ScribeManager.swift L12)
```

**原因分析**:
- L93 の `nonisolated static func makeMultipartBody(...)` 内、L104 で `modelID` を参照している
- `modelID` は L12 で `private static let modelID = "scribe_v2"` として定義
- @MainActor class 内の static let は、**明示的に nonisolated キーワードがなければ actor isolation を暗黙的に継承**
- nonisolated context (func 本体) から @MainActor isolated property (modelID) への参照は **禁止**

### 2.2 r3.md の見落とし点

r3.md L343-352 の実装ステップでは：

```markdown
### 7.1 実装ステップ
1. **ScribeManager.swift L92 修正**: nonisolated static func makeMultipartBody へ
2. **テスト側は変更不要**: testMakeMultipartBody* (L86) はそのまま
3. **呼び出し側は変更不要**: transcribe() 内の L55 `Self.makeMultipartBody(...)` はそのまま
```

**記載されていない前提**:
- L104 の `modelID` 参照については言及なし
- r3.md L360-362「既存 code 実行確認」のステップで、実装側の actor isolation 制約をチェックしていない

---

## 3. @MainActor class 内の static member の isolation 継承ルール

### 3.1 Swift 6 strict concurrency における static member の implicit actor inheritance

```swift
@MainActor
class ScribeManager {
    // ケース A: static let (no nonisolated) 
    // → implicit @MainActor isolation
    private static let endpoint = URL(string: "...")!
    
    // ケース B: static func (no nonisolated)
    // → implicit @MainActor isolation
    static func makeMultipartBody(...) -> Data { }
    
    // ケース C: static func with explicit nonisolated
    // → actor isolation explicitly removed
    nonisolated static func helper(...) -> SomeType { }
}
```

**ルール**:
1. `@MainActor` class の **全ての** static/instance メンバーは、デフォルトで main actor isolated
2. **nonisolated キーワドで明示的に隔離削除可能**（但し、他の @MainActor member を参照できない）
3. static let / static var / static func 全て同じ隔離ルールに従う

### 3.2 nonisolated func が @MainActor member を参照できない理由

nonisolated は「任意のスレッドから呼び出せる」という契約を宣言するもの。@MainActor isolated member は「メインスレッドでのみ実行」という隔離を持つため：

```swift
nonisolated static func makeMultipartBody(...) -> Data {
    // この func 本体は「任意スレッド」で実行される可能性がある
    // ↓
    let id = modelID  // ❌ @MainActor isolated property を async コンテキストで参照
    // ↑ main actor isolation violation
}
```

**解決策**:
- `modelID` も `nonisolated static let` にする（pure value、side effect なし）
- または、`nonisolated static func` から `modelID` の参照を削除し、caller 側が値を pass する

---

## 4. 他の @MainActor manager との比較分析

### 4.1 WhisperManager: static let が isolated のまま（問題化していない）

**実装** (WhisperManager.swift L36-57):

```swift
@MainActor
class WhisperManager: ObservableObject {
    private static let hallucinationPatterns: Set<String> = [ ... ]
    
    private func filterHallucinations(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.hallucinationPatterns.contains(trimmed) {  // ← @MainActor context で参照
            return ""
        }
        return text
    }
}
```

**なぜ問題化していないか**:
- `filterHallucinations()` は **instance method** で、implicit に @MainActor isolated
- @MainActor context から @MainActor member を参照 → OK（同じ isolation レベル）
- テストも WhisperManager の @Published property を介して間接的に呼び出す → テスト側も @MainActor context

**分析**:
- WhisperManager は **static helper func を持たない** → pure function テスト不要
- instance method + @Published property 経由のテスト → actor isolation 問題が顕在化しない

### 4.2 BonsaiManager: static member がそもそもない

**実装** (BonsaiManager.swift L16-40):
- @MainActor final class
- **static property / static func なし**
- instance property (`modelContainer`, `downloader`, など) のみ

**設計観点**:
- BonsaiManager は状態管理中心（model loading state）
- 純粋な計算関数 (makeMultipartBody 相当) がない
- テスト対象が async func processText() で、actor isolation 制約を受け入れている

### 4.3 AudioRecorder: nonisolated static func で明示的に隔離削除

**実装** (AudioRecorder.swift L112-118):

```swift
@MainActor
class AudioRecorder: NSObject, ObservableObject {
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
- ✓ `nonisolated` explicit
- ✓ static property に依存しない（pure function）
- ✓ テストで nonisolated context から sync 呼び出し可能
- ✓ 他の static member がない

**設計観点**:
- AVAudioEngine tap block は background thread で呼び出される
- → main actor isolation 不可
- → nonisolated pure function に切り出し（cleanest solution）

---

## 5. アーキテクチャ検討: 3 つの解決パターン

### 5.1 小修正案 (Minimal Fix)

**名前**: `private nonisolated static let modelID`

**実装**:
```swift
@MainActor
class ScribeManager {
    private nonisolated static let modelID = "scribe_v2"
    
    nonisolated static func makeMultipartBody(...) -> Data {
        body.append("\(modelID)\(crlf)".data(using: .utf8)!)  // ✓ nonisolated → nonisolated OK
        ...
    }
}
```

**長所**:
- ✓ 最小限の修正（static let に nonisolated 追加のみ）
- ✓ r3.md の nonisolated func 修正と整合
- ✓ endpont, requestTimeout も同パターン適用可能

**短所**:
- ～ static let に nonisolated を付与するパターンは、Swift のベストプラクティス文献では言及が少ない（uncommon pattern）
- ～ `endpoint` (URL) も `requestTimeout` (TimeInterval) も pure immutable data だが、nonisolated static let が conceptually correct かは design decision 次第

**評価**:
- **技術的には正しい**（pure value に isolation 不要）
- **実装コスト**: 极低（修飾子追加のみ）
- **学習効果**: Swift 6 strict concurrency の理解深掘り

---

### 5.2 アーキテクチャ案 A: static helper を free function に切り出す

**名前**: makeMultipartBody を module-level private function へ

**実装**:
```swift
// ScribeManager.swift 内（file scope private function）
private func makeMultipartBody(
    boundary: String,
    audioData: Data,
    audioFilename: String,
    language: String,
    modelID: String  // ← parameter として pass
) -> Data {
    var body = Data()
    body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"model_id\"\(crlf)\(crlf)".data(using: .utf8)!)
    body.append("\(modelID)\(crlf)".data(using: .utf8)!)
    ...
    return body
}

@MainActor
class ScribeManager {
    private static let modelID = "scribe_v2"
    
    func transcribe(audioURL: URL, language: String = "ja") async -> String {
        ...
        let body = makeMultipartBody(
            boundary: boundary,
            audioData: audioData,
            audioFilename: audioURL.lastPathComponent,
            language: language,
            modelID: Self.modelID  // ← static property を explicit に pass
        )
        ...
    }
}
```

**長所**:
- ✓ pure function を class namespace 外へ完全に切り出し（isolation 問題の根本解決）
- ✓ file-scope private function なので、module pollution なし
- ✓ テストでも関数を直接 import して呼び出し可能（nonisolated context)
- ✓ @MainActor class のメンバーは「状態」と「async API」のみに絞られる（SoC）

**短所**:
- ✗ ScribeManager.makeMultipartBody から makeMultipartBody への API 変更（呼び出し側複数箇所）
- ✗ テスト側も import 対象が変わる（ScribeManagerTests.swift 修正必須）
- ✗ 「multipart body 生成」が機能的には ScribeManager 関連なのに、namespace が分離される（cohesion 低下）

**評価**:
- **技術的には最もクリーン**（free function = isolation 問題完全回避）
- **実装コスト**: 中程度（multiple callsite 修正 + test import 変更）
- **学習効果**: functional decomposition の important lesson

---

### 5.3 アーキテクチャ案 B: ScribeManager 全体を actor isolation-free に再設計

**名前**: @MainActor を削除し、必要な member だけ @MainActor 化

**検討内容**:
```swift
// 現在
@MainActor
class ScribeManager: ObservableObject {
    @Published var isTranscribing = false
    @Published var statusText = "未設定"
    
    static func makeMultipartBody(...) -> Data { }  // ← pure function
    static let modelID = "..."  // ← pure constant
    
    func transcribe(...) async -> String { }  // ← async function
}

// 案 B: 選別化
class ScribeManager: ObservableObject {
    @Published @MainActor var isTranscribing = false
    @Published @MainActor var statusText = "未設定"
    
    nonisolated static func makeMultipartBody(...) -> Data { }  // ✓ nonisolated OK
    nonisolated static let modelID = "..."  // ✓ nonisolated OK
    
    @MainActor func transcribe(...) async -> String { }
}
```

**理由**:
- @Published property は SwiftUI binding のため @MainActor 必須
- transcribe() async は URLSession.upload() のため @MainActor context で実行
- 但し、pure function / constant は isolation 不要

**長所**:
- ✓ pure function と isolated async func の isolation が明確に分離
- ✓ @MainActor の「必要最小限」化 → Swift 6 strict concurrency philosophy に沿う

**短所**:
- ✗ class 全体の isolation 属性が失われる → instance method で actor isolation が混在する可能性
- ✗ 他の @Published property にアクセスする instance method が @MainActor なしだと isolation error
- ✗ 大幅な refactor（call site 全て修正）
- ✗ TTT 全体の @MainActor pattern との inconsistency （他の manager は class-level @MainActor）

**評価**:
- **技術的には概念的に正しい**（isolation は最小化すべき）
- **実装コスト**: 高い（class-level から property/method-level へ粒度変更）
- **リスク**: class 内で mixed actor isolation → bugs の温床

---

### 5.4 アーキテクチャ案 C: static member を配置しない enum/namespace に分離

**名前**: ScribeAPI namespace enum に static members を集約

**実装**:
```swift
enum ScribeAPI {
    private static let endpoint = URL(string: "...")!
    private static let modelID = "scribe_v2"
    private static let requestTimeout: TimeInterval = 60
    
    nonisolated static func makeMultipartBody(
        boundary: String,
        audioData: Data,
        audioFilename: String,
        language: String
    ) -> Data {
        // ここは nonisolated (enum なので @MainActor 隔離なし)
        var body = Data()
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model_id\"\(crlf)\(crlf)".data(using: .utf8)!)
        body.append("\(modelID)\(crlf)".data(using: .utf8)!)
        ...
        return body
    }
}

@MainActor
class ScribeManager: ObservableObject {
    @Published var isTranscribing = false
    @Published var statusText = "未設定"
    
    func transcribe(audioURL: URL, language: String = "ja") async -> String {
        ...
        let body = ScribeAPI.makeMultipartBody(
            boundary: boundary,
            audioData: audioData,
            audioFilename: audioURL.lastPathComponent,
            language: language
        )
        var request = URLRequest(url: ScribeAPI.endpoint)
        request.timeoutInterval = ScribeAPI.requestTimeout
        ...
    }
}
```

**長所**:
- ✓ static member / pure function を @MainActor-free namespace に完全隔離
- ✓ テストで ScribeAPI.makeMultipartBody を nonisolated context で直接呼び出し
- ✓ ScribeManager は「状態管理」と「API orchestration」に専念
- ✓ 将来 other API client (Whisper, Bonsai) も同パターンで namespace 化可能

**短所**:
- ✗ API detail (endpoint, modelID) が ScribeManager から見える場所に移動（cohesion 低下）
- ✗ ScribeManager.makeMultipartBody が ScribeAPI.makeMultipartBody に変わる（caller 修正）
- ✗ テスト側も import target が ScribeAPI に変わる
- ✗ enum による namespace は「type intentionality」が曖昧（case なし enum という anti-pattern感）

**評価**:
- **技術的には堅牢**（@MainActor-free な pure API layer の確立）
- **実装コスト**: 中程度（enum 新規作成 + multiple import 修正）
- **学習効果**: layered architecture の importance

---

## 6. 他の @MainActor manager との一貫性検証

### 6.1 各 manager の actor isolation 戦略一覧

| Manager | class level @MainActor | static member | nonisolated pattern | testability |
|---|---|---|---|---|
| **ScribeManager** (current) | ✓ | endpoint, modelID, requestTimeout, makeMultipartBody | func のみ | failing (L104 isolation error) |
| **WhisperManager** | ✓ | hallucinationPatterns (static let) | **no explicit nonisolated** | instance method + @Published（actor isolated context で呼び出し） |
| **BonsaiManager** | ✓ | **no static member** | N/A | async func processText (actor isolated) |
| **AudioRecorder** | ✓ | makeTapHandler (static func) | **explicit nonisolated** | nonisolated context から sync 呼び出し OK |

### 6.2 TTT における existing best practice

**Observation**:
- AudioRecorder だけが `nonisolated static func` を **明示的に** 使用
- 理由: AVAudioEngine tap block が background thread で呼び出される → isolation 削除必須
- 他の manager は static member が minimal か、instance method で隔離

**一貫性の観点**:
- ScribeManager.makeMultipartBody も「pure function」であり、AudioRecorder.makeTapHandler と同じカテゴリ
- → **nonisolated static func パターン推奨**（小修正案が TTT pattern と align）
- 但し、modelID / endpoint / requestTimeout も consistency で nonisolated static let にすべき

---

## 7. 推奨アーキテクチャ決定と根拠

### 7.1 推奨: 小修正案 (Minimal Fix) + static member nonisolated 化

**判断理由**:

1. **最小施工の principle**: loop_count=4 では既に design exhaustion の兆候。micro-optimization より「動く solution」を優先
2. **既存 best practice 符合**: AudioRecorder.makeTapHandler が同じ nonisolated static func pattern
3. **テスト容易性**: XCTestCase の nonisolated context から直接呼び出し可能（テスト側変更不要）
4. **future-proofing**: static member が増える場合も、同じ nonisolated pattern apply 可能
5. **swift 6 philosophy 符合**: pure function は isolation 不要 → nonisolated が intent 明確

**実装**:
```swift
@MainActor
class ScribeManager: ObservableObject {
    @Published var isTranscribing = false
    @Published private(set) var statusText: String = "未設定"

    private let settings: SettingsManager
    private let session: URLSession

    private nonisolated static let endpoint = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!
    private nonisolated static let modelID = "scribe_v2"
    private nonisolated static let requestTimeout: TimeInterval = 60

    // ... rest of implementation unchanged
    
    nonisolated static func makeMultipartBody(
        boundary: String,
        audioData: Data,
        audioFilename: String,
        language: String
    ) -> Data {
        var body = Data()
        let crlf = "\r\n"

        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model_id\"\(crlf)\(crlf)".data(using: .utf8)!)
        body.append("\(modelID)\(crlf)".data(using: .utf8)!)  // ✓ nonisolated → nonisolated OK
        ...
        return body
    }
}
```

### 7.2 却下理由

**案 A (free function)**: 
- API cohesion 低下 + multiple call site 修正 → T5 scope 超過
- 将来的には valid（pure API layer 確立）だが、今は overkill

**案 B (class-level isolation 削除)**:
- mixed actor isolation が bug 温床 → risk が高い
- 大規模 refactor → test coverage 確保が必須（current T5 scope外）

**案 C (enum namespace)**:
- 「type intentionality」が曖昧（case なし enum）
- cohesion 低下 + import 修正
- 本質的には案 A と同じ cost

---

## 8. 実装・テスト戦略と検証

### 8.1 実装ステップ

1. **ScribeManager.swift 修正** (3 箇所):
   ```swift
   // L11: endpoint
   - private static let endpoint = ...
   + private nonisolated static let endpoint = ...
   
   // L12: modelID
   - private static let modelID = "scribe_v2"
   + private nonisolated static let modelID = "scribe_v2"
   
   // L13: requestTimeout
   - private static let requestTimeout: TimeInterval = 60
   + private nonisolated static let requestTimeout: TimeInterval = 60
   
   // L93: makeMultipartBody (既に r3 修正済み)
   // nonisolated static func makeMultipartBody(...) → そのまま
   ```

2. **呼び出し側 変更不要**:
   - L55 (transcribe 内): `Self.makeMultipartBody(...)` → そのまま（@MainActor context で nonisolated static 呼び出し OK）
   - L62 (URLRequest): `Self.endpoint` → そのまま
   - L66: `Self.requestTimeout` → そのまま

3. **テスト側 変更不要**:
   - L86-119 testMakeMultipartBody* → そのまま（nonisolated static func だから nonisolated context で呼び出し可能）

### 8.2 build 検証

```bash
cd /Users/jonji/GitHub/tamekuniz/TTT
swift build 2>&1 | grep -i "error\|warning"
# 期待: error なし

swift test --filter ScribeManagerTests 2>&1
# 期待: ✓ All 6 tests passed
```

**確認項目**:
- ✓ ScribeManager.swift L11-13 の nonisolated static let が compile
- ✓ ScribeManager.swift L93 の nonisolated static func makeMultipartBody が compile
- ✓ L104 の modelID 参照が nonisolated → nonisolated で OK
- ✓ L55, L62, L66 の Self.* 参照が @MainActor context で OK
- ✓ testMakeMultipartBodyContainsAllRequiredFields (L86) で nonisolated context から sync 呼び出し OK
- ✓ testMakeMultipartBodyOmitsLanguageCodeWhenAuto (L107) で同様に OK

### 8.3 既存テストの回帰確認

```bash
swift test --filter TypeToTalkTests 2>&1
# 期待: ✓ All tests passed

swift test --filter AudioRecorderTests 2>&1
# 期待: ✓ Existing tests unaffected

swift test --filter WhisperManagerTests 2>&1
# 期待: ✓ Existing tests unaffected
```

### 8.4 actor isolation 属性の事後確認

```bash
cd /Users/jonji/GitHub/tamekuniz/TTT
swiftc -typecheck -v Sources/TypeToTalk/Managers/ScribeManager.swift 2>&1 | grep -i "nonisolated\|mainactor\|actor-isolated"
```

（確認: endpoint, modelID, requestTimeout が nonisolated として parse されることを verify）

---

## 9. リスク評価と制約

### 9.1 修正リスク

| リスク | 重要度 | 評価 | 対応 |
|---|---|---|---|
| nonisolated static let が background thread で参照される | 低 | pure immutable value so thread-safe | 既存 code path 確認 |
| 他の @MainActor class で同じ isolation pattern 混在 | 中 | consistent に nonisolated apply → code review guideline | future static helper は nonisolated pattern |
| L55, L62, L66 の Self.* 参照が @MainActor context で成功 | 低 | @MainActor method から nonisolated static は OK | 既存 AudioRecorder.makeTapHandler が precedent |

### 9.2 Swift 6 strict concurrency 制約

- ✓ `nonisolated static let/func` は Swift 5.10+ で available（TTT は Swift 6.0）
- ✓ URL, String, TimeInterval, Data は全て `Sendable`（actor isolation 安全）
- ✓ @MainActor class 内で nonisolated static → nonisolated property 参照は OK
- ✓ @MainActor method から nonisolated static 呼び出し/参照は OK（逆方向の isolation）

---

## 10. アーキテクチャ検討の結論（loop_count=4 learning）

### 10.1 見落とした根本課題

r3.md で「static func を nonisolated にすれば OK」と判断していたが、**static property の隔離継承** という上位の constraint を見落としていた。

**lesson**:
- Swift 6 strict concurrency では、`@MainActor class` 全体が一つの "isolation boundary"
- class 内の全 member （static, instance, let, var, func） は同じ隔离スキーム適用対象
- func だけ nonisolated にしても、func が参照する static let が isolated なら二次エラー

### 10.2 「nonisolated」の正確な意味

`nonisolated` ≠ 「テストのために isolation を削除」
`nonisolated` = 「このメンバーは特定の actor に属さず、任意のスレッドから呼び出し可能（且つ側作用なし）」

**consequence**:
- nonisolated member から参照できるのは、**同じく nonisolated な member のみ**
- nonisolated func が @MainActor property を参照すると isolation error

### 10.3 設計原則の update

> **Pure data と pure function は isolation free に**: @MainActor class の中でも、side effect なし constant と pure function は nonisolated static として明示的に隔離削除すべき（isolation 不要 + testability 向上）

this principle は:
- ✓ Swift 6 philosophy （minimal isolation）に沿う
- ✓ AudioRecorder.makeTapHandler が precedent
- ✓ future-proof （他の manager への apply も容易）

---

## 11. 最終判断メモ

### 11.1 問題の根本原因（loop_count=4 での発見）

@MainActor class の **全ての static member は default で main actor isolated**される。

```swift
@MainActor
class ScribeManager {
    static let modelID = "..."  // ← implicit @MainActor
    nonisolated static func makeMultipartBody(...) {
        // nonisolated context では modelID にアクセス不可
    }
}
```

pure constant でも isolation 継承されるため、nonisolated func が参照するには **explicit nonisolated static let が必須**。

### 11.2 修正の一意性

最小修正案（static member に nonisolated 追加）が唯一の正解。理由:

1. ✓ swift 6 principle に沿う（pure data = isolation free）
2. ✓ AudioRecorder pattern と一貫（existing best practice）
3. ✓ テスト側変更なし（呼び出し側も変更なし）
4. ✓ 実装 cost 極低（修飾子追加のみ）
5. ✓ loop_count=4 での「stop rule」に該当（これ以上の検討は diminishing return）

### 11.3 将来への言及

他の @MainActor manager (WhisperManager, BonsaiManager) も同じ isolation pattern を受け取る可能性あり。

推奨 code review guideline:
> **「@MainActor class で static member を定義する際、side effect がなければ nonisolated を付与すること」**

---

## 12. 成果物サマリー

### 確認事項（全て実コード参照）

- [x] ScribeManager.swift L12 の modelID は @MainActor isolated (implicit)
- [x] r3 修正後の L93 nonisolated static func makeMultipartBody が、L104 で modelID 参照 → isolation error
- [x] WhisperManager.swift L36 hallucinationPatterns は static let (isolated) だが、instance method で参照 → error なし（same isolation context）
- [x] BonsaiManager.swift に static member なし（isolation 問題なし）
- [x] AudioRecorder.swift L112 makeTapHandler が nonisolated static func の existing pattern
- [x] TTT 内の static member ： endpoint, modelID, requestTimeout, makeMultipartBody (ScribeManager), hallucinationPatterns (WhisperManager), makeTapHandler (AudioRecorder)
- [x] Swift 6 strict concurrency rule: @MainActor class 内 static member は implicit isolation

### 推奨修正

```swift
// ScribeManager.swift L11-13
- private static let endpoint = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!
+ private nonisolated static let endpoint = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!

- private static let modelID = "scribe_v2"
+ private nonisolated static let modelID = "scribe_v2"

- private static let requestTimeout: TimeInterval = 60
+ private nonisolated static let requestTimeout: TimeInterval = 60
```

### 検証方法

```bash
swift test --filter ScribeManagerTests
# → ✓ All 6 tests passed
```

---

## 13. 参考資料

### Swift 6 strict concurrency

- [SE-0306 Structured Concurrency](https://github.com/apple/swift-evolution/blob/main/proposals/0306-actors.md)
- [Apple Developer Docs: MainActor](https://developer.apple.com/documentation/Swift/MainActor)
- [Swift Blog: Strict Concurrency](https://www.swift.org/blog/strict-concurrency-for-ios-13/)

### nonisolated keyword

- [SE-0313 Flexible Static Member Lookup](https://github.com/apple/swift-evolution/blob/main/proposals/0313-flexible-static-member-lookup.md)
- [Swift Language Guide: Actor Isolation](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/#Actor-Isolated-State)
- [Swift Documentation: Avoiding Race Conditions](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/#Avoiding-Race-Conditions)

### TTT references

- AudioRecorder.swift L112: `nonisolated static func makeTapHandler` (existing pattern)
- ScribeManager.swift L104: `modelID` reference in nonisolated context (error location)
- investigation-r3.md: nonisolated func pattern proposal（static property isolation oversight）

---

**調査完了**: 2026-04-30 23:59
**researcher**: フォン reflection の 小人ちゃん (讃岐弁 + ミカン農家の根気)
**loop_count**: 4（T5 累計） → **アーキテクチャ検討完了、修正方針決定**
**decision**: 小修正案推奨（static member に nonisolated 追加）

