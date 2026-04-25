<!--
タスク分割の根拠:
- T1: 要件1（パス修正）と要件3（needsExplicitLoad リファクタ）はどちらも BonsaiManager.swift 内の小修正で、同じファイルを触るため1サイクルでまとめて実装・検証可能。SettingsView.swift:152 のパス表示文言も同時に確認する。
- T2: 要件2（AudioRecorder URL 活用）は Coordinator と AudioRecorder の連携。独立した責務のため単独タスク。
- T3: 要件4（ウインドウトグルショートカット）は KeyboardShortcuts.Name 追加 + Coordinator handler + SettingsView UI に跨る最大の変更。単独タスクとして集中実装。
-->

- [ ] T1: BonsaiManager のモデルパス修正と needsExplicitLoad リファクタ
  - 対象ファイル:
    - `Sources/TypeToTalk/Managers/BonsaiManager.swift`
    - `Sources/TypeToTalk/Views/SettingsView.swift`（パス表示文言の確認・必要なら更新）
    - `Tests/TypeToTalkTests/ModelSelectionTests.swift`（needsExplicitLoad 等価性の追加テスト）
  - 期待挙動:
    - `~/.ttt/models` を `~/.typetotalk/models` に変更し、新パスにモデルがダウンロードされる
    - `needsExplicitLoad` を `loadedModelID != currentSelectedModelID` にリファクタし、4 ケース（nil/同一/不一致）すべて意味的に等価
    - SettingsView のパス表示文言が新パス `~/.typetotalk/models` と一致
  - 備考:
    - 既存ユーザーの `~/.ttt/models/` キャッシュは孤児化するが、リリース前のため互換性は判断基準にしない
    - 等価性検証テスト（旧論理 vs 新論理の真理値表）を ModelSelectionTests に追加
    - WhisperManager のパターン（`loadedModelID != selectedModelID` 系）と命名規約を揃える

- [ ] T2: AudioRecorder の戻り値 URL を Coordinator が保持して活用
  - 対象ファイル:
    - `Sources/TypeToTalk/App/TypeToTalkApp.swift`
    - `Tests/TypeToTalkTests/AudioRecorderTests.swift`（戻り値 URL 検証テストの追加）
  - 期待挙動:
    - Coordinator に `@Published var recordingURL: URL?` を追加し、`startRecording()` の戻り値を捕捉
    - 文字起こしフェーズ（line 234 周辺）でハードコード `temporaryDirectory.appendingPathComponent("recording.wav")` を削除し、保持した `recordingURL` を使用
    - `AudioRecorder.startRecording()` が期待 URL を返すテストを追加
  - 備考:
    - URL は Sendable、@Published は @MainActor isolation で安全
    - 複数回 toggleRecording() で recordingURL が上書きされる動作を許容（既存の単一録音前提を維持）
    - フォールバックとして `recordingURL ?? temporaryDirectory.appendingPathComponent("recording.wav")` のような nil 時の安全網は実装時判断

- [ ] T3: ウインドウ表示トグル用ショートカット新規追加
  - 対象ファイル:
    - `Sources/TypeToTalk/App/TypeToTalkApp.swift`
    - `Sources/TypeToTalk/Views/SettingsView.swift`
    - `Tests/TypeToTalkTests/ModelSelectionTests.swift`（または新規テストファイル、`KeyboardShortcuts.Name.toggleWindow` 定義確認）
  - 期待挙動:
    - `KeyboardShortcuts.Name` に `static let toggleWindow = Self("toggleWindow")` を新規追加（デフォルトキー未割当）
    - Coordinator に `handleToggleWindow()` を実装し、`RecorderWindow` identifier の `isVisible` を見て `orderOut(nil)` / `makeKeyAndOrderFront(nil)` をトグル
    - Coordinator init で `KeyboardShortcuts.onKeyDown(for: .toggleWindow)` ハンドラを登録（既存 triggerRecording と同パターン）
    - SettingsView に `settingRow("ウインドウトグル") { KeyboardShortcuts.Recorder(for: .toggleWindow) }` を追加（既存ショートカット行の下）
  - 備考:
    - デフォルトキー未割当（KeyboardShortcuts フレームワークの仕様通り、ユーザーが SettingsView で対話的に設定）
    - 右Option キー監視（既存 setupRightOptionMonitor）は triggerRecording 専用で、toggleWindow とは独立。相互干渉なし
    - ウインドウ非表示中もショートカット監視は継続（global 登録）。実機検証必須項目
