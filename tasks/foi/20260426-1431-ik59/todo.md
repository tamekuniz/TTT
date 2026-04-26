# todo: なるべくそのままモード追加

- [ ] T1: `promptMode = "asIs"` の追加実装一式
    - 対象ファイル:
        - `Sources/TypeToTalk/Managers/SettingsManager.swift` — 新関数 `systemPromptForAsIs(language:provider:)` を追加。ja/en × Bonsai軽量/詳細 の4プロンプト関数も追加（`japaneseAsIsBonsaiPrompt()` / `japaneseAsIsDetailedPrompt()` / `englishAsIsBonsaiPrompt()` / `englishAsIsDetailedPrompt()`）。文体パラメータは受け取らない
        - `Sources/TypeToTalk/Views/SettingsView.swift:194-220` — Picker に `Text("そのまま").tag("asIs")` 追加。custom 以外（preset と asIs）を分けて説明文を出すように分岐拡張
        - `Sources/TypeToTalk/App/TypeToTalkApp.swift:412` — `if promptMode == "preset"` の分岐を `"preset"` / `"asIs"` / それ以外（custom）の3分岐に拡張。asIs 時は新関数 `systemPromptForAsIs(language:provider:)` を呼ぶ
        - `Tests/TypeToTalkTests/ModelSelectionTests.swift` — 新規テスト4件追加（investigation.md §7 の Unit Test 4件）
    - 期待挙動:
        - 設定画面のプロンプトモード Picker で「そのまま」が3つ目の選択肢として segmented で表示
        - asIs 選択時は WhisperKit 出力に対してフィラー削除と明示的な自己訂正・誤字修正のみが走り、文体・語順・言い回しは触られない
        - asIs 選択時は文体（`textStyle`）が無視される（プロンプトに文体指示文を含めない）
        - 既存の preset / custom 挙動は無変更
    - 備考:
        - `promptMode` は raw String 流儀（enum 化しない、investigation §6 Constraints）
        - LLM が「整える」癖を出す対策として、プロンプトで「やってはいけないこと」を強く列挙し、ja/en の詳細版は few-shot 2 例、Bonsai 版は few-shot 1 例で実演
        - 自己訂正は明示的キーワード（「あ、違う」「いや」「やっぱり」/ "no wait", "I mean", "actually"）に絞る
        - Bonsai 版は Groq/OpenAI 詳細版より短くする（既存 `testSettingsManagerSystemPromptForBonsaiIsShorter` と同じ context window 配慮）
