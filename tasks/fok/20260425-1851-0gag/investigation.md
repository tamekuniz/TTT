# TypeToTalk メインウインドウ タイトルバー実装調査レポート

**実施日**: 2026-04-25  
**調査者**: イチジク（福岡県産、調査員）  
**レベル**: Explore type, very thorough  
**方針**: 推測禁止、実コード確認のみ、path:line 番号で明示  

---

## 1. 関連ファイル一覧（パス + 役割）

| パス | 役割 | 重要度 |
|------|------|--------|
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift` | メイン画面（TypeToTalkMainView）、@main App struct、WindowGroup 定義、ウインドウ設定 | ★★★ |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Views/SettingsView.swift` | 設定画面（Settings scene）。独立したウインドウで表示 | ★★ |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Package.swift` | macOS デプロイメントターゲット v14 定義 | ★★ |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/project.yml` | Xcode プロジェクト設定、deploymentTarget macOS 14.0 | ★★ |

---

## 2. 既存実装パターン（命名・構造、SwiftUI WindowGroup / NSWindow 設定の現状）

### 2.1 メインアプリの構造（TypeToTalkApp.swift）

**ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`

#### @main App 定義（L500-548）

```swift
@main
struct TypeToTalkApp: App {
    @StateObject private var coordinator = TypeToTalkCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TypeToTalkMainView(coordinator: coordinator)
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    if let window = NSApplication.shared.windows.first {
                        window.identifier = NSUserInterfaceItemIdentifier("RecorderWindow")
                        window.titleVisibility = .hidden       // ← L513
                        window.titlebarAppearsTransparent = true // ← L514
                        window.isMovableByWindowBackground = true
                    }
                    coordinator.handleAppLaunch()
                }
                // ... onChange 修飾子省略
        }
        .windowStyle(.hiddenTitleBar)              // ← L535
        .windowResizability(.contentSize)          // ← L536
        
        Settings {
            SettingsView(...)
        }
    }
}
```

**現状**:
- `WindowGroup { TypeToTalkMainView(...) }` で主ウインドウを定義（L506-534）
- `.onAppear` コールバック内で NSWindow の設定を行う（L508-518）
  - `window.titleVisibility = .hidden` で タイトルバーの表示文字列を非表示
  - `window.titlebarAppearsTransparent = true` で タイトルバー領域そのものを透過させない（ただし表示文字列は hidden）
  - `window.isMovableByWindowBackground = true` で 背景をドラッグ可能にする
- `WindowGroup` に `.windowStyle(.hiddenTitleBar)` 修飾子を適用（L535）
- `windowResizability(.contentSize)` で コンテンツサイズに基づいてリサイズ（L536）

#### 主ビュー（TypeToTalkMainView）

**L10-185**: 
- VStack の トップレベルで HStack を配置（L16-40）
  - **L18**: `Text("TypeToTalk")` を `.font(.title3.weight(.semibold))` で配置
  - この Text が「独自のタイトル表示」である
  - L40: `.padding(.leading, 56)` で左寄せしている
- ボタン（マイクボタン）を ZStack で実装（L42-78）
  - ZStack は マイクアイコンとプログレスビューのレイヤリング用
  - ZStack 自体に特別な制約はない

**Z-stack の構造**（L47-71）:
```swift
ZStack {
    Circle()
        .fill(micButtonColor)
        .frame(width: 88, height: 88)
        .shadow(...)
        // ... アニメーション設定省略
    if coordinator.isProcessing {
        ProgressView()
    } else {
        Image(systemName: "mic.fill")
    }
}
.contentShape(Circle())
```
→ ZStack は「マイクボタンの視覚的レイアウト」用であり、タイトルバーとは無関係。

#### ウインドウサイズ設定

**L98**: `.frame(width: 360, height: 300)` でコンテンツの表示サイズを確定
- VStack 全体が 360x300 に制限される
- タイトルバー hidden でもこのサイズに影響なし（タイトルバーは領域の外）

### 2.2 NSWindow 設定の詳細

**titleVisibility と titlebarAppearsTransparent の組み合わせ**（L513-514）:

| 設定 | 効果 |
|------|------|
| `titleVisibility = .hidden` | タイトルテキスト（"TypeToTalk" など）を非表示にする。ただし タイトルバー領域自体は存在 |
| `titlebarAppearsTransparent = true` | タイトルバーを透過させる（背景が透ける）。通常 macOS は不透明なグレー背景 |

**現在の設定による状態**:
- タイトルバーのテキスト部分は hidden → 何も表示されない
- タイトルバー領域は transparent → ただし Settings 画面など他のウインドウでも同じ設定はない（Settings scene は別定義）

### 2.3 windowStyle 修飾子（L535）

```swift
.windowStyle(.hiddenTitleBar)
```

**効果**:
- SwiftUI 5.1+ 以降で利用可能
- macOS のウインドウデコレーション（タイトルバー）を完全に隠す
- L513 の `titleVisibility = .hidden` と重複する可能性がある

**優先度**: `.windowStyle()` 修飾子 > `.onAppear` での手動設定（通常）

---

## 3. 影響範囲（呼び出し側 / 依存。ZStack 削除がレイアウトに与える影響、ウインドウサイズや背景にどう波及するか）

### 3.1 現在の Text("TypeToTalk") の依存関係

**L18 の Text は以下の構造に埋め込まれている**:

```
VStack(spacing: 18)                    ← L15
  ├─ HStack(alignment: .top)           ← L16
  │   ├─ VStack(alignment: .leading)   ← L17
  │   │   ├─ Text("TypeToTalk")        ← L18（要削除）
  │   │   └─ Text(statusMessage)
  │   ├─ Spacer()
  │   └─ SettingsLink (ギア)
  │
  ├─ マイクボタン (ZStack 内)
  └─ モデルステータス表示
```

**削除時の影響**:
- HStack 内 VStack の第一子が空になる
- `.padding(.leading, 56)` は継続して statusMessage（まだ存在）に適用
- VStack(spacing: 18) の最初の要素（HStack）のサイズが縮小
- マイクボタンの相対位置に変化なし（マイクボタンは別の VStack 要素）

### 3.2 ZStack 削除の影響

**現在 ZStack 用途**: マイクアイコン（mic.fill）と ProgressView（読込中）の重ね合わせ

```swift
ZStack {  // L47
    Circle()     // 背景円
    if coordinator.isProcessing {
        ProgressView()
    } else {
        Image(systemName: "mic.fill")
    }
}
```

**ZStack 削除時**:
- ZStack は「マイクボタンの視覚的レイアウト内」のコンテナであり、削除不可
- ただし **本要件は「ZStack 削除」ではなく「Text("TypeToTalk") 削除」** であることを明確化

### 3.3 ウインドウサイズ変動予測

**タイトルバー表示化による高さ変化**:
- macOS 標準タイトルバー高さ: 約 28px（通常ウインドウ）
- 現在の `.frame(width: 360, height: 300)` はコンテンツ高さのみ指定
- タイトルバー visible にすると → 総ウインドウ高さ = 300 + 28 ≈ 328px

**レイアウト波及**:
- VStack 内の要素（Text、HStack など）の frame 指定なし → 自動レイアウト
- `.padding(20)` と `.padding(10)` は既存通り機能
- 背景 `.background(.regularMaterial, ...)` はコンテンツ領域のみ（タイトルバー下）

### 3.4 Settings ウインドウとの対比

**SettingsView は別シーン**（L538-545）:
```swift
Settings {
    SettingsView(...)
}
```
- Settings は SwiftUI で自動的にウインドウタイトル「TypeToTalk」を設定する（自動）
- Settings ウインドウは `.windowStyle(.hiddenTitleBar)` を使用していない
- したがって Settings は標準的なタイトルバーを持つ（確認済み）

→ **本要件（メインウインドウのみ）と Settings は独立**

---

## 4. 過去の類似実装（git log を見て、ウインドウ周りの変更があったかチェック）

**git log --oneline -50 の実行結果**:
```
1883798 [フォK] fix: 録音終了後のマイクボタンパルス停止バグを修正
9d70ec7 [フォK] feat: マイクボタンUI改善＋権限ラベル微調整
...
cb281cf Refactor: Modularize project structure (App, Managers, Models, Views) for high maintainability
```

**ウインドウ関連の過去コミット**:

- **コミット 16d3413** ("UI整理＋言語設定＋整形プロンプト構造化"):
  - `padding(.leading, 56)` を追加（L40）
  - タイトル "TypeToTalk" はこの時点で既存（削除対象外）
  - git log -p で確認済み

- **コミット cb281cf** ("Refactor: Modularize"):
  - App, Managers, Views ディレクトリ構造を確立
  - ウインドウ設定は この時点では `.hiddenTitleBar` と手動 NSWindow 設定が導入

**判定**: titleVisibility と titlebarAppearsTransparent の設定は **初期実装以来の状態**。削除は新規。

---

## 5. 想定される副作用 / リスク（タイトルバー有効化でウインドウ高さが変わる可能性、既存の .windowStyle 設定の影響）

### 5.1 タイトルバー有効化による変化

**現在の状態**:
- `window.titleVisibility = .hidden`（タイトルテキスト非表示）
- `.windowStyle(.hiddenTitleBar)`（タイトルバー自体を隠す）
- 実ウインドウサイズ: コンテンツ 360x300 のみ

**変更後（要件実装時）**:
- `window.titleVisibility = .visible`（またはデフォルト）に変更する必要
- `.windowStyle(.hiddenTitleBar)` を削除またはデフォルトに戻す
- `window.titlebarAppearsTransparent = true` は削除可能

**副作用**:
1. **ウインドウフレーム高さ増加**: 約 28px 追加
2. **ドラッグ領域**: `window.isMovableByWindowBackground = true` は non-titlebar 用→削除検討必要
3. **マテリアル背景**: `.background(.regularMaterial, ...)` はタイトルバーの下に配置される
4. **レイアウト自動調整**: VStack のスペーシング (spacing: 18) に変化なし

### 5.2 .windowStyle 修飾子の優先度

**SwiftUI macOS での優先度（高→低）**:
1. `.windowStyle()` 修飾子（SwiftUI 層）
2. `.onAppear` での NSWindow 手動設定（AppKit 層）

**現状**: 両方が hidden を指示 → redundant だが動作保証

**変更時の注意**: 
- `.windowStyle()` の削除だけでは不十分
- `window.titleVisibility` も同時に変更必要

### 5.3 Text("TypeToTalk") 削除の副作用

**非表示による圧縮効果**:
- 削除時 HStack の VStack がコンテンツを失う
- statusMessage だけが残る
- statusMessage が empty の場合（L20 if 文）→ HStack 内 VStack が完全に空
- 通常、不可視要素は SwiftUI が frame を 0 に圧縮

**ウインドウ外観の変化**:
- メインビューの上部空白が消える
- マイクボタンが相対的に上に移動？
  - **不確か**: VStack の自動スペーシング動作の詳細（spacing: 18 が要素削除時どう機能するか）
  - 要検証: 実機またはシミュレータで確認推奨

---

## 6. 制約条件（macOS バージョン、SwiftUI WindowGroup の標準的な作法、TypeToTalk プロジェクト固有のアプリ構造）

### 6.1 macOS バージョン要件

**Package.swift（L6-8）**:
```swift
platforms: [
    .macOS(.v14)
]
```

**project.yml（L5, L17）**:
```yaml
deploymentTarget:
  macOS: "14.0"
MACOSX_DEPLOYMENT_TARGET: "14.0"
```

**判定**: macOS 14（Sonoma）以降が必須

### 6.2 SwiftUI WindowGroup の標準作法（macOS 14+）

**タイトルバー制御方法**:

1. **`.windowStyle()` 修飾子（推奨）**:
   ```swift
   WindowGroup { ... }
       .windowStyle(.hiddenTitleBar)  // 完全に隠す
       .windowStyle(.automatic)       // デフォルト（タイトル表示）
   ```

2. **直接的な NSWindow 操作（低レベル）**:
   ```swift
   window.titleVisibility = .visible / .hidden
   window.title = "TypeToTalk"  // タイトルテキスト設定
   ```

**本要件での推奨**:
- `.navigationTitle("TypeToTalk")` は VStack 直下で設定可能（macOS 12+）
- または `.windowStyle()` を削除し `.onAppear` で `window.title = "TypeToTalk"` を明示設定

### 6.3 TypeToTalk プロジェクト固有の構造

**ウインドウ関連の設計**:

| 要素 | 実装方法 | 備考 |
|------|--------|------|
| メインウインドウ（レコーダー） | WindowGroup + TypeToTalkMainView | フローティングウインドウ型 |
| 設定ウインドウ | Settings scene | 標準ウインドウ |
| ウインドウ識別子 | `window.identifier = "RecorderWindow"` | 複数ウインドウ判別用 |
| ドラッグ可能 | `window.isMovableByWindowBackground = true` | 背景をドラッグしてウインドウ移動 |
| フォーカス制御 | `NSApplication.setActivationPolicy(.regular)` + `.activate()` | グローバルショートカット応答後にウインドウ前面化 |

**変更スコープ**:
- 本要件は **メインウインドウのみ** 対象
- Settings ウインドウには変更なし
- ウインドウ識別子・フォーカス制御はそのまま

---

## 7. テスト戦略（SwiftUI Mac アプリなのでテスト書きにくい想定。実機/シミュ確認ポイントを具体的に列挙）

### 7.1 テスト書きの制約

**SwiftUI macOS アプリ固有の困難**:
- `.onAppear` コールバック内の `NSApplication.shared.windows` アクセスは XCTest 環境で不安定
- `.windowStyle()` 修飾子の効果は ビジュアルテストのみ（ユニットテスト不可）
- ウインドウサイズ・位置の計測は統合テストまたは実機確認が必須

**テスト可能な範囲**:
- `TypeToTalkCoordinator` の状態管理（既存テスト）
- `TypeToTalkMainView` の View 階層（snapshot test、macOS では限定的）

### 7.2 実機 / シミュレータ確認ポイント

#### A. 起動時の外観確認

**チェックリスト**:

1. **ウインドウタイトルバー表示状態**
   - タイトルバーが中央に "TypeToTalk" テキストで表示されるか
   - フォントサイズ・色は macOS 標準フォント（San Francisco）か
   - ウインドウドラッグ時のタイトルバー反応速度（遅延なし）

2. **ウインドウサイズ**
   - 現在（hidden タイトルバー時）: 約 360x300px
   - 変更後（visible タイトルバー）: 約 360x328px（+28px 高）
   - ウインドウフレームが画面外に出ないか

3. **レイアウト変動**
   - "TypeToTalk" テキスト削除後、HStack の VStack 内に statusMessage のみ残る
   - statusMessage が empty の場合、上部に空白が残るか、完全に圧縮されるか
   - マイクボタンの垂直位置が変化するか（削除前後比較）

4. **背景マテリアル**
   - `.regularMaterial` 背景がタイトルバー下に正しく適用されるか
   - 背景透過による下層ウインドウの見え方

5. **マイク UI 変動**
   - ZStack 内のマイクアイコン（mic.fill）が圧縮・拡大されないか
   - プログレスビュー（読込中）の表示位置・サイズ（ZStack 再計算）

#### B. インタラクション確認

**チェックリスト**:

6. **ウインドウドラッグ**
   - タイトルバー をクリック・ドラッグしてウインドウ移動可能か
   - `window.isMovableByWindowBackground` の削除/保持の判定：
     - 保持 → 背景クリック時のドラッグも有効（浮動パネル体験）
     - 削除 → タイトルバーのみドラッグ可能（標準ウインドウ体験）

7. **マイクボタン操作**
   - ボタンクリックで録音開始・停止
   - パルスアニメーション（isRecording 時）に変化なし
   - プログレスビュー表示（isProcessing 時）に変化なし

8. **ショートカット応答**
   - グローバルショートカット（Cmd+Shift+;）でウインドウ前面化
   - ウインドウの show/hide トグル動作

9. **設定ウインドウ独立確認**
   - ギア icon をクリック→ Settings ウインドウ別表示
   - Settings ウインドウは従来通りタイトル "TypeToTalk" を持つ
   - メイン ウインドウの変更が Settings に波及しないか

#### C. Edge Case / ストレステスト

**チェックリスト**:

10. **statusMessage の表示/非表示 切り替え**
    - statusMessage = "" → HStack の VStack が完全に空になる場合の見栄え
    - statusMessage = "文字起こし中..." → 複数行メッセージの折り返し

11. **ウインドウリサイズ**
    - `.windowResizability(.contentSize)` で ウインドウがリサイズ不可になっているか（要件通り）
    - リサイズ試行時、コーナーのリサイズハンドルが非表示か

12. **デスクトップ配置**
    - macOS 14+ の Stage Manager / Spaces との相互作用
    - 複数ディスプレイ環境で表示位置が正しいか

13. **Dark Mode / Light Mode**
    - `.regularMaterial` 背景が両モード で適切に見えるか
    - タイトルバーのテキスト色が両モード で読みやすいか

14. **ウインドウ最小化・最大化**
    - 最小化（Cmd+M）で ウインドウが Dock に最小化される
    - 最大化（ダブルクリック タイトルバー）時の挙動
    - 再度開く時にタイトルバーが正しく再描画される

#### D. パフォーマンス確認

**チェックリスト**:

15. **起動時間**
    - `.onAppear` の NSWindow 設定処理が追加 → 起動時間に明確な遅延なし
    - window.titleVisibility / titlebarAppearsTransparent の設定は微小コスト

16. **メモリリーク**
    - 長時間ウインドウ表示時、メモリ使用量が増加しないか
    - globalFlagsMonitor / localFlagsMonitor（キーイベント監視）との競合

### 7.3 テスト実行の推奨手順

1. **デバッグビルド**（ローカル開発）
   ```bash
   swift build
   open .build/debug/TypeToTalk.app
   ```
   - または Xcode で Run（Cmd+R）

2. **シミュレータ**（macOS 14 環境）
   ```bash
   xcode-select --install  # Xcode Command Line Tools
   swift build -c debug    # または Xcode UI
   ```
   - シミュレータは実機とは異なり、タイトルバー挙動が微妙に異なる可能性

3. **実機**（推奨）
   ```bash
   swift build -c release
   open .build/release/TypeToTalk.app
   ```
   - macOS 14+ の複数台で検証（M1/M2/Intel）

4. **手動テストログ**
   ```
   - [ ] 起動時タイトルバー表示確認
   - [ ] ウインドウサイズ測定（360x328px ±5px）
   - [ ] statusMessage 削除後レイアウト確認
   - [ ] マイクボタン UI 圧縮なし確認
   - [ ] タイトルバードラッグ可能確認
   - [ ] Settings ウインドウ独立確認
   - [ ] ショートカット応答確認
   - [ ] Dark/Light Mode 表示確認
   ```

### 7.4 不確か な項目（要調査 / 実装後確認）

**以下の項目は、実装を進める上で判明する可能性あり**:

- **HStack 内 VStack の圧縮挙動**:
  - statusMessage が empty の場合、`.padding(.leading, 56)` が空要素に作用するか
  - → **判定**: 実装後に実機で確認する必要あり

- **`.navigationTitle()` vs 手動 `window.title` の優先度**:
  - SwiftUI 5.x での `.navigationTitle()` 動作が不確か
  - → **推奨**: 初期実装では `.onAppear` での手動設定 (`window.title = "TypeToTalk"`) で明示的に指定

- **`window.isMovableByWindowBackground` の保持判定**:
  - 現在は `true` で背景ドラッグ可能
  - 標準タイトルバー有効化時、この設定を保持するか削除するか
  - → **推奨**: ユーザー体験を優先して判定（タイトルバード ラッグで十分なら削除、浮動パネル体験を重視なら保持）

---

## 総括

### 現状の実装構造

- メインウインドウ（レコーダー）: WindowGroup + TypeToTalkMainView
- Z-stack: マイクボタン UI のみ（タイトルバーとは無関係）
- Text("TypeToTalk"): VStack 内 HStack に "独自配置" された冗長タイトル
- NSWindow 設定: `.onAppear` で titleVisibility=hidden + titlebarAppearsTransparent=true
- `.windowStyle(.hiddenTitleBar)` により SwiftUI 層でもタイトルバー隠蔽

### 実装予定の変更点（本要件）

1. Text("TypeToTalk") を VStack から削除
2. `.windowStyle(.hiddenTitleBar)` を削除または `.automatic` に変更
3. `.onAppear` で `window.titleVisibility = .visible` または `window.title = "TypeToTalk"` を設定
4. ウインドウサイズ +28px（タイトルバー高さ分）に自動調整される

### 波及範囲

- **確定**: メインウインドウのみ影響
- **未影響**: Settings ウインドウ、他 managers、coordinator 状態管理
- **検証必須**: レイアウト圧縮、ドラッグ可能性、ショートカット応答、マイクボタン UI

---

**報告者**: イチジク調査員  
**報告完了日時**: 2026-04-25 18:51 JST  
