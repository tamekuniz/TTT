# TypeToTalk メニューバー常駐型 Phase 2 調査報告書
## アイコン動的切替・エラー表示・権限誘導の実装設計

**調査者**: マンゴー調査小人ですぞ  
**調査日**: 2026-04-25  
**バージョン**: 0.1.0 (ビルド 20260425G)  
**対象環境**: macOS 14.0+, SwiftUI, Swift 6.0  
**Phase 状態**: Phase 1 完了（AppStatus enum・currentStatus 実装済み、MenuBarLabel アイコン静的表示）

---

## 1. 関連ファイル一覧

### A. コアアプリケーションファイル
- **TypeToTalkApp.swift** (`/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`)
  - 行11-21: `enum AppStatus: Equatable { case idle, recording, processing, error(String) }` ← Phase 2 で着色判定に使う
  - 行40: `@Published var currentStatus: AppStatus = .idle` ← MenuBarLabel が購読する
  - 行124-207: `func toggleRecording()` ← AppStatus を130行・135行・142行・155行・186行・189行・192行・201行・204行で更新
  - 行385-413: `struct MenuBarLabel: View` ← Phase 2 で body の Image を条件分岐させる
  - 行426-449: `@main struct TypeToTalkApp: App` - MenuBarExtra（行426）、label（行435）、menuBarExtraStyle(.menu)（行437）

### B. マネージャー系
- **AccessibilityManager.swift** (`/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/AccessibilityManager.swift`)
  - 行13: `@Published var hasPermission = false` ← 権限状態の @Published
  - 行20-22: `func refreshPermissionStatus()` ← hasPermission 更新メソッド
  - 行29-34: `func openAccessibilitySettings()` ← システム設定起動（Phase 2 で menu から呼び出す可能性）

### C. Settings UI
- **SettingsView.swift** (`/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Views/SettingsView.swift`)
  - 行269-276: 権限表示ユーザーインターフェース（Circle の color 着色、許可済/未許可表示）
  - 行280-287: 「システム設定を開く」ボタンと `accessibility.openAccessibilitySettings()` 呼び出し
  - 行8: `@ObservedObject var accessibility: AccessibilityManager` ← coordinator.accessibility を観察

### D. プロジェクト設定
- **project.yml** (`/Users/tamekuniz/GitHub/tamekuniz/TTT/project.yml`)
  - 行4-5: `macOS: "14.0"` ← デプロイメントターゲット
  - 行17: `MACOSX_DEPLOYMENT_TARGET: "14.0"` ← 確認

---

## 2. 既存実装パターン（実コード根拠付き）

### A. AppStatus enum と currentStatus の定義

**TypeToTalkApp.swift, 行16-21**
```swift
enum AppStatus: Equatable {
    case idle              // アプリ起動直後・テキスト入力完了
    case recording         // 音声録音中
    case processing        // Whisper + AI 成形処理中
    case error(String)     // エラー発生（引数に詳細メッセージ）
}
```

**TypeToTalkApp.swift, 行40**
```swift
@Published var currentStatus: AppStatus = .idle
```

**結論**: 
- AppStatus は4つの明確な状態を持つ（error は associated value で詳細情報を保持）
- `@Published` のため、MenuBarLabel が `@ObservedObject` で購読可能

---

### B. currentStatus の更新フロー

**TypeToTalkApp.swift, toggleRecording メソッド内の更新箇所**

| 行番号 | コンテキスト | 更新内容 |
|--------|-----------|---------|
| 130 | 停止ボタン → 処理開始 | `currentStatus = .processing` |
| 135 | 録音ファイル存在チェック失敗 | `currentStatus = .error("録音ファイルが見つかりません")` |
| 142 | Whisper モデル未読込チェック失敗 | `currentStatus = .error("聞き取りモデル未読込")` |
| 155 | Whisper 文字起こし失敗 | `currentStatus = .error("文字起こし失敗")` |
| 182 | insertText 成功 | `currentStatus = .idle` |
| 186 | insertText → アクセシビリティ権限なし | `currentStatus = .error("アクセシビリティ権限なし")` |
| 189 | insertText → 入力先がない | `currentStatus = .error("入力先なし")` |
| 192 | insertText → 書込不可 | `currentStatus = .error("書込不可")` |
| 201 | startRecording 成功 | `currentStatus = .recording` |
| 204 | startRecording 例外キャッチ | `currentStatus = .error("録音エラー")` |

**結論**: 
- 10箇所で明確に更新される
- エラー系は 6 箇所（アクセシビリティ権限含む）
- リカバリフロー（idle への復帰）は成功時のみ（行182）

---

### C. AccessibilityManager の hasPermission と refreshPermissionStatus

**AccessibilityManager.swift, 行13**
```swift
@Published var hasPermission = false
```

**AccessibilityManager.swift, 行20-22**
```swift
func refreshPermissionStatus() {
    hasPermission = AXIsProcessTrusted()
}
```

**TypeToTalkApp.swift, MenuBarLabel 内での呼び出し（行410）**
```swift
.onChange(of: scenePhase) { _, newPhase in
    // フォアグラウンド復帰時に権限状態を最新化（システム設定で変更後の反映）
    if newPhase == .active {
        coordinator.accessibility.refreshPermissionStatus()
    }
}
```

**結論**: 
- hasPermission は @Published のため MenuBarLabel から直接購読可能
- refreshPermissionStatus() は既に Phase 1 で scenePhase.active に連動
- Phase 2 では error 状態で権限を再確認し、UI に反映する仕組みが必要

---

### D. MenuBarLabel の現状定義

**TypeToTalkApp.swift, 行385-413**
```swift
struct MenuBarLabel: View {
    @ObservedObject var coordinator: TypeToTalkCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var didLaunch = false

    var body: some View {
        Image(systemName: "mic.circle")                    // ← Phase 1: 固定アイコン
            .onAppear {
                if !didLaunch {
                    didLaunch = true
                    coordinator.handleAppLaunch()
                }
            }
            .onChange(of: coordinator.settings.formatterProviderRawValue) { _, _ in
                coordinator.bonsai.configureSelectedModel(coordinator.settings.resolvedBonsaiModelID)
            }
            .onChange(of: coordinator.settings.bonsaiModelPresetRawValue) { _, _ in
                coordinator.bonsai.configureSelectedModel(coordinator.settings.resolvedBonsaiModelID)
            }
            .onChange(of: coordinator.settings.bonsaiCustomModelID) { _, _ in
                coordinator.bonsai.configureSelectedModel(coordinator.settings.resolvedBonsaiModelID)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    coordinator.accessibility.refreshPermissionStatus()
                }
            }
    }
}
```

**結論**: 
- body は単一の `Image(systemName: "mic.circle")`
- @ObservedObject で coordinator を購読可能
- Phase 2 では 行391 の Image 部分を条件分岐に置き換える
- 既存の onChange ハンドラはそのまま保持

---

### E. SF Symbol の使用パターン

**SettingsView.swift, 行270-272（権限インジケーター）**
```swift
Circle()
    .fill(accessibility.hasPermission ? Color.green : Color.red)
    .frame(width: 8, height: 8)
```

**TypeToTalkApp.swift, 行391（メニューバーアイコン）**
```swift
Image(systemName: "mic.circle")
```

**結論**: 
- SettingsView では Circle() + Color で着色（SF Symbol ではなく SwiftUI Shape）
- MenuBarLabel では `Image(systemName: ...)` で SF Symbol を使用
- SF Symbol への foregroundStyle 適用は Phase 2 で実装が必要

---

### F. MenuBarExtra と label の構文

**TypeToTalkApp.swift, 行426-437**
```swift
var body: some Scene {
    MenuBarExtra {
        SettingsLink {
            Text("設定...")
        }
        Divider()
        Button("TypeToTalk を終了") {
            NSApplication.shared.terminate(nil)
        }
    } label: {
        MenuBarLabel(coordinator: coordinator)
    }
    .menuBarExtraStyle(.menu)
```

**結論**: 
- MenuBarExtra の label パラメータは任意の View を受け取る（現在は MenuBarLabel View）
- label 内は単純な Image から HStack・VStack へも置き換え可能
- .menuBarExtraStyle(.menu) は fixed スタイル

---

## 3. 影響範囲（Phase 2 が触る範囲、既存機能への影響）

### A. Phase 2 実装が確実に触る領域

| ファイル | 行番号 | 変更内容 | 既存機能への影響 |
|---------|--------|---------|-----------------|
| MenuBarLabel.swift (新規 or 既存) | 391 | Image(systemName: ...) を条件分岐に置き換え | 新しい switch 文で AppStatus に応じたアイコン表示に置き換え |
| MenuBarLabel.swift | 391+ | .foregroundStyle(.red) 等を追加 | メニューバーアイコンの色が動的に変わる |
| MenuBarLabel.swift | 391+ | エラーメッセージ表示（Tooltip or Menu item） | ユーザーが error 状態を視認可能に |
| TypeToTalkApp.swift (Menu部分) | 426-436 | 「アクセシビリティ権限なし」エラーの誘導メニュー項目追加 | SettingsView 開かずに直接権限申請できる利便性向上 |

### B. 既存機能への影響チェック

**toggleRecording() メソッド**: 
- currentStatus 更新は既に 10 箇所で存在（行130, 135, 142, 155, 182, 186, 189, 192, 201, 204）
- Phase 2 ではこれらを **削除しない**（そのまま活用）
- 影響: なし

**AccessibilityManager**: 
- hasPermission、refreshPermissionStatus は既に @Published
- Phase 2 では MenuBarLabel から @Published hasPermission を購読
- 影響: なし（既存機能の拡張）

**MenuBarExtra / SettingsLink**: 
- 現在のメニュー構造（SettingsLink + Divider + 終了ボタン）は保持
- Phase 2 ではメニュー項目追加（権限誘導）の可能性あり
- 影響: メニュー項目数が増加する（UI 再配置）

---

## 4. 過去の類似実装（git log から抽出）

**Commit: 4b398df - [フォK] feat: メニューバー常駐型に全面移行 (Phase 1)**

```
Author: tamekuniz <tamekuniz@gmail.com>
Date:   Sat Apr 25 22:53:17 2026 +0900

    [フォK] feat: メニューバー常駐型に全面移行 (Phase 1)
    
    - setActivationPolicy(.accessory) で Dock から消える
    - WindowGroup と TypeToTalkMainView を廃止し MenuBarExtra に置換
    - メニュー: SettingsLink「設定...」+ Divider + 「TypeToTalk を終了」
    - MenuBarLabel View を新設、onAppear で handleAppLaunch を1回だけ起動
    - showRecorderWindow() メソッドと呼び出し2箇所を削除
    - NSApp.activate(ignoringOtherApps:) を全箇所削除（フォーカス奪取の根絶）
    - AppStatus enum と @Published currentStatus を Coordinator に追加
      （Phase 1 では更新のみ、Phase 2 で MenuBarExtra アイコン動的切替に活用）
    - 既存 onChange ハンドラ群（formatter / scenePhase 等）を MenuBarLabel へ移植
```

**影響**: 
- MenuBarLabel の概念設計は既に Phase 1 の commit msg で phase 2 への展望を明記している
- AppStatus enum の追加も「Phase 2 で MenuBarExtra アイコン動的切替に活用」を想定した設計
- 過去の icon/menu 関連変更は存在せず（WindowGroup → MenuBarExtra への大規模リプレイスのみ）

---

## 5. 想定される副作用 / リスク（実装前チェック項目）

### A. MenuBarExtra label の複合レイアウト表現（リスク中）

**疑問点**: MenuBarExtra の label が Text + Image + Spacer の HStack を受け入れるか

**根拠**:
- Apple 公式ドキュメント: MenuBarExtra は label: パラメータに任意の View を受け取る
- SwiftUI の View プロトコルでは HStack, VStack, ZStack も View に適合
- 実装予定: `HStack { Image(...); Text(...) }` で状態表示とアイコンを並べるケース

**リスク**: 
- メニューバースペースの制約（macOS では横幅制限がきつい）
- アイコン＋テキストで幅が超過した場合、テキストが切り詰められる可能性
- **テスト必須**: 実装後に macOS 14.0 実機で幅を確認

**対策**: 
- Phase 2 では当初アイコンのみの色変更、エラーテキストはメニューアイテムで表示
- メニュー内に詳細エラーメッセージを置く（メニューバーアイコン自体は最小限）

---

### B. SF Symbol の色付け（`.foregroundStyle()` vs template mode）（リスク中）

**疑問点**: MenuBarExtra の label 内で Image に `.foregroundStyle(.red)` を適用すると、メニューバーのテンプレートレンダリングに上書きされるか

**根拠（実装パターン）**:
- macOS のメニューバーアイコンはデフォルトで **template mode** で描画される
- template mode 下では色情報が破棄され、システムの前景色（通常は黒または白）で統一表示
- SwiftUI の `.foregroundStyle(.red)` が template mode を上書きできるかは **不確か**

**リスク**: 
- color assignment が無視される可能性
- PhaseGate: テスト実装が必須

**対策**:
1. まずアイコン部分を switch statement で異なる symbol に置き換える（色ではなく形状で区別）
   - idle: `"mic.circle"` (既存)
   - recording: `"mic.circle.fill"`（塗りつぶし）
   - processing: `"clock.circle"`（別シンボル）
   - error: `"exclamationmark.circle.fill"` or `"mic.circle.slash"`
2. 次に `.foregroundStyle()` 試験（実機で色付きの symbol が表示されるか確認）

---

### C. symbolEffect / symbolRenderingMode の macOS 14 サポート（リスク低）

**疑問点**: SF Symbol 5+ の `.symbolEffect(.pulse)` や `.symbolRenderingMode(.multicolor)` が macOS 14.0 で動作するか

**根拠**:
- Apple ドキュメント: symbolEffect は macOS 14+ で利用可能（iOS 17.1+）
- symbolRenderingMode（.multicolor など）は macOS 14+ で実装

**リスク**: 低（ドキュメント上では対応）

**ただし不確か な点**:
- MenuBarExtra の label 内で symbolEffect がレンダリングされるか（メニューバースペースの制限下）
- パフォーマンスへの影響（メニューバーは常時表示で refresh 頻度が高い）

**対策**: 
- Phase 2 初期実装では symbolEffect なし（単純な symbol 置き換え）
- Phase 2.1 以降で pulse アニメーション検討

---

### D. @ObservedObject と @Published の reactivity（リスク低）

**疑問点**: MenuBarLabel で `@ObservedObject var coordinator` を購読し、`coordinator.currentStatus` の変化が View 再評価をトリガするか

**根拠**:
- SwiftUI @ObservedObject: 任意の ObservableObject の @Published プロパティ変化で自動再評価
- coordinator は `@MainActor class` + `@Published var currentStatus`
- MenuBarLabel は `@ObservedObject var coordinator`

**リスク**: 低（SwiftUI の標準パターン）

**テスト**: 
- toggleRecording() → currentStatus 更新 → MenuBarLabel body 再評価
- アイコン表示切り替わり確認

---

## 6. 制約条件（platform / dependency 限定事項）

### A. macOS 14+ MenuBarExtra の label 表現の制約

**制約 1: MenuBarExtra label is a View**
```swift
// MenuBarExtra { ... } label: { <-- View を期待
    MenuBarLabel(coordinator: coordinator)
}
```
- label は任意の View プロトコル実装を受け入れる（テキスト、画像、スタック可能）
- ただし macOS メニューバーの物理的スペース制限で幅 ~30-40px が実用範囲

**制約 2: Template mode 下での色表現**
- macOS システムメニューバーでは template mode がデフォルト
- Image(systemName:) は template mode で描画される
- 色付けしたければ `.symbolRenderingMode(.multicolor)` or `.foregroundStyle()` で明示的に override（動作確認未）

**制約 3: scenePhase / onAppear / onChange の組み合わせ**
- MenuBarLabel の onAppear は `didLaunch` フラグで一度限りの実行を保証
- scenePhase は手動で refreshPermissionStatus を呼び出し（Phase 1 から既に実装）
- 追加の scenePhase binding は不要

**制約 4: SettingsLink との共存**
- MenuBarExtra のコンテキストメニューに SettingsLink を置く（既に実装）
- Settings シーン（独立ウインドウ）が立ち上がる
- Phase 2 で権限誘導メニュー項目を追加する際、SettingsLink とは別 action を定義

---

### B. SF Symbol 5+ のアニメーション（macOS 14 対応確認）

**現在のデプロイメントターゲット**:
```yaml
# project.yml 行4-5
deploymentTarget:
  macOS: "14.0"
```

**SF Symbol 機能の OS 対応**:
| 機能 | macOS 14 | 状態 |
|------|----------|------|
| SF Symbols 5 基本アイコン | ✅ | 利用可能 |
| `.symbolEffect(.pulse)` | ✅ | 利用可能（ドキュメント記載） |
| `.symbolRenderingMode(.multicolor)` | ✅ | 利用可能 |
| `.foregroundStyle()` (SwiftUI) | ✅ | 利用可能 |

**不確か な点**:
- MenuBarExtra の label（極小スペース）での symbol animation のレンダリング品質
- scenePhase.active で refreshPermissionStatus を何度も呼ぶ際の symbol update パフォーマンス

---

## 7. テスト戦略（実機目視確認シナリオ）

### フェーズ A: アイコン表示確認（単純置き換え版）

**テストシナリオ 1: アプリ起動時 idle アイコン**
```
1. TypeToTalk アプリを起動
2. メニューバーに `Image(systemName: "mic.circle")` が表示される
3. ログに「currentStatus = .idle」を確認
期待結果: アイコンが表示され、黒色（デフォルトテンプレート色）
実装内容: MenuBarLabel の body で coordinator.currentStatus が .idle なら mic.circle
```

**テストシナリオ 2: ショートカット押下 → recording アイコン**
```
1. テスト 1 の状態から、設定したショートカット（例: Cmd+Shift+R）を押す
2. メニューバーアイコンが「mic.circle.fill」に変わる
3. ログに「currentStatus = .recording」を確認
期待結果: アイコン形状が変わる、メニューバーアイコンが更新される
実装内容: MenuBarLabel で coordinator.currentStatus が .recording なら mic.circle.fill
```

**テストシナリオ 3: 停止 → processing アイコン**
```
1. テスト 2 の「mic.circle.fill」状態から、同じショートカット（例: Cmd+Shift+R）をもう一度押す
2. メニューバーアイコンが「clock.circle」に変わる（processing を示す）
3. ログに「currentStatus = .processing」を確認
4. Whisper + AI 処理の進捗に応じてアイコンは clock.circle のまま
期待結果: アイコン形状が clock.circle に変わり、その後 idle に戻る
実装内容: MenuBarLabel で coordinator.currentStatus が .processing なら clock.circle
```

**テストシナリオ 4: idle への復帰**
```
1. テスト 3 の processing 状態から約5-10秒待機
2. insertText 成功ログ「完了」を確認
3. メニューバーアイコンが元の「mic.circle」に戻る
4. ログに「currentStatus = .idle」を確認
期待結果: アイコンが初期状態に戻る
実装内容: MenuBarLabel で coordinator.currentStatus が .idle なら mic.circle
```

---

### フェーズ B: エラー状態とアイコン表示

**テストシナリオ 5: アクセシビリティ権限エラー → 警告アイコン**
```
1. システム設定 → プライバシーとセキュリティ → アクセシビリティ から TypeToTalk をチェック解除
2. アプリを再起動（permissions キャッシュ反映）
3. メニューバーショートカットを押下
4. テキスト入力時に insertText が missingPermission を返す
5. メニューバーアイコンが「exclamationmark.circle.fill」に変わる
6. ログに「currentStatus = .error("アクセシビリティ権限なし")」を確認
期待結果: エラーアイコン表示、ユーザーが権限問題を視認可能
実装内容: MenuBarLabel で coordinator.currentStatus が .error(...) なら exclamationmark.circle.fill + 赤色（可能なら）
```

**テストシナリオ 6: エラーメニュー項目の表示**
```
1. テスト 5 のエラー状態から、メニューバーアイコンをクリック
2. コンテキストメニューが展開
3. 「システム設定を開く」メニュー項目が表示される（新規追加）
4. メニュー項目をクリック → システム設定の「アクセシビリティ」セクションが開く
期待結果: ユーザーが直接権限設定へナビゲート可能
実装内容: MenuBarExtra のメニュー本体に「システム設定を開く」ボタン追加
```

**テストシナリオ 7: 権限を再有効化した後の自動リカバリ**
```
1. テスト 5 / 6 の状態から、システム設定で TypeToTalk にアクセシビリティ権限を付与
2. アプリのメニュー部分を軽くクリック（フォアグラウスに）
3. scenePhase.active が発火し refreshPermissionStatus() が呼ばれる
4. accessibility.hasPermission が true に更新
5. メニューバーアイコンが元の「mic.circle」に戻る
期待結果: 権限が復帰すると即座にアイコンが正常状態に戻る
実装内容: scenePhase binding で refreshPermissionStatus() が既に存在、MenuBarLabel 側で hasPermission → アイコン表示を反映
```

---

### フェーズ C: 複合エラーシナリオ

**テストシナリオ 8: Whisper モデル未読込エラー**
```
1. アプリ起動直後、Whisper モデルロード前にショートカットを押す
2. toggleRecording() が whisper.whisperKit != nil チェックで失敗
3. メニューバーアイコンが「exclamationmark.circle.fill」に変わる
4. ログに「currentStatus = .error("聞き取りモデル未読込")」を確認
期待結果: エラーアイコン表示、SettingsView で モデル再読込を促す動線
実装内容: MenuBarLabel の .error case で exclamationmark.circle.fill を表示
```

**テストシナリオ 9: 入力先なしエラー（フォーカスロスト）**
```
1. 正常に録音→文字起こし→AI 成形まで成功（.processing）
2. insertText() で入力先（フォーカス要素）が見つからない
3. メニューバーアイコンが「exclamationmark.circle.fill」に変わる
4. ログに「currentStatus = .error("入力先なし")」を確認
期待結果: エラーアイコン表示、ユーザーがテキスト入力先を確認して再トライ
実装内容: MenuBarLabel の .error case で表示
```

---

### フェーズ D: メニューアイコンの色付け試験（拡張版、Phase 2.1 以降の検討）

**テストシナリオ 10: .foregroundStyle(.red) の MenuBarExtra label への適用**
```
1. MenuBarLabel に .foregroundStyle(.red) を Image に追加（実験的）
2. アプリを起動、メニューバーアイコンを目視確認
期待結果（希望）: エラー状態時アイコンが赤色に表示
期待結果（代替）: template mode で色がシステムデフォルトに統一（色付け失敗）
実装内容: `.symbolRenderingMode(.multicolor)` を試す or symbol 形状の切り替えで対応
```

---

## まとめ表: Phase 2 実装の判定基準

| 判定項目 | 結論 | 根拠 |
|---------|------|------|
| **MenuBarLabel アイコン条件分岐** | ✅ 実装可能 | coordinator.currentStatus を @ObservedObject で購読、switch statement で symbol 置き換え |
| **エラー状態の視認性** | ✅ symbol 形状で可能 | "exclamationmark.circle.fill" など異なる symbol で区別（色付けは別検討） |
| **权限誘導（menu item追加）** | ✅ 実装可能 | accessibility.openAccessibilitySettings() の既存メソッド利用 |
| **SF Symbol アニメーション** | 📋 Phase 2.1 以降 | macOS 14 対応は O だが、メニューバースペース制約で実装検討が必要 |
| **アイコン色付け（.foregroundStyle）** | ❓ 要実機確認 | template mode 上書きの動作が不確か（実装後に評価） |
| **Phase 2 実装規模** | **中（2-3 営業日）** | MenuBarLabel 修正 + Menu item 追加 + テスト（実装コード目安 50-100 行） |

---

**調査終了**  
マンゴー調査小人ですぞ
