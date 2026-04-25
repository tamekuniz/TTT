# 要件: 録音終了後のマイクボタンパルス停止

## 背景

ズンジー: 「入力が終わったら伸び縮みも終わってほしい」「録音が終わったらアイコンの伸び縮みは終わってほしい」

現状の挙動（不具合）:
- 録音中はマイクボタンが scale 1.0↔1.08 / opacity 1.0↔0.85 でパルス（前フォK で色も濃い青に変更済み）
- 録音終了（isRecording=false）後も、パルスアニメーションが完全には止まらない
- onChange で `isPulsing = false` にしているが、`repeatForever` で開始した implicit animation は値変更だけでは停止しない SwiftUI の既知挙動

## ゴール

録音終了から **0.2 秒以内** に scale=1.0 / opacity=1.0 に戻り、以後は完全に静止する。

## 非ゴール

- 録音中のパルス挙動の見た目変更（要件は「停止」のみ、開始時の見え方は維持）
- マイクボタンの色変更（前フォK で対応済）
- アイコンの種類変更
- ProgressView 周りの変更
- 触覚フィードバックの変更

## 影響範囲（Step 3 で精査）

- `Sources/TypeToTalk/App/TypeToTalkApp.swift`
  - `isPulsing` State（@State 変数）
  - L42-66 マイクボタン本体（`.scaleEffect(...)` / `.opacity(...)` のトリガー条件）
  - L70-80 `.onChange(of: coordinator.recorder.isRecording)`（パルス開始/停止ロジック）

## 受け入れ条件

1. 録音開始（isRecording=true）でパルス開始（scale 1.08 / opacity 0.85 で 0.8 秒往復、繰り返し）
2. 録音終了（isRecording=false）で 0.2 秒以内に scale=1.0 / opacity=1.0 に戻る
3. 戻った後、それ以上パルス動作が見えない（完全静止）
4. 連続で録音開始/停止を繰り返してもパルスが残らない
5. ビルド成功 / swift test 16 件 PASS（リグレッションなし）

## 既知の SwiftUI 解決パターン（Step 3 で詳細調査）

候補:
- A. `withAnimation(nil) { isPulsing = false }` でアニメーション無しの即時値変更
- B. `.animation(value:)` ベースに切り替えて、`isPulsing` の値で SwiftUI 自身に制御させる
- C. 内部で `Bool` ではなく `Double` の scale/opacity を State で持ち、recording=false 時に明示的に 1.0 を再設定
- D. `repeatForever(autoreverses:)` の代わりに、`.delay() + onChange` で手動ループ

どれが最適かは Step 3 の小人ちゃんが調査して提案する。
