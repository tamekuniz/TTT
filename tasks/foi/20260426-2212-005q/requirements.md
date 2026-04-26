# requirements: AccessibilityManager カーソル挿入対応

## Goal

TTT が音声入力結果を他アプリのテキストフィールドに注入するとき、受け側のテキスト（CotEditor 等本格テキストエディタの既存ドキュメント、編集途中のフィールド内容）を **破壊しない**。カーソル位置に **挿入** し、選択範囲があればその範囲だけを置換する正しい挙動にする。

現状（commit fa4ba9b 時点）の `AccessibilityManager.insertText` は AX 経路で `kAXValueAttribute` をフィールド全体に set しているため、CotEditor のような本格的テキストエディタでは「ドキュメント全体が新規テキストに置き換わる」破壊的挙動になる。これを修正する。

## Constraints

1. **既存の二段 fallback 構造温存**: 「AX 経路を試す → 失敗したら CGEvent emulation」の順序は維持。CGEvent 一本化は IME 干渉と速度デメリットがあるため避ける
2. **AX 側を `kAXSelectedTextAttribute` に差し替え**: `kAXValueAttribute`（全置換）から `kAXSelectedTextAttribute`（カーソル位置挿入、選択範囲があれば置換）へ。Apple AX 標準属性で本格エディタは概ね対応
3. **既存ロジック温存**:
    - `text.isEmpty` 早期 return
    - `refreshPermissionStatus()` による権限再チェック
    - `AXUIElementCreateSystemWide()` + `kAXFocusedUIElementAttribute` で focused element 取得
    - 失敗時の InsertResult 列挙値（`.success` / `.missingPermission` / `.noFocusedElement` / `.unsupportedTarget`）
4. **CGEvent fallback 残置**: `kAXSelectedTextAttribute` set が失敗した場合（古い NSTextField の一部、特殊な Web 入力等で AX が薄いケース）は、現状の `typeTextUsingEvents(_ text:)` にフォールバック
5. **IME 干渉回避**: AX 経路で挿入できる場合は AX を使う（IME バッファを通らない）。CGEvent はあくまで保険

## Acceptance criteria

1. **CotEditor 動作確認**: CotEditor で何か文章を編集中に音声入力 → 既存ドキュメントが消えず、カーソル位置に音声入力テキストが挿入される。実機で確認
2. **短いテキストフィールド動作確認**: Safari の検索バー、メモ帳の表題等、短いテキストフィールドに音声入力 → カーソル位置に挿入される。既存テキストがあればそれを保持
3. **AXSelectedText 非対応フィールド動作確認**: もし AXSelectedText 非対応のフィールド（ターミナルや特殊な Electron 入力等）でも、CGEvent fallback で文字が入力される
4. **ビルド成功**: `./scripts/build_app.sh` Debug ビルド成功、既存テスト 17件全パス
