# 要件: Whisper / Bonsai モデルの自動ダウンロード停止

## 背景

ズンジーは外出先で Wi-Fi が無い場合がある。現在の TypeToTalk は起動時と録音開始時に Whisper / Bonsai のモデルを自動でロードしようとし、未ダウンロードならネット越しにダウンロードを開始する。Wi-Fi 無し or モバイル従量課金のシナリオで意図せずダウンロードが走る／失敗するのを防ぎたい。

## ゴール

「未ダウンロードなら何もしない、ダウンロード済みなら自動ロードする」挙動に変える。

具体的に:

- アプリ起動時の自動ロード（`handleAppLaunch` → `synchronizeModelsForCurrentSettings`）
  - **モデルがローカルにダウンロード済み** → 従来通り自動ロード（オフラインでもすぐ使える）
  - **未ダウンロード** → ロード処理を呼ばない（=ネット通信させない）
- 録音開始時の自動ロード（`toggleRecording` の else 分岐）
  - 同上の挙動
- 設定画面の「読み込み」ボタン（`loadSelectedModel`）
  - 従来通り、明示操作のときのみダウンロードを実行する

## 非ゴール

- ダウンロード進捗 UI の刷新
- オフライン検出（reachability）の実装
- ダウンロード済みモデルのバージョン整合チェック

## 影響範囲（Step 3 で精査）

- `Sources/TypeToTalk/Managers/WhisperManager.swift`
  - `ensureSelectedModelLoaded()` / `setupWhisper(forceReload:)` / `WhisperKit.download(variant:)`
- `Sources/TypeToTalk/Managers/BonsaiManager.swift`
  - `ensureSelectedModelLoaded(modelID:)` / `loadModel(modelID:)` / `HuggingFaceHubDownloader.download`
- `Sources/TypeToTalk/App/TypeToTalkApp.swift`
  - `handleAppLaunch()` / `synchronizeModelsForCurrentSettings()` / `toggleRecording()`

## 受け入れ条件

1. ダウンロード済みモデルがある状態でアプリを起動 → 従来通りモデルがロードされる
2. 未ダウンロード状態でアプリを起動（オフライン） → ネット通信しない、状態は「未読込」のまま、エラーも出さない
3. 「読み込み」ボタンを明示的に押した時のみダウンロードが始まる
4. 録音開始時にも同様の挙動（未 DL なら何もせず、ロード済みなら録音、未ロードなら従来のエラーメッセージ）
