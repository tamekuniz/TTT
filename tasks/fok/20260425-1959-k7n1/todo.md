# TODO: Whisper hallucination 3層防御

**サイクル ID**: 20260425-1959-k7n1
**作成日**: 2026-04-25
**プランナー**: メロン（フォK Step 4）
**入力**: `investigation.md`（同ディレクトリ）

---

## 方針サマリー

Whisper の hallucination（無音時に「ご視聴ありがとうございました」等が出力される問題）を、以下 3 層で同時防御する。**3 層は密接に絡むため、1 サイクル内で一気に実装する**（別サイクルにすると効果検証が分かりにくくなる）。

| 層 | 内容 | 実装場所 |
|----|------|----------|
| (1) VAD | WhisperKit 内蔵 EnergyVAD を有効化 | `WhisperManager.setupWhisper()` 内の `WhisperKitConfig` |
| (2) 後処理フィルタ | 既知 hallucination 文字列の完全一致リストで除去 | `WhisperManager.transcribe()` の return 直前 |
| (3) パラメータ | `DecodingOptions(noSpeechThreshold: 0.4)` ※Stage 1 のみ | `WhisperManager.transcribe()` 内の `DecodingOptions` 構築箇所 |

**Stage 2/3 (compressionRatioThreshold / logProbThreshold) は本サイクルでは見送る。** 実機検証で Stage 1 だけでは hallucination が抑えきれないと判明したら次サイクルで段階導入する。

---

## タスク一覧

### Task 1: WhisperManager に 3 層防御を実装

**対象ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/WhisperManager.swift`

**変更内容**:

#### 1-A. hallucination 文字列リストを static let で定義

クラス内 (例: プロパティ宣言エリア付近) に以下を追加。多言語対応の余地を残すため日本語/英語をそれぞれセクション分けしてコメント付き。

```swift
/// Whisper が無音区間で生成しがちな hallucination 文字列のホワイトリスト。
/// 完全一致（前後 whitespace は trim 済みで比較）で除去する。
/// 多言語対応する際は言語別に辞書化する余地あり。
private static let hallucinationPatterns: Set<String> = [
    // Japanese (YouTube/動画字幕由来の典型句)
    "ご視聴ありがとうございました",
    "ご視聴ありがとうございました。",
    "ご視聴ありがとうございます",
    "ご視聴ありがとうございます。",
    "ありがとうございました",
    "ありがとうございました。",
    "お疲れ様でした",
    "お疲れ様でした。",
    "字幕作成: ",
    "字幕制作: ",

    // English
    "Thank you for watching",
    "Thank you for watching.",
    "Thanks for watching",
    "Thanks for watching.",
    "Subtitles by",
    "[BLANK_AUDIO]",
    "(silence)",
    "[silence]",
]
```

※ 厳密な文字列は実機で出現したものを優先採用。投入時点では上記 18 件で初版とする（10〜20 件の指示通り）。

#### 1-B. フィルタ関数を追加

```swift
/// hallucination 文字列の完全一致を除去する。
/// 前後 whitespace は除いてから比較。マッチしたら空文字を返す。
private func filterHallucinations(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if Self.hallucinationPatterns.contains(trimmed) {
        return ""
    }
    return text
}
```

#### 1-C. setupWhisper() で EnergyVAD を WhisperKitConfig に設定（層 1）

現状の `WhisperKit(...)` または `WhisperKitConfig` 初期化箇所を特定し、`voiceActivityDetector` 引数に `EnergyVAD` を渡す。

```swift
let config = WhisperKitConfig(
    model: selectedModelID,
    modelFolder: modelPath.path,
    // ... 既存設定 ...
    voiceActivityDetector: EnergyVAD(
        sampleRate: WhisperKit.sampleRate,  // 16000
        frameLength: 0.1,                   // 100ms
        frameOverlap: 0.0,                  // デフォルトのまま
        energyThreshold: 0.02               // デフォルト維持。低音量問題が出たら 0.01 に下げる
    )
)
```

**注意**:
- 既存の WhisperKitConfig 引数は壊さない。**追加のみ**。
- `import WhisperKit` で `EnergyVAD` が公開 API として import 可能か実装時に確認する。
  - 不可なら `import` を補う or `WhisperKit.EnergyVAD` で参照。
- `WhisperKit.sampleRate` シンボルが見つからない場合は `16000` リテラル直書きでも可（要コメント）。

#### 1-D. transcribe() の DecodingOptions に noSpeechThreshold: 0.4 を追加（層 3 Stage 1）

現状:
```swift
let decodeOptions: DecodingOptions
if language == "auto" {
    decodeOptions = DecodingOptions(detectLanguage: true)
} else {
    decodeOptions = DecodingOptions(language: language)
}
```

変更後:
```swift
let decodeOptions: DecodingOptions
if language == "auto" {
    decodeOptions = DecodingOptions(
        detectLanguage: true,
        noSpeechThreshold: 0.4  // hallucination 対策 (Stage 1)
    )
} else {
    decodeOptions = DecodingOptions(
        language: language,
        noSpeechThreshold: 0.4  // hallucination 対策 (Stage 1)
    )
}
```

※ `DecodingOptions` のイニシャライザ引数順は WhisperKit 0.18.0 のシグネチャに合わせる。コンパイルエラー時は named argument を明示する形で並び替え。

#### 1-E. transcribe() の return 直前でフィルタ適用（層 2）

現状:
```swift
let combinedText = results.compactMap { $0.text }.joined(separator: " ")
lastTranscription = combinedText
return combinedText
```

変更後:
```swift
let combinedText = results.compactMap { $0.text }.joined(separator: " ")
let filtered = filterHallucinations(combinedText)
lastTranscription = filtered
return filtered
```

**完了条件**:
- [ ] `swift build` が通る（WhisperKit API 整合性 OK）
- [ ] 1-A〜1-E がすべて WhisperManager.swift に反映されている
- [ ] EnergyVAD の import / シンボル参照が解決している
- [ ] `DecodingOptions(noSpeechThreshold: 0.4, ...)` の引数順序が API と一致

---

### Task 2: 実機での 3 シナリオ自己検証

ビルド成功後、以下シナリオを手動実行して挙動確認。

#### シナリオ A: 完全無音録音（5 秒）
- 期待: hallucination 出ない（VAD でセグメント生成されない or フィルタで除去）
- 確認: 出力欄が空 or 無変化

#### シナリオ B: 通常発話（日本語、5〜10 秒）
- 期待: 正常に文字起こしされる
- 確認: 出力テキストが意味のある内容

#### シナリオ C: 「ご視聴ありがとうございました」をユーザーが実際に発話
- 期待: ユーザーの発話なので **本来は通したい**。だが完全一致フィルタで除去される（既知の妥協）。
- 確認: ログで「filtered out」が記録されることを目視確認 → 次サイクルでの改善余地としてメモ

**完了条件**:
- [ ] シナリオ A で hallucination が出ないことを確認
- [ ] シナリオ B で日本語認識精度が劣化していないことを確認
- [ ] シナリオ C の挙動を観察し、必要なら progress.md にメモ

---

## スコープ外（次サイクル候補）

- DecodingOptions Stage 2: `compressionRatioThreshold: 2.0`
- DecodingOptions Stage 3: `logProbThreshold: -0.8`
- 多言語ホワイトリストの言語別辞書化
- ユーザーがフィルタリストを編集できる UI
- フィルタヒット時のログ出力 / メトリクス記録
- AudioRecorder 側のリアルタイム VAD（録音段階での無音スキップ）

---

## リスク / 留意点

- **WhisperKit 0.18.0 の API シグネチャ確認**: `EnergyVAD` イニシャライザ引数名（`sampleRate` / `frameLength` / `frameOverlap` / `energyThreshold`）と `DecodingOptions(noSpeechThreshold:)` の利用可否は実装時に `.build/checkouts/WhisperKit/Sources/WhisperKit/Core/Audio/EnergyVAD.swift` および `Configurations.swift` で必ず再確認する。
- **EnergyVAD のシンボル可視性**: WhisperKit が `public` で公開しているか、internal なら別アプローチ要検討。
- **シナリオ C の妥協**: ユーザーが定型句を実際に話した場合も削除される。投入後にユーザー報告があれば Levenshtein 距離フィルタや前後文脈チェックで対応可能（次サイクル）。
- **noSpeechThreshold 0.4 の副作用**: 低音量発話が「無音」判定される可能性。シナリオ B の精度劣化を厳しめに見る。
