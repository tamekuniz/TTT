# TypeToTalk メニューバー常駐型 Phase 2 実装計画

**作成者**: いちごプランナー小人ちゃん
**作成日**: 2026-04-25
**サイクル ID**: 20260425-2256-ljr2
**実装規模見積**: 約60-90行（MenuBarLabel 改修 + Menu 内項目追加）
**1サイクル完結**: ✅（Phase 2 + Phase 2.1 を統合して1サイクルで実装）

---

## 1. ゴール

メニューバー常駐型 TypeToTalk のメニューバーアイコンとメニュー本体を、AppStatus と権限状態に応じて動的に変化させる。ユーザーが「録音中」「処理中」「エラー」「権限不足」を**メニューバー上で一目で認識でき**、必要なら**メニュー内から直接権限設定へ誘導**できる UX を実現する。

---

## 2. スコープ（やること）

### 2.1 MenuBarLabel のアイコン動的切替（switch 文 + foregroundStyle 試験）

**対象ファイル**: `Sources/TypeToTalk/App/TypeToTalkApp.swift` 行385-413（MenuBarLabel View）

**実装内容**:
- `coordinator.currentStatus` と `coordinator.accessibility.hasPermission` を購読
- 既存の `Image(systemName: "mic.circle")` を **computed property または switch 式** で AppStatus と権限状態に応じた SF Symbol に置換
- `.foregroundStyle()` 試験を併記（template mode 上書きが効くか実機で確認）

**SF Symbol マッピング表**:

| 状態 | SF Symbol | 色（試験） |
|------|----------|-----------|
| `idle` + 権限あり | `mic.circle` | デフォルト（テンプレート） |
| `idle` + 権限なし | `exclamationmark.circle` | `.orange` 試験 |
| `recording` | `mic.circle.fill` | `.red` 試験 |
| `processing` | `arrow.triangle.2.circlepath` | `.orange` 試験 |
| `error(_)` | `exclamationmark.circle` | `.red` 試験 |

**注意**:
- macOS メニューバーは template mode 強制の可能性あり → 色付きが効かなければ Phase 3 で `.symbolRenderingMode(.multicolor)` を再試行
- **形状の差別化を最優先**（色は副次）。`mic.circle` ↔ `mic.circle.fill` ↔ `exclamationmark.circle` ↔ `arrow.triangle.2.circlepath` で4状態を視覚的に区別

### 2.2 メニュー内に動的項目を追加

**対象ファイル**: `Sources/TypeToTalk/App/TypeToTalkApp.swift` 行426-449（@main TypeToTalkApp の MenuBarExtra body）

**実装内容**:

#### A. 直近ステータス表示行（idle 以外で表示）

```
recording → 「● 録音中」
processing → 「⏳ 処理中...」
error(msg) → 「⚠ エラー: <msg>」
idle → 表示しない
```

実装は `Text("...")` を `currentStatus` の case で出し分け。`.disabled(true)` を付けて操作不可（ステータス専用）にする。
idle の場合は何も描画しない（条件分岐で if）。

#### B. 権限誘導項目（hasPermission == false の場合のみ表示）

```swift
if !coordinator.accessibility.hasPermission {
    Button("アクセシビリティ権限を設定...") {
        coordinator.accessibility.openAccessibilitySettings()
    }
    Divider()
}
```

権限あり時は表示しない（既存メニューがゴチャつかない）。

#### C. 既存メニューは保持

- `SettingsLink { Text("設定...") }` （変更なし）
- `Divider()` （変更なし）
- `Button("TypeToTalk を終了") { NSApplication.shared.terminate(nil) }` （変更なし）

### 2.3 MenuBarExtra body に coordinator を購読させる

**現状の問題**: 行426-449 の `MenuBarExtra { ... }` クロージャは `coordinator` を直接参照しているが、`@StateObject` の更新が body 全体の再評価をトリガするか要確認。

**対応**:
- `TypeToTalkApp` 構造体は既に `@StateObject private var coordinator = TypeToTalkCoordinator()` を持つ前提
- もし保持していなければ、body 内の MenuBarExtra コンテンツを別 View（例: `MenuContentView`）として切り出し、`@ObservedObject var coordinator` で購読
- **判断**: 実装時に既存コードを再 Read して、coordinator が StateObject か確認 → 再評価が効かない場合のみ View 切り出し

---

## 3. スコープ外（やらないこと）

- **symbolEffect アニメーション**（pulse / rotate）: investigation §5-C で「Phase 2.1 以降」とある。今サイクルでは静的シンボル切替のみ
- **メニューバーアイコンに HStack でテキスト並置**: §5-A の幅制約リスクあり。ステータス文言はメニュー内にのみ表示
- **Whisper モデル再読込ボタン**: シナリオ 8 で言及されるが Phase 2 の本筋外。SettingsView から実行する既存動線で十分
- **Phase 1 で実装済みの onChange / scenePhase ハンドラ**: 既存のまま保持。再実装しない
- **toggleRecording() 内の currentStatus 更新ロジック**: 既に 10 箇所で正しく動いているので触らない

---

## 4. 実装ステップ詳細

### Step A: MenuBarLabel の改修（実装行数: 約30行）

1. `MenuBarLabel` View 内に **computed property** `iconName: String` と `iconColor: Color?` を追加
2. switch 式で `coordinator.currentStatus` と `coordinator.accessibility.hasPermission` から SF Symbol 名と色を導出
3. body の `Image(systemName: "mic.circle")` を `Image(systemName: iconName)` に変更
4. `.foregroundStyle(iconColor ?? .primary)` を chain（試験）
5. 既存 onChange / onAppear はそのまま保持

**Pseudo code**:
```swift
private var iconName: String {
    switch coordinator.currentStatus {
    case .idle:
        return coordinator.accessibility.hasPermission ? "mic.circle" : "exclamationmark.circle"
    case .recording:    return "mic.circle.fill"
    case .processing:   return "arrow.triangle.2.circlepath"
    case .error:        return "exclamationmark.circle"
    }
}

private var iconColor: Color? {
    switch coordinator.currentStatus {
    case .idle:         return coordinator.accessibility.hasPermission ? nil : .orange
    case .recording:    return .red
    case .processing:   return .orange
    case .error:        return .red
    }
}
```

### Step B: メニュー本体（@main TypeToTalkApp）の改修（実装行数: 約30-40行）

1. MenuBarExtra のクロージャ内に **ステータス表示行** を追加（`if case` で recording/processing/error を分岐）
2. **権限誘導項目** を `if !hasPermission` で囲んで条件追加
3. 既存の SettingsLink / Divider / 終了ボタンはそのまま保持

**Pseudo code**:
```swift
MenuBarExtra {
    // A. ステータス表示（idle 以外）
    if case .recording = coordinator.currentStatus {
        Text("● 録音中").disabled(true) // 表示専用
    } else if case .processing = coordinator.currentStatus {
        Text("⏳ 処理中...").disabled(true)
    } else if case .error(let msg) = coordinator.currentStatus {
        Text("⚠ エラー: \(msg)").disabled(true)
    }

    if case .idle = coordinator.currentStatus {
        // 何も出さない
    } else {
        Divider()
    }

    // B. 権限誘導（権限なし時のみ）
    if !coordinator.accessibility.hasPermission {
        Button("アクセシビリティ権限を設定...") {
            coordinator.accessibility.openAccessibilitySettings()
        }
        Divider()
    }

    // 既存メニュー
    SettingsLink { Text("設定...") }
    Divider()
    Button("TypeToTalk を終了") { NSApplication.shared.terminate(nil) }
} label: {
    MenuBarLabel(coordinator: coordinator)
}
```

**注意**:
- SwiftUI の MenuBarExtra クロージャ内で `if case` がそのまま効くか不確か。効かない場合は `switch coordinator.currentStatus` を `Group { ... }` で包む
- `Text("...").disabled(true)` でメニュー項目として「表示専用」（クリック無効・グレー表示）になる

### Step C: 動作検証（テスト戦略は §5）

---

## 5. テスト戦略（実機目視確認）

### 必須テストシナリオ

| # | シナリオ | 期待結果 |
|---|--------|---------|
| 1 | アプリ起動（権限あり） | アイコン: `mic.circle`、メニューに「設定...」「終了」のみ |
| 2 | アプリ起動（権限なし） | アイコン: `exclamationmark.circle`（オレンジ）、メニューに「アクセシビリティ権限を設定...」が出る |
| 3 | ショートカット押下 | アイコン: `mic.circle.fill`（赤）、メニューに「● 録音中」 |
| 4 | 停止押下 | アイコン: `arrow.triangle.2.circlepath`（オレンジ）、メニューに「⏳ 処理中...」 |
| 5 | 処理完了 | アイコン: `mic.circle`、ステータス行消滅 |
| 6 | エラー発生（例: 入力先なし） | アイコン: `exclamationmark.circle`（赤）、メニューに「⚠ エラー: 入力先なし」 |
| 7 | 権限誘導クリック | システム設定の「プライバシーとセキュリティ → アクセシビリティ」が開く |
| 8 | 権限付与後にメニュー再表示 | scenePhase.active 発火 → hasPermission true → 権限誘導項目消滅、アイコン正常化 |

### ビルド確認

- `xcodegen generate` でプロジェクト再生成（project.yml は触らない）
- `xcodebuild` または Xcode GUI でビルド成功
- 警告ゼロを目標（template mode の foregroundStyle 警告が出る可能性あり → 出たら記録）

---

## 6. リスクと対応策

### リスク 1: メニューバーアイコンの色付けが template mode で無視される
- **影響**: 形状切替のみで状態区別、色情報は失われる
- **対応**: 形状の差別化で十分視認可能（mic.circle ↔ mic.circle.fill ↔ arrow.triangle.2.circlepath ↔ exclamationmark.circle）。色は bonus。Phase 3 で `.symbolRenderingMode(.multicolor)` 試験

### リスク 2: MenuBarExtra クロージャ内の `if case` 構文が効かない
- **影響**: ステータス表示行が出ない / コンパイルエラー
- **対応**: `Group { switch ... }` でラップする代替パターンを準備。最悪 `Text(statusText)` を computed property で文字列化

### リスク 3: coordinator の更新が MenuBarExtra body に反映されない
- **影響**: アイコンは変わるがメニュー項目が更新されない
- **対応**: MenuBarExtra のコンテンツ部分を別 View（`MenuContentView`）に切り出して `@ObservedObject` で明示購読

### リスク 4: 「⚠ エラー: <長文>」がメニュー幅を超える
- **影響**: メニューが横に伸びすぎる
- **対応**: 既存 error メッセージは「録音ファイルが見つかりません」「アクセシビリティ権限なし」など最大 15 文字程度。実用上問題なし。必要なら `.lineLimit(1)` を追加

---

## 7. 完了条件

- [ ] MenuBarLabel が AppStatus と hasPermission に応じて 5 種類のアイコンを切り替える（テストシナリオ 1-6 全パス）
- [ ] メニュー内にステータス表示行が動的に出現/消滅する（idle 以外で表示）
- [ ] 権限なし時に「アクセシビリティ権限を設定...」項目が表示され、クリックでシステム設定が開く（テストシナリオ 7 パス）
- [ ] 権限付与後、scenePhase.active で自動リカバリする（テストシナリオ 8 パス）
- [ ] ビルド成功・警告ゼロ（template mode 警告は許容、記録のみ）
- [ ] 既存機能（録音/処理/設定/終了）が壊れていない

---

## 8. 工数見積

- 実装: 60-90 分（既存 View の改修中心、新規ファイル不要）
- ビルド + 実機目視確認: 30-45 分
- **合計**: 約 1.5-2 時間（1 サイクル完結に十分）

---

## 9. 参考資料

- `tasks/fok/20260425-2256-ljr2/investigation.md` （調査報告書、特に §2-D, §2-F, §5）
- `Sources/TypeToTalk/App/TypeToTalkApp.swift` 行385-449
- `Sources/TypeToTalk/Managers/AccessibilityManager.swift` 行13-34
- `Sources/TypeToTalk/Views/SettingsView.swift` 行269-287（既存の権限 UI パターン）

---

**プランナー署名**: いちごプランナー小人ちゃん
