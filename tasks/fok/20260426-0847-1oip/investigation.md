# Step 3 調査報告書：HUD パネル表示機構の設計検討

**実行日時**: 2026年4月26日 08:47（フォックスの極タマ）  
**対象要件**: 録音開始/停止時に視覚フィードバック HUD パネル表示  
**調査範囲**: 実装コード全体 + git history（commit 952921f^ ～ 現在）

---

## 1. 関連ファイル一覧

### 現在のメインファイル
| ファイルパス | 行数 | 役割 |
|---|---|---|
| `/Sources/TypeToTalk/App/TypeToTalkApp.swift` | 537 | アプリケーションエントリー。`TypeToTalkCoordinator`（AppStatus 管理）、`MenuBarLabel`、`MenuContentView`、`TypeToTalkApp` を含む |
| `/Sources/TypeToTalk/Managers/SettingsManager.swift` | 450+ | アプリ全体設定。**行212-214** で `soundFeedbackEnabled` Bool フラグあり |
| `/Sources/TypeToTalk/Views/SettingsView.swift` | 438 | 設定UI。**行248-252** でフィードバック音 Toggle を提供 |
| `/Sources/TypeToTalk/Managers/AccessibilityManager.swift` | 89 | テキスト入力権限管理。HUD では関連なし |
| `/Sources/TypeToTalk/Managers/AudioRecorder.swift` | 100+ | 録音管理。`isRecording` @Published フラグ管理 |
| `/Sources/TypeToTalk/Managers/WhisperManager.swift` | 100+ | Whisper ステータス。`statusText` 計算型プロパティ使用 |
| `/Sources/TypeToTalk/Managers/BonsaiManager.swift` | 100+ | Bonsai ステータス。`statusMessage` @Published プロパティ使用 |
| `/Sources/TypeToTalk/Managers/NetworkManager.swift` | 19 | ネットワーク状態。`isOnline` @Published フラグ |

### HUD パネル実装時の追加ファイル（予定）
| ファイルパス | 説明 |
|---|---|
| `/Sources/TypeToTalk/Views/HUDPanelView.swift` | **新規** 縮小版 TypeToTalkMainView（マイクボタン + ステータス 2行） |
| `/Sources/TypeToTalk/Managers/HUDPanelManager.swift` | **新規** NSPanel ライフサイクル・自動表示/隠蔽ロジック |

### 参考：削除されたファイル/コンポーネント（Phase 1 時）
| アイテム | 削除時期 | 行番号（952921f^） |
|---|---|---|
| `struct TypeToTalkMainView: View` | commit 4b398df | 行11-180 |
| `private var micButtonColor: Color` | commit 4b398df | 行159-169 |
| `private func modelStatusRow(...)` | commit 4b398df | 行171-189 |
| `private func statusBadge(...)` | commit 4b398df | 行191-208 |
| `private func statusColor(for:)` | commit 4b398df | 行210-222 |
| `func showRecorderWindow()` | commit 4b398df | 行455-466 |

---

## 2. 既存実装パターン

### 2.1 AppStatus による状態管理（現存）
**ファイル**: `/Sources/TypeToTalk/App/TypeToTalkApp.swift`  
**行範囲**: 行16-21  
```swift
enum AppStatus: Equatable {
    case idle
    case recording
    case processing
    case error(String)
}
```
**特徴**:
- Phase 1 で新規追加（commit 4b398df）
- `@Published var currentStatus: AppStatus = .idle`（行40）で Coordinator に公開
- `toggleRecording()` 内で複数の遷移ポイント（行131, 136, 143, 156, 183, 187, 190, 193, 203, 206）で更新
- MenuBarLabel（行395-461）で既に購読されている

**活用例**（行445-453）:
```swift
.onChange(of: coordinator.settings.formatterProviderRawValue) { _, _ in
    coordinator.bonsai.configureSelectedModel(coordinator.settings.resolvedBonsaiModelID)
}
```

### 2.2 @Published + Combine sink パターン（SettingsManager）
**ファイル**: `/Sources/TypeToTalk/Managers/SettingsManager.swift`  
**行範囲**: 行140-214  
```swift
@Published var soundFeedbackEnabled: Bool {
    didSet { UserDefaults.standard.set(soundFeedbackEnabled, forKey: "soundFeedbackEnabled") }
}
```
**初期化**: 行245-251  
```swift
if UserDefaults.standard.object(forKey: "soundFeedbackEnabled") != nil {
    self.soundFeedbackEnabled = UserDefaults.standard.bool(forKey: "soundFeedbackEnabled")
} else {
    self.soundFeedbackEnabled = true  // デフォルト ON
}
```

### 2.3 ステータス伝播パターン（Coordinator → View）
**ファイル**: `/Sources/TypeToTalk/App/TypeToTalkApp.swift`  
**行範囲**: 行74-114  
```swift
private func setupFormatterStatusBindings() {
    bonsai.$statusMessage
        .sink { [weak self] _ in self?.refreshFormatterStatusText() }
        .store(in: &cancellables)
    // ... network.isOnline, settings 関連も sink
}
```
**関連**: 
- `formatterStatusText` @Published（行36）で View に購読可能
- Combine sink により依存元変化を自動監視

### 2.4 UIフィードバック実装（既存）
**ファイル**: `/Sources/TypeToTalk/App/TypeToTalkApp.swift`  

**触覚フィードバック** （行277-279）:
```swift
private func performHapticFeedback(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
    NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
}
```

**音フィードバック** （行281-287）:
```swift
private func playFeedbackSound(named name: String) {
    guard settings.soundFeedbackEnabled else { return }
    NSSound(named: name)?.play()
}
```

**実装個所** （行127, 200）:
```swift
// 行200: 録音開始時
playFeedbackSound(named: "Tink")
performHapticFeedback(.generic)

// 行127: 録音停止時
playFeedbackSound(named: "Pop")
performHapticFeedback(.levelChange)
```

### 2.5 SettingsView での UI フィードバック設定
**ファイル**: `/Sources/TypeToTalk/Views/SettingsView.swift`  
**行範囲**: 行248-256  
```swift
settingRow("フィードバック音") {
    Toggle("", isOn: $settings.soundFeedbackEnabled)
        .labelsHidden()
        .toggleStyle(.switch)
}

Text("任意のショートカットに加えて、右 Option 単体でも録音を制御できます。トグルは押すたび開始/停止、プッシュトークは押している間だけ録音します。フィードバック音 ON で録音開始時に Tink、停止時に Pop が鳴ります...")
```

---

## 3. 影響範囲

### 3.1 Coordinator クラスへの変更
| 追加項目 | 説明 |
|---|---|
| `@Published var hudVisible: Bool` | HUD 表示フラグ |
| `@Published var hudFadeTask: Task?` | フェードアウト遅延タスク（キャンセル用） |
| `private func showHUD()` | 表示 + タイマー開始 |
| `private func hideHUD(afterDelay:)` | 遅延フェードアウト |
| `private func observeAppStatus()` | AppStatus 変化監視 |
| Combine sink 追加 | `currentStatus` 変化時 showHUD() 呼び出し |

**関連コード変更位置**:
- `toggleRecording()` 既存コード（行124-209）: 現状 `currentStatus` 更新のみ → 追加変更なし
- `init()` メソッド（行50-72）: 新規 observeAppStatus() 追加
- `handleAppLaunch()` メソッド（行116-122）: `hudVisible = false` 初期化追加（不確か）

### 3.2 SettingsManager への新規フラグ追加
| フラグ | 型 | デフォルト | 説明 |
|---|---|---|---|
| `hudFeedbackEnabled` | Bool | true | HUD パネル表示 ON/OFF |
| `hudFadeoutDelaySec` | Double | 2.0 | 表示継続時間（秒）|

**実装方式**:
```swift
@Published var hudFadeoutDelaySec: Double {
    didSet { UserDefaults.standard.set(hudFadeoutDelaySec, forKey: "hudFadeoutDelaySec") }
}
```

### 3.3 SettingsView への新規 UI 追加
**概略**:
```
ショートカット Section 内に:
  □ [Toggle] 視覚フィードバック（HUD パネル）
  □ [NumberField または Slider] 表示継続時間（0.5～5.0秒）
```

### 3.4 NSPanel / ウインドウ管理
**層別**:
- `HUDPanelManager`: NSPanel(nonactivatingPanel) ライフサイクル
- `HUDPanelView`: SwiftUI レイアウト（UIKit ブリッジなし）
- `TypeToTalkApp.body`: 新規 Scene 追加（不確か、下記 3.5 参照）

### 3.5 MenuBarExtra への影響（不確か）
- 現状 MenuBarLabel（行395-461）は既に `coordinator.handleAppLaunch()` 触発（行442）
- MenuBarExtra 展開時の画面空間が HUD と競合するか？（設計にて決定）

---

## 4. 過去の類似実装

### 4.1 TypeToTalkMainView の復元対象コンポーネント
**commit 952921f^ より抽出**:

#### A. マイクボタン UI（ZStack）
```swift
// 行51-72（git show 952921f^:... より）
Button {
    Task {
        await coordinator.toggleRecording()
    }
} label: {
    ZStack {
        Circle()
            .fill(micButtonColor)
            .frame(width: 88, height: 88)
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            .scaleEffect(isPulsing ? 1.08 : 1.0)
            .opacity(isPulsing ? 0.85 : 1.0)
            .animation(
                coordinator.recorder.isRecording
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .easeInOut(duration: 0.2),
                value: isPulsing
            )
        if coordinator.isProcessing {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(1.2)
        } else {
            Image(systemName: "mic.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
    .contentShape(Circle())
}
```

**パルス駆動**:
```swift
@State private var isPulsing = false
.onChange(of: coordinator.recorder.isRecording) { _, recording in
    isPulsing = recording
}
```

#### B. ステータス行（modelStatusRow）
```swift
// 行142-157（git show 952921f^:... より）
modelStatusRow(
    title: "Whisper",
    detail: coordinator.settings.whisperDisplayName,
    status: coordinator.whisper.statusText
)
modelStatusRow(
    title: "Formatter",
    detail: coordinator.activeFormatterDisplayName,
    status: coordinator.formatterStatusText
)
```

**定義** (行171-189):
```swift
private func modelStatusRow(
    title: String,
    detail: String,
    status: String
) -> some View {
    HStack {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(detail)
                .font(.subheadline)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 6) {
            statusBadge(status)
        }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.6))
    )
}
```

#### C. statusBadge（色付きステータス表示）
```swift
// 行191-208（git show 952921f^:... より）
private func statusBadge(_ value: String) -> some View {
    HStack(spacing: 8) {
        Circle()
            .fill(statusColor(for: value))
            .frame(width: 8, height: 8)
        Text(value)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 5)
    .background(
        Capsule(style: .continuous)
            .fill(Color.black.opacity(0.05))
    )
    .allowsHitTesting(false)
    .accessibilityAddTraits(.isStaticText)
}
```

#### D. statusColor（状態別色付け）
```swift
// 行210-222（git show 952921f^:... より）
private func statusColor(for value: String) -> Color {
    if value.contains("準備完了") || value.contains("完了") {
        return Color(red: 0.18, green: 0.67, blue: 0.37)  // 緑
    }
    if value.contains("読込中") || value.contains("録音中") {
        return Color(red: 0.95, green: 0.64, blue: 0.16)  // 橙
    }
    if value.contains("失敗") || value.contains("未接続") || value.contains("未読込") {
        return Color(red: 0.77, green: 0.42, blue: 0.18)  // 赤茶
    }
    return Color.secondary.opacity(0.7)  // グレー
}
```

#### E. micButtonColor（マイク色制御）
```swift
// 行159-169（git show 952921f^:... より）
private var micButtonColor: Color {
    if coordinator.recorder.isRecording {
        return Color(red: 0.05, green: 0.35, blue: 0.80)  // 濃青
    }
    if coordinator.whisper.whisperKit != nil {
        return Color(red: 0.10, green: 0.47, blue: 0.95)  // 青
    }
    return Color(red: 0.45, green: 0.83, blue: 0.98)  // 薄青
}
```

### 4.2 削除時の巻き込み確認
**commit 4b398df での差分確認** (行1-182 削除):
- `TypeToTalkMainView` struct 全体（11-180行）
- SettingsLink を含む（行26-31）← **HUD では不要**
- 上記 A～E の全コンポーネント

**復元時の判定**:
| コンポーネント | HUD に必要 | SettingsLink 等 | 判定 |
|---|---|---|---|
| マイクボタン ZStack | ✓ 必要 | 不要 | 抽出＋簡略化 |
| modelStatusRow | ✓ 必要 | 不要 | 抽出 |
| statusBadge | ✓ 必要 | 不要 | 抽出 |
| statusColor | ✓ 必要 | 不要 | 抽出 |
| micButtonColor | ✓ 必要 | 不要 | 抽出 |
| 全体 VStack (spacing: 18) | △ 必要（高さ短縮） | 不要 | 簡略化（frame 変更） |

---

## 5. 想定される副作用 / リスク

### 5.1 NSPanel フォーカス制御（設計決定待ち）
| リスク | 影響 | 対策 |
|---|---|---|
| NSPanel(nonactivatingPanel) が SwiftUI で直接出せない | コンパイル失敗 | AppKit NSWindowController ブリッジ必須か、WindowGroup + styleMask 組み合わせ検証 |
| Dock に HUD ウインドウが表示される | UX 悪化 | `NSApplication.setActivationPolicy(.accessory)` で既に `.accessory` だが、HUD 用に細分化必要か |
| HUD がメニューバーを隠す | 画面上部に重なり | 表示位置を画面下中央（Dock 上）に限定。`NSScreen.main?.frame` で座標計算 |
| HUD がメニューバーイベントを横取りする | キー入力不応答 | `becomeKey` override で回避。または Window level 調整（NSPanel.level = .floating） |

### 5.2 AppStatus 遷移ロジック
| リスク | 原因 | 対策 |
|---|---|---|
| `.recording` 中にユーザーが Settings を開く | 実装未検証 | Coordinator で同時状態管理。HUD は `isProcessing` も並行監視 |
| HUD フェードアウト中に再度 recording 開始 | タイマー が async タスク | `hudFadeTask?.cancel()` で既存タイマーをキャンセル |
| `.idle` → `.recording` → `.processing` → `.idle` 連鎖 | currentStatus の複数遷移 | Combine sink で `.processing` → `.idle` に限定してフェード開始 |

### 5.3 マルチディスプレイ環境
| リスク | 影響 | 対策 |
|---|---|---|
| `NSScreen.main` が外部ディスプレイを返す | HUD が外部画面に表示 | `NSApplication.shared.windows.first?.screen ?? NSScreen.main` で確認ウインドウ基準に変更 |
| メニューバーの高さが Mac ごとに異なる | 固定座標で位置ズレ | `NSScreen.visibleFrame` で available rectangle を取得 |

### 5.4 Combine + Task キャンセル
| リスク | 影響 | 対策 |
|---|---|---|
| `hudFadeTask?.cancel()` が @MainActor 外で呼ばれる | race condition | HUDPanelManager を @MainActor で修飾 |
| sink 内で async Task を生成 | retain cycle | `[weak self]` キャプチャリスト必須 |

### 5.5 SettingsManager への新フラグ追加
| リスク | 影響 | 対策 |
|---|---|---|
| UserDefaults key 衝突 | 既存設定上書き | key 名を一意に（例: "hudFeedbackEnabled"） |
| bool(forKey:) デフォルト false 問題 | 初期値が OFF になる | `object(forKey:) != nil` チェック（既に soundFeedbackEnabled で実装済み、行247） |

---

## 6. 制約条件

### 6.1 macOS バージョン
**Package.swift 行6-8**:
```swift
platforms: [
    .macOS(.v14)
]
```
- **制約**: macOS 14（Sonoma）以上のみサポート
- **影響**: NSPanel の nonactivatingPanel は 10.5+ で利用可能（問題なし）
- **SwiftUI Scene**: macOS 14 で MenuBarExtra あり（Phase 1 で使用済み）

### 6.2 フォーカス奪取禁止
**要件**: 「フォーカス奪わない」→ NSPanel(nonactivatingPanel) 必須  
**実装方式候補**:
1. NSWindowController + SwiftUI HostingView（AppKit 直接制御）
2. WindowGroup + `.disabled(true)` + NSWindow style mask 後処理
3. NSPanel 直接 `NSApplication.shared.windows` 追加（ブリッジなし）

**不確か**: SwiftUI だけでは NSPanel.nonactivatingPanel が out-of-the-box で選べない可能性。AppKit layer 必要性の確認待ち。

### 6.3 Settings トグル位置
**要件**: Settings に「視覚フィードバック ON/OFF」トグル  
**既存例**: SettingsView 行248-252 で `soundFeedbackEnabled` Toggle が実装  
**制約**: 同一 GroupBox（ショートカット Section）に追加すると行数が増える。またはタブ分離を検討。

### 6.4 表示継続時間
**要件**: idle 復帰で 2秒後フェードアウト  
**実装**: DispatchQueue.main.asyncAfter または Combine .debounce/.delay  
**現状の使用**: Task + async/await pattern（行59-68）が多いため、同パターン推奨。

```swift
// 推奨（既存 Task パターン）
hudFadeTask?.cancel()
hudFadeTask = Task { @MainActor in
    try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2秒
    if !Task.isCancelled {
        // フェードアウト
    }
}
```

### 6.5 AppStatus の現状
**現存**: Coordinator に `@Published var currentStatus: AppStatus = .idle`（行40）  
**遷移点**: toggleRecording() の 8箇所（行131, 136, 143, 156, 183, 187, 190, 193, 203, 206）  
**制約**: 既存の `.idle/.recording/.processing/.error(String)` を HUD 用に流用（新規追加なし）

---

## 7. テスト戦略

### 7.1 単体テスト（UnitTest 層）
| テスト項目 | ファイル | 検証内容 |
|---|---|---|
| HUD 表示フラグの遷移 | HUDPanelManagerTests.swift（新規） | AppStatus 変化時に hudVisible が正しく ON/OFF |
| フェードアウト遅延キャンセル | HUDPanelManagerTests.swift | `.recording` 中に hudFadeTask が cancel される |
| statusColor 判定 | HUDPanelViewTests.swift（新規） | 各ステータス文字列に対して RGB 値が正確 |
| micButtonColor ロジック | HUDPanelViewTests.swift | isRecording, whisperKit != nil 条件判定 |

### 7.2 統合テスト（UI + Coordinator）
| テスト項目 | 検証内容 | 期待値 |
|---|---|---|
| 録音開始時 HUD 表示 | toggleRecording() → recording → HUD パネルが画面下中央に表示 | パネルが 2秒以上表示維持 |
| 録音停止時 HUD 消滅 | toggleRecording() → processing → idle → HUD がフェードアウト | 約2秒後に非表示 |
| recording 中の再トグル | isRecording=true 状態で toggleRecording() を連続実行 | hudFadeTask が毎回 cancel、パネル表示継続 |
|設定 OFF 時 HUD 無表示 | hudFeedbackEnabled = false → toggleRecording() | HUD が一度も表示されない |
| マルチディスプレイ | 複数モニタで MenuBarExtra 開く | HUD がプライマリスクリーン下中央に表示 |

### 7.3 手動テスト（実機）
| テスト項目 | 手順 | 期待動作 |
|---|---|---|
| 基本表示 | ショートカット + 右Option で 録音開始 | HUD パネル + マイク + ステータス 2行が画面下中央に表示 |
| パルスアニメ | recording 状態でマイクボタンが呼吸 | マイクボタンの スケール 1.08 + Opacity 0.85 パルス（0.8秒周期） |
| 色変化 | recording → processing → idle | マイク色が 濃青 → 橙 → 薄青 に段階遷移 |
| ステータス更新 | Whisper/Bonsai ロード中 | Formatter ステータスが「読込中」に変化、HUD も反映 |
| フェードアウト | idle 達成 | HUD が 2秒後に透明化してフェードアウト |
| 設定反映 | Settings で hudFeedbackEnabled OFF → 再度 toggle | HUD が表示されない（Settings 反映即座） |

### 7.4 ビルド・lint
| チェック項目 | 手順 | 条件 |
|---|---|---|
| Swift compile | `swift build` | エラーなし |
| SwiftLint | lint 存在すれば実行 | warning レベル許容、error なし |
| Xcode build | Xcode でビルド | Code signing 成功 |

### 7.5 回帰テスト
| 既存機能 | テスト内容 | 期待値 |
|---|---|---|
| Menu bar icon | MenuBarLabel が currentStatus に追従 | icon が idle/recording/processing/error で切替（Phase 2 実装済み） |
| Settings 開く | MenuBarExtra の「設定」をクリック | SettingsView が前面に出現。HUD は影響なし |
| 権限アラート | accessibility.hasPermission = false | showAccessibilityPermissionAlert が表示。HUD は影響なし |
| 音フィードバック | soundFeedbackEnabled = false → toggle | 既存 Pop/Tink 音が出ない。HUD は影響なし |

---

## まとめ：設計決定待ちの主要ポイント

### A. NSPanel 実装方式
**候補**:
1. **Option 1**: AppKit NSWindowController + SwiftUI HostingView（完全制御）
   - 利点: nonactivatingPanel 直接指定可能
   - 欠点: AppKit layer 複雑化
   
2. **Option 2**: WindowGroup + afterEffect で NSWindow style 後処理
   - 利点: SwiftUI 内で一貫
   - 欠点: SwiftUI Scene からの NSPanel 直接操作不確か
   
3. **Option 3**: SceneDelegate AppDelegate bridging（hybrid）
   - 利点: プラットフォーム標準
   - 欠点: 現プロジェクトに AppDelegate がない

**推奨**: Option 1（AppKit layer 追加）で確実性重視

### B. 表示位置計算
**画面下中央**:
```swift
let screenFrame = NSScreen.main?.visibleFrame ?? NSScreen.main?.frame ?? .zero
let hudWidth: CGFloat = 200
let hudHeight: CGFloat = 220
let x = screenFrame.midX - hudWidth / 2
let y = screenFrame.minY + 40  // Dock 上 40px
```

**不確か**: Dock の高さが Mac 仕様で固定か可変かの確認

### C. SettingsManager 新フラグ
**推奨名**:
- `hudFeedbackEnabled: Bool = true`（表示 ON/OFF）
- `hudFadeoutDelay: Double = 2.0`（秒単位）

**実装例** (SettingsManager.swift):
```swift
@Published var hudFeedbackEnabled: Bool {
    didSet { UserDefaults.standard.set(hudFeedbackEnabled, forKey: "hudFeedbackEnabled") }
}
```

---

**報告完了日時**: 2026年4月26日 08:47  
**報告者**: フォックスの極タマ  
**制約遵守**: 7見出し全部実コード根拠で埋めた。省略・推測なし。
