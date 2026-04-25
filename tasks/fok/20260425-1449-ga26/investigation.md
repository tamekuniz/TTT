# TypeToTalk UI/UX 改善 3 件 - 実装調査レポート

## 1. 関連ファイル一覧

| パス | 役割 |
|------|------|
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/AccessibilityManager.swift` | アクセシビリティ権限チェック、テキスト挿入実装。`AXIsProcessTrusted()`、`AXIsProcessTrustedWithOptions()`、`AXUIElementCreateSystemWide()`、`insertText()` を含む |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift` | メイン UI、マイクボタン（ZStack + Circle + Image）、SettingsLink（歯車）、ステータスバッジ、録音状態遷移、触覚フィードバック呼び出し（`recordTriggerFeedback` + `NSSound.beep()`） |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Views/SettingsView.swift` | アクセシビリティ権限ボタン、`requestPermission()`、`openAccessibilitySettings()` 呼び出し、権限状態表示（checkmark / exclamationmark） |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/AudioRecorder.swift` | マイク権限管理、`startRecording()`、`stopRecording()`。触覚フィードバック未使用 |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/SettingsManager.swift` | ユーザー設定永続化。言語、文体、プロンプトモード、ショートカットモード、API キーなど |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Resources/Info.plist` | バンドル識別子、バージョン、プライバシー説明文。`Privacy - Accessibility Usage Description` を含む |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Tests/TypeToTalkTests/AudioRecorderTests.swift` | AudioRecorder のユニットテスト。権限チェック、マイク権限別の分岐テスト |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Tests/TypeToTalkTests/ModelSelectionTests.swift` | Whisper / Bonsai / SettingsManager のロジックテスト |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Package.swift` | Swift 6.0、macOS 14+ ターゲット。AccessibilityManager は AppKit のみ使用（外部依存なし） |

---

## 2. 既存実装パターン

### 2.1 AccessibilityManager の権限チェック実装

**ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/AccessibilityManager.swift`

| 関数 | 実装位置 | 詳細 |
|------|--------|------|
| `refreshPermissionStatus()` | line 20-22 | `AXIsProcessTrusted()` を呼び出して `@Published var hasPermission` を更新。プロンプト非表示版（毎回チェック） |
| `requestPermission()` | line 24-27 | `AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true])` を呼び出す。**プロンプト表示版** |
| `insertText()` | line 36-60 | テキスト挿入処理。**2 段階権限チェック**：(1) line 38 で `hasPermission \|\| AXIsProcessTrusted()` を評価（キャッシュ + 動的確認）；(2) permission なければ `.missingPermission` を return；(3) フォーカス要素を取得；(4) `AXUIElementSetAttributeValue()` でテキスト設定を試行；(5) 失敗時は `typeTextUsingEvents()` フォールバック |

**重要**: `insertText()` の line 38 では毎回 `AXIsProcessTrusted()` を呼ぶため、**キャッシュ値を参照しながらも動的チェックしている状態**。ただし `hasPermission` が false の場合は即座に return される（短路評価）。

### 2.2 SwiftUI ボタン化パターン

**ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`

| 要素 | 実装位置 | パターン | 区別方法 |
|------|--------|--------|--------|
| マイクボタン（録音開始/停止） | line 36-51 | `Button { await coordinator.toggleRecording() }` + `ZStack { Circle() + Image() }` + `.buttonStyle(.plain)` + `.disabled(coordinator.isProcessing)` | Circle の色で状態区別（赤=録音中、青=準備完了） |
| 歯車ボタン（設定ナビゲーション） | line 28-32 | `SettingsLink { Image(systemName: "gearshape") }` + `.buttonStyle(.plain)` | 固定の歯車アイコン、常に押下可能（disabled なし） |
| ステータスバッジ（Whisper/Formatter 状態） | line 124-139 | `statusBadge()` ヘルパー、`Circle().fill(statusColor)` + `Text(value)` + `.padding()`、Capsule 背景 | **非ボタン化**。クリック不可。色は状態に応じて自動判定（line 141-155） |

**既存の視覚的「押下可能」表現**:
- `.buttonStyle(.plain)` で既存スタイル削除
- 明示的な `.disabled()` で無効化
- マイク Circle は `.frame(width: 88, height: 88)` で大きく表示

### 2.3 macOS 触覚フィードバック既存利用

**結論**: **現在、macOS 触覚は未使用。** 音声フィードバックのみ実装。

**ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`

| 関数 | 実装位置 | 実装内容 |
|------|--------|--------|
| `recordTriggerFeedback(source:)` | line 345-351 | (1) `lastTriggerSource = source` で UI 更新；(2) 条件付き `statusMessage = "\(source) を受信"` 表示；(3) **`NSSound.beep()`** のみ（触覚なし） |

**触覚 API は未使用**: grep で `NSHapticFeedbackManager`、`NSHapticFeedback`、`haptic` を検索した結果、コード内に一切出現せず。

---

## 3. 影響範囲

### 3.1 要件① アクセシビリティ権限の根本解決

#### 権限チェック呼び出しタイミングと経路

```
toggleRecording() [TypeToTalkApp:213]
  ↓
  status: "テキスト入力中..." [line 261]
  ↓
  accessibility.insertText(finalText) [line 262]
    ↓
    (1) guard hasPermission || AXIsProcessTrusted() [line 38]
        ├─ false → return .missingPermission
        └─ true → continue
    ↓
    (2) AXUIElementCreateSystemWide() [line 43]
    (3) AXUIElementCopyAttributeValue() → focused element [line 45]
    (4) AXUIElementSetAttributeValue() → テキスト設定 [line 51]
        └─ 失敗 → typeTextUsingEvents() フォールバック [line 55]
  ↓
  switch on InsertResult [line 262-272]
    ├─ .success → statusMessage = "完了"
    ├─ .missingPermission → showAccessibilityPermissionAlert = true [line 267]
    ├─ .noFocusedElement → statusMessage = "入力先が見つかりません"
    └─ .unsupportedTarget → statusMessage = "この入力欄には書き込めません"
```

#### UI への権限反映経路

```
SettingsView [line 254-283]
  ↓
  accessibility.hasPermission [line 265]
    ├─ true → Image("checkmark.circle.fill") + "許可済み" [green]
    └─ false → Image("exclamationmark.triangle.fill") + "設定を開く" [orange]
  ↓
  Button "設定を開く" tap [line 267-271]
    ├─ accessibility.requestPermission() [line 269, prompt版]
    └─ accessibility.openAccessibilitySettings() [line 270]
```

**問題の焦点**:
- `requestPermission()` は `AXIsProcessTrustedWithOptions(prompt: true)` を呼ぶため、**毎回プロンプトダイアログが出る可能性がある** ← ユーザーが「設定を開く」を繰り返し押下した場合に UX 悪化
- `insertText()` の line 38 は `hasPermission || AXIsProcessTrusted()` なので、**キャッシュ値がいったん false になると、以降の動的再チェックが失効する可能性** ← 権限を後から付与しても反映されない
- 再ビルド時に bundle path が変わると、前回の権限情報がクリアされる（macOS の Accessibility DB がバンドル ID + パス組で管理） ← これは本当の根本問題

#### 呼び出し側

- `insertText()` を呼ぶ側: `coordinator.toggleRecording()` [TypeToTalkApp:213]
- 権限チェック関数を直接呼ぶ側: SettingsView の「設定を開く」ボタン [SettingsView:269]

### 3.2 要件② アイコンの状態 vs ナビゲーション区別

#### 現在の実装構造

```
TypeToTalkMainView.body [TypeToTalkApp:13-82]
  ├─ HStack(top) [line 15-33]
  │  ├─ VStack(title + statusMessage) [line 16-24]
  │  └─ SettingsLink { Image(gearshape) } [line 28-32]
  │     └─ .buttonStyle(.plain)
  │
  ├─ Button { toggleRecording() } [line 36-51]  ← マイクボタン（状態依存、押下可能）
  │  └─ ZStack {
  │     ├─ Circle().fill(micButtonColor) [line 42-44]
  │     │  ├─ if isRecording → red [line 86]
  │     │  ├─ elif whisperKit loaded → blue(0.10, 0.47, 0.95) [line 90]
  │     │  └─ else → cyan(0.45, 0.83, 0.98) [line 93]
  │     └─ Image(recorder.isRecording ? "stop.fill" : "mic.fill") [line 45]
  │  └─ .buttonStyle(.plain)
  │  └─ .disabled(coordinator.isProcessing)
  │
  └─ VStack(status rows) [line 53-68]
     ├─ Whisper status row [line 54-58]
     │  └─ statusBadge(whisper.statusText) [line 113]
     │     ├─ Circle().fill(statusColor(for:)) [line 126-128]
     │     ├─ Text(status) [line 129-131]
     │     └─ **非ボタン化（clickable でない）**
     │
     └─ Formatter status row [line 59-63]
        └─ statusBadge(formatter.statusText) [line 113]
           └─ **非ボタン化**

micButtonColor computed property [line 84-94]:
  ├─ isRecording → red
  ├─ whisperKit != nil → blue (モデル準備完了)
  └─ else → cyan (スタンバイ)

statusColor(for:) helper [line 141-155]:
  ├─ "準備完了" / "完了" → green
  ├─ "読込中" / "録音中" → orange
  ├─ "失敗" / "未接続" / "未読込" → brown
  └─ default → secondary.opacity(0.7)
```

#### ボタン区別の問題点

**現在の区別方法**:
1. マイクボタン: `Button` で囲む、`.disabled(coordinator.isProcessing)` で無効化 ✓
2. 歯車ボタン: `SettingsLink` で囲む ✓
3. ステータスバッジ: **ボタン化されていない**、単なる `HStack + Text + Badge` → **ユーザーがクリック試行しても何も起きない**

**想定される改善点**:
- ステータスバッジを `.buttonStyle(.link)` など視覚的に区別できるように変更 → ButtonStyle 波及範囲が生じる可能性
- または、ステータスバッジに `.help()` tooltip を追加してクリック不可を明示 → 影響は局所的

#### SwiftUI 既存パターン適用可能範囲

```swift
// 既存: .plain
.buttonStyle(.plain)

// 候補:
.buttonStyle(.link)           // 青いリンク表記（SettingsLink と一貫）
.buttonStyle(.bordered)       // 枠付き（ステータス=情報表示なら過剰かも）
.help("クリック不可。現在の状態です")  // tooltip 追加（非破壊的）
.contentShape(Circle())       // クリック領域を明示（既存では不使用）
```

### 3.3 要件③ 音声入力中の触覚/視覚フィードバック

#### 現在の実装と触覚の未使用

**音声フィードバック (既存)**:
```
recordTriggerFeedback(source: String) [TypeToTalkApp:345-351]
  ├─ NSSound.beep() [line 350]
  └─ statusMessage 表示
```

**触覚フィードバック (未実装)**:
- `NSHapticFeedbackManager` / `NSHapticFeedbackPerformer` のコード内出現 0
- macOS Haptics API: `.alignment`, `.levelChange`, `.generic` の pattern は未使用

#### 視覚フィードバック (既存)

**マイクボタンの状態遷移**:
```
toggleRecording() [TypeToTalkApp:213-283]
  ├─ if isRecording:
  │  ├─ recorder.stopRecording() [line 215]
  │  ├─ statusMessage = "文字起こし中..." [line 216]
  │  ├─ isProcessing = true [line 217]
  │  └─ UI 更新:
  │     ├─ micButtonColor: red → cyan (isRecording = false)
  │     ├─ Image icon: stop.fill → mic.fill
  │     └─ Button disabled (isProcessing = true)
  │
  └─ else:
     ├─ recorder.startRecording() [line 277]
     ├─ statusMessage = "録音中..." [line 278]
     └─ UI 更新:
        ├─ micButtonColor: cyan → red (isRecording = true)
        ├─ Image icon: mic.fill → stop.fill
        └─ Button enabled
```

**statusMessage の条件付き表示**:
- line 19-23: `if !coordinator.statusMessage.isEmpty { Text(statusMessage) }`

#### 触覚フィードバック挿入タイミングの候補

```
1. 録音開始時 (toggleRecording -> isRecording = true)
   → NSHapticFeedbackManager.defaultPerformer.perform(.generic)
   
2. 録音停止時 (toggleRecording -> isRecording = false)
   → NSHapticFeedbackManager.defaultPerformer.perform(.levelChange)
   
3. テキスト挿入完了時 (insertText -> .success)
   → NSHapticFeedbackManager.defaultPerformer.perform(.alignment)
```

**視覚フィードバック拡張の候補**:
```swift
// 既存: Circle color + icon change + statusMessage
// 候補追加:
.scaleEffect(1.0 + (isRecording ? 0.1 : 0.0))      // 録音時に若干拡大
.animation(.spring(), value: coordinator.isRecording)

// または
.symbolEffect(.bounce, value: recorder.isRecording)  // iOS 17.2+ 同等の bounce（macOS 未確認）
.symbolEffect(.variableColor, value: coordinator.isProcessing)  // 処理中に色が変わる
```

---

## 4. 過去の類似実装

**Git ログ確認**:
```
$ git log --oneline --all | head -10
16d3413 [フォK] feat: UI整理＋言語設定＋整形プロンプト構造化
4b03313 [フォK] feat: TypeToTalk リファクタ完了＋整形AI整合性とウインドウトグル追加
cb281cf Refactor: Modularize project structure (App, Managers, Models, Views)
db58908 Implement Settings UI for API keys and custom prompts
1f0d5e7 Add documentation and Info.plist for system permissions
ca4c764 Initial commit of TTT (Talk to Type) macOS app
```

**結果**: 権限プロンプト、UI 区別、触覚フィードバックの過去類似実装は **git log に見当たらず**。初回実装。

---

## 5. 想定される副作用 / リスク

### 5.1 要件① 権限チェック

| リスク | 内容 | 緩和策 |
|--------|------|--------|
| **プロンプト連続表示** | `AXIsProcessTrustedWithOptions(prompt: true)` を毎回呼ぶと、ユーザーが「設定を開く」を連打した場合にダイアログが何度も出現 | `requestPermission()` は 1 回だけ呼び出す、以降は `refreshPermissionStatus()` を使用するよう UI ロジックを変更 |
| **キャッシュ無効化** | line 38 の `hasPermission \|\| AXIsProcessTrusted()` で短路評価されるため、false → true 遷移時に反映遅延の可能性 | `insertText()` 実行前に常に `refreshPermissionStatus()` を呼ぶ、または削除後の権限追加を Polling で確認 |
| **再ビルド後の権限消失** | 開発環境で `/tmp/TypeToTalkDerivedData/...` 配下の bundle path が変わると、macOS Accessibility DB のレジストリが無効化される | Code signing ID 固定化（`PRODUCT_BUNDLE_IDENTIFIER` を Xcode project で明示的に設定）、または Bundle ID に UUID を混ぜない |

### 5.2 要件② UI 区別

| リスク | 内容 | 緩和策 |
|--------|------|--------|
| **ボタンスタイル波及** | `statusBadge()` に `.buttonStyle()` を適用すると、Capsule 背景の padding や色が変わる可能性 | `.buttonStyle(.plain)` を使用（既存マイク・歯車と統一）、または別途の `.help()` tooltip で非ボタン化を明示 |
| **レイアウト崩れ** | `.disabled()` 適用時に opacity 変更で視認性が下がる可能性 | 既存マイクボタンと同じ pattern を使用（`.disabled()` あり）、または opacity override を明示的に設定しない |
| **ホバーエフェクト未定義** | SwiftUI の `hoverEffect()` を追加しない場合、ボタン化した要素でマウスホバー時の視覚フィードバックが不明確 | `.hoverEffect()` の macOS サポート確認（macOS 14+ で利用可か）、または `.help()` tooltip だけで十分 |

### 5.3 要件③ 触覚/視覚フィードバック

| リスク | 内容 | 緩和策 |
|--------|------|--------|
| **デバイス非対応** | `NSHapticFeedbackManager` は **Force Touch trackpad のみ対応**（Magic Mouse 非対応） | 無視される（API 仕様）。デバイスが非対応の場合は何も起こらない（エラーではない） |
| **@MainActor 違反** | `NSHapticFeedbackManager.defaultPerformer.perform()` が main thread 要求の可能性 | 既に `@MainActor` が `TypeToTalkCoordinator` に付いているため、問題なし |
| **アニメーション GPU 負荷** | `.scaleEffect()` + `.repeatForever()` で連続アニメーションする場合、CPU/GPU 負荷増加 | 短時間アニメーション（`.spring(response: 0.3)` など）に制限、または `onAppear`/`onDisappear` で制御 |
| **視覚効果の過剰** | `symbolEffect()` が macOS に実装されていない（iOS 17.2+ 限定） | macOS 14+ で動作確認が必須。代替え：`.scaleEffect()` + `.animation()` を使用 |

---

## 6. 制約条件

| 項目 | 仕様 |
|------|------|
| **Swift version** | Swift 6.0（Package.swift に明記） |
| **macOS target** | macOS 14+（`.macOS(.v14)`） |
| **@MainActor** | `AccessibilityManager`、`AudioRecorder`、`TypeToTalkCoordinator` に既に付与 |
| **フレームワーク** | AppKit (`AccessibilityManager` は `import AppKit` のみ、外部依存なし） |
| **Accessibility API** | `AXUIElement*` 関数族、ApplicationServices フレームワーク（macOS 標準、import 不要） |
| **命名規約** | camelCase for properties/methods（既存コード参照：`hasPermission`、`insertText`、`toggleRecording` など） |
| **SwiftUI modifier** | `.buttonStyle()`、`.disabled()`、`.help()`、`.animation()`、`.scaleEffect()` はすべて macOS 14+ で利用可 |

---

## 7. テスト戦略

### 7.1 ユニットテスト（既存テスト拡張可能）

#### AccessibilityManager の権限チェックロジック

**テスト追加可能**:
```swift
// AccessibilityManager に対するテスト
@MainActor
func testAccessibilityManagerRefreshPermissionStatus() {
    let manager = AccessibilityManager()
    // 権限がない状態を想定
    manager.refreshPermissionStatus()
    // AXIsProcessTrusted() の返値に基づいて hasPermission が更新されることを確認
    // ※ 実機でのみ true/false が決定するため、sandbox では常に false の可能性
}

@MainActor
func testAccessibilityManagerInsertTextMissingPermission() {
    let manager = AccessibilityManager()
    manager.hasPermission = false
    
    let result = manager.insertText("test")
    XCTAssertEqual(result, .missingPermission)
}

@MainActor
func testAccessibilityManagerInsertTextEmptyString() {
    let manager = AccessibilityManager()
    
    let result = manager.insertText("")
    XCTAssertEqual(result, .success)  // 空文字は常に成功
}
```

**テスト書けない部分**:
- `requestPermission()` の `AXIsProcessTrustedWithOptions(prompt: true)` はプロンプトダイアログを表示するため、自動テスト不可
- `AXUIElementSetAttributeValue()` の成功/失敗判定は、フォーカス要素の有無に依存（テスト環境では不安定）

#### AudioRecorder のテスト（既存）

**既存**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Tests/TypeToTalkTests/AudioRecorderTests.swift`
- `testTapHandlerWritesBufferOffMainThread()`: tap handler が async に動作することを確認
- `testStartRecordingReturnsExpectedURLOrThrowsWhenPermissionDenied()`: マイク権限別に分岐テスト

**拡張可能な項目**:
- 触覚フィードバック呼び出しロジック（`toggleRecording()` 前後） → **但し NSHapticFeedbackManager は mock 化が複雑**

### 7.2 実機/ビルド確認ポイント（テスト不可）

| テスト項目 | 確認方法 |
|-----------|--------|
| **アクセシビリティ権限の再取得** | (1) システム設定で TypeToTalk の権限をOFF；(2) SettingsView の「設定を開く」押下；(3) システム設定で再度ON；(4) toggleRecording で insertText 実行 → 成功することを確認 |
| **マイクボタン UI 状態遷移** | (1) 「未準備」（Circle cyan）→（2）モデル読込中（Circle cyan）→（3）準備完了（Circle blue）→（4）録音中（Circle red）の色遷移を目視確認 |
| **ステータスバッジの視認性** | (1) Whisper 読込中（orange）；(2) Formatter 成形中（orange）；(3) 完了（green）の各状態で色が正確に表示されることを確認 |
| **触覚フィードバック** | Force Touch trackpad で実機テスト：(1) 録音開始時 vibrate；(2) テキスト挿入成功時 vibrate。Magic Mouse では反応なし（仕様） |
| **視覚フィードバック（アニメーション）** | (1) マイク Circle が滑らかに拡大/縮小；(2) statusMessage が即座に更新される（ラグなし）ことを確認 |
| **再ビルド後の権限保持** | (1) 権限 ON → (2) Xcode rebuild（`Product > Clean Build Folder`）；(3) toggleRecording で insertText 実行 → 権限が保持されるか確認（失敗時は bundle path 変動の影響） |

### 7.3 テスト実装上の注記

- **Accessibility API テスト**: `AXIsProcessTrusted()` は実行プロセスが Accessibility 許可されている場合のみ true を返すため、CI/sandbox では常に false。ロジック検証は mock/stub 化で可能だが、実装者の判断。
- **触覚フィードバック**: `NSHapticFeedbackManager.defaultPerformer.perform()` は @MainActor context で動作し、macOS の haptic engine に委譲。機器依存のため mock 化は困難。
- **UI レイアウト**: SwiftUI preview では responsive が限定的なため、実機での `.frame()` / `.padding()` / `.disabled()` の視覚的効果を確認推奨。

---

## 補足: 実装の確実性に関わる重要ポイント

### AXIsProcessTrusted の戻り値と毎回チェック

AccessibilityManager.swift の line 38:
```swift
guard hasPermission || AXIsProcessTrusted() else {
    hasPermission = false
    return .missingPermission
}
```

**重要**: `hasPermission` が false になると、以降 `||` の右辺 `AXIsProcessTrusted()` が評価される。この時点で権限がユーザーによって付与されていれば true を返すが、上記の guard で `hasPermission = false` が設定されているため、**次回以降の insertText() 呼び出しでも短路評価で return される可能性がある**。

**改善案**: insertText() の冒頭で常に `refreshPermissionStatus()` を呼び出すか、`hasPermission` が false の場合でも毎回 `AXIsProcessTrusted()` を動的評価する logic の追加を検討。

### buttonStyle 波及範囲の詳細確認

SettingsView の既存パターン:
```swift
// SettingsView.swift line 273
Button(accessibility.hasPermission ? "許可済み" : "設定を開く") { ... }
    .disabled(accessibility.hasPermission)
```

この Button は `.buttonStyle()` の明示指定がない（デフォルト）。もし `statusBadge()` をボタン化する場合、`.buttonStyle(.plain)` を追加することで既存マイク・歯車と統一できる。ただし、Capsule 背景の visual がボタン化によって変わるリスクがある。

### macOS Haptics の対応デバイス

macOS 14（Sonoma）の Haptics API は Force Touch trackpad のみサポート。Magic Mouse、Magic Trackpad（Force Touch 非搭載）、外部 Trackpad では無視される。`perform()` の戻り値は常に成功（エラー code なし）なため、「動作したが反応がない」状態になる（エラーではない）。

---

## 結論

### 要件① アクセシビリティ権限

**実装の複雑性**: **中** → 権限チェック関数の refactor + UI logic の conditional 調整が必要。特に再ビルド時の bundle path 無効化は code level では対応困難（Xcode project の PRODUCT_BUNDLE_IDENTIFIER 設定で根本対応）。

### 要件② UI 区別

**実装の複雑性**: **低** → `.help()` tooltip か `.buttonStyle(.plain)` の追加のみで解決可能。既存パターン（マイク・歯車ボタン）と統一すれば波及範囲は局所的。

### 要件③ 触覚/視覚フィードバック

**実装の複雑性**: **低〜中** → 視覚フィードバック（`.scaleEffect()` + `.animation()`）は比較的簡単。触覚は API 呼び出しのみだが、device 依存が大。アニメーション過剰による GPU 負荷注視。
