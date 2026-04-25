# フォK Phase 1: 進捗ログ

**ID**: 20260425-2234-kl4z
**目的**: TypeToTalk メニューバー常駐型（accessory）への移行（Phase 1: 骨組み）

---

## ステータス

- [x] Step 1: 受付（要件確認）
- [x] Step 2: 命名（task ID 採番）
- [x] Step 3: 調査（investigation.md, by マンゴーどす）
- [x] Step 4: 計画（todo.md, by あけびじゃっど）
- [x] Step 6: 実装（みかん博多、TypeToTalkApp.swift 589→446 行）
- [x] Step 7: 検証（ぶどう博多、xcodebuild BUILD SUCCEEDED、grep 全項目 0件 / accessory 1件）
- [x] Step 8: ビルド番号 20260425G 更新、再ビルド・起動済み
- 実機シナリオ確認: ズンジー側で目視（下記）

---

## Phase 分割の決定

要件「メニューバー常駐型へ全面移行」を 2 Phase に分けた。

### 理由
- accessory 化 + MenuBarExtra 導入 + メインウインドウ廃止だけで影響範囲が大きい
- アイコン状態反映や popover UI まで一気にやると Step 6 自己検証が肥大化
- フォK の「1 サイクル = 1 まとまった改善」原則に合わせ、Phase 1 = 骨組み、Phase 2 = UI 詳細化、と切る

### Phase 1 のスコープ（本サイクル）
1. accessory ポリシー化（init で setActivationPolicy）
2. MenuBarExtra 導入（最小実装：固定アイコン + 設定/終了メニュー）
3. メインウインドウ（WindowGroup + TypeToTalkMainView）廃止
4. NSApp.activate() 全削除
5. showRecorderWindow() メソッドと呼び出し削除
6. Settings シーンは保持

### Phase 2 のスコープ（次サイクル起票予定）
1. アイコン状態の動的反映
2. popover ベース UI
3. エラーハンドリング表示
4. アクセシビリティ権限未許可時のメニューバー誘導

---

## 重要な設計判断

### A. SettingsLink を採用
`Selector(("showSettingsWindow:"))` の文字列セレクタは fragile。macOS 14+ で利用可能な `SettingsLink` をメニュー項目に使う方が SwiftUI ネイティブで安全。

### B. accessory ポリシーは `TypeToTalkApp.init()` で設定
MenuBarExtra だけでは accessory にならない（デフォルトは regular）。アプリ起動時に確実に accessory にするため、`init()` 内で `NSApplication.shared.setActivationPolicy(.accessory)` を呼ぶ。

### C. handleAppLaunch() は MenuBarLabel の onAppear で起動
旧 WindowGroup の onAppear が消えるため、新たな起動トリガが必要。MenuBarLabel という小さな View ラッパーを作り、その onAppear で一度だけ handleAppLaunch を呼ぶ（`@State` フラグで二重起動防止）。

### D. AppStatus enum を追加（Phase 1 では未使用、Phase 2 への布石）
Coordinator に `enum AppStatus { idle / recording / processing / error(String) }` と `@Published var currentStatus` を追加し、状態遷移時に更新する。Phase 1 では MenuBarExtra label が固定アイコンのため見た目には反映されないが、Phase 2 で動的切替の準備となる。

---

## 実装順序の推奨（Step 5 で実装小人ちゃんへ）

1. AppStatus enum と @Published currentStatus を Coordinator に追加
2. 既存メソッド（toggleRecording, handleAppLaunch 等）に currentStatus 更新コードを差し込む
3. TypeToTalkApp の Scene を差し替え（WindowGroup → MenuBarExtra）
4. TypeToTalkApp.init() で setActivationPolicy(.accessory) を設定
5. MenuBarLabel View を新設（onAppear で handleAppLaunch 起動）
6. showRecorderWindow() メソッドと呼び出し 2 箇所を削除
7. TypeToTalkMainView を削除（参照消失を確認後）
8. ビルド → grep 検証

---

## 次の小人ちゃんへの引き継ぎ

- **Step 5 実装小人ちゃんへ**: todo.md の「実装順序の推奨」に沿って進めて。各 Task は独立しているように見えるが、Scene 差し替えで TypeToTalkMainView 参照が切れる順序があるので順番厳守。
- **Step 6 自己検証小人ちゃんへ**: todo.md Task 4 の grep コマンド 3 本を必ず実行。0 件確認できなければ実装漏れ。
- **Step 7 デプロイ後**: ズンジーに実機（とシミュ両方）で確認依頼する前に、Dock 非表示 + メニューバー表示の最低 2 点はシア自身で確認可能なら確認。

---

## ログ

- 2026-04-25 23:50 JST: あけびじゃっどが計画策定完了、todo.md 生成。Phase 分割を採用。
