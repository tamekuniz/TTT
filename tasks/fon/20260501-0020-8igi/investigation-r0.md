# フォーメーション反省サイクル (Reflection 0): `trimmedElevenLabsApiKey` getter 追加の整合性と影響範囲分析

フルーツ梨ちゃん、長野方言の researcher より。

---

## 1. 関連ファイル一覧

修正後の現況。

| パス | 役割 | 状態 |
|---|---|---|
| `Sources/TypeToTalk/Managers/SettingsManager.swift` | `@Published var elevenLabsApiKey` + 新規 `var trimmedElevenLabsApiKey` getter | **修正済み（uncommitted）** |
| `Sources/TypeToTalk/Managers/ScribeManager.swift` | 2箇所で `settings.trimmedElevenLabsApiKey` を使用（refreshStatusText L22、transcribe L32） | **新規作成、使用箇所揃い** |
| `Sources/TypeToTalk/App/TypeToTalkApp.swift` | 1箇所で `settings.trimmedElevenLabsApiKey.isEmpty` チェック（toggleRecording L230） | **修正済み（uncommitted）** |
| `Sources/TypeToTalk/Managers/OpenAICompatibleManager.swift` | Groq/OpenAI API 呼び出し（apiKey をそのまま受け取る）| 未変更、trimmed 不使用 |
| `Sources/TypeToTalk/Views/SettingsView.swift` | ElevenLabs Scribe 用の UI 条件分岐は未実装。formatter provider の .groq / .openAI のパターンに倣って追加すべき | **未実装** |

---

## 2. 既存実装パターン（trimmed API key の整合性）

### groqApiKey / openAIApiKey との比較
- **groqApiKey / openAIApiKey**: @Published プロパティのまま、trim getter なし。呼び出し側の `processText()` で **そのまま** Authorization header へ入れられる
- **elevenLabsApiKey**: @Published プロパティ + **新規に trimmedElevenLabsApiKey getter を追加**（trim 式を集約）

### resolvedBonsaiModelID / resolvedWhisperModelID との慣習との整合

```swift
// SettingsManager.swift:316-330
var resolvedBonsaiModelID: String {
    if let presetModelID = bonsaiModelPreset.modelID {
        return presetModelID
    }
    let trimmed = bonsaiCustomModelID.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "prism-ml/Ternary-Bonsai-8B-mlx-2bit" : trimmed
}

var resolvedWhisperModelID: String? {
    if let presetModelID = whisperModelPreset.modelID {
        return presetModelID
    }
    let trimmed = whisperCustomModelID.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

// 新規: trimmedElevenLabsApiKey
var trimmedElevenLabsApiKey: String {
    elevenLabsApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
}
```

**整合性評価**: ✓ 良好
- `resolved/trimmed` 系 getter の既存慣習に揃っている
- API key は「空かどうか判定」が主流なので `.isEmpty` で checkable にする設計
- 詳細 comment により intent が明確（「resolvedWhisperModelID 等と同じ慣習」と明記）

### ほか API key の trim 状況
- **groq/openAI** は trim getter がない理由: `processText()` の呼び出し側で `apiKey` をそのまま受け取り、trim 責任は「ユーザーが SettingsView で入力時にコピペ時の余白」を自分で削除する想定か、または「API key は通常コピペで正確なため trim 不要」と判断している可能性
- **Scribe だけ trim getter** がある理由: 不確か（仮説）Scribe は guard で isEmpty チェックする流れで、empty な判定が critical だから trim 時点で stricter にする設計か、または simplify review でこの 3 箇所の duplicated trim を consolidate する過程で意図的に Scribe 側にだけ getter を追加した可能性

---

## 3. 影響範囲（grep による uses 確認）

### trimmedElevenLabsApiKey の参照箇所

```
Sources/TypeToTalk/App/TypeToTalkApp.swift:230: guard !settings.trimmedElevenLabsApiKey.isEmpty
Sources/TypeToTalk/Managers/SettingsManager.swift:335: var trimmedElevenLabsApiKey: String { ... }
Sources/TypeToTalk/Managers/ScribeManager.swift:22: statusText = settings.trimmedElevenLabsApiKey.isEmpty ? "APIキー未設定" : "準備完了"
Sources/TypeToTalk/Managers/ScribeManager.swift:32: let apiKey = settings.trimmedElevenLabsApiKey
```

**計 4 箇所**: getter 定義 1 + 参照 3

### elevenLabsApiKey の「生」read 残存箇所

```
Sources/TypeToTalk/Managers/SettingsManager.swift:180: @Published var elevenLabsApiKey: String
Sources/TypeToTalk/Managers/SettingsManager.swift:181: didSet { UserDefaults.standard.set(...) }
Sources/TypeToTalk/Managers/SettingsManager.swift:251: self.elevenLabsApiKey = UserDefaults.standard.string(...) ?? ""
Sources/TypeToTalk/Managers/SettingsManager.swift:336: elevenLabsApiKey.trimmingCharacters(...)  ← getter の内部
```

**評価**: ✓ 整合性良好
- 生 elevenLabsApiKey は @Published プロパティ定義 + UserDefaults I/O のみ
- 外部利用者は全て `trimmedElevenLabsApiKey` 経由で access
- setter は SettingsView（未実装）経由で indirect だけ（予想）

---

## 4. 過去の類似実装（git log / コミット傾向）

### git log 直近 15 件の傾向

```
88e9567  fix: WhisperKit を @preconcurrency import に変更
64930e6  [フォI] feat: モードA/B の2ショートカット体制を追加
...
5c88970  [フォI] feat: なるべくそのままモード追加 (promptMode=asIs)
...
```

**注記**:
- 過去の trim 関連コミットは git log で明示的には出ない（今回が初の API key getter 追加か）
- `[フォI] / [フォK]` プレフィックスは既にあるが、current CLAUDE.md ルール（2026-04 以降）では "フォーメーション名を commit message に含めない" が正
- **resolvedBonsaiModelID / resolvedWhisperModelID の trim pattern** は既に確立済み（直近コミットでは確認できないが、SettingsManager.swift に存在）

### 類似の「複数箇所の重複 trim → getter に consolidate」パターン
- 直近では simplify review で「3箇所の `trimmingCharacters(in: .whitespacesAndNewlines)` 重複 → SettingsManager の getter に集約」という修正が実施された模様
- 過去の `[フォI] / [フォK]` では UserDefaults プロパティ追加 + SettingsView 条件分岐 + processText 分岐の **3 点セット** で既にパターン確立

---

## 5. 想定される副作用 / リスク

### A. trim 前後の比較（@MainActor 内での Sendability）

- **現状**: `trimmedElevenLabsApiKey` は `@MainActor` SettingsManager 内の純粋 getter（読取専用）
- **リスク**: なし。@Published プロパティ read が @MainActor context 内で安全に行われる
- **評価**: ✓ Swift 6 strict concurrency 適合

### B. groq/openAI との非対称性

- Scribe だけ getter を持つことで「trim policy が Provider ごとに異なる」という非直感的な状況が生じる
- **判断**: 不確か。groq/openAI 側は「API 仕様上 key に leading/trailing whitespace があると fail する」という制約が Groq/OpenAI 側に無いのか、または「ユーザーが正確にコピペすると仮定」しているのか
- **推奨**: future refactor で groq/openAI にも `trimmedGroqApiKey` / `trimmedOpenAIApiKey` を追加して揃える可能性がある。あるいは API Manager 側（OpenAICompatibleManager）で受け取り時に trim する設計に統一

### C. SettingsView での UI 未実装

- 現在 SettingsView に Scribe 選択時の API key 入力フィールドがない
- この getter だけがあって UI が無い状態は「設定画面から key を入力できない」 → 呼び出し側で trimmedElevenLabsApiKey.isEmpty だけがチェックできる矛盾
- **リスク度**: 中。ユーザーは Plist 編集か UserDefaults CLI で直接設定するしかない
- **対応**: Step 6 や後続フェーズで SettingsView に condition block を追加すべき

### D. multipart body のレスポンス processing

- ScribeManager.swift:83 では response を `.trimmingCharacters(in: .whitespacesAndNewlines)` している
- API key の trim とは異なり、レスポンス text の trim は「認識結果の前後空白除去」として機能
- **副作用**: 意図的な leading/trailing space がある場合は失われる。ただし Whisper 等でも同様（整形段階で自動 trim される流れ）

---

## 6. 制約条件

### Swift 6 strict concurrency / @MainActor との整合

```swift
@MainActor
class SettingsManager: ObservableObject {
    @Published var elevenLabsApiKey: String { ... }
    
    var trimmedElevenLabsApiKey: String {
        elevenLabsApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- ✓ 両プロパティとも @MainActor context 内
- ✓ elevenLabsApiKey.read は @MainActor guard で安全
- ✓ String.trimmingCharacters は Sendable（pure function）
- **結論**: Sendable / @MainActor 違反なし

### 命名規約との整合

- `trimmedElevenLabsApiKey` ← existing pattern `resolvedBonsaiModelID` に倣い `trimmed/resolved` prefix
- `elevenLabsApiKey` ← `groqApiKey`, `openAIApiKey` の camelCase パターン
- UserDefaults key = プロパティ名の camelCase（既存パターン）

### プロパティ定義パターンの一貫性

```swift
@Published var groqApiKey: String {
    didSet { UserDefaults.standard.set(groqApiKey, forKey: "groqApiKey") }
}
```

と同じ形式で elevenLabsApiKey が定義されている。trimmedElevenLabsApiKey は **getter のみ**（@Published ではない）なので didSet なし。これは `resolvedBonsaiModelID` と同パターン。

---

## 7. テスト戦略

### Build Success
- ✓ `./scripts/build_app.sh Debug` で成功（20260501E）
- ✓ Swift 6 strict concurrency エラーなし

### Unit Test（既存）
```
swift test --filter ModelSelectionTests
→ 17 tests, 0 failures ✓
```

不確か: ModelSelectionTests が `TranscriptionProvider` を直接検証しているか？（調査結果から見当たらない）

### テスト追加候補
1. **ScribeManager.transcribe()**: `trimmedElevenLabsApiKey` が empty の場合、空文字を返す
2. **ScribeManager.refreshStatusText()**: empty → "APIキー未設定", non-empty → "準備完了"
3. **SettingsManager.trimmedElevenLabsApiKey**: leading/trailing whitespace を正しく除去
4. **TypeToTalkCoordinator.toggleRecording()**: `.elevenLabsScribe` 選択時に guard が機能（API key empty check）

### 統合テスト（実機/シミュレータ）
- [ ] WhisperKit 既定動作は変わらず（provider 分岐のみ）
- [ ] Scribe 選択 + API key 未設定 → エラー表示（設定 UI 実装後）
- [ ] 永続化確認（UserDefaults）

---

## 8. 追加調査項目（Step 6 前に確認）

### A. groq/openAI の trim 方針
- OpenAICompatibleManager.processText() で API key を「そのまま」Authorization header に入れている
- ElevenLabs API は同じく header に `xi-api-key` を入れるが、Scribe 側で **trim 後** の値を使用
- **質問**: groq/openAI 仕様上、leading/trailing space があると API が fail するのか？それとも Scribe 特有の trim 必要なのか？

### B. SettingsView の未実装状況
- TranscriptionProvider picker は実装済み（L53）
- 条件分岐式 API key 入力は groq (L110-113) / openAI (L121-123) に存在
- **必須**: `if settings.transcriptionProvider == .elevenLabsScribe { ... API key input ... }` を追加

### C. Info.plist / Network 権限
- Groq/OpenAI 既使用なので network 権限は通っている想定
- Scribe も同じネット利用なので追加権限不要の想定だが、未検証

### D. ScribeManager の completeness
- ✓ statusText ("APIキー未設定" / "準備完了")
- ✓ transcribe(audioURL:language:) → ElevenLabs API call
- ? error handling / timeout（要件では 60 秒タイムアウト想定）
- ? hallucination filter（Scribe v2 の出力傾向は未検証。WhisperManager は filter_hallucinations がある）

---

## まとめ

### 現況
1. **trimmedElevenLabsApiKey getter の追加** は、SettingsManager の既存 resolved/trimmed パターンに揃った設計で、整合性 ✓
2. **3箇所の trim 重複が consolidate** されて呼び出し側がシンプル化 ✓
3. **ビルド成功、既存テスト全パス** ✓
4. **Swift 6 strict concurrency 準拠** ✓

### リスク
- **SettingsView に Scribe UI 未実装** → ユーザーが設定できない（中リスク）
- **groq/openAI との trim policy 非対称** → future refactor が必要か検討（低リスク、architectural）

### 推奨アクション
- Step 6 で SettingsView に Scribe 条件分岐を追加
- ScribeManager のエラーハンドリング / timeout の詳細実装確認
- groq/openAI の trim policy について仕様調査（将来の consistency 向上に向けて）

