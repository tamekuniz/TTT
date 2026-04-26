# Step 3 調査報告書：positionAtBottomCenter() の初回限定実装検討

**実行日時**: 2026年4月26日 11:44（タマスダチ調査）  
**要件**: HUDPanelController.show() で毎回呼ばれる positionAtBottomCenter() を初回のみに限定する  
**対象ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/HUDPanelController.swift`  
**調査範囲**: 実装コード、呼び出しパターン、NSPanel の frame 動作、複数モニタ環境

---

## 1. 関連ファイル一覧

### 主要ファイル

| ファイルパス | 行数 | 役割 |
|---|---|---|
| `/Sources/TypeToTalk/App/HUDPanelController.swift` | 82 | HUD パネル（NSPanel.nonactivatingPanel）ライフサイクル・位置管理 |
| `/Sources/TypeToTalk/App/TypeToTalkApp.swift` | 616 | Coordinator（AppStatus 管理）、show/hide 呼び出し元 |
| `/Sources/TypeToTalk/Views/HUDView.swift` | 145 | HUD パネル内容（SwiftUI View） |

### show() の呼び出し元（確認済み）

| 呼び出し元 | ファイルパス | 行番号 | 呼び出しコンテキスト |
|---|---|---|---|
| `handleHUDForStatus()` | TypeToTalkApp.swift | 156 | `case .recording, .processing, .error:` で即時 show |
| N/A（他の呼び出し元なし） | - | - | 複数の show 呼び出しなし（Coordinator.show() は handleHUDForStatus の中でのみ呼ばれる） |

**補足**: grep -r "\.show()" の結果、TypeToTalkApp.swift 行156 のみが HUDPanelController.show() 呼び出しポイント。他に show 直接呼び出しなし。

---

## 2. 既存実装パターン（show/hide/positionAtBottomCenter の現状、行番号付き）

### 2.1 show() メソッド（行50-55）

```swift
func show() {
    guard let panel = window as? NSPanel else { return }
    positionAtBottomCenter(panel: panel)  // 毎回呼ばれる（要求課題）
    // フォーカスを奪わずに前面化する（makeKeyAndOrderFront は使わない）
    panel.orderFrontRegardless()
}
```

**現在の動作**: 
- show() が呼ばれるたびに positionAtBottomCenter() が実行される
- positionAtBottomCenter() は NSPanel の frame を毎回再計算して上書きする

### 2.2 hide() メソッド（行58-60）

```swift
func hide() {
    window?.orderOut(nil)
}
```

**特徴**: 
- パネルを非表示にするが、frame は保持される
- orderOut 後に show() が呼ばれると positionAtBottomCenter() で再度位置調整される

### 2.3 positionAtBottomCenter() メソッド（行62-73）

```swift
private func positionAtBottomCenter(panel: NSPanel) {
    guard let screen = NSScreen.main else { return }
    let frame = screen.visibleFrame
    let hudWidth: CGFloat = 280
    let hudHeight: CGFloat = 200
    let x = frame.midX - hudWidth / 2
    let y = frame.minY + 40
    panel.setFrame(
        NSRect(x: x, y: y, width: hudWidth, height: hudHeight),
        display: true
    )
}
```

**詳細分析**:
- **行63**: NSScreen.main で主画面（メニューバーがある画面）を取得
- **行64**: screen.visibleFrame（メニューバー・Dock 除外領域）を取得
- **行67-68**: 画面下中央（x = 中央、y = Dock 上 40px）で位置を計算
- **行69-72**: panel.setFrame で NSPanel の frame を直接上書き（display: true で即座に画面反映）

**問題点（要求課題）**:
- 毎回 show() で positionAtBottomCenter() が実行され、ユーザーがドラッグで移動した位置が上書きされる
- setFrame の display: true パラメータにより、位置変更が即座に画面に反映される

---

## 3. 影響範囲

### 3.1 Coordinator から show を呼ぶ箇所

**ファイル**: `/Sources/TypeToTalk/App/TypeToTalkApp.swift`

| 行番号 | メソッド | コンテキスト |
|---|---|---|
| 156 | handleHUDForStatus() | `switch status { case .recording, .processing, .error: hudController?.show()` |

**呼び出しの頻度**:
- 行156 は Combine sink（行132-138）内で AppStatus が .recording/.processing/.error に遷移するたびに実行される
- idle 状態から recording 遷移時に 1 回、processing 遷移時に 1 回、error 遷移時に 1 回呼ばれる可能性あり

**呼び出しフロー**:
```
toggleRecording()
  → currentStatus = .recording (行264)
  → setupHUDBindings() の sink がトリガ
  → handleHUDForStatus(.recording)
  → hudController?.show()  // positionAtBottomCenter() 実行
```

### 3.2 複数モニタ環境での影響

**NSScreen.main の動作**:
- NSScreen.main は、メニューバーが存在する画面（通常はメイン/プライマリ画面）を返す
- デュアルモニタなど複数モニタ環境で、ユーザーが HUD をセカンダリモニタにドラッグしても、show() のたびに positionAtBottomCenter() で主画面座標に戻される

**複数モニタ切り替わりシナリオ**:
1. プライマリモニタで HUD を表示 → positionAtBottomCenter() で主画面下中央に配置
2. ユーザーが HUD をセカンダリモニタにドラッグで移動
3. 再度 show() が呼ばれる（次回の recording 遷移など）
4. → positionAtBottomCenter() で再びプライマリモニタ下中央に上書きされる（ユーザーのドラッグが無視される）

**追加リスク**: 
- 画面切り替わり（モニタ接続解除など）で、HUD が元いたセカンダリモニタの座標系に取り残される可能性
- positionAtBottomCenter() で毎回主画面を参照するため、接続解除後の「存在しない座標」が指定されるリスク低い（guard で screen が nil なら return）

---

## 4. 過去の類似実装（git log で HUD 関連変更）

### 4.1 HUD 実装の初期コミット

**コミット**: `e0de4f0`（2026年4月26日 09:01）  
**メッセージ**: `[フォK] feat: HUD 視覚フィードバックパネル追加 (Phase A)`

```
[フォK] feat: HUD 視覚フィードバックパネル追加 (Phase A)

旧 TypeToTalkMainView を HUD として復活させ、フォーカス奪わない
NSPanel(nonactivatingPanel) で AppStatus 連動表示する。

- HUDView.swift 新規: 旧マイクボタン UI + ステータス2行を縮小（280x200）
  ・SettingsLink/alert は削除、表示専用
- HUDPanelController.swift 新規: NSWindowController + HUDPanel(NSPanel)
  ・[.borderless, .nonactivatingPanel], .floating, isMovableByWindowBackground
  ・canBecomeKey/Main = false でフォーカス奪取を物理的に防止
  ・画面下中央 (Dock 上 40px) に positionAtBottomCenter
- Coordinator: $currentStatus を Combine sink で監視
  ・recording/processing/error → show()
  ・idle → 2秒遅延 hide()（hideTask cancel で点滅予防）
- SettingsManager: visualFeedbackEnabled (Bool, デフォルト ON) 追加
- SettingsView: 「視覚フィードバック」Toggle 追加（音と独立）

Phase B（フェードアニメーション・位置永続化等）は次サイクル候補。
```

**特徴**:
- 初回コミット（e0de4f0）で positionAtBottomCenter() は最初から毎回呼ばれるように設計
- 位置永続化・ドラッグ位置保持は「Phase B 候補」として明示的に後送り
- 初回限定の実装は当初からなし

### 4.2 prior の投稿状況

過去のコミット履歴では、HUD パネルのドラッグ位置保持や初回限定表示に関する実装記録なし（調査日時点）。

---

## 5. 想定される副作用 / リスク

### 5.1 ドラッグ後の位置が画面外に出ていた場合の挙動

**シナリオ**: ユーザーが HUD をドラッグして、一部またはすべてが表示画面の外（例: 上下の画面外、左右端）に出た場合

**初回限定実装時の動作**:
- positionAtBottomCenter() が初回のみ呼ばれるため、以後は setFrame が呼ばれない
- ユーザーがドラッグして画面外に出た位置のまま stay する可能性あり
- hide() 後に再度 show() しても、positionAtBottomCenter() は呼ばれず、画面外の位置で表示される

**リスク**: 中程度～高（ユーザー体験を損なう）

**対策案** (5.3 参照):
- setFrame 時に clamp 処理で画面内収まりチェック
- または、初回限定フラグを持ちつつ、画面外判定時にフラグをリセット

### 5.2 複数モニタ接続解除後の画面外挙動

**シナリオ**: セカンダリモニタに HUD をドラッグ → セカンダリモニタを接続解除

**現在の実装（初回限定なし）**:
- 毎回 positionAtBottomCenter() で主画面座標に戻される → 自動修正される

**初回限定実装後**:
- 初回のみ positionAtBottomCenter() なので、セカンダリモニタの座標が残る
- hide() → show() でも positionAtBottomCenter() が呼ばれず、セカンダリモニタ座標のままパネルが非表示のままになる可能性
- 画面がつながっていないため、マウス操作で再度見つけられない可能性あり

**リスク**: 高（ユーザーが HUD を完全に失う可能性）

**対策案**:
- hide() 呼び出し時に、frame を screen.visibleFrame で clamp
- または、初回フラグをモニタ接続状態の変化で自動リセット

### 5.3 hasPositioned フラグだけで足りるか、clamp が必要か

**フラグ: hasPositioned**:
```swift
private var hasPositioned = false
```

現状の案では、show() で hasPositioned を確認し、false なら positionAtBottomCenter() を呼ぶという実装が想定される。

**不十分な理由**:
1. **セカンダリモニタでの迷子**: has Positioned = true でも、セカンダリモニタの座標が画面内にない可能性
2. **モニタ接続解除**: frame が存在しないモニタの座標を保持している場合、orderFrontRegardless() でも描画できない
3. **画面解像度変更**: セカンダリモニタ座標が、新しい解像度では範囲外の可能性

**clamp 処理の必要性**: 高（推奨）

**想定される clamp 実装例**:
```swift
func ensureFrameOnScreen(panel: NSPanel) {
    guard let screen = NSScreen.main else { return }
    let visibleFrame = screen.visibleFrame
    var panelFrame = panel.frame
    
    // 左端を画面内に clamp
    if panelFrame.minX < visibleFrame.minX {
        panelFrame.origin.x = visibleFrame.minX
    }
    // 右端を画面内に clamp
    if panelFrame.maxX > visibleFrame.maxX {
        panelFrame.origin.x = visibleFrame.maxX - panelFrame.width
    }
    // 下端（Dock 回避）
    if panelFrame.minY < visibleFrame.minY + 40 {
        panelFrame.origin.y = visibleFrame.minY + 40
    }
    // 上端
    if panelFrame.maxY > visibleFrame.maxY {
        panelFrame.origin.y = visibleFrame.maxY - panelFrame.height
    }
    
    panel.setFrame(panelFrame, display: true)
}
```

**判定**: hasPositioned フラグだけでなく、show() 時に画面範囲チェック + clamp が必要と考えられる。

---

## 6. 制約条件（NSPanel の frame 永続化挙動、isMovableByWindowBackground）

### 6.1 isMovableByWindowBackground = true の動作

**現在の設定** (HUDPanelController.swift 行28):
```swift
panel.isMovableByWindowBackground = true
```

**動作**:
- isMovableByWindowBackground = true：ユーザーがパネルの背景領域をドラッグしても、タイトルバーなしで移動可能
- nonactivatingPanel の組合せで、ドラッグ時もアプリをアクティブ化しない
- ドラッグ後の frame は自動的に panel.frame に反映される（Apple のドラッグエンジンが frame を更新）

### 6.2 NSPanel の frame と永続化

**frame の保持方式**:
- NSWindow/NSPanel の frame は、アプリケーション内メモリに保持される
- autosave/RestorableState は設定されていない（調査結果）→ frame はアプリ終了時に失われる

**確認** (検索結果):
```
grep -rn "autosave\|saveFrame\|RestorableState" /Sources --include="*.swift"
# → 結果なし（frame の永続化設定なし）
```

**結論**: HUD の frame はアプリ終了時に記憶されず、毎回アプリ起動時には初期位置（positionAtBottomCenter）に配置される。

### 6.3 setFrame の動作と frame の生存期間

**setFrame() の効果** (HUDPanelController.swift 行69-72):
```swift
panel.setFrame(
    NSRect(x: x, y: y, width: hudWidth, height: hudHeight),
    display: true
)
```

- display: true により、setFrame 直後に NSView.setNeedsDisplay が呼ばれる → 即座に画面反映
- setFrame で指定した frame が panel.frame に代入される
- その後のドラッグまで、この frame が保持される

**ドラッグ時**:
- isMovableByWindowBackground = true により、ユーザーのマウスドラッグが panel.frame.origin を動的に更新
- ドラッグ終了後も panel.frame はドラッグ後の位置に更新されたまま

**show() 呼び出しまでの期間**:
- hide() が呼ばれても、panel.frame は変更されない（orderOut のみで frame は保持）
- show() で再度 positionAtBottomCenter() が呼ばれると、以前の frame がリセットされる（上書きされる）

### 6.4 マルチスクリーン環境での NSScreen.main

**NSScreen.main の定義**:
- メニューバーがある画面（通常はプライマリモニタ）を返す
- 複数モニタ環境では NSScreen.screens で全スクリーン取得可能

**現在の実装**:
```swift
guard let screen = NSScreen.main else { return }
```

- main のみを参照 → セカンダリモニタでのドラッグが反映されない

**改善案**:
- panel.frame が現在のどのスクリーン上にあるか判定
- セカンダリモニタにある場合、そのスクリーンの visibleFrame に clamp すべき

---

## 7. テスト戦略（実機での確認シナリオ）

### 7.1 基本シナリオ

#### A. 初回表示 → ドラッグ → 再表示

**手順**:
1. アプリ起動
2. グローバルショートカットで録音開始 → HUD が画面下中央に表示される
3. マウスで HUD をドラッグして、画面左上など別の位置に移動
4. 同じショートカットで録音停止 → HUD が hide される
5. 再度同じショートカットで録音開始 → HUD が show される

**期待値（初回限定実装後）**:
- 3 で移動した位置に HUD が表示される（positionAtBottomCenter は呼ばれない）

**検証項目**:
- HUD が初回のドラッグ位置に表示されるか
- positionAtBottomCenter() が呼ばれないことを確認（ログ出力またはブレークポイント）

#### B. ドラッグ → 画面外 → 再表示

**手順**:
1. HUD をドラッグして、パネルの 80% が画面外に出た位置に配置
2. 録音開始 → HUD が hide される
3. 再度録音開始 → HUD が show される

**期待値（clamp なし）**:
- HUD が画面外の位置のまま表示される（可視領域に戻らない）

**期待値（clamp あり）**:
- HUD が自動的に画面内に clamp されて表示される

**検証項目**:
- clamp 処理の必要性を実際に確認

### 7.2 複数モニタシナリオ

#### C. セカンダリモニタへのドラッグ

**前提**: Mac が 2 つ以上のモニタに接続されている

**手順**:
1. アプリ起動（メインモニタで表示）
2. 録音開始 → HUD が主画面下中央に表示
3. HUD を セカンダリモニタにドラッグ（接続状態を維持）
4. 録音停止 → HUD が hide される
5. 再度録音開始 → HUD が show される

**期待値（初回限定実装後、clamp なし）**:
- HUD がセカンダリモニタの位置に表示される（保持される）

**期待値（clamp あり、セカンダリ対応）**:
- HUD がセカンダリモニタの visibleFrame 内に clamp されて表示

**検証項目**:
- 複数モニタでの frame 保持が機能するか
- clamp が複数モニタに対応しているか

#### D. モニタ接続解除シナリオ

**前提**: Mac が 2 つ以上のモニタに接続された状態で作業後、セカンダリモニタを接続解除

**手順**:
1. HUD をセカンダリモニタにドラッグ
2. セカンダリモニタのケーブルを接続解除
3. 録音開始 → HUD が show される

**期待値（初回限定実装後、clamp なし）**:
- HUD が表示されない（セカンダリモニタの座標のため画面外）
- または、予期しない位置に表示される

**期待値（clamp あり、モニタ接続自動検出）**:
- HUD が主画面の visibleFrame 内に自動 clamp されて表示

**検証項目**:
- モニタ接続解除時の挙動が安全であるか
- hasPositioned フラグをリセットすべきトリガが必要か

### 7.3 edge case

#### E. 画面解像度変更（macOS 12+ の Dynamic Resolution など）

**手順**:
1. HUD をドラッグして位置を記録
2. System Settings で画面解像度を変更
3. 再度録音開始 → HUD が show される

**期待値**:
- HUD が新しい解像度での visibleFrame 内に clamp されるか、またはそのまま表示されるか

**検証項目**:
- 解像度変更で HUD が画面外に出ないか

#### F. アプリ終了 → 再起動

**手順**:
1. HUD をドラッグして位置を記録
2. アプリを終了
3. アプリを再起動

**期待値**:
- HUD がアプリ起動時の初期位置（画面下中央）に表示される
- ドラッグ位置は記憶されない（frame 永続化がないため）

**検証項目**:
- アプリ再起動時に positionAtBottomCenter() が呼ばれることを確認

---

## 8. 実装上の追加考慮事項

### 8.1 hasPositioned フラグのリセット条件

**現在案**: hasPositioned = false をどのタイミングでリセットするか

**候補**:
1. **リセット無し**: hasPositioned = true のままで、アプリ終了まで保持
   - **利点**: シンプル
   - **欠点**: モニタ接続解除時に画面外に取り残される可能性

2. **hide() 時にリセット**: 毎回 hide() で hasPositioned = false に戻す
   - **利点**: 毎回初期化される → 安全
   - **欠点**: ドラッグ位置が保持されない（要件と矛盾）

3. **条件付きリセット**: モニタ接続状態の変化やスクリーン削除時にリセット
   - **利点**: モニタ接続解除時に自動復帰
   - **欠点**: NSScreenDidChangeNotification の監視が必要（複雑化）

4. **frame 画面内チェック**: show() 時に frame が visibleFrame 内か確認し、外なら positionAtBottomCenter() を呼ぶ
   - **利点**: 安全性が高い、ドラッグ位置も保持できる
   - **欠点**: 毎回チェックのため計算コスト（軽微）

**推奨**: **案 4（clamp + 画面内チェック）** が最もバランスよい。hasPositioned フラグと clamp を組み合わせ、初回のみ positionAtBottomCenter、以降は画面内チェック後に clamp。

### 8.2 displayAsync 検討

**現在**:
```swift
panel.setFrame(..., display: true)
```

**代替案**: display: false で非同期描画、または orderFrontRegardless の後に display:
- 性能差は微微（HUD サイズ小さい）
- 現状の display: true で問題ないと判断

---

## 概要まとめ

| 項目 | 判定 |
|---|---|
| **要件の実現可能性** | ○ 可能（hasPositioned フラグで初回限定化） |
| **ドラッグ位置保持** | △ 要注意（clamp 処理がないと画面外リスク） |
| **複数モニタ対応** | △ 要注意（NSScreen.main のみ参照、セカンダリ対応必要） |
| **モニタ接続解除対応** | ✗ 対応なし（初回限定のみではリスク高） |
| **推奨実装方式** | hasPositioned フラグ + clamp + モニタ接続監視 |

