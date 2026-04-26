# investigation: なるべくそのままモード追加

## 1. 関連ファイル一覧

| パス | 役割 |
|---|---|
| `Sources/TypeToTalk/Managers/SettingsManager.swift` | 設定値の永続化と、`systemPromptForLanguageAndStyle(language:style:provider:)` で言語×文体×プロバイダー別 systemPrompt を組み立てる正本（lines 355–450）。`promptMode`（`@Published`、line 206）の宣言・初期化（init で `?? "custom"`、line 249）もここ |
| `Sources/TypeToTalk/Views/SettingsView.swift` | 「整形設定」GroupBox 内に Picker で `promptMode` を切り替える UI（lines 194–201）、custom 選択時のみ `TextEditor`（lines 203–215）、preset 選択時は説明テキスト（lines 216–220） |
| `Sources/TypeToTalk/App/TypeToTalkApp.swift` | `TypeToTalkCoordinator.processText(_:with:)`（lines 410–447）で `promptMode == "preset"` と else（custom）の2分岐を持ち、整形プロバイダー（Groq/OpenAI/Bonsai）に prompt を渡す呼び出し点 |
| `Sources/TypeToTalk/Managers/OpenAICompatibleManager.swift` | Groq/OpenAI 共通の REST 呼び出し。`processText(_:endpoint:model:apiKey:prompt:)` で system role に prompt 注入（line 18） |
| `Sources/TypeToTalk/Managers/BonsaiManager.swift` | ローカル MLX。`processText(_:prompt:modelID:)` で `ChatSession(... instructions: prompt ...)`（lines 38–67）に prompt 注入 |
| `Tests/TypeToTalkTests/ModelSelectionTests.swift` | 既存テスト群。`SettingsManager` を直接生成して `systemPromptForLanguageAndStyle` を呼ぶパターン確立済（lines 137–206）。promptMode デフォルト `"custom"` の検証も既存（line 134） |

## 2. 既存実装パターン

- **設定値の追加パターン**: `@Published var <name>: String { didSet { UserDefaults.standard.set(...) } }` を `SettingsManager` に追加し、`init` で `UserDefaults.standard.string(forKey:) ?? <default>` を読み込む（例: `promptMode` line 206/249、`textStyle` line 200/248）
- **enum 値の文字列定数管理**: `promptMode` は raw String（`"preset"` / `"custom"`）で扱われており enum 化されていない。Picker 側でも `.tag("preset")` のように直書き（SettingsView line 196/197）。本機能でも同じ raw String 流儀を踏襲する（`"asIs"`）
- **systemPrompt 組み立て**: 言語（ja/en） × 文体（desuMasu/daDearu/auto）× プロバイダー（軽量 Bonsai / 詳細 Groq+OpenAI）を `systemPromptForLanguageAndStyle` 1関数のスイッチで分岐（line 363–374）。実プロンプト本体は `japaneseBonsaiPrompt(style:)` / `japaneseDetailedPrompt(style:)` / `englishBonsaiPrompt()` / `englishDetailedPrompt()` の4関数（line 388–450）。Bonsai は few-shot 抜きの簡素版、Groq/OpenAI は few-shot 2例つきの詳細版で context window を配慮
- **promptMode 分岐の呼び出し点**: `TypeToTalkCoordinator.processText` のみ（grep で他箇所なし）。preset → `systemPromptForLanguageAndStyle` 呼び出し / それ以外 → `settings.systemPrompt` 直接使用、の二者択一
- **既存ユーザー保護方針**: コミット 16d3413 の本文「既存ユーザ互換: promptMode 初期値 "custom" で systemPrompt 温存」が示す通り、新値追加時は既存値を上書きしない方針で過去設計済み

## 3. 影響範囲

**書き換える箇所（3ファイル）**:
1. `SettingsManager.swift` — `systemPromptForLanguageAndStyle` の switch（または新関数）に `asIs` 分岐を追加。ja/en × Bonsai軽量/詳細 の4プロンプトを新設
2. `SettingsView.swift` — Picker に `Text("そのまま").tag("asIs")` を追加。`if settings.promptMode == "custom"` 分岐の else 側説明文を asIs にも対応させる
3. `TypeToTalkApp.swift:412` — `if promptMode == "preset"` を `if promptMode == "preset" || promptMode == "asIs"` に拡張。`systemPromptForLanguageAndStyle` がモードを受け取るように引数追加（または新関数呼び分け）

**触らない箇所**:
- `OpenAICompatibleManager.swift` / `BonsaiManager.swift` — prompt は文字列として外から渡されるだけなので無変更
- `WhisperManager.swift` — 文字起こし側。整形プロンプトとは無関係
- 既存 `systemPrompt`（custom 用）/ `textStyle` / `formatterLanguage` の永続化キー — 既存ユーザー設定に触らない

**呼び出しチェーン**:
```
SettingsView の Picker
  → settings.promptMode 更新（@Published、UserDefaults 永続化）
TypeToTalkCoordinator.processText
  → promptMode == "preset" or "asIs" → systemPromptForLanguageAndStyle
  → promptMode == "custom" → settings.systemPrompt
  → formatter.processText(prompt:) または bonsai.processText(prompt:)
  → API 呼び出し / MLX 推論
```

## 4. 過去の類似実装

- **コミット 16d3413（[フォK] feat: UI整理＋言語設定＋整形プロンプト構造化）**: `promptMode` / `formatterLanguage` / `textStyle` の3設定追加と、`systemPromptForLanguageAndStyle` 4テンプレート新設を一度に実施した直近の類似変更。既存ユーザー保護のため `promptMode` 初期値を `"custom"` にした設計判断はこのコミット由来。今回も「既存ユーザーが触らない限り挙動変えない」原則を踏襲する
- **テスト書き方**: 同コミットでテスト9件追加。`SettingsManager` を直接生成 → `systemPromptForLanguageAndStyle` 呼び出し → プロンプト本文に必要キーワード（「ですます調」「フィラー」「Whisper」等）が含まれるかを `XCTAssertTrue(prompt.contains(...))` で検証する流儀。同パターンで asIs テストを書ける

## 5. 想定される副作用 / リスク

- **既存ユーザー設定への影響**: `promptMode` の値域が増えるだけで、既存値（`"preset"` / `"custom"`）を読み込んだ場合の挙動は変わらない。**リスクなし**
- **systemPromptForLanguageAndStyle のシグネチャ変更**: 内部分岐に `mode` パラメータを足す案だと、テスト含む既存呼び出し全箇所の更新が必要（テスト4件、実呼び出し1件）。**新関数 `systemPromptForAsIs(language:provider:)` を追加する設計**にすれば既存シグネチャは温存でき、影響範囲が最小化する。本実装ではこの新関数案を採用する
- **AI モデル側の指示遵守**: 「整形しない」指示は LLM にとって苦手な領域（整形したがる）。プロンプトで「やってはいけないこと」を強く列挙し、few-shot 例で「フィラーと言い間違いだけ修正」を実演する必要あり。Bonsai（1-bit / 軽量）は特に指示遵守能力が低い可能性があり、軽量版でも few-shot を 1 例だけ入れる方針を取る
- **「言い間違い」の判定揺れ**: 何が言い間違いかは LLM の解釈に依存する（自己訂正キーワード「あ、違う」「いや」「やっぱり」のような明示的な訂正発言は安定して取れるが、暗黙的な訂正は揺れる）。プロンプトでは **明示的な訂正キーワードのある自己訂正** と **明らかな同音異義語の誤字** に絞ることを明記する
- **文体無視の徹底**: 「ですます」と「だ・である」が混在する WhisperKit 出力をそのまま通す指示。LLM は「自然に整える」癖を出しがちなので、プロンプトで「文体・語尾は触らない」ことを強く繰り返す必要あり

## 6. 制約条件

- **Swift 6 Concurrency-safe**: `SettingsManager` は `@MainActor` クラス（line 138）。関数追加時は MainActor 制約を継承すれば自然に守られる
- **macOS 14.0+ / SwiftUI**: SettingsView は SwiftUI。Picker の `.tag("asIs")` 追加だけで segmented スタイルに自動追従
- **命名規約**: `promptMode` は raw String（enum 化されていない）。本機能でも raw String `"asIs"` を使う。**enum 化リファクタは current_task のスコープ外**（リファクタ提案も simplify 段階で抑える）
- **UserDefaults キー**: `"promptMode"` を継続使用。新キーを増やさない
- **プロジェクトのフォーメーション運用**: 直近コミットはすべて `[フォK]` プレフィックスだが、今回は `[フォI]` プレフィックスでコミットする（フォーメーション skill 表示）
- **TTT はリリース前**: 既存ユーザーの互換性は配慮するが（要件 Constraints 3）、商用リリース後ほどのケアは不要。判断分岐ではあくまで「新モード追加」として扱う

## 7. テスト戦略

**Unit Test（必須、4件追加）** — `Tests/TypeToTalkTests/ModelSelectionTests.swift` に追記:

1. **`testSettingsManagerSystemPromptForAsIsJapaneseGroq`** — ja × Groq（詳細版）asIs プロンプトに「フィラー」「言い間違い」または「自己訂正」相当キーワード、および「文体」「整える」を **触らない指示** が含まれること、および few-shot 「入力:」「出力:」が含まれることを検証
2. **`testSettingsManagerSystemPromptForAsIsJapaneseBonsai`** — ja × Bonsai（軽量版）asIs プロンプトが Groq 版より短い（context window 配慮）こと、フィラー・言い直しキーワードが含まれること
3. **`testSettingsManagerSystemPromptForAsIsEnglish`** — en × OpenAI asIs プロンプトに英語のキーワード（`filler`, `correction`, `do not`, `style`/`tone`等）が含まれること、日本語キーワード（「ですます」「フィラー」）が混入していないこと
4. **`testSettingsManagerSystemPromptForAsIsIgnoresStyle`** — asIs モードでは `textStyle`（`desuMasu` / `daDearu`）を渡しても文体指示文（「ですます調で統一する」「だ・である調で統一する」）がプロンプトに含まれないこと（文体無視 Constraints 5 を機械的に検証）

**実機検証（手動、Step 8 でズンジー依頼）**:
- 設定画面の Picker に「そのまま」が現れる
- `promptMode = "asIs"` × Groq（または OpenAI）で「えーっと、明日は雨が降る、あっ、晴れだった」を音声入力 → 「明日は晴れる。」相当の出力（フィラー削除・自己訂正済み、文体・順序維持）
- `promptMode = "asIs"` で英語「Um, the meeting is at, like, 3, no, 4 o'clock tomorrow.」→「The meeting is at 4 o'clock tomorrow.」相当
- `promptMode = "preset"` / `"custom"` 既存モードに切り替えて、既存挙動が変わっていないこと

**ビルド検証**:
- `./scripts/build_app.sh` Debug ビルド成功
- `swift test` で既存16件 + 新規4件 = 20件 PASS
