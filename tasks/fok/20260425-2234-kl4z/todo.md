# フォK Phase 1: TypeToTalk メニューバー常駐型（accessory）移行

**プランナー**: あけびじゃっど（プランナー小人）
**作成日**: 2026-04-25
**根拠**: investigation.md（マンゴーどす調べ）

---

## 全体スコープと Phase 分割方針

要件「メニューバー常駐型へ全面移行」は実装範囲が広い（骨組み変更 + UI 詳細 + エラー表示）ため、**2 Phase に分割** する。

### Phase 1（本サイクル）: 骨組みの全面移行
- accessory ポリシー化
- MenuBarExtra 導入（最小限のステータスアイコン + 設定/終了メニュー）
- メインウインドウ（WindowGroup + TypeToTalkMainView）の廃止
- `NSApp.activate(ignoringOtherApps:)` 全箇所削除
- `showRecorderWindow()` メソッドと呼び出し削除
- Settings シーンは保持
- 「ショートカット押下 → 別アプリへ録音 → 元の入力欄へ書き込み」が動く状態を作る

### Phase 2（次サイクルで起票）: メニューバー UI 詳細化
- アイコン状態反映の精緻化（idle / recording / processing / error の SF Symbol 切替・色分け）
- popover ベースの簡易 UI（直近ステータス、軽量設定リンク等）
- エラーハンドリング表示（エラー時のメニューバー通知、tooltip）
- アクセシビリティ権限未許可時のメニューバー誘導 UI

→ **本 todo.md には Phase 1 のタスクのみ記載**

---

## Phase 1 タスク一覧

### Task 1: TypeToTalkApp.swift の Scene 全面再構築

**対象ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`

#### 1-1. AppStatus enum の追加（Coordinator 内）

`TypeToTalkCoordinator` クラス内に以下を追加：

```swift
enum AppStatus: Equatable {
    case idle
    case recording
    case processing
    case error(String)
}

@Published var currentStatus: AppStatus = .idle
```

**反映タイミング**:
- `toggleRecording()` 開始時 → `.processing` （録音停止後の Whisper/AI 処理）
- `recorder.isRecording` 監視 → `.recording`（録音中）
- `insertText` 結果が `.success` → `.idle`
- `insertText` 結果が `.missingPermission` / `.noFocusedElement` / `.unsupportedTarget` → `.error(reason)`
- `handleAppLaunch` 完了直後 → `.idle`

→ 既存の `statusMessage` 文字列ロジックと**並行して**保持。文字列は SettingsView 内の表示でこれまで通り使う。`currentStatus` は MenuBarExtra のアイコン切替用。

#### 1-2. Scene の差し替え

**現在（行 549-577）の `WindowGroup { TypeToTalkMainView(...) ... }` を削除**し、以下に置き換える：

```swift
@main
struct TypeToTalkApp: App {
    @StateObject private var coordinator = TypeToTalkCoordinator()
    @Environment(\.openSettings) private var openSettings  // ※ View 内で使うため別途必要

    var body: some Scene {
        MenuBarExtra {
            // Phase 1 ではコンテキストメニュー最小実装
            Button("設定...") {
                NSApp.sendAction(
                    Selector(("showSettingsWindow:")),
                    to: nil, from: nil
                )
                NSApplication.shared.activate(ignoringOtherApps: true)
                // ※ Settings ウインドウを開く瞬間だけ activate は許容
                //    （ユーザーが明示的に設定を開いたとき）
            }
            Divider()
            Button("TypeToTalk を終了") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            // Phase 1 では SF Symbol 固定（状態反映は Phase 2）
            Image(systemName: "mic.circle")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(
                settings: coordinator.settings,
                whisper: coordinator.whisper,
                bonsai: coordinator.bonsai,
                accessibility: coordinator.accessibility,
                coordinator: coordinator
            )
            .onAppear {
                // Settings 初表示時にも accessory ポリシーを再適用（保険）
                NSApplication.shared.setActivationPolicy(.accessory)
            }
        }
    }
}
```

**注意点**:
- macOS 14+ は `MenuBarExtra` で `Button("設定...")` から Settings を開く公式方法が `Selector(("showSettingsWindow:"))` または `SettingsLink`（macOS 14+）。**`SettingsLink` を採用**してよい：
  ```swift
  SettingsLink {
      Text("設定...")
  }
  ```
  → SettingsLink の方が SwiftUI ネイティブで安全。これを採用する。

- `MenuBarExtra` の `label` 部分は Phase 1 では `Image(systemName: "mic.circle")` で固定。Phase 2 で `coordinator.currentStatus` に応じて動的切替。

- accessory ポリシーの設定タイミング → アプリ起動時に必ず一度実行する必要がある。MenuBarExtra だけでは accessory にならない（デフォルトは regular）。
  - **解決策**: `init()` で `NSApplication.shared.setActivationPolicy(.accessory)` を呼ぶ。
  ```swift
  init() {
      NSApplication.shared.setActivationPolicy(.accessory)
  }
  ```

#### 1-3. handleAppLaunch() の起動箇所

旧 `WindowGroup { ... .onAppear { coordinator.handleAppLaunch() } }` が消えるため、`coordinator.handleAppLaunch()` の呼び出し箇所を別途用意する：

**選択肢**:
- (A) `TypeToTalkCoordinator.init()` 内で呼ぶ → SwiftUI ライフサイクルとずれる可能性
- (B) `MenuBarExtra` の `label` 内 View に `.onAppear { coordinator.handleAppLaunch() }` を仕込む
- (C) `TypeToTalkApp.init()` 内で `Task { @MainActor in coordinator.handleAppLaunch() }` を呼ぶ

**採用**: **(B)**。MenuBarExtra の label View が表示時に onAppear が一度だけ呼ばれることを利用する。`Image(systemName: "mic.circle")` を `MenuBarLabel()` というラッパー View に切り出して onAppear を仕込む。

```swift
struct MenuBarLabel: View {
    let coordinator: TypeToTalkCoordinator
    @State private var didLaunch = false

    var body: some View {
        Image(systemName: "mic.circle")
            .onAppear {
                if !didLaunch {
                    didLaunch = true
                    coordinator.handleAppLaunch()
                }
            }
    }
}
```

→ `MenuBarExtra { ... } label: { MenuBarLabel(coordinator: coordinator) }`

#### 1-4. 既存 onChange ハンドラ群の移植

旧 `WindowGroup { ... }` 内で `.onChange(of: coordinator.settings.formatterProviderRawValue)` 等が登録されていた（投資gation §2-A 行 73-75 周辺で確認済みの「他の onChange」）。これらを **`MenuBarLabel` 内に移植する**。

→ 実装小人ちゃんは TypeToTalkApp.swift 行 549-577 の WindowGroup ブロック全体の onChange/onAppear を MenuBarLabel に移し替える。

---

### Task 2: TypeToTalkMainView の削除

**対象ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`

- `struct TypeToTalkMainView: View` （行 11-180）を**ファイルから完全に削除**
- TypeToTalkMainView を参照している箇所は WindowGroup のみだったので、Scene 差し替えで参照が消える

**注意**: TypeToTalkMainView 内で使われている UI コンポーネント（マイクボタン関連の View 等）は、もし他で再利用されていなければ同時に削除してよい。
- 実装小人ちゃんは TypeToTalkMainView 内で参照している private struct/extension を Grep で確認し、TypeToTalkMainView でしか使われていないなら一緒に削除する。
- Phase 2 で popover UI を作るときに再利用したくなる可能性があるが、その時は git history から復元すればよい（**今は素直に消す**）。

---

### Task 3: showRecorderWindow() メソッドと呼び出しを完全削除

**対象ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`

#### 3-1. メソッド削除

行 453-463 の `func showRecorderWindow() { ... }` を**完全削除**。

#### 3-2. 呼び出し箇所削除

`handleTriggerShortcutDown()` 内の以下 2 箇所を削除：

- 行 367: `showRecorderWindow()`（toggle モード）
- 行 372: `showRecorderWindow()`（pushToTalk モード）

修正後の `handleTriggerShortcutDown()`：

```swift
private func handleTriggerShortcutDown() async {
    guard !isTriggerShortcutPressed else { return }
    isTriggerShortcutPressed = true
    recordTriggerFeedback(source: "グローバル")

    switch settings.shortcutTriggerMode {
    case .disabled:
        break
    case .toggle:
        await toggleRecording()
    case .pushToTalk:
        if !recorder.isRecording && !isProcessing {
            await toggleRecording()
        }
    }
}
```

---

### Task 4: NSApp.activate() の全箇所除去

**対象ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`

investigation §2-B で 2 箇所特定済み：
- 行 552-553（onAppear 内、WindowGroup 内 → Task 1 の Scene 差し替えで消える）
- 行 454-455（showRecorderWindow 内 → Task 3 の削除で消える）

**追加検証**: 実装小人ちゃんは作業完了後に以下を実行して 0 件を確認：
```bash
grep -rn "NSApplication.shared.activate" /Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/
grep -rn "NSApp.activate" /Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/
grep -rn "setActivationPolicy(.regular)" /Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/
```

- `NSApp.activate` / `NSApplication.shared.activate` → **0 件** であること
- `setActivationPolicy(.regular)` → **0 件** であること
- `setActivationPolicy(.accessory)` → **1〜2 件**（init と Settings の onAppear 保険）

---

### Task 5: ビルド確認

**実行**:
```bash
cd /Users/tamekuniz/GitHub/tamekuniz/TTT
xcodegen generate  # project.yml から再生成（必要なら）
xcodebuild -scheme TypeToTalk -destination 'platform=macOS' build 2>&1 | tail -50
```

**判定**: ビルド成功（エラー 0、Warning 許容）

→ ビルド失敗時は実装小人ちゃんが Phase 1 内で自己解決する。複雑な失敗の場合のみシアにエスカレーション。

---

### Task 6: 実機検証（Step 7 デプロイ後）

フォK Step 7 で macOS 実機にインストール → 以下を手動確認：

- [ ] Dock に TypeToTalk アイコンが**出ない**
- [ ] メニューバー右端に `mic.circle` アイコンが表示される
- [ ] アイコンクリック → 「設定...」「終了」のメニューが出る
- [ ] 「設定...」クリック → SettingsView が開く
- [ ] Safari の検索欄にフォーカス → ショートカット押下 → 録音 → 停止 → **Safari 検索欄にテキストが入力される**
- [ ] 上記の間、Safari からフォーカスが奪われない（メニューバーアイコンが active にならない）
- [ ] 右 Option キー長押しでも同じフローが動く
- [ ] アプリ終了 → メニューバーアイコン消失

→ 投資gation §7 シナリオ 1〜5・7 の Phase 1 担当部分。シナリオ 6（エラーハンドリング）は Phase 2 に回す。

---

## 制約・注意事項

- **Phase 1 ではアイコン状態の動的切替は実装しない**（Phase 2 へ）
- **マイクボタンUI は廃止**（メインウインドウごと消える）
- **Settings UI は既存のまま流用**（修正不要）
- **KeyboardShortcuts ライブラリは無修正**（accessory でも動作する想定 → 実機で確認）
- `setActivationPolicy(.accessory)` の設定タイミングは `TypeToTalkApp.init()` で行う
- Settings ウインドウを開くときだけ `activate(ignoringOtherApps: true)` を使ってよい（ユーザー明示操作のため OK）→ ただし `SettingsLink` を使えば自動でアクティベートされるので追加コード不要

---

## Phase 2 メモ（次サイクル起票）

Phase 1 完了後、別サイクルで以下を起票する：

1. MenuBarExtra label の動的アイコン切替（`coordinator.currentStatus` 連動）
2. menuBarExtraStyle(.window) ベースの popover 化（簡易ステータス + 直近メッセージ表示）
3. エラー時のアイコン色変更 + tooltip 通知
4. アクセシビリティ権限未許可時のメニューバー誘導
5. Whisper/Bonsai モデル未ロード時のステータス可視化

---

## 完了基準（Phase 1）

1. ビルド成功
2. `grep` で `NSApp.activate` / `setActivationPolicy(.regular)` / `showRecorderWindow` 0 件
3. 実機で Dock 非表示・メニューバー表示・別アプリ入力欄への書き込みが動く
4. Settings ウインドウが開閉できる
