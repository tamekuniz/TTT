# Todo: HUDPanelController.show() 位置上書き抑止（初回のみ positionAtBottomCenter）

**作成日時**: 2026-04-26 11:44（ぶどう小人 プランナー）
**サイクル ID**: 20260426-1144-jjz9
**方針**: シア指定 — 最小修正方針（hasPositioned フラグ追加のみ）

---

## 要件（ズンジー原文の核）

ショートカットを押すたびに HUD が画面下中央へ戻ってしまう挙動をやめる。
初回表示時のみ画面下中央に配置し、以降は前回ユーザーがドラッグした位置（または直前の位置）をそのまま踏襲する。

---

## スコープ

### 対象（今サイクルで実装）

- `HUDPanelController` に `private var hasPositioned = false` を追加
- `show()` 内で `hasPositioned == false` の場合のみ `positionAtBottomCenter(panel:)` を呼び、呼んだ後に `hasPositioned = true` をセット
- それ以外は `panel.orderFrontRegardless()` だけを実行

### スコープ外（今サイクルでは扱わない）

以下は investigation §5 / §8 で「やった方がいい」レベルとして列挙されているが、ズンジー要件
（「ショートカット押すたびに移動するのやめて、前回 or 今のままを踏襲」）には含まれていないため、
今サイクルでは実装しない。次サイクル候補としてここに明記しておく。

- 画面外 clamp（visibleFrame からはみ出した時の自動補正）
- 複数モニタ切替監視（NSScreenDidChangeNotification 等で hasPositioned をリセット）
- セカンダリモニタ接続解除時の自動復帰
- 解像度変更時の自動 clamp
- frame の autosave / RestorableState 永続化

理由: 要件に含まれない改善を今サイクルに混ぜると、レビュー観点が増えて検証負荷が上がり、
最小修正の意図がぼやける。投資gation §5.2/§5.3 のリスクは認識した上で、別サイクルで個別に扱う。

---

## タスク（1 件）

### Task 1: HUDPanelController.show() を初回のみ positionAtBottomCenter 呼び出しに変更

**対象ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/HUDPanelController.swift`

**変更内容（差分イメージ）**:

1. クラスのプロパティ部に以下を追加:
   ```swift
   private var hasPositioned = false
   ```
   配置は既存プロパティ（あれば）の近く、または `init` の直前。NSWindowController サブクラスのインスタンス変数として。

2. `show()` メソッド（投資gation §2.1 の現状コード、行50-55）を以下に書き換え:
   ```swift
   func show() {
       guard let panel = window as? NSPanel else { return }
       if !hasPositioned {
           positionAtBottomCenter(panel: panel)
           hasPositioned = true
       }
       // フォーカスを奪わずに前面化する（makeKeyAndOrderFront は使わない）
       panel.orderFrontRegardless()
   }
   ```

**変更しない箇所**:
- `hide()` メソッド（hasPositioned はリセットしない。アプリ起動中は初回位置決定後ずっと true のまま）
- `positionAtBottomCenter(panel:)` メソッド本体（中身は変えない）
- `init` / NSPanel 設定（isMovableByWindowBackground 等）
- `TypeToTalkApp.swift` 側の呼び出し（show() の呼び出しは現状維持）

**追加実装の有無**:
- 新規メソッド: なし
- 削除メソッド: なし
- リネーム: なし

---

## Step 5（実装）への申し送り

- ファイル: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/HUDPanelController.swift` 1 ファイルのみ
- 変更行数の見込み: 約 5 行（プロパティ 1 行 + show() 内 if ブロック 3 行 + 既存 1 行のインデント微調整）
- ビルド影響: HUDPanelController クラスのみ。他ファイルへの API 変更なし
- 既存挙動の保持:
  - 初回 show() 時の見た目（画面下中央に表示される）は変わらない
  - hide() の挙動は変わらない
  - HUDView の中身・サイズ・スタイルは変わらない

## Step 6（検証）への申し送り

実機/シミュレータでの確認シナリオ（投資gation §7.1-A を採用、§7.2/§7.3 はスコープ外）:

1. アプリ起動 → グローバルショートカットで録音開始 → HUD が画面下中央に表示されることを確認
2. HUD をマウスドラッグで画面の別の位置（例: 左上）に移動
3. 同じショートカットで録音停止 → HUD が hide
4. 再度同じショートカットで録音開始 → HUD が **2 でドラッグした位置に表示される** ことを確認（画面下中央に戻らないこと）
5. もう一度 stop → start を繰り返しても、同じ位置のままであることを確認

**期待値**: 初回のみ画面下中央、以降はドラッグ位置を保持。

**スコープ外の確認（やらない）**:
- 画面外にドラッグした時の挙動（clamp 未実装のため画面外のまま表示される。これは仕様）
- セカンダリモニタへのドラッグ後の挙動
- モニタ接続解除後の挙動

これらは次サイクル候補として記録済み。

---

## 次サイクル候補メモ（実装しないが残しておく）

- HUD 位置の clamp 処理（visibleFrame 内に収める）
- HUD 位置の永続化（アプリ再起動後も保持）
- 複数モニタ対応（現在のスクリーンの visibleFrame に基づく clamp）
- モニタ接続解除検知 → 自動的に主画面へ復帰

これらが必要かどうかは、ユーザー（ズンジー）が実機で使ってみて困った時に再判断する。
