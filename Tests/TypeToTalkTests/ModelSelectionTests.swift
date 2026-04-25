import XCTest
@testable import TypeToTalk

@MainActor
final class ModelSelectionTests: XCTestCase {
    func testWhisperManagerRecommendedModelMatchesResolvedSelection() {
        let settings = SettingsManager()
        settings.whisperModelPreset = .recommended

        let manager = WhisperManager(settings: settings)

        XCTAssertEqual(manager.selectedModelID, manager.selectedModelDisplayName)
        XCTAssertTrue(manager.canAutoLoad)
    }

    func testWhisperManagerUsesSelectedCustomModel() {
        let settings = SettingsManager()
        settings.whisperModelPreset = .custom
        settings.whisperCustomModelID = " acme/whisper-ja "

        let manager = WhisperManager(settings: settings)

        XCTAssertEqual(manager.selectedModelID, "acme/whisper-ja")
        XCTAssertTrue(manager.canAutoLoad)
        XCTAssertTrue(manager.needsExplicitLoad)
    }

    func testBonsaiManagerTracksSelectionChangeAsNotLoaded() {
        let manager = BonsaiManager()

        manager.configureSelectedModel("prism-ml/Ternary-Bonsai-8B-mlx-2bit")
        XCTAssertTrue(manager.canAutoLoad)
        XCTAssertTrue(manager.needsExplicitLoad)
        XCTAssertEqual(manager.statusMessage, "未読込")
    }

    /// `needsExplicitLoad` の真理値表検証（リファクタ後 `loadedModelID != currentSelectedModelID` の意味的等価性）。
    ///
    /// `loadedModelID` は `private(set)` かつ実モデルを読み込まないと non-nil にできないため、
    /// 実 DL を伴わない範囲で検証可能なのは loadedModelID = nil の系統のみ。
    /// loaded 状態（ケース2/3）は実モデルダウンロードが必要なため Unit Test では検証せず、
    /// 動作確認は `loadStatusBlock` 経由の手動検証に委ねる。
    func testBonsaiManagerNeedsExplicitLoadTruthTable() {
        // ケース1: loadedModelID = nil, currentSelectedModelID = "" → true
        let managerEmpty = BonsaiManager()
        managerEmpty.configureSelectedModel("")
        XCTAssertNil(managerEmpty.loadedModelID)
        XCTAssertEqual(managerEmpty.currentSelectedModelID, "")
        XCTAssertTrue(managerEmpty.needsExplicitLoad)

        // ケース1': loadedModelID = nil, currentSelectedModelID = "M" → true
        let managerSelected = BonsaiManager()
        managerSelected.configureSelectedModel("prism-ml/Ternary-Bonsai-8B-mlx-2bit")
        XCTAssertNil(managerSelected.loadedModelID)
        XCTAssertEqual(managerSelected.currentSelectedModelID, "prism-ml/Ternary-Bonsai-8B-mlx-2bit")
        XCTAssertTrue(managerSelected.needsExplicitLoad)
    }

    /// `WhisperManager.statusText` の idle 系の挙動回帰防止。
    ///
    /// メイン画面・設定画面が両方とも `whisper.statusText` 単一参照に揃っている前提で、
    /// idle 状態（whisperKit 未生成）では "未読込" を返すこと。
    /// loading / loaded 系は `loadState` と `loadingStatusText` が `private(set)` のため
    /// 実モデル DL 抜きにユニットテストでは検証不能。実機検証で担保する。
    func testWhisperStatusTextIsIdleNotLoadedBeforeExplicitLoad() {
        let settings = SettingsManager()
        settings.whisperModelPreset = .recommended

        let manager = WhisperManager(settings: settings)

        // 初期 loadState は .idle、whisperKit は nil なので needsExplicitLoad == true。
        // statusText は "未読込" を返すはず（設定画面・メイン画面で同一表示になる）。
        XCTAssertNil(manager.whisperKit)
        XCTAssertTrue(manager.needsExplicitLoad)
        XCTAssertEqual(manager.statusText, "未読込")
    }

    /// カスタムモデル選択時も idle 系の statusText が "未読込" を返すこと。
    func testWhisperStatusTextIsIdleForCustomModelBeforeExplicitLoad() {
        let settings = SettingsManager()
        settings.whisperModelPreset = .custom
        settings.whisperCustomModelID = "acme/whisper-ja"

        let manager = WhisperManager(settings: settings)

        XCTAssertNil(manager.whisperKit)
        XCTAssertTrue(manager.needsExplicitLoad)
        XCTAssertEqual(manager.statusText, "未読込")
    }

    func testSettingsManagerResolvesDefaultBonsaiModelForEmptyCustomValue() {
        let settings = SettingsManager()
        settings.bonsaiModelPreset = .custom
        settings.bonsaiCustomModelID = "   "

        XCTAssertEqual(settings.resolvedBonsaiModelID, "prism-ml/Ternary-Bonsai-8B-mlx-2bit")
        XCTAssertEqual(settings.bonsaiDisplayName, "prism-ml/Ternary-Bonsai-8B-mlx-2bit")
    }

    /// `whisperLanguage` の UserDefaults round-trip。
    /// 既存ユーザー互換のため、既定値は "ja"。
    func testSettingsManagerWhisperLanguageRoundTrip() {
        let key = "whisperLanguage"
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let fresh = SettingsManager()
        XCTAssertEqual(fresh.whisperLanguage, "ja")

        fresh.whisperLanguage = "en"
        XCTAssertEqual(fresh.whisperLanguage, "en")

        // 別インスタンスで永続化を確認
        let reload = SettingsManager()
        XCTAssertEqual(reload.whisperLanguage, "en")
    }

    /// 言語・文体のデフォルト値とプロンプトモードの初期値検証。
    /// `promptMode = "custom"` は既存ユーザーの systemPrompt を温存するための仕様。
    func testSettingsManagerLanguageAndStyleDefaults() {
        for key in ["whisperLanguage", "formatterLanguage", "textStyle", "promptMode"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        defer {
            for key in ["whisperLanguage", "formatterLanguage", "textStyle", "promptMode"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        let settings = SettingsManager()
        XCTAssertEqual(settings.whisperLanguage, "ja")
        XCTAssertEqual(settings.formatterLanguage, "ja")
        XCTAssertEqual(settings.textStyle, "auto")
        XCTAssertEqual(settings.promptMode, "custom")
    }

    /// 日本語 × ですます調 × Groq（詳細版）プロンプトに必要キーワードが含まれているか検証。
    func testSettingsManagerSystemPromptForJapaneseDesuMasu() {
        let settings = SettingsManager()

        let prompt = settings.systemPromptForLanguageAndStyle(
            language: "ja",
            style: "desuMasu",
            provider: .groq
        )

        XCTAssertTrue(prompt.contains("ですます調"), "文体指示が含まれていない")
        XCTAssertTrue(prompt.contains("整形"), "整形ルール記述が含まれていない")
        XCTAssertTrue(prompt.contains("フィラー"), "フィラー除去ルールが含まれていない")
        XCTAssertTrue(prompt.contains("入力:"), "few-shot 例の入力ラベルが含まれていない")
        XCTAssertTrue(prompt.contains("出力:"), "few-shot 例の出力ラベルが含まれていない")
    }

    /// だ・である調を選んだとき、ですます調ではなくだ・である調が指示される。
    func testSettingsManagerSystemPromptForJapaneseDaDearu() {
        let settings = SettingsManager()

        let prompt = settings.systemPromptForLanguageAndStyle(
            language: "ja",
            style: "daDearu",
            provider: .groq
        )

        XCTAssertTrue(prompt.contains("だ・である調"), "だ・である調の文体指示が含まれていない")
        XCTAssertFalse(prompt.contains("ですます調で統一"), "競合する文体指示が混在している")
    }

    /// Bonsai 用プロンプトは軽量版で、Groq / OpenAI の詳細版より短いはず（few-shot 例なし）。
    func testSettingsManagerSystemPromptForBonsaiIsShorter() {
        let settings = SettingsManager()

        let bonsaiPrompt = settings.systemPromptForLanguageAndStyle(
            language: "ja",
            style: "auto",
            provider: .bonsai
        )
        let groqPrompt = settings.systemPromptForLanguageAndStyle(
            language: "ja",
            style: "auto",
            provider: .groq
        )

        XCTAssertLessThan(
            bonsaiPrompt.count,
            groqPrompt.count,
            "Bonsai 軽量版が Groq 詳細版より短くなっていない（context window 配慮を満たさない）"
        )
        // Bonsai 軽量版には few-shot 例ブロックが無いこと
        XCTAssertFalse(bonsaiPrompt.contains("入力:"), "Bonsai 軽量版に few-shot 例が混入している")
    }

    /// 英語プロンプトには英語のキーワードが含まれ、日本語キーワードは含まれない。
    func testSettingsManagerSystemPromptForEnglish() {
        let settings = SettingsManager()

        let prompt = settings.systemPromptForLanguageAndStyle(
            language: "en",
            style: "auto",
            provider: .openAI
        )

        XCTAssertTrue(prompt.lowercased().contains("editor") || prompt.lowercased().contains("refine"),
                      "英語プロンプトに役割定義が含まれていない")
        XCTAssertTrue(prompt.contains("Whisper"), "Whisper 由来であることが明記されていない")
        XCTAssertFalse(prompt.contains("ですます"), "英語プロンプトに日本語の文体指示が混入している")
    }
}
