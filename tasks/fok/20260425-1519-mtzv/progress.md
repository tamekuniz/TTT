# progress: Whisper / Bonsai 自動ダウンロード停止

## T1: WhisperManager / BonsaiManager に `isLocalModelAvailable` ガードを追加し、自動ロードをローカル存在時のみ実行する

状態: 完了

### 実装サマリ
- `Sources/TypeToTalk/Managers/WhisperManager.swift`
  - L84-99: `private func isLocalModelAvailable(variant:)` 追加。`~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/<variant>/` の存在 + 非空判定
  - L69: `ensureSelectedModelLoaded()` の `canAutoLoad` ガード直後に `guard isLocalModelAvailable(...)` を追加。未存在ならサイレント return
- `Sources/TypeToTalk/Managers/BonsaiManager.swift`
  - L25: `private let modelsBaseDirectory: URL` プロパティ追加（init で `downloader` と同一パスを保持）
  - L121-134: `private func isLocalModelAvailable(modelID:)` 追加
  - L111: `ensureSelectedModelLoaded(modelID:)` の `canAutoLoad` ガード直後に同様のガード追加
- `loadSelectedModel()` 系（明示「再読込」ボタン経由）は無変更

### 検証
- ビルド成功（`xcodebuild -scheme TypeToTalk -destination 'platform=macOS' -configuration Debug build`）
- `swift test` 実行: **16 tests, 0 failures（全パス）**
  - `AudioRecorderTests`: 3 件
  - `ModelSelectionTests`: 13 件（WhisperManager / BonsaiManager の状態遷移、`needsExplicitLoad`、`statusText` の idle/未読込パスを網羅）
  - 「未 DL 時は `.idle` のままサイレント return」というガードは既存テストの前提と整合 → リグレッションなし
- コード論理セルフチェック PASS
- 実機での動作確認は Step 8 でズンジーに依頼
