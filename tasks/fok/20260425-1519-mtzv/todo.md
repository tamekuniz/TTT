# todo: Whisper / Bonsai 自動ダウンロード停止

## タスク

- [ ] T1: WhisperManager / BonsaiManager に `isLocalModelAvailable` ガードを追加し、自動ロードをローカル存在時のみ実行する
    - 対象ファイル:
      - `Sources/TypeToTalk/Managers/WhisperManager.swift`
      - `Sources/TypeToTalk/Managers/BonsaiManager.swift`
    - 実装内容:
      1. WhisperManager に `private func isLocalModelAvailable(variant: String) -> Bool` を追加。`~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/<variant>/` の存在を `FileManager.fileExists(atPath:)` で判定。
      2. BonsaiManager に `private func isLocalModelAvailable(modelID: String) -> Bool` を追加。`~/.typetotalk/models/<modelID>/` の存在を判定（`baseDirectory` プロパティ／init で渡されるパスを再利用すること）。
      3. `WhisperManager.ensureSelectedModelLoaded()`: 既存の `canAutoLoad` チェック直後に `guard isLocalModelAvailable(variant: <selectedVariant>) else { return }` を追加。エラーも `loadState` 変更もせずサイレントに return。
      4. `BonsaiManager.ensureSelectedModelLoaded(modelID:)`: 同様に `guard isLocalModelAvailable(modelID: modelID) else { return }` を追加。
      5. `loadSelectedModel()` 系（明示操作）には一切手を入れない。「再読込」ボタン経由のダウンロードは従来通り動作させる。
    - 期待挙動:
      - ダウンロード済み → 従来通り自動ロード（Happy Path 維持）
      - 未ダウンロード → サイレントに return、ネット通信ゼロ、`loadState` は `.idle` のまま
      - 「再読込」ボタン → 従来通りダウンロード/ロード実行
    - 不確かな点（実装時に確定すること）:
      - **WhisperKit のローカルキャッシュパスの正確な構造**: investigation §補足A では `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/<variant>/` としているが、実際は `<variant>/` 直下なのか `coreml_models/<variant>/` 配下なのか不確か。実装小人ちゃんは `.build/checkouts/WhisperKit/Sources/WhisperKit/` のソース（特に `WhisperKit.download()` と `ModelDownloader`）を読んで確定すること。確定できない場合は既存ユーザー環境の実ファイル配置（`~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/` 配下）を `ls` で確認。
      - BonsaiManager の `baseDirectory` は init 時に注入されているので、ハードコードでなくその値を再利用すること（命名規約の一貫性のため）。
    - 備考:
      - 両 Manager の変更は同種の小さなパターンであり、片方だけ動いても要件を満たさないため必ず一緒に実施する。
      - `@MainActor` を維持。新規 helper は `private` で十分。

## スコープ外（やらないこと）

- UI テキストの細分化（「未読込（未ダウンロード）」「オフライン中」等への変更）。要件は「自動 DL しない」のみで、UI 改修は別件。
- `WhisperLoadState` / `BonsaiLoadState` enum への新ケース追加（`.notDownloaded` 等）。状態は `.idle` のまま維持する。
- `NetworkMonitor` 等のリアクタビリティ追加。オフライン検出はしない。
- ダウンロード進捗 UI の刷新。
- ダウンロード済みモデルのバージョン整合チェック。
- `loadSelectedModel()` 系（明示ロード）の変更。
- 動作確認は Step 8（自己検証）でカバーするため独立タスクにしない。
