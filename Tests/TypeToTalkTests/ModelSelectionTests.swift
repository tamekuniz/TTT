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

    func testSettingsManagerResolvesDefaultBonsaiModelForEmptyCustomValue() {
        let settings = SettingsManager()
        settings.bonsaiModelPreset = .custom
        settings.bonsaiCustomModelID = "   "

        XCTAssertEqual(settings.resolvedBonsaiModelID, "prism-ml/Ternary-Bonsai-8B-mlx-2bit")
        XCTAssertEqual(settings.bonsaiDisplayName, "prism-ml/Ternary-Bonsai-8B-mlx-2bit")
    }
}
