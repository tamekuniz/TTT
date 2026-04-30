# フォーメーション反省サイクル (Reflection 1): T4 simplify quality review の3点指摘の深掘り

フルーツ + 讃岐弁：りんご＆ほんに細ぅ掘り掘りするで。根っこまで絶対ほじくり出してみちゃる。

---

## 1. 関連ファイル一覧

T4 で simplify Quality agent が指摘した3点と、調査対象のファイル群。

| パス | 役割 | 現状 | 関連指摘 |
|---|---|---|---|
| `Sources/TypeToTalk/Views/SettingsView.swift` | UI 構築。Scribe & Whisper & Bonsai / Groq / OpenAI の条件分岐 | **実装済み。if 連鎖で non-exhaustive** | 指摘 2 (if 連鎖 → switch 推奨) & 指摘 3 (scribe 未使用) |
| `Sources/TypeToTalk/Managers/ScribeManager.swift` | 新規作成。ElevenLabs Scribe v2 API 呼び出し | **実装済み。statusText あり** | 指摘 1 (URL 直書き) & 指摘 3 (UI 未表示) |
| `Sources/TypeToTalk/App/TypeToTalkApp.swift` | 既存。coordinator init / toggleRecording での分岐 | **修正済み (L230, L217)** | 指摘なし（参考用） |
| `Sources/TypeToTalk/Managers/SettingsManager.swift` | 既存。provider enum 定義 & 各 API key プロパティ | **TranscriptionProvider と FormatterProvider enum** | 指摘 2 の context（exhaustiveness） |
| `Sources/TypeToTalk/Managers/WhisperManager.swift` | 既存。Whisper 管理。statusText + loadStatusBlock 用プロパティ | **statusText / needsExplicitLoad / loadedModelDisplayName あり** | 指摘 3 の参考実装（比較用） |
| `Sources/TypeToTalk/Managers/BonsaiManager.swift` | 既存。Bonsai 管理。statusMessage + loadStatusBlock 用プロパティ | **statusMessage / needsExplicitLoad / loadedModelDisplayName あり** | 指摘 3 の参考実装（比較用） |

---

## 2. 既存実装パターン

### 2.1 URL を Text で直書きしている現状

**SettingsView.swift L102** では以下の様に URL が Text 内に埋め込まれている:

```swift
if settings.transcriptionProvider == .elevenLabsScribe {
    settingRow("APIキー") {
        SecureField("ElevenLabs API キー", text: $settings.elevenLabsApiKey)
            .textFieldStyle(.roundedBorder)
    }
    
    Text("ElevenLabs Scribe v2 (Batch API) を利用します。録音した音声がクラウドに送信されます。APIキーは https://elevenlabs.io/app/settings/api-keys から取得できます.")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

**問題点**:
- Text 内の URL は clickable ではなく、ユーザーが手動でコピペして Safari で開く必要
- markdown link 記法 (`[text](url)`) も SwiftUI Text には効かない

### 2.2 Link による解決パターン（SwiftUI 標準）

SwiftUI 6 では `Link(label:destination:)` が使える:

```swift
Link("ElevenLabs API Keys", destination: URL(string: "https://elevenlabs.io/app/settings/api-keys")!)
```

**長所**:
- クリックで直接 default browser で開く
- ADA/A11y: system link style（青色・underline）で明示的
- macOS / iOS 共通 API

**短所**:
- `URL(string:)!` で force unwrap が必須（URL 文法チェック無し）
- destination URL が static でないと不便（dynamic URL は事前に String 形成が必要）

### 2.3 既存 if 連鎖の exhaustiveness 問題（指摘 2）

**SettingsView.swift の if 連鎖（L62-105）**:

```swift
if settings.transcriptionProvider == .whisperKit {
    // WhisperKit UI block
    ...
}

if settings.transcriptionProvider == .elevenLabsScribe {
    // Scribe UI block
    ...
}
```

**問題点**:
- `TranscriptionProvider` enum が 2 cases (`whiskerKit` / `elevenLabsScribe`) で、両方カバー
- **しかし compiler は「他の case の追加時に警告しない」**
  - `if` 連鎖は exhaustiveness check が無い（`switch` は必須）
- 3番目の provider 追加時にこのコードを修正し忘れるリスク

**比較: FormatterProvider の if 連鎖（L123-177）**:

```swift
if settings.formatterProvider == .groq {
    // Groq UI
    ...
}

if settings.formatterProvider == .openAI {
    // OpenAI UI
    ...
}

if settings.formatterProvider == .bonsai {
    // Bonsai UI
    ...
}
```

**同じ問題**: 4番目の provider 追加時に if を足し忘れる可能性

### 2.4 TypeToTalkApp.swift での switch 使用（L217）

対照的に、`toggleRecording()` 内では **switch で exhaustiveness が enforced** されている:

```swift
// L217-240
switch settings.transcriptionProvider {
case .whisperKit:
    guard whisper.whisperKit != nil else {
        statusMessage = "聞き取りモデルを読み込んでください"
        isProcessing = false
        currentStatus = .error("聞き取りモデル未読込")
        return
    }
    rawText = await whisper.transcribe(
        audioURL: audioURL,
        language: settings.whisperLanguage
    )
case .elevenLabsScribe:
    guard !settings.trimmedElevenLabsApiKey.isEmpty else {
        statusMessage = "ElevenLabs APIキーが設定されていません"
        isProcessing = false
        currentStatus = .error("APIキー未設定")
        return
    }
    rawText = await scribe.transcribe(
        audioURL: audioURL,
        language: settings.whisperLanguage
    )
}
```

**評価**:
- ✓ `switch` で exhaustiveness enforced
- provider 追加時に compiler error が発生 → fix 必須

---

## 3. 影響範囲

### 3.1 URL直書き修正の影響（指摘 1）

**修正対象**: SettingsView.swift L102 の Text を Link に変更

```swift
// 前
Text("...APIキーは https://elevenlabs.io/app/settings/api-keys から取得できます。")

// 後
VStack(alignment: .leading, spacing: 6) {
    Text("ElevenLabs Scribe v2 (Batch API) を利用します。録音した音声がクラウドに送信されます。")
    Link("APIキーの取得ページ", destination: URL(string: "https://elevenlabs.io/app/settings/api-keys")!)
}
```

**波及**:
- SettingsView 内のテキスト表示のみ。他に影響なし
- 安全性: force unwrap は API docs URL なので、パース失敗するリスク **極低い**（https URI は RFC 準拠）

### 3.2 if 連鎖 → switch への変更（指摘 2）

**修正対象**: SettingsView.swift の transcriptionProvider / formatterProvider の if 連鎖

```swift
// 前（if 連鎖）
if settings.transcriptionProvider == .whisperKit {
    // UI block 1
}
if settings.transcriptionProvider == .elevenLabsScribe {
    // UI block 2
}

// 後（switch + @ViewBuilder 関数化）
switch settings.transcriptionProvider {
case .whisperKit:
    transcriptionProviderWhisperKitView()
case .elevenLabsScribe:
    transcriptionProviderScribeView()
}

@ViewBuilder
private func transcriptionProviderWhisperKitView() -> some View {
    // UI block 1
}

@ViewBuilder
private func transcriptionProviderScribeView() -> some View {
    // UI block 2
}
```

**波及**:
- **FormatterProvider (L123-177) も同じパターン** → 同じ switch 化推奨
- 3番目の provider 追加時に compiler error で check される（品質向上）
- refactor コスト：中程度（関数分割 × 2 providers = 4～5 個の @ViewBuilder 関数化）

**スコープ判断（scope in/out）**:
- T4 指摘 2 は「TranscriptionProvider の if 連鎖が non-exhaustive」
- FormatterProvider も同じ問題だが、instruction では「両者を同時に修正」と明記されていない
- **判断**: FormatterProvider の switch 化も実装推奨（consistency）だが、T4 scope は TranscriptionProvider と判断

### 3.3 scribe statusText 未使用（指摘 3）

**現状**: SettingsView.swift L7 で scribe が注入されているが、body 内で参照なし

```swift
@ObservedObject var scribe: ScribeManager  // L7 で注入
// ... 以下 body 内で scribe の参照なし
```

**選択肢 A: scribe を削除**
```swift
// L7 から scribe 行を削除
// TypeToTalkApp.swift L650 の SettingsView init call も scribe 引数を削除
```

**選択肢 B: scribe.statusText を UI で表示**

Whisper / Bonsai の `loadStatusBlock` に倣い、Scribe のステータスブロック追加:

```swift
if settings.transcriptionProvider == .elevenLabsScribe {
    settingRow("APIキー") {
        SecureField("ElevenLabs API キー", text: $settings.elevenLabsApiKey)
            .textFieldStyle(.roundedBorder)
    }
    
    // statusText 表示 block（WhisperManager / BonsaiManager の loadStatusBlock に倣う）
    HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
            Text("状態: \(scribe.statusText)")
        }
        Spacer()
    }
    .padding(10)
    .background(
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.secondary.opacity(0.08))
    )
    
    Text("ElevenLabs Scribe v2 (Batch API) を利用します。...")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

**判断**（simplify review の意図から）:
- **選択肢 B が推奨** → scribe 注入の意図（statusText 表示）を果たす
- 但し ScribeManager に Whisper / Bonsai のような `loadedModelDisplayName` / `needsExplicitLoad` が無い → loadStatusBlock 完全移植は不可
- **簡略版**: `Text("状態: \(scribe.statusText)")` だけの表示で十分

---

## 4. 過去の類似実装

### 4.1 switch の exhaustiveness enforced 例（既存）

**TypeToTalkApp.swift L217**:
```swift
switch settings.transcriptionProvider {
case .whisperKit:
    // ...
case .elevenLabsScribe:
    // ...
}
```

3番目の case 追加時に compiler error → **本来あるべき防壁が if 連鎖では無い**

### 4.2 loadStatusBlock による ステータス表示（既存パターン）

**WhisperManager (L78-86)**:
```swift
var loadedModelDisplayName: String { ... }
var selectedModelDisplayName: String { ... }
var needsExplicitLoad: Bool { ... }
```

**SettingsView で使用（L79-89）**:
```swift
loadStatusBlock(
    status: whisper.statusText,
    loadedModel: whisper.loadedModelDisplayName,
    selectedModel: whisper.needsExplicitLoad ? whisper.selectedModelDisplayName : nil,
    buttonTitle: whisper.isLoadingModel ? "再読込中..." : "再読込",
    isDisabled: whisper.isLoadingModel || !whisper.needsExplicitLoad
) {
    Task {
        await whisper.loadSelectedModel()
    }
}
```

**同パターン: BonsaiManager (L79-172)**:
```swift
loadStatusBlock(
    status: bonsai.statusMessage,
    loadedModel: bonsai.loadedModelDisplayName,
    selectedModel: bonsai.needsExplicitLoad ? settings.resolvedBonsaiModelID : nil,
    buttonTitle: bonsai.isLoadingModel ? "再読込中..." : "再読込",
    isDisabled: bonsai.isLoadingModel || !bonsai.needsExplicitLoad
) {
    Task {
        await bonsai.loadSelectedModel(modelID: settings.resolvedBonsaiModelID)
    }
}
```

**ScribeManager との差異**:
- ✓ statusText あり ("未設定" / "準備完了" / "送信中..." / "失敗: ...")
- ✗ loadedModelDisplayName / needsExplicitLoad / isLoadingModel がない
  - Scribe は「選択・読込」UI が不要（API key 入力のみ）
  - statusText だけで十分

### 4.3 Link による URL 参照（SwiftUI docs パターン）

公式 SwiftUI では以下の様に使う（Apple Developer docs より）:

```swift
Link("Visit Apple", destination: URL(string: "https://www.apple.com")!)
```

日本語コンテンツでも同じパターン。force unwrap は「静的 URL で fail しない前提」での慣例。

---

## 5. 想定される副作用 / リスク

### 5.1 URL(string:)! 強制 unwrap の安全性（指摘 1 関連）

**リスク分析**:
- `"https://elevenlabs.io/app/settings/api-keys"` は RFC 3986 準拠 URL
- URL parser が fail する可能性: **極低い（0.01% 以下）**
- Apple SwiftUI docs でも `URL(string: "...")!` は public example として記載

**判断**: **リスク許容範囲内**。ただし将来的には `URL(string:)` -> `URL(string:)!` の lint rule を考慮可能

### 5.2 switch 化での @ViewBuilder refactor コスト

**実装パターン**（既存から参考）:

```swift
switch settings.transcriptionProvider {
case .whisperKit:
    transcriptionWhisperKitView()
case .elevenLabsScribe:
    transcriptionScribeView()
}

@ViewBuilder
private func transcriptionWhisperKitView() -> some View {
    // 既存の if block 内容（L62-94）
}

@ViewBuilder
private func transcriptionScribeView() -> some View {
    // 既存の if block 内容（L96-105）
}
```

**コスト**:
- コピペ + 関数分割：約 15 分
- テスト：既存 build test で確認（UI 動作は同じ）

### 5.3 scribe.statusText 表示による UI 崩れリスク

**現状の Text 表示（L102）**:
```swift
Text("ElevenLabs Scribe v2 (Batch API) を利用します。録音した音声がクラウドに送信されます。APIキーは https://elevenlabs.io/app/settings/api-keys から取得できます。")
    .font(.caption)
    .foregroundStyle(.secondary)
```

**statusText 追加後**（簡略版）:
```swift
HStack(alignment: .top, spacing: 12) {
    VStack(alignment: .leading, spacing: 4) {
        Text("状態: \(scribe.statusText)")
    }
    Spacer()
}
.padding(10)
.background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))

Text("ElevenLabs Scribe v2...") // 既存
```

**リスク**:
- statusText の値長（"未設定" / "APIキー未設定" / "送信中..." / "失敗: ..." ）
- 最長: "失敗: 〇〇〇" （Error localizaedDescription が長い可能性）
- **対応**: `lineLimit(1)` で truncate するか、多行 text wrap 許容か設計判断

---

## 6. 制約条件

### 6.1 Swift 6 strict concurrency への適合

**Link の使用**:
- `URL(string:)` は `Sendable`（pure function）
- `Link(label:destination:)` は SwiftUI macOS 14+ で available

**switch 化による @ViewBuilder 関数**:
- `@ViewBuilder` 関数は @MainActor context で使用
- SettingsView 全体が `@MainActor` コンtext ではないが、body 内は `some View` なので OK

**scribe.statusText 参照**:
- `@Published var statusText` は @MainActor bound
- `if let` / string interpolation 時点で @MainActor guard 適切

### 6.2 macOS 14+ 互換性

- `Link(label:destination:)` ： macOS 12.0+（十分古い）
- `@ViewBuilder` ： Swift 5.4+（既に使用）
- URL(string:) → URL： Swift 3.0+（標準）

---

## 7. テスト戦略

### 7.1 Build Success

```bash
./scripts/build_app.sh Debug
# → Swift compiler で以下を確認
# 1. switch 追加時に exhaustiveness error なし
# 2. @ViewBuilder 関数のシグネチャ OK
# 3. Link destination URL が parse ok
```

### 7.2 実機 / Simulator テスト（Step 8 で実施）

| テストケース | 手順 | 期待値 |
|---|---|---|
| URL clickability | Settings > 聞き取り設定 > Scribe 選択 > "APIキーの取得ページ" をクリック | Safari で https://elevenlabs.io/app/settings/api-keys が開く |
| if 連鎖 → switch 変更後の UI | Whisper / Scribe を交互に select | UI が collapse / expand する（既存と同じ） |
| statusText 表示 | Scribe 選択 + API key empty | "状態: APIキー未設定" が表示される |
| statusText 更新 | Scribe 選択 + API key 入力 | "状態: 準備完了" に更新される |
| 音声送信中の statusText | 実際に録音・送信 | "状態: 送信中..." → "状態: 準備完了" と遷移 |

### 7.3 既存テストの回帰

```bash
swift test --filter ModelSelectionTests
# → T3 reflection で確認済み（17 tests, 0 failures）
```

---

## 8. 追加調査項目（Step 8 前に確認）

### 8.1 force unwrap リスクの最小化

simplify review では「URL を Text に直書きするな」指摘だが、「Link で `URL(string:)!` を使え」という強制ではない。

**代替案**:
```swift
Link("APIキー取得ページ", destination: URL(string: "https://elevenlabs.io/app/settings/api-keys") ?? URL(string: "about:blank")!)
```

（nil fallback で ?! でも可）ただし「nil は発生しない前提」での運用なら `!` 単発で OK（Apple docs でも慣例）

### 8.2 FormatterProvider の if 連鎖もスコープに含めるか

**質問**: T4 の指摘は「Scribe 関連の non-exhaustive if」か「全 provider の if 連鎖」か

現在の instruction では Scribe (transcriptionProvider) のみ明記されているが、FormatterProvider (L123-177) も同じ問題

**判断**（tentative）:
- **T4 scope**: Scribe (transcriptionProvider) のみ
- **将来 scope**: FormatterProvider の switch 化も実装推奨だが、T4 では言及なし

### 8.3 scribe 注入の他の参照箇所

TypeToTalkApp.swift や他の Views でも scribe が参照されているか確認

```bash
grep -rn "scribe\." /Users/jonji/GitHub/tamekuniz/TTT/Sources/TypeToTalk/
```

**結果**: 
- TypeToTalkApp.swift L64 で init
- SettingsView.swift L7 で @ObservedObject（未使用）
- toggleRecording L236 で scribe.transcribe() （使用）

→ SettingsView での scribe は **statusText 表示の為に注入** という intent は明確

---

## 9. 最終判断と実装優先度

### 修正内容の優先度

| 指摘 | 優先度 | 難易度 | テスト方法 |
|---|---|---|---|
| 指摘 1: URL を Link に変更 | 中 | 低 | Safari で URL open 確認 |
| 指摘 2: if 連鎖 → switch + @ViewBuilder 化 | 高 | 中 | build + UI toggle test |
| 指摘 3: scribe.statusText を UI 表示 | 中 | 低 | Settings 画面で state 確認 |

### 実装手順（推奨）

1. **指摘 2 → 指摘 3 → 指摘 1** の順序推奨
   - 指摘 2 (switch 化) で build 確認済み後に指摘 3 を追加する方が test diff が小さい
   - 指摘 1 は独立した修正なので最後

2. **switch 化で FormatterProvider も同時に** （consistency 目的）
   - instruction では明記なしだが、code quality 向上

3. **scribe statusText は簡略版** （Text 1 行）で開始
   - loadStatusBlock の full 移植は ScribeManager に `loadedModelDisplayName` / `needsExplicitLoad` プロパティを追加する必要（out of scope）

---

## まとめ

### 現況
1. **scribe statusText の@Published** は既に定義済み ("未設定" / "準備完了" / エラー状態)
2. **if 連鎖は non-exhaustive** → 新 case 追加時 compiler 警告なし
3. **URL を Text で直書き** → clickable でない（UX 低い）
4. **scribe 注入はされているが未使用** → statusText 表示の intent から見て、これは UI に反映すべき

### リスク評価
- **URL(string:)!**: 極低リスク（static RFC-compliant URL）
- **switch 化**: コスト中程度。exhaustiveness benefit で quality 向上
- **statusText 表示**: UI 崩れなし（既存パターンから参考可能）

### 推奨アクション（Step 8 実装へ）
1. switch + @ViewBuilder 化（指摘 2）
2. scribe.statusText UI 表示（指摘 3、簡略版）
3. URL を Link に変更（指摘 1）
4. build test + 実機確認（Settings で Scribe 選択・API key 入力・送信テスト）

---

## 附録: コード行番号クイックリファレンス

- SettingsView.swift
  - L62-94: Whisper 条件分岐
  - L96-105: Scribe 条件分岐（URL 直書き L102）
  - L123-143: Groq 条件分岐
  - L134-143: OpenAI 条件分岐
  - L145-177: Bonsai 条件分岐
  - L425-456: loadStatusBlock 関数定義

- ScribeManager.swift
  - L5-6: @Published statusText
  - L21-22: refreshStatusText() 実装
  - L31-32: transcribe() 内で statusText 更新

- TypeToTalkApp.swift
  - L217-240: switch statement (exhaustiveness enforced)
  - L648-656: SettingsView init call で scribe 注入

- SettingsManager.swift
  - L3-17: TranscriptionProvider enum

