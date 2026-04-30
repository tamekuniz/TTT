# Progress: ElevenLabs Scribe を STT 並列追加

## T1: SettingsManager に Scribe 関連 enum ケースとプロパティを追加

状態: 完了
- `TranscriptionProvider` enum に `case elevenLabsScribe` 追加 + displayName "ElevenLabs Scribe (クラウド)"
- `@Published var elevenLabsApiKey: String` 追加（didSet で UserDefaults 永続化）
- init で UserDefaults から復元
- ビルド検証: `./scripts/build_app.sh Debug` で BUILD SUCCEEDED 確認（build number 20260501B）
- simplify レビュー: reuse / quality / efficiency 全観点で重大問題なし、修正なし

## T2: ScribeManager.swift を新規作成（ElevenLabs Scribe API クライアント）

状態: 完了
- `Sources/TypeToTalk/Managers/ScribeManager.swift` 新規作成（@MainActor class, ObservableObject）
- `transcribe(audioURL:language:) async -> String` シグネチャを WhisperManager と揃える
- POST `https://api.elevenlabs.io/v1/speech-to-text`、`xi-api-key` ヘッダ、multipart/form-data（model_id=scribe_v2 / language_code / file）
- `URLSession` 注入可能（init second arg、デフォルト `.shared`）→ T5 のテストで mock しやすい
- `makeMultipartBody` を static 純粋関数で分離
- `statusText` 状態: 未設定 / APIキー未設定 / 準備完了 / 送信中... / 失敗: HTTP N / 失敗: レスポンス形式不正 / 失敗: error message
- ビルド検証: BUILD SUCCEEDED（build number 20260501C）
- simplify レビュー: reuse / quality / efficiency 全観点で重大問題なし、修正なし

## T3: TypeToTalkCoordinator に scribe を組み込み、toggleRecording() を provider 分岐に変更

状態: 完了
- `TypeToTalkCoordinator` に `@Published var scribe: ScribeManager` プロパティ + init 初期化
- `toggleRecording()` 内 `switch settings.transcriptionProvider` で WhisperKit / Scribe 分岐（exhaustive、default なし）
- WhisperKit 分岐は既存 guard 維持、Scribe 分岐は `settings.trimmedElevenLabsApiKey.isEmpty` で API key 未設定エラー
- simplify Reuse agent 由来の追加修正: SettingsManager に `trimmedElevenLabsApiKey` getter 追加 → 3箇所の trim 重複を集約（`resolvedWhisperModelID` / `resolvedBonsaiModelID` 慣習に整合）
- ビルド検証 (loop=0): BUILD SUCCEEDED 20260501D / (loop=1) BUILD SUCCEEDED 20260501F
- simplify 再レビュー (loop=1): reuse / quality / efficiency 全観点で修正なし
- reflection (loop=0): investigation-r0.md 生成（trim getter 整合性確認、groq/openAI との非対称性は別タスク提案として捨てた）

### 進捗履歴
- Step 6 (loop=0) 実装: Coordinator に `scribe: ScribeManager` プロパティ + init 初期化 + `toggleRecording()` の `switch settings.transcriptionProvider` 分岐
- Step 7 testing: BUILD SUCCEEDED（build number 20260501D）
- Step 7 simplify: Reuse agent が `elevenLabsApiKey.trimmingCharacters(in: .whitespacesAndNewlines)` の3箇所重複を指摘 → SettingsManager に `trimmedElevenLabsApiKey` getter 追加 + ScribeManager 2箇所 + TypeToTalkApp 1箇所 を置換
- Step 7 → reflection 経由（simplify がコード変更したため再 testing 必須）

### Reflection 4項目（loop=0、investigation-r0.md 参照）

1. **Root Cause Investigation（戻り理由）**:
   - 真の失敗ではなく、simplify Reuse agent が「trim 重複3箇所を SettingsManager の getter に集約すべき」と指摘し、独自に修正を実施したため、フォNルール「simplify が修正を入れた → 必ず再テスト」に従って reflection 経由に戻された
   - 該当箇所: `investigation-r0.md §1` 修正後ファイル一覧 / `§3` 影響範囲（grep `trimmedElevenLabsApiKey` で4参照、`elevenLabsApiKey` 生 read は SettingsView の API key 入力欄想定で残置）
   - simplify の修正自体は技術的に妥当（DRY、`resolvedWhisperModelID` / `resolvedBonsaiModelID` 慣習に整合）

2. **Pattern Analysis（動作リファレンスとの差異）**:
   - 既存 `groqApiKey` / `openAIApiKey` は trim getter なしで `OpenAICompatibleManager` が直接 raw read（API key 空チェックは `apiKey.isEmpty` でのみ）。Scribe だけ trim getter があるのは現状非対称
   - ただし SettingsManager 内には `resolvedWhisperModelID` / `resolvedBonsaiModelID` / `whisperDisplayName` / `bonsaiDisplayName` 等の `resolved/displayName` 系 getter が複数存在 → trim getter は同パターン拡張として正当
   - groq/openAI の trim policy 統一は別タスク提案（current_task T3 のスコープ外、investigation-r0.md §8 「追加調査項目」記録）
   - 前ループでの変更内容: simplify Reuse agent の独立修正（3箇所置換 + 1 getter 追加）

3. **Hypothesis（単一仮説）**:
   - simplify の修正は技術的に妥当で、既存の resolved 系慣習に合致しており、リグレッションリスクなし。再ビルドで BUILD SUCCEEDED が再現でき、Quality / Efficiency 観点でも問題が出ない、と仮説する
   - 理由: ① `trimmedElevenLabsApiKey` は computed property で副作用なし、② @MainActor 整合、③ 呼び出し側は3箇所すべて意味的に同等な置換

4. **Implementation 計画（単一修正）**:
   - 追加実装は **行わない**（simplify が既に修正済み）
   - 再 testing で `./scripts/build_app.sh Debug` がビルド成功するか検証
   - simplify の Quality / Efficiency 残り2エージェントを起動して、Reuse 修正後のコードに対する追加指摘がないか確認
   - 全観点で問題なければ verified に進む

## T4: SettingsView に Scribe API key 入力欄を追加

状態: 完了
- SettingsView 構造体に `@ObservedObject var scribe: ScribeManager` 追加 + TypeToTalkApp の Settings 注入で `scribe: coordinator.scribe` 追加
- 「聞き取り設定」GroupBox を `switch settings.transcriptionProvider` で provider 別 view 分岐（exhaustive、新 case 追加時にコンパイル時検出）
- WhisperKit ケース: 既存 UI（モデル選択 / カスタムID / loadStatusBlock / 説明文）をそのまま囲む
- Scribe ケース: `SecureField` で API key 入力、`Text("状態: \(scribe.statusText)")` で statusText 表示、SwiftUI Text の Markdown リテラル `Text("APIキーは [ElevenLabs API Keys](URL) から取得できます。")` で URL リンク化
- ビルド検証: (loop=1) 20260501G / (loop=2) 20260501H / (loop=3) 20260501I いずれも BUILD SUCCEEDED
- simplify レビュー (loop=1, 2, 3): 計3サイクル。最終 (loop=3) は最小修正で完成（HStack 削除 + Markdown Text 化で URL force unwrap + font/foregroundStyle 三重指定 + HStack 冗長 を一括解消）
- reflection (loop=1, 2): Quality 指摘採用の正規ルート遵守（researcher 起動 → investigation-r{N}.md 生成 → 4項目 progress.md 追記）

### Reflection 4項目（loop=2、investigation-r2.md 参照）

1. **Root Cause Investigation**: simplify Quality 再レビューで以下指摘:
   - **(a) URL force unwrap** (line 116): `URL(string: ...)!` が view body 内で評価される
   - **(b) HStack による文組み立てが冗長** (line 110-122): 3 Text + Link が HStack で並び、`.font(.caption).foregroundStyle(.secondary)` が3重指定。SwiftUI Text の Markdown リテラル `Text("APIキーは [ElevenLabs API Keys](URL) から取得できます。")` で1つの Text に集約できる

2. **Pattern Analysis**: investigation-r2.md より:
   - SwiftUI Text Markdown リテラルは **macOS 12+** で完全サポート（TTT は macOS 14+ 対応で問題なし）
   - TTT 内に既存 Markdown リテラル使用例は無い（新規採用だが SwiftUI 標準）
   - 1 つの Text に集約することで HStack 削除 + force unwrap 解消 + font/foregroundStyle 三重指定削減が同時達成
   - 前ループ修正（loop=1）で Link を独立要素として組んだが、Markdown リテラルの方が SwiftUI 慣用で簡潔

3. **Hypothesis（単一仮説）**: HStack + 3 Text + Link を `Text("APIキーは [ElevenLabs API Keys](https://elevenlabs.io/app/settings/api-keys) から取得できます。").font(.caption).foregroundStyle(.secondary)` に置換することで、Quality 指摘 (a) と (b) が同時解消、ビルド成功する

4. **Implementation 計画（単一修正）**: SettingsView.swift line 110-122 の VStack 内 HStack を削除して、Markdown リテラルの Text 1 個に置き換える。

### 進捗履歴
- Step 6 (loop=1) 実装: SettingsView 構造体に `scribe: ScribeManager` 注入、「聞き取り設定」GroupBox を `if settings.transcriptionProvider == .X` で provider 別分岐、Scribe 選択時に SecureField + 説明文追加。TypeToTalkApp の SettingsView 呼び出しに `scribe: coordinator.scribe` 追加
- Step 7 testing (loop=1): BUILD SUCCEEDED 20260501G
- Step 7 simplify (loop=1): Quality agent から3点指摘
- Step 7 → reflection (loop=1)

### Reflection 4項目（loop=1、investigation-r1.md 参照）

1. **Root Cause Investigation（戻り理由）**:
   - simplify Quality agent が3点指摘:
     - **(a) URL を Text 直書き** (SettingsView L102): `Text("...https://elevenlabs.io/app/settings/api-keys から取得できます。")` がクリック不可、UX 劣化
     - **(b) provider 別 if 連鎖が non-exhaustive** (L62, L96, ほか FormatterProvider 側 L123-145): 新 case 追加時にコンパイラが網羅性を検出しない
     - **(c) `scribe: ScribeManager` が未使用** (L7): 注入したのに view body 内で参照していない、dead code 候補
   - investigation-r1.md §3「影響範囲」より、(a) は SettingsView 内のみ、(b) は SettingsView の聞き取り設定 GroupBox 内、(c) は scribe statusText 表示するか削除するかの2択

2. **Pattern Analysis（動作リファレンスとの差異）**:
   - investigation-r1.md §2/§4 より:
     - **(a)**: TTT 内に `Link` 利用例は無いが、SwiftUI 標準 API で `Link("text", destination: URL(string:)!)` で簡単に対応可能
     - **(b)**: TypeToTalkApp.swift L217-240 の `toggleRecording()` が `switch settings.transcriptionProvider` で exhaustive 化済み。SettingsView も同パターンに揃えるべき
     - **(c)**: WhisperManager / BonsaiManager は `loadStatusBlock` で `statusText` 表示。Scribe にも同等表示が UX 整合（ScribeManager.statusText は「未設定 / APIキー未設定 / 準備完了 / 送信中... / 失敗:...」）
   - 前ループ（T3 reflection loop=0）との差: T3 は trim 重複の集約、T4 は UI 層の品質改善で別観点

3. **Hypothesis（単一仮説）**:
   - 3点を1サイクルで対応（同一 SettingsView 内の関連修正）することで、コンパイル時 exhaustive 化 + UX 向上 + dead 解消が達成できる、と仮説する
   - 理由: investigation-r1.md §3「影響範囲」の通り、3点は SettingsView 内に閉じる修正で互いに独立。同一 view の同一セクションで一気に整理する方が PR の一貫性が高い

4. **Implementation 計画（単一修正）**:
   - **(a) Link 化**: 説明 Text を `VStack` で分割し、URL 部分を `Link("ElevenLabs API Keys", destination: URL(string: "https://elevenlabs.io/app/settings/api-keys")!)` に置換
   - **(b) switch 化**: 「聞き取り設定」GroupBox 内の `if settings.transcriptionProvider == .X` 連鎖を `switch settings.transcriptionProvider` に変更、各 case 内で既存 view を直接書く（ViewBuilder サブ関数化は今回スコープ外、シンプルに維持）
   - **(c) scribe statusText 表示**: Scribe 選択時の説明文の上に `Text("状態: \(scribe.statusText)")` を1行追加（軽量、loadStatusBlock 全機能は不要）
   - **FormatterProvider 側の if → switch 化は別タスク提案**（current_task T4 のスコープ外、investigation-r1.md §3 で明記）

## T5: ScribeManager のユニットテストを追加

状態: 完了
- `Tests/TypeToTalkTests/ScribeManagerTests.swift` 新規作成（6テストケース）
- `MockURLProtocol` による URLSession の差し替えで API 通信をモック
- テスト内容:
  1. APIキー空時に空文字返却 + statusText "APIキー未設定"
  2. 正常 JSON レスポンス (text フィールド) → 文字列返却
  3. JSON に text 欠落 → 空文字 + statusText "失敗: レスポンス形式不正"
  4. HTTP 401 → 空文字 + statusText "失敗: HTTP 401"
  5. multipart body に file/model_id=scribe_v2/language_code=ja が含まれる
  6. language="auto" 時に language_code フィールドが含まれない
- 実装側修正（Swift 6 strict concurrency 対応 + 設計バグ修正）:
  - `static func makeMultipartBody` → `nonisolated static func` に変更
  - `private static let endpoint/modelID/requestTimeout` 3つを `nonisolated` 化（@MainActor 隔離継承の連鎖解消）
  - `defer { isTranscribing = false; refreshStatusText() }` を `defer { isTranscribing = false }` に変更（observable state を defer で上書きしない）
  - 成功 return 直前に `statusText = "準備完了"` を明示設定（エラー時は statusText がエラー文のまま維持）
- ビルド検証: BUILD SUCCEEDED 20260501J、`swift test --filter ScribeManagerTests` 6/6 PASS
- reflection 経由 (loop=3, 4, 5、計3回): r3.md (nonisolated 適用見落とし) → r4.md (静的定数連鎖、loop>3 アーキテクチャ検討) → r5.md (defer 設計バグ、loop>3 アーキテクチャ検討)

### Reflection 4項目（loop=5、investigation-r5.md 参照、loop > 3 でアーキテクチャ検討必須）

1. **Root Cause Investigation**: テスト 6 件中 2 件失敗（コンパイル成功）
   - `testTranscribeReturnsEmptyStringOnHTTP401`: 期待 `"失敗: HTTP 401"` / 実際 `"準備完了"`
   - `testTranscribeReturnsEmptyStringWhenTextFieldMissing`: 期待 `"失敗: レスポンス形式不正"` / 実際 `"準備完了"`
   - 原因: ScribeManager.swift L38-42 の `defer { isTranscribing = false; refreshStatusText() }` が、エラー時に設定した `statusText = "失敗: ..."` を `transcribe()` 終了時に「準備完了」/「APIキー未設定」へ即上書きしている

2. **Pattern Analysis** (investigation-r5.md):
   - WhisperManager / BonsaiManager の同種メソッドは defer で statusText を機械的にリセットしておらず、各分岐で明示的に statusText を設定する pattern
   - 設計上の本質: **defer は cleanup 責務であり、observable state (statusText) の上書きには使うべきでない**。statusText の責務は「最後の操作結果の表示」
   - **アーキテクチャ検討（loop > 3 必須）**:
     - 案A（推奨）: `defer` から `refreshStatusText()` を削除し、成功 return 直前に `statusText = "準備完了"` を明示設定。エラー時の statusText はそのまま維持される
     - 案B: `refreshStatusText()` を条件分岐させる（lastError プロパティ等で複雑化）→ fragile、却下
     - 案C: 成功時のみ refreshStatusText() を呼ぶ → 案A と実質同等

3. **Hypothesis（単一仮説）**:
   - `defer { isTranscribing = false }` のみとして、成功 return 直前に `statusText = "準備完了"` を1行追加すれば、エラー時の statusText が維持され、6 テスト全パスする。WhisperManager / BonsaiManager と一貫した設計になり、UX 上も「失敗が見える」改善
   - 理由: investigation-r5.md の比較表より、defer の責務明確化 + observable state の明示更新が Swift 6 async/await 時代のベストプラクティス

4. **Implementation 計画（単一修正）**:
   - ScribeManager.swift L38-42 の `defer { isTranscribing = false; refreshStatusText() }` を `defer { isTranscribing = false }` に変更
   - L83 の `return text.trimmingCharacters(...)` の直前に `statusText = "準備完了"` を1行追加（成功時のみ）
   - **「ついでに」修正禁止**、この2箇所のみ

### Reflection 4項目（loop=4、investigation-r4.md 参照、loop_count > 3 でアーキテクチャ検討必須）

1. **Root Cause Investigation**: r3.md 修正適用後の二次エラー
   - `error: main actor-isolated static property 'modelID' can not be referenced from a nonisolated context` (ScribeManager.swift L104)
   - 根本原因: @MainActor class の **全 static member は暗黙的に main actor isolation を継承**。func だけ nonisolated 化しても、参照先の static let（modelID）が isolated なら参照不可
   - r3.md は func の隔離解除のみ計画していたが、参照先 static property の隔離も同時に解除する必要があった

2. **Pattern Analysis** (investigation-r4.md §3-§4):
   - WhisperManager / BonsaiManager は static member を持たないので問題化していない（外部依存ライブラリ呼び出しが主体）
   - AudioRecorder.makeTapHandler は `nonisolated static func` で他 static property への参照なし（self-contained）→ 問題化しない
   - ScribeManager は **@MainActor class 内に「endpoint / modelID / requestTimeout」の静的定数 + 純粋関数 makeMultipartBody」を持つ唯一の構造**。Swift 6 strict concurrency と相性が悪い設計
   - **アーキテクチャ検討（loop > 3 必須）**:
     - 案A（推奨）: 全 static member に `nonisolated` 追加（最小施工、既存呼び出しと整合）
     - 案B: makeMultipartBody + 関連定数を ScribeManager 外に切り出し（free function or enum namespace）→ 修正範囲広い
     - 案C: ScribeManager から @MainActor 削除 → @Published / SwiftUI 連携に副作用大、却下
   - 推奨: **案A**（純粋データ・純粋関数を isolation-free にするのは Swift 6 のベストプラクティス、最小変更）

3. **Hypothesis（単一仮説）**: `endpoint`, `modelID`, `requestTimeout` の3つの static let に `nonisolated` を付与すれば、`makeMultipartBody` (nonisolated) からの参照が解決し、`transcribe` (MainActor) からの参照も従来通り動く。連鎖エラー終了、テスト全パスする
   - 理由: Swift 6 では nonisolated は MainActor からも参照可能（一方向許可）。3つとも純粋データ（URL/String/TimeInterval = Sendable）で副作用なし

4. **Implementation 計画（単一修正）**: ScribeManager.swift line 11-13 の3つの `private static let` に `nonisolated` キーワードを追加する。最小・的確。
   ```swift
   private nonisolated static let endpoint = ...
   private nonisolated static let modelID = ...
   private nonisolated static let requestTimeout = ...
   ```

### Reflection 4項目（loop=3、investigation-r3.md 参照）

1. **Root Cause Investigation**: `swift test --filter ScribeManagerTests` でコンパイルエラー
   - `error: call to main actor-isolated static method 'makeMultipartBody(...)' in a synchronous nonisolated context`
   - 根本原因: Swift 6 strict concurrency 下で、@MainActor class 内の修飾子なし static method は **暗黙的に @MainActor 隔離**。XCTestCase の nonisolated test 関数から sync で呼べない（ScribeManager.swift L92、ScribeManagerTests.swift L86, L107）
   - investigation-r3.md §2/§3 参照

2. **Pattern Analysis**: investigation-r3.md §3 より
   - **AudioRecorder.swift L112** の `nonisolated static func makeTapHandler(...)` が TTT 内唯一の正解パターン。明示的に隔離解除
   - AudioRecorderTests.swift は nonisolated test から同期で呼べている（line 23）
   - ScribeManager.makeMultipartBody は同種の純粋関数なのに `nonisolated` を欠いていた
   - 前ループ（loop=2 までの T4）はすべて UI 系修正で別観点

3. **Hypothesis（単一仮説）**: `static func makeMultipartBody` を `nonisolated static func makeMultipartBody` に変更すれば、テスト側・呼び出し側の変更なしで Swift 6 strict concurrency に適合し、コンパイル成功 + 6 テスト全パスする
   - 理由: AudioRecorder.makeTapHandler と完全に同パターン、Swift 仕様上正解、純粋関数（副作用なし）なので隔離解除に副作用リスクなし

4. **Implementation 計画（単一修正）**: `Sources/TypeToTalk/Managers/ScribeManager.swift` line 92 の `static func makeMultipartBody(` を `nonisolated static func makeMultipartBody(` に変更。**「ついでに」修正禁止**、この1箇所のみ

## T6: README に Scribe 設定手順とプライバシー注記を追加

状態: 完了
- 「✨ 特徴」を「🎙️ 聞き取りエンジン選択」セクションに改編し WhisperKit / Scribe を併記
- 「🔒 プライバシー第一」を Scribe / Groq / OpenAI 利用時の差分に応じて文言調整
- 「🛠️ 技術スタック」の Audio Engine 行を「WhisperKit / ElevenLabs Scribe v2 (Batch API)」に更新
- 「🚀 セットアップ」に新項「3. 聞き取りエンジンの選択」を追加（既存4項目を5項目にリナンバ）
- 末尾に「🔐 プライバシー注記」テーブルを追加（機能 / 送信先 / 送信内容 の対応表）
- 文言のみ変更でビルドへの影響なし

## T7: .fon-target ファイル作成

状態: 完了
- `.fon-target` 新規作成（`.foi-target` を踏襲）
- VERSION_FILE_1_PATH=project.yml / VERSION_FILE_1_KEY=CURRENT_PROJECT_VERSION
- VERSION_FORMAT="YYYYMMDD + 連番アルファベット"、VERSION_EXAMPLE="20260501A"
- DEPLOY_COMMAND="./scripts/build_app.sh"、DEPLOY_TARGET="ローカル Mac"、VERIFY_TYPE="ローカル起動確認"
- `bash -c 'source ./.fon-target && echo $VERSION_FILE_1_PATH'` で値が取れることを確認
