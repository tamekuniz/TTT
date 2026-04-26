# Step 4 実装計画書 — HUD パネル表示機構

**作成日時**: 2026-04-26 08:47（フォックスの極タマ）
**プランナー**: 桃ちゃん（Phase 4 / プランナー小人ちゃん）
**対象**: 旧 TypeToTalkMainView ベース HUD を NSPanel(nonactivatingPanel) で表示し AppStatus 連動で自動表示・非表示

---

## 0. 設計決定（シア指定方針より確定）

| 項目 | 決定 |
|---|---|
| NSPanel 実装方式 | **Option 1**: NSWindowController + NSHostingView（AppKit ブリッジ） |
| パネル種別 | `NSPanel(styleMask: [.borderless, .nonactivatingPanel])` |
| ウインドウレベル | `.floating` |
| 背景・影 | `backgroundColor = .clear`, `hasShadow = true` |
| ドラッグ移動 | `isMovableByWindowBackground = true` |
| HUD サイズ | **280 × 200**（マイクボタン縮小 + ステータス2行 + 余白） |
| 表示位置 | 画面下中央（Dock 上 40px、`NSScreen.main?.visibleFrame` 基準） |
| SettingsLink | **削除**（HUD は表示専用） |
| alert 系 | **削除**（コーディネータが管轄） |
| Settings トグル名 | `visualFeedbackEnabled: Bool`（デフォルト true） |
| トグル配置 | SettingsView 既存「フィードバック音」トグルと並べる（同 GroupBox 内） |
| フェード | `idle` 遷移後 2秒で fadeOut。`error` は手動操作 or 5秒で消える |

**採用根拠**:
- Option 1 は investigation.md §6.2 で「SwiftUI だけでは NSPanel.nonactivatingPanel が out-of-the-box で選べない可能性」が指摘されているため確実性最優先。
- HUD サイズ 280×200 は元 360×300 から縮小。ステータス2行 + マイクボタン (Φ72 に縮小) + 上下 padding を許容できる最小サイズ。

---

## 1. Phase 分割

スコープが広いため2 Phase に分割する。**Phase A 完了で動作確認 → Phase B で仕上げ** の順。

- **Phase A**: 骨組み（HUD 表示・基本連動）
  - HUD パネルが録音開始で出る・録音終了で消える状態まで
  - フェードや位置調整は最低限（即時 show/hide でも可）
  - 設定トグル無し（常時 ON で動かす）
- **Phase B**: 仕上げ（フェード・位置・設定トグル）
  - フェードイン/アウト
  - 位置計算（画面下中央 / Dock 上 40px）
  - SettingsManager.visualFeedbackEnabled 追加
  - SettingsView トグル追加
  - error 状態での 5秒 auto-hide
  - 既存 onChange パルス停止バグ未然防止確認

---

## 2. 実装タスク

### Phase A: 骨組み（HUD 表示・基本連動）

#### A-1. 旧 TypeToTalkMainView の参照取得
- `git show 952921f^:Sources/TypeToTalk/App/TypeToTalkApp.swift > /tmp/old_main_view.swift` で抽出
- 行11-180 の TypeToTalkMainView struct + 補助関数（micButtonColor, modelStatusRow, statusBadge, statusColor）を確認

#### A-2. HUDView 作成
**新規ファイル**: `/Sources/TypeToTalk/Views/HUDView.swift`
- 旧 TypeToTalkMainView をベースに以下を簡略化:
  - **削除**: SettingsLink, alert 修飾子, navigation 系
  - **保持**: マイクボタン ZStack（サイズを 88 → **72** に縮小）, modelStatusRow × 2, micButtonColor / statusBadge / statusColor / isPulsing
- 全体 VStack: spacing 14（元 18）、`.frame(width: 280, height: 200)`
- 背景: `.background(.ultraThinMaterial)` + `RoundedRectangle(cornerRadius: 16).fill(...)` で HUD らしさ
- マイクボタンは `ZStack` のまま、`Button` でタップで `coordinator.toggleRecording()` を呼ぶ（HUD 上からも操作可）
- 補助関数（micButtonColor, modelStatusRow, statusBadge, statusColor）も同ファイルに private で配置

#### A-3. HUDPanelController 作成
**新規ファイル**: `/Sources/TypeToTalk/Managers/HUDPanelController.swift`
- `@MainActor final class HUDPanelController: NSObject`
- 内部に `private var panel: NSPanel?`
- `init(coordinator: TypeToTalkCoordinator)` で coordinator を保持
- `func show()`:
  - 既に panel が存在すれば `panel.orderFrontRegardless()` のみ
  - 無ければ NSPanel を新規作成:
    ```
    NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 280, height: 200),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    ```
  - `level = .floating`
  - `isMovableByWindowBackground = true`
  - `hasShadow = true`
  - `backgroundColor = .clear`
  - `isOpaque = false`
  - `hidesOnDeactivate = false`
  - contentView = `NSHostingView(rootView: HUDView().environmentObject(coordinator))`
  - 表示位置は Phase A では一旦画面中央（`panel.center()`）でよい
  - `panel.orderFrontRegardless()` （`.makeKeyAndOrderFront()` ではなくフォーカス奪わない方）
- `func hide()`:
  - `panel?.orderOut(nil)`
- `func dispose()`:
  - panel close + nil 化（リソース解放、Phase B で必要に応じ実装）

#### A-4. Coordinator から HUDPanelController を駆動
**変更ファイル**: `/Sources/TypeToTalk/App/TypeToTalkApp.swift`（TypeToTalkCoordinator）
- `private lazy var hudController = HUDPanelController(coordinator: self)` 追加
- 既存の `setupFormatterStatusBindings()` パターンに準拠して `setupHUDBindings()` を追加:
  ```swift
  $currentStatus
      .receive(on: DispatchQueue.main)
      .sink { [weak self] status in
          self?.handleHUDForStatus(status)
      }
      .store(in: &cancellables)
  ```
- `private func handleHUDForStatus(_ status: AppStatus)`:
  - `.recording` / `.processing` / `.error` → `hudController.show()`
  - `.idle` → `hudController.hide()` （Phase A は即時、Phase B で 2秒遅延）
- `init()` の最後で `setupHUDBindings()` を呼ぶ

#### A-5. ビルド確認 & 手動動作確認
- `swift build` でコンパイル成功確認
- アプリ起動 → ショートカット or 右Option で録音開始 → HUD が表示されるか
- 停止 → HUD が消えるか
- マイクボタンが pulse するか（既存 isPulsing 連動）
- メニューバー操作・他アプリへのフォーカスが奪われないか

---

### Phase B: 仕上げ（フェード・位置・トグル）

#### B-1. SettingsManager に visualFeedbackEnabled を追加
**変更ファイル**: `/Sources/TypeToTalk/Managers/SettingsManager.swift`
- 行212-214 の `soundFeedbackEnabled` パターンに完全準拠
- 追加プロパティ:
  ```swift
  @Published var visualFeedbackEnabled: Bool {
      didSet { UserDefaults.standard.set(visualFeedbackEnabled, forKey: "visualFeedbackEnabled") }
  }
  ```
- init 内で（既存 soundFeedbackEnabled と同パターン）:
  ```swift
  if UserDefaults.standard.object(forKey: "visualFeedbackEnabled") != nil {
      self.visualFeedbackEnabled = UserDefaults.standard.bool(forKey: "visualFeedbackEnabled")
  } else {
      self.visualFeedbackEnabled = true
  }
  ```

#### B-2. SettingsView にトグル追加
**変更ファイル**: `/Sources/TypeToTalk/Views/SettingsView.swift`
- 行248-252 の `フィードバック音` トグル直後に `視覚フィードバック` トグルを追加:
  ```swift
  settingRow("視覚フィードバック") {
      Toggle("", isOn: $settings.visualFeedbackEnabled)
          .labelsHidden()
          .toggleStyle(.switch)
  }
  ```
- 行254 の説明文（フィードバック音についての段落）に「視覚フィードバック ON で録音中の状態を画面下にHUD表示します」を追記

#### B-3. handleHUDForStatus に visualFeedbackEnabled ガード追加
**変更ファイル**: TypeToTalkCoordinator
- `handleHUDForStatus` 冒頭で `guard settings.visualFeedbackEnabled else { hudController.hide(); return }`
- これで OFF にすると即非表示。ON にしても次の status 遷移で復帰

#### B-4. 表示位置を画面下中央に
**変更ファイル**: HUDPanelController
- `show()` 内で `panel.center()` の代わりに:
  ```swift
  if let screen = NSScreen.main {
      let frame = screen.visibleFrame
      let hudWidth: CGFloat = 280
      let hudHeight: CGFloat = 200
      let x = frame.midX - hudWidth / 2
      let y = frame.minY + 40
      panel.setFrameOrigin(NSPoint(x: x, y: y))
  }
  ```

#### B-5. フェードイン・フェードアウト
**変更ファイル**: HUDPanelController
- `show()`:
  - panel.alphaValue = 0 で表示開始
  - `NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.2; panel.animator().alphaValue = 1.0 }`
- `func hide(afterDelay seconds: Double = 0)`:
  - 内部に `private var hideTask: Task<Void, Never>?` を持ち
  - `hideTask?.cancel()` してから新規 Task 起動
  - `try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))`
  - キャンセルされていなければ animator で alphaValue → 0 → orderOut
- `show()` 呼び出し時には必ず `hideTask?.cancel()` する

#### B-6. AppStatus 別の表示制御
**変更ファイル**: TypeToTalkCoordinator
- `handleHUDForStatus`:
  - `.idle` → `hudController.hide(afterDelay: 2.0)`
  - `.recording`, `.processing` → `hudController.show()`（hideTask キャンセル込み）
  - `.error(_)` → `hudController.show()` + `hudController.hide(afterDelay: 5.0)`

#### B-7. 既存 isPulsing バグ確認
- 直近コミット `1883798 fix: 録音終了後のマイクボタンパルス停止バグ` の挙動が HUDView でも踏襲されているか確認
- 旧 TypeToTalkMainView の `.onChange(of: coordinator.recorder.isRecording)` パターンを HUDView でもそのまま採用

#### B-8. ビルド・統合確認
- `swift build`
- 録音開始 → 即表示 → 停止 → 2秒後フェードアウト
- エラー時 → 5秒で消える
- 設定トグル OFF → HUD 出ない / ON → 再度出る
- マルチディスプレイは Phase B 範囲外（後続課題、todo に記録のみ）

---

## 3. 影響ファイル一覧

| ファイル | 変更種別 | 概要 |
|---|---|---|
| `/Sources/TypeToTalk/Views/HUDView.swift` | 新規 | 旧 TypeToTalkMainView ベースの HUD 専用 View |
| `/Sources/TypeToTalk/Managers/HUDPanelController.swift` | 新規 | NSPanel ライフサイクル + 表示位置 + フェード |
| `/Sources/TypeToTalk/App/TypeToTalkApp.swift` | 編集 | TypeToTalkCoordinator に HUD 連動を追加 |
| `/Sources/TypeToTalk/Managers/SettingsManager.swift` | 編集 | visualFeedbackEnabled 追加 |
| `/Sources/TypeToTalk/Views/SettingsView.swift` | 編集 | 視覚フィードバックトグル追加 |

---

## 4. 検証計画

### Phase A 完了時
- [ ] `swift build` 成功
- [ ] 録音開始でHUD 表示
- [ ] 録音停止で HUD 消える
- [ ] HUD 表示中にメニューバー / 他アプリのフォーカスが奪われない
- [ ] HUD のマイクボタンがパルスする
- [ ] HUD のマイクボタンタップで録音開始/停止が動く

### Phase B 完了時（追加）
- [ ] `swift build` 成功
- [ ] HUD が画面下中央に表示される
- [ ] idle 遷移後 2秒で消える
- [ ] error 状態で 5秒で消える
- [ ] visualFeedbackEnabled OFF で HUD 出ない / ON で復帰
- [ ] フェードイン・フェードアウトが滑らか
- [ ] パルス停止バグ（直近 fix コミット相当）が再発していない
- [ ] HUD ドラッグで位置移動可能

---

## 5. 不確か / 後続課題

| 項目 | 状況 | 対処 |
|---|---|---|
| マルチディスプレイ環境での HUD 位置 | 未検証 | Phase B 範囲外。`NSScreen.main` 採用、後続 issue |
| HUD ドラッグ位置の永続化 | 未着手 | 範囲外。要望が出たら別タスク |
| HUD 上マイクボタンの hit-test と nonactivatingPanel 相性 | 不確か | Phase A の手動確認で要検証。動かない場合は acceptsMouseMovedEvents / styleMask 調整 |
| `visualFeedbackEnabled` の英訳 SettingsView 多言語対応 | 範囲外 | プロジェクト方針に合わせ後続 |
| アクセシビリティラベル | 未着手 | 後続。HUD は accessibility hidden で良い可能性も |

---

## 6. 制約遵守チェック

- [x] investigation.md を Read 済み（537行全部）
- [x] Option 1（NSWindowController + NSHostingView）採用を明示
- [x] SettingsLink 削除を明示
- [x] alert 系削除を明示
- [x] HUD サイズ 280×200 をプランナー判断で決定
- [x] visualFeedbackEnabled デフォルト true を明示
- [x] 表示位置：画面下中央（Dock 上 40px）を明示
- [x] Phase 分割で骨組み/仕上げを分離
- [x] 省略・サボりなし

---

**プランニング完了**: 2026-04-26 08:47 / 桃ちゃん
