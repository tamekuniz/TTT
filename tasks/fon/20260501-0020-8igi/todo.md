# Todo: ElevenLabs Scribe を STT 並列追加

## 設計方針サマリ

- WhisperManager は触らない（リグレッションリスク最小化）。
- `ScribeManager.swift` を新規作成し、`transcribe(audioURL:language:) async -> String` シグネチャを WhisperManager と揃える。
- Coordinator が `whisper` と `scribe` 両方をプロパティとして保有。`toggleRecording()` 内で `settings.transcriptionProvider` で分岐する。
- API key は UserDefaults に保存（既存の `groqApiKey` / `openAIApiKey` パターン踏襲）。
- model_id は `scribe_v2` 固定。UI 露出しない（要件スコープ外）。
- multipart/form-data は手動構築（URLSession `Foundation` 標準で完結）。

## タスク

- [ ] T1: SettingsManager に Scribe 関連 enum ケースとプロパティを追加
    - **対象ファイル**: `Sources/TypeToTalk/Managers/SettingsManager.swift`
    - **編集対象**:
      - `TranscriptionProvider` enum (line 3-14) に `case elevenLabsScribe` を追加し、`displayName` に「ElevenLabs Scribe (クラウド)」を追加
      - `WhisperManager (ローカル)` の displayName を「WhisperKit (ローカル)」のまま維持
      - `@Published var elevenLabsApiKey: String { didSet { UserDefaults.standard.set(...) } }` を追加（line 169 付近、`openAIModel` の直後）
      - `init()` (line 235-281) に `self.elevenLabsApiKey = UserDefaults.standard.string(forKey: "elevenLabsApiKey") ?? ""` を追加
    - **期待挙動**: `TranscriptionProvider.allCases` で WhisperKit と Scribe 両方が返る。`settings.elevenLabsApiKey` が UserDefaults backed で読み書き可能。
    - **検証コマンド**: `swift build` でビルド成功 + `swift test --filter ModelSelectionTests` がパス（既存テストの破壊なし）
    - **備考**: enum ケース追加で `SettingsView.swift:54` の Picker に自動的に Scribe が出現する。

- [ ] T2: ScribeManager.swift を新規作成（ElevenLabs Scribe API クライアント）
    - **対象ファイル**: `Sources/TypeToTalk/Managers/ScribeManager.swift` (新規)
    - **編集対象**:
      - `@MainActor class ScribeManager: ObservableObject` を定義
      - `@Published var isTranscribing: Bool = false`
      - `@Published private(set) var statusText: String = "未設定"`（API key 設定状態を反映）
      - `init(settings: SettingsManager)` で `settings` を保持、`statusText` 初期化
      - `func transcribe(audioURL: URL, language: String = "ja") async -> String` を実装
        - `apiKey` 空 → 空文字 return + statusText 更新
        - multipart/form-data 構築: boundary 文字列作成、`file`, `model_id=scribe_v2`, `language_code` (auto/ja/en に応じて)
        - `URLSession.shared.upload(for:from:)` または `data(for:)` で POST
        - レスポンス JSON `text` フィールドを抽出
        - 失敗時は空文字 + statusText にエラー文を反映
      - エンドポイント: `https://api.elevenlabs.io/v1/speech-to-text`
      - Header: `xi-api-key: <apiKey>`、`Content-Type: multipart/form-data; boundary=<boundary>`
      - language="auto" のときは `language_code` を送らない（自動検出）、それ以外は ISO-639-1 を送る
    - **期待挙動**: `await scribeManager.transcribe(audioURL: someWavURL, language: "ja")` で API へ送信し文字起こし結果を返す。
    - **検証コマンド**: `swift build` でビルド成功
    - **備考**: テストは T5 で別途追加。Sendable / @MainActor 規律を守る。

- [ ] T3: TypeToTalkCoordinator に scribe を組み込み、toggleRecording() を provider 分岐に変更
    - **対象ファイル**: `Sources/TypeToTalk/App/TypeToTalkApp.swift`
    - **編集対象**:
      - `TypeToTalkCoordinator` に `@Published var scribe: ScribeManager` プロパティを追加（line 25 の `whisper` の直後）
      - `init()` (line 59-96) で `self.scribe = ScribeManager(settings: settings)` を初期化
      - `toggleRecording()` (line 197-282) の以下を変更:
        - 既存: `guard whisper.whisperKit != nil else { ... }` → provider 分岐に置き換え
          - WhisperKit 選択時は既存 guard 維持
          - Scribe 選択時は API key 空チェックに置き換え（statusMessage に「APIキーが設定されていません」、currentStatus = .error）
        - 既存: `var rawText = await whisper.transcribe(audioURL: audioURL, language: settings.whisperLanguage)` → provider 分岐:
          - WhisperKit: 既存呼び出し
          - Scribe: `await scribe.transcribe(audioURL: audioURL, language: settings.whisperLanguage)`
      - 設定画面注入箇所 (line 631-639) で `SettingsView` に `scribe: coordinator.scribe` を追加
    - **期待挙動**: WhisperKit 選択時は従来通り、Scribe 選択時は ElevenLabs API へリクエスト送信される。
    - **検証コマンド**: `swift build` でビルド成功
    - **備考**: synchronizeModelsForCurrentSettings() の WhisperKit 自動ロードは Scribe 選択時もそのまま動かして良い（後で WhisperKit に戻したときに即使えるため）。

- [ ] T4: SettingsView に Scribe API key 入力欄を追加
    - **対象ファイル**: `Sources/TypeToTalk/Views/SettingsView.swift`
    - **編集対象**:
      - `generalSettings` 内の「聞き取り設定」GroupBox (line 50-96):
        - WhisperKit 専用 UI（モデル選択 Picker / カスタムモデル ID / loadStatusBlock / 説明 Text）を `if settings.transcriptionProvider == .whisperKit { ... }` で囲む
        - その後ろに `if settings.transcriptionProvider == .elevenLabsScribe { ... }` ブロックを追加:
          - `settingRow("APIキー") { SecureField("ElevenLabs API キー", text: $settings.elevenLabsApiKey) }`
          - 説明 Text: 「ElevenLabs Scribe v2 を利用します。録音した音声がクラウドに送信されます。APIキーは [https://elevenlabs.io/app/settings/api-keys](https://elevenlabs.io/app/settings/api-keys) から取得できます。」
      - `SettingsView` 構造体に `@ObservedObject var scribe: ScribeManager` を追加（line 4-9 の他 @ObservedObject の隣）
    - **期待挙動**: Picker で Scribe を選ぶと WhisperKit のモデル選択 UI が消え、API key 入力欄と説明テキストが現れる。
    - **検証コマンド**: `swift build` でビルド成功 + 実機 / シミュ で目視確認
    - **備考**: scribe を SettingsView に注入する関係で T3 で TypeToTalkApp.swift の SettingsView 呼び出しを更新済みになっている前提。

- [ ] T5: ScribeManager のユニットテストを追加
    - **対象ファイル**: `Tests/TypeToTalkTests/ScribeManagerTests.swift` (新規)
    - **編集対象**:
      - `URLProtocol` を継承した mock クラスを用意し、`URLSession` を差し替え可能な構造にする（`ScribeManager` の URLSession を init で受け取る形にリファクタする必要があるかは T2 完成後に判断、必要なら T2 を最小修正）
      - テストケース:
        1. API key 空のとき `transcribe()` が空文字を返す
        2. mock レスポンスで `text` フィールド付き JSON → 文字列が返る
        3. mock レスポンスで `text` 欠落 → 空文字
        4. mock レスポンスで HTTP 401 → 空文字（statusText がエラーになる確認は省略可）
        5. multipart body に `file` / `model_id=scribe_v2` / `language_code=ja` が含まれることを assert
    - **期待挙動**: `swift test --filter ScribeManagerTests` で全テストパス
    - **検証コマンド**: `swift test --filter ScribeManagerTests`
    - **備考**: T2 で `ScribeManager` の URLSession を inject 可能に設計しておけばテスト容易。注入できない場合は最小リファクタを T5 内で実施。

- [ ] T6: README に Scribe 設定手順とプライバシー注記を追加
    - **対象ファイル**: `README.md`
    - **編集対象**:
      - `## ✨ 特徴` の「🚀 M1 Pro / Apple Silicon 最適化」項目に「（または ElevenLabs Scribe v2 のクラウド文字起こしも選択可能）」を併記
      - `## 🛠️ 技術スタック` の「Audio Engine」を「WhisperKit / ElevenLabs Scribe v2 (Batch API)」に更新
      - `## 🚀 セットアップ` に「### 5. STT エンジンの選択」セクションを追加（WhisperKit がデフォルト、Scribe を使う場合は API キー入力）
      - `## ✨ 特徴` の「🔒 プライバシー第一」に「**Scribe を選択した場合は録音音声が ElevenLabs サーバーへ送信されます**。WhisperKit 選択時のみ完全オンデバイスです。」を追記
    - **期待挙動**: README が更新内容と整合し、ユーザーが Scribe 利用方法とプライバシー上の差を理解できる。
    - **検証コマンド**: 目視確認（プレビューレンダリング）
    - **備考**: なし

- [ ] T7: .fon-target ファイル作成
    - **対象ファイル**: `.fon-target` (新規)
    - **編集対象**:
      - 既存の `.foi-target` を踏襲して、`VERSION_FILE_1_PATH=project.yml`, `VERSION_FILE_1_KEY=CURRENT_PROJECT_VERSION`, `VERSION_FORMAT="YYYYMMDD + 連番アルファベット"`, `DEPLOY_COMMAND="./scripts/build_app.sh"` 等を記述
    - **期待挙動**: フォN Step 8 が `.fon-target` を読み込んでバージョン更新と検証コマンドを出せる
    - **検証コマンド**: `bash -c 'source .fon-target && echo $VERSION_FILE_1_PATH'` で値が出る
    - **備考**: Step 8 の前に存在していれば良いので、最後でも良い。ただ T1〜T6 のサイクル完走後に Step 8 で困らないよう、サイクル進行中に作っておくのが安全。

## タスク間依存

- T1 → T2 → T3 → T4 はシリアル（前タスクの成果物を後タスクが参照）
- T5 は T2 後に実施（テスト対象が ScribeManager）
- T6, T7 は独立、いつでも可

## 完了の基準

各タスクが「実装 + ビルド成功 + 関連テストパス（書ける場合）」で個別 done。
全タスク完了後 Step 8 で **実機（ローカル Mac）E2E 検証**:
- WhisperKit 選択で録音→注入が動く
- Scribe 選択 + API key 設定で録音→注入が動く
- API key 空 / オフラインでエラー表示が出る
