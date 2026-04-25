<!--
タスク分割の根拠:
- 要件①(権限)はAccessibilityManager.swift + SettingsView.swift + TypeToTalkApp.swift の3ファイルに跨るが関心事は「権限チェックの動的化と UI 反映」で1つ。
- 要件②(UI 区別)と要件③(触覚/視覚 FB)は両方 TypeToTalkApp.swift を触るが、関心事が「ボタン vs バッジの役割明示」と「録音体験のフィードバック追加」で全く別。
- 干渉低減のため別タスクに分割。1サイクル = 1タスクで完結する粒度に揃えた。
-->

- [ ] T1: アクセシビリティ権限の動的チェック化と UI 反映改善
    - 対象ファイル:
        - `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/AccessibilityManager.swift`
        - `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Views/SettingsView.swift`
        - `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`
    - 期待挙動:
        - `insertText()` の冒頭で必ず `refreshPermissionStatus()` を呼び、キャッシュ短路評価による「権限後付け非反映」を解消する
        - `requestPermission()` (prompt 版) は SettingsView から **明示的にユーザーが押した初回のみ** 呼ばれるよう整理（連打しても不要なプロンプトを抑止）
        - SettingsView に「権限を再チェック」ボタンを追加し、`refreshPermissionStatus()` を非破壊で呼べるようにする
        - アプリがフォアグラウンドに戻った時 (`scenePhase == .active` または `NSApplication.didBecomeActiveNotification`) に自動で `refreshPermissionStatus()` を呼ぶ
        - `showAccessibilityPermissionAlert` 表示時のメッセージから「再チェック」導線を案内する文言に整える
    - 備考:
        - investigation.md 5.1 のリスク表に従い、`requestPermission()` 連打を抑止
        - 再ビルド時の bundle path 無効化はコード側では根本解決不能（PRODUCT_BUNDLE_IDENTIFIER の Xcode 設定領域）。本タスクではコード側でできる動的再チェック化に絞る
        - `@MainActor` は AccessibilityManager に既に付与済みなので追加不要

- [ ] T2: アイコンの「ボタン」と「ステータス表示」の視覚的区別
    - 対象ファイル:
        - `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`
    - 期待挙動:
        - マイクボタン (line 36-51): `.help("録音を開始/停止")` 追加、`.shadow(...)` で押下可能であることを視覚強化、`.contentShape(Circle())` でクリック領域明示
        - 歯車ボタン (SettingsLink, line 28-32): `.help("設定を開く")` 追加、hover 時に視認性が上がるよう `.opacity` を hover 状態で調整 (`.onHover` + `@State`)
        - ステータスバッジ (`statusBadge()`, line 124-139): `.help("現在の状態 (クリック不可)")` 追加、`.allowsHitTesting(false)` で物理的にクリックを無効化、`.accessibilityAddTraits(.isStaticText)` で VoiceOver にも「表示専用」と伝える
        - 視覚的に「ボタンは shadow 付き、バッジは平坦」のメリハリをつける
    - 備考:
        - investigation.md 5.2 に従い、`.buttonStyle(.plain)` の既存パターンは維持
        - hoverEffect は macOS 14+ で利用可だがマウス/トラックパッド両対応のため `.onHover` で代替
        - レイアウト崩れを避けるため shadow は控えめ (radius: 2-3) に

- [ ] T3: 音声入力中の触覚フィードバックと録音中パルスアニメーション
    - 対象ファイル:
        - `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`
    - 期待挙動:
        - 録音開始時 (`toggleRecording` の `else` 分岐, isRecording 遷移後): `NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)` を呼ぶ
        - 録音停止時 (`toggleRecording` の `if isRecording` 分岐): `NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)` を呼ぶ
        - テキスト挿入成功時 (`.success` ケース): `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)` を呼ぶ
        - マイクボタンの Circle に **録音中だけ** パルスアニメーション: `.scaleEffect(isRecording ? pulseScale : 1.0)` + `.animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isRecording)` (`@State private var pulseScale: CGFloat` を 1.0 ↔ 1.08 で振動)
        - 処理中 (`isProcessing == true`) はマイクアイコンを `.opacity(0.6)` に落として「処理中で押下不可」を強調
        - 既存の `NSSound.beep()` (recordTriggerFeedback) は維持（触覚に置き換えではなく追加）
    - 備考:
        - investigation.md 5.3 に従い、Force Touch 非搭載デバイスでは触覚は無視されるが副作用なし
        - `.repeatForever` のアニメーションは isRecording=false で停止することを必ず確認 (GPU 負荷対策)
        - `symbolEffect` は macOS 14 で安定しないため、`.scaleEffect` + `.animation` の組み合わせを採用
