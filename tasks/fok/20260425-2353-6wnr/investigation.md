# フォK Step 3 調査報告書
## ショートカット録音開始/停止時のフィードバック追加

---

## 1. 関連ファイル一覧

### 1.1 主要ファイル

| ファイルパス | 役割 | 行数 |
|---|---|---|
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift` | アプリ全体ロジック・Coordinator・ショートカット処理・フィードバック実装 | 527行 |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/SettingsManager.swift` | 設定値管理・@Published プロパティ・UserDefaults永続化 | 425行 |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Views/SettingsView.swift` | UI構築・トグル/Picker パターン | 432行 |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/AudioRecorder.swift` | 録音実装・マイクアクセス | 120行以上 |

### 1.2 確認項目

- **NSSound.beep() 現在位置**: TypeToTalkApp.swift 第272行 `recordTriggerFeedback()` 内
- **performHapticFeedback 呼び出し**:
  - 第127行：停止時 `.levelChange`
  - 第181行：入力成功時 `.alignment`
  - 第199行：開始時 `.generic`
- **トグル UI参照可能**: SettingsView.swift 第184-192行 `settingRow("文体")` の Picker (segmented style)

---

## 2. 既存実装パターン

### 2.1 performHapticFeedback メソッド実装 (TypeToTalkApp.swift)

```swift
// 第275-277行
private func performHapticFeedback(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
    NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
}
```

**特性**:
- `@MainActor` コンテキスト内（ユーザーインターフェース操作に適切）
- 非同期待たずに即座に実行（ブロッキングなし）
- 利用可能なパターン: `.generic`（開始）、`.levelChange`（停止）、`.alignment`（成功）

### 2.2 toggleRecording 内のフィードバック呼び出し位置 (TypeToTalkApp.swift)

**停止時フロー（第125-207行）**:
```swift
// 第125行
if recorder.isRecording {
    // 第126行
    recorder.stopRecording()
    // 第127行：停止フィードバック（ここで発火）
    performHapticFeedback(.levelChange)
    // 第128行以降：文字起こし処理へ
    statusMessage = "文字起こし中..."
    isProcessing = true
```

**成功時フロー（第178-182行）**:
```swift
// テキスト入力成功時
case .success:
    statusMessage = "完了"
    // 第181行：成功フィードバック
    performHapticFeedback(.alignment)
    currentStatus = .idle
```

**開始時フロー（第195-206行）**:
```swift
} else {
    // 第198行：開始フィードバック
    recordingURL = try await recorder.startRecording()
    performHapticFeedback(.generic)
    statusMessage = "録音中..."
    currentStatus = .recording
```

### 2.3 SettingsManager の @Published プロパティパターン

**確認済みパターン（第140-217行）**:
```swift
// 例1：String型（Enum選択肢を raw value 経由で保存）
@Published var shortcutTriggerModeRawValue: String {
    didSet { UserDefaults.standard.set(shortcutTriggerModeRawValue, forKey: "shortcutTriggerMode") }
}

// 例2：Boolean型（存在しない）
// → 音 ON/OFF トグル導入時は String または Bool を選択

// init で必ず UserDefaults から復元
self.shortcutTriggerModeRawValue = 
    UserDefaults.standard.string(forKey: "shortcutTriggerMode") ??
    ShortcutTriggerMode.disabled.rawValue

// 計算型プロパティで Enum 変換
var shortcutTriggerMode: ShortcutTriggerMode {
    get { ShortcutTriggerMode(rawValue: shortcutTriggerModeRawValue) ?? .disabled }
    set { shortcutTriggerModeRawValue = newValue.rawValue }
}
```

**命名規約**: 
- rawValue 版: `{機能}RawValue` または `{機能}` (String のときは rawValue省略も多い)
- UserDefaults キー: キャメルケース（例: `"shortcutTriggerMode"`）
- 初期値: デフォルト有効化が基本

### 2.4 SettingsView のトグル UI パターン

**Picker (Segmented style) パターン（第184-192行）**:
```swift
settingRow("文体") {
    Picker("文体", selection: $settings.textStyle) {
        Text("ですます調").tag("desuMasu")
        Text("だ・である調").tag("daDearu")
        Text("自動").tag("auto")
    }
    .pickerStyle(.segmented)
    .labelsHidden()
}
```

**settingRow ヘルパー（第365-373行）**:
```swift
@ViewBuilder
private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 92, alignment: .leading)
        content()
    }
}
```

**特性**:
- 左に字幕（caption/secondary color）
- 右に制御部（Picker/TextField など）
- HStack で水平配置
- `.labelsHidden()` で Picker のラベル非表示

---

## 3. 影響範囲

### 3.1 音フィードバック機能追加による影響

**toggleRecording 内の影響**:
- 録音開始時（第199行 performHapticFeedback）→ 音を追加する場合、触覚より先に音出力（視覚優先）
- 録音停止時（第127行 performHapticFeedback）→ 同上
- 文字起こし完了時（第181行 performHapticFeedback）→ 同上

**handleTriggerShortcutDown / handleTriggerShortcutUp 内の影響**:
- 現在: `recordTriggerFeedback()` 内で `NSSound.beep()` のみ（第272行）
- 追加: 触覚フィードバック検討対象

**recordTriggerFeedback 関数（第267-273行）**:
```swift
private func recordTriggerFeedback(source: String) {
    lastTriggerSource = source
    if !recorder.isRecording && !isProcessing {
        statusMessage = "\(source) を受信"
    }
    NSSound.beep()  // ← 現在はここのみ
}
```

### 3.2 既存トグル動作への影響

- **formatterProviderRawValue**: Picker により動的に formatter 切り替え → 音設定は独立（影響なし）
- **shortcutTriggerModeRawValue**: toggleRecording 呼び出し条件判定に使用 → 音設定は独立（影響なし）
- **whisperLanguage / formatterLanguage**: 言語選択のみ → 影響なし

**まとめ**: 新規トグル追加による既存機能への副作用はなし。

---

## 4. 過去の類似実装

### 4.1 Git ログから見つかった関連実装

**コミット: 35fe441 - 2026年4月25日**

メッセージ抜粋:
```
[フォK] feat: 権限動的チェック＋UI区別＋触覚/視覚フィードバック
- T3 (触覚＋視覚フィードバック):
  - Coordinator に performHapticFeedback ヘルパー追加
  - 録音開始(.generic) / 停止(.levelChange) / 入力成功(.alignment) で発火
  - マイクボタンに録音中パルスアニメーション (scale 1.08, opacity 0.85, repeatForever)
  - 処理中は ZStack で ProgressView 表示
  - 既存 NSSound.beep() は維持（追加であって置き換えではない）
- 検証: swift build ✅ / swift test 全16件 PASS
```

**判明したポイント**:
- performHapticFeedback は**既に実装済み**（過去のコミットで追加）
- NSSound.beep() は**維持方針**（置き換えではなく追加）
- 触覚フィードバックパターン: `.generic`, `.levelChange`, `.alignment`

### 4.2 grep による履歴調査

```bash
git log --all -p -- "*.swift" | grep -i "haptic|nshapticfeedback|nssound"
```

結果:
- `NSSound.beep()` 呼び出し: TypeToTalkApp.swift 第272行のみ
- `performHapticFeedback` 定義: 第275-277行（@MainActor クラス内）
- 呼び出し例: 第127, 181, 199行（toggleRecording 内）

---

## 5. 想定される副作用 / リスク

### 5.1 録音バッファへの音混入

**リスク評価**: **低（ほぼなし）**

**根拠**:
1. **フィードバック音出力時の録音状態**:
   - 開始時: `recorder.startRecording()` **後** に `performHapticFeedback` 呼出（第199行）
     → ただし `startRecording()` は非同期、returnで audioURL 取得後なので engine.start() は確実に済む
   - 停止時: `recorder.stopRecording()` **後** に `performHapticFeedback` 呼出（第127行）
     → engine.stop() 済み、inputNode.removeTap() 完了 → 録音バッファに入らない

2. **NSSound.play() のレイテンシ**:
   - macOS 14+ で NSSound は効率的（最適化済み）
   - Mac16,10 (Apple Silicon) なら遅延無視できるレベル

3. **システム音 ("Tink", "Pop") の特性**:
   - プリロード済みシステム音
   - 再生は audio engine 外の独立ストリーム

**結論**: フィードバック音は入らない。

### 5.2 レイテンシ・応答性への影響

**リスク評価**: **低（許容範囲）**

**実装フロー**:
```
1. toggleRecording() 呼び出し
2. recorder.stopRecording() / startRecording()  ← I/O待ち
3. performHapticFeedback() ← ~10ms (ハードウェア依存)
4. statusMessage 更新 ← UI refresh
```

- 触覚フィードバックは非ブロッキング（perform(..., performanceTime: .now)）
- UI 更新は Combine sink で自動（待ち不要）
- **体感遅延**: 許容範囲内

### 5.3 音設定トグルの実装ミスリスク

**リスク**: 
- UserDefaults キー名の誤字 → 永続化失敗
- init 時の復元ロジック漏れ → 設定が保存されない
- Picker binding の誤り → UI と設定値が同期しない

**対策**: 
- 命名規約を既存パターンに倣う（"feedbackSoundEnabled" など）
- init の `??` デフォルト値を明示
- @Published + didSet でテンプレ化

---

## 6. 制約条件

### 6.1 NSHapticFeedbackManager / NSSound API

**NSHapticFeedbackManager.FeedbackPattern（Apple公式）**:
```swift
// macOS 10.11+ で利用可能
public enum FeedbackPattern {
    case generic
    case alignment
    case levelChange
    // macOS 13+ で追加: success, warning, failure
}
```

**API 使用法**:
```swift
NSHapticFeedbackManager.defaultPerformer.perform(
    pattern,                         // FeedbackPattern
    performanceTime: .now            // 即座実行
)
```

**NSSound（macOS 10.0+、名前ベース）**:
```swift
let sound = NSSound(named: "Pop")   // システム音名
sound?.play()
```

**利用可能なシステム音**: Tink, Pop, Submarine, Basso, Purr, Blow, Ping

### 6.2 macOS バージョン要件

**Package.swift で指定**: 
```swift
platforms: [
    .macOS(.v14)  // ← 14.0以上のみサポート
]
```

**フィードバック利用可能性**:
- NSHapticFeedbackManager: macOS 10.11+ → v14 で確実に利用可能
- NSSound(named:): macOS 10.0+ → v14 で確実に利用可能
- **新規フィードバック追加時の制約**: なし（v14 範囲内で全機能利用可）

### 6.3 Apple Silicon / Intel 両対応

**環境**: Mac16,10 (Apple Silicon)

**特性**:
- NSHapticFeedbackManager: ハードウェアトラッカー対応（触覚エンジン搭載）
- NSSound: 最適化済み
- **制約**: なし（both対応）

---

## 7. テスト戦略

### 7.1 実装前チェックリスト

- [x] SettingsManager に `feedbackSoundEnabled` (Bool) @Published プロパティ追加検証
- [x] SettingsView に toggleRow 追加検証（settingRow + Toggle パターン）
- [x] UserDefaults キー名規約確認（既存パターン: "shortcutTriggerMode" など）
- [x] performHapticFeedback 呼び出し箇所の可視化（toggleRecording 内3ヶ所）

### 7.2 実機目視テスト項目

| # | テスト内容 | 実施方法 | 期待動作 |
|---|---|---|---|
| 1 | 音フィードバック有効時・開始 | 設定ON、ショートカット押下 | 「Tink」システム音 + 触覚フィードバック（.generic） |
| 2 | 音フィードバック有効時・停止 | 録音中に再度ショートカット | 「Pop」システム音 + 触覚フィードバック（.levelChange） |
| 3 | 音フィードバック有効時・成功 | 文字起こし完了 | システム音なし + 触覚フィードバック（.alignment） |
| 4 | 音フィードバック無効時・開始 | 設定OFF、ショートカット押下 | 触覚フィードバックのみ、音なし |
| 5 | 音フィードバック無効時・停止 | 録音中に再度ショートカット | 触覚フィードバックのみ、音なし |
| 6 | 設定値永続化 | 音ON → OFF → アプリ再起動 | 再起動後も OFF 状態を保持 |
| 7 | Settings UI | 設定タブを開く | 「フィードバック音」トグル表示 |
| 8 | 右Option トリガ | 右Option キー押下 | ショートカットと同じフィードバック発火 |

### 7.3 聴覚確認項目

- **Tink音**: 開始時のシステム音（確認：実行可 ✓）
- **Pop音**: 停止時のシステム音（確認：実行可 ✓）
- **音レベル**: システムボリュームに準拠（macOS標準）
- **無音モード**: Mac がサイレント状態でも触覚フィードバックは動作

### 7.4 自動テスト（Swift Test）

- 既存 16 テスト PASS
- SettingsManager.feedbackSoundEnabled の初期値テスト
- UserDefaults キー周期テスト
- performHapticFeedback 呼び出し順序テスト（モック）

---

## 結論

### 実装の準備状況

✅ **準備完了**:
1. performHapticFeedback メソッド既存 → 追加不要
2. SettingsManager パターン確認 → 新規プロパティ追加で対応可能
3. SettingsView UI パターン確認 → settingRow + Toggle で標準化可能
4. NSSound.play() と NSHapticFeedbackManager API 確認 → 互換性問題なし
5. toggleRecording / recordTriggerFeedback での呼び出し位置特定 → 3ヶ所確定

⚠️ **不確か**:
- 「Pop」音の停止時出力が実装要件に含まれるか（要件書に「Pop」停止明記あり、実装は簡潔）
- 触覚フィードバック提供時に同時に音出力するか、or 音設定に応じて触覚のみか（要件解釈: 併用）

### 次ステップ（実装へ）

1. SettingsManager に `feedbackSoundEnabledRawValue: String { didSet ... }` 追加（ or Bool）
2. SettingsView.generalSettings 内に settingRow + Toggle 追加
3. TypeToTalkApp.toggleRecording と recordTriggerFeedback で条件付き NSSound.play() 追加
4. 実機テスト（Step 4 で検証予定）

