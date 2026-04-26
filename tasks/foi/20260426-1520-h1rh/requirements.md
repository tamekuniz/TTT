# requirements: .foi-target 整備 + ビルドナンバー bump

## Goal

TTT のビルドナンバー更新を仕組み化し、直前の asIs モード追加コミット (5c88970) を実機ビルドで判別可能にする。今後フォI サイクル毎に Step 8 で自動的にバージョン更新が走る体制にする（人間記憶ではなく `.foi-target` で物理担保）。

## Constraints

1. **既存ビルドナンバー書式踏襲**: `YYYYMMDDX`（X=A→B→...→Z→AA の連番アルファベット）。`scripts/generate_build_number.sh` がアルファベット連番ロジックの正本
2. **`.foi-target` スキーマ準拠**: フォI skill SKILL.md の Step 8 節で定義された KEY=VALUE スキーマに従う（VERSION_FILE_1_PATH/KEY、VERSION_FORMAT、VERSION_EXAMPLE、DEPLOY_COMMAND、DEPLOY_TARGET、VERIFY_TYPE）
3. **既存 generate_build_number.sh と並走可能**: Xcode build phase で自動採番が走る既存ロジックには触らない。フォI Step 8 の手動 bump はそれと独立に動く（手動更新値を Xcode が後から上書きしても問題ないが、commit 履歴上は手動値が見える）

## Acceptance criteria

1. プロジェクトルートに `.foi-target` が新規作成され、最低限以下を含む:
   - `VERSION_FILE_1_PATH=project.yml`
   - `VERSION_FILE_1_KEY=CURRENT_PROJECT_VERSION`
   - `VERSION_FORMAT="YYYYMMDD + 連番アルファベット (A→B→...→Z→AA)"`
   - `VERSION_EXAMPLE="20260426A"`
   - `DEPLOY_COMMAND="./scripts/build_app.sh"`
   - `DEPLOY_TARGET="ローカル Mac"`
   - `VERIFY_TYPE="ローカル起動確認"`
2. `project.yml:13` の `CURRENT_PROJECT_VERSION` が `"20260426E"` → `"20260426F"` に更新されている（最新コミット 5c88970 が "20260426E" のまま据え置きなので、その次の F）
3. `git commit` + `git push origin main` 完了。フォI 完了宣言で `20260426F` をチャットに明示出力
