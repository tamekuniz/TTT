# Step 4 進捗記録

**タスク**: アクセシビリティ権限取得フローの完全自動化
**フォルダ**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/tasks/fok/20260426-1132-c0aw/`

---

## Step 4: プランニング (完了)

**実施日**: 2026-04-26
**担当**: デコポンずら（プランナー小人ちゃん）

### 入力
- 要件: アクセシビリティ権限取得フロー完全自動化
- investigation.md（Step 3 成果物）
- シア指定方針:
  1. 起動時 hasPermission==false 検出
  2. 既存 `showAccessibilityPermissionAlert` 経路活用
  3. 「システム設定を開く」で `openAccessibilitySettings()` 呼ぶ
  4. 同時に `AccessibilityManager.startPermissionPolling()` 開始
  5. polling は Task で sleep 1秒ループ → AXIsProcessTrusted true 検出で停止 + restartApp()
  6. 5分でタイムアウト

### 成果物
- `todo.md`: 設計サマリ + Task 1（AccessibilityManager polling 追加）+ Task 2（TypeToTalkApp 起動時フロー組み込み）+ 検証計画
- `progress.md`: 本ファイル

### 設計判断ハイライト
- **既存 `showAccessibilityPermissionAlert` 流用**: 新規 @Published 追加なし
- **SwiftUI `.alert()` を MenuBarLabel に bind**: NSAlert は accessory アプリで挙動不確かなので回避
- **polling は AccessibilityManager に閉じ込め**: 重複起動防止フラグ `isPolling` で物理防御
- **タイムアウト 5分**: 永続 polling のオーバーヘッド回避

### 想定サイクル
1サイクル完結（Task 1 + Task 2 を一気に実装）

### 不確かな点
- SwiftUI `.alert()` が MenuBarExtra で正しく表示されるか（実機検証必須）
- 表示されない場合は次サイクルで NSAlert フォールバック検討

### 次フェーズ
Step 5: 実装（実装小人ちゃんに `todo.md` を Read させて Task 1 → Task 2 の順で実装）
