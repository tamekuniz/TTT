# フォK Step 4 進捗記録

タスク連番は `todo.md` と揃える。各タスク完了時に状態を「完了」に更新し、サイクル番号・主要変更ファイル・検証手段（test/build/実機）を簡潔に追記する。

## T1: メイン画面 UI 軽微整理（タイトル位置／待機中／Trigger 削除）

状態: 完了

- 要件②: ヘッダー HStack に `.padding(.leading, 56)` 追加（仮置き、実機で目視調整）
- 要件③: `statusMessage` 初期値を空文字列に変更、`if !isEmpty` で空時は Text 非表示
- 要件④: `infoStatusRow("Trigger", ...)` 行削除＋ヘルパー関数 `infoStatusRow` 自体も削除（dead code）。`lastTriggerSource` プロパティと `recordTriggerFeedback` 内更新は内部温存
- 検証: `swift build` ✅ / `swift test` 全10件 PASS
- 残課題: padding 56pt は仮値、実機目視で 64〜72pt 等に調整可能
- 実機検証は他タスク完了後にまとめて実施

## T2: Whisper/Formatter 状態同期バグ修正

状態: 完了

- 根因: `modelStatusRow` の `progressLabel` 引数が dead branch（loading 中は status==loadingStatusText で必ず一致して表示されない、loading 以外は nil）
- 修正: TypeToTalkApp.swift の `modelStatusRow` から `progressLabel` 引数を削除、Whisper/Formatter 両呼び出し側も削除、View 内の if let progressLabel ブロック削除
- WhisperManager.statusText / BonsaiManager.statusMessage / SettingsView は既存ロジックが正しい単一 source 構造のため修正不要
- ModelSelectionTests に 2 件追加（idle 時 statusText 検証 × recommended/custom）
- 検証: `swift build` ✅ / `swift test` 全10件 PASS / progressLabel 残存なし
- 残課題: `isFormatterLoading` (TypeToTalkApp.swift L391) が dead code 化したが T2 スコープ外として温存。将来整理候補
- 実機検証は他タスク完了後にまとめて実施

## T3: アクセシビリティ権限の説明強化＋システム設定誘導

状態: 完了

- AccessibilityManager.openAccessibilitySettings() は既存実装あり、再利用
- TypeToTalkApp.swift: `@Published showAccessibilityPermissionAlert` 追加、`.missingPermission` 時にメッセージ具体化＋alert 表示。alert ボタンから openAccessibilitySettings() 呼び出し
- SettingsView.swift: アクセシビリティ権限 GroupBox の説明文を具体化（用途・効果を明記）
- 検証: `swift build` ✅ / `swift test` 全10件 PASS（AudioRecorderTests は app プロセス起動中のマイクロック影響で時間かかった）
- 実機検証は他タスク完了後にまとめて実施

## T4: 言語設定＋整形プロンプト構造化（要件⑥⑦統合）

状態: 完了

- SettingsManager: `whisperLanguage`(ja/en/auto) / `formatterLanguage`(ja/en) / `textStyle`(desuMasu/daDearu/auto) / `promptMode`(preset/custom) 追加
- SettingsManager: `systemPromptForLanguageAndStyle(language:style:provider:)` 新設。日英×Bonsai軽量/Groq詳細の4テンプレート（5層構造、few-shot 込み）
- WhisperManager: `transcribe(audioURL:language:)` シグネチャ拡張、`DecodingOptions(language:)` で WhisperKit 0.18.0 API に伝播。"auto" は detectLanguage=true
- Coordinator: `processText` で promptMode 分岐。preset時は組立済プロンプト、custom時は既存 systemPrompt
- SettingsView: 4つの segmented Picker（聞き取り言語/整形言語/文体/プロンプトモード）追加。custom時のみTextEditor表示
- 既存ユーザ互換: promptMode 初期値 "custom" で既存 systemPrompt 温存
- 検証: `swift build` ✅ / `swift test` 全16件 PASS（新規7件追加）
- 実機検証ポイント:
  1. 設定画面に4つの新Pickerが表示されること
  2. 言語切り替え（日→英）でWhisper出力が変わること
  3. promptMode = preset で文体（ですます/だ・である）が反映されること
  4. promptMode = custom で既存編集内容が保持されること
