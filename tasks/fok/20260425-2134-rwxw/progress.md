# progress: BonsaiManager.isLocalModelAvailable パス検出ズレ修正

## 採用案
**案A（isLocalModelAvailable で `models/` を 1 段追加 + 仕様コメント明記）**

プランナー判定により investigation.md の推奨案 B から **案A に変更**。

理由:
- investigation.md §5 案B のコード例 (line 329-334) は isLocalModelAvailable で `models/` を 1 段しか append しないため、modelsBaseDirectory を `~/.typetotalk` に変えると検査パスが `~/.typetotalk/models/<id>` となり、既存ファイル `~/.typetotalk/models/models/<id>` と**不一致**になる
- 案B を正しく実装するには `models/` を 2 段 append する必要があり、命名美化メリットが消える
- 案A は最小変更で確実。HubApi 内部仕様への依存をコメントで明示すれば保守性も担保できる
- 既存 2.3GB ファイルは案A で完全流用可能（再ダウンロード不要）

## T1: BonsaiManager.isLocalModelAvailable に HubApi の repoType 層（`models/`）を追加
状態: 完了
- BonsaiManager.swift:148-151 に修正適用
- `let modelDir = modelsBaseDirectory.appendingPathComponent("models").appendingPathComponent(modelID)`
- 直上に HubApi 仕様コメント3行（localRepoLocation の構造、RepoType.models = "models"、なぜ `models/` を1段挟むか）

## T2: 修正後の検査パスと HubApi 実保存パスの整合性を再確認
状態: 完了
- 検査パス: `~/.typetotalk/models/models/prism-ml/Ternary-Bonsai-8B-mlx-2bit/`
- HubApi 実保存パス: `~/.typetotalk/models/models/prism-ml/Ternary-Bonsai-8B-mlx-2bit/`
- 完全一致確認

## T3: ビルド確認
状態: 完了
- xcodebuild BUILD SUCCEEDED、警告ゼロ

## T4: 実機自動ロード確認
状態: 部分完了（ズンジー目視待ち）
- Mac アプリのため シミュレータ概念は無し。実機 = ローカル Mac で起動済み
- 起動後、Bonsai ステータスが両画面で「準備完了」になるかをズンジーが目視
- log show は subsystem 絞りで 0件（ad-hoc 署名問題は別件、修正検証には影響なし）

## T5: 既存 2.3GB ファイル流用の確認
状態: 完了
- `~/.typetotalk/models/models/prism-ml/Ternary-Bonsai-8B-mlx-2bit/` に model.safetensors 2.3GB を含む全ファイルが存在することを確認済み
- 修正後の検査パスは上記と一致するため再ダウンロード不要

## ビルド番号
- CURRENT_PROJECT_VERSION: 20260425D → 20260425E に更新
