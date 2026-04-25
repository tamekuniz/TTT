# TODO — TypeToTalk メインウインドウ標準タイトルバー化

対象要件: macOS の SwiftUI アプリ TypeToTalk のメインウインドウタイトル "TypeToTalk" を、Mac 標準のウインドウタイトルバーに表示する。ZStack 内の独自 Text("TypeToTalk") を削除する。

参照: tasks/fok/20260425-1851-0gag/investigation.md

---

- [ ] T1: メインウインドウのタイトルバー表示を Mac 標準化し、独自 Text("TypeToTalk") を削除する
    - 対象ファイル: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`
    - 変更内容:
        1. `TypeToTalkMainView` 内 L18 付近の `Text("TypeToTalk")` を削除（HStack 内 VStack の第一子）。`statusMessage` の表示はそのまま残す。
        2. WindowGroup 末尾の `.windowStyle(.hiddenTitleBar)` を削除（標準タイトルバーを表示させる）。
        3. `.onAppear` ブロック内の `window.titleVisibility = .hidden` と `window.titlebarAppearsTransparent = true` を削除し、代わりに `window.title = "TypeToTalk"` を設定する。
        4. `window.isMovableByWindowBackground = true` は削除する（標準タイトルバーでドラッグ可能になるため、背景ドラッグは不要）。
        5. `window.identifier` の設定は維持する（ショートカット/識別用途のため）。
    - 期待挙動: アプリ起動時、ウインドウ上部に macOS 標準のタイトルバー（信号機ボタン + 中央 "TypeToTalk" タイトル）が表示される。マイクボタン・ステータス表示・SettingsLink などの既存レイアウトは崩れない。
    - 備考:
        - スコープ外: ステータス不整合、ショートカット仕様、権限ボタン、ビルドナンバーは触らない。
        - `.windowResizability(.contentSize)` は維持（リサイズ不可は要件通り）。
        - 検証は `swift build` 成功 + 実機/シミュ起動でタイトルバー表示・既存 UI 健全性を目視確認（フォK Step 7 で実施）。
