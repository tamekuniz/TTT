# Progress: TypeToTalk UI/UX 改善 3 件

## T1: アクセシビリティ権限の動的チェック化と UI 反映改善

状態: 完了

- AccessibilityManager.insertText() 冒頭で `refreshPermissionStatus()` を必ず呼ぶよう変更（短絡評価排除）
- 新規 `recheckPermissionAndOpenSettingsIfNeeded()` メソッド追加
- TypeToTalkApp に `@Environment(\.scenePhase)` 監視追加、`.active` 復帰時に自動再チェック
- alert 文言にフォアグラウンド復帰時の自動再チェックと再チェックボタン案内を追記
- SettingsView: 状態表示を緑/赤の小丸＋テキストに変更、「システム設定を開く」「権限を再チェック」の2ボタン構成
- 検証: `swift build` ✅ / `swift test` 全16件 PASS

## T2: アイコンの「ボタン」と「ステータス表示」の視覚的区別

状態: 完了

- マイクボタン: `.shadow`/`.contentShape(Circle())`/`.help("録音開始 / 停止")` 追加
- 歯車: 円形薄背景＋`.help("設定を開く")`/`.contentShape(Circle())` 追加
- statusBadge: `.allowsHitTesting(false)` + `.accessibilityAddTraits(.isStaticText)` で表示専用化
- 検証: `swift build` ✅ / `swift test` 全16件 PASS

## T3: 音声入力中の触覚フィードバックと録音中パルスアニメーション

状態: 完了

- Coordinator に `performHapticFeedback(_:)` ヘルパー追加。録音開始(.generic)/停止(.levelChange)/入力成功(.alignment) の3タイミングで呼出
- マイクボタンに録音中パルスアニメーション追加（scaleEffect 1.08, opacity 0.85, repeatForever autoreverses）
- 処理中は ZStack 内で ProgressView 表示（マイクアイコンと切替）
- 既存 NSSound.beep() は維持（触覚は追加であって置き換えではない）
- 検証: `swift build` ✅ / `swift test` 全16件 PASS
- 実機検証ポイント:
  1. マイクボタン押下→録音開始でパルス（拡大縮小）開始
  2. 録音停止で短時間フェード後パルス停止、ProgressView 表示
  3. 入力成功で ProgressView 消えて元に戻る
  4. Force Touch trackpad なら触覚を体感できる（未対応デバイスは無視される）
