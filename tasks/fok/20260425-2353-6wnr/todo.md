# フォK Step 4 実装計画 - ショートカット録音開始/停止時のフィードバック追加

## 要件サマリ

- 録音開始時: 触覚フィードバック（既存 `.generic`）に加えて **「Tink」システム音** を追加
- 録音停止時: 触覚フィードバック（既存 `.levelChange`）に加えて **「Pop」システム音** を追加
- 設定トグル: SettingsManager に `soundFeedbackEnabled: Bool`（デフォルト true）追加。OFF 時は音を鳴らさない
- 設定 UI: SettingsView に「フィードバック音」トグル追加
- 既存 `NSSound.beep()`（recordTriggerFeedback 内）は維持。今回の追加対象外

## 投資判断

- 規模: 1サイクル完結（タスク2件）
- 既存パターン流用率高（performHapticFeedback 既存 / @Published + UserDefaults テンプレ既存 / settingRow 既存）
- リスク低（録音バッファ混入なし、レイテンシ影響なし、副作用なし）

---

## タスク一覧

### Task 1: SettingsManager に音フィードバック設定プロパティを追加

**目的**: 「フィードバック音 ON/OFF」を永続化できる @Published プロパティを追加する

**対象ファイル**:
- `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/SettingsManager.swift`

**変更内容**:

1. **@Published プロパティ追加**（既存 Bool 系プロパティの近傍、または既存 String 系プロパティの末尾に配置）:
   ```swift
   @Published var soundFeedbackEnabled: Bool {
       didSet { UserDefaults.standard.set(soundFeedbackEnabled, forKey: "soundFeedbackEnabled") }
   }
   ```

2. **init 内の復元ロジック追加**:
   ```swift
   // UserDefaults に値が無い場合は true（デフォルト ON）
   if UserDefaults.standard.object(forKey: "soundFeedbackEnabled") != nil {
       self.soundFeedbackEnabled = UserDefaults.standard.bool(forKey: "soundFeedbackEnabled")
   } else {
       self.soundFeedbackEnabled = true
   }
   ```

   **注意**: `UserDefaults.standard.bool(forKey:)` は未設定時に `false` を返してしまうため、`object(forKey:)` で存在チェックを行ってデフォルト true を担保する。

**命名規約**:
- プロパティ名: `soundFeedbackEnabled`（既存の Bool プロパティ命名と整合。RawValue サフィックスは Bool には付けない）
- UserDefaults キー: `"soundFeedbackEnabled"`（プロパティ名と一致、キャメルケース）

**検証**:
- `swift build` が通る
- 設定 ON → アプリ再起動 → ON 維持
- 設定 OFF → アプリ再起動 → OFF 維持
- 初回起動時はデフォルト ON

---

### Task 2: TypeToTalkApp & SettingsView に音フィードバック実装と UI を追加

**目的**: 録音開始/停止時に設定値に応じてシステム音を鳴らし、設定画面にトグルを追加する

**対象ファイル**:
- `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`
- `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Views/SettingsView.swift`

**変更内容**:

#### 2-A. TypeToTalkApp.swift — playFeedbackSound ヘルパー追加

`performHapticFeedback`（第275-277行）の直下に新規メソッド追加:

```swift
private func playFeedbackSound(named name: String) {
    guard settings.soundFeedbackEnabled else { return }
    NSSound(named: name)?.play()
}
```

**配置位置**: performHapticFeedback の直下（同種ユーティリティのまとまり）

#### 2-B. TypeToTalkApp.swift — toggleRecording 内で音再生呼び出し

| 箇所 | 行番号目安 | 既存 | 追加 |
|---|---|---|---|
| 録音停止時 | 第127行 `performHapticFeedback(.levelChange)` の **直前** | 触覚 .levelChange | `playFeedbackSound(named: "Pop")` |
| 録音開始時 | 第199行 `performHapticFeedback(.generic)` の **直前** | 触覚 .generic | `playFeedbackSound(named: "Tink")` |

**順序**: 音 → 触覚（音を先に出して即触覚で確認の流れ。投資判断: 触覚は実質ノーレイテンシなので順序の体感差はほぼない）

**入力成功時 (.alignment 第181行)**: 今回の要件外。**変更しない**。

#### 2-C. SettingsView.swift — トグル UI 追加

「文体」 settingRow（第184-192行）の近傍（フィードバック系をまとめる場所、なければ「文体」の直前）に追加:

```swift
settingRow("フィードバック音") {
    Toggle("", isOn: $settings.soundFeedbackEnabled)
        .labelsHidden()
        .toggleStyle(.switch)
}
```

**配置判断**:
- 「文体」は出力フォーマット系、「フィードバック音」は UI 体験系
- 既存の settingRow 順序を見て、一般設定セクションの末尾（または開始/停止系設定の近く）に配置
- 実装時に SettingsView.swift 全体を Read してセクション構造を確認のうえ、最も自然な位置に挿入

**検証**:
- `swift build` が通る
- 設定 ON で録音開始 → Tink 音が鳴る
- 設定 ON で録音停止 → Pop 音が鳴る
- 設定 OFF で録音開始/停止 → 音なし、触覚のみ
- 設定 UI で「フィードバック音」トグルが表示・操作できる
- アプリ再起動後も設定値維持

---

## 実装順序と依存関係

```
Task 1 (SettingsManager) → Task 2 (TypeToTalkApp + SettingsView)
```

Task 2 の playFeedbackSound と Toggle は Task 1 のプロパティに依存するため、必ず Task 1 を先に完了する。

## テスト戦略

### ビルド検証
- `cd /Users/tamekuniz/GitHub/tamekuniz/TTT && swift build` → 成功

### 自動テスト
- `swift test` → 既存 16 件 PASS 維持（新規プロパティの存在を確認するテスト追加は今回スコープ外。既存挙動に副作用がないことを保証）

### 実機目視テスト（フォK Step 6 で実施）
1. 設定 ON で録音開始 → Tink + 触覚
2. 設定 ON で録音停止 → Pop + 触覚
3. 設定 OFF で録音開始 → 触覚のみ
4. 設定 OFF で録音停止 → 触覚のみ
5. アプリ再起動 → 設定値維持
6. 設定 UI トグル表示・操作確認
7. 右Option トリガでも同様に動作（toggleRecording 経由なので自動で追従するはず）

## 影響範囲の確認

- **既存挙動への副作用**: なし（音フィードバックは追加のみ、デフォルト ON でも今までより音が増えるだけ）
- **既存 NSSound.beep()（recordTriggerFeedback 内）**: 維持。今回の soundFeedbackEnabled トグルの管轄外
- **performHapticFeedback 呼び出し**: 既存3箇所をそのまま維持
- **録音バッファへの音混入リスク**: なし（投資判断: investigation §5.1 参照）

## 不確かな点 / 実装時に確認

1. **SettingsView のセクション構成**: 「フィードバック音」を入れる最適セクションは実装時に Read で確認のうえ判断
2. **Toggle スタイル**: `.switch`（macOS デフォルト）で問題ないが、既存 SettingsView に Toggle が無い場合は他のコンポーネントとの視覚的整合を実装時に再確認
3. **soundFeedbackEnabled プロパティの配置位置**: 既存 SettingsManager の Bool プロパティに合わせる。Bool が無ければ String 系の末尾に新規セクションとして追加
