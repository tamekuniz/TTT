# todo: BonsaiManager.isLocalModelAvailable パス検出ズレ修正（案B 採用）

## 採用案サマリー

**案B（modelsBaseDirectory を `~/.typetotalk` に変更し、Downloader と isLocalModelAvailable の双方で明示的に `models/` 層を append）を採用。**

検証結果（プランナー判定）:
- 既存ファイル `~/.typetotalk/models/models/prism-ml/Ternary-Bonsai-8B-mlx-2bit/` (2.3GB) は **完全に流用可能**
- 案B 後の HubApi 実保存パス = `~/.typetotalk/models` + `/models/` + `<repo.id>` = `~/.typetotalk/models/models/<repo.id>`（既存と完全一致）
- 案B 後の isLocalModelAvailable 検査パス = `~/.typetotalk` + `/models/` + `<repo.id>` = `~/.typetotalk/models/<repo.id>` ← **要注意**: investigation.md §5 案B コード（line 329-334）では `modelsBaseDirectory.appendingPathComponent("models").appendingPathComponent(modelID)` となっており、modelsBaseDirectory = `~/.typetotalk` なので `~/.typetotalk/models/<repo.id>` を検査することになる。これだと既存ファイル（`~/.typetotalk/models/models/<repo.id>`）と**不一致**になる
- **investigation.md §5 案B のコード例にバグあり**: isLocalModelAvailable は `models/` を **2 段** append しないと既存ファイルと一致しない（`~/.typetotalk` → `models/models/<repo.id>`）
- このため T2 で投資gation 修正と実装を兼ねた精緻な実装を行う

投資gation 修正必要箇所:
- §5 案B の isLocalModelAvailable 例（line 329-334）: `appendingPathComponent("models")` だけでは不足。HubApi の `<downloadBase>/models/<repo.id>` を再現するには、Downloader に渡す downloadBase（`~/.typetotalk/models`）に対して HubApi が `models/` を追加するため、isLocalModelAvailable も同じ計算（downloadBase + `/models/` + id）が必要 → **`modelsBaseDirectory.appendingPathComponent("models").appendingPathComponent("models").appendingPathComponent(modelID)`** が正解。または、命名を整理して `modelsBaseDirectory` を `~/.typetotalk/models`（= Downloader に渡す downloadBase）に保持し、isLocalModelAvailable で `models/` を 1 段だけ append する案A 寄りの形にする方がシンプル。

→ **再考**: 修正案を以下に変更
- `modelsBaseDirectory` の意味を「HuggingFaceHubDownloader に渡す downloadBase（= `~/.typetotalk/models`）」のままにする（命名はやや惜しいが実体は変えない）
- isLocalModelAvailable で `appendingPathComponent("models")` を 1 段だけ追加（HubApi の自動付加分を補う）
- これは実質「案A」になる。ただし **案A はコメントで「なぜ models/ を足すか」を明記**することで保守性を担保する

→ **最終決定: 案A を採用（コメントで HubApi 内部仕様への依存を明示）**。理由:
1. 案B は既存ファイルとの不一致リスクがあり、investigation.md §5 のコード例も誤り
2. 案A は最小変更で確実。コメントで仕様を明文化すれば保守性も担保できる
3. 案B の「命名美化」メリットは、`models/` が 2 段になる不格好さで打ち消される

---

## タスク一覧

- [ ] T1: BonsaiManager.isLocalModelAvailable に HubApi の repoType 層（`models/`）を追加
    - 対象: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/BonsaiManager.swift` line 147-164
    - 期待挙動: `modelsBaseDirectory.appendingPathComponent("models").appendingPathComponent(modelID)` で検査
    - 実装メモ: `appendingPathComponent("models")` の直前に `// HubApi が downloadBase 配下に <repoType>/<repoID> を作るため、repoType="models" を補う` のコメントを必ず付ける（保守性担保）
    - ログにも実検査パスが出るので debug ログはそのまま流用

- [ ] T2: 修正後の検査パスと HubApi 実保存パスの整合性を再確認（コードリーディング）
    - 対象: `BonsaiManager.swift` (修正後) と `.build/checkouts/swift-transformers/Sources/Hub/HubApi.swift` line 378-380
    - 期待挙動: `localRepoLocation` = `downloadBase(=~/.typetotalk/models) + /models/ + <repo.id>` = `~/.typetotalk/models/models/<repo.id>`、isLocalModelAvailable も同パスを検査
    - 確認方法: 修正後コードを Read して `.path` を脳内評価。既存実ファイル `~/.typetotalk/models/models/prism-ml/Ternary-Bonsai-8B-mlx-2bit/` と一致することを確認

- [ ] T3: ビルド確認（コンパイルエラー / 警告ゼロ）
    - 対象: TTT プロジェクト全体
    - 期待挙動: `xcodebuild -scheme TypeToTalk -configuration Debug build` が成功
    - 備考: フォK Step 5（Build/Test）で実施

- [ ] T4: 実機デプロイと自動ロード確認（Mac 実機 + シミュレータ両方）
    - 対象: TypeToTalk アプリ
    - 期待挙動:
        1. アプリ起動時に Bonsai モデルが自動ロードされる
        2. ログ `isLocalModelAvailable: path=.../.typetotalk/models/models/prism-ml/Ternary-Bonsai-8B-mlx-2bit ... visible>0` が出る
        3. ログ `ensureSelectedModelLoaded: load success` が出る
        4. Formatter ステータスが「準備完了」表示
    - 備考: フォK の dual deploy ルール（feedback_fok_dual_deploy）に従い、実機とシミュ両方に install。ログ確認は `log stream --predicate 'subsystem == "com.tamekuniz.TypeToTalk"' --level debug`

- [ ] T5: 既存 2.3GB ファイル流用の確認（再ダウンロードが走らないこと）
    - 対象: `~/.typetotalk/models/models/prism-ml/Ternary-Bonsai-8B-mlx-2bit/`
    - 期待挙動: 修正版起動後、当該ディレクトリのタイムスタンプ・サイズが変わらない（ネットワーク I/O なしで自動ロード成功）
    - 確認方法: `ls -la ~/.typetotalk/models/models/prism-ml/Ternary-Bonsai-8B-mlx-2bit/model.safetensors` を起動前後で比較
