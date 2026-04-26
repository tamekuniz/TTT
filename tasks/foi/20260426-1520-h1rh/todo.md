# todo: .foi-target 整備 + ビルドナンバー bump

- [ ] T1: `.foi-target` 新規作成 + `project.yml` の CURRENT_PROJECT_VERSION を `20260426F` に bump
    - 対象ファイル:
        - `.foi-target` （新規、プロジェクトルート直下）
        - `project.yml:13`
    - 期待挙動:
        - `.foi-target` が source 可能で、VERSION_FILE_1_PATH/KEY 等のスキーマを持つ
        - `project.yml:13` が `CURRENT_PROJECT_VERSION: "20260426F"` になる
        - 既存の generate_build_number.sh と Xcode 自動採番には影響なし
    - 備考:
        - スキーマは investigation.md §6 と AC1 を参照
        - bump 値の妥当性は Step 7 で `grep` 確認、ビルドは Step 8 でズンジー依頼
