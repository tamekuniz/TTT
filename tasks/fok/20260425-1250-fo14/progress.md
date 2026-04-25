# 進捗記録

## T1: BonsaiManager のモデルパス修正と needsExplicitLoad リファクタ

状態: 完了

- BonsaiManager.swift L28: `.ttt/models` → `.typetotalk/models`
- BonsaiManager.swift L64-66: `needsExplicitLoad` を `loadedModelID != currentSelectedModelID` に整理
- ModelSelectionTests.swift: `testBonsaiManagerNeedsExplicitLoadTruthTable` 追加
- 検証: `swift build` ✅ / `swift test` 全7件 PASS / `.ttt` 残存なし
- 実機検証は T3 完了後に T1〜T3 まとめて実施

---

## T2: AudioRecorder の戻り値 URL を Coordinator が保持して活用

状態: 完了

- TypeToTalkApp.swift L194: `@Published private(set) var recordingURL: URL?` 追加
- 同 L289: `recordingURL = try await recorder.startRecording()` で URL 捕捉
- 同 L235-239: ハードコード除去 → `guard let audioURL = recordingURL else { ... return }` に置換
- AudioRecorderTests.swift: `testStartRecordingReturnsExpectedURLOrThrowsWhenPermissionDenied` 追加
- 検証: `swift build` ✅ / `swift test` 全8件 PASS / Coordinator 側 `recording.wav` ハードコード除去確認
- 実機検証は T3 完了後に T1〜T3 まとめて実施

---

## T3: ウインドウ表示トグル用ショートカット新規追加

状態: 完了（実機検証待ち）

- TypeToTalkApp.swift: `KeyboardShortcuts.Name.toggleWindow` 追加（デフォルトキー未割当）
- 同: init で `onKeyDown(for: .toggleWindow)` 登録（onKeyUp 無し、トグルなので押下のみ）
- 同: `handleToggleWindow()` メソッド追加（録音状態には触らない、`isVisible` で判定して `orderOut`/`makeKeyAndOrderFront`、未生成時は `showRecorderWindow()` フォールバック）
- SettingsView.swift: 既存ショートカット行直下に `settingRow("ウインドウ表示トグル") { KeyboardShortcuts.Recorder(for: .toggleWindow) }` 追加
- 検証: `swift build` ✅ / `swift test` 全8件 PASS
- 実機検証ポイント（ズンジー依頼）:
  1. アプリ起動 → 設定画面に「ウインドウ表示トグル」のショートカット設定欄が出ること
  2. 任意のキーを割当 → 押すとウインドウ非表示、もう一度押すと再表示
  3. 録音中にウインドウを閉じても録音が継続すること（タップしてmicボタンに戻れること）
  4. T1 の Bonsai パスで `~/.typetotalk/models/` にモデルが配置されること（オフライン整形時）
  5. T2 の録音URL捕捉でエンドツーエンド（録音 → 文字起こし → 入力欄注入）が動くこと
