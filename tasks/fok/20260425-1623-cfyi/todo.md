# todo: マイクボタン UI 改善（アイコン統一＋色変更）

## 概要

`Sources/TypeToTalk/App/TypeToTalkApp.swift` の 2 行レベル変更。
- 録音中もアイコンを `mic.fill` のまま維持（`stop.fill` 切替を撤廃）
- 録音中の色を `.red` から濃い青 RGB(0.05, 0.35, 0.80) に変更

変更は 2 箇所のみで、互いに密接に関連する単一の UI 変更のため **1 タスクにまとめる**。

---

## タスク

### Task 1: マイクボタンのアイコン統一＋録音中の色を濃い青に変更

**ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`

**変更箇所 1: アイコン分岐の撤廃（L60 周辺）**

Before:
```swift
Image(systemName: coordinator.recorder.isRecording ? "stop.fill" : "mic.fill")
    .font(.system(size: 30, weight: .semibold))
    .foregroundStyle(.white)
```

After:
```swift
Image(systemName: "mic.fill")
    .font(.system(size: 30, weight: .semibold))
    .foregroundStyle(.white)
```

**変更箇所 2: micButtonColor の録音中分岐（L113-123）**

Before:
```swift
private var micButtonColor: Color {
    if coordinator.recorder.isRecording {
        return .red
    }
    if coordinator.whisper.whisperKit != nil {
        return Color(red: 0.10, green: 0.47, blue: 0.95)
    }
    return Color(red: 0.45, green: 0.83, blue: 0.98)
}
```

After:
```swift
private var micButtonColor: Color {
    if coordinator.recorder.isRecording {
        return Color(red: 0.05, green: 0.35, blue: 0.80)
    }
    if coordinator.whisper.whisperKit != nil {
        return Color(red: 0.10, green: 0.47, blue: 0.95)
    }
    return Color(red: 0.45, green: 0.83, blue: 0.98)
}
```

**触らない箇所（重要）**:
- L42-58: ZStack / Circle / scaleEffect / opacity の修飾子 → そのまま
- L52-53: パルスアニメーション条件 `coordinator.recorder.isRecording && isPulsing` → そのまま
- L70-80: `onChange(of: coordinator.recorder.isRecording)` のパルス制御ロジック → そのまま
- L69: `.help("録音開始 / 停止")` → そのまま
- isProcessing の ProgressView 表示 → そのまま

---

## 検証ポイント

ビルド成功 + 実機確認で以下を確認:

1. **アプリ起動時（待機・未ロード）**: マイクアイコン `mic.fill` ＋ 水色 RGB(0.45, 0.83, 0.98)
2. **モデルロード後（待機・準備完了）**: マイクアイコン `mic.fill` ＋ 鮮やかな青 RGB(0.10, 0.47, 0.95)
3. **クリック後（録音中）**:
   - アイコンは **`mic.fill` のまま**（`stop.fill` に変わらない ← 主目的）
   - 色は濃い青 RGB(0.05, 0.35, 0.80)
   - パルスアニメーション継続（scale 1.08 / opacity 0.85 / 0.8 秒往復）
4. **再クリック（停止）**: 色が鮮やかな青に戻る、アイコンは変化なし、パルス停止（0.2 秒で滑らかに）
5. **文字起こし中（isProcessing）**: ProgressView 表示は従来通り

---

## スコープ外

以下は今回の変更には**含めない**（明確に対象外）:

- アイコンの種類変更（`mic.fill` 以外への切替）
- パルスアニメーション仕様変更（scaleEffect / opacity / duration / repeatForever はそのまま）
- 色定義の Color extension 化（マジックナンバー直書きは現状パターン維持）
- accessibilityLabel / accessibilityHint の追加（投資対効果が小さい、別件）
- 録音停止操作の方法変更（再クリックで停止する仕様は維持）
- 録音中の音量レベル可視化（波形・レベルメーター追加）
- 触覚/視覚フィードバック（録音開始/停止時のハプティクス）の変更
- RGB 値の Color extension 一元管理（将来の拡張案、今回はやらない）

---

## 参考

- 要件: `/Users/tamekuniz/GitHub/tamekuniz/TTT/tasks/fok/20260425-1623-cfyi/requirements.md`
- 調査: `/Users/tamekuniz/GitHub/tamekuniz/TTT/tasks/fok/20260425-1623-cfyi/investigation.md`
