# investigation: AccessibilityManager カーソル挿入対応

## 1. 関連ファイル一覧

| パス | 役割 |
|---|---|
| `Sources/TypeToTalk/Managers/AccessibilityManager.swift`（line 101-126 `insertText`） | テキスト注入ロジックの正本。AX → CGEvent fallback の二段構え。今回の修正対象 |
| `Sources/TypeToTalk/Managers/AccessibilityManager.swift`（line 128-152 `typeTextUsingEvents`） | CGEvent emulation（フォールバック）。今回温存 |
| `Sources/TypeToTalk/App/TypeToTalkApp.swift:240` | `accessibility.insertText(finalText)` の唯一の呼び出し点。返り値 4 ケースを `switch` で処理 |
| `Sources/TypeToTalk/Views/SettingsView.swift:8` | `@ObservedObject var accessibility: AccessibilityManager` を参照（権限状態 UI 表示用、`insertText` は呼ばない） |
| `Tests/TypeToTalkTests/`（AudioRecorderTests, ModelSelectionTests） | 既存テスト 2 ファイル。**AccessibilityManager のテストは存在しない**（grep で確認） |

## 2. 既存実装パターン

`insertText(_ text: String) -> InsertResult` の処理フロー（line 101-126）:

```
1. text.isEmpty → .success で return
2. refreshPermissionStatus()  ← AXIsProcessTrusted() を再取得
3. !hasPermission → .missingPermission で return
4. AXUIElementCreateSystemWide() で system-wide AX element 取得
5. AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute, ...) で focused element 取得
6. 失敗 or nil → .noFocusedElement で return
7. AXUIElementSetAttributeValue(element, kAXValueAttribute, text) を試す
   ↑これが「フィールド全体の AXValue を新規テキストで上書きする」破壊的挙動
8. 成功 → .success で return
9. 失敗 → typeTextUsingEvents(text) を試す（CGEvent emulation, line 128-152）
10. 成功 → .success で return
11. 失敗 → .unsupportedTarget で return
```

**InsertResult enum**（line 6-11）:
- `.success` / `.missingPermission` / `.noFocusedElement` / `.unsupportedTarget`

**CGEvent emulation 詳細**（`typeTextUsingEvents`、line 128-152）:
- `CGEventSource(stateID: .combinedSessionState)` で source 作成
- 各 Unicode scalar に対し:
    - `CGEvent(keyboardEventSource:..., virtualKey: 0, keyDown: true/false)` で keyDown/keyUp イベント作成
    - `keyboardSetUnicodeString(stringLength: 1, unicodeString: ...)` で Unicode 文字を設定
    - `post(tap: .cghidEventTap)` で送信
- 失敗時は `false` を返す

## 3. 影響範囲

**書き換える箇所（1ファイル、1関数、1行）**:
- `Sources/TypeToTalk/Managers/AccessibilityManager.swift:117` の `kAXValueAttribute` を `kAXSelectedTextAttribute` に差し替え

**触らない箇所**:
- `typeTextUsingEvents`（CGEvent fallback、line 128-152）— Constraints 4 によりそのまま
- `InsertResult` enum と返り値の意味論 — 4 ケースは温存
- `TypeToTalkApp.swift:240` の `switch` 文 — 返り値の意味論が変わらないので呼び出し側変更不要
- `refreshPermissionStatus()` / `AXUIElementCreateSystemWide()` / `kAXFocusedUIElementAttribute` 取得ロジック — 全部温存

**呼び出しチェーン**（変更後も同じ）:
```
TypeToTalkCoordinator (録音→Whisper→整形 AI→) processText
  → accessibility.insertText(finalText)
    → AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute, text)
      ↑成功すればカーソル位置に挿入
    → 失敗時 typeTextUsingEvents(text)
    → さらに失敗時 .unsupportedTarget
```

## 4. 過去の類似実装

**memory grep**:
- AX 関連の memory なし
- 過去 commit に `[フォK] feat: アクセシビリティ権限取得を完全自動化` (edbdada) あり。権限取得自動化のサイクル
- `insertText` の本質ロジックは `4b03313 [フォK] feat: TypeToTalk リファクタ完了＋整形AI整合性とウインドウトグル追加` で確立後、変更なし

**外部リファレンス（Apple AX Programming Guide）**:
- `kAXSelectedTextAttribute`（文字列定数 `"AXSelectedText"`）: 選択テキストの取得・設定に使う標準属性
    - **set すると現在の選択範囲を新規テキストで置換**（選択範囲が0文字＝カーソルだけならカーソル位置に挿入）
    - 本格テキストエディタ（TextEdit / CotEditor / Xcode / VS Code 等）が概ね対応
    - 軽量フィールドや Web の一部 textarea では非対応のことがある（その場合 `AXUIElementSetAttributeValue` が `kAXErrorAttributeUnsupported` を返す）
- 参考: macOS 公式 [NSAccessibilityProtocol](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol) の `NSAccessibility.Attribute.selectedText`

## 5. 想定される副作用 / リスク

- **AXSelectedText 非対応フィールドへの影響**: 古い NSTextField の一部や Web の特殊な textarea で `kAXSelectedTextAttribute` の set が失敗 → 既存のフォールバックパス（CGEvent）に流れる。挙動が「全置換 → 挿入」に変わるが、CGEvent 自体は元から「挿入」挙動なので、ユーザー体感は **改善** のみ
- **focused element がコンテナ要素の場合**: 一部のアプリでは `kAXFocusedUIElementAttribute` が text element ではなく親コンテナを返す。その場合 `kAXSelectedTextAttribute` set も失敗する（→ CGEvent fallback）。これは `kAXValueAttribute` でも同じだったので新たな regression にはならない
- **権限・focused element 取得は無変更**: AC 範囲外の挙動劣化なし
- **テスト**: AccessibilityManager は既存テスト無し。Unit Test は AX API のモック必要で重いため、今回は **追加せず**（既存方針を踏襲）。検証は実機 CotEditor で行う

## 6. 制約条件

- **Swift 6 Concurrency-safe**: `AccessibilityManager` は `@MainActor` クラス（line 4）。関数本体は MainActor 制約を継承
- **既存命名規約**: `insertText` の関数シグネチャ・返り値型・enum 列挙値は変更不可（呼び出し側 TypeToTalkApp.swift:240 が依存）
- **kAXSelectedTextAttribute の Swift 表記**: HIToolbox の C 定数として `kAXSelectedTextAttribute` がそのまま使える（AppKit import 済みで参照可能）。型は `CFString` キャスト必要（既存の `kAXValueAttribute as CFString` パターンと同じ）
- **TTT はリリース前**: 既存ユーザー考慮不要 (memory: `[feedback_ttt_always_bump_version]` の精神に沿うが互換論点はない)
- **コミット規約**: `[フォI] fix: 〜` （既存テキスト破壊バグ修正なので fix）

## 7. テスト戦略

**Unit Test**: 該当なし
- 理由: `AXUIElementSetAttributeValue` のような C API は XCTest で素直にモックできない（DI しないと差し替え不能）。今回 DI を入れるリファクタはスコープ外
- 既存テスト 2 ファイルにも AccessibilityManager 関連は無い（`grep -rln "Accessibility\|insertText" Tests/` で 0 件）
- フォI チェックリスト「テスト書ける場合 / 書けない場合（実機/ビルド検証）」の **後者** に該当

**ビルド検証（シア自身が Step 7 で実施）**:
- `./scripts/build_app.sh` Debug ビルド成功
- 既存 Unit Test 全パス（17件、変更外なので影響なし想定）

**実機検証（Step 8 でズンジー依頼）**:
- ビルド済み `.app` を起動 → アクセシビリティ権限済み確認
- **CotEditor 検証**: 既存ファイルを開いた状態で文章を編集中、音声入力ショートカット（`Cmd+Option+V` デフォルト）→ カーソル位置に音声テキストが挿入され、既存ドキュメントは保持される
- **NSTextField 検証**: Safari の検索バー or Spotlight 等の単純フィールドに音声入力 → 既存テキストの後ろ（カーソル位置）に挿入される
- **既存テキストありで選択中の検証**: テキスト一部選択した状態で音声入力 → 選択範囲が音声テキストで **置換** される（仕様通り）
