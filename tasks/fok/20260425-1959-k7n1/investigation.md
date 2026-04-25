# Whisper Hallucination 対策の調査レポート

**調査日**: 2026-04-25
**調査者**: ゆず（フォK Step 3 調査小人）
**プロジェクト**: TypeToTalk (macOS SwiftUI アプリ)

---

## 1. 関連ファイル一覧（パス + 役割）

### 主要な実装ファイル

| パス | 役割 |
|------|------|
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/AudioRecorder.swift` | AVAudioEngine を使った録音管理。バッファサイズ 1024、format は outputFormat(forBus: 0)。VAD なし。 |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/WhisperManager.swift` | WhisperKit モデルローディング＋ transcribe メソッド呼び出し。DecodingOptions のカスタマイズなし（デフォルト使用）。 |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift` | Coordinator 経由でWhisper→成形AIへのフロー制御（253行目から277行目）。後処理フィルタなし。 |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/OpenAICompatibleManager.swift` | 整形AI への POST リクエスト。前処理なし。 |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Package.swift` | WhisperKit 0.18.0 を依存。 |

### WhisperKit ソース（.build/checkouts 配下）

| パス | 役割 |
|------|------|
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/.build/checkouts/WhisperKit/Sources/WhisperKit/Core/Audio/VoiceActivityDetector.swift` | VoiceActivityDetector 基底クラス（行7-163）。voiceActivity(in:) メソッドで [Bool] 配列を返す。calculateActiveChunks(), calculateSeekTimestamps() で VOI セグメント計算。 |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/.build/checkouts/WhisperKit/Sources/WhisperKit/Core/Audio/EnergyVAD.swift` | EnergyVAD 実装（行7-57）。energyThreshold = 0.02 デフォルト。frameLength = 0.1秒、frameOverlap = 0.0秒 デフォルト。AudioProcessor.calculateVoiceActivityInChunks() で RMS ベース VAD 実行。 |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/.build/checkouts/WhisperKit/Sources/WhisperKit/Core/Configurations.swift` | DecodingOptions 定義（行156-251）。デフォルト値:<br/>- noSpeechThreshold: 0.6<br/>- compressionRatioThreshold: 2.4<br/>- logProbThreshold: -1.0<br/>- firstTokenLogProbThreshold: -1.5<br/>- suppressBlank: false<br/>- clipTimestamps: [] |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/.build/checkouts/WhisperKit/Sources/WhisperKit/Core/WhisperKit.swift` | transcribe() メソッド（行599-611 等）。decodeOptions を引数に受け取り、WhisperKit 内部で処理。 |

### テストファイル

| パス | 役割 |
|------|------|
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Tests/TypeToTalkTests/AudioRecorderTests.swift` | AudioRecorder のバッファ書き込み動作テスト。権限チェック。VAD テストなし。 |

---

## 2. 既存実装パターン

### 2.1 AudioRecorder のバッファ管理

**ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/AudioRecorder.swift`

```swift
// 行47-85: startRecording() メソッド
let inputNode = engine.inputNode
let recordingFormat = inputNode.outputFormat(forBus: 0)

inputNode.installTap(
    onBus: 0,
    bufferSize: 1024,
    format: recordingFormat,
    block: Self.makeTapHandler(writer: writer)
)

// 行112-118: タップハンドラ
nonisolated static func makeTapHandler(
    writer: some AudioBufferWriting
) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
    { buffer, _ in
        writer.write(buffer)
    }
}
```

**パターン**:
- AVAudioEngine の inputNode に tap を install
- bufferSize = 1024 固定（フレーム数）
- AudioFileWriter で AVAudioFile に即座に書き込み
- **VAD なし**。すべてのバッファ（無音含む）がファイルに記録される

### 2.2 WhisperKit 呼び出し

**ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/WhisperManager.swift`

```swift
// 行147-176: transcribe() メソッド
func transcribe(audioURL: URL, language: String = "ja") async -> String {
    guard let whisperKit = whisperKit else {
        return ""
    }

    let decodeOptions: DecodingOptions
    if language == "auto" {
        decodeOptions = DecodingOptions(detectLanguage: true)
    } else {
        decodeOptions = DecodingOptions(language: language)
    }

    let results = try await whisperKit.transcribe(
        audioPath: audioURL.path,
        decodeOptions: decodeOptions
    )
    let combinedText = results.compactMap { $0.text }.joined(separator: " ")
    lastTranscription = combinedText
    return combinedText
}
```

**パターン**:
- language パラメータは ja / en / auto をサポート
- detectLanguage フラグのみで調整（detectLanguage: true なら言語検出、false なら language 明示）
- **DecodingOptions は最小限**。noSpeechThreshold, compressionRatioThreshold, logProbThreshold はすべてデフォルト値
- 結果は compactMap で text のみ抽出＋join

### 2.3 結果ハンドリング

**ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`

```swift
// 行253-280: toggleRecording() 内の流れ
// 1. Whisper による文字起こし (素の状態)
var rawText = await whisper.transcribe(
    audioURL: audioURL,
    language: settings.whisperLanguage
)

guard !rawText.isEmpty else {
    statusMessage = "文字起こし失敗"
    isProcessing = false
    return
}

// 2. AI に渡す前の「事前置換」 (辞書による読み置換)
for entry in settings.dictionary where !entry.reading.isEmpty {
    rawText = rawText.replacingOccurrences(of: entry.reading, with: entry.word)
}

// 3. AI による成形 (コンテキストは最小限)
let processedText = await processText(rawText, with: activeFormatter)

// 4. AI 成形後の「事後置換」
var finalText = processedText
for entry in settings.dictionary where !entry.reading.isEmpty {
    finalText = finalText.replacingOccurrences(of: entry.reading, with: entry.word)
}

// 5. テキスト入力
accessibility.insertText(finalText)
```

**パターン**:
- Whisper 結果→そのまま isEmpty チェック→辞書置換→AI送信
- **後処理フィルタなし**。hallucination 文字列リストによる除外処理は存在しない
- isEmpty チェックだけで進む（「ご視聴ありがとうございました」程度の短文でも通過）

### 2.4 DecodingOptions の現状

**ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/.build/checkouts/WhisperKit/Sources/WhisperKit/Core/Configurations.swift` (行156-251)

WhisperManager は `DecodingOptions(language: "ja")` のみで初期化し、他の細調整パラメータはいずれもデフォルト：

| パラメータ | デフォルト値 | 効果 |
|-----------|----------|------|
| noSpeechThreshold | 0.6 | 無音判定の閾値。0.6 以上の「無音確度」＋logProbThreshold 未満 なら無音と判定 |
| compressionRatioThreshold | 2.4 | テキストの圧縮比＞2.4 なら反復出力（hallucination）と見做して失敗扱い |
| logProbThreshold | -1.0 | 平均対数尤度＜-1.0 なら信頼度低いと判定 |
| firstTokenLogProbThreshold | -1.5 | 最初のトークン対数尤度＜-1.5 なら失敗 |
| suppressBlank | false | [BLANK] トークンを抑制しない |
| temperature | 0.0 | 完全決定論的デコード（サンプリングなし） |
| usePrefillPrompt | true | prefill トークンを使用 |
| withoutTimestamps | false | タイムスタンプを含める |

---

## 3. 影響範囲（呼び出し側 / 依存）

### 3.1 録音フロー への VAD 追加の影響

```
AudioRecorder.startRecording()
  ↓
AVAudioEngine.inputNode.installTap(bufferSize: 1024)
  ↓ [現在] ← すべてのバッファをファイルに書き込み
  ↓ [提案] ← VAD を insert → 無音バッファをスキップ
  ↓
AVAudioFile.write(buffer)
  ↓
AudioRecorder.stopRecording() → recordingURL 返却
  ↓
TypeToTalkCoordinator.toggleRecording() → recordingURL 取得
  ↓
WhisperManager.transcribe(audioURL)
```

**VAD 挿入位置の 3 パターン**:

1. **リアルタイム VAD（AudioRecorder 内）**
   - 利点: 無音ファイルがディスクに書かれない、ストレージ効率良い
   - 欠点: 音声開始/終了の微妙な判定で正常発話を切る可能性、低遅延な VAD 実装が必要
   - 推奨度: 中（バッファ管理の複雑化）

2. **事前処理 VAD（WhisperManager の transcribe 前）**
   - 利点: Whisper 前に無音区間を明示的に除外できる、clipTimestamps で Whisper に指示可能
   - 欠点: ファイルには無音も含まれる（ストレージ無駄）
   - 推奨度: 高（シンプルで影響が限定的）

3. **Whisper 内蔵 VAD**
   - WhisperKit の WhisperKitConfig.voiceActivityDetector に EnergyVAD をセット
   - 利点: Whisper がセグメント化時に自動的に無音をスキップ
   - 欠点: Whisper の transcribe() → transcribeWithResults() 内部で使われる（パス追跡が必要）
   - 推奨度: 高（WhisperKit の標準機能）

### 3.2 後処理フィルタの差し込み位置

```
WhisperManager.transcribe() → rawText
  ↓
[提案] ← hallucination フィルタ（文字列リスト完全一致チェック）
  ↓ → filtered Text
  ↓
TypeToTalkCoordinator.toggleRecording() 行254
  └→ isEmpty チェック → 辞書置換 → AI送信 → 最終出力
```

**差し込み位置**:
- **WhisperManager.transcribe() の return 前** が理想的（責務分離）
- または TypeToTalkCoordinator.toggleRecording() の行256-257 に追加フィルタロジック

### 3.3 DecodingOptions 調整が WhisperKit 処理フローに与える影響

WhisperKit の transcribe() 内部で：
1. AudioProcessor.loadAudio() → [Float] 配列
2. TextDecoder.decodeTokens() → 圧縮比チェック＆logProb チェック
3. 失敗判定時 → temperatureIncrementOnFallback で再トライ（最大 temperatureFallbackCount 回）
4. すべて失敗 → 空結果または低信頼度結果

**影響**:
- noSpeechThreshold 厳格化 (0.6 → 0.4) → 無音判定が敏感化
- compressionRatioThreshold 小型化 (2.4 → 2.0) → 反復出力（hallucination）を容易に弾く
- logProbThreshold 引き上げ (-1.0 → -0.5) → 信頼度低い出力を積極的に失敗扱いする

ただし、失敗時は **再トライ＆temperature 上昇** が発生 → ランダムネス増加 → 日本語精度低下の可能性

---

## 4. 過去の類似実装（git log による確認）

**コマンド**: `git log --oneline -50 | grep -i "whisper\|hallucin\|vad\|silence\|filter"`

**結果**:
```
848ef06 [フォK] fix: Whisperステータスがメインウインドウに伝播しない不整合を修正
aac4a7a [フォK] feat: モデル自動DL停止、ローカル存在時のみ自動ロード
16d3413 [フォK] feat: UI整理＋言語設定＋整形プロンプト構造化
```

**確認事項**:
- **VAD 実装なし**。過去に VAD / silence handling / hallucination filter の試みはない
- **DecodingOptions カスタマイズなし**。デフォルト値のみ使用
- Whisper 言語設定は「コミット 16d3413」で追加（language 引数サポート開始）
- **hallucination 対策の履歴はゼロ**。新規実装となる

---

## 5. 想定される副作用 / リスク

### 5.1 VAD 導入時のリスク

| リスク | 説明 | 対策 |
|------|------|------|
| **正常発話の切り落とし** | 音量小さい発話（囁き・高齢者）が無音判定される可能性 | EnergyVAD の energyThreshold を 0.02 より低める（0.01 等） |
| **音声開始/終了タイミング** | VOI セグメント開始直前の音声が欠落する可能性 | frameOverlap = 0.05秒 程度で前後マージン追加 |
| **背景雑音の誤判定** | 低周波環境ノイズが音声と判定される、あるいは除外される | EnergyVAD ではなく ML ベース VAD（Silero VAD 等）の検討 |

### 5.2 後処理フィルタのリスク

| リスク | 説明 | 対策 |
|------|------|------|
| **正常出力の誤削除** | ユーザー発話が定型句リストに部分一致して削除される | 完全一致のみ or 辺距離＞2 の正規表現利用 |
| **日本語/多言語カバレッジ不足** | 未知の hallucination パターンが新たに出現 | ユーザー報告ベースでリスト拡張する機構が必要 |
| **文化 / ドメイン依存性** | 配信サイト固有の定型句は不明 | 初版は「ご視聴ありがとうございました」等の汎用のみ |

### 5.3 DecodingOptions 調整のリスク

| リスク | 説明 | 対策 |
|------|------|------|
| **日本語精度低下** | compressionRatioThreshold 小型化で正常な反復も削除、logProb 引き上げで失敗率増加 | 実機テストで精度メトリクス測定（品質スコア記録） |
| **トライ増加による遅延** | logProbThreshold / compressionRatioThreshold で再トライ → 処理時間 1.5～2 倍化 | UI に「文字起こし中（リトライ）」等の表示 |
| **temperature 上昇の副作用** | 再トライ時 temperature が段階的に上昇 → ランダムネスで不規則な結果 | temperature 上昇幅を制限 or 再トライの回数上限設定 |

---

## 6. 制約条件

### 6.1 WhisperKit バージョン

- **依存バージョン**: 0.18.0 (Package.swift 行13)
- **DecodingOptions API**: v0.18.0 で安定
- **VoiceActivityDetector API**: v0.18.0 以降で EnergyVAD クラス利用可能

**バージョンアップ時の注意**:
- v0.19.0 以降で DecodingOptions シグネチャ変更の可能性あり（要確認）
- VAD の内蔵実装 / API 変更の追跡が必要

### 6.2 DecodingOptions API（Configurations.swift より）

```swift
public struct DecodingOptions: Codable, Sendable {
    public var noSpeechThreshold: Float?        // デフォルト 0.6
    public var compressionRatioThreshold: Float?  // デフォルト 2.4
    public var logProbThreshold: Float?         // デフォルト -1.0
    public var firstTokenLogProbThreshold: Float? // デフォルト -1.5
    public var suppressBlank: Bool              // デフォルト false
    public var supressTokens: [Int]             // デフォルト []
    public var clipTimestamps: [Float]          // デフォルト []
    public var windowClipTime: Float            // デフォルト 1.0
    public var temperature: Float               // デフォルト 0.0
    // ... その他 20+ パラメータ
}
```

### 6.3 オーディオ API

| API | 用途 | 制約 |
|-----|------|------|
| AVAudioEngine | 録音エンジン | tap をインストール直後は engine.start() 必須 |
| AVAudioPCMBuffer | バッファ表現 | format と frameLength の整合性が必須 |
| AVAudioFile | ファイル書き込み | settings 引数で format を完全指定 |
| VoiceActivityDetector (WhisperKit) | VAD 基底 | subclass 実装 or EnergyVAD の直接利用 |

### 6.4 言語サポート

- **現在**: ja (日本語) / en (英語) / auto (自動検出)
- **hallucination リスト**: 日本語＋英語の典型例を用意する必要

---

## 7. テスト戦略（実機確認シナリオ）

### 7.1 テスト環境

- **対象機**: Apple Silicon Mac (macOS 14+)
- **テスト方法**: 実機録音＋手動確認 or 録音ファイル再現

### 7.2 テストシナリオ

#### シナリオ 1: 完全無音録音（5秒）
- **期待**: rawText が空 or hallucination 定型句
- **実測**:
  - [ ] VAD なし: hallucination 出現（例：「ご視聴ありがとうございました」）
  - [ ] VAD あり: 無音セグメント→empty result
  - [ ] フィルタあり: hallucination → filtered out

#### シナリオ 2: 短時間無音 + 咳払い（0.3秒）
- **期待**: 咳払いは音声と判定 / 無音は除外
- **実測**:
  - [ ] VAD: energyThreshold で咳払い検出判定
  - [ ] Whisper: 短音声→「ん」「あ」程度のテキスト出力
  - [ ] フィルタ: 1文字以下削除 or 信頼度フィルタ

#### シナリオ 3: 正常発話（日本語、5～10秒）
- **期待**: 正確な文字起こし＋AI整形
- **実測**:
  - [ ] VAD なし vs あり: 品質・処理時間の差分
  - [ ] DecodingOptions 変更: 精度＆遅延の測定
  - [ ] AI整形: 辞書置換との相互作用確認

#### シナリオ 4: 低音量発話（囁き）
- **期待**: 正常認識（VAD は通過、Whisper は認識）
- **実測**:
  - [ ] EnergyVAD の energyThreshold: 低音量でも検出可能か
  - [ ] 閾値調整案: 0.02 → 0.01 で改善するか

#### シナリオ 5: 定型句テスト
- **期待**: hallucination 定型句が自動フィルタされる
- **実測**:
  - JP: 「ご視聴ありがとうございました」「お疲れ様でした」
  - EN: 「Thank you for watching」「Subtitles by」
  - 逆テスト: ユーザーが「ご視聴ありがとうございました」と言ったら、正常に認識＆ユーザーに返すべき

#### シナリオ 6: 処理時間測定
- **測定項目**:
  - [ ] 無音→Whisper 転送（VAD があると高速化）
  - [ ] Whisper 実行時間（DecodingOptions で変動）
  - [ ] 再トライ発生時の追加遅延

### 7.3 テスト結果記録方式

```markdown
## Test Session: YYYY-MM-DD HH:MM

### Scenario 1: Complete Silence (5sec)
- VAD Status: [enabled/disabled]
- EnergyThreshold: [0.02/0.01/custom]
- Whisper Result: "ご視聴ありがとうございました"
- Filter Result: [passed/filtered]
- Latency: XXXms

### Scenario 2: Cough (0.3sec)
- EnergyVAD Detection: [yes/no]
- Whisper Output: "ん"
- Filter Rule: [length < 2 chars]
- Status: [PASS/FAIL]

...
```

---

## 8. 仕様提案（実装方針）

### 8.1 VAD 実装方針

#### 推奨案: **WhisperKit 内蔵 VAD（EnergyVAD）の WhisperKitConfig 経由での利用**

**根拠**:
1. WhisperKit v0.18.0 で EnergyVAD が標準実装済み
2. WhisperKit 内部で clipTimestamps として transcribe に自動連携可能
3. AudioRecorder の変更が最小限で済む（WhisperManager のみ調整）

**実装スケッチ**:

```swift
// WhisperManager.swift の setupWhisper() 内で
let config = WhisperKitConfig(
    model: selectedModelID,
    modelFolder: modelPath.path,
    voiceActivityDetector: EnergyVAD(
        sampleRate: WhisperKit.sampleRate,      // 16000
        frameLength: 0.1,                       // 100ms フレーム
        frameOverlap: 0.05,                     // 50ms オーバーラップで境界保護
        energyThreshold: 0.01                   // デフォルト 0.02 → 0.01 に厳格化（低音量対応）
    )
)
let kit = try await WhisperKit(modelConfig: config)
self.whisperKit = kit
```

**メリット**:
- AudioRecorder は無変更
- WhisperManager に EnergyVAD 生成コードのみ追加
- WhisperKit の transcribe() 内部で自動的に VAD が適用

**デメリット**:
- EnergyVAD は RMS ベースで ML ベースではない（背景雑音に弱い可能性）
- energyThreshold の調整が実機テストに依存

#### 代替案 B: 自前 VAD（AudioRecorder 内での RMS ベース検出）

**実装コスト**: 高（バッファ管理の複雑化）
**メリット**: リアルタイムで不要な無音ファイル書き込みを削減
**デメリット**: 音声開始/終了の微妙な判定で正常発話を削除するリスク高

→ 推奨せず（初版は案 A）

---

### 8.2 後処理フィルタ実装方針

#### 推奨案: **完全一致ベースのホワイトリスト方式**

**根拠**:
1. 誤削除のリスク最小化（完全一致のみ）
2. 正規表現より保守性高い（初版）
3. ユーザー報告で段階的に拡張可能

**実装スケッチ**:

```swift
// WhisperManager.swift に以下を追加
private let hallucinnationPatterns = [
    // Japanese
    "ご視聴ありがとうございました",
    "ご視聴ありがとうございます",
    "ありがとうございました",
    "ご来場ありがとうございました",
    "お疲れ様でした",
    "字幕作成：",
    "字幕制作：",
    
    // English
    "Thank you for watching",
    "Thanks for watching",
    "Thanks for watching.",
    "[BLANK_AUDIO]",
    "Subtitles by",
    "(silence)",
    "[silence]",
]

func filterHallucinations(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    if hallucinnationPatterns.contains(trimmed) {
        return ""
    }
    return text
}
```

**使用箇所**:

```swift
// WhisperManager.transcribe() の return 前
let combinedText = results.compactMap { $0.text }.joined(separator: " ")
let filtered = filterHallucinations(combinedText)
lastTranscription = filtered
return filtered
```

**メリット**:
- 実装シンプル（5-10 行）
- 誤削除リスク最小
- ユーザー報告で拡張容易

**デメリット**:
- 未知の hallucination パターンに対応不可
- 多言語版は別途リスト管理必須

#### 代替案 B: 正規表現 + 部分一致フィルタ

```swift
let pattern = ".*ご?視聴|ご来場|お疲れ|字幕.*"
if text.range(of: pattern, options: .regularExpression) != nil {
    return ""
}
```

**デメリット**: 正常発話「ありがとうございました」と「ご視聴ありがとうございました」を区別困難

→ 完全一致推奨（案 A）

---

### 8.3 DecodingOptions パラメータ調整方針

#### 推奨案: **保守的な 3 段階調整**

**基本戦略**:
- Stage 0（初期値）: デフォルト値のまま baseline 測定
- Stage 1（軽量）: 無音判定の厳格化のみ
- Stage 2（本格）: 反復出力（hallucination）検出の厳格化

#### Stage 1: noSpeechThreshold 厳格化（リスク最小）

```swift
let decodeOptions = DecodingOptions(
    language: language,
    noSpeechThreshold: 0.4         // デフォルト 0.6 → 0.4
)
```

**効果**: 無音判定が厳しくなる（無音確度 0.4 以上で無音認定）
**リスク**: 低（logProb チェックもあるため）
**実装**: 1 行変更

#### Stage 2: 反復出力フィルタ（中リスク）

```swift
let decodeOptions = DecodingOptions(
    language: language,
    noSpeechThreshold: 0.4,
    compressionRatioThreshold: 2.0  // デフォルト 2.4 → 2.0（反復検出を敏感化）
)
```

**効果**: hallucination の反復パターンを容易に弾く
**リスク**: 中（反復のある正常発話も誤削除の可能性）
**実装**: 1 行追加

#### Stage 3: 信頼度 + 反復フィルタ（高リスク）

```swift
let decodeOptions = DecodingOptions(
    language: language,
    noSpeechThreshold: 0.4,
    compressionRatioThreshold: 2.0,
    logProbThreshold: -0.8         // デフォルト -1.0 → -0.8（信頼度向上）
)
```

**効果**: 自信のない出力を積極的に失敗扱い＆再トライ
**リスク**: 高（処理時間 1.5～2 倍化＋再トライで日本語精度低下）
**実装**: 1 行追加

#### 推奨の段階的導入

1. **初版リリース**: Stage 1 のみ（noSpeechThreshold: 0.4）
2. **実機テスト期間**: hallucination 発生状況を記録
3. **改善版**: hallucination が多ければ Stage 2 へ進める
4. **本格版**: 日本語精度テストを十分実施後に Stage 3 検討

#### パラメータ調整値の根拠

| パラメータ | デフォルト | 推奨値 | 理由 |
|----------|---------|-------|------|
| noSpeechThreshold | 0.6 | 0.4 | 無音→Whisper 送信を削減。logProb チェックもあるため誤削除リスク低 |
| compressionRatioThreshold | 2.4 | 2.0 | 反復 >2.0 で高圧縮比。hallucination の「ありがとうございました」(12字) が 圧縮比 1.3-1.5 程度なので余裕あり |
| logProbThreshold | -1.0 | -0.8 | 信頼度 -0.8 が「50% 確度」相当。日本語で は -1.0 でも多くが通過するため注意 |
| suppressBlank | false | **true** | [BLANK] トークン抑制で無音判定を支援（推奨） |

---

## 9. 実装ロードマップ（優先度順）

### Phase 1: フィルタ実装（最優先、リスク最小）
1. WhisperManager に hallucination フィルタ関数追加
2. 日本語＋英語の基本定型句リスト（20 個程度）
3. 実装コスト: 2-4 時間

### Phase 2: VAD 統合（中優先、安定性確認後）
1. WhisperKitConfig で EnergyVAD(energyThreshold: 0.01) 設定
2. WhisperManager.setupWhisper() で config 適用
3. 実機テスト: 低音量発話の通過確認
4. 実装コスト: 3-5 時間

### Phase 3: DecodingOptions 調整（低優先、テスト結果ベース）
1. Stage 1: noSpeechThreshold: 0.4 のみ適用
2. 実機テスト（hallucination 頻度測定）
3. hallucination 多発時のみ Stage 2 へ進める
4. 実装コスト: 1-2 時間（パラメータ変更のみ）

---

## 10. 不確かな点 / 要確認事項

1. **WhisperKit v0.18.0 の transcribe() 実装詳細**
   - clipTimestamps が実際にどのタイミングで Whisper に反映されるのか（transcribe 内部フロー要確認）
   - 参考: `/Users/tamekuniz/GitHub/tamekuniz/TTT/.build/checkouts/WhisperKit/Sources/WhisperKit/Core/WhisperKit.swift` 行599-611

2. **EnergyVAD のフレーム長と Whisper 処理単位の整合性**
   - frameLength = 0.1秒 が Whisper の window seek 単位（デフォルト 30秒？）と如何に相互作用するか
   - calculateActiveChunks() の戻り値がどのように使われるか

3. **AudioRecorder の WAV フォーマット仕様**
   - 現状：outputFormat(forBus: 0) から自動取得
   - サンプリングレート（44.1kHz vs 16kHz）が WhisperKit の 16kHz 仮定と一致するか

4. **日本語 hallucination パターンの完全性**
   - 初版リスト（20 個）でカバレッジはどの程度か
   - ユーザー報告の仕組みが必要か

5. **パフォーマンス測定方法**
   - 実機テストで「処理時間」「品質スコア」をどのように記録するか
   - StatusMessage だけでなく、詳細ログを Coordinator に付加する機構が必要

---

## 11. 結論

### 3 層防御の実装可能性

| 層 | 実装方法 | リスク | 優先度 |
|----|--------|-------|-------|
| (1) VAD | EnergyVAD@WhisperKitConfig | 低 | 中 |
| (2) フィルタ | 完全一致ホワイトリスト | 最小 | **最優先** |
| (3) パラメータ | Stage 1: noSpeechThreshold 調整 | 低 | 低（テスト結果ベース） |

### 初版実装の推奨スコープ

1. **必須**: フィルタ実装（Phase 1）
2. **推奨**: VAD 統合（Phase 2、実機テスト並行）
3. **オプション**: DecodingOptions 調整（Phase 3、hallucination 多発時）

### テスト戦略

- **実機テスト必須**: 日本語認識精度（VAD＆パラメータ調整の副作用測定）
- **シナリオテスト**: 完全無音、低音量、正常発話、定型句などの 6 シナリオ
- **品質メトリクス**: Whisper 実行時間、hallucination 率、正常発話の削除率

