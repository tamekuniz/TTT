# 要件: ElevenLabs Scribe を STT エンジン選択肢として並列追加

## Goal

TTT で文字起こしエンジンを **WhisperKit（オンデバイス）** と **ElevenLabs Scribe（クラウド）** から選べる状態にし、ユーザーが用途（精度・プライバシー・多言語対応）に応じて使い分けられるようにする。

## Constraints

1. **WhisperKit を既定エンジンとして残す**。README の「プライバシー第一・音声解析は完全に手元の Mac で完結」を毀損しない。Scribe はあくまで opt-in の追加選択肢。
2. **Scribe は API key opt-in**。API key の保管機構は既存の整形 AI 設定（Groq / OpenAI）と同じ仕組みに揃える（Keychain or 既存 SettingsStore 形式）。
3. **既存の挙動を維持**: クリップボード非汚染 / Accessibility API 経由のテキスト注入 / グローバルショートカット（Cmd+Opt+V）/ ハイブリッド整形 AI（Groq/OpenAI/Bonsai）。
4. **Swift 6 Concurrency-safe / macOS 14.0+** 維持（@MainActor / actor / Sendable 規律を守る）。
5. **Scribe API 利用時の通信内容は音声データのみ**。整形後テキストの送信ルートは既存の整形 AI 設定に従う（Scribe→Groq へのチェーンも従来通り動く）。
6. **Scribe API モードは Batch を採用**（録音終了後にまとめて POST）。Realtime（WebSocket ストリーミング）は今回スコープ外。

## Acceptance criteria

1. **設定画面に STT エンジン選択 UI が存在し永続化される**: WhisperKit / Scribe を選べるセグメントまたはピッカーがあり、再起動後も選択が維持される。
2. **Scribe 選択時に API key 入力欄があり、保存後にエンジンとして機能する**: API key 未設定で Scribe を選んだ場合は分かりやすいエラー or 警告を提示。
3. **Scribe 選択で end-to-end フローが動く**: グローバルショートカット → 録音 → Scribe API へ POST → 文字起こし結果取得 → 整形 AI（または素通し）→ Accessibility 経由で注入、までを実機確認できる。
4. **WhisperKit 選択のまま従来通り動作する（リグレッションなし）**: 既存の WhisperKit パスが影響を受けない。
5. **README に Scribe 設定手順 + プライバシー注記が追記される**: Scribe 選択時はクラウド送信が発生する旨を明記、API key 取得方法へのリンクを追加。

## スコープ外（今回やらないこと）

- Scribe Realtime（ストリーミング）対応 — 後続フォーメーションで検討
- Scribe 以外のクラウド STT（Whisper API / Google STT 等）
- 設定画面の全面リデザイン（最小限の追加・統合に留める）
- WhisperKit のモデル選択 UI 改修（既存仕様のまま）
