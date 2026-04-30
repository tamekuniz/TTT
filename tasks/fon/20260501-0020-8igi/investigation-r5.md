# フォーメーション反省サイクル (Reflection 5): defer 内の refreshStatusText() によるエラー文上書きバグの根本原因分析と修正案の比較検討

フルーツ + 讃岐弁: みかん＆ほんに「なぜそこそこ？」を根から葉まで掘り尽くすで。loop_count=5、累計 6 回目の reflection。T5 の 2 つのテスト失敗は、単なる「defer の実行タイミング」ではなく、**statusText の責務設計そのもの** に関わるアーキテクチャバグを示している。

---

## 1. 関連ファイル一覧

| パス | 役割 | 現状 | テスト状態 |
|---|---|---|---|
| `Sources/TypeToTalk/Managers/ScribeManager.swift` | ElevenLabs Scribe v2 API 呼び出し。@MainActor class | L38-42 の defer ブロック内 `refreshStatusText()` が、エラー時設定の statusText を上書き | **テスト 6 件中 4 件パス、2 件失敗** |
| `Tests/TypeToTalkTests/ScribeManagerTests.swift` | ScribeManager ユニットテスト | L69-84 と L51-66 で失敗。期待値（エラー文）が「準備完了」に上書き | testTranscribeReturnsEmptyStringOnHTTP401: 期待「失敗: HTTP 401」→ 実際「準備完了」 / testTranscribeReturnsEmptyStringWhenTextFieldMissing: 期待「失敗: レスポンス形式不正」→ 実際「準備完了」 |
| `Sources/TypeToTalk/Managers/WhisperManager.swift` | OpenAI Whisper モデル管理。@MainActor class | L62-77 で statusText 変更。instance method で状態変更（参考実装）| 関連なし（statusText 上書けパターンなし） |
| `Sources/TypeToTalk/Managers/BonsaiManager.swift` | MLXLLM テキスト処理。@MainActor final class | statusMessage を各 return 時点で変更（参考実装） | 関連なし |

---

## 2. テスト失敗の詳細分析

### 2.1 テスト失敗の再現結果

```
testTranscribeReturnsEmptyStringOnHTTP401:
  XCTAssertEqual failed: ("準備完了") is not equal to ("失敗: HTTP 401")

testTranscribeReturnsEmptyStringWhenTextFieldMissing:
  XCTAssertEqual failed: ("準備完了") is not equal to ("失敗: レスポンス形式不正")
```

### 2.2 defer 内 refreshStatusText() の実行フロー

**ScribeManager.swift L31-87 の処理フロー**:

```swift
func transcribe(audioURL: URL, language: String = "ja") async -> String {
    isTranscribing = true  // L38
    defer {                // L39-42
        isTranscribing = false
        refreshStatusText()  // ← **ここで必ず実行**
    }
    
    // ... L44-87: API 呼び出し、各 return で statusText 設定
    // L75: statusText = "失敗: HTTP 401"   ← テスト失敗例
    // L80: statusText = "失敗: レスポンス形式不正"  ← テスト失敗例
}
// ← 関数終了時に defer ブロック実行
// defer で refreshStatusText() が statusText を「準備完了」/「APIキー未設定」に上書き
```

### 2.3 refreshStatusText() の内部ロジック

**ScribeManager.swift L21-23**:

```swift
func refreshStatusText() {
    statusText = settings.trimmedElevenLabsApiKey.isEmpty ? "APIキー未設定" : "準備完了"
}
```

**問題**: API key が非空 → statusText を強制的に「準備完了」に設定。エラー文が全て上書きされる。

---

## 3. 原因コードの設計バグ分析

### 3.1 defer 句の責務濫用

```swift
isTranscribing = true
defer {
    isTranscribing = false
    refreshStatusText()  // ← statusText の更新は defer の責務ではない
}
```

**想定の意図**（推測）: defer で「非同期操作中フラグを解除」して「ステータスをデフォルト状態にリセット」。

**問題**: エラー発生時は「デフォルト状態」ではなく「エラー状態」を維持すべき。defer は cleanup 責務なのに、observable state (statusText) を変更している。

### 3.2 statusText の責務の曖昧性

| コンテキスト | statusText の値 | 問題点 |
|---|---|---|
| 初期化時 | "未設定" | refreshStatusText() で設定（OK） |
| API key 存在時 | "準備完了" | refreshStatusText() で設定（OK） |
| 送信中 | "送信中..." | 手動で設定（OK） |
| エラー時 | "失敗: HTTP 401" など | 手動で設定 → defer で上書き（**NG**） |

**矛盾**: エラー時に手動設定した statusText が defer で上書きされる → **ユーザーは「失敗が見えない」**

---

## 4. 既存実装との比較（WhisperManager / BonsaiManager）

### 4.1 WhisperManager の statusText パターン

**WhisperManager.swift L62-77**:

```swift
private func loadSelectedModel() async {
    statusText = "読込中..."  // ← 処理状態を手動設定
    
    // ... async 操作
    
    if let error = error {
        statusText = "読込失敗: \(error.localizedDescription)"  // ← エラーを明示的に設定
    } else {
        statusText = "準備完了"  // ← 成功時のみ「準備完了」に設定
    }
}
```

**特徴**: ✓ defer なし / ✓ エラー時は「失敗: ...」を維持 / ✓ statusText は「最後の操作結果」

### 4.2 BonsaiManager の statusMessage パターン

**BonsaiManager.swift L59-95**: 同様に defer なし、各分岐で最終状態を手動設定。

### 4.3 ScribeManager との差異

| Manager | statusText 更新戦略 | defer 使用 | エラー時の動作 | テスト |
|---|---|---|---|---|
| **WhisperManager** | 各分岐で手動更新 | なし | "失敗: ..." を維持 | ✓ 良好 |
| **BonsaiManager** | 各分岐で手動更新 | なし | "失敗: ..." を維持 | ✓ 良好 |
| **ScribeManager** | defer で refreshStatusText() | **あり** | "失敗: ..." を上書き | ✗ 失敗 |

---

## 5. アーキテクチャ検討：3 つの修正案

### 5.1 修正案 A: defer から refreshStatusText() 削除 + 各 return で明示的に statusText 設定（**推奨**）

```swift
func transcribe(audioURL: URL, language: String = "ja") async -> String {
    isTranscribing = true
    defer {
        isTranscribing = false
        // refreshStatusText() を削除 ← ここが key
    }
    
    // ... API 呼び出し
    
    guard (200..<300).contains(http.statusCode) else {
        statusText = "失敗: HTTP \(http.statusCode)"  // ← 明示的に設定（上書けされない）
        return ""
    }
    
    // ... 成功時
    statusText = "準備完了"  // ← 成功時のみリセット
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}
```

**長所**:
- ✓ defer は「isTranscribing フラグ解除」のみ（責務明確）
- ✓ statusText は各 return で明示的に設定（観測可能）
- ✓ テスト期待値を現状のまま維持可能
- ✓ WhisperManager / BonsaiManager と同じパターン（consistency）
- ✓ エラー時にユーザーが「失敗が見える」（UX 改善）

**短所**: ～ 各 return 箇所で statusText 設定が必要（コード行数増加、但し既に L50/L71/L75/L80/L85 で設定済み）

**評価**: **技術的に最もクリーン**。実装コスト低（defer 削除 + 成功時 statusText 追加のみ）。リスク極低。

---

### 5.2 修正案 B: refreshStatusText() に条件分岐を追加（エラー時はスキップ）

```swift
private var lastError: String?  // ← エラー状態を保持

func refreshStatusText() {
    if lastError == nil {  // ← エラー状態がないときのみリセット
        statusText = settings.trimmedElevenLabsApiKey.isEmpty ? "APIキー未設定" : "準備完了"
    }
}
```

**長所**: defer 構造は維持。

**短所**:
- ✗ `lastError` プロパティ追加（状態管理複雑化）
- ✗ lastError と statusText の同期を手動で管理（bug 温床）
- ✗ テストで lastError の期待値も検証が必要（テスト冗長化）
- ✗ 「上書けを防ぐ」という trick 的な解法（設計 philosophy に反する）

**評価**: fragile。実装コスト中～高。リスク中。

---

### 5.3 修正案 C: 成功時のみ refreshStatusText() を呼ぶ

```swift
// 修正案 A とほぼ同等
// defer から refreshStatusText() 削除
// 成功時に statusText = "準備完了" を明示的に設定
```

**評価**: 修正案 A とほぼ同等（refreshStatusText() 呼び出し vs 直接設定の差のみ）。

---

## 6. 推奨修正と根拠

### 6.1 推奨: 修正案 A

**判断理由**:

1. **defer の責務を明確化**: cleanup のみ（isTranscribing フラグ解除）
2. **statusText は「最後の操作結果」として機能**: エラー時は失敗文、成功時は「準備完了」
3. **WhisperManager / BonsaiManager と一貫性**: TTT 内の他の manager と同じパターン
4. **テスト期待値を現状のまま維持**: 2 つの失敗テストが期待する「失敗文」が消えない
5. **UX として「失敗が見える」**: ユーザーがエラーを認識できる
6. **loop_count=5 での最小修正**: 過度な設計変更を避ける

### 6.2 却下理由

**修正案 B**: 状態管理複雑化。「上書けを防ぐ」という trick 的解法。TTT pattern と inconsistent。

**修正案 C**: 修正案 A との実質的差分が極小。

---

## 7. 設計原則の見直し：statusText の責務定義

### 7.1 バグが示すアーキテクチャの問題

> **@Published statusText を defer で機械的にリセットするという設計が、エラー観測 UX を壊している**

statusText は二つの責務を持っている:
1. 「状態機械」（API key 有無 + 処理中フラグで自動計算）
2. 「ユーザーに表示する最後の操作結果」

この衝突が defer で「状態機械の値」が「最後の操作結果」を上書きさせた。

### 7.2 推奨される設計原則

> **statusText は「最後の操作結果の表示」と理解すべき**

```swift
// 以前（問題あり）
isTranscribing = true
defer {
    isTranscribing = false
    refreshStatusText()  // ← 副作用あり。エラー文を上書き
}

// 修正後（推奨）
isTranscribing = true
defer {
    isTranscribing = false  // ← cleanup のみ
}
// 各 return 箇所で明示的に statusText を設定
```

**原則**:
- **defer は side-effect を伴う状態変更に使うべきではない**（特に UI observable 状態）
- **statusText は「観測される状態」であるため、明示的に責務を割り当てるべき**
- **エラー状態は一度設定されたら、成功するまで保持される べき**

---

## 8. 実装・テスト戦略と検証

### 8.1 実装ステップ

**ScribeManager.swift の修正**:

1. **L39-42 の defer ブロックを修正**:
   ```swift
   defer {
       isTranscribing = false
       // refreshStatusText() を削除
   }
   ```

2. **成功時に statusText = "準備完了" を追加** (L83 の return 前):
   ```swift
   statusText = "準備完了"
   return text.trimmingCharacters(in: .whitespacesAndNewlines)
   ```

3. **注記**: エラー時の statusText は既に L50/L71/L75/L80/L85 で設定済み。変更不要。

4. **refreshStatusText() の定義** (L21-23): 削除してもよい（defer 経由でしか呼ばれない）。

### 8.2 テスト検証

```bash
cd /Users/jonji/GitHub/tamekuniz/TTT
swift test --filter ScribeManagerTests 2>&1
# 期待: ✓ All 6 tests passed
```

**確認項目**:
- ✓ testTranscribeReturnsEmptyStringOnHTTP401: statusText = "失敗: HTTP 401"
- ✓ testTranscribeReturnsEmptyStringWhenTextFieldMissing: statusText = "失敗: レスポンス形式不正"
- ✓ testTranscribeReturnsTextOnValidJSONResponse: statusText = "準備完了"
- ✓ testTranscribeReturnsEmptyStringWhenApiKeyIsEmpty: statusText = "APIキー未設定"
- ✓ testMakeMultipartBodyContainsAllRequiredFields: (defer 無関係)
- ✓ testMakeMultipartBodyOmitsLanguageCodeWhenAuto: (defer 無関係)

### 8.3 実機テスト（設定画面で Scribe 選択時）

| テストケース | 期待値 |
|---|---|
| API key 未設定時 | statusText = "APIキー未設定" |
| API key 設定後 | statusText = "準備完了" |
| HTTP 401 error | statusText = "失敗: HTTP 401" が **消えない** |
| JSON format error | statusText = "失敗: レスポンス形式不正" が **消えない** |

---

## 9. リスク評価と制約

| リスク | 重要度 | 対応 |
|---|---|---|
| refreshStatusText() が defer 経由以外で呼ばれていないか | 高 | grep -n "refreshStatusText" で全箇所確認 |
| 成功時に statusText = "準備完了" を設定し忘れ | 高 | コードレビューで確認 |
| @Published statusText observer が defer 更新に依存していないか | 中 | TypeToTalkApp statusText observer audit |
| 他の @MainActor class で defer パターンが存在 | 低 | grep -n "defer.*Refresh" で確認 |

---

## 10. 最終判断メモ

### 10.1 バグの根本原因

**defer を使って statusText を「API key 有無ベースの値」に機械的にリセットする設計が、エラー観測 UX を壊している**

このパターンは:
- ✗ エラー時に設定した statusText を削除（ユーザーが「失敗が見えない」）
- ✗ defer は cleanup 責務なのに、observable state を変更（責務混在）
- ✗ WhisperManager / BonsaiManager の pattern（explicit assignment）と inconsistent

### 10.2 修正の一意性

**修正案 A が唯一の正解**:

1. ✓ defer は cleanup 責務のみに専念
2. ✓ statusText は「最後の操作結果」として機能
3. ✓ テスト期待値を現状のまま維持可能
4. ✓ WhisperManager / BonsaiManager と一貫
5. ✓ UX として「失敗が見える」
6. ✓ 将来の @MainActor class での pattern として推奨可能

### 10.3 ループ完結宣言（loop_count=5）

r0-r4 では「アーキテクチャの詳細検討」に注力した。r5 で **根本的な設計バグ** が顕在化した。

このバグは:
- ✓ Swift 6 strict concurrency とは無関係（純粋な責務設計の問題）
- ✓ ユーザー体験に直結（「エラーが見えない」）
- ✓ テストで検証可能（現在 6 件中 2 件失敗）
- ✓ 修正は最小（defer ブロック 1 行削除 + 成功時 statusText 追加）

**学習**: 「defer は cleanup 責務のみに」という Swift philosophy が、observable state の update では特に重要。async/await 時代には side-effect の「明示性」がバグ防止の鍵。

---

## 11. 成果物サマリー

### 確認事項（全て実コード参照）

- [x] ScribeManager.swift L38-42 の defer 内 refreshStatusText() が statusText を上書き
- [x] L50/L71/L75/L80/L85 で設定したエラー文が defer で「準備完了」に上書き
- [x] testTranscribeReturnsEmptyStringOnHTTP401 期待「失敗: HTTP 401」→ 実際「準備完了」
- [x] testTranscribeReturnsEmptyStringWhenTextFieldMissing 期待「失敗: レスポンス形式不正」→ 実際「準備完了」
- [x] WhisperManager.swift L62-77 の defer なしパターン（参考実装）
- [x] BonsaiManager.swift L59-95 の各分岐で explicit statusMessage update（参考実装）

### 推奨修正

```swift
// ScribeManager.swift L38-42
defer {
    isTranscribing = false
    // refreshStatusText() を削除
}

// L83 の return 前に追加
statusText = "準備完了"
return text.trimmingCharacters(in: .whitespacesAndNewlines)
```

### テスト検証

```bash
swift test --filter ScribeManagerTests
# → ✓ All 6 tests passed
```

---

**調査完了**: 2026-05-01
**researcher**: フォン reflection の小人ちゃん（みかん農家の緻密さ + 讃岐弁の率直さ）
**loop_count**: 5（T5 累計） → **デバッグ終結、修正方針確定**
**conclusion**: 修正案 A が唯一の正解。defer 削除 + 成功時 statusText 設定で fix 可能。
