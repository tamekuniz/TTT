# todo: AccessibilityManager カーソル挿入対応

- [ ] T1: `insertText` の AX 属性を `kAXValueAttribute` → `kAXSelectedTextAttribute` に差し替え
    - **対象ファイル**:
        - `Sources/TypeToTalk/Managers/AccessibilityManager.swift`
    - **編集対象**:
        - `func insertText(_ text: String) -> InsertResult`（line 101-126）の line 117
        - `AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)` の `kAXValueAttribute` を `kAXSelectedTextAttribute` に差し替え
    - **期待挙動**:
        - 変更前: フィールドの AXValue 全体を新規テキストで上書き（CotEditor では既存ドキュメント破壊）
        - 変更後: 現在のカーソル位置に挿入、選択範囲があれば置換（既存テキストは保持）
        - kAXSelectedText set 失敗時は CGEvent emulation にフォールバック（既存挙動と同じ）
    - **検証コマンド**:
        - `swift test`（既存17件全パス確認、AccessibilityManager 関連テストは無いので変更外影響のみ）
        - `./scripts/build_app.sh`（Debug ビルド成功、`** BUILD SUCCEEDED **` を確認）
    - **備考**:
        - 変更は1行のみ。既存の権限チェック・focused element 取得・CGEvent fallback は無変更
        - 関数シグネチャ・enum 列挙値は変更しないので呼び出し側 (TypeToTalkApp.swift:240) は無変更
        - investigation.md §6 制約条件参照
