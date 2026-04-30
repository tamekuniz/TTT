# TypeToTalk 🎙️⌨️

**TypeToTalk** は、Mac のキーボードを叩く代わりに「声」でタイピングするための、プロフェッショナル向け音声入力アシスタントです。

既存のツールへの最大の不満点である**「クリップボード履歴の上書き」を完全に解消**し、M1 Pro などの Apple Silicon の性能を極限まで引き出す設計になっています。

## ✨ 特徴

- **🚫 クリップボードを汚さない**: Accessibility API を使用し、フォーカスのある入力欄にテキストを直接注入。コピー履歴を一切破壊しません。
- **🎙️ 聞き取りエンジン選択**:
  - **WhisperKit (オンデバイス、デフォルト)**: M1 Pro / Apple Silicon 最適化、ネット不要、完全ローカル。
  - **ElevenLabs Scribe v2 (クラウド)**: 99言語対応、ノイズ耐性が高い。録音音声を ElevenLabs サーバーへ送信。
- **🧠 ハイブリッド AI 成形**:
  - **オンライン (Groq / OpenAI)**: 利用したい整形 AI を設定画面から選択可能。
  - **オフライン (Bonsai)**: 今週リリースの最新 **1-bit LLM (Bonsai 8B)** を採用。ネットがなくてもローカルで賢く整形。
- **⌨️ グローバルショートカット**: `Cmd + Option + V`（デフォルト）で、どのアプリからでも即座に録音開始。
- **🔒 プライバシー第一**: WhisperKit 選択時は音声解析が完全に手元の Mac で完結。外部 API を使う場合（Groq / OpenAI / Scribe）は、それぞれの API へ送信するデータが異なるため後述「プライバシー注記」を確認してください。

## 🛠️ 技術スタック

- **Language**: Swift 6 (Concurrency-safe)
- **UI**: SwiftUI (macOS 14.0+)
- **Audio Engine**: WhisperKit / ElevenLabs Scribe v2 (Batch API)
- **Formatter**: Groq / OpenAI / Bonsai fallback
- **Direct Input**: Apple Accessibility API (AXUIElement)

## 🚀 セットアップ

### 1. 権限の設定
アプリをビルドして実行後、以下のシステム権限を許可してください：
- **マイク**: 音声を録音するために必要です。
- **アクセシビリティ**: 他のアプリの入力欄に文字を直接書き込むために必要です。

### 2. API キーの設定 (オプション)
設定画面から整形 AI を選び、必要な API キーを入力してください。Groq / OpenAI のどちらも利用できます。

### 3. 聞き取りエンジンの選択
設定画面の「聞き取りAI」から WhisperKit (ローカル) / ElevenLabs Scribe (クラウド) を選択できます。
- **WhisperKit**: デフォルト。完全ローカル、ネット不要。
- **ElevenLabs Scribe**: クラウド送信が発生。API キーは設定画面の「APIキー」欄から入力します。API キーは [ElevenLabs API Keys](https://elevenlabs.io/app/settings/api-keys) で取得できます。

### 4. ローカルモデルの配置
Bonsai によるオフライン成形を利用する場合、モデルファイルを `~/.typetotalk/models/bonsai-8b-1bit` に配置してください。

### 5. `.app` のビルド
XcodeGen で macOS アプリの project を生成し、`Info.plist` を反映した `.app` をビルドできます。

```bash
./scripts/build_app.sh
```

Release ビルド:

```bash
./scripts/build_app.sh Release
```

出力先:

```bash
/tmp/TypeToTalkDerivedData/Build/Products/Debug/TypeToTalk.app
```

## 🔐 プライバシー注記

| 機能 | 送信先 | 送信内容 |
|------|--------|----------|
| WhisperKit (聞き取り) | 送信なし | — (完全ローカル) |
| ElevenLabs Scribe (聞き取り) | api.elevenlabs.io | 録音音声 (multipart/form-data) |
| Groq (整形) | api.groq.com | 文字起こし後テキスト |
| OpenAI (整形) | api.openai.com | 文字起こし後テキスト |
| Bonsai (整形) | 送信なし | — (完全ローカル) |

WhisperKit + Bonsai の組み合わせを選べば外部送信なしで運用できます。クラウド系 (Scribe / Groq / OpenAI) を選択した場合、各サービスのプライバシーポリシーが適用されます。

---
Produced by Gemini CLI for tamekuniz.
Project initiated: 2026-04-19
