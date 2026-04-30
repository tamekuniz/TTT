# 調査: Scribe を WhisperKit 並列 STT エンジンとして追加するための既存コード分析

## 1. 関連ファイル一覧

| パス | 役割 |
|---|---|
| `Sources/TypeToTalk/Managers/SettingsManager.swift` | UserDefaults backed 設定モデル。`TranscriptionProvider` enum / `transcriptionProviderRawValue` プロパティを保持 |
| `Sources/TypeToTalk/Managers/WhisperManager.swift` | WhisperKit ロード + `transcribe(audioURL:language:) async -> String` を提供。Coordinator が直接所有 |
| `Sources/TypeToTalk/Managers/AudioRecorder.swift` | 録音→ `temporaryDirectory/recording.wav` に書き出し → URL を返す |
| `Sources/TypeToTalk/Managers/OpenAICompatibleManager.swift` | Groq/OpenAI へ `URLSession` で POST。プレーン JSON。multipart は未対応 |
| `Sources/TypeToTalk/Managers/NetworkManager.swift` | `NWPathMonitor` で online/offline を `@Published var isOnline` として公開 |
| `Sources/TypeToTalk/App/TypeToTalkApp.swift` | `TypeToTalkCoordinator`（録音→文字起こし→整形→注入の総司令）と SwiftUI App 本体 |
| `Sources/TypeToTalk/Views/SettingsView.swift` | 設定画面。「聞き取り設定」GroupBox に `TranscriptionProvider` Picker が既にある |
| `project.yml` | XcodeGen 設定。`packages` で SwiftPM 依存追加 |
| `Package.swift` | （後続で確認）SwiftPM パッケージ定義 |
| `Tests/TypeToTalkTests/AudioRecorderTests.swift` | 録音タップハンドラのテスト |
| `Tests/TypeToTalkTests/ModelSelectionTests.swift` | （後続で確認）モデル選択ロジックのテスト |

## 2. 既存実装パターン

### TranscriptionProvider 拡張パターン
`SettingsManager.swift:3-14` に既に enum がある。WhisperKit 1ケースのみ:
```swift
enum TranscriptionProvider: String, CaseIterable, Identifiable {
    case whisperKit
    var displayName: String { ... }
}
```
**Picker は `TranscriptionProvider.allCases` を使うので**（`SettingsView.swift:54`）、enum にケース追加するだけで UI に自動的に出現する。これは既存パターンに乗れる強い設計。

### Provider 別 API key / model プロパティパターン
整形 AI 側は次のパターンで個別プロパティを持つ（`SettingsManager.swift:161-176`）:
```swift
@Published var groqApiKey: String { didSet { UserDefaults.standard.set(...) } }
@Published var groqModel: String { didSet { UserDefaults.standard.set(...) } }
@Published var openAIApiKey: String { ... }
@Published var openAIModel: String { ... }
```
init で UserDefaults から復元（`SettingsManager.swift:240-243`）。**Scribe も同じパターンで `elevenLabsApiKey` を追加すれば素直**。Scribe の model は `scribe_v2` 固定でも UI 露出しなくて良い（要件 5・スコープ外との整合）。

### Manager クラスの形（WhisperManager 模倣ポイント）
`WhisperManager.swift` は `@MainActor class ... ObservableObject`。主要 API:
- `transcribe(audioURL: URL, language: String = "ja") async -> String` ← **Scribe も同じシグネチャで実装すれば呼び出し側を最小変更で済ませる**
- ロード状態 (`loadState`, `statusText`, `isLoadingModel`) — Scribe は遅延ロード概念がないので簡略化可。ただし「準備完了/未設定/通信失敗」のステータス文字列は SettingsView のロードブロックに合わせて出すと UI 一貫性が取れる

### 設定画面の Provider 別条件分岐パターン
`SettingsView.swift:109-129` で `if settings.formatterProvider == .groq { ... API key/model 入力 ... }` を並べる方式。**聞き取り設定 GroupBox（line 50-96）にも同じパターンで `if settings.transcriptionProvider == .elevenLabsScribe { API key 入力 }` を追加するのが既存規約に沿う**。

### 整形 AI 呼び出しの分岐パターン
`TypeToTalkApp.swift:425-473` の `processText(_:with:mode:)` で `switch provider` する形（Groq/OpenAI/Bonsai）。**`toggleRecording()` の Whisper 呼び出し箇所（line 213-224）も同様に provider 分岐に変える**:
```swift
guard whisper.whisperKit != nil else { ... } // ← Whisper 限定の guard
var rawText = await whisper.transcribe(audioURL: audioURL, language: settings.whisperLanguage)
```
を、provider に応じて分岐する形に変更が必要。

## 3. 影響範囲（呼び出し側 / 依存）

### `whisper.transcribe(...)` の呼び出し箇所
- `TypeToTalkApp.swift:221-224` （`toggleRecording()` 内、唯一の呼び出し）

### `whisper.whisperKit != nil` の guard
- `TypeToTalkApp.swift:213-218`（録音停止後、Whisper モデル必須チェック）
- Scribe 選択時はこの guard をスキップする必要がある

### `TranscriptionProvider` の参照
- `SettingsManager.swift:236`（init）/ `283-286`（getter/setter）
- `SettingsView.swift:53-58`（Picker）

### `transcriptionProviderRawValue` の購読
- 現状 `setupFormatterStatusBindings()` には含まれていない（formatter 側のみ Combine 購読）
- Scribe 側も Coordinator が状態購読する必要があるかは Scribe Manager の状態仕様次第

### Coordinator のメンバ追加
- `whisper: WhisperManager`（`TypeToTalkApp.swift:25`）に並んで `scribe: ScribeManager` を追加
- `init()` で `self.scribe = ScribeManager(settings: settings)` を初期化

### SettingsView への注入
- `TypeToTalkApp.swift:631-639` で `SettingsView` に `whisper`, `bonsai`, `accessibility`, `coordinator` を注入。**`scribe` も追加注入する必要がある**（SettingsView がステータス表示する場合のみ。ステータス表示なしなら省略可）

## 4. 過去の類似実装（git log / 既存パターン）

git log（直近20件）を確認:
- 過去のフォーメーションは `[フォI]` `[フォK]` プレフィックス付きでコミットしているが、CLAUDE.md 現行ルール（2026-04 以降）では「フォーメーション名は含めない」が正。**今回のコミットメッセージは `feat: ...` 形式に従う**（既存リポジトリ規約 vs 全体方針の矛盾は CLAUDE.md 優先と判断）
- `5c88970 [フォI] feat: なるべくそのままモード追加 (promptMode=asIs)` — UserDefaults プロパティ追加 + SettingsView 条件分岐 + processText 分岐の 3 点セットで既に実績あり。Scribe 追加もこのパターンの再現で済む
- `380c996 [フォK] feat: Whisper hallucination 3層防御` — WhisperManager 内に hallucination フィルタを追加。Scribe 側もレスポンスに混入する想定の文字列があれば同等の処理が必要かは未検証（Scribe v2 の出力傾向は要観察）

## 5. 想定される副作用 / リスク

### A. 通信遅延でユーザーが「フリーズした」と誤認
- WhisperKit は M1 Pro なら数秒で完了するが、Scribe は **ネットワーク往復 + サーバー処理** で数秒〜数十秒かかりうる（音声長による）
- HUD パネル（`HUDPanelController`）は `processing` 状態で表示されるので視覚 FB は出るが、長時間処理のタイムアウト戦略が必要
- 推奨: URLSession の `timeoutIntervalForRequest` を 60 秒程度に設定。タイムアウト時はエラー HUD で明示

### B. オフライン時の挙動
- `NetworkManager.isOnline == false` のときに Scribe 選択されているとリクエスト失敗
- 整形 AI 側は `activeFormatterProvider` で Bonsai 自動 fallback がある（`TypeToTalkApp.swift:365-371`）が、STT 側に同様の自動 fallback を入れるかは要件次第
- **要件側の判断**: スコープ外として「Scribe 選択時にオフラインなら明示エラー、自動 WhisperKit fallback はしない」が無難（ユーザー意図の尊重）。Step 6 で UX 確認

### C. API key 未設定時のエラー
- `OpenAICompatibleManager.swift:12` は `apiKey.isEmpty` で素通し（元テキスト返す）。Scribe 側は元テキスト返せない（Whisper 結果ではないため意味不明）
- 推奨: API key 空のときは `transcribe()` が空文字を返し、Coordinator 側で「APIキーが設定されていません」エラーを表示

### D. multipart/form-data 構築の手間
- 既存の `OpenAICompatibleManager` は JSON のみ。multipart 構築コードは新規作成
- Swift で `URLSession` の multipart は手動で boundary 文字列を作る必要あり（実装は決まりきったコード、テスタブル）

### E. 音声ファイル形式・サイズ
- AudioRecorder は WAV (`recording.wav`) で書き出す。ElevenLabs Scribe v2 は major audio formats 対応で WAV は OK
- ファイルサイズ上限は 3.0GB だが、TTT の用途は短い録音なので問題なし
- ただし長時間録音時のメモリ使用 / アップロード時間は注意点

### F. リグレッションリスク
- WhisperManager / AudioRecorder / 整形 AI 周りは触らない設計を貫けばリグレッションは最小化できる
- Coordinator の `toggleRecording()` 内の guard とコール先を分岐させる箇所のみ変更
- 既存テスト（`AudioRecorderTests`, `ModelSelectionTests`）はそのままパスする想定

## 6. 制約条件

### コード規約
- Swift 6 Concurrency: `@MainActor` / `Sendable` / `actor` の規律を保つ
- macOS 14.0+: `URLSession.shared.data(for:)` async 版が使える（既存パターンと同様）
- ObservableObject + `@Published` で状態公開（既存 Manager と統一）

### 命名規約
- Provider enum ケース: lowerCamelCase（`whisperKit`, `groq`, `openAI`, `bonsai` に倣い `elevenLabsScribe`）
- API key プロパティ: `<provider>ApiKey`（`groqApiKey`, `openAIApiKey` に倣い `elevenLabsApiKey`）
- UserDefaults キー: プロパティ名と同じ camelCase 文字列

### Scribe API 仕様（[ElevenLabs 公式 docs](https://elevenlabs.io/docs/api-reference/speech-to-text/convert) 確認済み）
- Endpoint: `POST https://api.elevenlabs.io/v1/speech-to-text`
- Header: `xi-api-key: <API_KEY>`、`Content-Type: multipart/form-data`
- Body (form fields):
  - `file` (binary, **必須**) — 音声ファイル
  - `model_id` (string, **必須**) — `scribe_v2` を採用（最新・最高精度）
  - `language_code` (string, optional) — ISO-639-1（"ja"/"en" 等）。指定しないと自動検出
- Response: JSON `{ "text": "...", "language_code": "...", "language_probability": 0.97, "words": [...] }`
- 制約: 音声 100ms 以上、ファイル < 3.0GB

### TTT 既存制約
- WhisperKit を既定エンジンとして残す（要件 Constraint 1）
- API key は `UserDefaults` に保存（既存の Groq/OpenAI と統一、Keychain は使われていない）
- グローバルショートカット → 録音 → 文字起こし → 整形 → Accessibility 注入 のパイプラインは維持

### `.fon-target` ファイル不在
- `.foi-target` と `.fok-target` は存在するが `.fon-target` は無い。Step 8 で参照されるので **Step 4 のプランニング段階で `.fon-target` を作成する**（既存の .foi-target に倣う）

## 7. テスト戦略

### ユニットテスト（書ける範囲）
- `Tests/TypeToTalkTests/ScribeManagerTests.swift`（新規）
  - `transcribe()` の API key 空のとき空文字を返す
  - レスポンス JSON パースのバリエーション（成功 / `text` 欠落 / 不正 JSON）
  - URLSession を mock して、リクエストの multipart body に `file`/`model_id` が含まれるか
- `TranscriptionProvider` の enum 拡張に対する既存 ModelSelectionTests への影響確認

### 統合テスト（実機検証）
1. **WhisperKit 既定動作**: 録音 → WhisperKit で文字起こし → 注入。**設定変更前と完全に同じ挙動**
2. **Scribe 選択 + API key 入力**: 設定画面で Scribe 選択 → API key 貼り付け → 録音 → ElevenLabs API へ送信 → 注入が成功
3. **Scribe 選択 + API key 未設定**: 録音 → エラー表示「APIキーが設定されていません」
4. **Scribe 選択 + オフライン**: 録音 → エラー表示
5. **整形 AI チェーン**: Scribe 結果 → Groq/OpenAI/Bonsai の整形 → 注入（既存パイプライン健在）
6. **永続化**: アプリ再起動後も Scribe 選択と API key が維持される

### Step 6 着手前に追加確認すべき項目
- [ ] Package.swift の構成（外部依存追加が必要か。手動 multipart 実装なら不要）
- [ ] `ModelSelectionTests.swift` の現行内容（`TranscriptionProvider` を直接検証していないか）
- [ ] `Info.plist` の network 関連 key（既に Groq/OpenAI 使用しているのでネット権限は通っている想定）
- [ ] Scribe v2 のレスポンス hallucination 傾向（必要なら WhisperManager と同様のフィルタ）
