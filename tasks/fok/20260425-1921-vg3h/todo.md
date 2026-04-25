# Step 4 計画書: TypeToTalk ショートカット仕様改修

**作成日**: 2026-04-25
**プランナー**: Step 4 プランナー小人ちゃん（もも、博多弁）
**サイクル**: fok/20260425-1921-vg3h

---

## 1. 要件サマリ（決定済み）

- 1つのショートカットで「ウインドウ表示＋録音開始」、再押下で「録音停止」を実現する
- TTT は **リリース前**。既存ユーザー保護・互換性は **不要**
- スコープ外: 権限ボタン、ビルドナンバー、ステータス表示、ウインドウタイトル

---

## 2. 採用方針（シア指定・確定済み）

investigation.md は方針B（新統合ショートカット + 旧2つ互換）を推奨しているが、**リリース前なので互換性は捨てる**。以下を採用する。

### 2.1 ショートカット定義
- `KeyboardShortcuts.Name.triggerRecording` **1つに統合**
- `KeyboardShortcuts.Name.toggleWindow` は **削除**（定義・ハンドラ・Settings UI すべて）

### 2.2 triggerRecording の新挙動（toggle モード時）
| 押下時の状態 | 動作 |
|--------------|------|
| ウインドウ閉 | ウインドウを開く + 録音開始 |
| ウインドウ開 + 録音中でない | 録音開始 |
| 録音中 | 録音停止 |

### 2.3 録音停止後のウインドウ挙動（暫定）
- **閉じない**方針で進める
- 理由: 停止直後の statusMessage（"文字起こし中..."）や整形結果を確認したい
- ズンジーが Step 8 検証時に「閉じてほしい」と判断したら、次サイクルで反転する

### 2.4 トリガーモード
- 既存の `shortcutTriggerMode` (`disabled` / `toggle` / `pushToTalk`) は **そのまま維持**
- `toggle` モードの「再押下で停止」が今回の主要動線
- `pushToTalk` モードは押下中録音 / 離す停止のまま（既存挙動維持）
- `disabled` モードは「ショートカット無効」のまま

---

## 3. 実装タスク（1サイクル完結 / 2タスク）

### Task 1: triggerRecording のハンドラ統合 + toggleWindow 削除
**対象ファイル**:
- `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`

**変更内容**:
1. `KeyboardShortcuts.Name.toggleWindow` の定義を削除（行7）
2. `KeyboardShortcuts.onKeyDown(for: .toggleWindow)` の登録ブロック削除（行226-230）
3. `handleToggleWindow()` メソッド削除（行430-448）
4. `handleTriggerShortcutDown()` を以下に書き換え（行315-332）:
   - `toggle` モード時、現在の `showRecorderWindow() + toggleRecording()` ロジックを以下に変更
     - ウインドウが閉じている → `showRecorderWindow()` でウインドウを開く + 録音開始
     - ウインドウが開いていて録音中でない → 録音開始（ウインドウ表示は維持）
     - 録音中 → 録音停止のみ（ウインドウは閉じない）
   - `pushToTalk` モード時の挙動は変更なし（押下時に開始）
   - `disabled` モード時の挙動は変更なし
5. `handleTriggerShortcutUp()` は変更なし（pushToTalk 解放時の停止）
6. ウインドウが開いているかの判定ロジックは `NSApplication.shared.windows.first { $0.identifier?.rawValue == "RecorderWindow" }?.isVisible == true` を内部 helper に切り出して再利用する

**注意点**:
- `handleToggleWindow()` 内のウインドウ表示処理（`setActivationPolicy(.regular)` + `activate(ignoringOtherApps:)` + `makeKeyAndOrderFront`）を `showRecorderWindow()` 側に内包する必要があるかチェック。`showRecorderWindow()` (行418-428) が同等のアクティベートを行っているか実装時に確認する
- もし `showRecorderWindow()` がアクティベートしていなければ、handleTriggerShortcutDown の「ウインドウ閉→開」ケースで activate を呼ぶ処理を追加する

---

### Task 2: SettingsView から toggleWindow UI を削除
**対象ファイル**:
- `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Views/SettingsView.swift`

**変更内容**:
1. 「ウインドウ表示トグル」の `settingRow` ブロック削除（行232相当）
2. 「ショートカット」（triggerRecording）の `settingRow` は維持
3. 「動作」（shortcutTriggerMode Picker）は維持
4. 説明文（行250 の caption）に変更が必要か確認。「右 Option 単体でも...」の文言が現状と齟齬を生まないかチェック

**注意点**:
- 残るUI構成: ショートカット（triggerRecording）/ 動作（モード Picker）/ 説明文
- セクションタイトル「ショートカット」は維持

---

## 4. 検証計画（Step 6-7 で実施）

### ビルド検証
- `swift build` または Xcode ビルドが成功すること
- `KeyboardShortcuts.Name.toggleWindow` への参照がコンパイル時に残っていないこと（残っていればビルドエラー）

### 動作検証（実機）
| シナリオ | 操作 | 期待挙動 |
|----------|------|----------|
| S1 | 設定で triggerRecording に Cmd+Shift+R を割当 + toggle モード設定 | 設定保存される |
| S2 | ウインドウ閉じた状態で Cmd+Shift+R 押下 | ウインドウ表示 + 録音開始 |
| S3 | S2 の状態でもう一度 Cmd+Shift+R 押下 | 録音停止（ウインドウは表示のまま） |
| S4 | S3 後にもう一度 Cmd+Shift+R 押下 | 録音再開（ウインドウ表示維持） |
| S5 | pushToTalk モードに切替、キー押下→離す | 押下中録音 / 離して停止（既存挙動） |
| S6 | disabled モードでキー押下 | 何も起きない |
| S7 | Settings 画面から「ウインドウ表示トグル」設定が消えていること | UI 確認 |

### コード検証
- `grep -r "toggleWindow" Sources/` で残存参照がゼロであること
- `grep -r "handleToggleWindow" Sources/` で残存参照がゼロであること

---

## 5. リスク・不確かポイント

- **不確か**: `showRecorderWindow()` (TypeToTalkApp.swift 行418-428) が `NSApplication.shared.activate(ignoringOtherApps:)` を呼んでいるか未確認。実装時に Read して確認する
- **不確か**: UserDefaults に残る `"KeyboardShortcuts_toggleWindow"` キーの掃除は不要（リリース前なのでユーザーデータが存在しない）。明示的削除は実装しない
- **判断保留**: 録音停止後のウインドウ自動クローズは Step 8 でズンジーがレビュー後に判断

---

## 6. 完了条件（Definition of Done）

- [ ] Task 1 完了（TypeToTalkApp.swift 改修）
- [ ] Task 2 完了（SettingsView.swift 改修）
- [ ] swift build / Xcode ビルド成功
- [ ] grep で `toggleWindow` 残存ゼロ確認
- [ ] 実機で S1〜S7 の動作確認
- [ ] progress.md に各 Task の進捗記録完了
