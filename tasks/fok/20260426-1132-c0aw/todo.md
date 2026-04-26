# Step 4 計画書: アクセシビリティ権限取得フローの完全自動化

**タスク**: 起動時に hasPermission==false → 誘導アラート → 「システム設定を開く」 → 裏で 1秒間隔 polling → AXIsProcessTrusted true 検出で即 restartApp()
**作成日**: 2026-04-26
**プランナー**: デコポンずら（フォルダ静岡弁）
**入力**: investigation.md（同フォルダ）、シア指定方針

---

## 0. 設計サマリ

### フロー
1. アプリ起動 → MenuBarLabel.onAppear → `handleAppLaunch()`
2. `handleAppLaunch()` 内で `accessibility.refreshPermissionStatus()` 呼んで現状確認
3. `hasPermission == false` なら `showAccessibilityPermissionAlert = true`（既存フラグ流用）
4. MenuBarExtra の MenuBarLabel に `.alert(..)` を bind → SwiftUI alert 表示
5. アラートのプライマリボタン「システム設定を開く」 → `openAccessibilitySettings()` + `accessibility.startPermissionPolling { restartApp() }`
6. アラートの「あとで」 → 何もしない（polling は走らせない）
7. polling は `AccessibilityManager` 内で `Task` + `Task.sleep(1秒)` ループ
   - 重複起動防止フラグ (`isPolling`) で再入禁止
   - 5分（300秒）でタイムアウト → 自動停止
   - `AXIsProcessTrusted()` が true を返した瞬間ループ break + completion (=`restartApp`) 呼び出し
8. polling 中はユーザーがメニューから「アクセシビリティ権限を設定...」を押した場合も再 polling 起動しない（フラグで防止）

### 設計判断（シア指定方針準拠）
- **既存 `showAccessibilityPermissionAlert` を流用**: 新規 @Published 追加せず、既存フラグを再利用
- **SwiftUI `.alert()` を MenuBarLabel に bind**: NSAlert は accessory アプリで挙動不確かなので回避（不確かなら NSAlert にフォールバック方針）
- **polling は AccessibilityManager に閉じ込める**: TypeToTalkCoordinator は trigger するだけ。テスタブル
- **タイムアウト 5分**: 永続 polling のオーバーヘッド回避（investigation.md 5.1 準拠）
- **handleAppLaunch / scenePhase との競合回避**: `isPolling` フラグで重複起動を物理的に防ぐ

### スコープ外（やらない）
- AXIsProcessTrusted のキャッシュ問題そのものの解決（restartApp で対応するのが既存方針）
- polling 中の isRecording チェック（起動直後の polling では発生しない、investigation 5.3 準拠）
- NSAlert フォールバック実装（SwiftUI .alert で動かなかったときの次サイクル課題）

---

## 1. タスク分解

### Task 1: AccessibilityManager に polling メカニズム追加
**対象**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/AccessibilityManager.swift`

**変更内容**:
- 新規プロパティ追加:
  - `private var pollingTask: Task<Void, Never>?`
  - `private(set) var isPolling: Bool = false`（観測用、@Published 不要）
- 新規メソッド `startPermissionPolling(onGranted: @escaping @MainActor () -> Void, timeoutSeconds: Int = 300)`:
  - `isPolling == true` なら何もせず return（重複起動防止）
  - `pollingTask?.cancel()` で念のため既存タスクキャンセル
  - `isPolling = true` セット
  - `Task { @MainActor in ... }` で開始:
    - `let start = Date()`
    - `while !Task.isCancelled` ループ:
      - `try? await Task.sleep(nanoseconds: 1_000_000_000)` (1秒)
      - `if AXIsProcessTrusted()` → `hasPermission = true; isPolling = false; onGranted(); return`
      - `if Date().timeIntervalSince(start) >= Double(timeoutSeconds)` → `isPolling = false; return`
    - 終了時に `isPolling = false`
- 新規メソッド `stopPermissionPolling()`:
  - `pollingTask?.cancel()`
  - `pollingTask = nil`
  - `isPolling = false`

**理由**: polling ロジックを AccessibilityManager に閉じ込めることで責務が明確、テスタブル、再利用可能。

**検証**: ビルド成功 + 後段の Task 2 で実機動作確認。

---

### Task 2: TypeToTalkApp に起動時誘導フロー組み込み
**対象**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`

**変更内容**:

#### 2-A: `handleAppLaunch()` 修正 (L167-173 付近)
```swift
func handleAppLaunch() {
    startupLoadTask?.cancel()
    startupLoadTask = Task { @MainActor [weak self] in
        guard let self else { return }
        await self.synchronizeModelsForCurrentSettings()
        self.currentStatus = .idle

        // 権限チェック → 誘導アラート起動
        self.accessibility.refreshPermissionStatus()
        if !self.accessibility.hasPermission {
            self.showAccessibilityPermissionAlert = true
        }
    }
}
```

#### 2-B: MenuBarLabel に `.alert(..)` modifier 追加 (L481-512 の body 内)
```swift
.alert(
    "アクセシビリティ権限が必要です",
    isPresented: $coordinator.showAccessibilityPermissionAlert
) {
    Button("システム設定を開く") {
        coordinator.accessibility.openAccessibilitySettings()
        coordinator.accessibility.startPermissionPolling { [weak coordinator] in
            coordinator?.restartApp()
        }
    }
    Button("あとで", role: .cancel) { }
} message: {
    Text("TypeToTalk がテキストを入力するには、システム設定でアクセシビリティを許可してください。許可後はアプリを自動的に再起動します。")
}
```

**注意点**:
- MenuBarLabel は `@ObservedObject var coordinator` を持っている前提（既存）
- `$coordinator.showAccessibilityPermissionAlert` で binding する（@Published なので使える）
- Alert のメッセージは日本語固定（既存 SettingsView と整合、i18n は対象外）

#### 2-C: scenePhase 監視は据え置き
- L505-510 の `.onChange(of: scenePhase)` はそのまま（refreshPermissionStatus 呼ぶだけ、polling とは別）
- AXIsProcessTrusted キャッシュ問題は restartApp が解決するので、scenePhase 経由の更新は補助的に残しておいて害はない

**検証**:
- ビルド成功
- 実機: 権限剥奪 → アプリ起動 → アラート表示 → 「システム設定を開く」 → システム設定で ON → 1秒以内に自動再起動
- 「あとで」を押して polling が走らないこと（メニューバーのアプリが落ちないことで間接確認）

---

## 2. 検証計画（Step 5 で実施）

### ビルド検証
```bash
cd /Users/tamekuniz/GitHub/tamekuniz/TTT && swift build 2>&1 | tail -50
```

### 実機検証手順（Step 7 deploy 後）
1. システム設定 → プライバシーとセキュリティ → アクセシビリティ → TypeToTalk を OFF
2. アプリ起動 → 誘導アラート出ることを確認
3. 「システム設定を開く」をクリック → システム設定が開くこと
4. システム設定で TypeToTalk を ON
5. 1〜2秒以内にアプリが自動再起動することを確認
6. 再起動後、メニューバーから「アクセシビリティ権限を設定...」項目が消えていることを確認（hasPermission == true）

### エッジケース検証
- アラートで「あとで」を押したとき、polling が起動しないこと
- アラート表示後にユーザーがメニューから「アクセシビリティ権限を設定...」を別途押したとき、二重 polling にならないこと（isPolling フラグで防御）
- 5分放置で polling が自動停止すること（ログで確認、または stopwatch で）

---

## 3. リスクと対応

| リスク | 影響 | 対応 |
|--------|------|------|
| SwiftUI .alert が MenuBarExtra で表示されない | 致命的（フロー破綻） | NSAlert にフォールバック（次サイクルで対応） |
| polling 中に restartApp が二重発火 | 別プロセス起動が複数 | `pollingTask?.cancel()` + `isPolling = false` を `onGranted` 呼ぶ前にセットすることで物理防止 |
| Task.sleep が cancel されないまま残る | リーク | `Task.isCancelled` チェック + try? await でクリーン終了 |
| アラート表示中に scenePhase 切替で refreshPermissionStatus が呼ばれて hasPermission が変動 | UI 不整合 | 既存挙動維持（AXIsProcessTrusted キャッシュにより実質変動しない） |

---

## 4. 想定サイクル数
**1サイクル**: Task 1 + Task 2 を一気に実装 → ビルド → 実機検証

破綻したら 2サイクル目で NSAlert フォールバック検討。
