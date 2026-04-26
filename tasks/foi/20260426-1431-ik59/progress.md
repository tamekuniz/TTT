# progress: なるべくそのままモード追加

## T1: `promptMode = "asIs"` の追加実装一式

状態: 完了

### 変更ファイル

- `Sources/TypeToTalk/Managers/SettingsManager.swift` — `systemPromptForAsIs(language:provider:)` 新関数 + `japaneseAsIsBonsaiPrompt()` / `japaneseAsIsDetailedPrompt()` / `englishAsIsBonsaiPrompt()` / `englishAsIsDetailedPrompt()` の private 関数4つ追加
- `Sources/TypeToTalk/Views/SettingsView.swift:194-220` — Picker に `Text("そのまま").tag("asIs")` 追加。`promptMode == "asIs"` 用説明文の `else if` 分岐を追加
- `Sources/TypeToTalk/App/TypeToTalkApp.swift:410` — `processText` 内の `if/else` を `switch` に変更し `"asIs"` ケース追加
- `Tests/TypeToTalkTests/ModelSelectionTests.swift` — asIs テスト4件追加（ja Groq / ja Bonsai / en OpenAI / 文体指示混入なし）

### 検証結果

- **Unit Test**: `swift test` 実行 → ModelSelectionTests 17件すべて PASS（既存13件 + 新規4件）
  - 失敗1件: `AudioRecorderTests.testStartRecordingReturnsExpectedURLOrThrowsWhenPermissionDenied` (CoreAudio `kAUStartIO` 環境依存エラー)。`AudioRecorder.RecordingError` に列挙されていない NSError が catch-all に落ちる既存テストの脆弱性。今回の変更（プロンプト関数 / Picker / 呼び出し分岐）と完全に無関係。current_task のスコープ外
- **simplify レビュー**: 3 agent（reuse / quality / efficiency）すべて Critical 0 件。「既存パターンを忠実に踏襲、そのまま merge OK」判定。修正なしで verified に進行

### Acceptance criteria 達成状況

- [x] AC1: 設定画面のプロンプトモード Picker で「そのまま」が選択肢として表示される（SettingsView 実装で確認）
- [ ] AC2: 「えーっと、明日は雨が降る、あっ、晴れだった」入力 → 「明日は晴れる。」相当の出力（**実機検証で確認予定**）
- [ ] AC3: ja / en 両言語で動作確認（**実機検証で確認予定**）

### 次のアクション

実機ビルドと動作確認をズンジーに依頼。ultrareview は新機能追加（プロンプトモード追加）に該当するため依頼対象とする。
