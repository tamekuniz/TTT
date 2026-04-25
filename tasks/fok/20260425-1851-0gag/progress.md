# Progress — TypeToTalk メインウインドウ標準タイトルバー化

タスク管理: tasks/fok/20260425-1851-0gag/todo.md
調査レポート: tasks/fok/20260425-1851-0gag/investigation.md

---

## T1: メインウインドウのタイトルバー表示を Mac 標準化し、独自 Text("TypeToTalk") を削除する

状態: 完了

メモ:
- 対象は `Sources/TypeToTalk/App/TypeToTalkApp.swift` の 1 ファイルのみ。
- 削除対象: `Text("TypeToTalk")` (L18 付近), `.windowStyle(.hiddenTitleBar)` (L535), `window.titleVisibility = .hidden` (L513), `window.titlebarAppearsTransparent = true` (L514), `window.isMovableByWindowBackground = true` (L515 付近)。
- 追加: `window.title = "TypeToTalk"`。
- 維持: `window.identifier`, `.windowResizability(.contentSize)`, `NSApplication.shared.setActivationPolicy(.regular)`, `coordinator.handleAppLaunch()`。

実装結果（2026-04-25）:
- 編集1（HStack 内 VStack）: `Text("TypeToTalk")` と `.font(.title3.weight(.semibold))` を削除。statusMessage 表示用 if ブロックは維持。
- 編集2（.onAppear NSWindow 設定）: `titleVisibility = .hidden` / `titlebarAppearsTransparent = true` / `isMovableByWindowBackground = true` を削除し、`window.title = "TypeToTalk"` を追加。`identifier = "RecorderWindow"` は維持。
- 編集3（WindowGroup 修飾子）: `.windowStyle(.hiddenTitleBar)` を削除。`.windowResizability(.contentSize)` は維持。
- 検証: `xcodebuild ... build` で BUILD SUCCEEDED 確認済み。
- 実機確認: ズンジー側で起動して、タイトルバー中央に "TypeToTalk" が標準表示されることを目視確認予定。
